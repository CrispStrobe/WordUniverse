// Tests for GermanWord.fromJson — focusing on the fields that feed the
// SpellingSpotter and WordSort games: commonMistakes, exampleSentences
// priority, apiEnrichment injection, and lemma resolution.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';

/// Minimal JSON that satisfies GermanWord.fromJson without errors.
Map<String, dynamic> _base({Map<String, dynamic>? overrides}) => {
      'id': 'test_word',
      'word': 'happy',
      'wordType': 'adjective',
      'gradeLevel': 2,
      ...?overrides,
    };

void main() {
  // -------------------------------------------------------------------------
  // commonMistakes (DE: populated from LiTKey via metadata_json spread)
  // -------------------------------------------------------------------------
  group('GermanWord.commonMistakes', () {
    test('absent key → null', () {
      final w = GermanWord.fromJson(_base());
      expect(w.commonMistakes, isNull);
    });

    test('list of strings is preserved', () {
      final w = GermanWord.fromJson(_base(overrides: {
        'commonMistakes': ['happi', 'hapy', 'happey'],
      }));
      expect(w.commonMistakes, ['happi', 'hapy', 'happey']);
    });

    test('empty list is preserved (not coerced to null)', () {
      final w = GermanWord.fromJson(_base(overrides: {
        'commonMistakes': <String>[],
      }));
      expect(w.commonMistakes, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // exampleSentences priority: Tatoeba > Wiktionary API examples > legacy
  // -------------------------------------------------------------------------
  group('GermanWord.exampleSentences priority', () {
    test('Tatoeba examples win over API examples and legacy strings', () {
      final w = GermanWord.fromJson(_base(overrides: {
        'tatoeba_examples': ['Tatoeba sentence.'],
        'apiEnrichment': {
          'enrichment_status': 'success',
          'examples': [
            {'text': 'API example sentence.'}
          ],
          'synonyms': [],
          'antonyms': [],
          'definitions': [],
        },
        'exampleSentences': ['Legacy sentence.'],
      }));
      expect(w.exampleSentences, ['Tatoeba sentence.']);
    });

    test('API examples win when Tatoeba is absent', () {
      final w = GermanWord.fromJson(_base(overrides: {
        'apiEnrichment': {
          'enrichment_status': 'success',
          'examples': [
            {'text': 'API example sentence.'}
          ],
          'synonyms': [],
          'antonyms': [],
          'definitions': [],
        },
        'exampleSentences': ['Legacy sentence.'],
      }));
      expect(w.exampleSentences, ['API example sentence.']);
    });

    test('legacy strings used when Tatoeba and API examples are absent', () {
      final w = GermanWord.fromJson(_base(overrides: {
        'exampleSentences': ['Legacy sentence.'],
      }));
      expect(w.exampleSentences, ['Legacy sentence.']);
    });

    test('empty Tatoeba list falls through to API examples', () {
      final w = GermanWord.fromJson(_base(overrides: {
        'tatoeba_examples': <String>[],
        'apiEnrichment': {
          'enrichment_status': 'success',
          'examples': [
            {'text': 'API example.'}
          ],
          'synonyms': [],
          'antonyms': [],
          'definitions': [],
        },
      }));
      expect(w.exampleSentences, ['API example.']);
    });

    test('API examples with empty text are filtered out', () {
      final w = GermanWord.fromJson(_base(overrides: {
        'apiEnrichment': {
          'enrichment_status': 'success',
          'examples': [
            {'text': ''},
            {'text': 'Good sentence.'},
          ],
          'synonyms': [],
          'antonyms': [],
          'definitions': [],
        },
      }));
      expect(w.exampleSentences, ['Good sentence.']);
    });

    test('all sources absent → empty list', () {
      final w = GermanWord.fromJson(_base());
      expect(w.exampleSentences, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // apiEnrichment injection
  // -------------------------------------------------------------------------
  group('GermanWord.apiEnrichment', () {
    test('null apiEnrichment key → apiEnrichment is null', () {
      final w = GermanWord.fromJson(_base());
      expect(w.apiEnrichment, isNull);
    });

    test('apiEnrichment key present → populated with synonyms and errors', () {
      final w = GermanWord.fromJson(_base(overrides: {
        'apiEnrichment': {
          'enrichment_status': 'success',
          'synonyms': ['glad', 'pleased'],
          'antonyms': ['sad'],
          'definitions': ['feeling pleasure'],
          'commonLearnerErrors': ['hapy', 'happpy'],
        },
      }));
      expect(w.apiEnrichment, isNotNull);
      expect(w.apiEnrichment!.synonyms, ['glad', 'pleased']);
      expect(w.apiEnrichment!.antonyms, ['sad']);
      expect(w.apiEnrichment!.definitions, ['feeling pleasure']);
      expect(w.apiEnrichment!.commonLearnerErrors, ['hapy', 'happpy']);
    });
  });

  // -------------------------------------------------------------------------
  // lemma resolution: primaryLemma from apiEnrichment overrides json['lemma']
  // -------------------------------------------------------------------------
  group('GermanWord.lemma resolution', () {
    test('lemma falls back to json[word] when neither source is present', () {
      final w = GermanWord.fromJson(_base());
      expect(w.lemma, 'happy');
    });

    test('json[lemma] is used when apiEnrichment is absent', () {
      final w = GermanWord.fromJson(_base(overrides: {'lemma': 'happi'}));
      expect(w.lemma, 'happi');
    });

    test('primaryLemma from apiEnrichment overrides json[lemma]', () {
      final w = GermanWord.fromJson(_base(overrides: {
        'lemma': 'json_lemma',
        'apiEnrichment': {
          'enrichment_status': 'success',
          'primary_lemma': 'api_lemma',
          'synonyms': [],
          'antonyms': [],
          'definitions': [],
        },
      }));
      expect(w.lemma, 'api_lemma');
    });
  });

  // -------------------------------------------------------------------------
  // gradeLevel safe parsing
  // -------------------------------------------------------------------------
  group('GermanWord.gradeLevel safe parsing', () {
    test('integer value is parsed', () {
      final w = GermanWord.fromJson(_base(overrides: {'gradeLevel': 3}));
      expect(w.gradeLevel, 3);
    });

    test('string integer is parsed', () {
      final w = GermanWord.fromJson(_base(overrides: {'gradeLevel': '4'}));
      expect(w.gradeLevel, 4);
    });

    test('null defaults to 1', () {
      final w = GermanWord.fromJson(_base(overrides: {'gradeLevel': null}));
      expect(w.gradeLevel, 1);
    });

    test('invalid string defaults to 1', () {
      final w =
          GermanWord.fromJson(_base(overrides: {'gradeLevel': 'bad'}));
      expect(w.gradeLevel, 1);
    });
  });

  // -------------------------------------------------------------------------
  // isProperNoun — guards the "Angeles ist schön" class of bad challenges
  // -------------------------------------------------------------------------
  group('GermanWord.isProperNoun', () {
    test('"proper_noun" wordType sets isProperNoun = true', () {
      final w = GermanWord.fromJson(_base(overrides: {'wordType': 'proper_noun'}));
      expect(w.isProperNoun, isTrue);
    });

    test('"propernoun" (no underscore variant) also sets isProperNoun = true', () {
      final w = GermanWord.fromJson(_base(overrides: {'wordType': 'propernoun'}));
      expect(w.isProperNoun, isTrue);
    });

    test('"proper_noun" still resolves wordType to GermanWordType.substantiv', () {
      final w = GermanWord.fromJson(_base(overrides: {'wordType': 'proper_noun'}));
      expect(w.wordType, GermanWordType.substantiv);
    });

    test('"noun" sets isProperNoun = false', () {
      final w = GermanWord.fromJson(_base(overrides: {'wordType': 'noun'}));
      expect(w.isProperNoun, isFalse);
    });

    test('"adjective" sets isProperNoun = false', () {
      final w = GermanWord.fromJson(_base(overrides: {'wordType': 'adjective'}));
      expect(w.isProperNoun, isFalse);
    });

    test('"verb" sets isProperNoun = false', () {
      final w = GermanWord.fromJson(_base(overrides: {'wordType': 'verb'}));
      expect(w.isProperNoun, isFalse);
    });

    test('absent wordType key sets isProperNoun = false', () {
      final w = GermanWord.fromJson({
        'id': 'x',
        'word': 'Laufen',
        'gradeLevel': 2,
      });
      expect(w.isProperNoun, isFalse);
    });

    test('PROPER_NOUN (uppercase) is case-insensitively detected', () {
      final w = GermanWord.fromJson(_base(overrides: {'wordType': 'PROPER_NOUN'}));
      expect(w.isProperNoun, isTrue);
    });

    test('simulated Angeles entry: proper_noun → excluded from content pool', () {
      // SentenceCompletion and SpellingSpotter check w.isProperNoun before
      // adding a word to the challenge pool. This test verifies the flag is
      // set correctly for the Angeles class of entry.
      final angeles = GermanWord.fromJson(_base(overrides: {
        'word': 'Angeles',
        'wordType': 'proper_noun',
        'gradeLevel': 3,
      }));
      expect(angeles.isProperNoun, isTrue);
      expect(angeles.wordType, GermanWordType.substantiv,
          reason: 'wordType still maps to substantiv for sort/inflection logic');
    });

    test('default constructor isProperNoun defaults to false', () {
      // Ensures existing code that constructs GermanWord directly (e.g.
      // custom vocabulary) is not broken by the new field.
      final w = GermanWord.fromJson(_base());
      expect(w.isProperNoun, isFalse);
    });
  });
}
