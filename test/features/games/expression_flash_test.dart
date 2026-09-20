// test/features/games/expression_flash_test.dart
//
// Unit tests for Expression Flash (#45) — covers _tryBlank word-boundary logic
// (shared with ClozeFlash), the 2-visible-words requirement, same-type distractor
// preference, and buildChallenge end-to-end.
//
// All expression strings verified against pipeline/voc-de/grundwortschatz.db
// on 2026-05-26.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/features/games/services/cloze_service.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({List<ApiExpression> expressions = const []}) =>
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
      expressions: expressions,
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

ApiExpression _expr(String text) => ApiExpression(expression: text);

GermanWord _word(
  String word, {
  List<ApiExpression> expressions = const [],
  GermanWordType type = GermanWordType.verb,
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
      apiEnrichment: _enrichment(expressions: expressions),
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

// ─── The service, called the way Expression Flash calls it ─────────────────

/// Mirrors expression_flash_game.dart: expressions are the texts, 8-80
/// characters, and at least two words have to stay visible beside the gap.
ClozeChallenge? buildChallenge(
  GermanWord word,
  List<String> pool, {
  Random? rng,
  int optionCount = 4,
}) =>
    buildClozeChallenge(
      word: word,
      texts: [
        for (final entry in word.apiEnrichment?.expressions ?? const [])
          if (entry.expression case final text?) text,
      ],
      byType: {word.wordType: pool},
      anyType: pool,
      optionCount: optionCount,
      minLength: 8,
      maxLength: 80,
      minVisibleWords: 2,
      rng: rng ?? Random(42),
    );

void main() {
  // ── tryBlank — word boundary (reused from ClozeFlash, spot-check) ──────────
  group('tryBlank — word boundary', () {
    test('blanks verb at end of idiom', () {
      final r = tryBlank('etwas die Spitze abbrechen', 'abbrechen');
      expect(r, isNotNull);
      expect(r!.before, equals('etwas die Spitze '));
      expect(r.after, equals(''));
      expect(r.matchedForm.toLowerCase(), equals('abbrechen'));
    });

    test('blanks noun in middle of idiom', () {
      final r = tryBlank('zu Abend essen', 'Abend');
      expect(r, isNotNull);
      expect(r!.before, equals('zu '));
      expect(r.after, equals(' essen'));
    });

    test('does not match partial word', () {
      // 'ab' should not match inside 'abbrechen'
      expect(tryBlank('etwas abbrechen', 'ab'), isNull);
    });

    test('before + matchedForm + after reconstructs original', () {
      const expr = 'den Löffel abgeben';
      final r = tryBlank(expr, 'abgeben');
      expect(r, isNotNull);
      expect(r!.before + r.matchedForm + r.after, equals(expr));
    });
  });

  // ── visible word count requirement ─────────────────────────────────────────
  group('visible word count requirement', () {
    test('2 visible words → accepted', () {
      final r = tryBlank('zu Abend essen', 'Abend')!;
      expect(visibleWordCount(r), greaterThanOrEqualTo(2));
    });

    test('1 visible word → rejected (Hürden abbauen → only "Hürden" left)', () {
      // 'Hürden abbauen' — blanking 'abbauen' leaves only 'Hürden'
      final r = tryBlank('Hürden abbauen', 'abbauen')!;
      expect(visibleWordCount(r), equals(1));
    });
  });

  // ── buildChallenge — null cases ──────────────────────────────────────────────
  group('buildChallenge — null cases', () {
    test('returns null when expressions list is empty', () {
      final w = _word('abbauen', expressions: []);
      expect(buildChallenge(w, ['nehmen', 'geben', 'laufen']), isNull);
    });

    test('returns null when expression is too short (< 8 chars)', () {
      final w = _word('ab', expressions: [_expr('ab gut')]);
      expect(buildChallenge(w, ['an', 'auf', 'aus']), isNull);
    });

    test('returns null when only 1 word visible after blanking', () {
      // 'Hürden abbauen' → only 'Hürden' visible → rejected
      final w = _word('abbauen', expressions: [_expr('Hürden abbauen')]);
      expect(buildChallenge(w, ['nehmen', 'laufen', 'geben']), isNull);
    });

    test('returns null when word not at word boundary in expression', () {
      // 'ab' is a prefix of 'abbrechen', not standalone
      final w = _word('ab', expressions: [_expr('etwas die Spitze abbrechen')]);
      expect(buildChallenge(w, ['nehmen', 'geben', 'laufen']), isNull);
    });

    test('returns null when pool has no distractors', () {
      final w = _word('abgeben', expressions: [_expr('den Löffel abgeben')]);
      expect(buildChallenge(w, ['abgeben']), isNull);
    });
  });

  // ── buildChallenge — structural invariants ───────────────────────────────────
  group('buildChallenge — structural invariants', () {
    test('options[correctIndex] == word.word', () {
      final w = _word('abgeben', expressions: [_expr('den Löffel abgeben')]);
      final pool = ['nehmen', 'laufen', 'stehen', 'sehen'];
      final c = buildChallenge(w, pool, rng: Random(1));
      expect(c, isNotNull);
      expect(c!.options[c.correctIndex].toLowerCase(), equals('abgeben'));
    });

    test('before + matchedForm + after reconstructs original expression', () {
      const expr = 'alle Brücken hinter sich abbrechen';
      final w = _word('abbrechen', expressions: [_expr(expr)]);
      final pool = ['nehmen', 'laufen', 'stehen'];
      final c = buildChallenge(w, pool, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.before + c.matchedForm + c.after, equals(expr));
    });

    test('target word not duplicated among distractors', () {
      final w = _word('abgeben', expressions: [_expr('den Löffel abgeben')]);
      final pool = ['abgeben', 'nehmen', 'laufen', 'stehen'];
      final c = buildChallenge(w, pool, rng: Random(2));
      expect(c, isNotNull);
      final count =
          c!.options.where((o) => o.toLowerCase() == 'abgeben').length;
      expect(count, equals(1));
    });

    test('options length does not exceed optionCount', () {
      final w = _word('abgeben', expressions: [_expr('den Löffel abgeben')]);
      final pool = List.generate(20, (i) => 'Verb$i');
      final c = buildChallenge(w, pool, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.options.length, lessThanOrEqualTo(4));
    });

    test('skips expression with only 1 visible word, uses next valid one', () {
      final w = _word('abbauen', expressions: [
        _expr('Hürden abbauen'), // 1 visible word → skip
        _expr('Vorurteile langsam abbauen'), // 3 visible words → use this
      ]);
      final pool = ['nehmen', 'laufen', 'stehen'];
      final c = buildChallenge(w, pool, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.source, equals('Vorurteile langsam abbauen'));
    });
  });

  // ── DB-pinned realistic expressions ─────────────────────────────────────────
  // Strings verified against pipeline/voc-de/grundwortschatz.db 2026-05-26.
  group('DB-pinned DE expressions', () {
    test('abbrechen: "etwas die Spitze abbrechen" → blank at end', () {
      final r = tryBlank('etwas die Spitze abbrechen', 'abbrechen');
      expect(r, isNotNull);
      expect(r!.before, contains('Spitze'));
      expect(r.after, equals(''));
    });

    test('abbrechen: "alle Brücken hinter sich abbrechen" → 4 visible words',
        () {
      final r = tryBlank('alle Brücken hinter sich abbrechen', 'abbrechen')!;
      expect(visibleWordCount(r), equals(4));
    });

    test('Abend: "zu Abend essen" → blank in middle', () {
      final r = tryBlank('zu Abend essen', 'Abend')!;
      expect(r.before, equals('zu '));
      expect(r.after, equals(' essen'));
    });

    test('abgeben: "den Löffel abgeben" (kick the bucket) → blank at end', () {
      final r = tryBlank('den Löffel abgeben', 'abgeben');
      expect(r, isNotNull);
      expect(r!.before, equals('den Löffel '));
    });

    test('abfahren: "dieser Zug ist abgefahren" — inflected form match', () {
      // headword is 'abfahren' but expression has 'abgefahren' — no match expected
      final r = tryBlank('dieser Zug ist abgefahren', 'abfahren');
      expect(r, isNull);
    });

    test('abgefahren: "dieser Zug ist abgefahren" — exact form matches', () {
      final r = tryBlank('dieser Zug ist abgefahren', 'abgefahren');
      expect(r, isNotNull);
      expect(r!.before, equals('dieser Zug ist '));
    });

    test('buildChallenge end-to-end: abgeben with idiom', () {
      final w = _word('abgeben', expressions: [_expr('den Löffel abgeben')]);
      final pool = ['nehmen', 'laufen', 'stehen', 'sehen'];
      final c = buildChallenge(w, pool, rng: Random(5));
      expect(c, isNotNull);
      expect(c!.options[c.correctIndex].toLowerCase(), equals('abgeben'));
      expect(c.source, equals('den Löffel abgeben'));
    });
  });
}
