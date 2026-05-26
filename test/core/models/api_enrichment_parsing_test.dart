// Tests for ApiEnrichment.fromJson — particularly the new fields added for
// the SpellingSpotter game and WordSort synonym hints.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';

/// Minimal valid ApiEnrichment JSON. Every test overrides only the fields
/// it cares about; the rest are absent / null so the parser uses defaults.
Map<String, dynamic> _base({Map<String, dynamic>? overrides}) => {
      'enrichment_status': 'success',
      ...?overrides,
    };

void main() {
  // -------------------------------------------------------------------------
  // commonLearnerErrors
  // -------------------------------------------------------------------------
  group('ApiEnrichment.commonLearnerErrors parsing', () {
    test('null → empty list', () {
      final e = ApiEnrichment.fromJson(_base());
      expect(e.commonLearnerErrors, isEmpty);
    });

    test('empty list → empty list', () {
      final e = ApiEnrichment.fromJson(
          _base(overrides: {'commonLearnerErrors': []}));
      expect(e.commonLearnerErrors, isEmpty);
    });

    test('list of strings → returned as-is', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'commonLearnerErrors': ['recieve', 'acheive', 'occured'],
      }));
      expect(e.commonLearnerErrors, ['recieve', 'acheive', 'occured']);
    });

    test('list of maps with error key → extracts string values', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'commonLearnerErrors': [
          {'error': 'recieve', 'freq': 42},
          {'error': 'acheive', 'freq': 17},
        ],
      }));
      expect(e.commonLearnerErrors, ['recieve', 'acheive']);
    });

    test('mixed strings and maps → handles both shapes', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'commonLearnerErrors': [
          'recieve',
          {'error': 'occured'},
        ],
      }));
      expect(e.commonLearnerErrors, ['recieve', 'occured']);
    });

    test('empty string entries are filtered out', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'commonLearnerErrors': ['recieve', '', 'occured'],
      }));
      expect(e.commonLearnerErrors, ['recieve', 'occured']);
    });

    test('map entries with null/missing error key are filtered out', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'commonLearnerErrors': [
          {'error': null},
          {'error': 'recieve'},
          {'other_key': 'x'},
        ],
      }));
      expect(e.commonLearnerErrors, ['recieve']);
    });

    test('non-list value (e.g. a string) → returns empty list', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'commonLearnerErrors': 'recieve',
      }));
      expect(e.commonLearnerErrors, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // synonyms / antonyms
  // -------------------------------------------------------------------------
  group('ApiEnrichment.synonyms and .antonyms parsing', () {
    test('null synonyms → empty list', () {
      final e = ApiEnrichment.fromJson(_base());
      expect(e.synonyms, isEmpty);
    });

    test('null antonyms → empty list', () {
      final e = ApiEnrichment.fromJson(_base());
      expect(e.antonyms, isEmpty);
    });

    test('synonyms list is returned verbatim', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'synonyms': ['happy', 'joyful', 'content'],
      }));
      expect(e.synonyms, ['happy', 'joyful', 'content']);
    });

    test('antonyms list is returned verbatim', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'antonyms': ['sad', 'miserable'],
      }));
      expect(e.antonyms, ['sad', 'miserable']);
    });
  });

  // -------------------------------------------------------------------------
  // gradeExamples
  // -------------------------------------------------------------------------
  group('ApiEnrichment.gradeExamples parsing', () {
    test('null → null', () {
      final e = ApiEnrichment.fromJson(_base());
      expect(e.gradeExamples, isNull);
    });

    test('non-map (e.g. list) → null', () {
      final e = ApiEnrichment.fromJson(
          _base(overrides: {'grade_examples': ['a', 'b']}));
      expect(e.gradeExamples, isNull);
    });

    test('empty map → null', () {
      final e =
          ApiEnrichment.fromJson(_base(overrides: {'grade_examples': {}}));
      expect(e.gradeExamples, isNull);
    });

    test('grade keys map to sentence lists', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'grade_examples': {
          '1': ['The cat sat.', 'Dogs run.'],
          '3': ['She reads every day.'],
        },
      }));
      expect(e.gradeExamples, isNotNull);
      expect(e.gradeExamples!['1'], ['The cat sat.', 'Dogs run.']);
      expect(e.gradeExamples!['3'], ['She reads every day.']);
    });

    test('non-list value for a grade key is skipped', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'grade_examples': {
          '1': ['The cat sat.'],
          '2': 'not a list',
        },
      }));
      expect(e.gradeExamples!.containsKey('1'), isTrue);
      expect(e.gradeExamples!.containsKey('2'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // gutenbergExamples
  // -------------------------------------------------------------------------
  group('ApiEnrichment.gutenbergExamples parsing', () {
    test('null → empty list', () {
      final e = ApiEnrichment.fromJson(_base());
      expect(e.gutenbergExamples, isEmpty);
    });

    test('list is returned verbatim', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'gutenberg_examples': ['She smiled warmly.', 'He laughed.'],
      }));
      expect(e.gutenbergExamples, ['She smiled warmly.', 'He laughed.']);
    });
  });

  // -------------------------------------------------------------------------
  // enrichmentStatus default
  // -------------------------------------------------------------------------
  group('ApiEnrichment.enrichmentStatus', () {
    test("absent key defaults to 'unknown'", () {
      final e = ApiEnrichment.fromJson({});
      expect(e.enrichmentStatus, 'unknown');
    });

    test('present value is preserved', () {
      final e = ApiEnrichment.fromJson({'enrichment_status': 'success'});
      expect(e.enrichmentStatus, 'success');
    });
  });

  // -------------------------------------------------------------------------
  // definitions
  // -------------------------------------------------------------------------
  group('ApiEnrichment.definitions parsing', () {
    test('null → empty list', () {
      final e = ApiEnrichment.fromJson(_base());
      expect(e.definitions, isEmpty);
    });

    test('list preserved', () {
      final e = ApiEnrichment.fromJson(_base(overrides: {
        'definitions': ['feeling happy', 'contented state'],
      }));
      expect(e.definitions, ['feeling happy', 'contented state']);
    });
  });
}
