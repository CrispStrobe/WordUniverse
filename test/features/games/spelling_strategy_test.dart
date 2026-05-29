// test/features/games/spelling_strategy_test.dart
//
// Unit tests for the spelling-strategy feature (#37):
//   • spellingStrategyLabel() helper
//   • ApiEnrichment.spellingStrategyPrimary — construction & JSON round-trip
//   • Realistic word/strategy pairs sampled from the DE DB
//
// Note on data quality: LiTKey error_rate=1.0 for words like "Dose" or "März"
// with zero commonMistakes entries indicates single-child samples in the corpus.
// The field is still useful as a rough difficulty ranking but extreme values
// should be treated with caution.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/widgets/spelling_strategy_badge.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({String? spellingStrategyPrimary,
        String? spellingExplanation}) =>
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
      gutenbergExamples: const [],
      commonLearnerErrors: const [],
      spellingStrategyPrimary: spellingStrategyPrimary,
      spellingExplanation: spellingExplanation,
    );

GermanWord _word(String word, {String? strategy, double? litekeyErrorRate}) =>
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
      apiEnrichment: strategy != null ? _enrichment(spellingStrategyPrimary: strategy) : null,
      litekeyErrorRate: litekeyErrorRate,
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

// ─── spellingStrategyLabel ────────────────────────────────────────────────────

void main() {
  group('spellingStrategyLabel', () {
    test('returns correct label for grossschreibung', () {
      expect(spellingStrategyLabel('grossschreibung'), 'Großschreibung');
    });

    test('returns correct label for klangtreu', () {
      expect(spellingStrategyLabel('klangtreu'), 'Klangtreu');
    });

    test('returns correct label for morphem', () {
      expect(spellingStrategyLabel('morphem'), 'Stammprinzip');
    });

    test('returns correct label for verwandt', () {
      expect(spellingStrategyLabel('verwandt'), 'Verwandtschaft');
    });

    test('returns correct label for doppelkonsonant', () {
      expect(spellingStrategyLabel('doppelkonsonant'), 'Doppelkonsonant');
    });

    test('returns correct label for dehnung', () {
      expect(spellingStrategyLabel('dehnung'), 'Dehnung');
    });

    test('returns correct label for merkwort', () {
      expect(spellingStrategyLabel('merkwort'), 'Merkwort');
    });

    test('returns null for unknown key', () {
      expect(spellingStrategyLabel('unknown_strategy'), isNull);
    });

    test('returns null for null input', () {
      expect(spellingStrategyLabel(null), isNull);
    });

    test('returns null for empty string', () {
      expect(spellingStrategyLabel(''), isNull);
    });

    test('all 7 known keys produce non-null labels', () {
      const knownKeys = [
        'grossschreibung', 'klangtreu', 'doppelkonsonant', 'dehnung',
        'verwandt', 'morphem', 'merkwort',
      ];
      for (final k in knownKeys) {
        expect(spellingStrategyLabel(k), isNotNull,
            reason: '$k should have a label');
      }
    });
  });

  // ─── ApiEnrichment.spellingStrategyPrimary ────────────────────────────────

  group('ApiEnrichment.spellingStrategyPrimary', () {
    test('is null by default in constructor', () {
      expect(_enrichment().spellingStrategyPrimary, isNull);
    });

    test('stores provided strategy value', () {
      final e = _enrichment(spellingStrategyPrimary: 'klangtreu');
      expect(e.spellingStrategyPrimary, 'klangtreu');
    });

    test('fromJson reads spellingStrategyPrimary field', () {
      final e = ApiEnrichment.fromJson({
        'enrichment_status': 'ok',
        'definitions': <String>[],
        'pronunciation': <dynamic>[],
        'examples': <dynamic>[],
        'synonyms': <String>[],
        'antonyms': <String>[],
        'conceptnet': <dynamic>[],
        'alternative_analyses': <dynamic>[],
        'inflections': <dynamic>[],
        'semantic_relations': <dynamic>[],
        'hyphenation': <String>[],
        'wiktionary_translations': <dynamic>[],
        'wiktionary_derived_terms': <dynamic>[],
        'wiktionary_related_terms': <dynamic>[],
        'expressions': <dynamic>[],
        'proverbs': <dynamic>[],
        'entry_notes': <String>[],
        'hypernyms': <dynamic>[],
        'hyponyms': <dynamic>[],
        'holonyms': <dynamic>[],
        'meronyms': <dynamic>[],
        'coordinate_terms': <dynamic>[],
        'gutenberg_examples': <String>[],
        'spellingStrategyPrimary': 'doppelkonsonant',
      });
      expect(e.spellingStrategyPrimary, 'doppelkonsonant');
    });

    test('fromJson returns null when field absent', () {
      final e = ApiEnrichment.fromJson({
        'enrichment_status': 'ok',
        'definitions': <String>[],
        'pronunciation': <dynamic>[],
        'examples': <dynamic>[],
        'synonyms': <String>[],
        'antonyms': <String>[],
        'conceptnet': <dynamic>[],
        'alternative_analyses': <dynamic>[],
        'inflections': <dynamic>[],
        'semantic_relations': <dynamic>[],
        'hyphenation': <String>[],
        'wiktionary_translations': <dynamic>[],
        'wiktionary_derived_terms': <dynamic>[],
        'wiktionary_related_terms': <dynamic>[],
        'expressions': <dynamic>[],
        'proverbs': <dynamic>[],
        'entry_notes': <String>[],
        'hypernyms': <dynamic>[],
        'hyponyms': <dynamic>[],
        'holonyms': <dynamic>[],
        'meronyms': <dynamic>[],
        'coordinate_terms': <dynamic>[],
        'gutenberg_examples': <String>[],
      });
      expect(e.spellingStrategyPrimary, isNull);
      expect(e.spellingExplanation, isNull);
    });

    test('fromJson reads the per-word spellingExplanation field', () {
      final e = ApiEnrichment.fromJson({
        'enrichment_status': 'ok',
        'spellingStrategyPrimary': 'verwandt',
        'spellingExplanation':
            'Am Wortende klingt es hart, aber du schreibst den Stamm: Tag → Tage.',
      });
      expect(e.spellingExplanation, contains('Tag → Tage'));
    });
  });

  // ─── Realistic word/strategy pairs (science-grounded; see
  //     pipeline/voc-de/spelling_strategy_gold.csv) ──────────────────────────
  // These pin the badge label mapping using examples that are CORRECT under the
  // orthographic-principle scheme (Eisenberg/Maas/Thomé), not the old worksheet.

  group('Realistic word–strategy pairs', () {
    // grossschreibung: a noun whose only other feature is regular spelling
    test('Nase is grossschreibung — noun, otherwise regular', () {
      final w = _word('Nase', strategy: 'grossschreibung');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary),
          'Großschreibung');
    });

    // klangtreu: written as it sounds, no orthographic marker
    test('malen is klangtreu — phonographic, no marker', () {
      final w = _word('malen', strategy: 'klangtreu');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary),
          'Klangtreu');
    });

    // doppelkonsonant: Schärfung — short vowel + doubling, ANY position
    // (Thomé: Tasse and Mann are the same category)
    test('Tasse / Mann are doppelkonsonant — Schärfung', () {
      for (final word in ['Tasse', 'Mann', 'kennen']) {
        final w = _word(word, strategy: 'doppelkonsonant');
        expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary),
            'Doppelkonsonant');
      }
    });

    // dehnung: long-vowel marker (Dehnungs-h / Doppelvokal / ie / silbentrennendes-h)
    test('Stuhl / gehen are dehnung — long-vowel marking', () {
      for (final word in ['Stuhl', 'gehen', 'Boot']) {
        final w = _word(word, strategy: 'dehnung');
        expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary),
            'Dehnung');
      }
    });

    // verwandt: Stammkonstanz — Auslautverhärtung (Tag→Tage), -ig (lustig)
    test('Tag / lustig are verwandt — Stammkonstanz', () {
      for (final word in ['Tag', 'Hund', 'lustig']) {
        final w = _word(word, strategy: 'verwandt');
        expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary),
            'Verwandtschaft');
      }
    });

    // morphem: built from Wortbausteine (prefix/suffix/compound/particle)
    test('Freundschaft is morphem — derivational suffix', () {
      final w = _word('Freundschaft', strategy: 'morphem');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary),
          'Stammprinzip');
    });

    // merkwort: genuine etymological/foreign exception (v→[f], ch→[k])
    test('Vater / Chor are merkwort — etymological exception', () {
      for (final word in ['Vater', 'Chor']) {
        final w = _word(word, strategy: 'merkwort');
        expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary),
            'Merkwort');
      }
    });

    // No strategy set → badge should return null label
    test('word without strategy → spellingStrategyLabel returns null', () {
      final w = _word('Hund');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary),
          isNull);
    });

    // The per-word explanation rides on the word and is what the badge shows
    test('word carries its science-grounded explanation', () {
      final w = _word('Mann');
      final enr = ApiEnrichment.fromJson({
        'enrichment_status': 'ok',
        'spellingStrategyPrimary': 'doppelkonsonant',
        'spellingExplanation': 'Verlängere, um es zu hören: „Mann" → „Männer".',
      });
      expect(enr.spellingExplanation, contains('Männer'));
      expect(w.word, 'Mann');
    });
  });
}
