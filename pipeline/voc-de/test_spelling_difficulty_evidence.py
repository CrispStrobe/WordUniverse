"""Regression checks for unknown versus observed spelling evidence.

Run: python3 -m unittest discover -s pipeline/voc-de -p 'test_*evidence.py'
No downloaded pack is opened or rewritten.
"""

import contextlib
import csv
import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from spelling_difficulty_evidence import (litkey_spelling_difficulty,
                                          unknown_spelling_difficulty)
from add_litkey_profiles import error_rate_to_difficulty, profile_metadata
from add_litkey_words import _make_row, content_lemma_metadata, load_litkey


def load_stage(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SpellingEvidenceTests(unittest.TestCase):
    def test_compatibility_zero_is_distinct_from_observed_zero(self):
        unknown = unknown_spelling_difficulty()
        observed = litkey_spelling_difficulty(0.0, 0, sample_size=12, error_tokens=0)
        self.assertEqual(unknown['spellingDifficulty'], observed['spellingDifficulty'])
        self.assertEqual(unknown['spellingDifficultySource'], 'unknown')
        self.assertIsNone(unknown['spellingDifficultyEvidence']['source'])
        self.assertEqual(observed['spellingDifficultySource'], 'litkey')
        self.assertEqual(observed['spellingDifficultyEvidence']['status'], 'corpus-derived')
        self.assertEqual(observed['spellingDifficultyEvidence']['sampleSize'], 12)
        self.assertFalse(observed['spellingDifficultyEvidence']['calibrated'])

    def test_existing_rate_thresholds_do_not_change_in_either_producer(self):
        expected = [(0.0, 0), (0.2499, 0), (0.25, 1), (0.4999, 1),
                    (0.50, 2), (0.7499, 2), (0.75, 3), (1.0, 3)]
        for rate, score in expected:
            with self.subTest(rate=rate):
                self.assertEqual(error_rate_to_difficulty(rate), score)
                profile = profile_metadata({}, {'litkey_error_rate': rate})
                lemma = content_lemma_metadata({'error_rate': rate})
                self.assertEqual(profile['spellingDifficulty'], score)
                self.assertEqual(lemma['spellingDifficulty'], score)
                self.assertEqual(profile['spellingDifficultyEvidence']['errorRate'], rate)
                self.assertEqual(lemma['spellingDifficultyEvidence']['errorRate'], rate)

    def test_profile_adds_evidence_even_if_the_numeric_score_stays_zero(self):
        before = {**unknown_spelling_difficulty(), 'otherMetadata': {'retain': True}}
        profile = {
            'litkey_error_rate': 0.0, 'litkey_total_tokens': 8, 'litkey_error_tokens': 0,
            'litkey_error_profile': {}, 'litkey_grade_first_correct': 2,
            'litkey_word_features': {'doubleC_syl': 1},
        }
        result = profile_metadata(before, profile)
        self.assertEqual(result['spellingDifficulty'], 0)
        self.assertEqual(result['spellingDifficultySource'], 'litkey')
        self.assertEqual(result['litkey_total_tokens'], 8)
        self.assertEqual(result['litkey_error_tokens'], 0)
        self.assertEqual(result['spellingDifficultyEvidence']['sampleSize'], 8)
        self.assertEqual(result['spellingDifficultyEvidence']['aggregation'], 'target')
        self.assertEqual(result['otherMetadata'], before['otherMetadata'])
        self.assertEqual(before['spellingDifficultySource'], 'unknown')

    def test_missing_sample_counts_remain_unknown(self):
        result = profile_metadata({}, {'litkey_error_rate': 0.5})
        evidence = result['spellingDifficultyEvidence']
        self.assertIsNone(evidence['sampleSize'])
        self.assertIsNone(evidence['errorTokens'])
        self.assertNotIn('litkey_total_tokens', result)
        self.assertEqual(evidence['status'], 'corpus-derived')
        self.assertFalse(evidence['calibrated'])

    def test_lemma_aggregation_retains_real_counts_and_new_names_are_unknown(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'litkey.tsv'
            with path.open('w', encoding='utf-8', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=['POS', 'target', 'chl_lemma', 'erroneous'], delimiter='\t')
                writer.writeheader()
                for erroneous in (0, 0, 0, 1):
                    writer.writerow({'POS': 'NN', 'target': 'Ball', 'chl_lemma': 'Ball', 'erroneous': erroneous})
            lemmas, _ = load_litkey(path)
        metadata = content_lemma_metadata(lemmas['ball'])
        self.assertEqual(metadata['spellingDifficulty'], 1)
        self.assertEqual(metadata['litkey_total_tokens'], 4)
        self.assertEqual(metadata['litkey_error_tokens'], 1)
        self.assertEqual(metadata['spellingDifficultyEvidence']['aggregation'], 'lemma')
        inserted = json.loads(_make_row(1, 'Ball', 'Ball', 'NN', ['LITKEY'], litkey_meta=metadata)[-1])
        self.assertEqual(inserted['spellingDifficultyEvidence']['sampleSize'], 4)
        name = json.loads(_make_row(2, 'Lea', 'Lea', 'NE', ['LITKEY'], definitions=['Vorname'])[-1])
        self.assertEqual(name['spellingDifficulty'], 0)
        self.assertEqual(name['spellingDifficultyEvidence']['status'], 'unknown')

    def test_invalid_rates_or_denominators_cannot_claim_corpus_evidence(self):
        for rate in (-0.1, 1.1, float('nan'), float('inf'), True):
            with self.subTest(rate=rate), self.assertRaises(ValueError):
                litkey_spelling_difficulty(rate, 0)
        for sample_size in (0, -1, True, 1.5):
            with self.subTest(sample_size=sample_size), self.assertRaises(ValueError):
                litkey_spelling_difficulty(0.5, 2, sample_size=sample_size)
        with self.assertRaises(ValueError):
            litkey_spelling_difficulty(0.5, 2, sample_size=2, error_tokens=3)

    def test_initial_csv_json_and_sqlite_keep_unknown_evidence(self):
        try:
            import pandas  # noqa: F401
        except ImportError:
            self.skipTest('CSV converter requires pandas')
        converter = load_stage('spelling_json_fixture', '03_conv_csv_to_json.py')
        sqlite_stage = load_stage('spelling_sqlite_fixture', '14_convert_db_to_sqflite.py')
        row = {
            'Source': 'BW1', 'Word': 'Ball', 'Wortart': 'Substantiv',
            'Article': 'der', 'Lemma_spacy': 'Ball', 'Forms': 'Bälle', 'Genus': 'Maskulinum',
            'URL': '', 'nur_im_Plural': '', 'Case_spacy': '', 'Number_spacy': '',
            'Degree_spacy': '', 'PronType_spacy': '', 'VerbForm_spacy': '',
        }
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source.csv'
            output = Path(directory) / 'output.json'
            with source.open('w', encoding='utf-8', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=list(row), delimiter=';')
                writer.writeheader()
                writer.writerow(row)
            with contextlib.redirect_stdout(io.StringIO()):
                converter.convert_csv_to_json(source, output)
            words = json.loads(output.read_text())['vocabulary']
        self.assertEqual(words[0]['spellingDifficulty'], 0)
        self.assertEqual(words[0]['spellingDifficultySource'], 'unknown')
        with sqlite3.connect(':memory:') as db, contextlib.redirect_stdout(io.StringIO()):
            sqlite_stage.init_db_schema(db.cursor())
            sqlite_stage.process_and_insert(db, {'vocabulary': words})
            stored = json.loads(db.execute('SELECT metadata_json FROM words').fetchone()[0])
        self.assertEqual(stored['spellingDifficultyEvidence'], words[0]['spellingDifficultyEvidence'])
        self.assertEqual(stored['spellingDifficultySource'], 'unknown')


if __name__ == '__main__':
    unittest.main()
