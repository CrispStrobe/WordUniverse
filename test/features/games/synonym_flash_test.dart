// test/features/games/synonym_flash_test.dart
//
// Synonym Flash, against the real service. This file used to hold a copy of
// the game's logic and test that; the copy had drifted (it still rejected
// diacritics, which the shipped rule accepts so German synonyms survive).
//
// The DB-pinned cases were verified against pipeline/voc-en/grundwortschatz_en.db
// on 2026-05-26 and are kept, now driving the shipped code.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/features/games/services/synonym_flash_service.dart';

ApiEnrichment _enrichment({
  List<String> synonyms = const [],
  List<String> definitions = const [],
}) =>
    ApiEnrichment(
      enrichmentStatus: 'ok',
      definitions: definitions,
      pronunciation: const [],
      examples: const [],
      synonyms: synonyms,
      antonyms: const [],
      conceptnet: const [],
      alternativeAnalyses: const [],
      inflections: const [],
      semanticRelations: const [],
      hyphenation: const [],
      translations: const [],
      derivedTerms: const [],
      relatedTerms: const [],
      expressions: const [],
      proverbs: const [],
      entryNotes: const [],
      hypernyms: const [],
      hyponyms: const [],
      holonyms: const [],
      meronyms: const [],
      coordinateTerms: const [],
      gutenbergExamples: const [],
      commonLearnerErrors: const [],
    );

GermanWord _word(
  String word, {
  List<String> synonyms = const [],
  List<String> definitions = const [],
  int grade = 3,
  GermanWordType type = GermanWordType.adjektiv,
  int features = 0,
}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: type,
      gradeLevel: grade,
      lemma: word,
      sources: const [],
      isGrundwortschatzBW: false,
      nurImPlural: false,
      graphematicVariants: const [],
      categories: const [],
      exampleSentences: const [],
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: false,
      features: features,
      apiEnrichment: _enrichment(synonyms: synonyms, definitions: definitions),
      examples: const [],
      hyphenation: const [],
      wiktionaryInflections: const [],
      translations: const [],
      derivedTerms: const [],
      relatedTerms: const [],
      expressions: const [],
      proverbs: const [],
      entryNotes: const [],
      hypernyms: const [],
      hyponyms: const [],
      holonyms: const [],
      meronyms: const [],
      coordinateTerms: const [],
    );

/// A word the packs' curriculum lists prescribe — the top distractor tier.
GermanWord _curriculumWord(String word, {int grade = 1}) =>
    _word(word, grade: grade, features: WordFeature.curriculum.mask);

/// Four ordinary catalogue words to draw distractors from.
List<GermanWord> _filler() => [
      _word('quiet'),
      _word('narrow'),
      _word('sudden'),
      _word('gentle'),
    ];

SynonymChallenge? _build(
  GermanWord word,
  List<GermanWord> others, {
  bool isGerman = false,
  int optionCount = 4,
  int seed = 1,
  List<GermanWord> catalogue = const [],
}) {
  final all = [word, ...others];
  return buildSynonymChallenge(
    word: word,
    allWords: all,
    known: {
      for (final w in catalogue) w.word.toLowerCase(): w,
      for (final w in all) w.word.toLowerCase(): w,
    },
    isGerman: isGerman,
    optionCount: optionCount,
    rng: Random(seed),
  );
}

void main() {
  group('isCleanSynonym', () {
    test('accepts a plain word', () => expect(isCleanSynonym('glad'), isTrue));
    test('accepts a hyphenated word',
        () => expect(isCleanSynonym('well-chosen'), isTrue));
    test(
        'accepts an apostrophe', () => expect(isCleanSynonym("don't"), isTrue));
    test('accepts two characters', () => expect(isCleanSynonym('ab'), isTrue));
    test('accepts title case', () => expect(isCleanSynonym('Begin'), isTrue));
    test('accepts German diacritics — the rule is not ASCII', () {
      expect(isCleanSynonym('Größe'), isTrue);
      expect(isCleanSynonym('schön'), isTrue);
      expect(isCleanSynonym('café'), isTrue);
    });
    test('rejects a single character (the Roman numeral I)',
        () => expect(isCleanSynonym('I'), isFalse));
    test('rejects the empty string', () => expect(isCleanSynonym(''), isFalse));
    test('rejects a digit (1st)', () => expect(isCleanSynonym('1st'), isFalse));
    test('rejects an all-caps abbreviation (AA, MBD)', () {
      expect(isCleanSynonym('AA'), isFalse);
      expect(isCleanSynonym('MBD'), isFalse);
    });
    test('rejects a two-word phrase',
        () => expect(isCleanSynonym('good afternoon'), isFalse));
  });

  group('when there is no question to ask', () {
    test('no synonyms at all', () {
      expect(_build(_word('happy'), _filler()), isNull);
    });

    test('every synonym fails the cleanliness rule', () {
      final word = _word('first', synonyms: ['1st', 'I', 'MBD', 'no way']);
      expect(_build(word, _filler()), isNull);
    });

    test('the only synonym is the word itself in another case', () {
      // The pack offers "Creator" for "creator" — not a question.
      final word = _word('creator', synonyms: ['Creator']);
      expect(_build(word, _filler()), isNull);
    });

    test('the word is a name', () {
      // "atlantic" glossed as an ocean is a name, not vocabulary.
      final word = _word('atlantic',
          synonyms: ['pacific'],
          definitions: ['An ocean between Europe, Africa and the Americas.']);
      expect(_build(word, _filler()), isNull);
    });

    test('nothing is left to use as a distractor', () {
      final word = _word('happy', synonyms: ['glad']);
      expect(_build(word, const []), isNull);
    });
  });

  group('which synonym is asked', () {
    test('a curriculum word at or below the band beats a rarer one', () {
      // "creator" lists "Almighty" first in the pack; the curriculum word is
      // the one a learner can be expected to know.
      final word = _word('happy', synonyms: ['felicitous', 'glad'], grade: 3);
      final challenge = _build(word, [
        ..._filler(),
        _word('felicitous', grade: 6),
        _curriculumWord('glad', grade: 2),
      ]);
      expect(challenge!.correctSynonym, 'glad');
    });

    test('a near-band catalogue word beats one the catalogue does not have',
        () {
      final word =
          _word('begin', synonyms: ['inaugurate', 'commence'], grade: 3);
      final challenge =
          _build(word, [..._filler(), _word('commence', grade: 4)]);
      expect(challenge!.correctSynonym, 'commence');
    });

    test('a German compound does not show its own answer', () {
      // Splitting on separators sees one part on each side, so the
      // intersection is empty however plainly the answer is written in the
      // prompt. The nightly sweep found "Schließfach" answered "Fach",
      // "hinüber" answered "hin" and "selbständig" answered "selbst".
      expect(sharesAWrittenPart('Fach', 'Schließfach'), isTrue);
      expect(sharesAWrittenPart('hin', 'hinüber'), isTrue);
      expect(sharesAWrittenPart('selbst', 'selbständig'), isTrue);
      // Two unrelated words still share nothing.
      expect(sharesAWrittenPart('Treppe', 'Stiege'), isFalse);
      expect(sharesAWrittenPart('brave', 'courageous'), isFalse);
      // And a two-letter string inside a longer word is coincidence.
      expect(sharesAWrittenPart('an', 'Banane'), isFalse);
    });

    test('a synonym no pack contains is not an answer', () {
      // It used to be, as a last resort, and that is how "which word means
      // the same as später?" came to be answered "nachmalig" — a word in
      // neither catalogue, so one the learner cannot have met.
      final word = _word('happy', synonyms: ['felicitous']);
      expect(_build(word, _filler()), isNull);
      // With the catalogue holding it, it is a fair question again.
      expect(
          _build(word, _filler(), catalogue: [_word('felicitous')])!
              .correctSynonym,
          'felicitous');
    });

    test('a synonym written inside the prompt is not asked', () {
      // "Which word means the same as high-pitched?" → high.
      final word = _word('high-pitched', synonyms: ['high', 'shrill']);
      expect(
          _build(word, _filler(), catalogue: [_word('high'), _word('shrill')])!
              .correctSynonym,
          'shrill');
    });

    test('nor one the prompt is written inside', () {
      // "white" → "lily-white", "cool" → "coolheaded" reads the same way.
      final word = _word('white', synonyms: ['lily-white', 'pale']);
      expect(
          _build(word, _filler(),
                  catalogue: [_word('lily-white'), _word('pale')])!
              .correctSynonym,
          'pale');
    });

    test('a trailing parenthetical is stripped before the rules are applied',
        () {
      final word = _word('begin', synonyms: ['commence (formal)']);
      final challenge = _build(word, _filler(), catalogue: [_word('commence')]);
      expect(challenge!.correctSynonym, 'commence');
    });

    test('English skips a capitalised synonym of a lowercase word', () {
      // "Almighty" for "creator" is the proper-noun sense.
      final word = _word('creator', synonyms: ['Almighty', 'maker']);
      expect(
          _build(word, _filler(),
                  catalogue: [_word('Almighty'), _word('maker')])!
              .correctSynonym,
          'maker');
    });

    test('German does not, since every noun is capitalised', () {
      final word =
          _word('Größe', synonyms: ['Ausmaß'], type: GermanWordType.substantiv);
      final challenge = _build(
          word,
          [
            _word('Haus', type: GermanWordType.substantiv),
            _word('Weg', type: GermanWordType.substantiv),
            _word('Baum', type: GermanWordType.substantiv),
          ],
          isGerman: true,
          catalogue: [_word('Ausmaß', type: GermanWordType.substantiv)]);
      expect(challenge!.correctSynonym, 'Ausmaß');
    });
  });

  group('the options', () {
    test('the keyed index points at the synonym', () {
      final word = _word('happy', synonyms: ['glad']);
      final challenge = _build(word, _filler(), catalogue: [_word('glad')])!;
      expect(challenge.correctIndex, inInclusiveRange(0, 3));
      expect(challenge.options[challenge.correctIndex], 'glad');
    });

    test('no distractor is another synonym of the same word', () {
      final word = _word('happy', synonyms: ['glad', 'quiet']);
      final challenge = _build(word, _filler(), catalogue: [_word('glad')])!;
      final wrong = [...challenge.options]..remove(challenge.correctSynonym);
      expect(wrong, isNot(contains('quiet')),
          reason: 'it would be keyed wrong while being right');
    });

    test('the prompt word is never offered as an answer', () {
      final word = _word('happy', synonyms: ['glad']);
      final challenge = _build(word, [..._filler(), _word('happy')],
          catalogue: [_word('glad')])!;
      expect(challenge.options, isNot(contains('happy')));
    });

    test('there are exactly optionCount options, all distinct', () {
      for (final count in [2, 3, 4, 5]) {
        final word = _word('happy', synonyms: ['glad']);
        final challenge = _build(
            word, [..._filler(), _word('eager'), _word('calm')],
            optionCount: count, catalogue: [_word('glad')])!;
        expect(challenge.options.length, count);
        expect(challenge.options.map((o) => o.toLowerCase()).toSet().length,
            count);
      }
    });

    test('distractors prefer the prompt word\'s own word type', () {
      final word = _word('happy', synonyms: ['glad']);
      final challenge = _build(word, [
        _word('quiet'),
        _word('narrow'),
        _word('sudden'),
        _word('Haus', type: GermanWordType.substantiv),
        _word('Weg', type: GermanWordType.substantiv),
      ], catalogue: [
        _word('glad')
      ])!;
      expect(challenge.options, isNot(contains('Haus')));
    });
  });

  group('buildSynonymChallenges over a pool', () {
    test('stops at maxChallenges and skips words it cannot ask about', () {
      final pool = [
        _word('happy', synonyms: ['glad']),
        _word('begin', synonyms: ['commence']),
        _word('first', synonyms: ['1st']), // unusable
        ..._filler(),
      ];
      final challenges = buildSynonymChallenges(
          pool: pool,
          catalogue: [_word('glad'), _word('commence')],
          isGerman: false,
          maxChallenges: 5,
          rng: Random(1));
      expect(challenges.map((c) => c.word.word), ['happy', 'begin']);
    });
  });
}
