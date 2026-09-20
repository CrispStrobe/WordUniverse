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
import 'package:WortUniversum/features/games/services/syllable_count_service.dart';

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
      // GermanWord.fromJson fills this from the enrichment (models line 784),
      // and the service reads it rather than reaching into apiEnrichment.
      hyphenation: hyphenation,
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
    test('1 → 0 (bucket 0)', () => expect(syllableBucket(1), equals(0)));
    test('2 → 1 (bucket 1)', () => expect(syllableBucket(2), equals(1)));
    test('3 → 2 (bucket 2)', () => expect(syllableBucket(3), equals(2)));
    test('4 → 3 (bucket 3 = "4+")', () => expect(syllableBucket(4), equals(3)));
    test('5 → 3 (bucket 3 = "4+")', () => expect(syllableBucket(5), equals(3)));
    test('10 → 3 (very long words)', () => expect(syllableBucket(10), equals(3)));
  });

  // ── buildChallenge ──────────────────────────────────────────────────────────
  group('buildChallenge', () {
    test('returns null when hyphenation is empty', () {
      final w = _word('Haus', hyphenation: []);
      expect(buildSyllableChallenge(w), isNull);
    });

    test('returns null when only invalid hyphenation entries', () {
      final w = _word('Februar', hyphenation: ['Fe-b-ru-ar']);
      expect(buildSyllableChallenge(w), isNull);
    });

    test('uses first valid entry when first entry is invalid', () {
      final w = _word('Beispiel', hyphenation: ['Fe-b-ru-ar', 'Bei-spiel']);
      final c = buildSyllableChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(2));
      expect(c.correctBucket, equals(1)); // 2 → bucket 1
    });

    test('Haus (1 syllable) → bucket 0', () {
      final w = _word('Haus', hyphenation: ['Haus']);
      final c = buildSyllableChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(1));
      expect(c.correctBucket, equals(0));
    });

    test('Kin-der (2 syllables) → bucket 1', () {
      final w = _word('Kinder', hyphenation: ['Kin-der']);
      final c = buildSyllableChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(2));
      expect(c.correctBucket, equals(1));
    });

    test('Schmet-ter-ling (3 syllables) → bucket 2', () {
      final w = _word('Schmetterling', hyphenation: ['Schmet-ter-ling']);
      final c = buildSyllableChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(3));
      expect(c.correctBucket, equals(2));
    });

    test('Bil-dungs-ein-rich-tung (5 syllables) → bucket 3 (4+)', () {
      final w = _word('Bildungseinrichtung',
          hyphenation: ['Bil-dungs-ein-rich-tung']);
      final c = buildSyllableChallenge(w);
      expect(c, isNotNull);
      expect(c!.syllableCount, equals(5));
      expect(c.correctBucket, equals(3));
    });

    test('concatenated DB form Bei-spielBei-spie-le → 2 syllables, bucket 1', () {
      final w = _word('Beispiel', hyphenation: ['Bei-spielBei-spie-le']);
      final c = buildSyllableChallenge(w);
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
      expect(buildSyllableChallenge(w)!.syllableCount, equals(3));
    });

    test('Haus → 1 syllable', () {
      final w = _word('Haus', hyphenation: ['Haus']);
      expect(buildSyllableChallenge(w)!.syllableCount, equals(1));
    });

    test('Beispiel → 2 syllables (concatenated DB form)', () {
      final w = _word('Beispiel', hyphenation: ['Bei-spielBei-spie-le']);
      expect(buildSyllableChallenge(w)!.syllableCount, equals(2));
    });

    test('Gemüse → 3 syllables', () {
      final w = _word('Gemüse', hyphenation: ['Ge-mü-se']);
      expect(buildSyllableChallenge(w)!.syllableCount, equals(3));
    });

    test('Februar → null (consonant-only segment in DB entry)', () {
      final w = _word('Februar', hyphenation: ['Fe-b-ru-ar']);
      expect(buildSyllableChallenge(w), isNull);
    });

    test('Unterricht → 3 syllables (Un-ter-richt)', () {
      final w = _word('Unterricht', hyphenation: ['Un-ter-richt']);
      expect(buildSyllableChallenge(w)!.syllableCount, equals(3));
    });

    test('Bildungseinrichtung → 5 syllables → bucket 3 (4+)', () {
      final w = _word('Bildungseinrichtung',
          hyphenation: ['Bil-dungs-ein-rich-tung']);
      final c = buildSyllableChallenge(w)!;
      expect(c.syllableCount, equals(5));
      expect(c.correctBucket, equals(3));
    });
  });
}
