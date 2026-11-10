#!/usr/bin/env python3
"""The synonym rules of thesaurus_de.py, each on the case that made it.

    python3 tools/pack/thesaurus_de_test.py
"""
import pathlib
import sys
import tempfile
import unittest
from collections import defaultdict

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import thesaurus_de as T  # noqa: E402


def ot_from(synsets):
    """synsets: {id: (visible, [(word, level)])} -> an OpenThesaurus."""
    lines = ['INSERT INTO `synset` VALUES '
             + ','.join(f"({sid},1,NULL,'{chr(1) if vis else chr(92) + '0'}',"
                        "NULL,NULL,NULL,NULL,NULL)"
                        for sid, (vis, _) in synsets.items()) + ';']
    level_id = {v: k for k, v in T.LEVELS.items()}
    rows, n = [], 1
    for sid, (_, terms) in synsets.items():
        for word, level in terms:
            lv = level_id[level] if level else 'NULL'
            rows.append(f"({n},0,2,{lv},NULL,NULL,{sid},NULL,'{word}',NULL)")
            n += 1
    lines.append('INSERT INTO `term` VALUES ' + ','.join(rows) + ';')
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write('\n'.join(lines) + '\n')
    return T.OpenThesaurus(f.name)


class FakeOdeNet:
    def __init__(self, senses=None):
        self._senses = senses or {}

    def senses(self, word, word_type):
        return self._senses.get(word, [])


class FakeWiktionary:
    def __init__(self, entries):
        self.entries = defaultdict(list, entries)

    def lookup(self, word, word_type):
        return self.entries.get(word, [])


def entry(senses, synonyms):
    return {'pos': 'noun',
            'senses': [({n}, g, set()) for n, g in senses],
            'synonyms': [(w, {n}, set(tags)) for w, n, *tags in synonyms]}


class Rules(unittest.TestCase):
    def test_a_hidden_synset_and_the_word_itself_are_dropped(self):
        ot = ot_from({41007: (False, [('Preis', 'gehoben'),
                                      ('Egon Schiele Art Center', 'gehoben')]),
                      9989: (True, [('Preis', None), ('Gebühr', None)])})
        wikt = FakeWiktionary({'Preis': [entry(
            [(1, 'zu zahlender Geldbetrag')], [('Wert', 1)])]})
        drop, ranked = T.review(
            'Preis', 'substantiv', ['zu zahlender Geldbetrag'],
            ['Egon Schiele Art Center (gehoben)', 'Preis', 'Gebühr'],
            FakeOdeNet(), ot, wikt)
        self.assertEqual(drop['Egon Schiele Art Center (gehoben)'], 'hidden synset')
        self.assertEqual(drop['Preis'], 'self')
        self.assertEqual([t for t, _ in ranked], ['Gebühr'])

    def test_insults_go_with_their_sense(self):
        # OdeNet keeps the insult sense of "Hund" without a register; OT
        # files its terms as derb.
        ot = ot_from({1: (True, [('Drecksack', 'derb'), ('Scheißkerl', 'derb'),
                                 ('Sack', 'derb'), ('Mistkerl', None)]),
                      2: (True, [('Sack', None), ('Beutel', None)])})
        odenet = FakeOdeNet({'Hund': [('odenet-9510-n',
                                       ['Drecksack', 'Scheißkerl', 'Mistkerl'])]})
        wikt = FakeWiktionary({'Hund': [entry(
            [(1, 'Haustier, das bellt')], [('Köter', 1)])]})
        drop, ranked = T.review(
            'Hund', 'substantiv', ['ein Tier, das bellt'],
            ['Drecksack (derb)', 'Mistkerl', 'Köter', 'Sack'], odenet, ot, wikt)
        self.assertEqual(drop['Drecksack (derb)'], 'offensive')
        self.assertEqual(drop['Mistkerl'], 'insult sense')
        # A bag in another synset, but a child sees the word.
        self.assertEqual(drop['Sack'], 'offensive elsewhere')
        self.assertEqual([t for t, _ in ranked], ['Köter'])

    def test_the_meaning_shown_first_ranks_first_in_its_own_entry(self):
        # "Ball" the dance is a separate entry with its own sense 1.
        wikt = FakeWiktionary({'Ball': [
            entry([(1, 'kugelförmiges Objekt'), (2, 'Spielweise')],
                  [('Kugel', 1), ('Schuss', 2)]),
            entry([(1, 'festliche Tanzveranstaltung')], [('Tanzabend', 1)])]})
        ot = ot_from({5: (True, [('Ball', None), ('Kugel', None), ('Pille', None)])})
        drop, ranked = T.review(
            'Ball', 'substantiv', ['Ein runder Gegenstand zum Spielen.',
                                   'kugelförmiges Objekt'],
            ['Tanzabend', 'Schuss', 'Pille', 'Kugel'], FakeOdeNet(), ot, wikt)
        self.assertEqual(ranked, [('Kugel', 0), ('Pille', 1),
                                  ('Tanzabend', 2), ('Schuss', 2)])

    def test_the_first_definition_names_the_sense_when_it_is_a_gloss(self):
        wikt = FakeWiktionary({'Schloss': [entry(
            [(1, 'Schließvorrichtung'), (2, 'prunkvolles Wohngebäude')],
            [('Riegel', 1), ('Palast', 2)])]})
        _, ranked = T.review('Schloss', 'substantiv', ['prunkvolles Wohngebäude'],
                             ['Riegel', 'Palast'], FakeOdeNet(), ot_from({}), wikt)
        self.assertEqual(ranked[0], ('Palast', 0))

    def test_register_labels_leave_the_term(self):
        _, ranked = T.review('leise', 'adjektiv', ['kaum hörbar'],
                             ['still (umgangssprachlich)', 'still'],
                             FakeOdeNet(), ot_from({}), FakeWiktionary({}))
        self.assertEqual([t for t, _ in ranked], ['still'])

    def test_sense_numbers(self):
        self.assertEqual(T.sense_numbers('1a'), {1})
        self.assertEqual(T.sense_numbers('2, 3'), {2, 3})
        self.assertEqual(T.sense_numbers('1–3'), {1, 2, 3})

    def test_antonyms_lose_the_word_and_offensive_terms(self):
        ot = ot_from({1: (True, [('Arsch', 'vulgär'), ('Po', None)])})
        drop, out = T.clean_antonyms('laut', ['leise', 'laut', 'leise', 'Arsch'], ot)
        self.assertEqual(out, ['leise'])
        self.assertEqual(drop, {'laut': 'self', 'leise': 'duplicate',
                                'Arsch': 'offensive'})


if __name__ == '__main__':
    unittest.main()
