#!/usr/bin/env python3
"""Checks the guards in apply_llm_overlay.py on a throwaway pack.

Each guard exists because a reviewed correction was wrong in a way a model
let through, so each test pairs the real failure with a change that must
still be applied.

    python3 tools/pack/apply_llm_overlay_test.py
"""
import importlib.util
import io
import json
import pathlib
import sqlite3
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('apply_llm_overlay',
                                              HERE / 'apply_llm_overlay.py')
apply = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apply)
correct = apply  # entry_of / digest are re-exported from llm_correct


def pack(path, rows):
    db = sqlite3.connect(path)
    db.execute('CREATE TABLE words (id INTEGER PRIMARY KEY, original_id TEXT, '
               'word TEXT, lemma TEXT, word_type TEXT, article TEXT, genus TEXT, '
               'grade_level INTEGER, enrichment_json TEXT, metadata_json TEXT)')
    for i, (oid, word, wtype, article, defs, meta) in enumerate(rows, 1):
        db.execute('INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?)',
                   (i, oid, word, word, wtype, article, None, 1,
                    json.dumps({'definitions': defs}), json.dumps(meta)))
    db.commit()
    return db


class Guards(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.dir.name)
        apply.OUT_DIR = root
        self.db_path = root / 'pack.db'
        self.db = pack(self.db_path, [
            ('w1', 'Hund', 'substantiv', 'der', ['Sternbilder'], {'forms': None}),
            ('w2', 'Tröpfchen', 'substantiv', 'das', [], {}),
            ('w3', 'fett', 'adjektiv', None, ['dick'], {'sources': ['BW1']}),
            (None, 'schlurfen', 'verb', None, [], {}),
        ])
        self.records, self.audit = [], []

    def tearDown(self):
        self.db.close()
        self.dir.cleanup()

    def entry(self, row_id):
        self.db.row_factory = sqlite3.Row
        row = self.db.execute('SELECT * FROM words WHERE id = ?', (row_id,)).fetchone()
        self.db.row_factory = None
        return correct.entry_of(row, 'de')

    def propose(self, row_id, change, audit_ok=True):
        entry = self.entry(row_id)
        src = correct.digest(entry)
        self.records.append({'id': entry['id'], 'word': entry['word'], 'src': src,
                             'ok': False, 'change': change})
        for field in change:
            if field != 'not_vocabulary' and audit_ok is not None:
                self.audit.append({'key': f"{entry['id']}|{src}|{field}",
                                   'ok': audit_ok if isinstance(audit_ok, bool)
                                   else audit_ok.get(field, True)})

    def run_apply(self):
        root = pathlib.Path(self.dir.name)
        (root / 'de.jsonl').write_text(
            '\n'.join(json.dumps(r, ensure_ascii=False) for r in self.records) + '\n')
        (root / 'de.audit.jsonl').write_text(
            '\n'.join(json.dumps(r) for r in self.audit) + '\n')
        self.db.close()
        sys.argv = ['apply', str(self.db_path), '--lang', 'de']
        with redirect_stdout(io.StringIO()):
            apply.main()
        self.db = sqlite3.connect(self.db_path)

    def row(self, row_id):
        word, wtype, article, enr, meta = self.db.execute(
            'SELECT word, word_type, article, enrichment_json, metadata_json '
            'FROM words WHERE id = ?', (row_id,)).fetchone()
        return wtype, article, json.loads(enr), json.loads(meta)

    def test_a_confirmed_gloss_and_plural_are_applied(self):
        self.propose(1, {'definition': 'ein Tier, das bellt', 'plural': 'Hunde'})
        self.run_apply()
        _, _, enr, meta = self.row(1)
        self.assertEqual(enr['definitions'][0], 'ein Tier, das bellt')
        self.assertEqual(meta['forms'], 'Hunde')

    def test_a_change_the_audit_flagged_is_not_applied(self):
        # "schlurfen" was given the gloss of a screw.
        self.propose(4, {'definition': 'Ein Metallteil mit Gewinde'}, audit_ok=False)
        self.run_apply()
        self.assertEqual(self.row(4)[2]['definitions'], [])

    def test_a_plural_that_does_not_start_like_its_word_is_refused(self):
        self.propose(2, {'plural': 'Vanillen'})
        self.run_apply()
        self.assertNotIn('forms', self.row(2)[3])

    def test_a_taught_german_word_stays_vocabulary(self):
        self.propose(3, {'vocabulary': False, 'not_vocabulary': 'misspelling'})
        self.run_apply()
        self.assertNotIn('quality', self.row(3)[3])

    def test_a_row_without_original_id_is_found_by_its_row(self):
        self.propose(4, {'definition': 'die Füße beim Gehen über den Boden ziehen'})
        self.run_apply()
        self.assertEqual(self.row(4)[2]['definitions'][0],
                         'die Füße beim Gehen über den Boden ziehen')


if __name__ == '__main__':
    unittest.main()
