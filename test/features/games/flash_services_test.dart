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
      final challenge = build(_adj('happy', antonyms: ['sad']), [
        _adj('sad', antonyms: ['happy']),
        ...filler()
      ])!;
      expect(challenge.correctAntonym, 'sad');
      expect(challenge.options[challenge.correctIndex], 'sad');
    });

    test('every listed antonym is carried, since any is accepted on tap', () {
      final challenge = build(_adj('happy', antonyms: ['sad', 'unhappy']), [
        _adj('sad', antonyms: ['happy']),
        _adj('unhappy', antonyms: ['happy']),
        ...filler(),
      ])!;
      expect(challenge.antonyms, ['sad', 'unhappy']);
      final wrong = [...challenge.options]..remove(challenge.correctAntonym);
      expect(wrong, isNot(contains('sad')));
      expect(wrong, isNot(contains('unhappy')));
    });

    test('an "antonym" that is the word in another case is not one', () {
      expect(build(_adj('latin', antonyms: ['Latin']), filler()), isNull);
    });

    // The packs inherit Wiktionary's contrast lists, where Telefon is the
    // opposite of Telegraph and Lösung of Kolloid. Only a tenth of the pairs
    // are listed from both sides, and that tenth is the part a child would
    // call an opposite.
    test('an opposite only one side lists is not asked about', () {
      expect(
        build(_adj('happy', antonyms: ['sad']), [
          _adj('sad', antonyms: ['cheerful']),
          ...filler()
        ]),
        isNull,
      );
    });

    test('a word the pool does not hold cannot agree, so it is not asked', () {
      expect(build(_adj('happy', antonyms: ['sad']), filler()), isNull);
    });

    test('English drops a capitalised antonym of a lowercase word', () {
      // The proper-noun sense, as in Synonym Flash.
      final challenge = build(_adj('latin', antonyms: ['Romance', 'greek']), [
        _adj('romance', antonyms: ['latin']),
        _adj('greek', antonyms: ['latin']),
        ...filler(),
      ])!;
      expect(challenge.correctAntonym, 'greek');
    });

    test('German keeps one, because German capitalises nouns', () {
      final word = testWord('Hitze',
          type: GermanWordType.substantiv,
          enrichment: testEnrichment(antonyms: ['Kälte']));
      final challenge = build(
        word,
        [
          testWord('Kälte',
              type: GermanWordType.substantiv,
              enrichment: testEnrichment(antonyms: ['Hitze'])),
          testWord('Haus', type: GermanWordType.substantiv),
          testWord('Weg', type: GermanWordType.substantiv),
          testWord('Baum', type: GermanWordType.substantiv),
        ],
        isGerman: true,
      )!;
      expect(challenge.correctAntonym, 'Kälte');
    });

    test('the other half may come from the partner list, not the pool', () {
      // On a real pack the opposite is rarely in the same 200-word sample, so
      // the game looks it up separately and passes it in for this check only.
      final challenges = buildAntonymChallenges(
        pool: [
          _adj('happy', antonyms: ['sad']),
          ...filler()
        ],
        partners: [
          _adj('sad', antonyms: ['happy'])
        ],
        isGerman: false,
        rng: Random(1),
      );
      expect(challenges.single.correctAntonym, 'sad');
      // Looked up, not asked about, and never an option of its own.
      expect(challenges.single.word.word, 'happy');
    });

    test('a word with no antonyms is skipped', () {
      expect(build(_adj('happy'), filler()), isNull);
    });

    test('distractors prefer the prompt\'s word class', () {
      final challenge = build(_adj('happy', antonyms: ['sad']), [
        _adj('sad', antonyms: ['happy']),
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
      final crowd = _noun('crowd',
          hypernyms: ['displace', 'gathering'],
          definitions: ['A large gathering of people.']);
      final words = [
        crowd,
        testWord('displace', type: GermanWordType.verb),
        _noun('gathering'),
      ];
      expect(pickHypernym(crowd, isGerman: false, catalogue: catalogue(words)),
          'gathering');
    });

    test('a word is never its own hypernym', () {
      final launch = _noun('launch',
          hypernyms: ['launch', 'boat'], definitions: ['A large motor boat.']);
      final words = [launch, _noun('boat')];
      expect(pickHypernym(launch, isGerman: false, catalogue: catalogue(words)),
          'boat');
    });

    test('an abstract English verb is not an answer worth asking for', () {
      // "a rise is a kind of make" is not a question about meaning.
      final word = _noun('rise',
          hypernyms: ['make', 'movement'],
          definitions: ['To make an upward movement.']);
      final words = [word, _noun('make'), _noun('movement')];
      expect(pickHypernym(word, isGerman: false, catalogue: catalogue(words)),
          'movement');
      // The list is English, so it is not applied to the German pack.
      expect(pickHypernym(word, isGerman: true, catalogue: catalogue(words)),
          'make');
    });

    test('a hypernym naming a place is not offered', () {
      final word = _noun('alp',
          hypernyms: ['alps', 'mountain'],
          definitions: ['A high mountain, especially in the Alps.']);
      final words = [
        word,
        _noun('alps', definitions: ['A mountain range in central Europe.']),
        _noun('mountain'),
      ];
      expect(pickHypernym(word, isGerman: false, catalogue: catalogue(words)),
          'mountain');
    });

    test('without a catalogue the first clean hypernym is taken', () {
      final word = _noun('crowd',
          hypernyms: ['gathering'],
          definitions: ['A large gathering of people.']);
      expect(pickHypernym(word, isGerman: false), 'gathering');
    });

    test('an adjective is never asked, since WordNet has no hypernym for one',
        () {
      // Every hypernym listed on "deaf" was written for another word class:
      // "desensitise" is the verb's, "people" the noun's.
      final deaf = testWord('deaf',
          type: GermanWordType.adjektiv,
          enrichment:
              testEnrichment(hypernyms: [term('desensitise'), term('people')]));
      final words = [
        deaf,
        testWord('desensitise', type: GermanWordType.verb),
        _noun('people'),
      ];
      expect(pickHypernym(deaf, isGerman: false, catalogue: catalogue(words)),
          isNull);
    });

    test('a capitalised English answer to a lowercase prompt is a name sense',
        () {
      // "a boy is a kind of Black man", "a satyr is a kind of Greek deity".
      final boy = _noun('boy',
          hypernyms: ['Black man', 'male child'],
          definitions: ['A young male child; a Black man (dated, offensive).']);
      final words = [boy, _noun('Black man'), _noun('male child')];
      expect(pickHypernym(boy, isGerman: false, catalogue: catalogue(words)),
          'male child');
    });

    test('the top of WordNet is true of everything and answers nothing', () {
      final word = _noun('curiosity',
          hypernyms: ['cognitive state', 'interest'],
          definitions: ['A cognitive state of eager interest in learning.']);
      final words = [word, _noun('cognitive state'), _noun('interest')];
      expect(pickHypernym(word, isGerman: false, catalogue: catalogue(words)),
          'interest');
    });

    test('a curated relation is preferred to an unsourced one', () {
      // "poet" arrives unsourced, from the Robert Frost sense.
      final frost = testWord('frost',
          type: GermanWordType.substantiv,
          enrichment: testEnrichment(
            definitions: [
              'Ice crystals forming a white deposit; a United '
                  'States poet.'
            ],
            hypernyms: [
              term('poet'),
              term('ice', source: 'OEWN'),
            ],
          ));
      final words = [frost, _noun('poet'), _noun('ice')];
      expect(pickHypernym(frost, isGerman: false, catalogue: catalogue(words)),
          'ice');
    });

    test('a hypernym the catalogue cannot confirm is not asked about', () {
      // Nothing says which sense "affirm" was listed under, so "a show is a
      // kind of affirm" cannot be ruled out — or in.
      final show = _noun('show', hypernyms: ['affirm']);
      expect(pickHypernym(show, isGerman: false, catalogue: catalogue([show])),
          isNull);
    });

    test('only a hypernym the entry itself mentions is asked about', () {
      // The one thing in the packs that says which sense a hypernym belongs
      // to. Without it a six-year-old was asked whether "at" is a kind of
      // element — "at" is astatine, and nothing in its gloss says so.
      final at = _noun('at',
          hypernyms: ['element'],
          definitions: ['Indicating a position in space or time.']);
      final words = [at, _noun('element')];
      expect(pickHypernym(at, isGerman: false, catalogue: catalogue(words)),
          isNull);
    });

    test('among the mentioned ones, the most familiar wins', () {
      // The lists are alphabetical inside each sense group and a third of
      // them were sorted wholesale, so position says nothing: "adult male"
      // only leads because of the a. The learner should get the word they
      // have.
      final boy = _noun('boy',
          hypernyms: ['adult male', 'man'],
          definitions: ['A young man; an adult male servant (dated).']);
      final words = [
        boy,
        testWord('adult male', type: GermanWordType.substantiv, grade: 4),
        testWord('man', type: GermanWordType.substantiv, grade: 1),
      ];
      expect(pickHypernym(boy, isGerman: false, catalogue: catalogue(words)),
          'man');
    });

    test('a compound does not answer itself', () {
      // Reading the gloss for the sense turns up "Ball" for "Fußball", and
      // the prompt is then the answer with a word in front of it.
      final ball = testWord('Fußball',
          type: GermanWordType.substantiv,
          enrichment: testEnrichment(
            definitions: ['Ein Ball für das Spiel; ein Sportgerät.'],
            hypernyms: [term('Ball'), term('Sportgerät')],
          ));
      final words = [
        ball,
        testWord('Ball', type: GermanWordType.substantiv),
        testWord('Sportgerät', type: GermanWordType.substantiv),
      ];
      expect(pickHypernym(ball, isGerman: true, catalogue: catalogue(words)),
          'Sportgerät');
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

    test('the classes take turns, so "Nomen" is not always right', () {
      // German nouns outnumber everything else: a shuffled pool gave six noun
      // rounds in a row.
      final catalogue = [
        for (var i = 0; i < 20; i++)
          testWord('nomen${String.fromCharCode(97 + i % 20)}',
              type: GermanWordType.substantiv),
        testWord('laufen', type: GermanWordType.verb),
        testWord('gehen', type: GermanWordType.verb),
        testWord('schnell', type: GermanWordType.adjektiv),
      ];
      final chosen = selectWordClassCandidates(
        catalogue: catalogue,
        askableTypes: askable,
        gradeLevel: 3,
        rng: Random(1),
      ).take(4).map((w) => w.wordType).toSet();
      expect(chosen.length, greaterThan(1));
    });

    test('inflected forms and abbreviations are not asked about', () {
      final catalogue = [
        for (var i = 0; i < 12; i++)
          testWord('wort${String.fromCharCode(97 + i)}',
              type: GermanWordType.substantiv),
        testWord('Geheimnisse',
            type: GermanWordType.substantiv, lemma: 'Geheimnis'),
        testWord('PDS', type: GermanWordType.substantiv),
      ];
      final chosen = selectWordClassCandidates(
        catalogue: catalogue,
        askableTypes: askable,
        gradeLevel: 3,
        rng: Random(1),
      ).map((w) => w.word);
      expect(chosen, isNot(contains('Geheimnisse')));
      expect(chosen, isNot(contains('PDS')));
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
