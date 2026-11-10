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
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / 'pipeline' / 'llm_review'

OPENCODE_SESSION = {'x-opencode-session': lambda: str(uuid.uuid4())}

# (lane name, base url, key variables, model, role, seconds between calls,
#  family[, extra headers])
# Free tiers only. "propose" lanes write corrections, "verify" lanes judge
# them; a batch is never verified by the family that proposed it.
LANES = [
    ('mistral-large', 'https://api.mistral.ai/v1', ['MISTRAL_API_KEY'],
     'mistral-large-latest', 'propose', 2.2, 'mistral'),
    ('gemini-3.1-flash-lite', 'https://generativelanguage.googleapis.com/v1beta/openai',
     ['GOOGLEAI_API_KEY', 'GOOGLE_API_KEY'], 'gemini-3.1-flash-lite', 'propose', 5, 'google'),
    # Free on Together (2026-11). A ternary 27B: proposes only, so a
    # stronger model of another family checks everything it suggests.
    ('bonsai-27b', 'https://api.together.xyz/v1',
     ['TOGETHER_API_KEY', 'TOGETHER_API_KEY2', 'TOGETHER_API_KEY3'],
     'Prism-ML/Ternary-Bonsai-27B', 'propose', 3, 'prism'),
    # OpenCode Go's free models; they need a client session header.
    ('longcat-2.5', 'https://opencode.ai/zen/go/v1', ['OPENCODEGO_TOKEN'],
     'longcat-2.5-free', 'propose', 3, 'longcat', OPENCODE_SESSION),
    ('beam', 'https://opencode.ai/zen/go/v1', ['OPENCODEGO_TOKEN'],
     'beam-free', 'verify', 3, 'beam', OPENCODE_SESSION),
    ('iceman', 'https://opencode.ai/zen/go/v1', ['OPENCODEGO_TOKEN'],
     'iceman-contributor-free', 'verify', 3, 'iceman', OPENCODE_SESSION),
    # Hetzner's free inference (experiments.hetzner.com), HETZNER_TOKEN.
    ('hetzner-qwen-p', 'https://inference.hetzner.com/v1', ['HETZNER_TOKEN'],
     'Qwen/Qwen3.8-27B', 'propose', 2, 'qwen'),
    ('hetzner-qwen', 'https://inference.hetzner.com/v1', ['HETZNER_TOKEN'],
     'Qwen/Qwen3.8-27B', 'verify', 2, 'qwen'),
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
    def __init__(self, name, base, key, model, role, interval, family,
                 headers=None):
        self.name, self.base, self.key, self.model = name, base, key, model
        self.headers = headers or {}
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
                     'User-Agent': 'wordUniverse-pack-review',
                     **{k: (v() if callable(v) else v)
                        for k, v in self.headers.items()}})
        self.calls += 1
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = json.load(response)
        return data['choices'][0]['message']['content'] or ''


class Pool:
    def __init__(self, env, only=None):
        self.lanes = []
        for name, base, keys, model, role, interval, family, *rest in LANES:
            if only and name not in only:
                continue
            for i, var in enumerate(keys):
                if env.get(var):
                    self.lanes.append(Lane(f'{name}#{i}', base, env[var], model,
                                           role, interval, family,
                                           rest[0] if rest else None))
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


def entry_key(row):
    """original_id, or the row id where there is none.

    3,035 rows of the German pack (the later child-vocabulary additions:
    anbellen, Bushaltestelle, Dackel) have no original_id. Keyed by it, they
    all shared one key, so their verdicts overwrote each other and none could
    be applied. Row ids are stable through slim, repair and the CI build.
    """
    return row['original_id'] or f"row:{row['id']}"


def entry_of(row, lang):
    enrichment = json.loads(row['enrichment_json'] or '{}')
    metadata = json.loads(row['metadata_json'] or '{}')
    definitions = [d[:220] for d in (enrichment.get('definitions') or [])[:3]
                   if isinstance(d, str)]
    entry = {
        'id': entry_key(row),
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
    rows = db.execute('SELECT id, original_id, word, word_type, article, grade_level, '
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


# ─── Audit: re-check every accepted change in isolation ───────────────────
#
# The first German run attached glosses to the wrong entry: "schlurfen" got
# "Ein Metallteil mit Gewinde" (a screw), "lern" "Ein frecher Junge", and
# "Tröpfchen" the plural "Vanillen". Entries with no gloss of their own are
# where it happened — the verifier had nothing to compare against. So each
# accepted change is shown again on its own line, word beside value, where a
# misplaced one is obvious, to two judges of different families. A change
# either of them flags is dropped (pipeline/llm_review/<lang>.audit.jsonl).

AUDIT_PROMPT = """You are checking a {language} children's dictionary. Each \
line is: number | word | field | proposed value.

Fields:
- definition: must describe THIS word's common meaning (for an inflected \
form, the meaning of that form).
- plural: the nominative plural of this noun. It may be identical to the \
singular (der Lehrer -> die Lehrer, der Pinsel -> die Pinsel); "None" means \
the noun has no plural.
- article: der/die/das of this noun.
- word_type: its part of speech.
- plural_only: true = the noun exists only in the plural (Ferien, Leute); \
false = it has a normal singular.
- vocabulary=false: the word is a name, abbreviation, misspelling, fragment, \
foreign or unsuitable word.

List the numbers of the lines that are clearly WRONG: the value belongs to \
a different word, or is factually incorrect. Do not list a line just because \
another answer would also be acceptable. Answer with ONLY a JSON array of \
numbers, e.g. [3, 17], or [] if all are right.

{lines}"""


def audit(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    language = 'German' if args.lang == 'de' else 'English'
    out = OUT_DIR / f'{args.lang}.audit.jsonl'
    done = set()
    if out.exists():
        for line in open(out, encoding='utf-8'):
            if line.strip():
                done.add(json.loads(line)['key'])
    checks = []
    for line in open(OUT_DIR / f'{args.lang}.jsonl', encoding='utf-8'):
        r = json.loads(line)
        for field, value in (r.get('change') or {}).items():
            if field == 'not_vocabulary':
                continue
            key = f"{r['id']}|{r['src']}|{field}"
            if key in done:
                continue
            shown = 'false' if field == 'vocabulary' else value
            checks.append({'key': key, 'word': r['word'], 'field': field,
                           'value': shown})
    batches = [checks[i:i + 40] for i in range(0, len(checks), 40)]
    print(f'{len(checks)} changes to audit in {len(batches)} batches', flush=True)
    judges = args.judges.split(',')
    lock = threading.Lock()
    stats = {'kept': 0, 'dropped': 0, 'failed': 0}

    def one(batch):
        lines = '\n'.join(f"{i + 1} | {c['word']} | {c['field']} | {c['value']}"
                          for i, c in enumerate(batch))
        prompt = AUDIT_PROMPT.format(language=language, lines=lines)
        flagged, by, per_judge = set(), [], {}
        for judge in judges:
            lane_pool = Pool.__new__(Pool)
            lane_pool.lanes = [l for l in pool.lanes if l.name.split('#')[0] == judge]
            if not lane_pool.lanes:
                raise RuntimeError(f'no lane {judge}')
            for l in lane_pool.lanes:
                l.role = 'audit'
            lane, numbers = lane_pool.run('audit', prompt, attempts=40)
            by.append(lane.model)
            mine = {n for n in numbers if isinstance(n, int)}
            per_judge[lane.model] = mine
            flagged |= mine
        with lock, open(out, 'a', encoding='utf-8') as f:
            for i, c in enumerate(batch):
                bad = (i + 1) in flagged
                f.write(json.dumps({'key': c['key'], 'word': c['word'],
                                    'field': c['field'], 'value': c['value'],
                                    'ok': not bad, 'by': by,
                                    'flagged_by': [m for m, n in per_judge.items()
                                                   if (i + 1) in n]},
                                   ensure_ascii=False) + '\n')
                stats['dropped' if bad else 'kept'] += 1

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for f in as_completed([ex.submit(one, b) for b in batches]):
            try:
                f.result()
            except Exception as e:
                stats['failed'] += 1
                print(f'batch failed: {e}', flush=True)
    print(stats, flush=True)


# ─── Relations: word classes and a child's category word ──────────────────
#
# Two games ask what the pack cannot say reliably. Word Class Flash asks
# which class a word is, and 4,150 English entries have no WordNet senses to
# show that "mash" is a noun as well as a verb. Hypernym Flash asks "a knife
# is a kind of …?", and WordNet's hypernyms span every sense: knife -> arm
# (the weapon), bone -> white, ache -> long. So a model names the classes a
# child meets the spelling in, and the category word for the sense the pack
# glosses; a model of another family lists the classes again on its own and
# judges the category. The class lists are united, so a word either model
# calls ambiguous is not asked about.

CLASSES = ['noun', 'verb', 'adjective', 'adverb', 'pronoun', 'preposition',
           'conjunction', 'determiner', 'numeral', 'interjection']
CLASS_OF_TYPE = {
    'noun': 'noun', 'substantiv': 'noun', 'verb': 'verb',
    'adjective': 'adjective', 'adjektiv': 'adjective', 'adverb': 'adverb',
    'pronoun': 'pronoun', 'pronomen': 'pronoun', 'preposition': 'preposition',
    'praeposition': 'preposition', 'conjunction': 'conjunction',
    'konjunktion': 'conjunction', 'artikel': 'determiner',
    'determiner': 'determiner', 'numerale': 'numeral', 'numeral': 'numeral',
    'interjection': 'interjection', 'interjektion': 'interjection',
}
RELATION_TYPES = {'noun', 'substantiv', 'verb', 'adjective', 'adjektiv',
                  'adverb'}

RELATIONS_TEXT = {
    'en': dict(
        noun_frame='A <word> is a kind of ___.',
        verb_frame='To <word> is a way to ___.',
        too_general='thing, object, item, stuff, person, people, place, '
                    'act, action, do, make, be, have, get, go',
        class_note='A participle or -ing form counts as an adjective only '
                   'where it is commonly one ("interesting", "tired").'),
    'de': dict(
        noun_frame='Ein/eine <Wort> ist eine Art ___.',
        verb_frame='<wort> ist eine Art zu ___.',
        too_general='Ding, Sache, Gegenstand, Etwas, Person, Mensch, Ort, '
                    'Handlung, tun, machen, sein, haben, werden',
        class_note='Use German school grammar: an adjective used '
                   'adverbially ("schnell laufen") is still only an '
                   'adjective; a noun is only a noun (the nominalised verb '
                   '"das Laufen" is a separate entry), and a verb is only a '
                   'verb.'),
}

RELATIONS_PROMPT = """You are preparing word games for {language}-speaking \
children aged 6-11. Each entry gives a word, its word type in our dictionary \
and its first meaning.

For each entry:
1. classes: every word class in which this exact spelling is commonly used \
in everyday {language}, from {classes}. Include a class only if a child \
would plausibly meet the word used that way. {class_note}
2. category — only for nouns and verbs, and in the meaning given: the one \
common, simple {language} word a child would give for "{noun_frame}" or \
"{verb_frame}". It must be of the same word class as the entry, a true \
superordinate (a kind-of relation: not a part, colour, material, place, \
use or synonym), not the word itself or contained in it, and not so general \
that it fits almost anything ({too_general}). Use null where no such \
everyday word exists, and for every word that is not a noun or verb.

Answer with ONLY a JSON array, one object per entry, same order, no prose:
{{"id": "...", "classes": ["..."], "category": "..." or null}}

Entries:
{entries}"""

RELATIONS_VERIFY = """You are checking word-game data for {language}-speaking \
children aged 6-11. Each entry gives a word, its word type, its first \
meaning and a proposed category.

For each entry:
1. classes: on your own, list every word class in which this exact spelling \
is commonly used in everyday {language}, from {classes}. Include a class \
only if a child would plausibly meet the word used that way. {class_note}
2. category_ok (only where a category is given): true if "{noun_frame}" / \
"{verb_frame}" with that category is correct for the meaning given, the \
category is a true superordinate of the same word class (not a part, \
colour, material, place, use or synonym) and a word a child knows; \
otherwise false.

Answer with ONLY a JSON array, one object per entry, same order, no prose:
{{"id": "...", "classes": ["..."], "category_ok": true}}

Entries:
{entries}"""


def relation_entry(row, lang):
    enrichment = json.loads(row['enrichment_json'] or '{}')
    gloss = next((d[:200] for d in enrichment.get('definitions') or []
                  if isinstance(d, str) and d.strip()), '')
    entry = {'id': entry_key(row), 'word': row['word'],
             'word_type': CLASS_OF_TYPE.get(row['word_type'], row['word_type']),
             'meaning': gloss}
    if lang == 'de' and row['word_type'] == 'substantiv' and row['article']:
        entry['word'] = f"{row['article']} {row['word']}"
    return entry


def clean_classes(value):
    if not isinstance(value, list):
        return None
    out = sorted({c.strip().lower() for c in value
                  if isinstance(c, str) and c.strip().lower() in CLASSES})
    return out or None


def relations(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    language = 'German' if args.lang == 'de' else 'English'
    text = RELATIONS_TEXT[args.lang]
    out = OUT_DIR / f'{args.lang}_relations.jsonl'
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    seen = {}
    if out.exists():
        for line in open(out, encoding='utf-8'):
            if line.strip():
                r = json.loads(line)
                seen[r['id']] = r['src']
    db = sqlite3.connect(args.pack)
    db.row_factory = sqlite3.Row
    rows = db.execute(
        "SELECT id, original_id, word, word_type, article, enrichment_json, "
        "metadata_json FROM words WHERE coalesce(json_extract(metadata_json, "
        "'$.quality.vocabulary'), 1) = 1 ORDER BY grade_level, id").fetchall()
    todo = []
    for row in rows:
        if row['word_type'] not in RELATION_TYPES:
            continue
        entry = relation_entry(row, args.lang)
        src = digest(entry)
        if seen.get(entry['id']) != src:
            todo.append((entry, src))
    if args.limit:
        todo = todo[:args.limit]
    batches = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    print(f'{len(todo)} entries in {len(batches)} batches', flush=True)
    lock = threading.Lock()
    stats = {'entries': 0, 'categories': 0, 'ambiguous': 0, 'failed': 0}

    def one(batch):
        entries = [e for e, _ in batch]
        fmt = dict(language=language, classes=CLASSES, **text)
        proposer, proposals = pool.run('propose', RELATIONS_PROMPT.format(
            entries=json.dumps(entries, ensure_ascii=False, indent=0), **fmt))
        by_id = {p.get('id'): p for p in proposals if isinstance(p, dict)}
        shown = []
        for entry in entries:
            p = by_id.get(entry['id']) or {}
            category = p.get('category')
            if not (isinstance(category, str) and category.strip()
                    and entry['word_type'] in ('noun', 'verb')):
                category = None
            shown.append({**entry, 'category': category.strip() if category else None})
        verifier, verdicts = pool.run('verify', RELATIONS_VERIFY.format(
            entries=json.dumps(shown, ensure_ascii=False, indent=0), **fmt),
            exclude_family=proposer.family)
        v_by_id = {v.get('id'): v for v in verdicts if isinstance(v, dict)}
        records = []
        for (entry, src), item in zip(batch, shown):
            p, v = by_id.get(entry['id']), v_by_id.get(entry['id'])
            if not p or not v:
                continue  # read again on the next run
            a, b = clean_classes(p.get('classes')), clean_classes(v.get('classes'))
            classes = sorted(set(a or []) | set(b or [])) if a and b else None
            category = item['category'] if v.get('category_ok') is True else None
            records.append({'id': entry['id'], 'word': entry['word'], 'src': src,
                            'word_type': entry['word_type'], 'classes': classes,
                            'category': category,
                            'proposed_category': item['category'],
                            'by': proposer.model, 'checked_by': verifier.model})
        with lock, open(out, 'a', encoding='utf-8') as f:
            for r in records:
                f.write(json.dumps(r, ensure_ascii=False) + '\n')
                stats['entries'] += 1
                stats['categories'] += r['category'] is not None
                stats['ambiguous'] += len(r['classes'] or []) > 1

    started = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = [ex.submit(one, b) for b in batches]
        for i, f in enumerate(as_completed(futures), 1):
            try:
                f.result()
            except Exception as e:
                stats['failed'] += 1
                print(f'batch failed: {e}', flush=True)
            if i % 10 == 0 or i == len(futures):
                rate = i / max(1, time.time() - started) * 3600
                print(f'[{i}/{len(futures)}] {stats} ~{rate:.0f} batches/h', flush=True)


# ─── Phrasal fits: which particles fill each gap ─────────────────────────
#
# The phrasal rewrite asked its verifier to confirm three wrong particles,
# and confirming is where it slipped: "She walks me ___ the steps" kept
# "down" as wrong. So two judges now list every particle that fits each gap,
# literal readings included, and only a particle neither lists is offered.

FITS_PROMPT = """Each line is a sentence with a gap (___). For each, list \
EVERY word from {particles} that could fill the gap to give a grammatical \
sentence that makes sense in any reading, literal or idiomatic. Be generous: \
when in doubt, include the word.

Answer with ONLY a JSON array with one object per line, e.g. \
[{{"n": 1, "fits": ["up", "down"]}}, {{"n": 2, "fits": ["away"]}}].

{lines}"""


def phrasal_fits(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    out = OUT_DIR / 'en_phrasal_fits.jsonl'
    done = set()
    if out.exists():
        done = {json.loads(l)['sentence'] for l in open(out, encoding='utf-8')
                if l.strip()}
    gaps = []
    latest = {}
    for line in open(OUT_DIR / 'en_phrasal.jsonl', encoding='utf-8'):
        if line.strip():
            r = json.loads(line)
            if r.get('keep') is not None or r['id'] not in latest:
                latest[r['id']] = r
    for r in latest.values():
        if r.get('keep') is not True:
            continue
        particle = r['id'].split(' ', 1)[1]
        for sentence in r['sentences']:
            gap = re.sub(r'\b' + re.escape(particle) + r'\b', '___', sentence,
                         count=1, flags=re.I)
            if gap not in done and '___' in gap:
                gaps.append({'id': r['id'], 'sentence': gap})
    batches = [gaps[i:i + 25] for i in range(0, len(gaps), 25)]
    print(f'{len(gaps)} gaps in {len(batches)} batches', flush=True)
    judges = args.judges.split(',')
    lock = threading.Lock()
    stats = {'gaps': 0, 'failed': 0}

    def one(batch):
        lines = '\n'.join(f"{i + 1}. {g['sentence']}" for i, g in enumerate(batch))
        prompt = FITS_PROMPT.format(particles=PARTICLES, lines=lines)
        answers = []
        for judge in judges:
            sub = Pool.__new__(Pool)
            sub.lanes = [l for l in pool.lanes if l.name.split('#')[0] == judge]
            for l in sub.lanes:
                l.role = 'audit'
            lane, reply = sub.run('audit', prompt, attempts=30)
            by_n = {r.get('n'): r.get('fits') for r in reply if isinstance(r, dict)}
            if not all(isinstance(by_n.get(i + 1), list) for i in range(len(batch))):
                raise RuntimeError(f'{judge}: an answer is missing')
            answers.append((lane.model, [by_n[i + 1] for i in range(len(batch))]))
        with lock, open(out, 'a', encoding='utf-8') as f:
            for i, g in enumerate(batch):
                fits = set()
                for _, reply in answers:
                    fits |= {w for w in (reply[i] if isinstance(reply[i], list) else [])
                             if w in PARTICLES}
                f.write(json.dumps({**g, 'fits': sorted(fits),
                                    'by': [m for m, _ in answers]}) + '\n')
                stats['gaps'] += 1

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
    au = sub.add_parser('audit')
    au.add_argument('--lang', choices=['de', 'en'], required=True)
    au.add_argument('--judges', default='mistral-large,gpt-oss-120b')
    au.add_argument('--workers', type=int, default=3)
    au.add_argument('--lanes')
    au.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    rl = sub.add_parser('relations')
    rl.add_argument('pack')
    rl.add_argument('--lang', choices=['de', 'en'], required=True)
    rl.add_argument('--limit', type=int)
    rl.add_argument('--batch', type=int, default=30)
    rl.add_argument('--workers', type=int, default=6)
    rl.add_argument('--lanes')
    rl.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    pf = sub.add_parser('phrasal-fits')
    pf.add_argument('--judges', default='mistral-large,command-a')
    pf.add_argument('--workers', type=int, default=3)
    pf.add_argument('--lanes')
    pf.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    r = sub.add_parser('report')
    r.add_argument('--lang', choices=['de', 'en'], required=True)
    r.add_argument('--samples', type=int, default=8)
    args = parser.parse_args()
    {'propose': propose, 'report': report, 'phrasal': phrasal,
     'audit': audit, 'relations': relations,
     'phrasal-fits': phrasal_fits}[args.cmd](args)


if __name__ == '__main__':
    main()
