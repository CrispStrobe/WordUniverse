#!/usr/bin/env python3
"""Have language models re-read every pack entry and correct what is wrong.

    python3 tools/pack/llm_correct.py propose <pack.db> --lang de [--limit N]
    python3 tools/pack/llm_correct.py report  --lang de
    python3 tools/pack/apply_llm_overlay.py <pack.db> --lang de   # into a pack

The packs were assembled from frequency lists, Wiktionary, WordNet and
spaCy, and each of those got some entries wrong in ways no rule catches:
"Hund" glossed as the constellations Großer/Kleiner Hund and flagged as
plural-only, "an" as the first letter of the Georgian alphabet, "it" as
information technology, "im" as a galaxy class. Reading catches them; there
are 24,000 entries, so models read.

Two passes, by two different model families, because a model asked to
improve something will improve it whether or not it was broken:

  propose   a model sees 20 entries as JSON and returns, for each, either
            {"ok": true} or the fields it would change, with a reason.
  verify    a model from another family sees the original entry beside the
            proposed change and accepts or rejects each field on its own.

Only fields both agree on reach the overlay (pipeline/llm_review/<lang>.jsonl).
Rejections are kept in <lang>.rejected.jsonl as a triage list for a person —
a disagreement is signal, not noise (pipeline/LEARNINGS.md §8).

Resumable: an entry is skipped when the overlay or the rejection log already
holds a verdict for it at the same source digest, so an interrupted run
continues where it stopped and an entry whose pack data changed is re-read.

Providers are any OpenAI-compatible endpoint whose key is in the environment
or in --env-file. A lane that is rate limited is parked and the batch goes
to another; nothing is retried against the same lane while it is parked.
"""
import argparse
import hashlib
import json
import os
import pathlib
import random
import re
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / 'pipeline' / 'llm_review'

# (lane name, base url, key variables, model, role, seconds between calls)
# Free tiers only. "propose" lanes write corrections, "verify" lanes judge
# them; a batch is never verified by the family that proposed it.
LANES = [
    ('mistral-large', 'https://api.mistral.ai/v1', ['MISTRAL_API_KEY'],
     'mistral-large-latest', 'propose', 2.2, 'mistral'),
    ('gemini-3.1-flash-lite', 'https://generativelanguage.googleapis.com/v1beta/openai',
     ['GOOGLEAI_API_KEY', 'GOOGLE_API_KEY'], 'gemini-3.1-flash-lite', 'propose', 5, 'google'),
    ('magistral-medium', 'https://api.mistral.ai/v1', ['MISTRAL_API_KEY'],
     'magistral-medium-latest', 'verify', 2.2, 'mistral'),
    ('command-a', 'https://api.cohere.ai/compatibility/v1', ['COHERE_API_KEY'],
     'command-a-03-2025', 'verify', 4, 'cohere'),
    ('gemini-3-flash', 'https://generativelanguage.googleapis.com/v1beta/openai',
     ['GOOGLEAI_API_KEY', 'GOOGLE_API_KEY'], 'gemini-3-flash-preview', 'propose', 7, 'google'),
    ('gpt-oss-120b-p', 'https://api.groq.com/openai/v1', ['GROQ_API_KEY'],
     'openai/gpt-oss-120b', 'propose', 3, 'openai'),
    ('nemotron-ultra-p', 'https://openrouter.ai/api/v1',
     ['OPENROUTER_API_KEY', 'OPENROUTER_API_KEY2', 'OPENROUTER_API_KEY3',
      'OPENROUTER_API_KEY4'],
     'nvidia/nemotron-3-ultra-550b-a55b:free', 'propose', 4, 'nvidia'),
    ('gpt-oss-120b', 'https://api.groq.com/openai/v1', ['GROQ_API_KEY'],
     'openai/gpt-oss-120b', 'verify', 3, 'openai'),
    ('qwen3.8-27b', 'https://api.groq.com/openai/v1', ['GROQ_API_KEY'],
     'qwen/qwen3.8-27b', 'verify', 3, 'qwen'),
    ('nemotron-ultra', 'https://openrouter.ai/api/v1',
     ['OPENROUTER_API_KEY', 'OPENROUTER_API_KEY2', 'OPENROUTER_API_KEY3',
      'OPENROUTER_API_KEY4'],
     'nvidia/nemotron-3-ultra-550b-a55b:free', 'verify', 4, 'nvidia'),
    ('mistral-medium', 'https://api.mistral.ai/v1', ['MISTRAL_API_KEY'],
     'mistral-medium-latest', 'verify', 2.2, 'mistral'),
    ('gemma-31b', 'https://openrouter.ai/api/v1',
     ['OPENROUTER_API_KEY', 'OPENROUTER_API_KEY2', 'OPENROUTER_API_KEY3',
      'OPENROUTER_API_KEY4'],
     'google/gemma-4-31b-it:free', 'verify', 4, 'google'),
]

WORD_TYPES = {
    'de': ['substantiv', 'verb', 'adjektiv', 'adverb', 'pronomen', 'artikel',
           'praeposition', 'konjunktion', 'partikel', 'numerale', 'andere'],
    'en': ['noun', 'verb', 'adjective', 'adverb', 'pronoun', 'proper_noun',
           'other'],
}
NOT_VOCABULARY = ['name', 'abbreviation', 'fragment', 'misspelling',
                  'inappropriate', 'foreign', 'not_a_word']
FIELDS = ['vocabulary', 'word_type', 'definition', 'article', 'plural',
          'plural_only']

PROPOSE_PROMPT = """You are a lexicographer checking entries of a {language} \
vocabulary database for a learning app used by children aged 6-12.

Each entry is JSON: id, word (exact spelling, exact case), word_type, \
grade (school year it is taught), definitions (the app shows ONLY the first \
one to children){extra}.

For every entry decide whether anything is WRONG. Typical faults:
- the first definition describes a different word or an obscure sense \
(a homograph, a proper noun, an abbreviation, a technical or adult sense) \
instead of the sense a child meets first;
- the definition is a grammatical parse ("plural of ...") or missing;
- the word type is wrong;
- the entry is not vocabulary a child should be asked about at all: a \
person or place name, an abbreviation, a contraction fragment, a misspelling, \
a non-{language} word, or vulgar/adult content;{extra_faults}

Answer with ONLY a JSON array, one object per entry, same order, no prose:
- nothing wrong: {{"id": "...", "ok": true}}
- otherwise: {{"id": "...", "ok": false, "reason": "<short>", ...only the \
fields you change}} using these fields:
  "vocabulary": false, "not_vocabulary": one of {not_vocabulary}
  "word_type": one of {word_types}
  "definition": a new FIRST definition in {language}: the most common \
sense, one short sentence a 9-year-old understands, not containing the word \
itself{extra_fields}

Be conservative. Change a field only when it is clearly wrong; a correct but \
imperfect definition stays. Never change the spelling or case of the word.

Important:
- Inflected forms (plurals, past tense, participles, -ing forms, comparatives, \
conjugated or declined forms) ARE vocabulary: keep them, and if the \
definition describes only the base word, write one for this form.
- A common word whose definition is wrong (e.g. "water" glossed as a village) \
is still vocabulary: fix the definition, do not mark it "name".
- Judge the WORD in its everyday sense, not the definition shown: "come" \
or "without" are never inappropriate even if a definition is.
- Use "name" only when the word itself is mainly a person or place name, and \
"fragment" only for prefixes, suffixes or broken pieces like "a-" or "i-i".

Entries:
{entries}"""

PROPOSE_EXTRA_DE = {
    'extra': ', article (der/die/das for nouns), plural, plural_only '
             '(true when the noun exists only in the plural)',
    'extra_faults': '\n- a noun has the wrong article, a wrong plural, or is '
                    'wrongly marked plural-only;',
    'extra_fields': '\n  "article": "der" | "die" | "das"\n  "plural": the '
                    'nominative plural, or null if there is none\n  '
                    '"plural_only": true | false',
}

VERIFY_PROMPT = """You are checking corrections that another reviewer \
proposed for a {language} vocabulary database used by children aged 6-12. \
The app shows children only the FIRST definition.

For each item you get the ORIGINAL entry and the PROPOSED change. Judge every \
proposed field on its own: accept it only if the original really is wrong \
and the proposal is correct and suitable for a child. A proposed definition \
must describe the word's most common sense in correct {language}, without \
containing the word itself.

Answer with ONLY a JSON array, one object per item, same order, no prose:
{{"id": "...", "accept": {{"<field>": true|false, ...}}, "note": "<short, \
only if you reject something>"}}

Items:
{items}"""


def load_env(path):
    env = dict(os.environ)
    if path and pathlib.Path(path).exists():
        for line in open(path, encoding='utf-8'):
            m = re.match(r'\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$', line)
            if m and m.group(1) not in os.environ:
                env[m.group(1)] = m.group(2).strip('"').strip("'")
    return env


class Lane:
    def __init__(self, name, base, key, model, role, interval, family):
        self.name, self.base, self.key, self.model = name, base, key, model
        self.role, self.interval, self.family = role, interval, family
        self.lock = threading.Lock()
        self.next_at = 0.0
        self.parked_until = 0.0
        self.calls = self.failures = 0

    def available(self):
        return time.time() >= self.parked_until

    def park(self, seconds):
        self.parked_until = max(self.parked_until, time.time() + seconds)

    def call(self, prompt, timeout=240):
        with self.lock:
            wait = self.next_at - time.time()
            if wait > 0:
                time.sleep(wait)
            self.next_at = time.time() + self.interval
        body = {
            'model': self.model,
            'messages': [{'role': 'user', 'content': prompt}],
            'temperature': 0.1,
        }
        request = urllib.request.Request(
            self.base + '/chat/completions', data=json.dumps(body).encode(),
            headers={'Authorization': 'Bearer ' + self.key,
                     'Content-Type': 'application/json',
                     'User-Agent': 'wordUniverse-pack-review'})
        self.calls += 1
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = json.load(response)
        return data['choices'][0]['message']['content'] or ''


class Pool:
    def __init__(self, env, only=None):
        self.lanes = []
        for name, base, keys, model, role, interval, family in LANES:
            if only and name not in only:
                continue
            for i, var in enumerate(keys):
                if env.get(var):
                    self.lanes.append(Lane(f'{name}#{i}', base, env[var], model,
                                           role, interval, family))
        if not self.lanes:
            sys.exit('no provider keys found')

    def run(self, role, prompt, exclude_family=None, attempts=10):
        tried = []
        for _ in range(attempts):
            candidates = [l for l in self.lanes if l.role == role
                          and l.family != exclude_family and l.available()]
            if not candidates:
                time.sleep(15)
                continue
            # Least-recently-scheduled first spreads load across lanes.
            lane = min(candidates, key=lambda l: (l.next_at, random.random()))
            try:
                return lane, parse_array(lane.call(prompt))
            except urllib.error.HTTPError as e:
                lane.failures += 1
                retry = e.headers.get('retry-after') if e.headers else None
                if e.code == 429:
                    lane.park(float(retry) if retry and retry.isdigit() else 90)
                elif e.code in (401, 402, 403, 404):
                    lane.park(10 ** 9)  # not usable this run
                else:
                    lane.park(30)
                tried.append(f'{lane.name}:{e.code}')
            except Exception as e:  # timeout, bad JSON, connection reset
                lane.failures += 1
                lane.park(20)
                tried.append(f'{lane.name}:{type(e).__name__}')
        raise RuntimeError('all attempts failed: ' + ', '.join(tried[-5:]))


def parse_array(text):
    text = re.sub(r'<think>.*?</think>', '', text, flags=re.S)
    start, end = text.find('['), text.rfind(']')
    if start < 0 or end < start:
        raise ValueError('no JSON array in reply')
    return json.loads(text[start:end + 1])


def entry_of(row, lang):
    enrichment = json.loads(row['enrichment_json'] or '{}')
    metadata = json.loads(row['metadata_json'] or '{}')
    definitions = [d[:220] for d in (enrichment.get('definitions') or [])[:3]
                   if isinstance(d, str)]
    entry = {
        'id': row['original_id'],
        'word': row['word'],
        'word_type': row['word_type'],
        'grade': row['grade_level'],
        'definitions': definitions,
    }
    if lang == 'de' and row['word_type'] == 'substantiv':
        entry['article'] = row['article']
        entry['plural'] = metadata.get('forms')
        entry['plural_only'] = bool(metadata.get('nurImPlural'))
    return entry


def digest(entry):
    return hashlib.sha256(json.dumps(entry, sort_keys=True,
                                     ensure_ascii=False).encode()).hexdigest()[:16]


def clean_change(proposal, entry, lang):
    """Keep only well-formed fields that actually differ from the entry."""
    change = {}
    if proposal.get('vocabulary') is False:
        reason = proposal.get('not_vocabulary')
        change['vocabulary'] = False
        change['not_vocabulary'] = reason if reason in NOT_VOCABULARY else 'not_a_word'
    wt = proposal.get('word_type')
    if wt in WORD_TYPES[lang] and wt != entry['word_type']:
        change['word_type'] = wt
    d = proposal.get('definition')
    if isinstance(d, str) and 8 <= len(d.strip()) <= 160 and \
            not re.search(r'\b' + re.escape(entry['word']) + r'\b', d, re.I) and \
            d.strip() != (entry['definitions'] or [''])[0]:
        change['definition'] = d.strip()
    if lang == 'de' and (entry['word_type'] == 'substantiv'
                         or change.get('word_type') == 'substantiv'):
        a = proposal.get('article')
        if a in ('der', 'die', 'das') and a != entry.get('article'):
            change['article'] = a
        if 'plural' in proposal:
            p = proposal['plural']
            if (p is None or (isinstance(p, str) and 0 < len(p) < 40)) and \
                    p != entry.get('plural'):
                change['plural'] = p
        po = proposal.get('plural_only')
        if isinstance(po, bool) and po != entry.get('plural_only'):
            change['plural_only'] = po
    return change


class Store:
    def __init__(self, lang):
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        self.accepted = OUT_DIR / f'{lang}.jsonl'
        self.rejected = OUT_DIR / f'{lang}.rejected.jsonl'
        self.lock = threading.Lock()
        self.seen = {}
        for path in (self.accepted, self.rejected):
            if path.exists():
                for line in open(path, encoding='utf-8'):
                    if line.strip():
                        record = json.loads(line)
                        self.seen[record['id']] = record['src']

    def done(self, entry_id, src):
        return self.seen.get(entry_id) == src

    def write(self, path, record):
        with self.lock:
            with open(path, 'a', encoding='utf-8') as f:
                f.write(json.dumps(record, ensure_ascii=False) + '\n')
            self.seen[record['id']] = record['src']


def process(batch, pool, store, lang, language, stats):
    entries = [e for e, _ in batch]
    extra = PROPOSE_EXTRA_DE if lang == 'de' else {
        'extra': '', 'extra_faults': '', 'extra_fields': ''}
    prompt = PROPOSE_PROMPT.format(
        language=language, word_types=WORD_TYPES[lang],
        not_vocabulary=NOT_VOCABULARY,
        entries=json.dumps(entries, ensure_ascii=False, indent=0), **extra)
    proposer, proposals = pool.run('propose', prompt)
    by_id = {p.get('id'): p for p in proposals if isinstance(p, dict)}

    changes = []
    for entry, src in batch:
        p = by_id.get(entry['id'])
        change = clean_change(p, entry, lang) if p and p.get('ok') is False else {}
        if change:
            changes.append((entry, src, change, (p or {}).get('reason', '')))
        else:
            # "ok", or a proposal with nothing well formed in it: the entry
            # has been read and stands. Recorded so a rerun skips it.
            store.write(store.accepted, {'id': entry['id'], 'word': entry['word'],
                                         'src': src, 'ok': True,
                                         'by': proposer.model})
            stats['ok'] += 1
    if not changes:
        return

    items = [{'id': e['id'], 'original': e, 'proposed': c, 'reason': r}
             for e, _, c, r in changes]
    verifier, verdicts = pool.run(
        'verify', VERIFY_PROMPT.format(
            language=language, items=json.dumps(items, ensure_ascii=False, indent=0)),
        exclude_family=proposer.family)
    verdict_by_id = {v.get('id'): v for v in verdicts if isinstance(v, dict)}

    for entry, src, change, reason in changes:
        v = verdict_by_id.get(entry['id']) or {}
        accept = v.get('accept') or {}
        kept = {k: val for k, val in change.items()
                if accept.get(k) is True
                or (k == 'not_vocabulary' and accept.get('vocabulary') is True)}
        dropped = {k: val for k, val in change.items() if k not in kept}
        base = {'id': entry['id'], 'word': entry['word'], 'src': src,
                'reason': reason, 'by': proposer.model, 'checked_by': verifier.model}
        if kept:
            store.write(store.accepted, {**base, 'ok': False, 'change': kept,
                                         'original': {k: entry.get(k) for k in
                                                      ('word_type', 'definitions',
                                                       'article', 'plural',
                                                       'plural_only') if k in entry}})
            stats['changed'] += 1
        if dropped:
            store.write(store.rejected, {**base, 'rejected': dropped,
                                         'note': v.get('note', ''),
                                         'original': entry})
            stats['rejected'] += 1


def propose(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    store = Store(args.lang)
    language = 'German' if args.lang == 'de' else 'English'
    db = sqlite3.connect(args.pack)
    db.row_factory = sqlite3.Row
    rows = db.execute('SELECT original_id, word, word_type, article, grade_level, '
                      'enrichment_json, metadata_json FROM words '
                      'ORDER BY grade_level IS NULL, grade_level, id').fetchall()
    todo = []
    for row in rows:
        entry = entry_of(row, args.lang)
        src = digest(entry)
        if not store.done(entry['id'], src):
            todo.append((entry, src))
    if args.limit:
        todo = todo[:args.limit]
    batches = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    print(f'{len(rows)} entries, {len(todo)} to read in {len(batches)} batches; '
          f'lanes: {", ".join(l.name for l in pool.lanes)}', flush=True)
    stats = {'ok': 0, 'changed': 0, 'rejected': 0, 'failed': 0}
    started = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = [ex.submit(process, b, pool, store, args.lang, language, stats)
                   for b in batches]
        for i, f in enumerate(as_completed(futures), 1):
            try:
                f.result()
            except Exception as e:
                stats['failed'] += 1
                print(f'batch failed: {e}', flush=True)
            if i % 10 == 0 or i == len(futures):
                rate = i / max(1, time.time() - started) * 3600
                print(f'[{i}/{len(futures)}] {stats} ~{rate:.0f} batches/h', flush=True)
    print('lanes:', ', '.join(f'{l.name} {l.calls} calls/{l.failures} failed'
                              for l in pool.lanes), flush=True)


def report(args):
    store = Store(args.lang)
    counts = {}
    examples = {}
    for line in open(store.accepted, encoding='utf-8'):
        r = json.loads(line)
        if r.get('ok'):
            counts['ok'] = counts.get('ok', 0) + 1
            continue
        for k in r['change']:
            counts[k] = counts.get(k, 0) + 1
            examples.setdefault(k, []).append(r)
    rejected = sum(1 for _ in open(store.rejected)) if store.rejected.exists() else 0
    print(json.dumps(counts), f'rejected={rejected}')
    for k, rs in examples.items():
        print(f'\n== {k}')
        for r in random.Random(1).sample(rs, min(args.samples, len(rs))):
            o = r['original']
            print(f"  {r['word']} [{o.get('word_type')}] "
                  f"{(o.get('definitions') or [''])[0][:70]!r} -> {r['change'][k]!r}"
                  f"  ({r['reason'][:60]})")


# ─── Phrasal verbs (English pack, `phrasal_verbs` table) ───────────────────
#
# Phrasal Verb Power blanks the particle out of a sentence and offers three
# others. A dump read found 5-7 of 12 items broken at every grade: rows that
# are not English ("join out" = "join a group"), sentences that are not
# either ("I send ___ card.", "Mom sends away kid."), and distractors that
# fit as well as the key ("The bad guy will break ___ tonight": in / out).
# So each row is rewritten whole and then checked sentence by sentence.

PARTICLES = ['up', 'down', 'in', 'out', 'on', 'off', 'away', 'back', 'over',
             'around', 'through', 'along', 'apart', 'by', 'into', 'across']

PHRASAL_PROMPT = """You are writing exercises for English learners aged 8-11. \
Each item below is a phrasal verb from our database, with its stored meaning \
and two of its current example sentences.

For each item:
1. keep: false if it is not a real, common English phrasal verb with that \
meaning, or not suitable for children (violence, crime, sex, alcohol). \
Otherwise keep: true.
2. meaning: the most common meaning, in very simple English (max 10 words).
3. sentences: exactly 3 short, natural, grammatical sentences (5-12 words) \
using the phrasal verb in that meaning. The particle "{{particle}}" must appear \
exactly once, right where the phrasal verb uses it. The context must make \
this particle the ONLY one that fits: no other particle from {particles} may \
make sense in its place.
4. wrong_particles: exactly 3 particles from {particles} that do NOT make \
sense in ANY of your sentences.

Answer with ONLY a JSON array, one object per item, same order, no prose:
{{"id": "...", "keep": true, "meaning": "...", "sentences": ["...", "...", \
"..."], "wrong_particles": ["...", "...", "..."]}}
or {{"id": "...", "keep": false, "reason": "..."}}

Items:
{items}"""

PHRASAL_VERIFY = """You are checking exercises for English learners aged \
8-11. In each sentence the particle of the given phrasal verb will be \
replaced by a gap, and the child chooses between the correct particle and \
the three wrong_particles.

For each item judge:
- meaning_ok: the meaning is correct and simple.
- sentences_ok: for each sentence, true only if it is natural, grammatical, \
uses the phrasal verb in that meaning, and NONE of the wrong_particles would \
also make sense in the gap.

Answer with ONLY a JSON array, one object per item, same order, no prose:
{{"id": "...", "meaning_ok": true, "sentences_ok": [true, false, true], \
"note": "<short, only if something is rejected>"}}

Items:
{items}"""


def phrasal(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    out = OUT_DIR / 'en_phrasal.jsonl'
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    done = set()
    if out.exists():
        done = {json.loads(l)['id'] for l in open(out, encoding='utf-8') if l.strip()}
    db = sqlite3.connect(args.pack)
    db.row_factory = sqlite3.Row
    rows = [r for r in db.execute('SELECT phrasal, base_verb, particle, meaning, '
                                  'examples_json FROM phrasal_verbs ORDER BY phrasal')
            if r['phrasal'] not in done]
    items = []
    for r in rows:
        examples = json.loads(r['examples_json'] or '{}')
        sample = [s for band in sorted(examples) for s in examples[band]][:2]
        items.append({'id': r['phrasal'], 'phrasal': r['phrasal'],
                      'particle': r['particle'], 'meaning': r['meaning'],
                      'examples': sample})
    batches = [items[i:i + 15] for i in range(0, len(items), 15)]
    print(f'{len(rows)} phrasal verbs to read in {len(batches)} batches', flush=True)
    lock = threading.Lock()
    stats = {'kept': 0, 'dropped': 0, 'unusable': 0, 'failed': 0}

    def one(batch):
        prompt = PHRASAL_PROMPT.format(particles=PARTICLES, items=json.dumps(
            batch, ensure_ascii=False, indent=0)).replace('{particle}', 'its particle')
        proposer, proposals = pool.run('propose', prompt)
        by_id = {p.get('id'): p for p in proposals if isinstance(p, dict)}
        to_check, records = [], []
        for item in batch:
            p = by_id.get(item['id'])
            if not p:
                continue
            if p.get('keep') is False:
                records.append({'id': item['id'], 'keep': False,
                                'reason': p.get('reason', ''), 'by': proposer.model})
                continue
            particle = item['particle'].lower()
            sentences = [s.strip() for s in p.get('sentences') or []
                         if isinstance(s, str) and len(re.findall(
                             r'\b' + re.escape(particle) + r'\b', s.lower())) == 1]
            wrong = [w for w in p.get('wrong_particles') or []
                     if w in PARTICLES and w != particle][:3]
            meaning = (p.get('meaning') or item['meaning']).strip()
            if len(sentences) < 2 or len(wrong) < 3:
                records.append({'id': item['id'], 'keep': None, 'by': proposer.model,
                                'note': 'proposal unusable'})
                continue
            to_check.append({'id': item['id'], 'phrasal': item['phrasal'],
                             'meaning': meaning, 'sentences': sentences,
                             'wrong_particles': wrong})
        if to_check:
            verifier, verdicts = pool.run('verify', PHRASAL_VERIFY.format(
                items=json.dumps(to_check, ensure_ascii=False, indent=0)),
                exclude_family=proposer.family)
            vby = {v.get('id'): v for v in verdicts if isinstance(v, dict)}
            for c in to_check:
                v = vby.get(c['id']) or {}
                oks = v.get('sentences_ok') or []
                good = [s for s, ok in zip(c['sentences'], oks) if ok is True]
                if v.get('meaning_ok') is True and len(good) >= 2:
                    records.append({'id': c['id'], 'keep': True, 'meaning': c['meaning'],
                                    'sentences': good,
                                    'wrong_particles': c['wrong_particles'],
                                    'by': proposer.model, 'checked_by': verifier.model})
                else:
                    records.append({'id': c['id'], 'keep': None, 'by': proposer.model,
                                    'checked_by': verifier.model,
                                    'note': v.get('note', 'rejected'), 'proposal': c})
        with lock:
            with open(out, 'a', encoding='utf-8') as f:
                for r in records:
                    f.write(json.dumps(r, ensure_ascii=False) + '\n')
                    key = {True: 'kept', False: 'dropped', None: 'unusable'}[r['keep']]
                    stats[key] += 1

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for f in as_completed([ex.submit(one, b) for b in batches]):
            try:
                f.result()
            except Exception as e:
                stats['failed'] += 1
                print(f'batch failed: {e}', flush=True)
    print(stats, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('propose')
    p.add_argument('pack')
    p.add_argument('--lang', choices=['de', 'en'], required=True)
    p.add_argument('--limit', type=int)
    p.add_argument('--batch', type=int, default=20)
    p.add_argument('--workers', type=int, default=6)
    p.add_argument('--lanes', help='comma-separated lane names to use')
    p.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    ph = sub.add_parser('phrasal')
    ph.add_argument('pack')
    ph.add_argument('--workers', type=int, default=4)
    ph.add_argument('--lanes')
    ph.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    r = sub.add_parser('report')
    r.add_argument('--lang', choices=['de', 'en'], required=True)
    r.add_argument('--samples', type=int, default=8)
    args = parser.parse_args()
    {'propose': propose, 'report': report, 'phrasal': phrasal}[args.cmd](args)


if __name__ == '__main__':
    main()
