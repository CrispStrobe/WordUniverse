#!/usr/bin/env python3
"""Checks review.py against a stub endpoint, so the plumbing is tested without
a model — and without pretending a stub says anything about content.

    python3 tools/audit/review_test.py
"""
import http.server
import importlib.util
import json
import pathlib
import tempfile
import threading
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('review', HERE / 'review.py')
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)

ITEMS = [
    {'game': 'definition_quiz', 'prompt': 'A large stream of water.',
     'options': ['river', 'table'], 'answer': 'river'},
    {'game': 'grossstadt', 'prompt': 'DU [lesst]', 'answer': 'klein',
     'notes': {'rule': 'Verben im Satz'}},
]


class Stub(http.server.BaseHTTPRequestHandler):
    """Flags the second item of every batch, so the path is visible."""

    def do_POST(self):
        length = int(self.headers['Content-Length'])
        body = json.loads(self.rfile.read(length))
        prompt = body['messages'][-1]['content']
        count = prompt.count('game: ')
        verdicts = [
            {'n': number, 'answerable': True, 'keyed': True,
             'grammatical': number != 2, 'appropriate': True,
             'note': '' if number != 2 else 'du liest, not du lesst'}
            for number in range(1, count + 1)
        ]
        payload = json.dumps({
            'choices': [{'message': {
                'content': json.dumps({'verdicts': verdicts})}}]
        }).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_):
        pass


class ReviewTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.HTTPServer(('127.0.0.1', 0), Stub)
        cls.thread = threading.Thread(target=cls.server.serve_forever,
                                      daemon=True)
        cls.thread.start()
        cls.endpoint = f'http://127.0.0.1:{cls.server.server_port}/v1'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    @staticmethod
    def _pool(client, label='stub'):
        return review.Pool([review.Lane(client, 'stub-model', label, 0.0)],
                           patience=1.0)

    def test_verdicts_are_written_and_reported(self):
        from openai import OpenAI
        client = OpenAI(base_url=self.endpoint, api_key='stub')
        verdicts = review.judge(self._pool(client), ITEMS, 0.0)
        self.assertEqual(len(verdicts), 2)
        self.assertTrue(verdicts[0]['grammatical'])
        self.assertFalse(verdicts[1]['grammatical'],
                         'a flag from the model has to survive the round trip')
        self.assertIn('du liest', verdicts[1]['note'])
        self.assertEqual(verdicts[1]['item']['game'], 'grossstadt',
                         'a verdict has to carry the item it judged')

    def test_a_missing_verdict_counts_as_unflagged(self):
        """A model that answers about fewer items must not flag the rest."""
        verdicts = review.judge(
            self._pool(_FixedClient({'verdicts': [{'n': 1, 'keyed': False,
                                                   'note': 'wrong'}]})),
            ITEMS, 0.0)
        self.assertFalse(verdicts[0]['keyed'])
        self.assertTrue(all(verdicts[1][field] for field in review.FIELDS))


    def test_a_rate_limited_lane_steps_aside_for_another(self):
        """Two lanes, one always 429: the work still gets done."""
        angry = _FailingClient('Error code: 429 - rate limited, '
                               'retry_after_seconds: 1')
        calm = _FixedClient({'verdicts': [{'n': 1}, {'n': 2}]})
        pool = review.Pool([
            review.Lane(angry, 'busy-model', 'busy', 0.0),
            review.Lane(calm, 'free-model', 'free', 0.0),
        ], patience=5.0)
        verdicts = review.judge(pool, ITEMS, 0.0, attempts=4)
        self.assertEqual(len(verdicts), 2)
        self.assertGreater(
            next(lane for lane in pool._lanes if lane.label == 'busy').failures,
            0, 'the rate-limited lane has to have been parked')

    def test_every_lane_parked_gives_up_rather_than_hangs(self):
        angry = _FailingClient('Error code: 429 - rate limited')
        pool = review.Pool(
            [review.Lane(angry, 'busy-model', 'busy', 0.0)], patience=0.2)
        self.assertEqual(review.judge(pool, ITEMS, 0.0, attempts=3), [])

    def test_an_answer_with_no_choices_parks_the_lane_and_moves_on(self):
        # OpenRouter answers 200 with an error body when a free model is out
        # of capacity; the SDK leaves choices None and indexing it threw,
        # which retired a lane that was only busy.
        empty = _EmptyChoicesClient(
            {'message': 'upstream provider returned no response'})
        calm = _FixedClient({'verdicts': [{'n': 1}, {'n': 2}]})
        lanes = [
            review.Lane(empty, 'nemotron', 'nemotron', 0.0),
            review.Lane(calm, 'free-model', 'free', 0.0),
        ]
        pool = review.Pool(lanes, patience=5.0)
        self.assertEqual(len(review.judge(pool, ITEMS, 0.0, attempts=4)), 2)
        self.assertFalse(lanes[0].retired,
                         'one empty answer is not a reason to retire a lane')
        self.assertGreater(lanes[0].failures, 0)

    def test_a_lane_that_keeps_answering_with_nothing_is_retired(self):
        empty = _EmptyChoicesClient(None)
        lane = review.Lane(empty, 'nemotron', 'nemotron', 0.0)
        pool = review.Pool([lane], patience=30.0)
        review.judge(pool, ITEMS, 0.0, attempts=8)
        self.assertTrue(lane.retired)

    def test_two_replicas_use_two_different_lanes(self):
        # One model's verdict is an opinion; the same batch judged twice by
        # two models is something that can be compared. Four rounds of review
        # could not be, because each batch went to whichever lane was free.
        a = _FixedClient({'verdicts': [{'n': 1}, {'n': 2}]})
        b = _FixedClient({'verdicts': [{'n': 1, 'keyed': False}, {'n': 2}]})
        pool = review.Pool([
            review.Lane(a, 'model-a', 'lane-a', 0.0),
            review.Lane(b, 'model-b', 'lane-b', 0.0),
        ], patience=5.0)
        rows = review.judge_repeatedly(pool, ITEMS, 0.0, replicas=2)
        self.assertEqual(len(rows), 4, 'two items judged twice')
        self.assertEqual({row['lane'] for row in rows}, {'lane-a', 'lane-b'})

    def test_a_verdict_records_which_lane_made_it(self):
        pool = review.Pool([
            review.Lane(_FixedClient({'verdicts': [{'n': 1}, {'n': 2}]}),
                        'model-a', 'lane-a', 0.0),
        ], patience=5.0)
        rows = review.judge(pool, ITEMS, 0.0)
        self.assertTrue(all(row['lane'] == 'lane-a' for row in rows))

    def test_one_lane_cannot_supply_two_replicas(self):
        # Asked for two opinions with only one lane, it gives the one it has
        # rather than asking the same model twice and calling that agreement.
        pool = review.Pool([
            review.Lane(_FixedClient({'verdicts': [{'n': 1}, {'n': 2}]}),
                        'model-a', 'lane-a', 0.0),
        ], patience=0.2)
        rows = review.judge_repeatedly(pool, ITEMS, 0.0, replicas=2)
        self.assertEqual(len(rows), 2)

    def test_json_in_a_fence_is_still_json(self):
        fenced = '```json\n{"verdicts": [{"n": 1, "keyed": false}]}\n```'
        self.assertEqual(review.parse_verdicts(fenced),
                         [{'n': 1, 'keyed': False}])
        self.assertEqual(review.parse_verdicts('here you go: '
                                               '{"verdicts": []}'), [])
        self.assertIsNone(review.parse_verdicts('I could not do that'))

    def test_retry_after_is_read_when_the_provider_sends_one(self):
        self.assertEqual(
            review.retry_after('429 ... retry_after_seconds: 17 ...'), 17)
        self.assertIsNone(review.retry_after('500 server error'))

    def test_resume_skips_what_was_judged(self):
        with tempfile.TemporaryDirectory() as directory:
            out = pathlib.Path(directory) / 'verdicts.jsonl'
            out.write_text(json.dumps({'item': ITEMS[0]}) + '\n')
            done = {review.key_of(json.loads(line)['item'])
                    for line in out.read_text().splitlines()}
            remaining = [item for item in ITEMS
                         if review.key_of(item) not in done]
            self.assertEqual(remaining, [ITEMS[1]])


class _FailingClient:
    """Always raises, the way a rate-limited provider does."""

    def __init__(self, message):
        self.chat = self
        self.completions = self
        self._message = message

    def create(self, **_):
        raise RuntimeError(self._message)


class _FixedClient:
    """The smallest thing that looks like the OpenAI client."""

    def __init__(self, payload):
        self.chat = self
        self.completions = self
        self._payload = payload

    def create(self, **_):
        content = json.dumps(self._payload)
        return type('R', (), {'choices': [type('C', (), {
            'message': type('M', (), {'content': content})()})()]})()


class _EmptyChoicesClient:
    """A 200 with no choices, the way OpenRouter reports an upstream fault."""

    def __init__(self, error):
        self.chat = self
        self.completions = self
        self._error = error

    def create(self, **_):
        return type('R', (), {'choices': None, 'error': self._error})()


if __name__ == '__main__':
    unittest.main()
