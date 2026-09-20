// test/features/games/wortbaumeister_service_test.dart
//
// Wortbaumeister splits a compound noun into two halves the learner then puts
// back together. Which split it picks is the whole game.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/wortbaumeister_service.dart';

import 'word_fixture.dart';

Map<String, GermanWord> _nouns(List<String> words) => {
      for (final word in words)
        word.toLowerCase(): testWord(word, type: GermanWordType.substantiv),
    };

void main() {
  group('findValidCompoundSplit', () {
    test('splits a compound into two nouns the pack knows', () {
      final split = findValidCompoundSplit(
          'Abendessen', _nouns(['Abend', 'Essen', 'Abendessen']));
      expect(split!.part1, 'Abend');
      expect(split.part2, 'essen');
    });

    test('allows a single Fugen-s on the modifier', () {
      // Arbeits + platz: "Arbeits" is not a word, "Arbeit" is.
      final split = findValidCompoundSplit(
          'Arbeitsplatz', _nouns(['Arbeit', 'Platz', 'Arbeitsplatz']));
      expect(split!.part1, 'Arbeits');
      expect(split.part2, 'platz');
    });

    test('prefers the balanced split when the pack allows two', () {
      // Hand|ballspiel and Handball|spiel are both noun + noun; the balanced
      // one tracks the real boundary, and returning the first match did not.
      final split = findValidCompoundSplit('Handballspiel',
          _nouns(['Hand', 'Ball', 'Spiel', 'Handball', 'Ballspiel']));
      expect(split!.part1, 'Handball');
      expect(split.part2, 'spiel');
    });

    test('refuses a split whose halves are not both nouns', () {
      // "laufen" is a verb, so "Dauerlaufen" has no noun+noun boundary.
      final map = _nouns(['Dauer']);
      map['laufen'] = testWord('laufen', type: GermanWordType.verb);
      expect(findValidCompoundSplit('Dauerlaufen', map), isNull);
    });

    test('refuses halves shorter than four letters', () {
      expect(findValidCompoundSplit('Hausbau', _nouns(['Haus', 'Bau'])), isNull,
          reason: '"Bau" is three letters, so the split is noise');
    });

    test('a word the pack cannot decompose yields nothing', () {
      expect(findValidCompoundSplit('Schmetterling', _nouns(['Schmetterling'])),
          isNull);
    });
  });

  group('buildCompoundChallenges', () {
    List<GermanWord> pool() => [
          testWord('Abendessen', type: GermanWordType.substantiv),
          testWord('Haus', type: GermanWordType.substantiv),
        ];

    Map<String, GermanWord> map() =>
        _nouns(['Abend', 'Essen', 'Abendessen', 'Haus']);

    test('asks only about words long enough to be compounds', () {
      final challenges = buildCompoundChallenges(pool(), map());
      expect(challenges.map((c) => c.fullWord), ['Abendessen'],
          reason: '"Haus" is below minCompoundLength');
      expect(minCompoundLength, 8);
    });

    test('the two halves are always written together', () {
      final challenge = buildCompoundChallenges(pool(), map()).single;
      expect(challenge.shouldBeTogether, isTrue);
      expect(challenge.mode, GameMode.nomenKomposita);
      expect(challenge.part1 + challenge.part2.toLowerCase(),
          equalsIgnoringCase('Abendessen'));
    });

    test('an example sentence becomes the context when there is a short one',
        () {
      final word = testWord('Abendessen',
          type: GermanWordType.substantiv,
          examples: [ApiExample(text: 'Wir essen um sieben zu Abend.')]);
      final challenge = buildCompoundChallenges([word], map()).single;
      expect(challenge.context, 'Wir essen um sieben zu Abend.');
    });

    test('a long example is left out, and the word speaks for itself', () {
      final word = testWord('Abendessen',
          type: GermanWordType.substantiv,
          examples: [ApiExample(text: 'Wort ' * 30)]);
      final challenge = buildCompoundChallenges([word], map()).single;
      expect(challenge.context, contains('"Abendessen"'));
    });
  });
}
