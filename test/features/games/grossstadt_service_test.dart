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
    test('prefers the form the pack carries', () {
      final word =
          testWord('laufen', type: GermanWordType.verb, wiktionaryInflections: [
        {'form_text': 'läufst', 'tags': 'present second-person singular'},
        {'form_text': 'lief', 'tags': 'past first-person singular'},
      ]);
      expect(conjugatedForm(word, 'du'), 'läufst');
    });

    test('reads tags given as a list as well as a string', () {
      final word =
          testWord('laufen', type: GermanWordType.verb, wiktionaryInflections: [
        {
          'form_text': 'laufe',
          'tags': ['present', 'first-person', 'singular'],
        },
      ]);
      expect(conjugatedForm(word, 'ich'), 'laufe');
    });

    test('never answers with a past form or a participle', () {
      final word =
          testWord('laufen', type: GermanWordType.verb, wiktionaryInflections: [
        {'form_text': 'gelaufen', 'tags': 'participle perfect'},
        {'form_text': 'liefst', 'tags': 'past second-person singular'},
      ]);
      // Falls through to the regular conjugation instead.
      expect(conjugatedForm(word, 'du'), 'laufst');
    });

    test('falls back to regular conjugation when the pack has nothing', () {
      final word = testWord('lachen', type: GermanWordType.verb);
      expect(conjugatedForm(word, 'ich'), 'lache');
      expect(conjugatedForm(word, 'du'), 'lachst');
      expect(conjugatedForm(word, 'wir'), 'lachen');
    });

    test('a lemma that is not an -en infinitive has no fallback form', () {
      final word = testWord('wandern', type: GermanWordType.verb);
      expect(conjugatedForm(word, 'ich'), isNull);
    });
  });

  group('verbVariants', () {
    test('nominalised is large, conjugated and infinitive are small', () {
      final word = testWord('laufen', type: GermanWordType.verb);
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
      final word = testWord('laufen', type: GermanWordType.verb);
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
      verbs: [testWord('laufen', type: GermanWordType.verb)],
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
