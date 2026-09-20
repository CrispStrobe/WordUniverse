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

  group('isUsableDefinition', () {
    test('accepts an explanation', () {
      expect(isUsableDefinition('A large natural stream of water.'), isTrue);
      expect(isUsableDefinition('Not shared.'), isTrue);
    });

    test('rejects a parse of the word', () {
      // Both shipped: "passerbys" and "annointed" are English grade 6.
      expect(isUsableDefinition('plural of passerby'), isFalse);
      expect(isUsableDefinition('simple past and past participle of annoint'),
          isFalse);
      expect(isUsableDefinition('Partizip Präsens des Verbs wüten'), isFalse);
      expect(
          isUsableDefinition('Nominativ Singular Femininum attributiv des '
              'Indefinitpronomens jeder'),
          isFalse);
    });

    test('rejects an abbreviation', () {
      expect(isUsableDefinition('Abbreviation of July.'), isFalse);
    });

    test('rejects a bare domain label', () {
      // The German pack offers this as the meaning of "Mais".
      expect(isUsableDefinition('Botanik:'), isFalse);
    });

    test('rejects a one-word gloss', () {
      // "residental" is glossed "residentiary" — a misspelling pointing at an
      // obscure word.
      expect(isUsableDefinition('residentiary'), isFalse);
    });

    test('rejects a name', () {
      expect(isUsableDefinition('The capital city of the United Kingdom.'),
          isFalse);
      expect(isUsableDefinition('Afrika ist ein Kontinent.'), isFalse);
    });
  });

  group('describesAName', () {
    test('catches the German pack\'s sentence glosses', () {
      expect(describesAName('Afrika ist ein Kontinent.'), isTrue);
      expect(describesAName('Berlin ist eine Stadt.'), isTrue);
    });

    test('catches a capital without the leading article', () {
      expect(
          describesAName('The capital city of the United Kingdom; the capital '
              'city of England.'),
          isTrue);
    });

    test('catches peoples and languages', () {
      expect(
          describesAName('Any of the languages of these aboriginal peoples.'),
          isTrue);
    });

    test('leaves ordinary meanings alone', () {
      expect(describesAName('A large natural stream of water.'), isFalse);
      expect(describesAName('ein Gebäude zum Wohnen'), isFalse);
    });
  });

  test('rejects an entry the pack tags as often misspelled', () {
    expect(
      isPresentableVocabularyEntry(
        _word('desireable', definitions: ['Archaic form of desirable.']),
      ),
      isFalse,
    );
  });
}
