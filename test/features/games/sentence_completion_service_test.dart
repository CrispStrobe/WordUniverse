// test/features/games/sentence_completion_service_test.dart
//
// Sentence Completion blanks a word out of one of the pack's grade-levelled
// example sentences. Which occurrence it blanks, and what it offers instead,
// is the game.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/adaptive_word_selection.dart';
import 'package:WortUniversum/features/games/services/sentence_completion_service.dart';

import 'word_fixture.dart';

/// Every pack entry a game may use carries a meaning; one that does not is
/// filtered out, so the fixtures carry one too.
const _def = ['Ein Ding, das man benutzt.'];

GermanWord _word(
  String word, {
  Map<String, List<String>>? examples,
  int grade = 4,
  GermanWordType type = GermanWordType.substantiv,
  List<String> definitions = const [],
}) =>
    testWord(
      word,
      type: type,
      grade: grade,
      enrichment:
          testEnrichment(gradeExamples: examples, definitions: definitions),
    );

List<GermanWord> _pool() => [
      _word('Tisch', definitions: _def),
      _word('Stuhl', definitions: _def),
      _word('Lampe', definitions: _def),
      _word('Teppich', definitions: _def),
    ];

void main() {
  group('blankWord', () {
    test('cuts the word out on a word boundary', () {
      expect(blankWord('Der Hund bellt.', 'Hund'), ('Der ', ' bellt.'));
    });

    test('is case-insensitive', () {
      expect(blankWord('Hund bellt.', 'hund'), ('', ' bellt.'));
    });

    test('takes an inflected form with a short ending', () {
      expect(blankWord('Die Hunde bellen.', 'Hund'), ('Die ', ' bellen.'));
    });

    test('refuses a longer word that merely starts the same', () {
      // "Hunderte" is not an inflection of "Hund".
      expect(blankWord('Hunderte kamen.', 'Hund'), isNull);
    });

    test('returns nothing when the word is absent', () {
      expect(blankWord('Die Katze schläft.', 'Hund'), isNull);
    });
  });

  group('hasGradeExamples', () {
    test('true for the asked grade', () {
      final word = _word('Tisch', examples: {
        '4': ['Der Tisch ist rund.']
      });
      expect(hasGradeExamples(word, 4), isTrue);
    });

    test('falls back to any grade the pack does have', () {
      final word = _word('Tisch', examples: {
        '2': ['Der Tisch ist rund.']
      });
      expect(hasGradeExamples(word, 6), isTrue);
    });

    test('false without grade examples', () {
      expect(hasGradeExamples(_word('Tisch'), 4), isFalse);
    });
  });

  group('buildSentenceChallenge', () {
    test('blanks the word and keeps the rest of the sentence', () {
      final word = _word('Tisch', examples: {
        '4': ['Der Tisch steht im Zimmer.']
      });
      final challenge = buildSentenceChallenge(
          word: word, gradeIndex: 4, pool: _pool(), rng: Random(1))!;
      expect(challenge.before, 'Der ');
      expect(challenge.after, ' steht im Zimmer.');
      expect(challenge.correctOption, 'Tisch');
      expect(challenge.options[challenge.correctIndex], 'Tisch');
    });

    test('the bare noun is offered, never with an article', () {
      // The sentence supplies the article in its own case: "Ich sehe den ___".
      final word = testWord('Tisch',
          type: GermanWordType.substantiv,
          article: 'der',
          enrichment: testEnrichment(gradeExamples: {
            '4': ['Ich sehe den Tisch.']
          }));
      final challenge = buildSentenceChallenge(
          word: word, gradeIndex: 4, pool: _pool(), rng: Random(1))!;
      expect(challenge.correctOption, 'Tisch');
      expect(challenge.options, isNot(contains('der Tisch')));
    });

    test('skips a sentence that says the word again beside the gap', () {
      final word = _word('Tisch', examples: {
        '4': [
          'Der Tisch ist ein Tisch.',
          'Der Tisch steht im Zimmer.',
        ]
      });
      final challenge = buildSentenceChallenge(
          word: word, gradeIndex: 4, pool: _pool(), rng: Random(1))!;
      expect('${challenge.before}${challenge.after}', isNot(contains('Tisch')));
    });

    test('nothing is built when no sentence contains the word', () {
      final word = _word('Tisch', examples: {
        '4': ['Die Lampe leuchtet hell.']
      });
      expect(
          buildSentenceChallenge(
              word: word, gradeIndex: 4, pool: _pool(), rng: Random(1)),
          isNull);
    });

    test('nothing is built without a pool to draw distractors from', () {
      final word = _word('Tisch', examples: {
        '4': ['Der Tisch steht im Zimmer.']
      });
      expect(
          buildSentenceChallenge(
              word: word, gradeIndex: 4, pool: [word], rng: Random(1)),
          isNull);
    });

    test('distractors share the prompt\'s word class', () {
      final word = _word('Tisch', examples: {
        '4': ['Der Tisch steht im Zimmer.']
      });
      final pool = [
        word,
        _word('Stuhl'),
        _word('Lampe'),
        _word('Teppich'),
        _word('laufen', type: GermanWordType.verb),
      ];
      final challenge = buildSentenceChallenge(
          word: word, gradeIndex: 4, pool: pool, rng: Random(1))!;
      expect(challenge.options, isNot(contains('laufen')));
    });

    test('another word class fills in rather than leave the round short', () {
      final word = _word('Tisch', examples: {
        '4': ['Der Tisch steht im Zimmer.']
      });
      final pool = [
        word,
        _word('Stuhl'),
        _word('laufen', type: GermanWordType.verb),
        _word('springen', type: GermanWordType.verb),
      ];
      final challenge = buildSentenceChallenge(
          word: word, gradeIndex: 4, pool: pool, rng: Random(1))!;
      expect(challenge.options.length, 4);
      expect(challenge.options, contains('Stuhl'));
    });
  });

  group('buildSentenceChallenges', () {
    test('skips names and stops at maxChallenges', () {
      final pool = [
        _word('Tisch', definitions: _def, examples: {
          '4': ['Der Tisch steht im Zimmer.']
        }),
        _word('columbia', definitions: [
          'A city in South Carolina, United States.'
        ], examples: {
          '4': ['Wir fahren nach columbia.']
        }),
        // No meaning at all: "iot" was asked as "___ has practical uses."
        _word('iot', examples: {
          '4': ['Das iot hat viele Anwendungen.']
        }),
        _word('Stuhl', definitions: _def, examples: {
          '4': ['Der Stuhl ist bequem und alt.']
        }),
        ..._pool(),
      ];
      final challenges = buildSentenceChallenges(
          pool: pool, gradeIndex: 4, maxChallenges: 1, rng: Random(1));
      expect(challenges.single.word.word, 'Tisch');

      final all = buildSentenceChallenges(
          pool: pool, gradeIndex: 4, maxChallenges: 10, rng: Random(1));
      expect(all.map((c) => c.word.word), ['Tisch', 'Stuhl'],
          reason: 'a name and a word with no meaning are both skipped');
    });
  });

  test('baseWordFromSriId strips the skill prefix the queue carries', () {
    // Shared by the six practice games; the rest of selectAdaptiveWords needs
    // a live catalogue, and is covered by the audit harness instead.
    expect(baseWordFromSriId('SPELL_Tisch'), 'Tisch');
    expect(baseWordFromSriId('TYPE_laufen'), 'laufen');
    expect(baseWordFromSriId('Tisch'), 'Tisch');
    expect(baseWordFromSriId(''), isNull);
  });
}
