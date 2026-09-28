#!/usr/bin/env python3
"""Fix in the pack what the app has been working around at runtime.

    python3 tools/pack/repair_pack.py <pack.db> [--out repaired.db] [--report]

Three reading passes over the generated questions found the same thing each
time: the app filtering prose it cannot really judge. The packs carry entries
that are not vocabulary — a spelling-error corpus contributes "kacken" with no
gloss and no grade, Wiktionary contributes "passerbys" glossed "plural of
passerby", and a bad word-list import tags "jun", "jul", "html" and "linux" as
Fry sight words. Every game then needs a rule to keep them out of a question.

This marks them once, in the artifact, so the app can read a verdict instead
of guessing from the gloss:

  quality.vocabulary=false   the entry is not a word to ask about
  word_type=proper_noun      the gloss says it names something
  curriculum tags dropped    from entries that are neither

and it recovers entries whose *first* gloss is unusable but whose later senses
are fine, by dropping the leading ones — the app only ever reads the first.

The rules come from lib/core/models/vocabulary_quality.dart, parsed out of it
rather than copied, so the two cannot drift.

Idempotent: only rows whose verdict differs from what they already carry are
rewritten, because the published digest is the pin.
"""
import argparse
import json
import pathlib
import re
import shutil
import sqlite3
import sys
from collections import Counter

QUALITY_DART = pathlib.Path('lib/core/models/vocabulary_quality.dart')


def dart_list(source, name):
    """The string literals of a `const name = <String>[...]` / `{...}` list."""
    match = re.search(
        r'const\s+(?:List<String>\s+)?' + re.escape(name) +
        r'\s*=\s*(?:<String>)?\s*[\[{](.*?)[\]}];', source, re.S)
    if not match:
        sys.exit(f'{QUALITY_DART}: cannot find {name}')
    return [literal for literal in re.findall(r"'([^']*)'", match.group(1))]



ACCUSATIVE_ARTICLES = ('den', 'einen', 'jeden', 'diesen', 'keinen', 'unseren',
                       'meinen', 'deinen', 'seinen', 'ihren', 'euren')
DATIVE_ARTICLES = ('dem', 'einem', 'jedem', 'diesem', 'keinem', 'unserem',
                   'meinem', 'deinem', 'seinem', 'ihrem', 'eurem')


def weak_masculine_forms(db):
    """Nouns the pack declines weakly: Held → Helden, Gedanke → Gedanken.

    German marks these in every case but the nominative, and the packs'
    written examples keep forgetting: "Ich habe einen Gedanke", "den Held und
    Erzähler". The pack's own declension table says what the form should be,
    so nothing here is invented.
    """
    forms = {}
    for word, blob in db.execute(
            "SELECT word, enrichment_json FROM words "
            "WHERE word_type = 'substantiv' AND enrichment_json IS NOT NULL"):
        inflections = json.loads(blob).get('inflections') or []
        oblique = {}
        for inflection in inflections:
            tags = str(inflection.get('tags') or '')
            text = str(inflection.get('form_text') or '')
            if 'singular' not in tags or not text:
                continue
            for case in ('accusative', 'dative'):
                if case in tags and case not in oblique:
                    oblique[case] = text.split()[-1]
        accusative = oblique.get('accusative')
        if not accusative:
            continue
        if accusative.lower() in (f'{word.lower()}n', f'{word.lower()}en'):
            forms[word] = accusative
    return forms


def fix_weak_nouns(sentence, forms, patterns):
    """The sentence with weak nouns given the ending their case requires."""
    fixed = sentence
    for word, pattern in patterns.items():
        fixed = pattern.sub(lambda m: f'{m.group(1)} {forms[word]}', fixed)
    return fixed


def weak_noun_patterns(forms):
    articles = '|'.join(ACCUSATIVE_ARTICLES + DATIVE_ARTICLES)
    return {
        word: re.compile(rf'\b({articles})\s+{re.escape(word)}\b')
        for word in forms
    }


def load_rules():
    # Comments first: an apostrophe in one ("The German pack's grade glosses")
    # breaks the quote pairing, and the parser then reads the ", " between two
    # literals as a literal of its own — which matches every gloss there is.
    source = re.sub(r'//[^\n]*', '', QUALITY_DART.read_text())
    return {
        'name_openings': dart_list(source, 'kNameGlossOpenings'),
        'name_phrases': dart_list(source, 'kNameGlossPhrases'),
        'form_markers': dart_list(source, 'kGrammaticalFormMarkers'),
        'abbreviation_markers': dart_list(source, 'kAbbreviationMarkers'),
        'misspelling_markers': dart_list(source, '_invalidSpellingMarkers'),
        'dangling': dart_list(source, '_danglingWords'),
    }


# Mirrors _geographyGloss in vocabulary_quality.dart. Keep the two together.
GEOGRAPHY_GLOSS = re.compile(
    r'^(hauptstadt|stadt|fluss|insel|gebirge|ozean|provinz|bundesland'
    r'|bundesstaat|kontinent|staat|region|gemeinde|dorf)\s*,?\s*'
    r'(in|im|der|des|von|vom|zwischen|an|auf|nahe|bei|südlich|nördlich'
    r'|östlich|westlich|mit)\b')


def describes_a_name(definition, rules):
    lower = definition.lower()
    # Mirrors the one rule in describesAName that is code rather than a list:
    # a capital and a city in one gloss is a place however it is phrased.
    if 'capital' in lower and 'city' in lower:
        return True
    # And the German pack's "kind of place, then where it is": "Stadt im
    # US-Bundesstaat Pennsylvania", "Staat in Ostasien". The locating word is
    # what keeps "Ausland: Land oder Länder außerhalb ..." out of it.
    if GEOGRAPHY_GLOSS.match(lower):
        return True
    return (any(lower.startswith(opening) for opening in rules['name_openings'])
            or any(phrase in lower for phrase in rules['name_phrases']))


def ends_mid_sentence(definition, rules):
    trimmed = definition.strip()
    if ',.' in trimmed or ' .' in trimmed:
        return True
    if trimmed.endswith(',') or trimmed.endswith(';'):
        return True
    if re.search(r'[.!?]$', trimmed):
        return False
    stripped = re.sub(r'[\s.,;:!?]+$', '', trimmed)
    if not stripped:
        return True
    return stripped.split()[-1].lower() in rules['dangling']


def gloss_verdict(definition, rules):
    """Why this gloss cannot carry a question, or None when it can."""
    trimmed = (definition or '').strip()
    lower = trimmed.lower()
    if len(trimmed) < 4:
        return 'gloss too short'
    if trimmed.endswith(':'):
        return 'gloss is a bare label'
    if ' ' not in trimmed:
        return 'gloss is a single word'
    if any(marker in lower for marker in rules['form_markers']):
        return 'gloss is a grammatical parse'
    if any(marker in lower for marker in rules['abbreviation_markers']):
        return 'gloss is an abbreviation'
    if describes_a_name(trimmed, rules):
        return 'gloss names something'
    if ends_mid_sentence(trimmed, rules):
        return 'gloss stops mid-sentence'
    return None


# Words two unrelated dictionary definitions share anyway. Without them
# "used" and "something" alone make a gloss look like its reader's own.
_GLOSS_STOP_WORDS = frozenset('''
    the and that which are been being for with from its something someone any
    each one two who whom whose not other others such this these those used
    use using especially typically usually often more most very can may having
    have has made make makes also into out off over under was were his her
    their they you she
    der die das ein eine einer eines einem einen und oder von mit auf für als
    dem den des ist sind wird werden sich nicht man etwas jemand jemanden
    jemandem wie durch bei aus zum zur über unter nach dass auch nur sehr beim
    ohne vor wenn
'''.split())

# Crude, and crude on purpose: a real lemmatiser is not available here and the
# only question asked is "does the catalogue contain this word in some form".
# Without it "standing", "relating", "consisting" and "survives" all read as
# words a child has never met, and every second gloss looks too hard.
_SUFFIXES = (('ies', 'y'), ('es', ''), ('s', ''), ('ed', ''), ('ed', 'e'),
             ('ing', ''), ('ing', 'e'), ('ly', ''), ('er', ''), ('er', 'e'),
             ('est', ''), ('est', 'e'), ('ness', ''), ('ment', ''),
             ('en', ''), ('e', ''), ('n', ''))


def graded_surfaces(db):
    """Every spelling the pack grades, lowercased: the catalogue a child of
    this pack is taught, and the only frequency list needed."""
    return {row[0] for row in db.execute(
        'SELECT DISTINCT lower(word) FROM words WHERE grade_level IS NOT NULL')}


def _is_taught(word, vocabulary):
    if word in vocabulary:
        return True
    for suffix, replacement in _SUFFIXES:
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            if word[:-len(suffix)] + replacement in vocabulary:
                return True
    if len(word) > 4 and word[-1] == word[-2] and word[:-1] in vocabulary:
        return True
    return False


# How much of a gloss may be words the pack never teaches, before the gloss
# stops explaining anything. Per language, and that is calibration rather than
# policy: German writes a compound where English writes three words, so
# "Körpertemperatur" and "Pflanzenteile" each count once as unseen where "body
# temperature" and "plant parts" contribute a seen word apiece. The same
# fraction is therefore a stricter test in German, and at 0.5 it took 1,231 of
# 11,806 German glosses -- 10% -- including Frosch, Katze, Finger and Gemüse at
# grade 1, where nothing replaces what it removes: German has no WordNet senses
# to fall back on, so the entry would show no meaning at all.
#
#         English         German
#  > 0.5      98 (0.9%)     1231 (10.4%)
#  > 0.6      41            753  (6.4%)
#  > 0.7      32            465  (3.9%)
#  > 0.8       5             88  (0.7%)
#
# English keeps 0.5, where the cost is 98 glosses and 63 of those have a
# WordNet sense ready. German takes 0.7, which still reaches the glosses that
# are no use to anyone -- "Fach: der durch das Balkengerüst beziehungsweise die
# tragenden Balken begrenzte ...", "Fliege: fliegendes Insekt der Unterordnung
# Fliegen (Brachycera)", "Spiegel: polierte Glas- oder Metallfläche, die
# Lichtstrahlen ..." at grade 1 -- and leaves the ones whose hard gloss is
# still the best there is.
_MOSTLY_UNTAUGHT = {'en': 0.5, 'de': 0.7}


def gloss_is_above_its_reader(definition, vocabulary, language='en'):
    """Whether a gloss is written in words the pack never teaches.

    The pack's own graded catalogue is the frequency list. A content word that
    appears nowhere in 11,539 English or 13,040 German graded spellings is a
    word this reader has not met, and a gloss made mostly of those explains
    nothing however short and plain its grammar is:

        sein     grade 2   Kopula, die dem Subjekt ein logisches Prädikat
                           zuordnet
        among    grade 2   Denotes a mingling or intermixing with distinct or
                           separable objects
        grüßen   grade 2   Worte oder Gebärden als Höflichkeitsgeste beim
                           Zusammentreffen entbieten
        gall     grade 4   Impudence or brazenness; temerity; chutzpah
        nervous  grade 3   Of sinews and tendons.; Full of sinews.

    Over at least four content words, and past the share in _MOSTLY_UNTAUGHT.
    The threshold is high because a gloss is allowed to teach one new word --
    that is what a gloss is for -- and only past it does the sentence stop
    being one the reader can repair from context.

    This is a fault in the gloss, not in the word: "sein", "among" and "ear"
    are words a seven-year-old needs. The entry keeps its place in the
    catalogue and the app stops handing that sentence to a learner -- it does
    *not* promote the next gloss, which changes the sense. Promotion here would
    take "ai" from a three-toed sloth to the branch of computer science, and
    "post" from a plank in the ground to "A stud; a two-by-four".
    """
    if not definition:
        return False
    words = [w for w in re.findall(r'[a-zäöüß]+', definition.lower())
             if len(w) > 2 and w not in _GLOSS_STOP_WORDS]
    if len(words) < 4:
        return False
    unknown = sum(1 for w in words if not _is_taught(w, vocabulary))
    return unknown / len(words) > _MOSTLY_UNTAUGHT[language]


CURRICULUM_TAGS = re.compile(
    r'^source:(dolch|fry|de_curriculum_en|cambridge_yle_.*|uk_y.*)$')

MISSPELLING_TAGS = ('common_misspell', 'often_misspelled')

# The misspelling tags mark the *pair* — "accomodation" carries them and so
# does "add". What separates the mistake from the word is that the word is
# also on a vocabulary list.
# Any independent corroboration that this half of a misspelling pair is the
# word rather than the mistake — a frequency corpus counts here, since a
# corpus that lists "accomodation" also lists "accommodation" far more often
# and only the latter reaches a word list.
VOCABULARY_TAGS = re.compile(
    r'^(source:(fry|dolch|cefr_j|hermit|cambridge_yle_.*|uk_y.*|'
    r'de_curriculum_en)|fry_.*|dolch_.*)$')


def is_attested_vocabulary(metadata):
    """Whether something independent says this entry is a word, not a name.

    A CEFR level, and only that. Levels are assigned to meanings a learner is
    expected to acquire, and no one assigns one to a place: "of", "gay" and
    "mrs" are A1/B1 and lead with a surname or a territory gloss, while
    "london", "texas", "canada" and "ii" have no level at all — though all
    four sit on the Fry list, which is why word lists cannot answer this.
    """
    return bool(metadata.get('cefr_level'))


def names_something(definitions, metadata, rules):
    """Whether the entry is a name rather than a word.

    Either of the first two senses naming something is enough, unless the
    entry carries a CEFR level. See is_attested_vocabulary.
    """
    described = [definition for definition in definitions
                 if isinstance(definition, str) and definition.strip()]
    if not described:
        return False
    if is_attested_vocabulary(metadata):
        return False
    return any(describes_a_name(definition, rules)
               for definition in described[:2])


def row_verdict(word, word_type, definitions, metadata, rules, language):
    """(reasons, names_something) for one row."""
    reasons = []
    not_a_word = NOT_VOCABULARY.get(word) if language == 'en' else None
    if not_a_word:
        reasons.append(not_a_word)
    tags = [str(tag).lower() for tag in metadata.get('tags') or []]
    sources = [str(source).upper() for source in metadata.get('sources') or []]
    if (any(marker in tag for tag in tags for marker in MISSPELLING_TAGS)
            and not any(VOCABULARY_TAGS.match(tag) for tag in tags)):
        reasons.append('tagged a misspelling')
    if any('COMMON_MISSPELL' in source for source in sources):
        reasons.append('sourced as a misspelling')

    described = [
        definition for definition in definitions
        if isinstance(definition, str) and definition.strip()
    ]
    if not described:
        # Not a reason to call it non-vocabulary: a word with no gloss is
        # still a word to spell. It cannot carry a *question*, and the app
        # already knows that from WordFeature.usableDefinition.
        return reasons, word in PROPER_NOUN_HEADWORDS

    names = (names_something(described, metadata, rules)
             or (language == 'en' and word in PROPER_NOUN_HEADWORDS))
    if gloss_belongs_to_another_word(word, word_type, described, metadata,
                                     rules, names, language):
        reasons.append('gloss belongs to another word')
    return reasons, names


def leading_unusable(definitions, rules):
    """How many leading glosses to drop so a usable one leads."""
    dropped = 0
    for definition in definitions:
        if not isinstance(definition, str) or gloss_verdict(definition, rules):
            dropped += 1
        else:
            return dropped
    return 0  # nothing usable anywhere; leave the row alone


# Entries whose headword is simply missing its capital.
#
# Found by spellingIsTrustworthy: an entry whose own glosses and examples
# capitalise it three or more times mid-sentence, without a single exception,
# is not spelled the way the pack spells it. 169 English entries qualified.
# These are the ones that are ordinary vocabulary and only want the capital --
# a child learning "January" or "English" at grade 2 should be able to spell
# it, and until this ran the app excluded all 169 from spelling games rather
# than teach the wrong form.
#
# Written out rather than title-cased, because the acronyms are not title-case
# and because a closed list is the only honest way to say "lowercase is never
# correct here". "august" is deliberately absent: the adjective ("venerable")
# is lowercase, which is also why "march" and "may" never reached the list. So
# are "god", "mommy", "pa", "republican", "soviet" and "escape", where both
# cases are correct English and only the context decides.
def _capitals(*groups):
    out = {}
    for group in groups:
        for word in group.split():
            out[word] = word[0].upper() + word[1:]
    return out


CAPITALISED_HEADWORDS = {
    **_capitals(
        'january february april june july september october november december',
        'monday tuesday wednesday thursday friday saturday sunday',
        'christmas easter halloween olympics olympic olympia',
        # Nationality, language and belief.
        'african buddhist canadian caribbean carthaginian chinese dutch '
        'english european fahrenheit flemish greek hebrew hungarian indian '
        'italian japanese jewish korean linnaean mediterranean palestinian '
        'philippine russian shakespearean sistine spanish yemeni',
        'british brazilian catholicism christian christianity cuban danish '
        'englishman french irish israeli judaism jew moroccan',
        # Continents and countries a geography lesson names.
        'asia europe germany atlantic',
        'mr mrs',
    ),
    # Acronyms, which are not title-case.
    **{word: word.upper() for word in
       'ceo dj dna dvd faq fbi hiv hq uk url usa'.split()},
}

# See the search_index note in main(): a rename that changed more than case
# would leave the shipped full-text index unable to find the row.
assert all(word.lower() == fixed.lower()
           for word, fixed in CAPITALISED_HEADWORDS.items())

# Entries that are names. Kept, so a reading question can still use them, but
# typed proper_noun so they leave spelling, synonym and word-class games.
# describes_a_name does not reach these: it keys on how a gloss opens, and
# "Siddhartha Gautama, the Nepali prince ...", "The fictional vampire in the
# novel ..." and "The strait connecting ..." each open some other way.
PROPER_NOUN_HEADWORDS = frozenset(
    'aborigine amazon bailey barbie beatles benjamin buddha caesar chet '
    'columbia daphne dardanelles diana doris eric franco george gloria hector '
    'henry hulk joanna jonathan joseph judas khan kleenex lapd leo likud '
    'linux lothringen mccarthyist microsoft skagerrak sony yahoo'.split())

# Entries that are not words at all. Marked rather than deleted, which is what
# the pack already does with a misspelling, so the row stays auditable.
NOT_VOCABULARY = {
    **{word: 'misspelling of a capitalised name' for word in
       'brittish conneticut creedence portugese maltesian youtube gya'.split()},
    **{word: 'a symbol, not a word' for word in
       'au aug beng iv ms dr cd-rom'.split()},
    **{word: 'a plural surface of an entry the pack already has' for word in
       'greeks indians zionists saturdays'.split()},
    **{word: 'an obsolete form' for word in 'offred joan'.split()},
    'fritz': 'a slur',
}


# Text that capitalises most of its words is a heading, not a sentence, and
# says nothing about how the word is spelled inside one. Without this,
# "escape" looks like a name: its three capitalised uses are all chapter
# titles -- "The Boys Escape Jim.-Tom Sawyer's ...".
def _is_a_heading(text):
    # The opening word is dropped before counting: a sentence capitalises it
    # too, and in a short sentence that one capital was enough to make "Each
    # January brings snow." look like a heading and be thrown away.
    words = re.findall(r"[A-Za-z][A-Za-z'’-]*", text)[1:]
    words = [w for w in words if len(w) > 2]
    if len(words) < 4:
        return False
    return sum(1 for w in words if w[0].isupper()) / len(words) > 0.4


def evidence_capitalises(word, definitions, metadata):
    """Whether every mid-sentence use of the word in its own evidence is
    capitalised, over at least three uses. Mirrors spellingIsTrustworthy."""
    if not word[:1].isalpha() or word[0] != word[0].lower():
        return False
    texts = [d for d in definitions[:3] if isinstance(d, str)]
    grade_examples = metadata.get('grade_examples')
    if isinstance(grade_examples, dict):
        for sentences in grade_examples.values():
            if isinstance(sentences, list):
                texts += [s for s in sentences[:2] if isinstance(s, str)]
    texts += [s for s in (metadata.get('gutenberg_examples') or [])[:3]
              if isinstance(s, str)]
    pattern = re.compile(r'\b' + re.escape(word) + r'\b', re.IGNORECASE)
    seen = 0
    capitalised = 0
    for text in texts:
        if _is_a_heading(text):
            continue
        for match in pattern.finditer(text):
            before = text[:match.start()].rstrip()
            if not before or before[-1] in '.!?':
                continue          # a sentence start says nothing about case
            seen += 1
            if text[match.start()].isupper():
                capitalised += 1
    return seen >= 3 and capitalised == seen


# Where a CEFR level protects an entry it should not. "august" is A1 as the
# month; the entry glosses the adjective ("Awe-inspiring, majestic, noble,
# venerable") and carries the month's sentences, so the level is evidence for
# a word that is not the one described. Nothing in the row distinguishes the
# two, so it is named here.
GLOSS_MISMATCHES = frozenset({'august'})


def pack_language(db):
    """The language the pack teaches.

    Read from the translations it carries, which name the *other* language:
    the English pack translates into de, the German pack into en.
    """
    row = db.execute('SELECT lang_code, COUNT(*) c FROM translations '
                     'GROUP BY lang_code ORDER BY c DESC LIMIT 1').fetchone()
    into = (row[0] if row else '') or ''
    return 'de' if into.startswith('en') else 'en'


def gloss_belongs_to_another_word(word, word_type, definitions, metadata,
                                  rules, names, language):
    """Whether the gloss and the evidence describe different words.

    Evidence that always capitalises the word says it is a name; a gloss that
    does not describe a name says it is not. Both cannot be about the same
    word, and it is the gloss that loses -- the examples are what a child
    reads. This is how "olympics" came to be glossed "Five consecutive ducks"
    at grade 2, "henry" the unit of inductance at grade 3, and "joanna" a
    piano: a rare homograph of a name, carrying the name's sentences.

    English only. The rule reads a capital as evidence of a name, which holds
    only where nothing else is capitalised. German capitalises every noun and
    every nominalised verb, so "das Reisen" in an example of "reisen" is
    correct German and says nothing at all -- it flagged "aussagen",
    "donnern", "regeln", "reisen" and "freie" before this line existed.
    """
    if language != 'en':
        return False
    if word in CAPITALISED_HEADWORDS or word in NOT_VOCABULARY:
        return False
    if names or word_type == 'proper_noun':
        return False    # the pack already says it is a name; nothing to add
    described = [d for d in definitions if isinstance(d, str) and d.strip()]
    if not described:
        return False
    if describes_a_name(described[0], rules):
        return False              # gloss and evidence agree: it is a name
    # A level is assigned to a meaning a learner acquires, and "god", "mommy",
    # "pa" and "soviet" are levelled and correct in both cases -- there the
    # gloss describes the capitalised sense rather than contradicting it.
    if is_attested_vocabulary(metadata) and word not in GLOSS_MISMATCHES:
        return False
    return evidence_capitalises(word, described, metadata)


# Rows a model read and found plainly wrong, which nothing in the pack can be
# used to detect: the linkage is right, the examples are right, only the gloss
# is somebody else's. Each entry names the text it expects to replace, so this
# fails loudly rather than silently if the upstream data is ever corrected.
#
#   "know about" was glossed "like something because you have good feelings
#   about it" — the meaning of "be keen on" — while its own examples read
#   "I know about toys" and "You never know about that family."
PHRASAL_CORRECTIONS = {
    'know about': (
        'like something because you have good feelings about it',
        'be informed about something',
        'To be informed about (someone or something); to have knowledge of.',
    ),
}


def fix_phrasal_glosses(db, report):
    """Applies PHRASAL_CORRECTIONS. Returns the phrasals it changed."""
    try:
        rows = db.execute(
            'SELECT id, phrasal, meaning FROM phrasal_verbs').fetchall()
    except sqlite3.OperationalError:
        return []                      # the German pack has no phrasal verbs
    fixed = []
    for row in rows:
        correction = PHRASAL_CORRECTIONS.get(row['phrasal'])
        if correction is None:
            continue
        wrong, meaning, sense = correction
        if row['meaning'] != wrong:
            print(f'  phrasal "{row["phrasal"]}" no longer reads '
                  f'"{wrong}" — leaving it alone')
            continue
        fixed.append(row['phrasal'])
        if not report:
            db.execute(
                'UPDATE phrasal_verbs SET meaning = ?, senses_json = ? '
                'WHERE id = ?',
                (meaning, json.dumps([sense], ensure_ascii=False), row['id']))
    if fixed and not report:
        db.commit()
    return fixed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('pack', type=pathlib.Path)
    parser.add_argument('--out', type=pathlib.Path)
    parser.add_argument('--report', action='store_true',
                        help='count and sample without writing anything')
    args = parser.parse_args()

    rules = load_rules()
    if args.report:
        out = args.pack
    else:
        out = args.out or args.pack.with_suffix('.repaired.db')
        shutil.copyfile(args.pack, out)

    db = sqlite3.connect(out)
    db.row_factory = sqlite3.Row
    language = pack_language(db)
    vocabulary = graded_surfaces(db)
    phrasals_fixed = fix_phrasal_glosses(db, args.report)
    weak = weak_masculine_forms(db)
    weak_patterns = weak_noun_patterns(weak)
    reasons = Counter()
    above = 0
    samples = {}
    named = 0
    detagged = 0
    resenses = 0
    declined = 0
    capitalised = 0
    rewritten = 0

    updates = []
    for row in db.execute(
            'SELECT id, word, lemma, word_type, enrichment_json, '
            'metadata_json FROM words'):
        enrichment = json.loads(row['enrichment_json'] or '{}')
        metadata = json.loads(row['metadata_json'] or '{}')
        definitions = enrichment.get('definitions') or []

        verdict, names = row_verdict(row['word'], row['word_type'],
                                     definitions, metadata, rules, language)
        # Never for a name: its leading gloss is *why* it is a name, and
        # dropping it left "london" reading "A former administrative county of
        # England" and looking like ordinary vocabulary again.
        drop = 0 if (verdict or names) else leading_unusable(definitions, rules)
        # Nor when dropping would *reveal* one: "erin" is glossed "Ireland."
        # first — a single word, and unusable — and a town in Ontario next.
        if drop and names_something(definitions[drop:], metadata, rules):
            names, drop = True, 0
        # Only for what is demonstrably not the word: "my" and "they" really
        # are Dolch words, however parse-like their glosses are, and a true
        # fact is not worth removing to make a filter easier.
        untaught = bool(verdict) or names

        quality = {'vocabulary': False, 'reasons': verdict} if verdict else None
        tags = [tag for tag in metadata.get('tags') or []]
        kept_tags = tags
        if untaught:
            kept_tags = [tag for tag in tags
                         if not CURRICULUM_TAGS.match(str(tag))]
        word_type = 'proper_noun' if names else row['word_type']

        # A gloss written above the reader it is for. Recorded rather than
        # replaced: the next gloss is a different sense.
        leading = next((d for d in definitions[drop:]
                        if isinstance(d, str) and d.strip()), None)
        hard_gloss = gloss_is_above_its_reader(leading, vocabulary, language)

        # The headword itself, where the entry's own evidence spells it with a
        # capital and nothing else does. Games compare what a child types
        # against this column, so until it is right the word cannot be taught.
        word = (CAPITALISED_HEADWORDS.get(row['word'], row['word'])
                if language == 'en' else row['word'])
        lemma = row['lemma']
        if word != row['word'] and lemma == row['word']:
            lemma = word

        # The pack writes its own example sentences, and they decline weak
        # masculine nouns as if they were strong: "den Held", "einen
        # Gedanke". The table in the same row says what the form is.
        sentences_fixed = 0
        for example in enrichment.get('examples') or []:
            if not isinstance(example, dict):
                continue
            text = example.get('text')
            if not isinstance(text, str):
                continue
            fixed = fix_weak_nouns(text, weak, weak_patterns)
            if fixed != text:
                example['text'] = fixed
                sentences_fixed += 1
        grade_examples = metadata.get('grade_examples')
        if isinstance(grade_examples, dict):
            for grade, sentences in grade_examples.items():
                if not isinstance(sentences, list):
                    continue
                for index, text in enumerate(sentences):
                    if not isinstance(text, str):
                        continue
                    fixed = fix_weak_nouns(text, weak, weak_patterns)
                    if fixed != text:
                        sentences[index] = fixed
                        sentences_fixed += 1

        changed = (quality != metadata.get('quality')
                   or hard_gloss != bool(metadata.get('gloss_above_reader'))
                   or kept_tags != tags
                   or word_type != row['word_type']
                   or word != row['word']
                   or drop
                   or sentences_fixed)
        if not changed:
            continue

        for reason in verdict:
            reasons[reason] += 1
            samples.setdefault(reason, []).append(row['word'])
        if names and row['word_type'] != 'proper_noun':
            named += 1
            samples.setdefault('named', []).append(row['word'])
        if kept_tags != tags:
            detagged += 1
            samples.setdefault('detagged', []).append(row['word'])
        if drop:
            resenses += 1
            samples.setdefault('resensed', []).append(row['word'])
        if sentences_fixed:
            declined += sentences_fixed
            samples.setdefault('declined', []).append(row['word'])
        if word != row['word']:
            capitalised += 1
            samples.setdefault('capitalised', []).append(word)
        if hard_gloss != bool(metadata.get('gloss_above_reader')):
            above += 1
            samples.setdefault('above', []).append(row['word'])
        rewritten += 1

        if args.report:
            continue

        if quality is None:
            metadata.pop('quality', None)
        else:
            metadata['quality'] = quality
        if kept_tags != tags:
            metadata['tags'] = kept_tags
        if hard_gloss:
            metadata['gloss_above_reader'] = True
        else:
            metadata.pop('gloss_above_reader', None)
        if drop:
            enrichment['definitions'] = definitions[drop:]
        updates.append((
            json.dumps(enrichment, ensure_ascii=False)
            if (drop or sentences_fixed) else row['enrichment_json'],
            json.dumps(metadata, ensure_ascii=False),
            word_type,
            word,
            lemma,
            row['id'],
        ))

    if updates:
        db.executemany(
            'UPDATE words SET enrichment_json = ?, metadata_json = ?, '
            'word_type = ?, word = ?, lemma = ? WHERE id = ?', updates)
        # The pack ships a prebuilt FTS5 search_index over the words table,
        # which nothing here can rebuild -- it is declared over a translations
        # column the words table does not have, so 'rebuild' fails. It does not
        # need rebuilding: every rename below differs from the old headword
        # only in case, and FTS5 folds case, so the index still matches. The
        # assertion is what keeps that true.
        db.commit()
        db.execute('VACUUM')

    total = db.execute('SELECT COUNT(*) FROM words').fetchone()[0]
    db.close()

    print(f'{args.pack.name}: {total} words, {rewritten} rows '
          f'{"would be " if args.report else ""}rewritten')
    for reason, count in reasons.most_common():
        shown = ', '.join(samples[reason][:6])
        print(f'  {count:6d}  {reason:28s} {shown}')
    for label, count in (('glosses above their reader', above),
                         ('headwords capitalised', capitalised),
                         ('word_type -> proper_noun', named),
                         ('curriculum tags dropped', detagged),
                         ('leading glosses dropped', resenses),
                         ('weak nouns declined', declined)):
        if count:
            key = {'glosses above their reader': 'above',
                   'headwords capitalised': 'capitalised',
                   'word_type -> proper_noun': 'named',
                   'curriculum tags dropped': 'detagged',
                   'leading glosses dropped': 'resensed',
                   'weak nouns declined': 'declined'}[label]
            print(f'  {count:6d}  {label:28s} {", ".join(samples[key][:6])}')
    if phrasals_fixed:
        print(f'  {len(phrasals_fixed):6d}  {"phrasal glosses corrected":28s} '
              f'{", ".join(phrasals_fixed)}')
    if not args.report:
        print(f'  wrote   {out}')


if __name__ == '__main__':
    main()
