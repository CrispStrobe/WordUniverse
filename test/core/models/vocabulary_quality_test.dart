import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/vocabulary_quality.dart';
import 'package:flutter_test/flutter_test.dart';

GermanWord _word(
  String headword, {
  List<String> definitions = const ['definition'],
  List<String> sources = const [],
}) {
  final enrichment = ApiEnrichment(
    enrichmentStatus: 'success',
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
    entryNotes: const [],
    hypernyms: const [],
    hyponyms: const [],
    holonyms: const [],
    meronyms: const [],
    coordinateTerms: const [],
    gutenbergExamples: const [],
    commonLearnerErrors: const [],
  );
  return GermanWord(
    id: headword,
    word: headword,
    wordType: GermanWordType.andere,
    gradeLevel: 1,
    lemma: headword,
    sources: sources,
    isGrundwortschatzBW: false,
    nurImPlural: false,
    graphematicVariants: const [],
    categories: const [],
    exampleSentences: const [],
    spellingDifficulty: SpellingDifficulty.easy,
    apiEnrichment: enrichment,
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
}

void main() {
  test('accepts ordinary headwords, contractions, and hyphenation', () {
    for (final headword in ['Haus', "didn't", 'E-Mail']) {
      expect(isPresentableVocabularyEntry(_word(headword)), isTrue);
    }
  });

  test('rejects malformed headwords', () {
    for (final headword in ['a. didnt', 'two words', 'word2']) {
      expect(isPresentableVocabularyEntry(_word(headword)), isFalse);
    }
  });

  test('rejects the shipped didnt learner-error record', () {
    expect(
      isPresentableVocabularyEntry(
        _word('didnt', definitions: ["Misspelling of didn't."]),
      ),
      isFalse,
    );
  });

  test('rejects misspelling source records', () {
    expect(
      isPresentableVocabularyEntry(
        _word('accomodate', sources: ['source:common_misspelled']),
      ),
      isFalse,
    );
  });
}
