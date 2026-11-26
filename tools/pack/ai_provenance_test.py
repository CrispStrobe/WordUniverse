"""No network/model calls: provenance follows accepted output and replay."""
import importlib.util
import io
import json
import pathlib
import sqlite3
import tempfile
import threading
import unittest
from contextlib import redirect_stdout, redirect_stderr
from types import SimpleNamespace

from ai_provenance import (generation_from_record, record_fields,
                           refresh_pack_manifest, response_metadata)

ROOT = pathlib.Path(__file__).resolve().parents[2]


def pipeline(language):
    name = 'add_llm_examples' + ('_en' if language == 'en' else '')
    spec = importlib.util.spec_from_file_location(
        f'test_{name}', ROOT / 'pipeline' / f'voc-{language}' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pack(words=('cat', 'dog')):
    db = sqlite3.connect(':memory:')
    db.row_factory = sqlite3.Row
    db.execute('CREATE TABLE words (id INTEGER PRIMARY KEY, word TEXT, lemma TEXT, '
               'metadata_json TEXT, enrichment_json TEXT)')
    for i, word in enumerate(words, 1):
        db.execute('INSERT INTO words VALUES (?,?,?,?,?)', (
            i, word, word, json.dumps({'sources': ['dictionary'], 'license': 'CC BY-SA 4.0'}), '{}'))
    return db


class Provenance(unittest.TestCase):
    def test_private_hosts_and_model_paths_are_redacted_in_new_and_replayed_records(self):
        actual = response_metadata('tenant-private-alias',
            'https://tenant.internal.example/v1', '/home/person/model.gguf',
            'https://private.example/model?token=secret')
        replayed = generation_from_record({'generation': {
            'provider': 'tenant-private-alias',
            'provider_host': 'tenant.internal.example',
            'requested_model': 'models/private-model',
            'response_model': r'C:\Users\person\model.onnx',
            'api_key': 'secret',
        }})
        for record in (actual, replayed):
            self.assertEqual(record['provider_host'], 'configured_endpoint')
            self.assertNotIn('requested_model', record)
            self.assertNotIn('response_model', record)
            for private_part in ('tenant', 'private', 'person', 'secret'):
                self.assertNotIn(private_part, json.dumps(record))
        local = response_metadata('my-server', 'http://localhost:8080', 'model')
        self.assertEqual(local['provider_host'], 'local_endpoint')
        public = response_metadata('nebius', 'https://api.tokenfactory.nebius.com/v1',
                                   'meta-llama/Llama-3.3-70B-Instruct')
        self.assertEqual(public['requested_model'], 'meta-llama/Llama-3.3-70B-Instruct')

    def test_no_secrets_and_unknown_checkpoint_details_stay_unknown(self):
        actual = response_metadata('configured-provider',
            'https://user:secret@example.test/private?api_key=secret', 'requested', 'served')
        self.assertEqual(actual['provider_host'], 'configured_endpoint')
        self.assertEqual(actual['response_model'], 'served')
        self.assertNotIn('secret', json.dumps(actual))
        self.assertEqual(generation_from_record({}), {})
        self.assertEqual(generation_from_record({'by': 'old-model'}),
                         {'requested_model': 'old-model'})

    def test_field_scope_source_license_and_stale_manifest(self):
        db = pack()
        metadata = {'sources': ['dictionary'], 'license': 'CC BY-SA 4.0',
                    'grade_examples': {'1': ['A cat sits.']}}
        record_fields(metadata, {'metadata.grade_examples': metadata['grade_examples']})
        self.assertEqual(metadata['sources'], ['dictionary'])
        self.assertEqual(metadata['license'], 'CC BY-SA 4.0')
        field = metadata['ai_content']['fields']['metadata.grade_examples']
        self.assertEqual(field['details_status'], 'unrecorded')
        self.assertEqual(field['generation'], {})
        db.execute('UPDATE words SET metadata_json=? WHERE id=1', (json.dumps(metadata),))
        counts = refresh_pack_manifest(db)['counts']
        self.assertEqual(counts['entries_with_recorded_ai_fields'], 1)
        self.assertEqual(counts['entries_with_unrecorded_origin'], 1)
        metadata['grade_examples'] = {'1': ['Edited later.']}
        db.execute('UPDATE words SET metadata_json=? WHERE id=1', (json.dumps(metadata),))
        counts = refresh_pack_manifest(db)['counts']
        self.assertEqual(counts['entries_with_recorded_ai_fields'], 0)
        self.assertEqual(counts['stale_field_records'], 1)
        db.close()

    def test_successful_fallback_and_dry_run_metadata_for_both_pipelines(self):
        for language in ('de', 'en'):
            module = pipeline(language)
            client = module.LLMClient.__new__(module.LLMClient)
            client._tls = threading.local()
            client._rr_lock = threading.Lock()
            client._rr_index = 0
            client._stats = {}
            client._disabled = set()
            def unavailable(**kwargs):
                raise RuntimeError('temporary unavailable')
            def successful(**kwargs):
                return SimpleNamespace(model='served-model', choices=[
                    SimpleNamespace(message=SimpleNamespace(content='{"ok":true}'))])
            def provider(name, call):
                return {'name': name, 'endpoint': 'https://api.tokenfactory.nebius.com/v1' if name == 'successful' else 'https://api.groq.com/v1',
                        'type': 'openai_compat', 'fill_model': name + '-requested',
                        'client': SimpleNamespace(chat=SimpleNamespace(
                            completions=SimpleNamespace(create=call)))}
            client._ordered = lambda: [provider('failed', unavailable), provider('successful', successful)]
            with redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
                self.assertEqual(client.call('system', 'user'), '{"ok":true}')
                record = client._tls.last_generation
                self.assertEqual(record['provider'], 'nebius')
                self.assertEqual(record['requested_model'], 'successful-requested')
                self.assertEqual(record['response_model'], 'served-model')
                client.call('system', 'user', dry_run=True)
                self.assertIsNone(client._tls.last_generation)

    def test_worker_records_survive_checkpoint_replay_for_both_languages(self):
        class FakeLLM:
            def __init__(self):
                self._tls = threading.local()
            def call(self, system, user, **kwargs):
                word = json.loads(user.splitlines()[-1])[0]
                self._tls.last_provider = word + '-provider'
                self._tls.last_generation = response_metadata(
                    word + '-provider', 'https://' + word + '.example', word + '-model')
                return json.dumps({word: {str(g): [f'A {word} sits.'] for g in (1, 2, 3)}})
            def record_invalid(self):
                raise AssertionError('fixture should validate')
        class NoCalls:
            def call(self, *args, **kwargs):
                raise AssertionError('checkpoint replay must not contact a provider')
        for language in ('de', 'en'):
            module = pipeline(language)
            with tempfile.TemporaryDirectory() as folder, redirect_stdout(io.StringIO()):
                module.GRADE_JSONL = pathlib.Path(folder) / 'grade.jsonl'
                db = pack()
                rows = [dict(r) for r in db.execute('SELECT * FROM words')]
                module.run_grade_fill(db, FakeLLM(), rows, False, None, workers=2)
                first = [dict(r) for r in db.execute('SELECT * FROM words')]
                replay = pack()
                module.run_grade_fill(replay, NoCalls(),
                    [dict(r) for r in replay.execute('SELECT * FROM words')], False, None)
                for original, restored in zip(first, replay.execute('SELECT * FROM words')):
                    metadata = json.loads(restored['metadata_json'])
                    self.assertEqual(metadata, json.loads(original['metadata_json']))
                    field = metadata['ai_content']['fields']['metadata.grade_examples']
                    self.assertEqual(field['generation']['requested_model'], original['word'] + '-model')
                    self.assertEqual(metadata['license'], 'CC BY-SA 4.0')
                    self.assertIn('dictionary', metadata['sources'])
                db.close()
                replay.close()

    def test_unchanged_check_does_not_relabel_source_text(self):
        for language in ('de', 'en'):
            module = pipeline(language)
            with tempfile.TemporaryDirectory() as folder, redirect_stdout(io.StringIO()):
                module.CHECK_JSONL = pathlib.Path(folder) / 'check.jsonl'
                examples = {str(g): ['A cat sits.'] for g in (1, 2, 3)}
                module.CHECK_JSONL.write_text(json.dumps({'id': 1, 'grade_examples': examples}) + '\n')
                db = pack(('cat',))
                db.execute('UPDATE words SET metadata_json=?',
                           (json.dumps({'grade_examples': examples, 'sources': ['dictionary']}),))
                module.run_check(db, None, [dict(r) for r in db.execute('SELECT * FROM words')], False, None)
                metadata = json.loads(db.execute('SELECT metadata_json FROM words').fetchone()[0])
                self.assertNotIn('ai_content', metadata)
                self.assertEqual(metadata['sources'], ['dictionary'])
                db.close()

    def test_phrasal_loader_keeps_meaning_and_revised_example_origins_separate(self):
        spec = importlib.util.spec_from_file_location('test_phrasal',
            ROOT / 'pipeline/voc-en/add_phrasal_verbs_en.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as folder, redirect_stdout(io.StringIO()):
            root = pathlib.Path(folder)
            module.SRC_DB = root / 'pack.db'
            module.RANKED_JSONL = root / 'ranked.jsonl'
            module.GRADE_JSONL = root / 'grade.jsonl'
            module.CHECK_JSONL = root / 'check.jsonl'
            db = sqlite3.connect(module.SRC_DB)
            db.execute('CREATE TABLE words (id INTEGER PRIMARY KEY, metadata_json TEXT, enrichment_json TEXT)')
            db.execute("INSERT INTO words VALUES (1, '{}', '{}')")
            db.commit()
            db.close()
            ranked = {'word_id': 1, 'phrasal': 'give up', 'base_verb': 'give',
                'particle': 'up', 'meaning': 'dictionary meaning', 'senses': [],
                'distractors': [], 'wiktionary_examples': [], 'synonyms': [],
                'grade_band': 3, 'base_zipf': 4.0, 'source': 'Wiktionary', 'license': 'CC BY-SA 4.0'}
            generation = response_metadata('nebius', 'https://api.tokenfactory.nebius.com/v1', 'first-model')
            revision = response_metadata('groq', 'https://api.groq.com/v1', 'second-model')
            module.RANKED_JSONL.write_text(json.dumps(ranked) + '\n')
            module.GRADE_JSONL.write_text(json.dumps({'phrasal': 'give up',
                'meaning_kid': 'stop trying', 'meaning_generated': True,
                'grade_examples': {'3': ['Do not give up.']}, 'generation': generation}) + '\n')
            module.CHECK_JSONL.write_text(json.dumps({'phrasal': 'give up', 'ok': True,
                'grade_examples': {'3': ['I will not give up.']}, 'generation': revision}) + '\n')
            module.load(compress=False)
            db = sqlite3.connect(module.SRC_DB)
            source, license, raw = db.execute('SELECT source, license, ai_content_json FROM phrasal_verbs').fetchone()
            self.assertEqual((source, license), ('Wiktionary', 'CC BY-SA 4.0'))
            fields = json.loads(raw)['fields']
            self.assertEqual(fields['meaning']['origin'], 'ai_generated')
            self.assertEqual(fields['meaning']['generation']['requested_model'], 'first-model')
            self.assertEqual(fields['examples']['origin'], 'ai_assisted_revision')
            self.assertEqual(fields['examples']['generation']['requested_model'], 'second-model')
            manifest = json.loads(db.execute('SELECT value_json FROM content_provenance').fetchone()[0])
            self.assertEqual(manifest['phrasal_verbs']['entries_with_recorded_ai_fields'], 1)
            db.close()


if __name__ == '__main__':
    unittest.main()
