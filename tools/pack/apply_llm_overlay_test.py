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

    def relation(self, row_id):
        self.db.row_factory = sqlite3.Row
        row = self.db.execute('SELECT * FROM words WHERE id = ?', (row_id,)).fetchone()
        self.db.row_factory = None
        return apply.relation_entry(row, 'de')

    def test_relations_apply_to_the_row_the_models_read(self):
        self.db.row_factory = sqlite3.Row
        row = self.db.execute('SELECT * FROM words WHERE id = 1').fetchone()
        self.db.row_factory = None
        entry = apply.relation_entry(row, 'de')
        root = pathlib.Path(self.dir.name)
        (root / 'de_relations.jsonl').write_text('\n'.join(json.dumps(r) for r in [
            {'id': 'w1', 'src': correct.digest(entry), 'word_type': 'noun',
             'classes': ['noun'], 'category': 'Tier'},
            # Read when Tröpfchen said something else: not applied.
            {'id': 'w2', 'src': 'stale', 'word_type': 'noun',
             'classes': ['noun', 'verb'], 'category': None},
            {'id': 'w3', 'src': correct.digest(self.relation(3)),
             'word_type': 'noun', 'classes': ['noun'], 'category': 'Sache'},
        ]) + '\n')
        self.run_apply()
        meta = self.row(1)[3]
        self.assertEqual(meta['llm_classes'], ['noun'])
        self.assertEqual(meta['llm_category'], 'Tier')
        self.assertNotIn('llm_classes', self.row(2)[3])
        # Too general to be an answer.
        self.assertEqual(self.row(3)[3]['llm_category'], '')

    def test_reviewed_synonyms_keep_only_what_the_row_still_lists(self):
        self.db.execute(
            "UPDATE words SET enrichment_json=? WHERE id=1",
            (json.dumps({'definitions': ['Sternbilder'],
                         'synonyms': [{'word': 'Köter'}, 'Treffer', 'fett'],
                         'antonyms': ['Katze']}),))
        self.db.commit()
        root = pathlib.Path(self.dir.name)
        (root / 'de_lexrel.jsonl').write_text(json.dumps(
            {'id': 'w1', 'src': correct.digest(self.relation(1)),
             'synonyms': ['Köter', 'Fremdwort'], 'antonyms': []}) + '\n')
        self.run_apply()
        meta = self.row(1)[3]
        self.assertEqual(meta['llm_synonyms'], ['Köter'])
        # A pack word, so it was put to the judges, who turned it down.
        self.assertEqual(meta['llm_rejected_synonyms'], ['fett'])
        # Empty is a verdict: nothing to ask.
        self.assertEqual(meta['llm_antonyms'], [])

    def test_synonyms_ranked_by_sense_replace_the_lists_they_were_read_from(self):
        listed = {'definitions': ['Sternbilder'],
                  'synonyms': ['Hurensohn (derb)', 'Hund', 'Köter'],
                  'antonyms': ['Katze']}
        self.db.execute("UPDATE words SET enrichment_json=? WHERE id IN (1, 3)",
                        (json.dumps(listed),))
        self.db.commit()
        src = apply.synonym_lists_digest(listed)
        root = pathlib.Path(self.dir.name)
        (root / 'de_synonym_senses.jsonl').write_text('\n'.join(json.dumps(r) for r in [
            {'id': 'w1', 'src': src, 'synonyms': ['Köter'], 'antonyms': ['Katze']},
            {'id': 'w3', 'src': 'stale', 'synonyms': [], 'antonyms': []},
        ]) + '\n')
        (root / 'de_lexrel.jsonl').write_text(json.dumps(
            {'id': 'w1', 'src': correct.digest(self.relation(1)),
             'synonyms': ['Köter'], 'antonyms': []}) + '\n')
        self.run_apply()
        _, _, enr, meta = self.row(1)
        self.assertEqual(enr['synonyms'], ['Köter'])
        self.assertEqual(meta['llm_synonyms'], ['Köter'])
        # Read from other lists: left as it is.
        self.assertEqual(self.row(3)[2]['synonyms'], listed['synonyms'])

    def test_a_checked_childrens_gloss_goes_first(self):
        root = pathlib.Path(self.dir.name)
        src = correct.digest(self.relation(1))
        (root / 'de_kidgloss.jsonl').write_text('\n'.join(json.dumps(r) for r in [
            {'id': 'w1', 'src': src, 'gloss': 'Ein Tier, das bellt.',
             'old': 'Sternbilder', 'ok': True},
            {'id': 'w3', 'src': correct.digest(self.relation(3)),
             'gloss': 'Fett halt.', 'old': 'dick', 'ok': False},
        ]) + '\n')
        self.run_apply()
        _, _, enr, meta = self.row(1)
        self.assertEqual(enr['definitions'], ['Ein Tier, das bellt.', 'Sternbilder'])
        self.assertEqual(meta['gloss_source'], 'llm-reviewed')
        self.assertEqual(self.row(3)[2]['definitions'], ['dick'])

    def test_the_meaning_a_child_means_goes_first_once_confirmed(self):
        root = pathlib.Path(self.dir.name)
        (root / 'de_sense.jsonl').write_text('\n'.join(json.dumps(r) for r in [
            {'id': 'w1', 'src': correct.digest(self.relation(1)), 'ok': False,
             'old': 'Sternbilder', 'gloss': 'Ein Tier, das bellt.', 'confirmed': True},
            # The second judge disagreed: left alone.
            {'id': 'w3', 'src': correct.digest(self.relation(3)), 'ok': False,
             'old': 'dick', 'gloss': 'Öl zum Braten.', 'confirmed': False},
        ]) + '\n')
        self.run_apply()
        _, _, enr, meta = self.row(1)
        self.assertEqual(enr['definitions'], ['Ein Tier, das bellt.', 'Sternbilder'])
        self.assertEqual(meta['gloss_source'], 'llm-sense')
        self.assertEqual(self.row(3)[2]['definitions'], ['dick'])

    def test_a_written_gloss_ending_on_a_particle_is_closed_with_a_full_stop(self):
        root = pathlib.Path(self.dir.name)
        (root / 'de_sense.jsonl').write_text('\n'.join(json.dumps(r) for r in [
            {'id': 'w1', 'src': correct.digest(self.relation(1)), 'ok': False,
             'old': 'Sternbilder', 'gloss': 'damit isst man Suppe oder rührt um',
             'confirmed': True},
        ]) + '\n')
        self.run_apply()
        self.assertEqual(self.row(1)[2]['definitions'],
                         ['damit isst man Suppe oder rührt um.', 'Sternbilder'])
        # A source gloss is left as it is: there the word is a real cut.
        self.assertEqual(self.row(3)[2]['definitions'], ['dick'])

    def test_a_family_word_of_someone_is_never_the_word_itself(self):
        self.assertTrue(apply.self_relative('Opa von Papa oder Mama', 'Großvater', ['Opa']))
        self.assertTrue(apply.self_relative('Oma und Opa von Papa oder Mama',
                                            'Großeltern', ['Oma und Opa']))
        self.assertTrue(apply.self_relative("The grandpa of your mom", 'grandfather',
                                            ['grandpa']))
        self.assertFalse(apply.self_relative('der Vater von Papa oder Mama',
                                             'Großvater', ['Opa']))
        self.assertFalse(apply.self_relative('Ein Stück von etwas.', 'Teil', ['Stück']))
        self.assertFalse(apply.self_relative('Der Junge von Mama und Papa.', 'Sohn',
                                             ['Junge']))

    def test_a_childrens_gloss_naming_a_relative_is_not_applied(self):
        root = pathlib.Path(self.dir.name)
        self.db.execute("UPDATE words SET word='Großvater', enrichment_json=? WHERE id=1",
                        (json.dumps({'definitions': ['Vater des Vaters oder der Mutter'],
                                     'synonyms': ['Opa']}),))
        self.db.commit()
        (root / 'de_kidgloss.jsonl').write_text(json.dumps(
            {'id': 'w1', 'src': correct.digest(self.relation(1)),
             'gloss': 'Opa von Papa oder Mama', 'old': 'Vater des Vaters oder der Mutter',
             'ok': True}) + '\n')
        self.run_apply()
        self.assertEqual(self.row(1)[2]['definitions'], ['Vater des Vaters oder der Mutter'])

    def test_a_gloss_a_blind_reader_could_not_trace_is_replaced_or_dropped(self):
        root = pathlib.Path(self.dir.name)
        (root / 'de_kidgloss.jsonl').write_text('\n'.join(json.dumps(r) for r in [
            {'id': 'w1', 'src': correct.digest(self.relation(1)),
             'gloss': 'Damit kannst du etwas halten.', 'old': 'Sternbilder', 'ok': True},
            {'id': 'w3', 'src': correct.digest(self.relation(3)),
             'gloss': 'Etwas zum Werfen', 'old': 'dick', 'ok': True},
        ]) + '\n')
        (root / 'de_blind.jsonl').write_text('\n'.join(json.dumps(r) for r in [
            {'id': 'w1', 'gloss': 'Damit kannst du etwas halten', 'guesses': ['Ball'],
             'ok': False, 'fix': 'Ein Tier, das bellt.', 'fix_found': True},
            {'id': 'w3', 'gloss': 'Etwas zum Werfen', 'guesses': ['Ball'],
             'ok': False, 'fix': 'Etwas', 'fix_found': False},
        ]) + '\n')
        self.run_apply()
        _, _, enr, meta = self.row(1)
        self.assertEqual(enr['definitions'], ['Ein Tier, das bellt.', 'Sternbilder'])
        self.assertEqual(meta['gloss_source'], 'llm-reviewed')
        _, _, enr, meta = self.row(3)
        self.assertEqual(enr['definitions'], ['dick'])
        self.assertNotIn('gloss_source', meta)


class PhrasalFits(unittest.TestCase):
    def test_only_particles_no_judge_fits_anywhere_are_offered(self):
        record = {'id': 'walk through',
                  'sentences': ['She walks me through the steps.',
                                'He walks us through the game.']}
        fits = {'She walks me ___ the steps.': {'through', 'up', 'down', 'along'},
                'He walks us ___ the game.': {'through', 'into'}}
        sentences, wrong = apply.safe_distractors(record, fits)
        self.assertEqual(len(sentences), 2)
        for p in ('up', 'down', 'along', 'into', 'through'):
            self.assertNotIn(p, wrong)
        self.assertIn('off', wrong)

    def test_another_phrasal_verb_of_the_same_verb_is_never_wrong(self):
        record = {'id': 'put up', 'sentences': ['She put up the tent.']}
        fits = {'She put ___ the tent.': {'up'}}
        _, wrong = apply.safe_distractors(record, fits, {'put up', 'put away'})
        self.assertNotIn('away', wrong)
        self.assertIn('through', wrong)

    def test_a_sentence_judged_later_keeps_the_verified_rewrite(self):
        record = {'id': 'eat away', 'sentences': ['Rust eats away the metal.']}
        self.assertIsNone(apply.safe_distractors(record, {}))


if __name__ == '__main__':
    unittest.main()
