#!/usr/bin/env python3
"""Checks the headword-capitalisation tiers in repair_pack.py.

Every test here asserts a rule *fires* on a real example as well as staying
quiet on a real counter-example. A rule that never fires breaks no test, which
is how _geographyGloss shipped dead for weeks.

    python3 tools/pack/repair_pack_test.py
"""
import importlib.util
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('repair_pack',
                                              HERE / 'repair_pack.py')
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)

RULES = repair.load_rules()


def evidence(*sentences):
    # One per grade: evidence_capitalises reads only the first two sentences
    # of any one grade, the same way the app samples them.
    return {'grade_examples': {str(grade + 2): [sentence]
                               for grade, sentence in enumerate(sentences)}}


class Tiers(unittest.TestCase):
    def test_the_three_tiers_do_not_overlap(self):
        capitalised = set(repair.CAPITALISED_HEADWORDS)
        junk = set(repair.NOT_VOCABULARY)
        self.assertEqual(capitalised & repair.PROPER_NOUN_HEADWORDS, set())
        self.assertEqual(capitalised & junk, set())
        self.assertEqual(repair.PROPER_NOUN_HEADWORDS & junk, set())

    def test_every_rename_changes_only_the_case(self):
        # The pack ships a prebuilt FTS index that folds case. A rename that
        # changed a letter would leave the row unfindable.
        for word, fixed in repair.CAPITALISED_HEADWORDS.items():
            self.assertEqual(word.lower(), fixed.lower(), word)
            self.assertNotEqual(word, fixed, word)

    def test_the_words_that_are_correct_in_lower_case_are_absent(self):
        for word in ('august', 'march', 'may', 'god', 'mommy', 'escape',
                     'soviet'):
            self.assertNotIn(word, repair.CAPITALISED_HEADWORDS, word)

    def test_acronyms_are_upper_case_and_months_are_title_case(self):
        self.assertEqual(repair.CAPITALISED_HEADWORDS['dvd'], 'DVD')
        self.assertEqual(repair.CAPITALISED_HEADWORDS['usa'], 'USA')
        self.assertEqual(repair.CAPITALISED_HEADWORDS['january'], 'January')
        self.assertEqual(repair.CAPITALISED_HEADWORDS['mr'], 'Mr')


class Headings(unittest.TestCase):
    def test_a_title_cased_chapter_heading_is_a_heading(self):
        self.assertTrue(repair._is_a_heading(
            "The Boys Escape Jim.-Tom Sawyer's Wonderful Plan"))

    def test_an_ordinary_sentence_is_not(self):
        self.assertFalse(repair._is_a_heading(
            'The boys escape from the barn at night.'))

    def test_a_short_phrase_is_not_judged_at_all(self):
        self.assertFalse(repair._is_a_heading('In January'))


class EvidenceCapitalises(unittest.TestCase):
    def test_three_capitalised_mid_sentence_uses_are_enough(self):
        self.assertTrue(repair.evidence_capitalises(
            'january', [], evidence('We swim in January every year.',
                                    'By January it was cold.',
                                    'Each January brings snow.')))

    def test_a_single_lower_case_use_is_enough_to_clear_the_word(self):
        self.assertFalse(repair.evidence_capitalises(
            'january', [], evidence('We swim in January every year.',
                                    'By January it was cold.',
                                    'Each january brings snow.')))

    def test_a_use_at_the_start_of_a_sentence_says_nothing(self):
        # Three sentence-initial uses and one mid-sentence: one use seen.
        self.assertFalse(repair.evidence_capitalises(
            'january', [], evidence('January is cold.', 'January again.',
                                    'January ends. We like January.')))

    def test_a_chapter_heading_is_not_counted(self):
        # This is "escape": every capitalised use is a Title Case heading.
        self.assertFalse(repair.evidence_capitalises(
            'escape', [], evidence("The Boys Escape Jim.-Tom Sawyer's Plan",
                                   'Chapter Two: They Escape The Island Camp',
                                   'A Daring Escape From The Prison Yard')))


class GlossBelongsToAnotherWord(unittest.TestCase):
    def flagged(self, word, gloss, metadata, word_type='noun', names=False,
                language='en'):
        return repair.gloss_belongs_to_another_word(
            word, word_type, [gloss], metadata, RULES, names, language)

    def test_a_rare_homograph_of_a_name_is_caught(self):
        # "olympics" was glossed "Five consecutive ducks" at grade 2.
        self.assertTrue(self.flagged(
            'joanna', 'A piano.',
            evidence('My sister Joanna sings.', 'We asked Joanna to come.',
                     'Then Joanna laughed at him.')))

    def test_a_gloss_that_names_something_is_left_alone(self):
        self.assertFalse(self.flagged(
            'brooklyn', 'A borough of New York City, New York.',
            evidence('She lives in Brooklyn now.', 'We drove to Brooklyn.',
                     'His flat in Brooklyn is small.')))

    def test_an_entry_the_pack_already_calls_a_name_is_left_alone(self):
        self.assertFalse(self.flagged(
            'joanna', 'A piano.',
            evidence('My sister Joanna sings.', 'We asked Joanna to come.',
                     'Then Joanna laughed at him.'),
            word_type='proper_noun'))
        self.assertFalse(self.flagged(
            'joanna', 'A piano.',
            evidence('My sister Joanna sings.', 'We asked Joanna to come.',
                     'Then Joanna laughed at him.'),
            names=True))

    def test_a_levelled_word_correct_in_both_cases_is_protected(self):
        # "god" is B2 and its gloss describes the capitalised sense too.
        levelled = dict(evidence('We prayed to God that night.',
                                 'She thanked God for it.',
                                 'He swore before God.'),
                        cefr_level='B2')
        self.assertFalse(self.flagged(
            'god', 'A deity or supreme being.', levelled))

    def test_the_named_exception_survives_its_level(self):
        # "august" is A1 as the month; the gloss is the adjective's.
        levelled = dict(evidence('It rained all August long.',
                                 'We met in August that year.',
                                 'By August the fields were dry.'),
                        cefr_level='A1')
        self.assertIn('august', repair.GLOSS_MISMATCHES)
        self.assertTrue(self.flagged(
            'august', 'Awe-inspiring, majestic, noble, venerable.', levelled,
            word_type='adjective'))

    def test_german_is_left_alone_because_every_noun_is_capitalised(self):
        # "reisen" is a verb whose examples say "das Reisen", which is correct
        # German and no evidence of anything.
        german = evidence('Wir lieben das Reisen sehr.',
                          'Beim Reisen lernt man viel.',
                          'Das Reisen macht mude.')
        self.assertTrue(self.flagged('reisen', 'sich fortbewegen', german,
                                     word_type='verb', language='en'))
        self.assertFalse(self.flagged('reisen', 'sich fortbewegen', german,
                                      word_type='verb', language='de'))

    def test_a_word_on_the_capitalise_list_is_not_also_faulted(self):
        self.assertFalse(self.flagged(
            'january', 'The first month of the Gregorian calendar.',
            evidence('We swim in January every year.',
                     'By January it was cold.', 'Each January brings snow.')))


class RowVerdict(unittest.TestCase):
    def test_a_misspelling_of_a_name_is_not_vocabulary(self):
        reasons, names = repair.row_verdict(
            'conneticut', 'noun', ['Misspelling of Connecticut.'], {}, RULES,
            'en')
        self.assertIn('misspelling of a capitalised name', reasons)

    def test_a_curated_name_is_typed_a_name_even_with_no_gloss(self):
        # "lapd" has no gloss at all, which is why no rule can reach it and
        # the curated list has to. Names a rule *can* reach are not listed:
        # "dracula" is caught by "the fictional ", "gestapo" by " secret
        # police of ", "persan" by " commune in ".
        reasons, names = repair.row_verdict('lapd', 'noun', [], {}, RULES,
                                            'en')
        self.assertTrue(names)
        for word in ('dracula', 'gestapo', 'persan', 'hollywood'):
            self.assertNotIn(word, repair.PROPER_NOUN_HEADWORDS, word)

    def test_ordinary_vocabulary_is_left_alone(self):
        reasons, names = repair.row_verdict(
            'river', 'noun', ['A large natural stream of water.'],
            evidence('The river is wide.'), RULES, 'en')
        self.assertEqual(reasons, [])
        self.assertFalse(names)


if __name__ == '__main__':
    unittest.main(verbosity=2)
