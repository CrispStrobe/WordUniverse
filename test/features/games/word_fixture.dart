// test/features/games/word_fixture.dart
//
// Building a GermanWord takes thirty named arguments, most of which no test
// cares about. These helpers fill in the rest so a test can say what it is
// actually about.
//
// Not a _test file: imported by the service tests in this directory.

import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';

ApiEnrichment testEnrichment({
  List<String> definitions = const [],
  List<String> synonyms = const [],
  List<String> antonyms = const [],
  List<ApiSemanticTerm> hypernyms = const [],
  List<ApiSemanticTerm> hyponyms = const [],
  List<String> hyphenation = const [],
  List<String> commonLearnerErrors = const [],
  List<ApiExample> examples = const [],
  List<ApiExpression> expressions = const [],
  List<ApiProverb> proverbs = const [],
  List<ApiTranslation> translations = const [],
  List<Map<String, dynamic>> inflections = const [],
  Map<String, List<String>>? gradeExamples,
  String enrichmentStatus = 'ok',
}) =>
    ApiEnrichment(
      enrichmentStatus: enrichmentStatus,
      definitions: definitions,
      pronunciation: const [],
      examples: examples,
      synonyms: synonyms,
      antonyms: antonyms,
      conceptnet: const [],
      alternativeAnalyses: const [],
      inflections: inflections,
      semanticRelations: const [],
      hyphenation: hyphenation,
      translations: translations,
      derivedTerms: const [],
      relatedTerms: const [],
      expressions: expressions,
      proverbs: proverbs,
      entryNotes: const [],
      hypernyms: hypernyms,
      hyponyms: hyponyms,
      holonyms: const [],
      meronyms: const [],
      coordinateTerms: const [],
      gutenbergExamples: const [],
      commonLearnerErrors: commonLearnerErrors,
      gradeExamples: gradeExamples,
    );

/// A hypernym/hyponym entry, which the packs store as {word, senseIndex}.
ApiSemanticTerm term(String word) => ApiSemanticTerm(word: word);

/// A catalogue word. [enrichment] is where definitions, synonyms and the rest
/// live; the top-level lists mirror what GermanWord.fromJson fills in.
GermanWord testWord(
  String word, {
  GermanWordType type = GermanWordType.substantiv,
  int grade = 3,
  String? lemma,
  String? article,
  bool isProperNoun = false,
  int features = 0,
  List<String> sources = const [],
  List<String>? commonMistakes,
  List<ApiExample> examples = const [],
  List<String> hyphenation = const [],
  List<Map<String, dynamic>> wiktionaryInflections = const [],
  ApiEnrichment? enrichment,
}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: type,
      gradeLevel: grade,
      lemma: lemma ?? word,
      article: article,
      sources: sources,
      isGrundwortschatzBW: false,
      nurImPlural: false,
      graphematicVariants: const [],
      categories: const [],
      exampleSentences: const [],
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: isProperNoun,
      features: features,
      commonMistakes: commonMistakes,
      apiEnrichment: enrichment,
      examples: examples,
      hyphenation: hyphenation,
      wiktionaryInflections: wiktionaryInflections,
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
