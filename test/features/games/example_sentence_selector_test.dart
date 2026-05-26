// test/features/games/example_sentence_selector_test.dart
//
// Unit tests for pickExampleSentence() — the three-tier example pipeline:
// gradeExamples → exampleSentences → gutenbergExamples.
// Tests confirm which source wins at each tier, labelling, truncation,
// and realistic DE/EN sentences users would actually see.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/services/example_sentence_selector.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({
  Map<String, List<String>>? gradeExamples,
  List<String> gutenbergExamples = const [],
}) =>
    ApiEnrichment(
      enrichmentStatus: 'ok',
      definitions: const ['a definition'],
      pronunciation: const [],
      examples: const [],
      synonyms: const [],
      antonyms: const [],
      conceptnet: const [],
      alternativeAnalyses: const [],
      inflections: const [],
      semanticRelations: const [],
      hyphenation: const [],
      translations: const [],
      derivedTerms: const [],
      relatedTerms: const [],
      expressions: const [],
      proverbs: const [],
      entryNotes: const [],
      hypernyms: const [],
      hyponyms: const [],
      holonyms: const [],
      meronyms: const [],
      coordinateTerms: const [],
      gradeExamples: gradeExamples,
      gutenbergExamples: gutenbergExamples,
      commonLearnerErrors: const [],
    );

GermanWord _word(
  String word, {
  List<String> exampleSentences = const [],
  ApiEnrichment? api,
}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: GermanWordType.substantiv,
      gradeLevel: 1,
      lemma: word,
      sources: const [],
      isGrundwortschatzBW: false,
      nurImPlural: false,
      graphematicVariants: const [],
      categories: const [],
      exampleSentences: exampleSentences,
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: false,
      entryNotes: const [],
      apiEnrichment: api,
      examples: const [],
      hyphenation: const [],
      wiktionaryInflections: const [],
      translations: const [],
      derivedTerms: const [],
      relatedTerms: const [],
      expressions: const [],
      proverbs: const [],
      hypernyms: const [],
      hyponyms: const [],
      holonyms: const [],
      meronyms: const [],
      coordinateTerms: const [],
    );

// ─── Null / empty cases ────────────────────────────────────────────────────

void main() {
  group('pickExampleSentence — null/empty', () {
    test('returns null when word has no examples at all', () {
      expect(pickExampleSentence(_word('still')), isNull);
    });

    test('returns null when api is present but all example sources empty', () {
      final w = _word('still', api: _enrichment());
      expect(pickExampleSentence(w), isNull);
    });

    test('returns null when gradeExamples present but empty for all grades', () {
      final w = _word('still', api: _enrichment(gradeExamples: {'1': [], '2': []}));
      expect(pickExampleSentence(w, gradeLevel: GradeLevel.grade3), isNull);
    });
  });

  // ─── Tier 1: gradeExamples ──────────────────────────────────────────────

  group('pickExampleSentence — tier 1: gradeExamples', () {
    test('returns grade-keyed sentence with "Beispiel" label', () {
      final w = _word('laufen', api: _enrichment(
        gradeExamples: {'1': ['Der Hund läuft schnell.']},
        gutenbergExamples: ['A Gutenberg sentence.'],
      ));
      final r = pickExampleSentence(w, gradeLevel: GradeLevel.grade1);
      expect(r, isNotNull);
      expect(r!.text, 'Der Hund läuft schnell.');
      expect(r.label, 'Beispiel');
    });

    test('grade-keyed sentence wins over exampleSentences', () {
      final w = _word('laufen',
        exampleSentences: ['ExampleSentences entry.'],
        api: _enrichment(gradeExamples: {'2': ['Grade 2 example.']}),
      );
      final r = pickExampleSentence(w, gradeLevel: GradeLevel.grade2);
      expect(r!.text, 'Grade 2 example.');
    });

    test('grade-keyed sentence wins over Gutenberg', () {
      final w = _word('laufen', api: _enrichment(
        gradeExamples: {'3': ['Grade 3 sentence.']},
        gutenbergExamples: ['Gutenberg sentence.'],
      ));
      final r = pickExampleSentence(w, gradeLevel: GradeLevel.grade3);
      expect(r!.text, 'Grade 3 sentence.');
      expect(r.label, 'Beispiel');
    });

    test('falls back to any grade key when exact grade absent', () {
      final w = _word('laufen', api: _enrichment(
        gradeExamples: {'5': ['Grade 5 sentence.']},
      ));
      // asking for grade 2 — key '2' absent, falls back to first available
      final r = pickExampleSentence(w, gradeLevel: GradeLevel.grade2);
      expect(r!.text, 'Grade 5 sentence.');
    });
  });

  // ─── Tier 2: exampleSentences ────────────────────────────────────────────

  group('pickExampleSentence — tier 2: exampleSentences', () {
    test('returns exampleSentence when gradeExamples absent', () {
      final w = _word('Hund', exampleSentences: ['Der Hund bellt.']);
      final r = pickExampleSentence(w);
      expect(r!.text, 'Der Hund bellt.');
      expect(r.label, 'Beispiel');
    });

    test('exampleSentences wins over Gutenberg', () {
      final w = _word('Hund',
        exampleSentences: ['Der Hund bellt.'],
        api: _enrichment(gutenbergExamples: ['A Gutenberg example.']),
      );
      final r = pickExampleSentence(w);
      expect(r!.text, 'Der Hund bellt.');
      expect(r.label, 'Beispiel');
    });

    test('returns first exampleSentence only', () {
      final w = _word('Hund', exampleSentences: [
        'First sentence.',
        'Second sentence.',
        'Third sentence.',
      ]);
      expect(pickExampleSentence(w)!.text, 'First sentence.');
    });
  });

  // ─── Tier 3: Gutenberg ────────────────────────────────────────────────────

  group('pickExampleSentence — tier 3: Gutenberg', () {
    test('returns Gutenberg sentence with "Aus einem echten Buch" label', () {
      final w = _word('Wasser',
          api: _enrichment(gutenbergExamples: [
            'Das Wasser floss klar durch das Tal.'
          ]));
      final r = pickExampleSentence(w);
      expect(r, isNotNull);
      expect(r!.text, 'Das Wasser floss klar durch das Tal.');
      expect(r.label, 'Aus einem echten Buch');
    });

    test('returns first Gutenberg sentence only', () {
      final w = _word('Wasser', api: _enrichment(gutenbergExamples: [
        'First Gutenberg.',
        'Second Gutenberg.',
      ]));
      expect(pickExampleSentence(w)!.text, 'First Gutenberg.');
    });

    test('Gutenberg absent → null (no crash)', () {
      final w = _word('Wasser', api: _enrichment());
      expect(pickExampleSentence(w), isNull);
    });
  });

  // ─── Truncation ──────────────────────────────────────────────────────────

  group('pickExampleSentence — truncation', () {
    test('sentence exactly at limit is not truncated', () {
      final exact = 'x' * kExampleMaxLen;
      final w = _word('w', api: _enrichment(gutenbergExamples: [exact]));
      final r = pickExampleSentence(w)!;
      expect(r.text, exact);
      expect(r.text.length, kExampleMaxLen);
    });

    test('sentence one over limit is truncated with ellipsis', () {
      final long = 'x' * (kExampleMaxLen + 1);
      final w = _word('w', api: _enrichment(gutenbergExamples: [long]));
      final r = pickExampleSentence(w)!;
      expect(r.text.endsWith('…'), isTrue);
      expect(r.text.length, kExampleMaxLen);
    });

    test('very long sentence is truncated correctly', () {
      final veryLong = 'A' * 200;
      final w = _word('w', exampleSentences: [veryLong]);
      final r = pickExampleSentence(w)!;
      expect(r.text.length, kExampleMaxLen);
      expect(r.text.endsWith('…'), isTrue);
    });

    test('short sentence is not truncated', () {
      const short = 'Die Katze sitzt.';
      final w = _word('Katze', exampleSentences: [short]);
      expect(pickExampleSentence(w)!.text, short);
    });
  });

  // ─── Realistic DE examples users would see ───────────────────────────────

  group('pickExampleSentence — realistic examples', () {
    test('grade-1 Hund: grade example wins', () {
      final w = _word('Hund', api: _enrichment(
        gradeExamples: {'1': ['Mein Hund heißt Bello.']},
        gutenbergExamples: [
          'Ein Hund, der in der Nacht bellt, zieht die Aufmerksamkeit auf sich.',
        ],
      ));
      final r = pickExampleSentence(w, gradeLevel: GradeLevel.grade1);
      expect(r!.text, 'Mein Hund heißt Bello.');
      expect(r.label, 'Beispiel');
    });

    test('EN word "run": Gutenberg shown when no other examples', () {
      final w = _word('run', api: _enrichment(
        gutenbergExamples: [
          'He had to run as fast as his legs would carry him.',
        ],
      ));
      final r = pickExampleSentence(w);
      expect(r!.label, 'Aus einem echten Buch');
      expect(r.text, contains('run'));
    });

    test('DE Philosophie: long grade example is truncated for display', () {
      final long = 'Philosophie ist die Wissenschaft, die sich mit den Grundfragen '
          'des Daseins, der Erkenntnis, der Ethik und der Ästhetik befasst '
          'und dabei immer wieder neue Perspektiven eröffnet.';
      final w = _word('Philosophie', api: _enrichment(
        gradeExamples: {'6': [long]},
      ));
      final r = pickExampleSentence(w, gradeLevel: GradeLevel.grade6);
      expect(r!.text.length, lessThanOrEqualTo(kExampleMaxLen));
    });
  });
}
