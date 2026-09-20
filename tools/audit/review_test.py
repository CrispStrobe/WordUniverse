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

    def test_verdicts_are_written_and_reported(self):
        from openai import OpenAI
        client = OpenAI(base_url=self.endpoint, api_key='stub')
        verdicts = review.judge(client, 'stub-model', ITEMS, 0.0)
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
            _FixedClient({'verdicts': [{'n': 1, 'keyed': False,
                                        'note': 'wrong'}]}),
            'stub', ITEMS, 0.0)
        self.assertFalse(verdicts[0]['keyed'])
        self.assertTrue(all(verdicts[1][field] for field in review.FIELDS))

    def test_resume_skips_what_was_judged(self):
        with tempfile.TemporaryDirectory() as directory:
            out = pathlib.Path(directory) / 'verdicts.jsonl'
            out.write_text(json.dumps({'item': ITEMS[0]}) + '\n')
            done = {review.key_of(json.loads(line)['item'])
                    for line in out.read_text().splitlines()}
            remaining = [item for item in ITEMS
                         if review.key_of(item) not in done]
            self.assertEqual(remaining, [ITEMS[1]])


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


if __name__ == '__main__':
    unittest.main()
