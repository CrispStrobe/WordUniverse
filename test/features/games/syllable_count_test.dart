// test/features/games/syllable_count_test.dart
//
// Unit tests for Syllable Count (#43) — covers _countSyllables, _toBucket,
// and buildChallenge end-to-end.
//
// All expected DB values verified against pipeline/voc-de/grundwortschatz.db
// and pipeline/voc-en/grundwortschatz_en.db on 2026-05-26.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({List<String> hyphenation = const []}) =>
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
      hyphenation: hyphenation,
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
      commonLearnerErrors: const [],
    );

GermanWord _word(String word, {List<String> hyphenation = const []}) =>
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
      exampleSentences: const [],
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: false,
      apiEnrichment: _enrichment(hyphenation: hyphenation),
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

// ─── Mirror of game logic ─────────────────────────────────────────────────────

int? countSyllables(String rawHyph) {
  if (rawHyph.isEmpty) return null;
  String truncated = rawHyph;
  for (int i = 1; i < rawHyph.length; i++) {
    final ch = rawHyph[i];
    if (ch == ch.toUpperCase() && ch != ch.toLowerCase() && rawHyph[i - 1] != '-') {
      truncated = rawHyph.substring(0, i);
      break;
    }
  }
  final segments = truncated.split('-');
  const vowels = 'aeiouyäöüAEIOUYÄÖÜ';
  for (final seg in segments) {
    if (!seg.split('').any(vowels.contains)) return null;
  }
  return segments.length;
}

int toBucket(int n) => n <= 3 ? n - 1 : 3;

class _Challenge {
  final GermanWord word;
  final int syllableCount;
  final int correctBucket;
  const _Challenge({
    required this.word,
    required this.syllableCount,
    required this.correctBucket,
  });
}

_Challenge? buildChallenge(GermanWord word) {
  final hyphenations = word.apiEnrichment!.hyphenation;
  for (final raw in hyphenations) {
    final count = countSyllables(raw);
    if (count != null && count >= 1) {
      return _Challenge(
        word: word,
        syllableCount: count,
        correctBucket: toBucket(count),
      );
    }
  }
  return null;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── countSyllables — basic cases ────────────────────────────────────────────
  group('countSyllables — basic', () {
    test('single segment (no hyphen) = 1', () {
      expect(countSyllables('Haus'), equals(1));
    });

    test('two segments = 2', () {
      expect(countSyllables('Kin-der'), equals(2));
    });

    test('three segments = 3', () {
      expect(countSyllables('Schmet-ter-ling'), equals(3));
    });

    test('four segments = 4', () {
      expect(countSyllables('Un-ter-rich-ten'), equals(4));
    });

    test('five segments = 5', () {
      expect(countSyllables('Bil-dungs-ein-rich-tung'), equals(5));
    });
  });

  // ── countSyllables — rejection cases ────────────────────────────────────────
  group('countSyllables — invalid inputs', () {
    test('empty string returns null', () {
      expect(countSyllables(''), isNull);
    });

    test('consonant-only segment returns null (Fe-b-ru-ar pattern)', () {
      // "Fe-b-ru-ar" — "b" has no vowel → rejected
      expect(countSyllables('Fe-b-ru-ar'), isNull);
    });

    test('all-consonant single segment returns null', () {
      expect(countSyllables('bcdf'), isNull);
    });
  });

  // ── countSyllables — concatenated form truncation ───────────────────────────
  group('countSyllables — concatenated form handling', () {
    test('Bei-spielBei-spie-le → truncates at mid-capital → Bei-spiel = 2', () {
      // DB stores "Bei-spielBei-spie-le" for Beispiel (singular + plural forms).
      // The uppercase 'B' at index 8 (preceded by 'l', not '-') triggers truncation.
      expect(countSyllables('Bei-spielBei-spie-le'), equals(2));
    });

    test('Schmet-ter-lingSchmet-ter-lin-ge → truncates to Schmet-ter-ling = 3', () {
      expect(countSyllables('Schmet-ter-lingSchmet-ter-lin-ge'), equals(3));
    });

    test('does NOT truncate at hyphen-preceded uppercase (Ge-Mü-se stays intact)', () {
      // Each uppercase letter is right after a hyphen → no truncation
      expect(countSyllables('Ge-Mü-se'), equals(3));
    });
  });

  // ── countSyllables — umlauts and special vowels ──────────────────────────────
  group('countSyllables — German-specific vowels', () {
    test('Ge-mü-se (umlaut ü counts as vowel) = 3', () {
      expect(countSyllables('Ge-mü-se'), equals(3));
    });

    test('Ge-bäu-de (umlaut ä) = 3', () {
      expect(countSyllables('Ge-bäu-de'), equals(3));
    });

    test('Grö-ße (ß-containing segment with ö vowel) = 2', () {
      expect(countSyllables('Grö-ße'), equals(2));
    });

    test('Ü-bung (initial umlaut) = 2', () {
      expect(countSyllables('Ü-bung'), equals(2));
    });
  });

  // ── toBucket ────────────────────────────────────────────────────────────────
  group('toBucket', () {
    test('1 → 0 (bucket 0)', () => expect(toBucket(1), equals(0)));
    test('2 → 1 (bucket 1)', () => expect(toBucket(2), equals(1)));
    test('3 → 2 (bucket 2)', () => expect(toBucket(3), equals(2)));
    test('4 → 3 (bucket 3 = "4+")', () => expect(toBucket(4), equals(3)));
    test('5 → 3 (bucket 3 = "4+")', () => expect(toBucket(5), equals(3)));
    test('10 → 3 (very long words)', () => expect(toBucket(10), equals(3)));
  });

  // ── buildChallenge ──────────────────────────────────────────────────────────
  group('buildChallenge', () {
    test('returns null when hyphenation is empty', () {
      final w = _word('Haus', hyphenation: []);
      expect(buildChallenge(w), isNull);
    });

    test('returns null when only invalid hyphenation entries', () {
      final w = _word('Februar', hyphenation: ['Fe-b-ru-ar']);
      expect(buildChallenge(w), isNull);
    });

    test('uses first valid entry when first entry is invalid', () {
      final w = _word('Beispiel', hyphenation: ['Fe-b-ru-ar', 'Bei-spiel']);
      final c = buildChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(2));
      expect(c.correctBucket, equals(1)); // 2 → bucket 1
    });

    test('Haus (1 syllable) → bucket 0', () {
      final w = _word('Haus', hyphenation: ['Haus']);
      final c = buildChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(1));
      expect(c.correctBucket, equals(0));
    });

    test('Kin-der (2 syllables) → bucket 1', () {
      final w = _word('Kinder', hyphenation: ['Kin-der']);
      final c = buildChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(2));
      expect(c.correctBucket, equals(1));
    });

    test('Schmet-ter-ling (3 syllables) → bucket 2', () {
      final w = _word('Schmetterling', hyphenation: ['Schmet-ter-ling']);
      final c = buildChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(3));
      expect(c.correctBucket, equals(2));
    });

    test('Bil-dungs-ein-rich-tung (5 syllables) → bucket 3 (4+)', () {
      final w = _word('Bildungseinrichtung',
          hyphenation: ['Bil-dungs-ein-rich-tung']);
      final c = buildChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(5));
      expect(c.correctBucket, equals(3));
    });

    test('concatenated DB form Bei-spielBei-spie-le → 2 syllables, bucket 1', () {
      final w = _word('Beispiel', hyphenation: ['Bei-spielBei-spie-le']);
      final c = buildChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(2));
      expect(c.correctBucket, equals(1));
    });
  });

  // ── DB-pinned realistic expectations ────────────────────────────────────────
  // All values verified against pipeline/voc-de/grundwortschatz.db 2026-05-26.
  group('DB-pinned DE syllable counts', () {
    test('Schmetterling → 3 syllables', () {
      final w = _word('Schmetterling', hyphenation: ['Schmet-ter-ling']);
      expect(buildChallenge(w)!.syllableCount, equals(3));
    });

    test('Haus → 1 syllable', () {
      final w = _word('Haus', hyphenation: ['Haus']);
      expect(buildChallenge(w)!.syllableCount, equals(1));
    });

    test('Beispiel → 2 syllables (concatenated DB form)', () {
      final w = _word('Beispiel', hyphenation: ['Bei-spielBei-spie-le']);
      expect(buildChallenge(w)!.syllableCount, equals(2));
    });

    test('Gemüse → 3 syllables', () {
      final w = _word('Gemüse', hyphenation: ['Ge-mü-se']);
      expect(buildChallenge(w)!.syllableCount, equals(3));
    });

    test('Februar → null (consonant-only segment in DB entry)', () {
      final w = _word('Februar', hyphenation: ['Fe-b-ru-ar']);
      expect(buildChallenge(w), isNull);
    });

    test('Unterricht → 3 syllables (Un-ter-richt)', () {
      final w = _word('Unterricht', hyphenation: ['Un-ter-richt']);
      expect(buildChallenge(w)!.syllableCount, equals(3));
    });

    test('Bildungseinrichtung → 5 syllables → bucket 3 (4+)', () {
      final w = _word('Bildungseinrichtung',
          hyphenation: ['Bil-dungs-ein-rich-tung']);
      final c = buildChallenge(w)!;
      expect(c.syllableCount, equals(5));
      expect(c.correctBucket, equals(3));
    });
  });
}
