// test/features/home/word_of_the_day_service_test.dart
//
// Unit tests for word_of_the_day_service.dart pure helpers.
// Covers: dayOfYear arithmetic, pool filtering, determinism, edge cases.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/home/services/word_of_the_day_service.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({
  List<String> definitions = const [],
  List<String> entryNotes = const [],
}) =>
    ApiEnrichment(
      enrichmentStatus: 'ok',
      definitions: definitions,
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
      entryNotes: entryNotes,
      hypernyms: const [],
      hyponyms: const [],
      holonyms: const [],
      meronyms: const [],
      coordinateTerms: const [],
      gutenbergExamples: const [],
      commonLearnerErrors: const [],
    );

GermanWord _word(
  String word, {
  int grade = 1,
  bool isProperNoun = false,
  List<String> sources = const [],
  List<String>? commonMistakes,
  GermanWordType wordType = GermanWordType.substantiv,
  ApiEnrichment? api,
}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: wordType,
      gradeLevel: grade,
      lemma: word,
      sources: sources,
      isGrundwortschatzBW: false,
      nurImPlural: false,
      graphematicVariants: const [],
      categories: const [],
      exampleSentences: const [],
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: isProperNoun,
      commonMistakes: commonMistakes,
      apiEnrichment: api,
      examples: const [],
      hyphenation: const [],
      wiktionaryInflections: const [],
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
    );

GermanWord _eligible(String word, {int grade = 1}) =>
    _word(word, grade: grade, api: _enrichment(definitions: ['a meaning']));

void main() {
  // ─── dayOfYear ─────────────────────────────────────────────────────────────

  group('dayOfYear', () {
    test('Jan 1 → 0', () {
      expect(dayOfYear(DateTime(2024, 1, 1)), 0);
    });

    test('Jan 2 → 1', () {
      expect(dayOfYear(DateTime(2024, 1, 2)), 1);
    });

    test('Dec 31 non-leap → 364', () {
      expect(dayOfYear(DateTime(2023, 12, 31)), 364);
    });

    test('Dec 31 leap year → 365', () {
      expect(dayOfYear(DateTime(2024, 12, 31)), 365);
    });

    test('Feb 29 in leap year → day 59', () {
      expect(dayOfYear(DateTime(2024, 2, 29)), 59);
    });
  });

  // ─── Pool filtering ────────────────────────────────────────────────────────

  group('pickWordOfTheDay pool filter', () {
    final date = DateTime(2024, 6, 15);

    test('returns null for empty list', () {
      expect(pickWordOfTheDay([], date), isNull);
    });

    test('returns null when no words pass the filter', () {
      final words = [
        _word('Haus', grade: 1), // no definitions
      ];
      expect(pickWordOfTheDay(words, date), isNull);
    });

    test('excludes grade 4 words', () {
      final words = [
        _word('Lärm', grade: 4, api: _enrichment(definitions: ['noise']))
      ];
      expect(pickWordOfTheDay(words, date), isNull);
    });

    test('excludes grade 5 words', () {
      final words = [
        _word('Philosophie', grade: 5, api: _enrichment(definitions: ['…']))
      ];
      expect(pickWordOfTheDay(words, date), isNull);
    });

    test('excludes grade 6 words', () {
      final words = [
        _word('Allegorie', grade: 6, api: _enrichment(definitions: ['…']))
      ];
      expect(pickWordOfTheDay(words, date), isNull);
    });

    test('includes grade 1, 2, 3 words that have definitions', () {
      for (final g in [1, 2, 3]) {
        final words = [_eligible('Wort', grade: g)];
        expect(pickWordOfTheDay(words, date), isNotNull,
            reason: 'grade $g should be included');
      }
    });

    test('targets the selected learning band when requested', () {
      final words = [
        _eligible('leicht', grade: 1),
        _eligible('anspruchsvoll', grade: 4),
      ];

      expect(
        pickWordOfTheDay(words, date, targetBand: 4)?.word,
        'anspruchsvoll',
      );
    });

    test('excludes proper nouns', () {
      final proper = _word('Berlin',
          grade: 1,
          isProperNoun: true,
          api: _enrichment(definitions: ['city']));
      expect(pickWordOfTheDay([proper], date), isNull);
    });

    test('excludes multi-word entries (contains space)', () {
      final multiWord = _word('zwei Wörter',
          grade: 1, api: _enrichment(definitions: ['two words']));
      expect(pickWordOfTheDay([multiWord], date), isNull);
    });

    test('excludes malformed source artifacts such as "a. didnt"', () {
      expect(pickWordOfTheDay([_eligible('a. didnt')], date), isNull);
    });

    test('excludes a database headword defined as a misspelling', () {
      final shippedDidnt = _word(
        'didnt',
        grade: 2,
        api: _enrichment(definitions: ["Misspelling of didn't."]),
      );

      expect(pickWordOfTheDay([shippedDidnt], date), isNull);
    });

    test('excludes a headword listed as a known misspelling', () {
      final misspelling = _eligible('didnt');
      final canonical = _word(
        "didn't",
        api: _enrichment(
          definitions: ['did not'],
          entryNotes: const [],
        ),
        commonMistakes: const ['didnt'],
      );

      expect(pickWordOfTheDay([misspelling, canonical], date)?.word, "didn't");
    });

    test('accepts clean apostrophes and hyphens', () {
      for (final word in ["didn't", 'E-Mail']) {
        expect(pickWordOfTheDay([_eligible(word)], date)?.word, word);
      }
    });

    test('excludes entries explicitly sourced as common misspellings', () {
      final misspelling = _word(
        'accomodate',
        sources: const ['COMMON_MISSPELLED'],
        api: _enrichment(definitions: ['incorrect form']),
      );
      expect(pickWordOfTheDay([misspelling], date), isNull);
    });

    test('excludes words with no definitions in apiEnrichment', () {
      final noApi = _word('still', grade: 1);
      final emptyDefs = _word('leer', grade: 1, api: _enrichment());
      expect(pickWordOfTheDay([noApi, emptyDefs], date), isNull);
    });
  });

  // ─── Determinism ───────────────────────────────────────────────────────────

  group('pickWordOfTheDay determinism', () {
    final words = [
      _eligible('Haus'),
      _eligible('Baum'),
      _eligible('Hund'),
      _eligible('Katze'),
      _eligible('Wasser'),
      _eligible('Feuer'),
    ];

    test('same date always returns same word', () {
      final date = DateTime(2024, 5, 10);
      final a = pickWordOfTheDay(words, date);
      final b = pickWordOfTheDay(words, date);
      expect(a, same(b));
    });

    test('consecutive days can return different words from a large pool', () {
      // With 6 words, day+1 changes the seed by 1 → different pool index
      final day1 = DateTime(2024, 1, 1);
      final day2 = DateTime(2024, 1, 2);
      final seed1 = dayOfYear(day1) + day1.year * 366;
      final seed2 = dayOfYear(day2) + day2.year * 366;
      expect(seed1 % words.length == seed2 % words.length, isFalse,
          reason: 'seeds should produce different indices for a 6-word pool');
    });

    test('single-word pool always returns that word regardless of date', () {
      final only = _eligible('einzig');
      for (final d in [
        DateTime(2024, 1, 1),
        DateTime(2024, 6, 15),
        DateTime(2024, 12, 31),
      ]) {
        expect(pickWordOfTheDay([only], d)?.word, 'einzig');
      }
    });

    test('different years produce different seeds for the same day-of-year',
        () {
      final d2023 = DateTime(2023, 7, 4);
      final d2024 = DateTime(2024, 7, 4);
      final s2023 = dayOfYear(d2023) + 2023 * 366;
      final s2024 = dayOfYear(d2024) + 2024 * 366;
      expect(s2023, isNot(s2024));
    });
  });
}
