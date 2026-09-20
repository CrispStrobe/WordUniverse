// test/features/games/flash_services_test.dart
//
// The three "flash" services that ask about a word's relations or its class:
// Antonym Flash, Hypernym Flash and Word Class Flash. Each rule here is one
// the packs made necessary — a hypernym listed under a sense of another word
// class, an "antonym" that is the word itself in another case, a surface form
// that belongs to two word classes at once.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/antonym_flash_service.dart';
import 'package:WortUniversum/features/games/services/hypernym_flash_service.dart';
import 'package:WortUniversum/features/games/services/word_class_flash_service.dart';

import 'word_fixture.dart';

GermanWord _adj(String word, {List<String> antonyms = const []}) => testWord(
      word,
      type: GermanWordType.adjektiv,
      enrichment: testEnrichment(antonyms: antonyms),
    );

GermanWord _noun(String word,
        {List<String> hypernyms = const [],
        List<String> definitions = const []}) =>
    testWord(
      word,
      type: GermanWordType.substantiv,
      enrichment: testEnrichment(
        hypernyms: [for (final h in hypernyms) term(h)],
        definitions: definitions,
      ),
    );

void main() {
  group('Antonym Flash', () {
    List<GermanWord> filler() =>
        [_adj('quiet'), _adj('narrow'), _adj('sudden'), _adj('gentle')];

    AntonymChallenge? build(GermanWord word, List<GermanWord> others,
            {bool isGerman = false, int optionCount = 4, int seed = 1}) =>
        buildAntonymChallenge(
          word: word,
          allWords: [word, ...others],
          isGerman: isGerman,
          optionCount: optionCount,
          rng: Random(seed),
        );

    test('asks one of the listed antonyms', () {
      final challenge = build(_adj('happy', antonyms: ['sad']), filler())!;
      expect(challenge.correctAntonym, 'sad');
      expect(challenge.options[challenge.correctIndex], 'sad');
    });

    test('every listed antonym is carried, since any is accepted on tap', () {
      final challenge =
          build(_adj('happy', antonyms: ['sad', 'unhappy']), filler())!;
      expect(challenge.antonyms, ['sad', 'unhappy']);
      final wrong = [...challenge.options]..remove(challenge.correctAntonym);
      expect(wrong, isNot(contains('sad')));
      expect(wrong, isNot(contains('unhappy')));
    });

    test('an "antonym" that is the word in another case is not one', () {
      expect(build(_adj('latin', antonyms: ['Latin']), filler()), isNull);
    });

    test('English drops a capitalised antonym of a lowercase word', () {
      // The proper-noun sense, as in Synonym Flash.
      final challenge =
          build(_adj('latin', antonyms: ['Romance', 'greek']), filler())!;
      expect(challenge.correctAntonym, 'greek');
    });

    test('German keeps one, because German capitalises nouns', () {
      final word = testWord('Hitze',
          type: GermanWordType.substantiv,
          enrichment: testEnrichment(antonyms: ['Kälte']));
      final challenge = build(
        word,
        [
          testWord('Haus', type: GermanWordType.substantiv),
          testWord('Weg', type: GermanWordType.substantiv),
          testWord('Baum', type: GermanWordType.substantiv),
        ],
        isGerman: true,
      )!;
      expect(challenge.correctAntonym, 'Kälte');
    });

    test('a word with no antonyms is skipped', () {
      expect(build(_adj('happy'), filler()), isNull);
    });

    test('distractors prefer the prompt\'s word class', () {
      final challenge = build(_adj('happy', antonyms: ['sad']), [
        _adj('quiet'),
        _adj('narrow'),
        _adj('sudden'),
        testWord('Haus', type: GermanWordType.substantiv),
      ])!;
      expect(challenge.options, isNot(contains('Haus')));
    });
  });

  group('Hypernym Flash', () {
    Map<String, GermanWord> catalogue(List<GermanWord> words) =>
        {for (final w in words) w.word.toLowerCase(): w};

    test('asks for a hypernym the catalogue holds with the same word class',
        () {
      // The packs list hypernyms across every WordNet sense: "crowd" is also
      // a verb, and "displace" is the hypernym of *that* sense.
      final crowd = _noun('crowd', hypernyms: ['displace', 'gathering']);
      final words = [
        crowd,
        testWord('displace', type: GermanWordType.verb),
        _noun('gathering'),
      ];
      expect(pickHypernym(crowd, isGerman: false, catalogue: catalogue(words)),
          'gathering');
    });

    test('a word is never its own hypernym', () {
      final launch = _noun('launch', hypernyms: ['launch', 'boat']);
      final words = [launch, _noun('boat')];
      expect(pickHypernym(launch, isGerman: false, catalogue: catalogue(words)),
          'boat');
    });

    test('an abstract English verb is not an answer worth asking for', () {
      // "a rise is a kind of make" is not a question about meaning.
      final word = _noun('rise', hypernyms: ['make', 'movement']);
      final words = [word, _noun('make'), _noun('movement')];
      expect(pickHypernym(word, isGerman: false, catalogue: catalogue(words)),
          'movement');
      // The list is English, so it is not applied to the German pack.
      expect(pickHypernym(word, isGerman: true, catalogue: catalogue(words)),
          'make');
    });

    test('a hypernym naming a place is not offered', () {
      final word = _noun('alp', hypernyms: ['alps', 'mountain']);
      final words = [
        word,
        _noun('alps', definitions: ['A mountain range in central Europe.']),
        _noun('mountain'),
      ];
      expect(pickHypernym(word, isGerman: false, catalogue: catalogue(words)),
          'mountain');
    });

    test('without a catalogue the first clean hypernym is taken', () {
      final word = _noun('crowd', hypernyms: ['gathering']);
      expect(pickHypernym(word, isGerman: false), 'gathering');
    });

    test('no other hypernym of the same word is ever a distractor', () {
      // Any of them would be right, so keying one wrong is unfair.
      final word = _noun('crowd', hypernyms: ['gathering', 'group', 'set']);
      final challenge = buildHypernymChallenge(
        word: word,
        correct: 'gathering',
        hypernymPool: ['group', 'set', 'vehicle', 'building', 'tool'],
        rng: Random(1),
      )!;
      expect(challenge.options, isNot(contains('group')));
      expect(challenge.options, isNot(contains('set')));
      expect(challenge.options[challenge.correctIndex], 'gathering');
    });
  });

  group('Word Class Flash', () {
    const askable = {
      GermanWordType.substantiv,
      GermanWordType.verb,
      GermanWordType.adjektiv,
    };

    test('drops a spelling that belongs to two word classes', () {
      // "laut" is adjective, adverb and noun: more than one answer is right.
      final catalogue = [
        testWord('laut', type: GermanWordType.adjektiv),
        testWord('laut', type: GermanWordType.substantiv),
        for (var i = 0; i < 12; i++)
          testWord('wort$i', type: GermanWordType.substantiv),
      ];
      final chosen = selectWordClassCandidates(
        catalogue: catalogue,
        askableTypes: askable,
        gradeLevel: 3,
        rng: Random(1),
      );
      expect(chosen.map((w) => w.word), isNot(contains('laut')));
      expect(chosen, isNotEmpty);
    });

    test('keeps the ambiguous words rather than leave too few to play', () {
      final catalogue = [
        testWord('laut', type: GermanWordType.adjektiv),
        testWord('laut', type: GermanWordType.substantiv),
        testWord('Haus', type: GermanWordType.substantiv),
      ];
      final chosen = selectWordClassCandidates(
        catalogue: catalogue,
        askableTypes: askable,
        gradeLevel: 3,
        rng: Random(1),
      );
      expect(chosen.length, 3);
    });

    test('word classes the game does not ask about are excluded', () {
      final catalogue = [
        for (var i = 0; i < 12; i++)
          testWord('wort$i', type: GermanWordType.substantiv),
        testWord('schnell', type: GermanWordType.adverb),
      ];
      final chosen = selectWordClassCandidates(
        catalogue: catalogue,
        askableTypes: askable,
        gradeLevel: 3,
        rng: Random(1),
      );
      expect(chosen.map((w) => w.word), isNot(contains('schnell')));
    });

    test('names and multi-word entries are never asked about', () {
      final catalogue = [
        for (var i = 0; i < 12; i++)
          testWord('wort$i', type: GermanWordType.substantiv),
        testWord('Berlin', type: GermanWordType.substantiv, isProperNoun: true),
        testWord('columbia',
            type: GermanWordType.substantiv,
            enrichment: testEnrichment(
                definitions: ['A city in South Carolina, United States.'])),
        testWord('zum Beispiel', type: GermanWordType.substantiv),
      ];
      final chosen = selectWordClassCandidates(
        catalogue: catalogue,
        askableTypes: askable,
        gradeLevel: 3,
        rng: Random(1),
      ).map((w) => w.word);
      expect(chosen, isNot(contains('Berlin')));
      expect(chosen, isNot(contains('columbia')));
      expect(chosen, isNot(contains('zum Beispiel')));
    });

    test('the answer is the word\'s own class', () {
      final challenges = buildWordClassChallenges(
        words: [testWord('Haus', type: GermanWordType.substantiv)],
        maxChallenges: 5,
      );
      expect(challenges.single.correctType, GermanWordType.substantiv);
    });
  });
}
