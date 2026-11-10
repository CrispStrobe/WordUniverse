#!/usr/bin/env python3
"""The English synonym rules of thesaurus_en.py, on a stand-in WordNet.

    python3 tools/pack/thesaurus_en_test.py
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import thesaurus_en as E  # noqa: E402


class FakeWordNet:
    def __init__(self, ranks, offensive=()):
        self.ranks, self._offensive = ranks, set(offensive)

    def sense_rank(self, word, word_type):
        return self.ranks.get(word, {})

    def offensive(self, term):
        return term.lower() in self._offensive


class Rules(unittest.TestCase):
    def test_a_late_sense_ranks_last_and_vulgar_terms_go(self):
        # "know": sense 1 cognize, sense 8 sleep together.
        wn = FakeWordNet({'know': {'cognize': (True, 1), 'acknowledge': (True, 2),
                                   'bed': (True, 8), 'fuck': (True, 8),
                                   'knowing': (False, 1)}})
        drop, ranked = E.review('know', 'verb',
                                ['bed', 'Know', 'fuck', 'knowing', 'acknowledge',
                                 'cognize', 'savvy'], wn)
        self.assertEqual(drop, {'Know': 'self', 'fuck': 'offensive'})
        self.assertEqual(ranked, [('cognize', 0), ('acknowledge', 1), ('bed', 2),
                                  ('knowing', 3), ('savvy', 4)])

    def test_a_vulgar_word_inside_a_phrase_counts(self):
        self.assertTrue(E.vulgar('take a shit'))
        self.assertTrue(E.vulgar('jerk off'))
        self.assertFalse(E.vulgar('niggling'))

    def test_wordnet_obscenity_marks_count(self):
        wn = FakeWordNet({'tool': {}}, offensive={'shaft'})
        drop, _ = E.review('tools', 'noun', ['shaft', 'instrument'], wn)
        self.assertEqual(drop, {'shaft': 'offensive'})


if __name__ == '__main__':
    unittest.main()
