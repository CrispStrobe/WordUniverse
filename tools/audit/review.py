#!/usr/bin/env python3
"""Have a model read the generated questions, and say which ones are wrong.

    tools/audit/dump.sh --lang de --pack-de pack.db --count 200 --json --out items.jsonl
    python3 tools/audit/review.py items.jsonl --model <name> --out verdicts.jsonl
    python3 tools/audit/review.py items.jsonl --report verdicts.jsonl

The contract test checks that an item is *well formed*: options distinct, the
keyed answer among them, the prompt not giving it away. It cannot tell "du
sprichst" from "du sprechst", or notice that a distractor is also a correct
answer, or that a sentence is nonsense. Reading catches those, at about a
hundred items an hour; the games can produce a hundred thousand.

So this asks a model, item by item, four questions a teacher would ask:

    answerable        can the question be answered from what is shown?
    correctly keyed   is the marked answer right, and the others wrong?
    grammatical       is every sentence correct in its language?
    appropriate       would you put this in front of a ten-year-old?

It flags rather than fixes. The output is a triage list for a person — and
the point of the rubric is that a flag is a *claim* with a reason attached,
which can be read and dismissed in seconds when the model is wrong.

Any OpenAI-compatible endpoint: --endpoint http://localhost:11434/v1 for a
local server, or a hosted one with --api-key-env. Nothing is sent anywhere
unless you pass --model; --dry-run prints what would be asked.
"""
import argparse
import json
import os
import pathlib
import re
import sys
import threading
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor

RUBRIC = """You are checking exercises from a German/English vocabulary app \
for children in school years 1-6. For each numbered item, judge only what is \
shown.

Some games are not multiple choice: a word-search hands out a letter grid, a \
snake traces letters, a memory game turns over tiles. For those the item \
gives the word the game uses and no options, and that is complete — judge \
whether the word itself suits the game and the age, not whether options are \
missing.

For each item answer four questions:
- answerable: can a learner answer it from the prompt and options alone?
- keyed: is the marked answer correct, and is every other option wrong?
- grammatical: is every sentence and form correct in its language?
- appropriate: is the content suitable for a child of about ten?

Reply with JSON only: {"verdicts": [{"n": 1, "answerable": true, "keyed": \
true, "grammatical": true, "appropriate": true, "note": ""}, ...]}. Set a \
field to false only when you are confident, and then put a short reason in \
"note" naming the problem. An item that is merely dull or obscure is still \
answerable, keyed, grammatical and appropriate."""

FIELDS = ('answerable', 'keyed', 'grammatical', 'appropriate')


def render(item, number):
    title = item.get('title')
    lines = [f'{number}. game: {item.get("game")}'
             + (f' — "{title}", as the menu names it' if title else '')]
    lines.append(f'   prompt: {item.get("prompt", "")}')
    options = item.get('options') or []
    if options:
        lines.append('   options: ' + ' | '.join(options))
    if item.get('answer') is not None:
        lines.append(f'   marked correct: {item["answer"]}')
    notes = item.get('notes') or {}
    if notes:
        lines.append('   (data: ' + ', '.join(
            f'{key}={value}' for key, value in notes.items()) + ')')
    return '\n'.join(lines)


def batches(items, size):
    for start in range(0, len(items), size):
        yield items[start:start + size]



class Lane:
    """One key on one model, with its own pace and its own cooldown.

    Free tiers rate-limit per key *and* per model, and they do it by
    returning 429 rather than by telling you the limit. So a lane carries the
    earliest time it may be used again: a 429 parks it (honouring Retry-After
    when the provider sends one), everything else waits out a minimum
    interval. Work goes to whichever lane comes free first, which is what
    turns three rate-limited free models into one usable one.
    """

    def __init__(self, client, model, label, min_interval):
        self.client = client
        self.model = model
        self.label = label
        self.min_interval = min_interval
        self.ready_at = 0.0
        self.failures = 0
        self.judged = 0
        self.retired = False

    def parked(self, seconds, reason):
        self.ready_at = time.monotonic() + seconds
        self.failures += 1
        return f'{self.label}: {reason}, back in {seconds:.0f}s'

    def used(self):
        self.ready_at = time.monotonic() + self.min_interval
        self.failures = 0

    def retire(self):
        """Out for the rest of the run — a refusal repeats."""
        self.ready_at = float('inf')
        self.retired = True


class Pool:
    """Hands out lanes, one at a time, waiting when they are all parked."""

    def __init__(self, lanes, patience):
        self._lanes = lanes
        self._lock = threading.Lock()
        self._patience = patience

    def take(self):
        deadline = time.monotonic() + self._patience
        while True:
            with self._lock:
                if all(lane.retired for lane in self._lanes):
                    return None
                lane = min(self._lanes, key=lambda candidate: candidate.ready_at)
                wait = lane.ready_at - time.monotonic()
                if wait <= 0:
                    lane.ready_at = time.monotonic() + lane.min_interval
                    return lane
            if time.monotonic() > deadline:
                return None
            time.sleep(min(wait, 5))

    def report(self):
        return ', '.join(f'{lane.label}: {lane.judged}' for lane in self._lanes
                         if lane.judged)


def retry_after(error):
    """Seconds the provider asked for, or None."""
    match = re.search(r"retry.after[^0-9]{0,12}(\d+)", str(error), re.I)
    return int(match.group(1)) if match else None


def judge(pool, batch, temperature, attempts=6):
    prompt = '\n\n'.join(render(item, i + 1) for i, item in enumerate(batch))
    for _ in range(attempts):
        lane = pool.take()
        if lane is None:
            print('\n  every lane is rate-limited; giving these up')
            return []
        try:
            response = lane.client.chat.completions.create(
                model=lane.model,
                temperature=temperature,
                messages=[
                    {'role': 'system', 'content': RUBRIC},
                    {'role': 'user', 'content': prompt},
                ],
                response_format={'type': 'json_object'},
            )
            verdicts = parse_verdicts(response.choices[0].message.content or '')
            if verdicts is None:
                print('\n  ' + lane.parked(10, 'answered with something that '
                                            'is not JSON'))
                continue
            lane.used()
            lane.judged += len(batch)
            return stitch(batch, verdicts)
        except Exception as error:  # noqa: BLE001 - any transport problem
            text = str(error)
            transient = any(code in text for code in
                            ('429', '500', '502', '503', '504', '529',
                             'overloaded', 'timeout', 'Connection'))
            if not transient:
                # A refusal is about the lane, not the batch: a model that is
                # gated, misspelled or out of credit says so every time.
                print(f'\n  {lane.label}: {type(error).__name__}: '
                      f'{text[:160]} — retiring this lane')
                lane.retire()
                continue
            wait = retry_after(error) or min(2 ** lane.failures * 5, 120)
            print('\n  ' + lane.parked(wait, 'rate-limited'))
    return []


def parse_verdicts(text):
    """The verdict list, or None when the model did not answer in JSON.

    Models wrap JSON in ```fences and prepend commentary; neither is worth
    losing a batch over.
    """
    body = text.strip()
    if body.startswith('```'):
        body = body.split('```', 2)[1]
        if body.lstrip().lower().startswith('json'):
            body = body.lstrip()[4:]
    if not body.lstrip().startswith('{'):
        start, end = body.find('{'), body.rfind('}')
        if start == -1 or end == -1:
            return None
        body = body[start:end + 1]
    try:
        return json.loads(body).get('verdicts') or []
    except json.JSONDecodeError:
        return None


def stitch(batch, verdicts):
    """Verdicts back onto the items they judged, defaulting to unflagged."""
    by_number = {int(v.get('n', 0)): v for v in verdicts if isinstance(v, dict)}
    return [
        {
            'item': item,
            **{field: bool(by_number.get(index, {}).get(field, True))
               for field in FIELDS},
            'note': str(by_number.get(index, {}).get('note') or ''),
        }
        for index, item in enumerate(batch, start=1)
    ]


def key_of(item):
    return json.dumps([item.get('game'), item.get('prompt'),
                       item.get('answer')], ensure_ascii=False)


def report(path, samples):
    flagged = defaultdict(list)
    total = 0
    for line in pathlib.Path(path).read_text().splitlines():
        if not line.strip():
            continue
        verdict = json.loads(line)
        total += 1
        for field in FIELDS:
            if not verdict.get(field, True):
                flagged[(verdict['item'].get('game'), field)].append(verdict)
    print(f'{path}: {total} items reviewed, '
          f'{sum(len(v) for v in flagged.values())} flags\n')
    if not flagged:
        print('  nothing flagged')
        return
    counts = Counter({key: len(value) for key, value in flagged.items()})
    for (game, field), count in counts.most_common():
        print(f'{game} — not {field}: {count}')
        for verdict in flagged[(game, field)][:samples]:
            item = verdict['item']
            print(f'    {item.get("prompt")!r} → {item.get("answer")!r}')
            if verdict.get('note'):
                print(f'      {verdict["note"]}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('items', type=pathlib.Path,
                        help='JSONL from tools/audit/dump.sh --json')
    parser.add_argument('--model', help='one model, or several separated by '
                        'commas: the work is spread over all of them')
    parser.add_argument('--endpoint', default=os.environ.get(
        'WU_REVIEW_ENDPOINT', 'https://api.openai.com/v1'))
    parser.add_argument('--api-key-env', default='WU_REVIEW_API_KEY',
                        help='environment variable holding the key, or '
                             'several separated by commas — a lane is opened '
                             'for every key on every model')
    parser.add_argument('--pace', type=float, default=3.0, metavar='SECONDS',
                        help='shortest gap between two requests on the same '
                             'lane (default 3s, which free tiers tolerate)')
    parser.add_argument('--lane', action='append', default=[],
                        metavar='URL|KEY_ENV|MODEL',
                        help='one lane, spelled out; repeatable, and mixes '
                             'providers in a single run')
    parser.add_argument('--patience', type=float, default=180.0,
                        metavar='SECONDS',
                        help='how long to wait when every lane is parked')
    parser.add_argument('--out', type=pathlib.Path)
    parser.add_argument('--report', type=pathlib.Path,
                        help='summarise an existing verdict file and stop')
    parser.add_argument('--batch', type=int, default=10)
    parser.add_argument('--concurrency', type=int, default=4)
    parser.add_argument('--limit', type=int)
    parser.add_argument('--temperature', type=float, default=0.0)
    parser.add_argument('--samples', type=int, default=4)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--sheet', type=int, metavar='PER_GAME',
                        help='write a review sheet for a person instead: this '
                             'many items per game, spread across the file')
    args = parser.parse_args()

    if args.report:
        report(args.report, args.samples)
        return 0

    items = []
    for line in args.items.read_text().splitlines():
        line = line.strip()
        if not line.startswith('{'):
            continue  # a dump written as text, or its section headers
        items.append(json.loads(line))
    if not items:
        sys.exit(f'{args.items}: no JSON items — dump with --json')
    if args.limit:
        items = items[:args.limit]

    done = set()
    if args.out and args.out.exists():
        for line in args.out.read_text().splitlines():
            if line.strip():
                done.add(key_of(json.loads(line)['item']))
        items = [item for item in items if key_of(item) not in done]
        print(f'{len(done)} already reviewed; {len(items)} to go')

    if args.sheet:
        # A person reads faster with the games kept together and the items
        # spread across the whole file rather than taken from the front.
        by_game = defaultdict(list)
        for item in items:
            by_game[item.get('game')].append(item)
        written = 0
        lines = []
        for game in sorted(by_game):
            chosen = by_game[game]
            step = max(1, len(chosen) // args.sheet)
            lines.append(f'\n══ {game} ' + '═' * 40)
            for item in chosen[::step][:args.sheet]:
                written += 1
                lines.append(f'\n[{written}]  ' + render(item, written)
                             .split('\n', 1)[1].strip())
                lines.append('     verdict: ')
        lines.append(f'\n{written} items. Mark a verdict on anything wrong: '
                     'not answerable / wrongly keyed / bad grammar /\n'
                     'not for a child — and say why in a few words.')
        text = '\n'.join(lines)
        if args.out:
            args.out.write_text(text)
            print(f'wrote {written} items to {args.out}')
        else:
            print(text)
        return 0

    if args.dry_run or not (args.model or args.lane):
        print(RUBRIC)
        print('\n--- one batch would look like ---\n')
        print('\n\n'.join(render(item, i + 1)
                          for i, item in enumerate(items[:args.batch])))
        print(f'\n{len(items)} items, {args.batch} per request '
              f'= {(len(items) + args.batch - 1) // args.batch} requests')
        return 0

    try:
        from openai import OpenAI
    except ImportError:
        sys.exit('pip install openai')

    lanes = []
    for spec in args.lane:
        url, key_env, model = [part.strip() for part in spec.split('|')]
        key = os.environ.get(key_env)
        if not key:
            print(f'  {key_env} is not set; skipping {model}')
            continue
        lanes.append(Lane(OpenAI(base_url=url, api_key=key), model,
                          f'{model} @ {url.split("//")[-1].split("/")[0]}',
                          args.pace))
    for key_env in [name.strip() for name in args.api_key_env.split(',')
                    if name.strip()]:
        key = os.environ.get(key_env)
        if not key:
            print(f'  {key_env} is not set; skipping it')
            continue
        client = OpenAI(base_url=args.endpoint, api_key=key)
        for model in [name.strip() for name in (args.model or '').split(',')
                      if name.strip()]:
            label = model if len(args.api_key_env.split(',')) == 1 \
                else f'{model} via {key_env}'
            lanes.append(Lane(client, model, label, args.pace))
    if not lanes:
        sys.exit(f'no usable key: set {args.api_key_env}')
    print(f'{len(lanes)} lane(s): '
          + ', '.join(lane.label for lane in lanes))
    pool = Pool(lanes, args.patience)

    out = args.out or args.items.with_suffix('.verdicts.jsonl')
    written = 0
    with out.open('a') as handle:
        with ThreadPoolExecutor(max_workers=args.concurrency) as workers:
            for verdicts in workers.map(
                    lambda batch: judge(pool, batch, args.temperature),
                    list(batches(items, args.batch))):
                for verdict in verdicts:
                    handle.write(json.dumps(verdict, ensure_ascii=False) + '\n')
                    written += 1
                handle.flush()
                print(f'  {written}/{len(items)}', end='\r', flush=True)
    print(f'\nwrote {written} verdicts to {out}   [{pool.report()}]')
    report(out, args.samples)
    return 0


if __name__ == '__main__':
    sys.exit(main())
