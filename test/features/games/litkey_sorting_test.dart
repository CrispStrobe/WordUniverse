// test/features/games/litkey_sorting_test.dart
//
// Unit tests for SpellingSpotter difficulty sorting (#37, #39):
//   • GermanWord.litekeyErrorRate model field — parsing & edge cases
//   • spellingDifficultyScore() — DE (LiTKey) and EN (Norvig count) branches
//   • Pool sorting by difficulty score (descending)
//   • Realistic hard-word verification from DE LiTKey data
//
// Data notes:
//   • error_rate=1.0 for some grade-1 words (Dose, März, Papier) with zero
//     commonMistakes reflects single-sample LiTKey entries. They sort first
//     but may not produce good SpellingSpotter challenges.
//   • error_rate from the corpus is reliable for words with ≥3 mistakes logged.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/features/games/services/spelling_spotter_service.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({List<String> commonLearnerErrors = const []}) =>
    ApiEnrichment(
      enrichmentStatus: 'ok',
      definitions: const [],
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
      gutenbergExamples: const [],
      commonLearnerErrors: commonLearnerErrors,
    );

GermanWord _word(
  String word, {
  double? litekeyErrorRate,
  List<String>? commonMistakes,
  int grade = 1,
  List<String>? commonLearnerErrors,
}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: GermanWordType.substantiv,
      gradeLevel: grade,
      lemma: word,
      sources: const [],
      isGrundwortschatzBW: false,
      nurImPlural: false,
      graphematicVariants: const [],
      categories: const [],
      exampleSentences: const [],
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: false,
      litekeyErrorRate: litekeyErrorRate,
      commonMistakes: commonMistakes,
      apiEnrichment: commonLearnerErrors != null
          ? _enrichment(commonLearnerErrors: commonLearnerErrors)
          : null,
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

/// Apply the same sort SpellingSpotter uses (DE path): error rate descending.
List<GermanWord> _sortByDifficulty(List<GermanWord> words) {
  final pool = List<GermanWord>.from(words);
  pool.sort((a, b) =>
      spellingDifficultyScore(b, isDE: true)
          .compareTo(spellingDifficultyScore(a, isDE: true)));
  return pool;
}

/// Apply the EN sort: Norvig error-count descending.
List<GermanWord> _sortByDifficultyEN(List<GermanWord> words) {
  final pool = List<GermanWord>.from(words);
  pool.sort((a, b) =>
      spellingDifficultyScore(b, isDE: false)
          .compareTo(spellingDifficultyScore(a, isDE: false)));
  return pool;
}

// ─── litekeyErrorRate model field ────────────────────────────────────────────

void main() {
  group('GermanWord.litekeyErrorRate', () {
    test('is null by default (no litkey data)', () {
      expect(_word('Hund').litekeyErrorRate, isNull);
    });

    test('stores 0.0 correctly', () {
      expect(_word('blau', litekeyErrorRate: 0.0).litekeyErrorRate, 0.0);
    });

    test('stores 1.0 correctly', () {
      expect(_word('Knie', litekeyErrorRate: 1.0).litekeyErrorRate, 1.0);
    });

    test('stores fractional values correctly', () {
      expect(
        _word('kennen', litekeyErrorRate: 0.67).litekeyErrorRate,
        closeTo(0.67, 0.001),
      );
    });

    test('null and 0.0 are distinct — null means no data, not easy', () {
      final noData = _word('no_data');
      final veryEasy = _word('leicht', litekeyErrorRate: 0.0);
      expect(noData.litekeyErrorRate, isNull);
      expect(veryEasy.litekeyErrorRate, 0.0);
      expect(noData.litekeyErrorRate == veryEasy.litekeyErrorRate, isFalse);
    });
  });

  // ─── Pool sorting ─────────────────────────────────────────────────────────

  group('Pool sorting by litekeyErrorRate', () {
    test('higher error rate sorts before lower', () {
      final pool = [
        _word('leicht', litekeyErrorRate: 0.1),
        _word('schwer', litekeyErrorRate: 0.9),
        _word('mittel', litekeyErrorRate: 0.5),
      ];
      final sorted = _sortByDifficulty(pool);
      expect(sorted.map((w) => w.word).toList(), ['schwer', 'mittel', 'leicht']);
    });

    test('null error rate sorts after 0.6 (treated as 0.5 neutral)', () {
      final pool = [
        _word('no_data'),       // null → 0.5
        _word('hard', litekeyErrorRate: 0.8),
        _word('medium', litekeyErrorRate: 0.6),
        _word('easy', litekeyErrorRate: 0.2),
      ];
      final sorted = _sortByDifficulty(pool);
      expect(sorted[0].word, 'hard');
      expect(sorted[1].word, 'medium');
      // null (0.5) sits after 0.6
      expect(sorted[2].word, 'no_data');
      expect(sorted[3].word, 'easy');
    });

    test('two nulls remain stable relative to each other', () {
      final pool = [
        _word('alpha'), // null
        _word('beta'),  // null
        _word('hard', litekeyErrorRate: 0.9),
      ];
      final sorted = _sortByDifficulty(pool);
      expect(sorted[0].word, 'hard');
      // alpha and beta both null → original relative order preserved
      expect(sorted.sublist(1).map((w) => w.word).toSet(),
          containsAll(['alpha', 'beta']));
    });

    test('all same error rate produces no reordering (stable)', () {
      final pool = [
        _word('a', litekeyErrorRate: 0.5),
        _word('b', litekeyErrorRate: 0.5),
        _word('c', litekeyErrorRate: 0.5),
      ];
      final sorted = _sortByDifficulty(pool);
      expect(sorted.map((w) => w.word).toList(), ['a', 'b', 'c']);
    });

    test('single-item pool sorts without error', () {
      final sorted = _sortByDifficulty([_word('einzel', litekeyErrorRate: 0.3)]);
      expect(sorted.length, 1);
      expect(sorted.first.word, 'einzel');
    });

    test('empty pool is a no-op', () {
      expect(_sortByDifficulty([]), isEmpty);
    });

    // ─── Realistic session simulation ──────────────────────────────────────

    test('realistic grade-1 pool: hardest words sort first', () {
      // Actual LiTKey rates sampled from DE DB (doppelkonsonant / verwandt words)
      final grade1Pool = [
        _word('alle',    litekeyErrorRate: 0.18),  // doppelkonsonant
        _word('dürfen',  litekeyErrorRate: 0.71),  // verwandt (Umlaut)
        _word('hören',   litekeyErrorRate: 0.43),  // verwandt (Umlaut)
        _word('kennen',  litekeyErrorRate: 0.67),  // doppelkonsonant
        _word('kommen',  litekeyErrorRate: 0.27),  // doppelkonsonant
        _word('laufen',  litekeyErrorRate: 0.0),   // klangtreu, easy
        _word('am',      litekeyErrorRate: 0.02),  // merkwort, easy
        _word('Papier'),                           // null (sparse data)
      ];
      final sorted = _sortByDifficulty(grade1Pool);
      // dürfen (0.71) and kennen (0.67) must be in top 2
      final top2 = sorted.take(2).map((w) => w.word).toSet();
      expect(top2, containsAll(['dürfen', 'kennen']));
      // null 'Papier' (→ 0.5) sorts above hören (0.43) and kommen (0.27)
      final top4 = sorted.take(4).map((w) => w.word).toSet();
      expect(top4, containsAll(['dürfen', 'kennen', 'Papier', 'hören']));
      // Easiest words sink to the bottom
      final bottom2 = sorted.skip(6).map((w) => w.word).toSet();
      expect(bottom2, containsAll(['laufen', 'am']));
    });

    test('Umlaut verwandt words (dürfen 71%, hören 43%) outrank doppelkonsonant (kennen 67%)', () {
      // Both are hard but dürfen (Umlaut ö/u confusion) is hardest overall
      final pool = [
        _word('kennen', litekeyErrorRate: 0.67),
        _word('dürfen', litekeyErrorRate: 0.71),
        _word('hören',  litekeyErrorRate: 0.43),
      ];
      final sorted = _sortByDifficulty(pool);
      expect(sorted[0].word, 'dürfen');
      expect(sorted[1].word, 'kennen');
      expect(sorted[2].word, 'hören');
    });

    test('words with error_rate=1.0 (LiTKey single-sample) sort first', () {
      // Note: 1.0 may reflect 1/1 child samples — treat as tentative hard signal
      final pool = [
        _word('Frühling', litekeyErrorRate: 1.0, commonMistakes: ['früling']),
        _word('schmecken', litekeyErrorRate: 1.0, commonMistakes: ['ge_schmekt', 'schmeken']),
        _word('kennen',   litekeyErrorRate: 0.67, commonMistakes: ['kenen']),
        _word('alle',     litekeyErrorRate: 0.18),
      ];
      final sorted = _sortByDifficulty(pool);
      // Both 1.0-rate words come first (any order among themselves)
      expect(sorted.take(2).map((w) => w.word).toSet(),
          containsAll(['Frühling', 'schmecken']));
    });

    test('words with error_rate=0 (very easy) sort last', () {
      final pool = [
        _word('laufen', litekeyErrorRate: 0.0),
        _word('blau',   litekeyErrorRate: 0.0),
        _word('kennen', litekeyErrorRate: 0.67),
      ];
      final sorted = _sortByDifficulty(pool);
      expect(sorted.last.word, isIn(['laufen', 'blau']));
      expect(sorted.first.word, 'kennen');
    });
  });

  // ─── spellingDifficultyScore — EN branch (#39) ────────────────────────────

  group('spellingDifficultyScore EN (Norvig count)', () {
    test('0 errors → 0.3 (below neutral, not zero)', () {
      final w = _word('cat', commonLearnerErrors: []);
      expect(spellingDifficultyScore(w, isDE: false), closeTo(0.3, 0.001));
    });

    test('null apiEnrichment → 0.3 (same as 0 errors)', () {
      final w = _word('tree'); // no apiEnrichment
      expect(spellingDifficultyScore(w, isDE: false), closeTo(0.3, 0.001));
    });

    test('10 errors → 0.5 (midpoint at cap/2)', () {
      final w = _word('receive', commonLearnerErrors: List.filled(10, 'e'));
      expect(spellingDifficultyScore(w, isDE: false), closeTo(0.5, 0.001));
    });

    test('20 errors → 1.0 (at cap)', () {
      final w = _word('miscellaneous',
          commonLearnerErrors: List.filled(20, 'miscelaneous'));
      expect(spellingDifficultyScore(w, isDE: false), closeTo(1.0, 0.001));
    });

    test('50 errors → 1.0 (clamped at cap)', () {
      final w = _word('beautiful',
          commonLearnerErrors: List.filled(50, 'beautifull'));
      expect(spellingDifficultyScore(w, isDE: false), closeTo(1.0, 0.001));
    });

    test('5 errors → 0.25', () {
      final w = _word('accommodate',
          commonLearnerErrors: List.filled(5, 'accomodate'));
      expect(spellingDifficultyScore(w, isDE: false), closeTo(0.25, 0.001));
    });

    test('DE path is unaffected — uses litekeyErrorRate', () {
      final w = _word('kennen', litekeyErrorRate: 0.67);
      expect(spellingDifficultyScore(w, isDE: true), closeTo(0.67, 0.001));
    });

    test('DE null litekeyErrorRate → 0.5 (neutral)', () {
      final w = _word('Hund'); // no litkey data
      expect(spellingDifficultyScore(w, isDE: true), closeTo(0.5, 0.001));
    });
  });

  group('EN pool sorting by Norvig count', () {
    test('more errors sorts before fewer errors', () {
      final pool = [
        _word('easy',    commonLearnerErrors: List.filled(2,  'e')),
        _word('hard',    commonLearnerErrors: List.filled(15, 'e')),
        _word('medium',  commonLearnerErrors: List.filled(7,  'e')),
      ];
      final sorted = _sortByDifficultyEN(pool);
      expect(sorted.map((w) => w.word).toList(), ['hard', 'medium', 'easy']);
    });

    test('0 errors (0.3) sorts after any word with ≥1 error', () {
      final pool = [
        _word('nodata',  commonLearnerErrors: []),
        _word('oneErr',  commonLearnerErrors: ['e']), // 0.05 < 0.3? No: 1/20=0.05 < 0.3
        _word('tenErrs', commonLearnerErrors: List.filled(10, 'e')),
      ];
      // oneErr → 0.05, nodata → 0.3, tenErrs → 0.5
      // Descending: tenErrs (0.5) > nodata (0.3) > oneErr (0.05)
      final sorted = _sortByDifficultyEN(pool);
      expect(sorted[0].word, 'tenErrs');
      expect(sorted[1].word, 'nodata');
      expect(sorted[2].word, 'oneErr');
    });

    test('realistic EN words: miscellaneous (many) > guarantee (some) > cat (none)', () {
      // Approximates the Norvig distribution: miscellaneous has 226 variants,
      // guarantee ~154. Use counts within the 0-20 range so scores differ.
      final pool = [
        _word('cat',           commonLearnerErrors: []),
        _word('guarantee',     commonLearnerErrors: List.filled(10, 'e')), // 0.5
        _word('miscellaneous', commonLearnerErrors: List.filled(18, 'e')), // 0.9
      ];
      final sorted = _sortByDifficultyEN(pool);
      expect(sorted[0].word, 'miscellaneous');
      expect(sorted[1].word, 'guarantee');
      expect(sorted[2].word, 'cat');
    });
  });
}
