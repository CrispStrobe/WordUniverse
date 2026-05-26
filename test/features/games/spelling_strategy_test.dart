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

ApiEnrichment _enrichment({String? spellingStrategyPrimary}) => ApiEnrichment(
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

    test('all 6 known keys produce non-null labels', () {
      const knownKeys = [
        'grossschreibung', 'klangtreu', 'morphem',
        'verwandt', 'doppelkonsonant', 'merkwort',
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
    });
  });

  // ─── Realistic word/strategy pairs (sampled from DE DB) ──────────────────

  group('Realistic word–strategy pairs', () {
    // grossschreibung: DE Nouns are capitalized → strategy is about the rule
    test('Anfang is grossschreibung — noun, capitalized', () {
      final w = _word('Anfang', strategy: 'grossschreibung');
      expect(w.apiEnrichment?.spellingStrategyPrimary, 'grossschreibung');
      expect(spellingStrategyLabel('grossschreibung'), 'Großschreibung');
    });

    // klangtreu: written as it sounds
    test('backen is klangtreu — phonetically transparent', () {
      final w = _word('backen', strategy: 'klangtreu');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary), 'Klangtreu');
    });

    // morphem: root principle — "erst" shares root with "Erste"
    test('erst is morphem — root-principled spelling', () {
      final w = _word('erst', strategy: 'morphem');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary), 'Stammprinzip');
    });

    // verwandt: spelling derived from related form
    // "hören" — the ö is consistent with related noun "Ohr"
    test('hören is verwandt — related to Ohr (ear)', () {
      final w = _word('hören', strategy: 'verwandt');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary), 'Verwandtschaft');
    });

    // doppelkonsonant: short vowel before double consonant
    test('kennen is doppelkonsonant — short e, nn', () {
      final w = _word('kennen', strategy: 'doppelkonsonant');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary), 'Doppelkonsonant');
    });

    // merkwort: sight word, must be memorised (function words)
    test('ab is merkwort — preposition with no phonetic rule', () {
      final w = _word('ab', strategy: 'merkwort');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary), 'Merkwort');
    });

    // No strategy set → badge should return null label
    test('word without strategy → spellingStrategyLabel returns null', () {
      final w = _word('Hund');
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary), isNull);
    });

    // doppelkonsonant examples have consistently high error rates
    // (kennen: 67%, fallen: 42%, kommen: 27%) — confirms the strategy badge
    // is most informative for the words kids actually find hard
    test('doppelkonsonant word with high error rate — badge label is non-null', () {
      final w = _word('kennen', strategy: 'doppelkonsonant', litekeyErrorRate: 0.67);
      expect(spellingStrategyLabel(w.apiEnrichment?.spellingStrategyPrimary), isNotNull);
      expect(w.litekeyErrorRate, closeTo(0.67, 0.001));
    });

    // merkwort (sight words) tend to have low error rates — kids learn them
    // through sheer frequency ("ab" 13%, "aber" 7%, "als" 8%)
    test('merkwort words have low error rates (high-frequency function words)', () {
      for (final pair in [
        ('ab', 0.13), ('aber', 0.07), ('als', 0.08), ('am', 0.02),
      ]) {
        final w = _word(pair.$1, strategy: 'merkwort', litekeyErrorRate: pair.$2);
        expect(w.litekeyErrorRate, lessThan(0.2),
            reason: '${pair.$1} is a high-freq function word, should be easy');
      }
    });

    // verwandt words with Umlauts are harder (dürfen: 71%, hören: 43%, böse: 36%)
    test('verwandt Umlaut words have notably higher error rates', () {
      final hard = [
        ('dürfen', 0.71), ('hören', 0.43), ('böse', 0.36),
      ];
      for (final pair in hard) {
        final w = _word(pair.$1, strategy: 'verwandt', litekeyErrorRate: pair.$2);
        expect(w.litekeyErrorRate, greaterThan(0.3),
            reason: '${pair.$1} Umlaut form is hard for children');
      }
    });
  });
}
