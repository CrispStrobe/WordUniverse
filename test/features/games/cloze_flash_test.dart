// test/features/games/cloze_flash_test.dart
//
// Unit tests for Cloze Flash (#44) — covers _tryBlank word-boundary logic
// and buildChallenge end-to-end.
//
// All expected DB values verified against pipeline/voc-de/grundwortschatz.db
// on 2026-05-26 and are pinned here so regressions surface immediately.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/features/games/services/cloze_service.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({List<ApiExample> examples = const []}) =>
    ApiEnrichment(
      enrichmentStatus: 'ok',
      definitions: const [],
      pronunciation: const [],
      examples: examples,
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
      commonLearnerErrors: const [],
    );

ApiExample _ex(String text) => ApiExample(text: text);

GermanWord _word(
  String word, {
  List<ApiExample> examples = const [],
  GermanWordType type = GermanWordType.substantiv,
}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: type,
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
      apiEnrichment: _enrichment(examples: examples),
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

// ─── The service, called the way Cloze Flash calls it ───────────────────────

/// The game passes its whole pool as distractors; these tests pass a list of
/// spellings, so the adapter offers them as both the same-type and any-type
/// pools.
ClozeChallenge? buildChallenge(
  GermanWord word,
  List<String> wordPool, {
  Random? rng,
  int optionCount = 4,
}) =>
    buildClozeChallenge(
      word: word,
      // The same projection the screen passes (cloze_flash_game.dart:171).
      texts: [
        for (final example in word.apiEnrichment?.examples ?? const [])
          if (example.text case final text?) text,
      ],
      byType: {word.wordType: wordPool},
      anyType: wordPool,
      optionCount: optionCount,
      rng: rng ?? Random(42),
    );

void main() {
  // ── tryBlank — basic matching ────────────────────────────────────────────────
  group('tryBlank — basic matching', () {
    test('blanks word at start of sentence', () {
      final r = tryBlank('Haus ist schön.', 'Haus');
      expect(r, isNotNull);
      expect(r!.before, equals(''));
      expect(r.after, equals(' ist schön.'));
      expect(r.matchedForm, equals('Haus'));
    });

    test('blanks word in middle of sentence', () {
      final r = tryBlank('Das Haus ist schön.', 'Haus');
      expect(r, isNotNull);
      expect(r!.before, equals('Das '));
      expect(r.after, equals(' ist schön.'));
    });

    test('blanks word at end of sentence', () {
      final r = tryBlank('Wir sehen das Haus.', 'Haus');
      expect(r, isNotNull);
      expect(r!.after, equals('.'));
    });

    test('returns null when word not in sentence', () {
      expect(tryBlank('Das ist schön.', 'Haus'), isNull);
    });

    test('returns null for empty target', () {
      expect(tryBlank('Das Haus ist schön.', ''), isNull);
    });

    test('match is case-insensitive', () {
      final r = tryBlank('Das haus ist schön.', 'Haus');
      expect(r, isNotNull);
      expect(r!.matchedForm, equals('haus')); // preserves original casing
    });
  });

  // ── tryBlank — word boundary enforcement ───────────────────────────────────
  group('tryBlank — word boundary enforcement', () {
    test('does NOT blank "ab" when it appears as prefix in "abbiegen"', () {
      expect(tryBlank('abbiegen ist schwer', 'ab'), isNull);
    });

    test('blanks "ab" when it appears as standalone word', () {
      final r = tryBlank('Der Zug fährt erst ab Stuttgart.', 'ab');
      expect(r, isNotNull);
      expect(r!.matchedForm.toLowerCase(), equals('ab'));
    });

    test('does NOT blank "Haus" when it is a prefix in "Hausdach"', () {
      expect(tryBlank('Das Hausdach ist kaputt.', 'Haus'), isNull);
    });

    test('does NOT blank "biegen" inside "abbiegen"', () {
      expect(tryBlank('abbiegen ist schwer', 'biegen'), isNull);
    });

    test('does NOT blank "gut" when it is a prefix in "gutartig"', () {
      expect(tryBlank('Das ist gutartig.', 'gut'), isNull);
    });

    test('blanks "gut" as standalone word', () {
      final r = tryBlank('Das ist gut.', 'gut');
      expect(r, isNotNull);
    });

    test('skips non-matching prefix occurrence and finds standalone later', () {
      // "Abbau" appears first as "Abbauprodukt" (no match), then standalone.
      final r = tryBlank('Das Abbauprodukt und der Abbau selbst.', 'Abbau');
      expect(r, isNotNull);
      expect(r!.before, contains('Abbauprodukt'));
      expect(r.matchedForm.toLowerCase(), equals('abbau'));
    });

    test('punctuation after word is a valid boundary', () {
      final r = tryBlank('Wir sahen das Haus.', 'Haus');
      expect(r, isNotNull);
    });

    test('sentence-start uppercase preserved in matchedForm', () {
      final r = tryBlank('Abend ist schön.', 'Abend');
      expect(r, isNotNull);
      expect(r!.matchedForm, equals('Abend'));
    });
  });

  // ── buildChallenge — null cases ──────────────────────────────────────────────
  group('buildChallenge — null cases', () {
    test('returns null when no examples', () {
      final w = _word('Haus', examples: []);
      expect(buildChallenge(w, ['Baum', 'Hund', 'Kind']), isNull);
    });

    test('returns null when example is too short (< 20 chars)', () {
      final w = _word('Haus', examples: [_ex('Das Haus.')]);
      expect(buildChallenge(w, ['Baum', 'Hund', 'Kind']), isNull);
    });

    test('returns null when example is too long (> 180 chars)', () {
      final long = 'Wort ' * 40; // 200 chars
      final w = _word('Wort', examples: [_ex(long)]);
      expect(buildChallenge(w, ['Baum', 'Hund', 'Kind']), isNull);
    });

    test(
        'returns null when word does not appear in any example at word boundary',
        () {
      // 'ab' only appears inside 'abbiegen', never standalone
      final w = _word('ab',
          examples: [_ex('Das Abbiegen an der Kreuzung war notwendig.')]);
      expect(buildChallenge(w, ['Baum', 'Hund', 'Kind']), isNull);
    });

    test('returns null when pool has no distractors', () {
      final w = _word('Haus',
          examples: [_ex('Das Haus ist sehr schön und gemütlich.')]);
      expect(buildChallenge(w, ['Haus']), isNull);
    });
  });

  // ── buildChallenge — structural invariants ───────────────────────────────────
  group('buildChallenge — structural invariants', () {
    test('options[correctIndex] equals word.word (case-insensitive)', () {
      final w = _word('Haus',
          examples: [_ex('Das Haus ist sehr schön und gemütlich heute.')]);
      final pool = ['Baum', 'Hund', 'Kind', 'Tier'];
      final c = buildChallenge(w, pool, rng: Random(1));
      expect(c, isNotNull);
      expect(c!.options[c.correctIndex].toLowerCase(), equals('haus'));
    });

    test('before + matchedForm + after reconstructs the original sentence', () {
      final sentence = 'Das Haus ist sehr schön und gemütlich heute.';
      final w = _word('Haus', examples: [_ex(sentence)]);
      final pool = ['Baum', 'Hund', 'Kind', 'Tier'];
      final c = buildChallenge(w, pool, rng: Random(2));
      expect(c, isNotNull);
      expect(c!.before + c.matchedForm + c.after, equals(sentence));
    });

    test('target word itself is not among the distractors', () {
      final w = _word('Haus',
          examples: [_ex('Das Haus ist sehr schön und gemütlich heute.')]);
      final pool = ['Haus', 'Baum', 'Hund', 'Kind'];
      final c = buildChallenge(w, pool, rng: Random(3));
      expect(c, isNotNull);
      // Only one 'Haus' in options (the correct answer)
      final count = c!.options.where((o) => o.toLowerCase() == 'haus').length;
      expect(count, equals(1));
    });

    test('options length does not exceed optionCount', () {
      final w = _word('Haus',
          examples: [_ex('Das Haus ist sehr schön und gemütlich heute.')]);
      final pool = List.generate(20, (i) => 'Wort$i');
      final c = buildChallenge(w, pool, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.options.length, lessThanOrEqualTo(4));
    });

    test('skips first example (too short) and uses second valid one', () {
      final w = _word('Haus', examples: [
        _ex('Haus.'),
        _ex('Das schöne Haus am Berg ist ein beliebtes Ausflugsziel.'),
      ]);
      final pool = ['Baum', 'Hund', 'Kind'];
      final c = buildChallenge(w, pool, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.matchedForm.toLowerCase(), equals('haus'));
    });
  });

  // ── DB-pinned realistic examples ─────────────────────────────────────────────
  // All sentences verified against pipeline/voc-de/grundwortschatz.db 2026-05-26.
  group('DB-pinned DE cloze examples', () {
    test('ab in "Der Zug fährt erst ab Stuttgart."', () {
      final r = tryBlank('Der Zug fährt erst ab Stuttgart.', 'ab');
      expect(r, isNotNull);
      expect(r!.matchedForm.toLowerCase(), equals('ab'));
    });

    test('abbiegen in its example sentence', () {
      const sentence =
          'Der Klempner musste das Rohr erst abbiegen, ehe er es einbauen konnte.';
      final r = tryBlank(sentence, 'abbiegen');
      expect(r, isNotNull);
      expect(r!.matchedForm.toLowerCase(), equals('abbiegen'));
    });

    test('Abendessen in its example sentence', () {
      const sentence =
          'Zum Abendessen gibt es heute einen besonders guten Wein.';
      final r = tryBlank(sentence, 'Abendessen');
      expect(r, isNotNull);
      expect(r!.before, equals('Zum '));
      expect(r.after, startsWith(' gibt es'));
    });

    test('abends in its example sentence', () {
      const sentence =
          'Am Wochenende dürfen die Kinder abends länger aufbleiben.';
      final r = tryBlank(sentence, 'abends');
      expect(r, isNotNull);
      expect(r!.matchedForm.toLowerCase(), equals('abends'));
    });

    test('buildChallenge end-to-end for Haus', () {
      final w = _word('Haus', examples: [
        _ex('Das Haus ist schön und liegt am Berg in einer ruhigen Gegend.'),
      ]);
      final pool = ['Baum', 'Hund', 'Kind', 'Tier', 'Garten'];
      final c = buildChallenge(w, pool, rng: Random(7));
      expect(c, isNotNull);
      expect(c!.options[c.correctIndex].toLowerCase(), equals('haus'));
      expect(c.options.length, equals(4));
    });
  });
}
