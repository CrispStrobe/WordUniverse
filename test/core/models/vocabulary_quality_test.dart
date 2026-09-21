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

  group('isUsableDefinition, continued', () {
    test('rejects a gloss that stops mid-sentence', () {
      // Shipped: the German gloss of "hupen".
      expect(isUsableDefinition('eine Hupe am Kraftfahrzeug betätigen, um'),
          isFalse);
      expect(isUsableDefinition('Ein Gerät zum'), isFalse);
      expect(isUsableDefinition('A device used for,'), isFalse);
      // "Eine Alternative ist,." — stopped, then punctuated anyway.
      expect(isUsableDefinition('Eine Alternative ist,.'), isFalse);
    });

    test('a gloss that merely ends in a short word is fine', () {
      expect(isUsableDefinition('Etwas, das man gerne tut.'), isTrue);
      expect(isUsableDefinition('A person who helps.'), isTrue);
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

    test('catches religious figures', () {
      // "jesus" reached an English grade 3 definition quiz.
      expect(
          describesAName('Jesus of Nazareth, a first-century Jewish '
              'religious preacher, held to be the Messiah in Christianity.'),
          isTrue);
    });

    test('a state of being is not a state of the union', () {
      expect(
          describesAName('The state of being free from physical or '
              'psychological disease.'),
          isFalse);
      expect(describesAName('A state of the United States.'), isTrue);
    });

    test('catches German place glosses in the appositive form', () {
      expect(describesAName('eine Stadt in Nordrhein-Westfalen, Deutschland'),
          isTrue);
    });

    test('catches the shorter ways Wiktionary says "this is a name"', () {
      // Three English entries word it this way and came through as ordinary
      // vocabulary while the other 63 were typed proper_noun in the pack.
      expect(
          describesAName('A diminutive of Edward, Edgar, Edwin, or other '
              'male given names beginning with Ed-.'),
          isTrue);
      expect(
          describesAName('A short version of Frederick, Alfred, or Wilfred, '
              'also used as a formal given name.'),
          isTrue);
      expect(describesAName('An English placename.'), isTrue);
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

  group('sentenceSuitsAChild', () {
    test('keeps ordinary sentences', () {
      expect(
          sentenceSuitsAChild('Wir frühstücken immer in der Küche.'), isTrue);
      expect(sentenceSuitsAChild('The cat sat on the mat.'), isTrue);
      expect(sentenceSuitsAChild('Kriegen wir heute noch ein Eis?'), isTrue,
          reason: '"kriegen" is not "Kriege" — German nouns are capitalised, '
              'which is the whole reason this half of the rule is '
              'case-sensitive');
      expect(sentenceSuitsAChild('She was warm and well.'), isTrue);
    });

    test('drops a sentence written four centuries ago', () {
      // 6% of the English example sentences are Early Modern English: a cloze
      // gap arrived built on "He that feareth oblatration must not travel".
      expect(
          sentenceSuitsAChild('He that feareth oblatration must not '
              'travel.'),
          isFalse);
      expect(sentenceSuitsAChild('Thou shalt be a father of many nations.'),
          isFalse);
      // The long s settles the scanned quartos, in either language.
      expect(
          sentenceSuitsAChild('The prince is here at hand, pleaſeth your '
              'Lordſhip.'),
          isFalse);
      expect(
          sentenceSuitsAChild('„Manchmal ſieht man Berlinerinnen auf ihren '
              'Balkons ſitzen."'),
          isFalse);
    });

    test('a name that ends in -eth is not archaic', () {
      // The reason that half of the rule is case-sensitive: Elisabeth,
      // Sabeth and Lambeth are all in the German pack's sentences.
      expect(sentenceSuitsAChild('Elisabeth wohnt nicht mehr auf dem Schloss.'),
          isTrue);
      expect(sentenceSuitsAChild('He works in Lambeth.'), isTrue);
    });

    test('drops the ones a model flagged', () {
      // Shipped as the example for "auffordern".
      expect(
          sentenceSuitsAChild('„Die syrische Armee fordert Rebellen und '
              'Bewohner auf, die Stadt zu verlassen."'),
          isFalse);
      expect(
          sentenceSuitsAChild('We had to ration our food because there '
              'was a war on.'),
          isFalse);
      expect(sentenceSuitsAChild('Der Mann wurde erschossen.'), isFalse);
      expect(sentenceSuitsAChild('The soldiers killed him.'), isFalse);
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
