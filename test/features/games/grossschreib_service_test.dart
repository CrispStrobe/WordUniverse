// test/features/games/grossschreib_service_test.dart
//
// Großschreib-Rakete shows a sentence with one word to judge: capital or
// small. Finding that word in the sentence is where it goes wrong — an
// inflected form, a word at the start, a lemma that is a prefix of another
// word.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/grossschreib_service.dart';

import 'word_fixture.dart';

GermanWord _word(String word,
        {String? lemma,
        List<String> examples = const [],
        GermanWordType type = GermanWordType.substantiv}) =>
    testWord(
      word,
      lemma: lemma,
      type: type,
      examples: [for (final text in examples) ApiExample(text: text)],
    );

SentenceChallenge? _build(
  GermanWord word, {
  WordCase correctCase = WordCase.capitalized,
  bool forceMiddlePosition = false,
  bool forceSentenceStart = false,
}) =>
    challengeFromWord(
      word,
      correctCase: correctCase,
      rule: CapitalizationRule.noun,
      explanation: 'Nomen schreibt man groß.',
      forceMiddlePosition: forceMiddlePosition,
      forceSentenceStart: forceSentenceStart,
    );

void main() {
  test('cuts the sentence around the word', () {
    final challenge =
        _build(_word('Pflaumen', examples: ['Die Pflaumen blühen.']))!;
    expect(challenge.beforeWord, 'Die ');
    expect(challenge.targetWord, 'Pflaumen');
    expect(challenge.afterWord, ' blühen.');
    expect(challenge.fullSentence, 'Die Pflaumen blühen.');
  });

  test('takes the inflected form the sentence actually uses', () {
    final challenge = _build(_word('amerikanisch',
        type: GermanWordType.adjektiv,
        examples: ['Das amerikanische Auto fährt schnell.']))!;
    expect(challenge.targetWord, 'amerikanische');
    expect(challenge.fullSentence, 'Das amerikanische Auto fährt schnell.');
  });

  test('a word at the start of the sentence is marked as such', () {
    final challenge =
        _build(_word('Pflaumen', examples: ['Pflaumen blühen.']))!;
    expect(challenge.isAtSentenceStart, isTrue);
    expect(challenge.beforeWord, isEmpty);
  });

  test('an opening quotation mark does not hide the sentence start', () {
    final challenge =
        _build(_word('Pflaumen', examples: ['„Pflaumen blühen.“']))!;
    expect(challenge.isAtSentenceStart, isTrue);
  });

  test('a word after a full stop is at a sentence start too', () {
    final challenge = _build(
        _word('Pflaumen', examples: ['Es ist Mai. Pflaumen blühen jetzt.']))!;
    expect(challenge.isAtSentenceStart, isTrue);
  });

  group('position requirements', () {
    test('forceMiddlePosition skips a sentence that starts with the word', () {
      final word = _word('Pflaumen', examples: [
        'Pflaumen blühen.',
        'Die Pflaumen blühen im Mai.',
      ]);
      final challenge = _build(word, forceMiddlePosition: true)!;
      expect(challenge.fullSentence, 'Die Pflaumen blühen im Mai.');
    });

    test('forceSentenceStart skips a sentence where the word is in the middle',
        () {
      final word = _word('Pflaumen', examples: [
        'Die Pflaumen blühen im Mai.',
        'Pflaumen blühen.',
      ]);
      final challenge = _build(word, forceSentenceStart: true)!;
      expect(challenge.fullSentence, 'Pflaumen blühen.');
    });

    test('nothing is returned when no example meets the requirement', () {
      final word = _word('Pflaumen', examples: ['Pflaumen blühen.']);
      expect(_build(word, forceMiddlePosition: true), isNull);
    });
  });

  group('sentences it refuses', () {
    test('a word with no examples', () {
      expect(_build(_word('Pflaumen')), isNull);
    });

    test('a sentence longer than the tile can show', () {
      expect(
        _build(_word('Pflaumen',
            examples: ['Die Pflaumen ${'blühen sehr schön ' * 10}.'])),
        isNull,
      );
    });

    test('a sentence that does not contain the word', () {
      expect(
        _build(_word('Pflaumen', examples: ['Die Äpfel blühen.'])),
        isNull,
      );
    });

    test('a word that only appears inside another word', () {
      // \b on the front: "Pflaume" must not be found inside "Zwetschgen-
      // pflaume" written as one token without a boundary.
      expect(
        _build(_word('flaume', examples: ['Die Pflaumen blühen.'])),
        isNull,
      );
    });
  });

  test('the lemma is tried when the spelling itself is absent', () {
    final word =
        _word('Pflaumen', lemma: 'Pflaume', examples: ['Die Pflaume blüht.']);
    final challenge = _build(word)!;
    expect(challenge.targetWord, 'Pflaume');
  });
}
