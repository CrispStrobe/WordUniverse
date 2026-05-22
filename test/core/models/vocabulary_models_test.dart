import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';

void main() {
  test('GermanWord.fromJson maps English POS tokens to existing enum values',
      () {
    final cases = {
      'noun': GermanWordType.substantiv,
      'verb': GermanWordType.verb,
      'adjective': GermanWordType.adjektiv,
      'adverb': GermanWordType.adverb,
      'pronoun': GermanWordType.pronomen,
      'preposition': GermanWordType.praeposition,
      'conjunction': GermanWordType.konjunktion,
      'article': GermanWordType.artikel,
      'numeral': GermanWordType.numerale,
      'particle': GermanWordType.partikel,
    };

    for (final entry in cases.entries) {
      final word = GermanWord.fromJson({
        'id': 'test_${entry.key}',
        'word': entry.key,
        'lemma': entry.key,
        'wordType': entry.key,
        'gradeLevel': 1,
      });

      expect(word.wordType, entry.value, reason: entry.key);
    }
  });
}
