import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/services/spelling_spotter_challenges.dart';

import 'word_fixture.dart';

void main() {
  test(
    'fallback context uses the requested grade key, not first map entry',
    () {
      final word = testWord(
        'Hund',
        commonMistakes: ['Hunt'],
        enrichment: testEnrichment(
          gradeExamples: {
            '1': ['Der Hund ist klein.'],
            '4': ['Der Hund wartet geduldig vor dem Haus.'],
          },
        ),
      );
      final challenge = buildSpellingChallenge(
        word: word,
        allErrors: ['Hunt'],
        validWords: {'hund'},
        isGerman: true,
        gradeLevel: 4,
        rng: Random(1),
      )!;
      expect(
        challenge.contextSentence,
        'Der Hund wartet geduldig vor dem Haus.',
      );
    },
  );

  test(
    'context must contain the word, not merely the start of another word',
    () {
      final word = testWord(
        'Hund',
        commonMistakes: ['Hunt'],
        enrichment: testEnrichment(
          gradeExamples: {
            '4': ['Hundert Kinder spielen auf dem Platz.'],
          },
        ),
      );
      final challenge = buildSpellingChallenge(
        word: word,
        allErrors: ['Hunt'],
        validWords: {'hund'},
        isGerman: true,
        gradeLevel: 4,
        rng: Random(1),
      )!;
      expect(challenge.contextSentence, isNull);
    },
  );
}
