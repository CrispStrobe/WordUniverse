"""Regression checks for source completeness and lossless BW consolidation.

Run: python -m unittest discover -s pipeline/voc-de -p 'test_bw_source_lists.py'
"""

import csv
import importlib.util
import json
import contextlib
import io
import os
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from bw_source_lists import (PROVENANCE_COLUMNS, consolidation_key, is_valid_bw_word,
                             merge_bw_rows, merge_json_lists,
                             normalize_bw_label, parse_pages,
                             protected_bw_case_variants, read_bw_list)


class BWSourceTests(unittest.TestCase):
    def read(self, level, kind):
        return read_bw_list(HERE / f'Grundwortschatz{level}{kind}.csv', kind)

    def test_page_lists_are_references_not_invalid_numbers(self):
        self.assertEqual(parse_pages('49, 56'), (49, 56))
        self.assertEqual(parse_pages(' 36 , 54 '), (36, 54))
        for heading in ('', 'Seite im GRUNDWORTSCHATZ', 'Weitere Wörter', '36x'):
            self.assertEqual(parse_pages(heading), ())
        long_rows = self.read(1, 'L') + self.read(3, 'L')
        self.assertEqual(sum(len(row.pages) > 1 for row in long_rows), 27)
        erklaeren = next(row for row in long_rows if row.raw_label == 'erklären')
        self.assertEqual(erklaeren.pages, (36, 54))
        self.assertEqual(erklaeren.page_text, '36, 54')
        self.assertEqual(erklaeren.forms, 'du erklärst, Erklärung')

    def test_short_only_words_survive_outer_union_with_origin(self):
        for level, word in ((1, 'fliegen'), (1, 'fragen'), (3, 'Erklärung'), (3, 'Gesundheit')):
            merged = merge_bw_rows(self.read(level, 'L'), self.read(level, 'S'))
            found = next(row for row in merged if row['Word'] == word)
            self.assertEqual(json.loads(found['BW_Pages']), [])
            provenance = json.loads(found['BW_Provenance'])
            self.assertEqual({row['list'] for row in provenance}, {'S'})
            self.assertEqual({row['rawLabel'] for row in provenance}, {word})
            self.assertTrue(all(row['row'] > 0 for row in provenance))
        article = next(row['Article'] for row in merged if row['Word'] == 'Erklärung')
        self.assertEqual(article, 'die')

    def test_complete_official_z_table_has_its_forms_and_pages(self):
        expected = {
            'zählen': ('du zählst, Zahl', '46'), 'Zahn': ('Zähne', '46'),
            'Zeh': ('Zehen', '42'), 'Zeichnung': ('zeichnen', '54'),
            'Zeitung': ('', '54'), 'Zelt': ('zelten', '24'),
            'Zeugnis': ('Zeugnisse', '54'), 'ziehen': ('du ziehst, ich zog', '42'),
            'ziemlich': ('', '30'), 'Zoo': ('', '46'), 'Zucker': ('', '42'),
            'zuerst': ('', '30'), 'Zug': ('Züge', '49'), 'Zukunft': ('', '24'),
            'zurück': ('', '46'), 'zusammen': ('', '46'), 'Zwerg': ('Zwerge', '49'),
            'zwischen': ('', '30'), 'Zylinder': ('', '36'),
        }
        actual = {row.raw_label: (row.forms, row.page_text) for row in self.read(3, 'L')
                  if row.raw_label in expected}
        self.assertEqual(actual, expected)
        raw = (HERE / 'Grundwortschatz3L.csv').read_bytes()
        self.assertTrue(raw.startswith(b'\xef\xbb\xbf'))
        self.assertNotIn(b'\n', raw.replace(b'\r\n', b''))
        self.assertIn('Z z;Weitere (ggf. fehleranfällige) Wortformen;Seite im GRUNDWORTSCHATZ',
                      raw.decode('utf-8-sig'))

    def test_annotations_are_explicit_and_lossless(self):
        expected = {'ein(-)': 'ein', '(ein) bisschen': 'bisschen',
                    '(sich) freuen': 'freuen', '(ein) paar': 'paar',
                    'E-Mail': 'E-Mail'}
        for raw, head in expected.items():
            self.assertEqual(normalize_bw_label(raw), head)
            self.assertTrue(is_valid_bw_word(head))
        self.assertNotEqual(normalize_bw_label('Paar'), normalize_bw_label('(ein) paar'))
        rows = merge_bw_rows(self.read(3, 'L'), self.read(3, 'S'))
        row = next(row for row in rows if row['Word'] == 'freuen')
        self.assertEqual(json.loads(row['BW_RawLabels']), ['(sich) freuen'])
        self.assertEqual({r['rawLabel'] for r in json.loads(row['BW_Provenance'])},
                         {'(sich) freuen'})

    def test_case_distinct_declarations_are_not_merged(self):
        rows = merge_bw_rows(self.read(1, 'L'), self.read(1, 'S'))
        arm = {r['Word']: r for r in rows if r['Word'].lower() == 'arm'}
        self.assertEqual(set(arm), {'Arm', 'arm'})
        self.assertEqual(arm['Arm']['Article'], 'der')
        self.assertEqual(arm['arm']['Article'], '')
        protected = protected_bw_case_variants(r['Word'] for r in rows)
        self.assertNotEqual(consolidation_key('Arm', protected), consolidation_key('arm', protected))
        for noun, other in [('Essen', 'essen'), ('Leben', 'leben'), ('Morgen', 'morgen'), ('Sie', 'sie')]:
            self.assertNotEqual(consolidation_key(noun, protected), consolidation_key(other, protected))
        self.assertEqual(consolidation_key('Frequenzbeispiel', protected),
                         consolidation_key('frequenzbeispiel', protected))
        protected3 = protected_bw_case_variants(row.word for row in self.read(3, 'L'))
        for noun, other in [('Nächste', 'nächste'), ('Vertrauen', 'vertrauen'), ('Weg', 'weg'), ('Paar', 'paar')]:
            self.assertNotEqual(consolidation_key(noun, protected3), consolidation_key(other, protected3))

    def test_same_case_senses_retain_their_source_declarations(self):
        rows = merge_bw_rows(self.read(1, 'L'), self.read(3, 'L'))
        sein = [row for row in rows if row['Word'] == 'sein']
        self.assertEqual(len(sein), 2)
        self.assertEqual({tuple(json.loads(row['BW_RawLabels'])) for row in sein},
                         {('sein',), ('sein(-)',)})

    def test_unknown_annotations_are_rejected_without_broad_stripping(self):
        for raw in ('(optional) Haus', 'Haus (Beispiel)', '(einmal) paar'):
            self.assertEqual(normalize_bw_label(raw), raw)
            self.assertFalse(is_valid_bw_word(normalize_bw_label(raw)))
        with tempfile.TemporaryDirectory(dir=HERE) as temp:
            source = Path(temp) / 'unknownL.csv'
            source.write_text('(optional) Haus;;46\n', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'unrecognized BW head'):
                read_bw_list(source, 'L')

    def test_raw_labels_and_provenance_are_preserved_across_matching_lists(self):
        rows = merge_bw_rows(self.read(3, 'L'), self.read(3, 'S'))
        row = next(row for row in rows if row['Word'] == 'E-Mail')
        self.assertEqual(row['Article'], 'die')
        self.assertEqual(json.loads(row['BW_RawLabels']), ['E-Mail'])
        self.assertEqual(json.loads(row['BW_Pages']), [36])
        self.assertEqual({r['list'] for r in json.loads(row['BW_Provenance'])}, {'L', 'S'})

    def test_dataframe_adapter_retains_references_and_short_only_heads(self):
        try:
            import pandas  # noqa: F401
        except ImportError:
            self.skipTest('pandas adapter dependency not installed; pure reader tests still run')
        spec = importlib.util.spec_from_file_location('bw_consolidation', HERE / '01_consolidate_wordlists_csv.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        frame = module.process_bw_pair(HERE / 'Grundwortschatz3L.csv',
                                       HERE / 'Grundwortschatz3S.csv', 'BW3')
        self.assertIn('Erklärung', set(frame['Word']))
        self.assertIn('E-Mail', set(frame['Word']))
        row = frame.loc[frame['Word'] == 'erklären'].iloc[0]
        self.assertEqual(json.loads(row['BW_Pages']), [36, 54])
        self.assertEqual(row['Source'], 'BW3')

    def test_consolidation_keeps_bw_case_and_provenance_through_final_filters(self):
        try:
            import pandas as pd
        except ImportError:
            self.skipTest('pandas adapter dependency not installed')
        spec = importlib.util.spec_from_file_location('bw_consolidation_smoke', HERE / '01_consolidate_wordlists_csv.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        previous = Path.cwd()
        with tempfile.TemporaryDirectory(dir=HERE) as temp:
            temp = Path(temp)
            for name in ('Grundwortschatz1L.csv', 'Grundwortschatz1S.csv',
                         'Grundwortschatz3L.csv', 'Grundwortschatz3S.csv'):
                shutil.copyfile(HERE / name, temp / name)
            (temp / 'A1.csv').write_text(
                'Lemma,Artikel,Wortart,Genus,URL,nur_im_Plural\n'
                'Essen,das,Substantiv,Neutrum,,\n'
                'Arm,der,Substantiv,Maskulinum,,\n', encoding='utf-8')
            try:
                os.chdir(temp)
                with contextlib.redirect_stdout(io.StringIO()):
                    module.main()
                result = pd.read_csv('voc_de.csv', sep=';', keep_default_na=False)
            finally:
                os.chdir(previous)
        self.assertTrue({'essen', 'Essen', 'Arm', 'arm', 'Paar', 'paar',
                         'E-Mail', 'bisschen', 'freuen', 'fliegen', 'Erklärung'}
                        <= set(result['Word']))
        essen = result.loc[result['Word'] == 'essen'].iloc[0]
        self.assertEqual(essen['Article'], '')
        self.assertNotEqual(essen['Wortart'], 'Substantiv')
        self.assertEqual(result.loc[result['Word'] == 'Essen', 'Article'].iloc[0], 'das')
        sein = result.loc[result['Word'] == 'sein'].iloc[0]
        self.assertEqual(set(json.loads(sein['BW_RawLabels'])), {'sein', 'sein(-)'})
        self.assertTrue(json.loads(essen['BW_Provenance']))

    def test_bw_provenance_survives_spacy_csv_app_json_and_sqlite_metadata(self):
        try:
            import pandas as pd
        except ImportError:
            self.skipTest('pandas adapter dependency not installed')

        def load_stage(name, filename):
            spec = importlib.util.spec_from_file_location(name, HERE / filename)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module

        # Use actual source records, including the two contexts of sein. No
        # language model, spaCy download, enrichment API, or live DB is needed.
        source_rows = merge_bw_rows(self.read(1, 'L'), self.read(1, 'S'),
                                    self.read(3, 'L'), self.read(3, 'S'))
        rows = []
        for word in ('paar', 'Paar', 'sein'):
            declarations = [row for row in source_rows if row['Word'] == word]
            row = declarations[0].copy()
            for column in PROVENANCE_COLUMNS:
                row[column] = merge_json_lists(item[column] for item in declarations)
            row.update(Source='BW1,BW3' if word == 'sein' else 'BW3',
                       Wortart='', Genus='', URL='', nur_im_Plural='')
            rows.append(row)
        fake_nlp = SimpleNamespace(pipe=lambda words: (
            [SimpleNamespace(pos_='X', lemma_=word.lower(), morph={})] for word in words))
        fake_spacy = SimpleNamespace(load=mock.Mock(return_value=fake_nlp))
        with tempfile.TemporaryDirectory(dir=HERE) as temp, contextlib.redirect_stdout(io.StringIO()):
            temp = Path(temp)
            input_csv, enriched_csv, app_json = (temp / name for name in ('input.csv', 'enriched.csv', 'app.json'))
            pd.DataFrame(rows).to_csv(input_csv, sep=';', index=False)
            with mock.patch.dict(sys.modules, {'spacy': fake_spacy}):
                enrichment = load_stage('bw_enrichment_fixture', '02_enrich_with_spacy_csv.py')
                enrichment.tqdm = lambda items, **kwargs: items
                enrichment.enrich_data(input_csv, enriched_csv)
            enriched = pd.read_csv(enriched_csv, sep=';', keep_default_na=False)
            for original, (_, actual) in zip(rows, enriched.iterrows()):
                for column in PROVENANCE_COLUMNS:
                    self.assertEqual(actual[column], original[column])
            converter = load_stage('bw_json_fixture', '03_conv_csv_to_json.py')
            converter.convert_csv_to_json(enriched_csv, app_json)
            exported = json.loads(app_json.read_text(encoding='utf-8'))
            by_word = {entry['word']: entry for entry in exported['vocabulary']}
            self.assertEqual(by_word['paar']['bwSourceLabels'], ['(ein) paar'])
            self.assertEqual(by_word['Paar']['bwSourceLabels'], ['Paar'])
            self.assertEqual(by_word['paar']['bwSourcePages'], [57])
            self.assertEqual(by_word['Paar']['bwSourcePages'], [46])
            self.assertEqual(set(by_word['sein']['bwSourceLabels']), {'sein', 'sein(-)'})
            for original in rows:
                self.assertEqual(by_word[original['Word']]['bwSourceProvenance'],
                                 json.loads(original['BW_Provenance']))
            self.assertEqual(converter.parse_bw_source_metadata({'Word': 'alt'}),
                             {'bwSourceLabels': [], 'bwSourcePages': [], 'bwSourceProvenance': []})
            for field, invalid in [('BW_RawLabels', 'not-json'), ('BW_Pages', '["57"]'),
                                   ('BW_Provenance', '{}')]:
                with self.assertRaisesRegex(ValueError, field):
                    converter.parse_bw_source_metadata({'Word': 'paar', field: invalid})

            # Verify the existing DB converter's generic metadata path without
            # editing or rebuilding any shipped database.
            by_word['paar']['futureMetadata'] = {'nested': [1, {'check': 'preserved'}]}
            database = load_stage('bw_sqlite_fixture', '14_convert_db_to_sqflite.py')
            with sqlite3.connect(':memory:') as conn:
                database.init_db_schema(conn.cursor())
                database.process_and_insert(conn, exported)
                stored = {word: json.loads(metadata) for word, metadata in
                          conn.execute('SELECT word, metadata_json FROM words')}
            for word in by_word:
                for key in ('bwSourceLabels', 'bwSourcePages', 'bwSourceProvenance'):
                    self.assertEqual(stored[word][key], by_word[word][key])
            self.assertEqual(stored['paar']['futureMetadata'], by_word['paar']['futureMetadata'])


if __name__ == '__main__':
    unittest.main()
