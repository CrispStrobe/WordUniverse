// test/features/games/grossstadt_service_test.dart
//
// Großstadt shows a word in a frame — DAS ___, ICH ___, IST ___ — and asks
// whether it is written large or small. The frame decides the answer, so the
// frames and the forms put in them are what these cover.
//
// getPossessiveArticle has its own file: grossstadt_possessive_test.dart.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/grossstadt_service.dart';

import 'word_fixture.dart';

void main() {
  group('isInfinitive', () {
    test('accepts the three German infinitive endings', () {
      expect(isInfinitive('laufen'), isTrue);
      expect(isInfinitive('wandern'), isTrue);
      expect(isInfinitive('sammeln'), isTrue);
    });
    test('rejects a conjugated form', () {
      expect(isInfinitive('läuft'), isFalse);
      expect(isInfinitive('lief'), isFalse);
    });
  });

  group('conjugatedForm', () {
    /// The German pack's convention: three bare "present" forms, in ich / du
    /// / er order. See conjugation_drill_service.dart.
    List<Map<String, dynamic>> present(List<String> forms) => [
          for (final form in forms) {'form_text': form, 'tags': 'present'},
        ];

    test('takes the forms the pack carries', () {
      final word = testWord('lesen',
          type: GermanWordType.verb,
          wiktionaryInflections: present(['lese', 'liest', 'liest']));
      expect(conjugatedForm(word, 'ich'), 'lese');
      expect(conjugatedForm(word, 'du'), 'liest',
          reason: 'not "lesst" — the vowel changes, and only the pack knows');
    });

    test('a separable verb keeps its prefix where German puts it', () {
      final word = testWord('abbrechen',
          type: GermanWordType.verb,
          wiktionaryInflections:
              present(['breche ab', 'brichst ab', 'bricht ab']));
      expect(conjugatedForm(word, 'ich'), 'breche ab');
      expect(conjugatedForm(word, 'du'), 'brichst ab');
      expect(conjugatedForm(word, 'wir'), isNull,
          reason: '"wir abbrechen" is not German, and the pack lists no '
              'first-person plural to use instead');
    });

    test('first-person plural is the infinitive, for a verb that stays whole',
        () {
      final word = testWord('lachen',
          type: GermanWordType.verb,
          wiktionaryInflections: present(['lache', 'lachst', 'lacht']));
      expect(conjugatedForm(word, 'wir'), 'lachen');
    });

    test('nothing is invented when the pack carries no present row', () {
      // It used to conjugate regularly, which is wrong for every strong verb
      // in the language: "du sprechst", "du essst", "du gebst".
      final word = testWord('sprechen', type: GermanWordType.verb);
      expect(conjugatedForm(word, 'ich'), isNull);
      expect(conjugatedForm(word, 'du'), isNull);
      expect(conjugatedForm(word, 'wir'), isNull);
    });

    test('an imperative is never offered as a conjugated form', () {
      // "du flieg ab!" reached the game this way.
      final word = testWord('abfliegen',
          type: GermanWordType.verb,
          wiktionaryInflections: [
            {'form_text': 'flieg ab!', 'tags': 'singular, imperative'},
            {'form_text': 'fliegt ab!', 'tags': 'plural, imperative'},
          ]);
      expect(conjugatedForm(word, 'du'), isNull);
    });
  });

  group('verbVariants', () {
    /// A verb as the pack carries one: three bare "present" forms, ich / du
    /// / er. Without them there is no conjugated frame to show.
    GermanWord verb(String infinitive, List<String> forms) => testWord(
          infinitive,
          type: GermanWordType.verb,
          wiktionaryInflections: [
            for (final form in forms) {'form_text': form, 'tags': 'present'},
          ],
        );

    test('nominalised is large, conjugated and infinitive are small', () {
      final word = verb('laufen', ['laufe', 'läufst', 'läuft']);
      final items = verbVariants(word, rng: Random(1));
      expect(items.length, 3);

      final nominalized = items.firstWhere((i) => i.rule == 'nominalized_verb');
      expect(nominalized.shouldBeCapitalized, isTrue);
      expect(nominalized.target, 'laufen');
      expect(['DAS ', 'BEIM ', 'ZUM '], contains(nominalized.prefix));

      final conjugated = items.firstWhere((i) => i.rule == 'conjugated_verb');
      expect(conjugated.shouldBeCapitalized, isFalse);
      expect(['ICH ', 'DU ', 'WIR '], contains(conjugated.prefix));

      final infinitive = items.firstWhere((i) => i.rule == 'infinitive_verb');
      expect(infinitive.shouldBeCapitalized, isFalse);
      expect(['KANN ', 'MUSS ', 'WILL ', 'DARF '], contains(infinitive.prefix));
    });

    test('a word that is not an infinitive is not asked about', () {
      final word = testWord('läuft', type: GermanWordType.verb, lemma: 'läuft');
      expect(verbVariants(word, rng: Random(1)), isEmpty);
    });

    test('the same seed gives the same frames', () {
      final word = verb('laufen', ['laufe', 'läufst', 'läuft']);
      expect(
        verbVariants(word, rng: Random(7)).map((i) => i.prefix),
        verbVariants(word, rng: Random(7)).map((i) => i.prefix),
      );
    });
  });

  group('adjectiveVariants', () {
    test('nominalised is large, predicative is small', () {
      final word = testWord('gut', type: GermanWordType.adjektiv);
      final items = adjectiveVariants(word, rng: Random(1));
      final nominalized =
          items.firstWhere((i) => i.rule == 'nominalized_adjective');
      expect(nominalized.target, 'gutes');
      expect(nominalized.shouldBeCapitalized, isTrue);
      expect(['ETWAS ', 'NICHTS ', 'VIEL ', 'WENIG '],
          contains(nominalized.prefix));

      final predicative =
          items.firstWhere((i) => i.rule == 'predicative_adjective');
      expect(predicative.target, 'gut');
      expect(predicative.shouldBeCapitalized, isFalse);
    });

    test('an adjective that cannot be nominalised keeps only the small one',
        () {
      // "dunkel" would become "dunkeles"; the stem changes, so it is skipped
      // rather than shown wrong.
      final items = adjectiveVariants(
          testWord('dunkel', type: GermanWordType.adjektiv),
          rng: Random(1));
      expect(items.map((i) => i.rule), ['predicative_adjective']);
      expect(items.single.target, 'dunkel',
          reason: 'the lemma is already the base form; it must not be cut');
    });

    test('the base form is only lowercased, never trimmed', () {
      final items = adjectiveVariants(
          testWord('sauer', type: GermanWordType.adjektiv),
          rng: Random(1));
      expect(items.single.target, 'sauer');
    });
  });

  group('nounVariants', () {
    test('both frames are large, and the article is the noun\'s own', () {
      final word =
          testWord('Tisch', type: GermanWordType.substantiv, article: 'der');
      final items = nounVariants(word, rng: Random(1));
      expect(items.every((i) => i.shouldBeCapitalized), isTrue);
      expect(items.firstWhere((i) => i.rule == 'noun_standard').prefix, 'DER ');
    });

    test('a missing or unusable article falls back to DAS', () {
      final word = testWord('Ding', type: GermanWordType.substantiv);
      expect(
          nounVariants(word, rng: Random(1))
              .firstWhere((i) => i.rule == 'noun_standard')
              .prefix,
          'DAS ');
    });

    test('the possessive frame agrees with the noun\'s gender', () {
      final word =
          testWord('Stirn', type: GermanWordType.substantiv, article: 'die');
      final possessive = nounVariants(word, rng: Random(1))
          .firstWhere((i) => i.rule == 'noun_possessive');
      expect(possessive.prefix.trim(), endsWith('E'),
          reason: 'MEINE Stirn, not MEIN Stirn');
    });
  });

  test('buildCapitalizationItems keeps the three groups in order', () {
    final items = buildCapitalizationItems(
      verbs: [
        testWord('laufen', type: GermanWordType.verb, wiktionaryInflections: [
          for (final form in ['laufe', 'läufst', 'läuft'])
            {'form_text': form, 'tags': 'present'},
        ])
      ],
      adjectives: [testWord('gut', type: GermanWordType.adjektiv)],
      nouns: [
        testWord('Tisch', type: GermanWordType.substantiv, article: 'der')
      ],
      rng: Random(1),
    );
    expect(items.map((i) => i.rule), [
      'nominalized_verb',
      'conjugated_verb',
      'infinitive_verb',
      'nominalized_adjective',
      'predicative_adjective',
      'noun_standard',
      'noun_possessive',
    ]);
  });
}
