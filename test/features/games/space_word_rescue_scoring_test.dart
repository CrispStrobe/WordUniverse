import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/services/space_word_rescue_scoring.dart';

import 'word_fixture.dart';

void main() {
  final dog = testWord('Hund', article: 'der', commonMistakes: ['Hunt']);

  test('German nouns require their capital, with or without their article', () {
    for (final answer in ['Hund', 'der Hund', 'Der Hund', '  Hund  ']) {
      expect(
        evaluateRescueSpelling(dog, answer, isGerman: true),
        RescueSpellingResult.correct,
      );
    }
    for (final answer in ['hund', 'der hund', 'HUND']) {
      expect(
        evaluateRescueSpelling(dog, answer, isGerman: true),
        RescueSpellingResult.commonMistake,
      );
    }
  });

  test('a known misspelling gets targeted feedback, never correct credit', () {
    expect(
      evaluateRescueSpelling(dog, 'Hunt', isGerman: true),
      RescueSpellingResult.commonMistake,
    );
    expect(
      evaluateRescueSpelling(dog, 'Katze', isGerman: true),
      RescueSpellingResult.incorrect,
    );
    expect(
      evaluateRescueSpelling(dog, 'die Hund', isGerman: true),
      RescueSpellingResult.incorrect,
    );
  });

  test(
    'English keeps its existing case-insensitive ordinary-word behaviour',
    () {
      final word = testWord('dog');
      expect(
        evaluateRescueSpelling(word, 'Dog', isGerman: false),
        RescueSpellingResult.correct,
      );
    },
  );
}
