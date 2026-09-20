// test/features/games/verbtrenner_service_test.dart
//
// Trennbare Verben drops a verb form and asks whether it is written apart or
// joined. Only some of Wiktionary's forms are a fair question — the rest
// produced tiles no rule explains, which is what most of these cover.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/verbtrenner_service.dart';

import 'word_fixture.dart';

Map<String, dynamic> _form(String text, String tags) =>
    {'form_text': text, 'tags': tags};

GermanWord _verb(
  String infinitive, {
  required List<Map<String, dynamic>> forms,
  List<String> examples = const [],
}) =>
    testWord(
      infinitive,
      type: GermanWordType.verb,
      enrichment: testEnrichment(
        inflections: forms,
        examples: [for (final text in examples) ApiExample(text: text)],
      ),
    );

void main() {
  group('isAskableSeparableForm', () {
    test('accepts a separated finite form and a joined infinitive', () {
      expect(isAskableSeparableForm('stehe auf'), isTrue);
      expect(isAskableSeparableForm('aufstehen'), isTrue);
    });

    test('rejects a zu-infinitive, infixed or spaced', () {
      expect(isAskableSeparableForm('aufzustehen'), isFalse);
      expect(isAskableSeparableForm('vorzutragen'), isFalse);
      expect(isAskableSeparableForm('eingezogen zu sein'), isFalse);
      expect(isAskableSeparableForm('zu kommen'), isFalse);
    });

    test('rejects a past participle', () {
      // "auf … gefordert" matches no rule the game explains.
      expect(isAskableSeparableForm('aufgefordert'), isFalse);
      expect(isAskableSeparableForm('angekommen'), isFalse);
    });

    test('rejects nothing at all', () {
      expect(isAskableSeparableForm(''), isFalse);
      expect(isAskableSeparableForm('   '), isFalse);
    });
  });

  group('isVerbSeparable', () {
    test('true when a form splits off a separable prefix', () {
      final verb = _verb('aufstehen', forms: [
        _form('stehe auf', 'present first-person singular'),
      ]);
      expect(isVerbSeparable(verb), isTrue);
    });

    test('false for a verb whose second word is not a prefix', () {
      final verb = _verb('sich freuen', forms: [
        _form('freue mich', 'present first-person singular'),
      ]);
      expect(isVerbSeparable(verb), isFalse);
    });

    test('false when no form splits at all', () {
      final verb = _verb('lachen', forms: [
        _form('lache', 'present first-person singular'),
      ]);
      expect(isVerbSeparable(verb), isFalse);
    });
  });

  group('findRealExample', () {
    test('takes a sentence that actually contains the form', () {
      expect(
        findRealExample(
          apiExamples: [ApiExample(text: 'Ich stehe früh auf.')],
          tataoebaExamples: const [],
          formText: 'stehe auf',
        ),
        isNull,
        reason: 'the sentence has the parts split, not the form as written',
      );
      expect(
        findRealExample(
          apiExamples: [ApiExample(text: 'Wann willst du aufstehen?')],
          tataoebaExamples: const [],
          formText: 'aufstehen',
        ),
        'Wann willst du aufstehen?',
      );
    });

    test('never falls back to an unrelated sentence', () {
      // It used to attach "Komm doch mal vor zu mir!" to "vorzukommen".
      expect(
        findRealExample(
          apiExamples: [ApiExample(text: 'Komm doch mal vor zu mir!')],
          tataoebaExamples: const ['Ein ganz anderer Satz.'],
          formText: 'vorzukommen',
        ),
        isNull,
      );
    });

    test('falls back from the enrichment to the pack\'s own sentences', () {
      expect(
        findRealExample(
          apiExamples: const [],
          tataoebaExamples: const ['Wann willst du aufstehen?'],
          formText: 'aufstehen',
        ),
        'Wann willst du aufstehen?',
      );
    });
  });

  group('pairsFromVerb', () {
    test('a conjugated form is asked as GETRENNT', () {
      final verb = _verb('aufstehen', forms: [
        _form('stehe auf', 'present first-person singular'),
      ], examples: [
        'Ich stehe auf und gehe.',
      ]);
      final pair = pairsFromVerb(verb).single;
      expect(pair.shouldBeSeparated, isTrue);
      expect([pair.part1, pair.part2], ['stehe', 'auf']);
      expect(pair.context, 'Ich stehe auf und gehe.');
    });

    test('the plain infinitive is asked as ZUSAMMEN', () {
      final verb = _verb('aufstehen', forms: [
        _form('stehe auf', 'present first-person singular'),
        _form('aufstehen', 'infinitive'),
      ], examples: [
        'Wann willst du aufstehen?',
      ]);
      final joined =
          pairsFromVerb(verb).where((p) => !p.shouldBeSeparated).single;
      expect([joined.part1, joined.part2], ['auf', 'stehen']);
      expect(joined.explanation, contains('zusammen'));
    });

    test('a form with no sentence of its own is not asked', () {
      final verb = _verb('aufstehen', forms: [
        _form('stehe auf', 'present first-person singular'),
      ], examples: [
        'Ein Satz ohne diese Form.',
      ]);
      expect(pairsFromVerb(verb), isEmpty);
    });

    test('participles and zu-infinitives never become tiles', () {
      final verb = _verb('aufstehen', forms: [
        _form('stehe auf', 'present first-person singular'),
        _form('aufgestanden', 'participle perfect'),
        _form('aufzustehen', 'extended infinitive'),
      ], examples: [
        'Ich stehe auf und gehe.',
        'Er ist aufgestanden.',
        'Es ist Zeit aufzustehen.',
      ]);
      expect(pairsFromVerb(verb).map((p) => p.formText), ['stehe auf']);
    });

    test('a verb with no separable prefix yields nothing', () {
      final verb = _verb('lachen', forms: [
        _form('lache', 'present first-person singular'),
      ], examples: [
        'Ich lache viel.',
      ]);
      expect(pairsFromVerb(verb), isEmpty);
    });
  });

  group('buildVerbPairs', () {
    test('skips inseparable verbs and caps how many it returns', () {
      final verbs = [
        for (var i = 0; i < 30; i++)
          _verb('aufstehen$i', forms: [
            _form('stehe auf', 'present first-person singular'),
          ], examples: [
            'Ich stehe auf und gehe.',
          ]),
        _verb('lachen', forms: [
          _form('lache', 'present first-person singular'),
        ], examples: [
          'Ich lache viel.',
        ]),
      ];
      final pairs = buildVerbPairs(verbs: verbs, maxPairs: 12, rng: Random(1));
      expect(pairs.length, 12);
      expect(pairs.every((p) => p.shouldBeSeparated), isTrue);
    });
  });
}
