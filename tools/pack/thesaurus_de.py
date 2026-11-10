#!/usr/bin/env python3
"""German synonyms by sense, from Wiktionary, OpenThesaurus and OdeNet.

The DE pipeline (pipeline/voc-de, steps 11 and 13b) filled each word's
synonym list by taking every synset that contains the word, in both
thesauri, and pouring them into one flat list. That is how "Preis" came to
list "Egon Schiele Art Center" and "Hund" came to list insults:

* OpenThesaurus hides synsets it has rejected (synset.is_visible = 0);
  13b read them anyway. "Egon Schiele Art Center" is in hidden synset 41007.
* OpenThesaurus marks register per term (umgangssprachlich, gehoben,
  fachsprachlich, derb, vulgär). 13b kept derb and vulgär and wrote the
  level into the word ("Sack (derb)"), so the app showed it.
* A word is in the synset of its insult sense; every other term of that
  synset became a synonym of the animal.
* The OdeNet lookup lowercased the word and then compared it with OdeNet's
  capitalised lemma, so a noun was never removed from its own list.
* Step 11 put all OdeNet senses in one set and cut it to ten in set order,
  which is different on every run.

OdeNet's own definitions cannot place a sense: they are often attached to
the wrong synset (the synset "Idiot, Einfaltspinsel, Tor" of "Esel" carries
the definition of a camel). Wiktionary can. Its synonyms are numbered by
the sense they belong to, and the pack's definitions are Wiktionary's
senses. So a word's synonyms are ranked by sense: Wiktionary's synonyms of
the meaning the pack shows first, then the thesaurus synsets that contain
one of them (the same sense, now placed), then the other meanings, then
what no source places.

OdeNet: CC BY-SA 4.0 (https://github.com/hdaSprachtechnologie/odenet), read
from the wn package's database. OpenThesaurus: LGPL 2.1 / CC BY-SA 4.0
(https://www.openthesaurus.de/about/download), read from its MySQL dump.
Wiktionary: CC BY-SA 4.0, via wiktextract (dataset cstr/de-wiktionary-extracted).
"""
import re
import sqlite3
from collections import defaultdict

# OpenThesaurus term_level ids (term_level table in the dump).
LEVELS = {'2': 'umgangssprachlich', '3': 'derb', '4': 'vulgär',
          '5': 'fachsprachlich', '6': 'gehoben'}
OFFENSIVE = {'derb', 'vulgär'}

ODENET_POS = {'substantiv': ('n',), 'verb': ('v',), 'adjektiv': ('a', 's'),
              'adverb': ('a', 'r', 's')}

TAG = re.compile(r'\s*\(([^()]*)\)\s*$')


def bare(term):
    """'Sack (derb)' -> ('Sack', 'derb'); 'Haus' -> ('Haus', None)."""
    m = TAG.search(term)
    if m:
        return term[:m.start()].strip(), m.group(1).strip()
    return term.strip(), None


# --------------------------------------------------------------- OpenThesaurus

def _rows(line):
    """The value tuples of one MySQL INSERT line, as lists of strings."""
    start = line.find('VALUES (')
    if start < 0:
        return
    i, n = start + 7, len(line)
    while i < n:
        if line[i] != '(':
            i += 1
            continue
        i += 1
        row, cur, quoted = [], [], False
        while i < n:
            c = line[i]
            if quoted:
                if c == '\\' and i + 1 < n:
                    nxt = line[i + 1]
                    cur.append({'0': '\0', 'n': '\n', 't': '\t'}.get(nxt, nxt))
                    i += 2
                    continue
                if c == "'":
                    quoted = False
                else:
                    cur.append(c)
            elif c == "'":
                quoted = True
            elif c == ',':
                row.append(''.join(cur))
                cur = []
            elif c == ')':
                row.append(''.join(cur))
                i += 1
                break
            else:
                cur.append(c)
            i += 1
        yield row


class OpenThesaurus:
    def __init__(self, dump_path):
        self.visible = {}                 # synset id -> bool
        self.terms = defaultdict(list)    # synset id -> [(word, level)]
        self.synsets_of = defaultdict(set)  # word -> synset ids
        with open(dump_path, encoding='utf-8', errors='replace') as f:
            for line in f:
                if line.startswith('INSERT INTO `synset` '):
                    for r in _rows(line):
                        # id, version, evaluation, is_visible, ...
                        self.visible[r[0]] = r[3] not in ('\0', '0', '')
                elif line.startswith('INSERT INTO `term` '):
                    for r in _rows(line):
                        # id, version, language_id, level_id, normalized_word,
                        # original_id, synset_id, user_comment, word, ...
                        level = LEVELS.get(r[3])
                        self.terms[r[6]].append((r[8], level))
                        self.synsets_of[r[8]].add(r[6])

    def senses(self, word):
        """Visible synsets the word is in, in a register a child may meet.

        Returns [(synset id, [(term, level)])] without the word itself.
        """
        out = []
        for sid in sorted(self.synsets_of.get(word, ()), key=int):
            if not self.visible.get(sid, False):
                continue
            own = [lv for w, lv in self.terms[sid] if w == word]
            if own and all(lv in OFFENSIVE for lv in own):
                continue
            out.append((sid, [(w, lv) for w, lv in self.terms[sid]
                              if w.lower() != word.lower()]))
        return out

    def hidden_only(self, word, term):
        """True if word and term share synsets, but only hidden ones."""
        shared = self.synsets_of.get(word, set()) & self.synsets_of.get(term, set())
        return bool(shared) and not any(self.visible.get(s, False) for s in shared)

    def offensive_lower(self, term):
        """offensive() for a lowercased term."""
        if not hasattr(self, '_lower'):
            self._lower = defaultdict(list)
            for w in self.synsets_of:
                self._lower[w.lower()].append(w)
        return any(self.offensive(w) for w in self._lower.get(term, ()))

    def offensive_somewhere(self, term):
        """True if some visible synset files the term as derb or vulgär."""
        return any(lv in OFFENSIVE
                   for sid in self.synsets_of.get(term, ())
                   if self.visible.get(sid, False)
                   for w, lv in self.terms[sid] if w == term)

    def offensive(self, term):
        """True if every visible use of the term is derb or vulgär."""
        levels = [lv for sid in self.synsets_of.get(term, ())
                  if self.visible.get(sid, False)
                  for w, lv in self.terms[sid] if w == term]
        return bool(levels) and all(lv in OFFENSIVE for lv in levels)


# ---------------------------------------------------------------------- OdeNet

class OdeNet:
    def __init__(self, wn_db):
        self.db = sqlite3.connect(f'file:{wn_db}?mode=ro', uri=True)
        self.lex = self.db.execute(
            "SELECT rowid FROM lexicons WHERE id='odenet'").fetchone()[0]

    def senses(self, word, word_type):
        """[(synset id, [lemmas without the word])] in the word's class."""
        pos = ODENET_POS.get(word_type)
        rows = self.db.execute(
            'SELECT DISTINCT ss.rowid, ss.id, ss.pos FROM forms f '
            'JOIN senses s ON s.entry_rowid = f.entry_rowid '
            'JOIN synsets ss ON ss.rowid = s.synset_rowid '
            'WHERE f.form = ? AND f.lexicon_rowid = ? ORDER BY ss.rowid',
            (word, self.lex)).fetchall()
        out = []
        for rowid, sid, p in rows:
            if pos and p not in pos:
                continue
            lemmas = [w for (w,) in self.db.execute(
                'SELECT f.form FROM senses s JOIN forms f '
                'ON f.entry_rowid = s.entry_rowid AND f.rank = 0 '
                'WHERE s.synset_rowid = ? ORDER BY s.rowid', (rowid,))
                      if w.lower() != word.lower()]
            out.append((sid, lemmas))
        return out


# ------------------------------------------------------------------ Wiktionary

WIKT_POS = {'substantiv': {'noun'}, 'verb': {'verb'}, 'adjektiv': {'adj'},
            'adverb': {'adv'}}
WIKT_OFFENSIVE = {'vulgar', 'derogatory', 'pejorative', 'offensive', 'slur',
                  'abwertend', 'derb', 'vulgär', 'Schimpfwort', 'beleidigend'}


def sense_numbers(index):
    """'1', '1a', '2, 3', '1–3' -> {1}, {1}, {2, 3}, {1, 2, 3}."""
    out = set()
    for part in re.split(r'[,;\s]+', index or ''):
        m = re.match(r'(\d+)\D*[–-](\d+)', part)
        if m:
            out.update(range(int(m.group(1)), int(m.group(2)) + 1))
            continue
        m = re.match(r'(\d+)', part)
        if m:
            out.add(int(m.group(1)))
    return out


def _tags(item):
    """Tags and raw tags, a raw tag like 'salopp, abwertend' split up."""
    out = set(item.get('tags') or ())
    for raw in item.get('raw_tags') or ():
        out.update(x.strip() for x in raw.split(',') if x.strip())
    return out


class Wiktionary:
    """German entries of the German Wiktionary, for the given words only."""

    def __init__(self, parquet_dir, words):
        import glob
        import pyarrow.parquet as pq
        wanted = set(words)
        self.entries = defaultdict(list)
        for path in sorted(glob.glob(f'{parquet_dir}/**/*.parquet', recursive=True)):
            table = pq.read_table(path, columns=['word', 'pos', 'lang_code',
                                                 'senses', 'synonyms'])
            for row in table.to_pylist():
                if row['lang_code'] != 'de' or row['word'] not in wanted:
                    continue
                senses = [(sense_numbers(s.get('sense_index')), ' '.join(g.split()),
                           _tags(s))
                          for s in row['senses'] or [] for g in s.get('glosses') or []]
                syns = [(s['word'].strip(), sense_numbers(s.get('sense_index')), _tags(s))
                        for s in row['synonyms'] or [] if s.get('word')]
                self.entries[row['word']].append(
                    {'pos': row['pos'], 'senses': senses, 'synonyms': syns})

    def lookup(self, word, word_type):
        entries = self.entries.get(word, [])
        pos = WIKT_POS.get(word_type)
        same = [e for e in entries if not pos or e['pos'] in pos]
        return same or entries


# ------------------------------------------------------------------- the review

def main_sense(definitions, entries):
    """(entry, sense number) of the meaning the pack shows first.

    The pack's definitions are Wiktionary glosses, except one written for
    children, which replaces or precedes the gloss of sense 1. So the first
    definition names the sense if it is a gloss, and otherwise it is sense
    1 of the first entry. Later definitions do not count: for "Hund" the
    next one is the constellation. The entry matters: "Ball" the dance is
    an entry of its own with its own sense 1.
    """
    first = next((' '.join(d.split()) for d in definitions
                  if isinstance(d, str) and d.strip()), None)
    for i, e in enumerate(entries):
        for numbers, gloss, _ in e['senses']:
            if numbers and gloss == first:
                return i, min(numbers)
    return 0, 1


# Best first, by how often three model judges accepted a term of the tier
# as a synonym of the meaning shown (7,321 German words, Nov 2026):
# 0: 49%, 1: 18%, 4: 17%, 6: 14%, 7: 14%, 2: 7%, 5: 7%, 3: 5%.
BIG_SENSE = 25

TIER_ORDER = (0, 1, 4, 6, 7, 2, 5, 3)
WEAK_TIERS = {3, 5}   # dropped from the pack unless a review accepted the term

# Pet names of a cat that are vulgar words for a child (Wiktionary lists
# them under the cat sense without a label), and anatomy Wiktionary gives
# as another sense of "Katze" or "Sack". Not synonyms to show a child.
BLOCKED = {'muschi', 'pussi', 'pussy', 'vulva', 'vagina', 'penis',
           'hoden', 'hodensack', 'skrotum'}
TIERS = {
    0: 'Wiktionary, the meaning shown first',
    1: 'a thesaurus synset holding one of those',
    2: 'Wiktionary, another meaning',
    3: 'a thesaurus synset of another meaning',
    4: 'both thesauri, meaning not placed',
    5: 'one thesaurus, meaning not placed',
    6: 'no source lists it',
    7: 'only a very large synset',
}


def review(word, word_type, definitions, listed, odenet, ot, wikt, common=()):
    """What to do with each term of a word's listed synonyms.

    Returns (drop, ranked): drop is {listed term: reason}; ranked is
    [(term without register label, tier)] best first, tiers as in TIERS.
    Within a tier a term in ``common`` (lowercased frequent words) comes
    before one that is not, then one without a register label.
    """
    entries = wikt.lookup(word, word_type)
    main_entry, main = main_sense(definitions, entries)
    offensive_senses = {n for e in entries for numbers, _, tags in e['senses']
                        if tags & WIKT_OFFENSIVE for n in numbers}

    wikt_tier, wikt_bad, labelled = {}, set(), set()
    for i, e in enumerate(entries):
        for syn, numbers, tags in e['synonyms']:
            k = syn.lower()
            if tags & WIKT_OFFENSIVE or (
                    i == main_entry and numbers and numbers <= offensive_senses):
                wikt_bad.add(k)
                continue
            if tags:
                labelled.add(k)
            main_here = i == main_entry and (main in numbers or (not numbers and main == 1))
            tier = 0 if main_here else 2
            wikt_tier[k] = min(tier, wikt_tier.get(k, 9))
    main_syns = {k for k, t in wikt_tier.items() if t == 0}
    other_syns = {k for k, t in wikt_tier.items() if t == 2}

    synsets = [('odenet', {t.lower() for t in terms}, False)
               for _, terms in odenet.senses(word, word_type)]
    for _, terms in ot.senses(word):
        labelled.update(w.lower() for w, lv in terms if lv)
        lower = {w.lower() for w, lv in terms if lv not in OFFENSIVE}
        bad = sum(1 for w, lv in terms if lv in OFFENSIVE or ot.offensive(w))
        synsets.append(('openthesaurus', lower, bad >= 2 and bad * 4 >= len(terms)))
    # OdeNet keeps no register; its insult sense of "Hund" is found by
    # OpenThesaurus filing a quarter of the terms as derb or vulgär.
    synsets = [(src, terms, insult or (src == 'odenet' and _insult(terms, ot)))
               for src, terms, insult in synsets]

    thes_tier, sources, tainted, clean = {}, defaultdict(set), set(), set()
    in_big = set()
    for source, terms, insult in synsets:
        if insult:
            tainted |= terms
            continue
        clean |= terms
        if len(terms) > BIG_SENSE:
            # A list of 90 pet names is a register, not a meaning.
            in_big |= terms
            continue
        tier = 1 if terms & main_syns else 3 if terms & other_syns else None
        for k in terms:
            sources[k].add(source)
            if tier is not None:
                thes_tier[k] = min(tier, thes_tier.get(k, 9))

    drop, ranked, seen = {}, [], set()
    for term in listed:
        text, tag = bare(term)
        k = text.lower()
        if not text:
            continue
        if tag:
            labelled.add(k)
        if k == word.lower():
            drop[term] = 'self'
        elif text.startswith(('...', '…')) or text.endswith(('...', '…')):
            drop[term] = 'pattern'      # "...freund", a Wiktionary word family
        elif k in BLOCKED:
            drop[term] = 'offensive'
        elif tag in OFFENSIVE or ot.offensive(text) or (
                k in wikt_bad and k not in wikt_tier):
            drop[term] = 'offensive'
        elif ot.offensive_somewhere(text) and not (
                wikt_tier.get(k) == 0 and k not in labelled):
            # "Muschi" is a cat in one synset and vulgar in another; a
            # child sees the word, not the synset.
            drop[term] = 'offensive elsewhere'
        elif k in tainted and k not in clean and k not in wikt_tier:
            drop[term] = 'insult sense'
        elif ot.hidden_only(word, text) and k not in clean and k not in wikt_tier:
            drop[term] = 'hidden synset'
        elif k in seen:
            drop[term] = 'duplicate'
        else:
            seen.add(k)
            tier = min(wikt_tier.get(k, 9), thes_tier.get(k, 9))
            if tier == 9:
                tier = {2: 4, 1: 5}.get(len(sources[k]), 7 if k in in_big else 6)
            ranked.append((TIER_ORDER.index(tier), k not in common, k in labelled,
                           len(ranked), text, tier))
    ranked.sort()
    return drop, [(r[-2], r[-1]) for r in ranked]


def clean_antonyms(word, listed, ot):
    """Antonyms keep no sense numbers to rank by; drop what is plainly wrong."""
    out, drop, seen = [], {}, set()
    for term in listed:
        text, tag = bare(term)
        k = text.lower()
        if not text:
            continue
        if k == word.lower():
            drop[term] = 'self'
        elif k in BLOCKED or tag in OFFENSIVE or ot.offensive_somewhere(text):
            drop[term] = 'offensive'
        elif k in seen:
            drop[term] = 'duplicate'
        else:
            seen.add(k)
            out.append(text)
    return drop, out


def frequent_words(voc_de_dir):
    """Lowercased words of the two frequency lists the DE pipeline uses."""
    import pathlib
    words = set()
    leeds = pathlib.Path(voc_de_dir) / 'leeds_freq.num'      # CC BY, Sharoff
    if leeds.exists():
        for line in leeds.read_text(encoding='utf-8', errors='replace').splitlines():
            parts = line.split()
            if len(parts) >= 3:
                words.add(parts[2].lower())
    buch = pathlib.Path(voc_de_dir) / 'Buchmeier20k.txt'   # CC BY-SA, Wiktionary
    if buch.exists():
        words.update(m.lower() for m in re.findall(r'\[\[(.+?)\]\]', buch.read_text()))
    return words


def _insult(terms, ot):
    bad = sum(1 for w in terms if ot.offensive_lower(w))
    return bad >= 2 and bad * 4 >= len(terms)
