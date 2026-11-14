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
        self.streak = 0  # consecutive failures
        self.seconds = 0.0  # time spent in successful calls
        self.ok = 0

    def available(self):
        return time.time() >= self.parked_until

    def park(self, seconds):
        self.parked_until = max(self.parked_until, time.time() + seconds)

    def failed(self, seconds):
        # A lane that keeps failing is rested longer each time: a fixed short
        # park had every worker cycling through the same dead lanes (Nemotron,
        # Gemma: every call failed) and a run of 300 batches doing four an hour.
        self.failures += 1
        self.streak += 1
        self.park(min(3600, seconds * 2 ** (self.streak - 1)))

    def call(self, prompt, timeout=150):
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


def _families(exclude):
    if exclude is None:
        return set()
    return {exclude} if isinstance(exclude, str) else set(exclude)


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
                          and l.family not in _families(exclude_family)
                          and l.available()]
            if not candidates:
                time.sleep(15)
                continue
            # Least-recently-scheduled first spreads load across lanes.
            lane = min(candidates, key=lambda l: (l.next_at, random.random()))
            try:
                t0 = time.time()
                result = lane, parse_array(lane.call(prompt))
                lane.streak = 0
                lane.ok += 1
                lane.seconds += time.time() - t0
                return result
            except urllib.error.HTTPError as e:
                retry = e.headers.get('retry-after') if e.headers else None
                if e.code == 429:
                    # A rate limit says nothing about the lane's health: a
                    # flat pause. Escalating it parked the only fast lanes
                    # for an hour and stalled the run.
                    lane.failures += 1
                    lane.park(float(retry) if retry and retry.isdigit() else 60)
                elif e.code in (401, 402, 403, 404):
                    lane.failures += 1
                    lane.park(10 ** 9)  # not usable this run
                else:
                    lane.failed(30)
                tried.append(f'{lane.name}:{e.code}')
            except Exception as e:  # timeout, bad JSON, connection reset
                lane.failed(30)
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


def assign_roles(pool, proposers, verifiers):
    """Give the named lanes these roles for this run, and drop the rest.

    A lane named in both is split in two, one per role. For a task where
    only a few lanes answer fast — a batch of 30 took Mistral 6 s and Groq's
    Qwen 3 s, while four lanes timed out at 150 s and held a worker each
    time — this keeps the run on the ones that work.
    """
    import copy
    lanes = []
    for lane in pool.lanes:
        base = lane.name.split('#')[0]
        for role, names in (('propose', proposers), ('verify', verifiers)):
            if base in names:
                twin = copy.copy(lane)
                twin.lock = threading.Lock()
                twin.role = role
                lanes.append(twin)
    pool.lanes = lanes


def relations(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    if args.proposers:
        assign_roles(pool, set(args.proposers.split(',')),
                     set(args.verifiers.split(',')))
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
    print_lanes(pool)


# ─── Synonyms and antonyms a child can be asked for ──────────────────────
# The packs' synonym lists join every OdeNet/OpenThesaurus sense of a word
# with Wiktionary's, so "Preis" lists "Treffer" (the lottery sense) and
# "Käfig" "Bauer"; the antonyms pair "Salz" with "Zucker". Two judges of
# Three judges of different families each keep what fits the word's usual
# meaning, and only what all three keep is kept: with two, "Bein" still had
# "Arm" as its opposite. Only candidates that are themselves pack words are
# shown: the games never offer any other.

LEXREL_PROMPT = """You check word relations for a vocabulary game for children aged 8 to 12 learning {language}.
Each entry has a word, its word class, its usual meaning, candidate synonyms and candidate antonyms.

Keep a synonym only if, in the usual meaning given, a teacher would accept it as meaning the same thing:
same word class, and it could replace the word in a simple sentence. Drop words that match only a rare
sense (Preis/Treffer is the lottery sense, Käfig/Bauer the birdcage sense), broader or narrower terms
(Hund/Tier, Tier/Hund), merely related words, and words of another word class.
Keep an antonym only if it is a clear opposite of the usual meaning (heiß/kalt, kaufen/verkaufen,
hostile/friendly). Drop contrasts, pairs and companions (Salz/Zucker, Obst/Gemüse, bounce/clear).
When unsure, drop it.

Answer with JSON only, one object per entry, copying kept words exactly from the candidates:
[{{"id": "...", "synonyms": ["..."], "antonyms": ["..."]}}]

Entries:
{entries}"""


def _terms(values):
    out = []
    for v in values or []:
        t = v.get('word') if isinstance(v, dict) else v
        if isinstance(t, str) and t.strip():
            out.append(t.strip())
    return out


def lexrel_candidates(row, vocabulary):
    """The synonyms and antonyms of a row that are themselves pack words."""
    enrichment = json.loads(row['enrichment_json'] or '{}')
    word = row['word'].lower()

    def pick(key):
        seen, out = set(), []
        for t in _terms(enrichment.get(key)):
            k = t.lower()
            if k != word and k in vocabulary and k not in seen:
                seen.add(k)
                out.append(t)
        return out[:10]
    return pick('synonyms'), pick('antonyms')


def pack_vocabulary(db):
    return {r[0].lower() for r in db.execute(
        "SELECT word FROM words WHERE grade_level IS NOT NULL AND coalesce("
        "json_extract(metadata_json, '$.quality.vocabulary'), 1) = 1")}


def lexrel(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    if args.proposers:
        assign_roles(pool, set(args.proposers.split(',')),
                     set(args.verifiers.split(',')))
    language = 'German' if args.lang == 'de' else 'English'
    out = OUT_DIR / f'{args.lang}_lexrel.jsonl'
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    seen = {}
    if out.exists():
        for line in open(out, encoding='utf-8'):
            if line.strip():
                r = json.loads(line)
                seen[r['id']] = r['src']
    db = sqlite3.connect(args.pack)
    db.row_factory = sqlite3.Row
    vocabulary = pack_vocabulary(db)
    rows = db.execute(
        "SELECT id, original_id, word, word_type, article, enrichment_json, "
        "metadata_json FROM words WHERE grade_level IS NOT NULL AND coalesce("
        "json_extract(metadata_json, '$.quality.vocabulary'), 1) = 1 "
        "ORDER BY grade_level, id").fetchall()
    todo = []
    for row in rows:
        synonyms, antonyms = lexrel_candidates(row, vocabulary)
        if not synonyms and not antonyms:
            continue
        entry = relation_entry(row, args.lang)
        src = digest(entry)
        if seen.get(entry['id']) != src:
            todo.append(({**entry, 'synonyms': synonyms, 'antonyms': antonyms}, src))
    if args.limit:
        todo = todo[:args.limit]
    batches = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    print(f'{len(todo)} entries in {len(batches)} batches', flush=True)
    lock = threading.Lock()
    stats = {'entries': 0, 'synonyms': 0, 'antonyms': 0, 'failed': 0}

    def kept(answer, entry, key):
        allowed = {t.lower(): t for t in entry[key]}
        return {t.lower() for t in _terms(answer.get(key)) if t.lower() in allowed}

    def one(batch):
        entries = [e for e, _ in batch]
        prompt = LEXREL_PROMPT.format(
            language=language,
            entries=json.dumps(entries, ensure_ascii=False, indent=0))
        # Groq's Qwen, the only third family that answers, allows 8,000
        # tokens a minute — about two batches — so a call waits its turn
        # rather than failing the batch.
        first, a = pool.run('propose', prompt, attempts=60)
        second, b = pool.run('verify', prompt, exclude_family=first.family,
                             attempts=60)
        third, c = pool.run('verify', prompt, attempts=60,
                            exclude_family={first.family, second.family})
        answers = [{x.get('id'): x for x in r if isinstance(x, dict)}
                   for r in (a, b, c)]
        records = []
        for entry, src in batch:
            got = [by.get(entry['id']) for by in answers]
            if any(x is None for x in got):
                continue  # read again on the next run
            syn = set.intersection(*(kept(x, entry, 'synonyms') for x in got))
            ant = set.intersection(*(kept(x, entry, 'antonyms') for x in got))
            records.append({
                'id': entry['id'], 'word': entry['word'], 'src': src,
                'synonyms': [t for t in entry['synonyms'] if t.lower() in syn],
                'antonyms': [t for t in entry['antonyms'] if t.lower() in ant],
                'candidates': [len(entry['synonyms']), len(entry['antonyms'])],
                'by': [first.model, second.model, third.model]})
        with lock, open(out, 'a', encoding='utf-8') as f:
            for r in records:
                f.write(json.dumps(r, ensure_ascii=False) + '\n')
                stats['entries'] += 1
                stats['synonyms'] += len(r['synonyms'])
                stats['antonyms'] += len(r['antonyms'])

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
    print_lanes(pool)


# ─── A meaning a child can read ──────────────────────────────────────────
# German glosses come from Wiktionary and DWDS and are written for adults:
# Planet "…der sich um einen Stern bewegt und seine Umlaufbahn freigeräumt
# hat", Haut "…Wärmeregulierung". One family writes a gloss for a child (or
# keeps the one there if it already is one), another checks it is right for
# the usual meaning, readable at eight, and does not use the word itself.

KIDGLOSS_PROMPT = """You write word meanings for a {language} vocabulary app for children aged 7 to 10.
For each entry write the usual meaning of the word in ONE short {language} sentence or phrase of at most
12 words, using only common everyday words a child knows. Describe the meaning given in "gloss"
(the usual one), not a rare sense. Do not use the word itself or a word of its family.
Keep relations exact: "Vater des Vaters" is "der Vater von Papa oder Mama", not
"der Opa von Papa" (that is the great-grandfather). The gloss must name this word,
not a relative of it, a broader or narrower thing, or a part of it.
{style}
If the current gloss is already short, correct and easy for a child, return it unchanged.

Answer with JSON only: [{{"id": "...", "gloss": "..."}}]

Entries:
{entries}"""

KIDGLOSS_STYLE = {
    'de': 'Write like a children\'s dictionary: "Ein Tier mit Fell, das bellt." for Hund, '
          '"sehr müde sein und nicht mehr können" for erschöpft sein.',
    'en': 'Write like a children\'s dictionary: "An animal with fur that barks." for dog, '
          '"very tired" for exhausted.',
}

KIDGLOSS_VERIFY = """You check word meanings written for children aged 7 to 10 learning {language}.
For each entry, "ok" is true only if ALL hold:
- the gloss is correct for the usual meaning of the word (the "old" gloss shows the intended sense),
- read alone, it names exactly this word, not another one: "Opa von Papa oder Mama" is the
  great-grandfather, so it is wrong for Großvater; check relations, broader/narrower things and parts,
- a child of eight can understand every word of it,
- it does not contain the word itself or a word of its family,
- it is at most 12 words.

Answer with JSON only: [{{"id": "...", "ok": true|false}}]

Entries:
{entries}"""


def kidgloss(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    if args.proposers:
        assign_roles(pool, set(args.proposers.split(',')),
                     set(args.verifiers.split(',')))
    language = 'German' if args.lang == 'de' else 'English'
    out = OUT_DIR / f'{args.lang}_kidgloss.jsonl'
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
        "SELECT id, original_id, word, word_type, article, grade_level, "
        "enrichment_json, metadata_json FROM words WHERE grade_level "
        "BETWEEN 1 AND ? AND coalesce(json_extract(metadata_json, "
        "'$.quality.vocabulary'), 1) = 1 ORDER BY grade_level, id",
        (args.max_grade,)).fetchall()
    todo = []
    for row in rows:
        if row['word_type'] not in RELATION_TYPES:
            continue
        entry = relation_entry(row, args.lang)
        gloss = entry['meaning']
        if not gloss:
            continue
        metadata = json.loads(row['metadata_json'] or '{}')
        if args.only_long and len(gloss.split()) <= 12 \
                and not metadata.get('gloss_above_reader'):
            continue
        src = digest(entry)
        if seen.get(entry['id']) != src:
            todo.append(({'id': entry['id'], 'word': entry['word'],
                          'word_type': entry['word_type'], 'gloss': gloss}, src))
    if args.limit:
        todo = todo[:args.limit]
    batches = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    print(f'{len(todo)} entries in {len(batches)} batches', flush=True)
    lock = threading.Lock()
    stats = {'entries': 0, 'rewritten': 0, 'kept': 0, 'rejected': 0, 'failed': 0}

    def one(batch):
        entries = [e for e, _ in batch]
        proposer, proposals = pool.run('propose', KIDGLOSS_PROMPT.format(
            language=language, style=KIDGLOSS_STYLE[args.lang],
            entries=json.dumps(entries, ensure_ascii=False, indent=0)), attempts=30)
        by_id = {p.get('id'): p for p in proposals if isinstance(p, dict)}
        shown = []
        for entry in entries:
            g = (by_id.get(entry['id']) or {}).get('gloss')
            if isinstance(g, str) and g.strip():
                shown.append({'id': entry['id'], 'word': entry['word'],
                              'old': entry['gloss'], 'gloss': g.strip()})
        verifier, verdicts = pool.run('verify', KIDGLOSS_VERIFY.format(
            language=language,
            entries=json.dumps(shown, ensure_ascii=False, indent=0)),
            exclude_family=proposer.family, attempts=30)
        ok = {v.get('id'): v.get('ok') for v in verdicts if isinstance(v, dict)}
        src_of = {e['id']: src for e, src in batch}
        with lock, open(out, 'a', encoding='utf-8') as f:
            for item in shown:
                if not isinstance(ok.get(item['id']), bool):
                    continue
                record = {'id': item['id'], 'word': item['word'],
                          'src': src_of[item['id']], 'gloss': item['gloss'],
                          'old': item['old'], 'ok': ok[item['id']],
                          'by': proposer.model, 'checked_by': verifier.model}
                f.write(json.dumps(record, ensure_ascii=False) + '\n')
                stats['entries'] += 1
                if not record['ok']:
                    stats['rejected'] += 1
                elif record['gloss'] == record['old']:
                    stats['kept'] += 1
                else:
                    stats['rewritten'] += 1

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
    print_lanes(pool)


# ─── Sense: is the first meaning the one a child means? ──────────────────
#
# The children's glosses rewrite the leading meaning in easy words, but keep
# whichever meaning leads. "Kater" (grade 1) led with a hangover and had no
# other sense; the rewrite made the hangover easy to read. This pass asks
# whether the leading meaning is the one a child of the word's grade means,
# and if not, writes that one; a judge of another family confirms each change.

SENSE_PROMPT = """You check a {language} vocabulary app for children aged 6 to 11.
Each entry has a word, its word class, the school grade it is taught in, the
meaning the app shows first ("gloss") and the other meanings it lists ("other").

For each entry decide: is "gloss" the meaning a child of that grade most likely
means by this word? Example: for "Kater" a child means a male cat, not a
hangover; for "Maus" the animal, not a computer mouse; for "Bank" a bench to
sit on is as likely as a bank for money, so either is fine.

- If it is, answer {{"id": "...", "ok": true}}.
- If it is not, answer {{"id": "...", "ok": false, "gloss": "..."}} with the
  meaning the child means, in ONE short {language} sentence or phrase of at
  most 12 everyday words, without the word itself or a word of its family.
  {style}
Only say false when you are sure; a correct but less common reading of a word
a child also uses is fine.

Answer with ONE JSON array only, one object per entry: [{{"id": "...", "ok": true}}, ...]

Entries:
{entries}"""

SENSE_VERIFY = """You check meanings in a {language} vocabulary app for children aged 6 to 11.
For each entry a reviewer replaced the meaning shown first ("old") with "new".
"ok" is true only if ALL hold:
- "new" is the meaning a child of that grade most likely means by the word,
  and "old" was not (for "Kater": a male cat, not a hangover),
- "new" is correct, easy for a child, at most 12 words, and does not contain
  the word itself or a word of its family,
- read alone, "new" names exactly this word, not a relative of it ("Opa von
  Papa" is the great-grandfather, not the grandfather), nor a broader or
  narrower thing.

Answer with JSON only: [{{"id": "...", "ok": true|false}}]

Entries:
{entries}"""


def sense(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    if args.proposers:
        assign_roles(pool, set(args.proposers.split(',')),
                     set(args.verifiers.split(',')))
    language = 'German' if args.lang == 'de' else 'English'
    out = OUT_DIR / f'{args.lang}_sense.jsonl'
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
        "SELECT id, original_id, word, word_type, article, grade_level, "
        "enrichment_json, metadata_json FROM words WHERE grade_level "
        "BETWEEN 1 AND ? AND coalesce(json_extract(metadata_json, "
        "'$.quality.vocabulary'), 1) = 1 ORDER BY grade_level, id",
        (args.max_grade,)).fetchall()
    todo = []
    for row in rows:
        if row['word_type'] not in RELATION_TYPES:
            continue
        entry = relation_entry(row, args.lang)
        if not entry['meaning']:
            continue
        src = digest(entry)
        if seen.get(entry['id']) == src:
            continue
        defs = [d for d in json.loads(row['enrichment_json'] or '{}').get('definitions') or []
                if isinstance(d, str) and d.strip()]
        others = [d[:120] for d in defs[1:6] if d[:200] != entry['meaning']]
        todo.append(({'id': entry['id'], 'word': entry['word'],
                      'word_type': entry['word_type'], 'grade': row['grade_level'],
                      'gloss': entry['meaning'], 'other': others}, src))
    if args.limit:
        todo = todo[:args.limit]
    batches = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    print(f'{len(todo)} entries in {len(batches)} batches', flush=True)
    lock = threading.Lock()
    stats = {'entries': 0, 'kept': 0, 'changed': 0, 'rejected': 0, 'failed': 0}

    def one(batch):
        entries = [e for e, _ in batch]
        proposer, answers = pool.run('propose', SENSE_PROMPT.format(
            language=language, style=KIDGLOSS_STYLE[args.lang],
            entries=json.dumps(entries, ensure_ascii=False, indent=0)), attempts=30)
        by_id = {a.get('id'): a for a in answers if isinstance(a, dict)}
        if sum(1 for e in entries if isinstance((by_id.get(e['id']) or {}).get('ok'), bool)) \
                < len(entries) * 0.9:
            raise RuntimeError(f'{proposer.name}: answered too few entries')
        changes = []
        for e in entries:
            a = by_id.get(e['id']) or {}
            g = a.get('gloss')
            if a.get('ok') is False and isinstance(g, str) and g.strip() \
                    and g.strip() != e['gloss']:
                changes.append({'id': e['id'], 'word': e['word'], 'grade': e['grade'],
                                'old': e['gloss'], 'new': g.strip()})
        verdict, checker = {}, None
        if changes:
            checker, verdicts = pool.run('verify', SENSE_VERIFY.format(
                language=language,
                entries=json.dumps(changes, ensure_ascii=False, indent=0)),
                exclude_family=proposer.family, attempts=30)
            verdict = {v.get('id'): v.get('ok') for v in verdicts if isinstance(v, dict)}
        changed = {c['id']: c for c in changes}
        src_of = {e['id']: src for e, src in batch}
        with lock, open(out, 'a', encoding='utf-8') as f:
            for e in entries:
                a = by_id.get(e['id']) or {}
                if not isinstance(a.get('ok'), bool):
                    continue
                record = {'id': e['id'], 'word': e['word'], 'src': src_of[e['id']],
                          'ok': a['ok'], 'by': proposer.model}
                if e['id'] in changed:
                    if not isinstance(verdict.get(e['id']), bool):
                        continue
                    record.update(old=e['gloss'], gloss=changed[e['id']]['new'],
                                  confirmed=verdict[e['id']], checked_by=checker.model)
                f.write(json.dumps(record, ensure_ascii=False) + '\n')
                stats['entries'] += 1
                if a['ok']:
                    stats['kept'] += 1
                elif record.get('confirmed'):
                    stats['changed'] += 1
                else:
                    stats['rejected'] += 1

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
    print_lanes(pool)


# ─── Blind: does the gloss name its word? ────────────────────────────────
#
# The definitions quiz shows a gloss and asks which word it describes. A
# model-written gloss passed a check that saw word and gloss together, and
# "Opa von Papa oder Mama" passed for Großvater although it is the
# great-grandfather: a reader who knows the word reads the gloss as meant.
# This pass reads it the way the child does. A model sees only the gloss
# and the word class and names the words it describes; where the word (or
# one of its synonyms) is not among them, a judge of another family sees
# word and gloss and says whether the gloss is right, writing a new one if
# not, and a third model, blind again, has to find the word from that.

BLIND_GUESS = """A {language} children's dictionary gives these meanings. For each, name
the {language} words it most likely describes, best first, at most 4, as
dictionary forms (nouns without article). Read each meaning literally and
exactly, as a strict teacher would: "Mutter von Mama" is the grandmother, so
"Oma von Papa" is the great-grandmother; a part, a tool or a use of a thing is
not the thing.

Answer with JSON only: [{{"id": "...", "words": ["...", "..."]}}]

Entries:
{entries}"""

BLIND_JUDGE = """You check meanings in a {language} vocabulary app for children aged 6 to 11.
The app shows the meaning ("gloss") and asks the child which word it describes.
Someone who saw only the gloss guessed other words ("guesses"); "other" lists
the dictionary's meanings of the word.

"ok" is true if the gloss correctly describes the usual meaning of "word", so
that a child can find the word from it; the guesses may be near synonyms of it.
"ok" is false if it describes something else: a relative of it ("Opa von Papa
oder Mama" is the great-grandfather, not Großvater), a broader or narrower
thing, a part of it, the opposite, or is plainly wrong.
If false, also give "gloss": the right meaning in ONE short {language} sentence
or phrase of at most 12 everyday words, without the word itself or a word of its
family. {style}

Answer with JSON only: [{{"id": "...", "ok": true}}, {{"id": "...", "ok": false, "gloss": "..."}}]

Entries:
{entries}"""


def blind_norm(text):
    text = re.sub(r"[^\w\s-]", ' ', text or '').lower().split()
    while text and text[0] in ('der', 'die', 'das', 'the', 'a', 'an', 'to', 'sich'):
        text = text[1:]
    return ' '.join(text)


def blind_names(row):
    """The word and its synonyms, as a guess would name them."""
    enrichment = json.loads(row['enrichment_json'] or '{}')
    names = {blind_norm(row['word']), blind_norm(enrichment.get('primary_lemma') or '')}
    # An inflected form ("hatte", "ist") is found when its lemma is named.
    if 'lemma' in row.keys() and row['lemma']:
        names.add(blind_norm(row['lemma']))
    for s in enrichment.get('synonyms') or []:
        if isinstance(s, str):
            names.add(blind_norm(s))
    names.discard('')
    return names


def blind_hit(guesses, names):
    return any(blind_norm(g) in names for g in guesses if isinstance(g, str))


def blind(args):
    env = load_env(args.env_file)
    pool = Pool(env, only=set(args.lanes.split(',')) if args.lanes else None)
    assign_roles(pool, set(args.guessers.split(',')), set(args.judges.split(',')))
    language = 'German' if args.lang == 'de' else 'English'
    out = OUT_DIR / f'{args.lang}_blind.jsonl'
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    seen = set()
    if out.exists():
        for line in open(out, encoding='utf-8'):
            if line.strip():
                r = json.loads(line)
                seen.add((r['id'], r['gloss']))
    db = sqlite3.connect(args.pack)
    db.row_factory = sqlite3.Row
    rows = db.execute(
        "SELECT id, original_id, word, word_type, article, grade_level, "
        "enrichment_json, metadata_json FROM words WHERE grade_level "
        "BETWEEN 1 AND ? AND coalesce(json_extract(metadata_json, "
        "'$.quality.vocabulary'), 1) = 1 AND json_extract(metadata_json, "
        "'$.gloss_source') IN ('llm-reviewed', 'llm-sense') "
        "ORDER BY grade_level, id", (args.max_grade,)).fetchall()
    todo = []
    for row in rows:
        entry = relation_entry(row, args.lang)
        gloss = blind_gloss(entry['meaning'])
        if not gloss or (entry['id'], gloss) in seen:
            continue
        defs = [d for d in json.loads(row['enrichment_json'] or '{}').get('definitions') or []
                if isinstance(d, str) and d.strip()]
        todo.append({'id': entry['id'], 'word': entry['word'],
                     'word_type': entry['word_type'], 'gloss': gloss,
                     'other': [d[:120] for d in defs[1:5]],
                     'names': blind_names(row)})
    if args.ids:
        wanted = set(args.ids.split(','))
        todo = [e for e in todo if e['id'] in wanted or e['word'] in wanted]
    if args.limit:
        todo = todo[:args.limit]
    batches = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    print(f'{len(todo)} entries in {len(batches)} batches', flush=True)
    lock = threading.Lock()
    stats = {'entries': 0, 'found': 0, 'judged_ok': 0, 'fixed': 0, 'wrong': 0, 'failed': 0}

    def guess(entries, exclude=None):
        shown = [{'id': e['id'], 'word_type': e['word_type'], 'gloss': e['gloss']}
                 for e in entries]
        lane, answers = pool.run('propose', BLIND_GUESS.format(
            language=language, entries=json.dumps(shown, ensure_ascii=False, indent=0)),
            exclude_family=exclude, attempts=30)
        by_id = {a.get('id'): a.get('words') for a in answers if isinstance(a, dict)}
        if sum(1 for e in entries if isinstance(by_id.get(e['id']), list)) < len(entries) * 0.9:
            raise RuntimeError(f'{lane.name}: guessed too few entries')
        return lane, by_id

    def one(batch):
        guesser, guesses = guess(batch)
        missed = [e for e in batch if isinstance(guesses.get(e['id']), list)
                  and not blind_hit(guesses[e['id']], e['names'])]
        verdict, fixes, judge, second = {}, {}, None, {}
        if missed:
            shown = [{'id': e['id'], 'word': e['word'], 'gloss': e['gloss'],
                      'guesses': guesses[e['id']][:4], 'other': e['other']} for e in missed]
            judge, verdicts = pool.run('verify', BLIND_JUDGE.format(
                language=language, style=KIDGLOSS_STYLE[args.lang],
                entries=json.dumps(shown, ensure_ascii=False, indent=0)),
                exclude_family=guesser.family, attempts=30)
            for v in verdicts:
                if isinstance(v, dict) and isinstance(v.get('ok'), bool):
                    verdict[v.get('id')] = v['ok']
                    if v['ok'] is False and isinstance(v.get('gloss'), str) and v['gloss'].strip():
                        fixes[v.get('id')] = v['gloss'].strip()
            if fixes:
                again = [dict(e, gloss=fixes[e['id']]) for e in missed if e['id'] in fixes]
                _, second = guess(again, exclude=judge.family)
        with lock, open(out, 'a', encoding='utf-8') as f:
            for e in batch:
                g = guesses.get(e['id'])
                if not isinstance(g, list):
                    continue
                record = {'id': e['id'], 'word': e['word'], 'gloss': e['gloss'],
                          'guesses': g[:4], 'by': guesser.model}
                if e in missed:
                    if e['id'] not in verdict:
                        continue
                    record.update(ok=verdict[e['id']], checked_by=judge.model)
                    if e['id'] in fixes:
                        record['fix'] = fixes[e['id']]
                        record['fix_guesses'] = (second.get(e['id']) or [])[:4]
                        record['fix_found'] = blind_hit(record['fix_guesses'], e['names'])
                else:
                    record['ok'] = True
                f.write(json.dumps(record, ensure_ascii=False) + '\n')
                stats['entries'] += 1
                if e not in missed:
                    stats['found'] += 1
                elif record['ok']:
                    stats['judged_ok'] += 1
                elif record.get('fix_found'):
                    stats['fixed'] += 1
                else:
                    stats['wrong'] += 1

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
    print_lanes(pool)


def blind_gloss(gloss):
    """The gloss as the blind pass keys it: finish_glosses may have added a stop."""
    return (gloss or '').strip().rstrip('.').strip()


def print_lanes(pool):
    print('lanes:', ', '.join(
        f'{l.name} {l.ok}ok/{l.failures}fail'
        + (f' {l.seconds / l.ok:.0f}s' if l.ok else '')
        for l in pool.lanes if l.calls), flush=True)


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
                if l.strip() and json.loads(l).get('round', 1) == args.round}
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
                f.write(json.dumps({**g, 'fits': sorted(fits), 'round': args.round,
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
    rl.add_argument('--proposers', help='lanes to propose with, e.g. mistral-large,qwen3.8-27b')
    rl.add_argument('--verifiers', default='magistral-medium,mistral-medium,command-a,iceman,qwen3.8-27b')
    rl.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    lx = sub.add_parser('lexrel')
    lx.add_argument('pack')
    lx.add_argument('--lang', choices=['de', 'en'], required=True)
    lx.add_argument('--limit', type=int)
    lx.add_argument('--batch', type=int, default=20)
    lx.add_argument('--workers', type=int, default=8)
    lx.add_argument('--lanes')
    lx.add_argument('--proposers', default='mistral-large,qwen3.8-27b')
    lx.add_argument('--verifiers', default='iceman,magistral-medium,qwen3.8-27b,gpt-oss-120b,command-a')
    lx.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    kg = sub.add_parser('kidgloss')
    kg.add_argument('pack')
    kg.add_argument('--lang', choices=['de', 'en'], required=True)
    kg.add_argument('--max-grade', type=int, default=4)
    kg.add_argument('--only-long', action='store_true',
                    help='only glosses over 12 words or marked above the reader')
    kg.add_argument('--limit', type=int)
    kg.add_argument('--batch', type=int, default=20)
    kg.add_argument('--workers', type=int, default=4)
    kg.add_argument('--lanes')
    kg.add_argument('--proposers', default='mistral-large')
    kg.add_argument('--verifiers', default='iceman,gpt-oss-120b,gemini-3-flash,nemotron-ultra,longcat-2.5')
    kg.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    se = sub.add_parser('sense', help='is the meaning shown first the one a child means?')
    se.add_argument('pack')
    se.add_argument('--lang', choices=['de', 'en'], required=True)
    se.add_argument('--max-grade', type=int, default=13)
    se.add_argument('--limit', type=int)
    se.add_argument('--batch', type=int, default=50)
    se.add_argument('--workers', type=int, default=6)
    se.add_argument('--lanes')
    se.add_argument('--proposers', default='mistral-large,mistral-medium')
    se.add_argument('--verifiers', default='iceman,gpt-oss-120b,gemini-3-flash,nemotron-ultra,longcat-2.5')
    se.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    bl = sub.add_parser('blind', help='does a model-written gloss, read alone, name its word?')
    bl.add_argument('pack')
    bl.add_argument('--lang', choices=['de', 'en'], required=True)
    bl.add_argument('--max-grade', type=int, default=13)
    bl.add_argument('--ids', help='comma-separated entry ids or words, for a trial')
    bl.add_argument('--limit', type=int)
    bl.add_argument('--batch', type=int, default=40)
    bl.add_argument('--workers', type=int, default=6)
    bl.add_argument('--lanes')
    bl.add_argument('--guessers', default='mistral-large,mistral-medium,gemini-3-flash')
    bl.add_argument('--judges', default='iceman,gpt-oss-120b,gemini-3-flash,nemotron-ultra,longcat-2.5')
    bl.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    pf = sub.add_parser('phrasal-fits')
    pf.add_argument('--judges', default='mistral-large,command-a')
    pf.add_argument('--round', type=int, default=1,
                    help='another round with other judges; rounds are united')
    pf.add_argument('--workers', type=int, default=3)
    pf.add_argument('--lanes')
    pf.add_argument('--env-file', default=str(pathlib.Path.home() / 'code' / '.env'))
    r = sub.add_parser('report')
    r.add_argument('--lang', choices=['de', 'en'], required=True)
    r.add_argument('--samples', type=int, default=8)
    args = parser.parse_args()
    {'propose': propose, 'report': report, 'phrasal': phrasal,
     'audit': audit, 'relations': relations,
     'phrasal-fits': phrasal_fits, 'lexrel': lexrel,
     'kidgloss': kidgloss, 'sense': sense, 'blind': blind}[args.cmd](args)


if __name__ == '__main__':
    main()
