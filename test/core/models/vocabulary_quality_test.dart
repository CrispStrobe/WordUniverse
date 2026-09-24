import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/vocabulary_quality.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/games/word_fixture.dart';

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

    test('catches the German pack\'s "kind of place, then where it is"', () {
      // This rule shipped dead: its trailing \b had been written as a
      // literal backspace byte, so it asked for a control character after
      // the preposition and matched nothing at all. Nobody noticed because
      // repair_pack.py carries its own correct copy, and that is what typed
      // the 70 places in the pack. Asserting the rule *fires* is what a test
      // for it is for; asserting it exists would have passed throughout.
      expect(describesAName('Stadt im US-Bundesstaat Pennsylvania'), isTrue);
      expect(describesAName('Staat in Ostasien'), isTrue);
      expect(describesAName('Bundesstaat im Südosten der USA'), isTrue);
      expect(
          describesAName('Kontinent, der das Festland des Staats Australien '
              'umfasst'),
          isTrue);
    });

    test('but not the ordinary words that share those openings', () {
      // The locating word right after the noun is the whole of the rule's
      // safety: without it these four are places too.
      expect(
          describesAName('Land oder Länder außerhalb des eigenen '
              'Staatsgebiets'),
          isFalse);
      expect(describesAName('vollständig von Wasser umgebenes Stück Land'),
          isFalse);
      expect(describesAName('größeres, fließendes Gewässer'), isFalse);
      expect(describesAName('Bereich um einen Ort'), isFalse);
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

  group('classIsContradicted', () {
    // 2% of the English pack and 0.5% of the German one; the column is the
    // half that is wrong, and it is wrong about exactly the function words.
    test('a word filed as a noun whose own primary_pos says otherwise', () {
      expect(
          classIsContradicted(testWord('at',
              type: GermanWordType.substantiv,
              enrichment: testEnrichment(primaryPos: 'preposition'))),
          isTrue);
      expect(
          classIsContradicted(testWord('he',
              type: GermanWordType.substantiv,
              enrichment: testEnrichment(primaryPos: 'pronoun'))),
          isTrue);
    });

    test('the two spellings of the same class agree', () {
      // The packs write the class differently in the two fields: the column
      // says "substantiv" and "adjektiv" where primary_pos says "noun" and
      // "adj", and reading those as disagreements would empty the game.
      expect(
          classIsContradicted(testWord('Haus',
              type: GermanWordType.substantiv,
              enrichment: testEnrichment(primaryPos: 'noun'))),
          isFalse);
      expect(
          classIsContradicted(testWord('schön',
              type: GermanWordType.adjektiv,
              enrichment: testEnrichment(primaryPos: 'adj'))),
          isFalse);
    });

    test('a word with no primary_pos is not contradicted', () {
      // Three thousand German entries have none; they are not suspect.
      expect(
          classIsContradicted(
              testWord('Baum', type: GermanWordType.substantiv)),
          isFalse);
    });
  });

  group('glossSuitsAChild', () {
    test('drops the ones written for a naturalist', () {
      // All five games that show a hint gloss were showing this one.
      expect(
          glossSuitsAChild('A ruminant, of the genus Giraffa, of the African '
              'savannah with long legs and highly elongated neck, making them '
              'the tallest living animal; yellow fur patterned with dark '
              'spots; strictly speaking the horn-like projections are '
              'ossicones.'),
          isFalse);
      expect(glossSuitsAChild('A mammal of the family Canidae.'), isFalse);
      expect(glossSuitsAChild('An adult female of the species Bos taurus.'),
          isFalse);
    });

    test('keeps a gloss a child can read', () {
      expect(
          glossSuitsAChild('The amount of rain that falls on a single '
              'occasion'),
          isTrue);
      expect(glossSuitsAChild('Harsh and rough-sounding.'), isTrue);
      expect(glossSuitsAChild('Muttertier des Hausrinds'), isTrue);
      expect(glossSuitsAChild('erneutes Treffen von Personen'), isTrue);
    });

    test('a gloss merely above the reader is not caught, and that is known',
        () {
      // "honest" is explained with "scrupulous" and "swindling". Telling that
      // apart from an ordinary gloss needs to know which words the reader
      // has, and counting the ones missing from the catalogue reads German
      // compounds as unknown and calls "Muttertier des Hausrinds" the hardest
      // gloss in the pack.
      expect(
          glossSuitsAChild('Scrupulous with regard to telling the truth; not '
              'given to swindling, lying, or fraud; upright.'),
          isTrue);
    });
  });

  group('classIsSettled', () {
    test('a word whose senses span two classes is not asked', () {
      // "answer" is filed as a noun and its primary_pos agrees; WordNet gives
      // it five noun senses and ten verb ones. A learner answering Verb is
      // not wrong, so the question is not fair to ask.
      expect(
          classIsSettled(testWord('answer',
              type: GermanWordType.substantiv,
              enrichment:
                  testEnrichment(primaryPos: 'noun', wordnetSenses: const [
                WordNetSense(pos: 'noun', definition: 'a reply'),
                WordNetSense(pos: 'verb', definition: 'to reply'),
              ]))),
          isFalse);
    });

    test('a word whose senses all name another class is not asked', () {
      // "annoyed" is filed as a verb and primary_pos agrees; every sense it
      // has is an adjective. Two opinions out of three were wrong together.
      expect(
          classIsSettled(testWord('annoyed',
              type: GermanWordType.verb,
              enrichment:
                  testEnrichment(primaryPos: 'verb', wordnetSenses: const [
                WordNetSense(pos: 'adjective', definition: 'troubled'),
                WordNetSense(pos: 'adjective', definition: 'irritated'),
              ]))),
          isFalse);
    });

    test('agreement on all three is settled', () {
      expect(
          classIsSettled(testWord('raucous',
              type: GermanWordType.adjektiv,
              enrichment:
                  testEnrichment(primaryPos: 'adjective', wordnetSenses: const [
                WordNetSense(pos: 'adjective', definition: 'harsh'),
              ]))),
          isTrue);
    });

    test('no senses means the other two opinions decide', () {
      // Four thousand English entries and every German one carry none.
      expect(
          classIsSettled(testWord('giraffe',
              type: GermanWordType.substantiv,
              enrichment: testEnrichment(primaryPos: 'noun'))),
          isTrue);
      expect(
          classIsSettled(testWord('at',
              type: GermanWordType.substantiv,
              enrichment: testEnrichment(primaryPos: 'preposition'))),
          isFalse);
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

    test('drops a clinical sentence about ordinary words', () {
      // Labelling a review sheet turned up this as a gap exercise on the
      // verb "convey". Nothing in it is a banned word, which is why every
      // other rule passed it.
      expect(
          sentenceSuitsAChild('The Fallopian Tubes, or oviducts, convey the '
              'ova from the ovaries to the cavity of the uterus.'),
          isFalse);
      expect(
          sentenceSuitsAChild('Normalerweise schützt die Plazenta den Fötus '
              'vor dem Stresshormon Cortisol.'),
          isFalse);
      // Words that are ordinary in another sense are deliberately not in it.
      expect(sentenceSuitsAChild('Wir säen die Samen im Frühling.'), isTrue);
      expect(sentenceSuitsAChild('Das Schwert steckt in der Scheide.'), isTrue);
      expect(sentenceSuitsAChild('She hurt her cervical spine.'), isTrue);
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
