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
    // lowercase because it is an adjective: the helper's default says
    // capitalized, and the sentence writes it small, which the rule below
    // now reads as a disagreement and refuses to ask about.
    final challenge = _build(
        _word('amerikanisch',
            type: GermanWordType.adjektiv,
            examples: ['Das amerikanische Auto fährt schnell.']),
        correctCase: WordCase.lowercase)!;
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

  group('the sentence in front of the learner wins', () {
    test('an adjective inside a proper name is not asked as an adjective', () {
      // "Der Europäische Gerichtshof spricht Recht für ganz Europa" was
      // asked about "Europäische" and keyed klein: an adjective everywhere
      // except in the name of a court. Keying it would teach that the
      // sentence being read is misspelled.
      expect(
        _build(
          _word('europäisch', examples: [
            'Der Europäische Gerichtshof spricht Recht für ganz Europa.'
          ]),
          correctCase: WordCase.lowercase,
        ),
        isNull,
      );
    });

    test('an ordinary adjective in mid-sentence is still asked', () {
      final challenge = _build(
        _word('traurig', examples: ['Warum bist Du heute so traurig?']),
        correctCase: WordCase.lowercase,
      )!;
      expect(challenge.targetWord, 'traurig');
    });

    test('at the start of a sentence the capital proves nothing', () {
      // Every word is capitalised there whatever its class, and the game
      // asks about that separately.
      final challenge = _build(
        _word('traurig', examples: ['Traurig war der Tag.']),
        correctCase: WordCase.lowercase,
      )!;
      expect(challenge.isAtSentenceStart, isTrue);
    });
  });

  test('the lemma is tried when the spelling itself is absent', () {
    final word =
        _word('Pflaumen', lemma: 'Pflaume', examples: ['Die Pflaume blüht.']);
    final challenge = _build(word)!;
    expect(challenge.targetWord, 'Pflaume');
  });
}
