"""Regressions for honest grade-estimate provenance and unchanged thresholds.

Run: python -m unittest discover -s pipeline/voc-de -p 'test_grade_level_evidence.py'
"""

from copy import deepcopy
import contextlib
import gzip
import io
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compute_grade_level_estimate as estimator


class GradeEvidenceTests(unittest.TestCase):
    def test_existing_grades_do_not_invent_list_provenance(self):
        metadata = {
            'sources': ['NRW111', 'BW3'],
            'isGrundwortschatzBW': True,
            'gradeLevelEstimateSource': 'nrw',
        }
        signals = {'childlex': {'age1_freq_norm': 100},
                   'dwds': {'frequenzklasse': 5}}
        for grade in (1, 2, 3, 4):
            with self.subTest(grade=grade):
                result = estimator.decide_grade_estimate(grade, signals, metadata)
                self.assertEqual(result['gradeLevelEstimate'], grade)
                self.assertEqual(result['gradeLevelEstimateSource'], 'existing_grade_level')
                evidence = result['gradeLevelEstimateEvidence']
                self.assertEqual(evidence['status'], 'inherited')
                self.assertEqual(evidence['sourceField'], 'words.grade_level')
                self.assertNotIn('upstreamSource', evidence)
                self.assertNotIn('upstreamEvidence', evidence)

    def test_explicit_upstream_provenance_is_preserved_without_mutation(self):
        metadata = {
            'gradeLevelSource': 'explicit_project_assignment',
            'gradeLevelEvidence': {'document': 'teacher-record', 'references': ['p. 7']},
            'gradeLevelEstimateSource': 'nrw',
            'otherMetadata': {'retained': True},
        }
        before = deepcopy(metadata)
        result = estimator.decide_grade_estimate(3, {}, metadata)
        evidence = result['gradeLevelEstimateEvidence']
        self.assertEqual(evidence['upstreamSource'], metadata['gradeLevelSource'])
        self.assertEqual(evidence['upstreamEvidence'], metadata['gradeLevelEvidence'])
        self.assertEqual(metadata, before)
        evidence['upstreamEvidence']['references'].append('independent copy')
        self.assertEqual(metadata, before)

    def test_generic_fallback_keeps_existing_values_and_default(self):
        for grade, expected in ((5, 5), (6, 6), (0, 0), (7, 7), (None, 5), ('3', 5)):
            with self.subTest(grade=grade):
                result = estimator.decide_grade_estimate(grade, {}, {'gradeLevelEstimateSource': 'nrw'})
                self.assertEqual(result['gradeLevelEstimate'], expected)
                self.assertEqual(result['gradeLevelEstimateSource'], 'original')
                evidence = result['gradeLevelEstimateEvidence']
                self.assertEqual(evidence['status'], 'inherited' if isinstance(grade, int) else 'default')
                self.assertNotIn('upstreamSource', evidence)
        explicit = estimator.decide_grade_estimate(6, {}, {'gradeLevelSource': 'provided_source'})
        self.assertEqual(explicit['gradeLevelEstimateEvidence']['upstreamSource'], 'provided_source')

    def test_childlex_boundary_grades_and_earliest_band_are_unchanged(self):
        cases = [
            ('age1', 4.999, 6, 'original'),
            ('age1', 5, 2, 'childlex_age1'),
            ('age1', 49.999, 2, 'childlex_age1'),
            ('age1', 50, 1, 'childlex_age1'),
            ('age2', 4.999, 6, 'original'),
            ('age2', 5, 4, 'childlex_age2'),
            ('age2', 29.999, 4, 'childlex_age2'),
            ('age2', 30, 3, 'childlex_age2'),
            ('age3', 4.999, 6, 'original'),
            ('age3', 5, 6, 'childlex_age3'),
            ('age3', 9.999, 6, 'childlex_age3'),
            ('age3', 10, 5, 'childlex_age3'),
        ]
        for age, frequency, expected, source in cases:
            with self.subTest(age=age, frequency=frequency):
                result = estimator.decide_grade_estimate(6, {'childlex': {f'{age}_freq_norm': frequency}})
                self.assertEqual(result['gradeLevelEstimate'], expected)
                self.assertEqual(result['gradeLevelEstimateSource'], source)
                if source != 'original':
                    evidence = result['gradeLevelEstimateEvidence']
                    self.assertEqual(evidence['status'], 'heuristic')
                    self.assertEqual(evidence['sourceField'], f'frequency_json.childlex.{age}_freq_norm')
                    self.assertEqual(evidence['value'], frequency)
                    self.assertEqual(evidence['presenceThreshold'], 5.0)
        result = estimator.decide_grade_estimate(6, {'childlex': {
            'age1_freq_norm': 5, 'age2_freq_norm': 100, 'age3_freq_norm': 100},
            'dwds': {'frequenzklasse': 1}})
        self.assertEqual(result['gradeLevelEstimate'], 2)
        self.assertEqual(result['gradeLevelEstimateSource'], 'childlex_age1')

    def test_dwds_boundary_grades_and_integer_requirement_are_unchanged(self):
        for frequency_class, expected in ((-1, 6), (0, 6), (1, 6), (2, 6),
                                          (3, 4), (4, 4), (5, 2), (6, 2)):
            with self.subTest(frequency_class=frequency_class):
                result = estimator.decide_grade_estimate(5, {
                    'childlex': {'age1_freq_norm': 4.999},
                    'dwds': {'frequenzklasse': frequency_class}})
                self.assertEqual(result['gradeLevelEstimate'], expected)
                self.assertEqual(result['gradeLevelEstimateSource'], 'dwds_fallback')
                evidence = result['gradeLevelEstimateEvidence']
                self.assertEqual(evidence['status'], 'heuristic')
                self.assertEqual(evidence['sourceField'], 'frequency_json.dwds.frequenzklasse')
                self.assertEqual(evidence['value'], frequency_class)
        for invalid in (None, '5', 5.0):
            result = estimator.decide_grade_estimate(6, {'dwds': {'frequenzklasse': invalid}})
            self.assertEqual(result['gradeLevelEstimate'], 6)
            self.assertEqual(result['gradeLevelEstimateSource'], 'original')

    def test_main_uses_decision_and_preserves_metadata_in_isolated_fixture(self):
        upstream = {'gradeLevelSource': 'provided_assignment',
                    'gradeLevelEvidence': {'ref': 'source-record-12'},
                    'gradeLevelEstimateSource': 'nrw', 'unrelated': ['keep']}
        with tempfile.TemporaryDirectory(dir=HERE) as temporary:
            temporary = Path(temporary)
            source_db = temporary / 'fixture.db'
            compressed = temporary / 'fixture.db.gz'
            working = temporary / 'work' / 'working.db'
            with sqlite3.connect(source_db) as con:
                con.execute('CREATE TABLE words (id INTEGER PRIMARY KEY, word TEXT, lemma TEXT, '
                            'grade_level INTEGER, frequency_json TEXT, metadata_json TEXT)')
                con.executemany('INSERT INTO words VALUES (?, ?, ?, ?, ?, ?)', [
                    (1, 'Wort', 'Wort', 3, '{}', json.dumps(upstream)),
                    (2, 'weiter', 'weiter', 5, '{}', json.dumps({'gradeLevelEstimateSource': 'nrw'})),
                    (3, 'später', 'spät', 6, json.dumps({'childlex': {'age3_freq_norm': 10}}), '{}'),
                ])
            with gzip.open(compressed, 'wb') as handle:
                handle.write(source_db.read_bytes())
            with mock.patch.object(estimator, 'DB_GZ', compressed), \
                    mock.patch.object(estimator, 'WORK', working), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(estimator.main(), 0)
            with sqlite3.connect(working) as con:
                rows = con.execute('SELECT id, grade_level, metadata_json FROM words ORDER BY id').fetchall()
            self.assertEqual([row[1] for row in rows], [3, 5, 6])
            metadata = [json.loads(row[2]) for row in rows]
            self.assertEqual([row['gradeLevelEstimate'] for row in metadata], [3, 5, 5])
            self.assertEqual(metadata[0]['gradeLevelEstimateSource'], 'existing_grade_level')
            for key in ('gradeLevelSource', 'gradeLevelEvidence', 'unrelated'):
                self.assertEqual(metadata[0][key], upstream[key])
            self.assertEqual(metadata[0]['gradeLevelEstimateEvidence']['upstreamEvidence'],
                             upstream['gradeLevelEvidence'])
            self.assertNotIn('upstreamSource', metadata[1]['gradeLevelEstimateEvidence'])
            self.assertEqual(metadata[2]['gradeLevelEstimateSource'], 'childlex_age3')


if __name__ == '__main__':
    unittest.main()
