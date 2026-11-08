import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/spelling_spotter_service.dart';

GermanWord _word([Map<String, dynamic> metadata = const {}]) =>
    GermanWord.fromJson({
      'id': 'evidence_word',
      'word': 'Wort',
      'lemma': 'Wort',
      'wordType': 'noun',
      'sources': ['BW1'],
      'gradeLevel': 1,
      'spellingDifficulty': 0,
      ...metadata,
    });

void main() {
  test('a compatibility zero and a curriculum band do not imply measured ease',
      () {
    final word = _word();
    expect(word.spellingDifficulty, SpellingDifficulty.easy);
    expect(word.spellingDifficultySource, 'unknown');
    expect(word.spellingDifficultyEvidence['status'], 'unknown');
    expect(word.spellingDifficultyEvidence['source'], isNull);
    expect(word.spellingDifficultyEvidence['calibrated'], isFalse);
    expect(word.litekeyErrorRate, isNull);
    expect(spellingDifficultyScore(word, isDE: true), 0.5);
    expect(word.gradeLevelEstimate, isNull);
    expect(word.gradeLevelEstimateSource, 'unknown');
  });

  test(
      'an actual zero error rate survives persistence without invented samples',
      () {
    final word = _word({'litkey_error_rate': 0});
    final restored = GermanWord.fromJson(word.toJson());
    for (final value in [word, restored]) {
      expect(value.litekeyErrorRate, 0);
      expect(value.spellingDifficultySource, 'litkey');
      expect(value.spellingDifficultyEvidence['status'], 'corpus-derived');
      expect(value.spellingDifficultyEvidence['source'], 'LiTKey');
      expect(value.spellingDifficultyEvidence['errorRate'], 0);
      expect(
          value.spellingDifficultyEvidence.containsKey('sampleSize'), isFalse);
      expect(value.spellingDifficultyEvidence['calibrated'], isFalse);
      expect(spellingDifficultyScore(value, isDE: true), 0);
    }
  });

  test('invalid corpus rates remain unknown rather than becoming scores', () {
    for (final rate in [-0.1, 1.1, double.nan, double.infinity, 'NaN', true]) {
      final word = _word({'litkey_error_rate': rate});
      expect(word.litekeyErrorRate, isNull, reason: '$rate');
      expect(word.spellingDifficultySource, 'unknown', reason: '$rate');
      expect(spellingDifficultyScore(word, isDE: true), 0.5);
    }
  });

  test(
      'explicit corpus evidence retains its actual counts and calibration flag',
      () {
    const evidence = {
      'status': 'corpus-derived',
      'source': 'LiTKey',
      'errorRate': 0.25,
      'sampleSize': 4,
      'errorTokens': 1,
      'aggregation': 'target',
      'calibrated': false,
    };
    final word = _word({
      'spellingDifficultySource': 'litkey',
      'spellingDifficultyEvidence': evidence,
    });
    expect(word.litekeyErrorRate, 0.25);
    expect(word.spellingDifficultyEvidence, evidence);
    expect(GermanWord.fromJson(word.toJson()).spellingDifficultyEvidence,
        evidence);
  });

  test('a copied legacy NRW label is kept as unverified provenance', () {
    final word = _word({
      'gradeLevelEstimate': 3,
      'gradeLevelEstimateSource': 'nrw',
    });
    expect(word.gradeLevelEstimate, 3);
    expect(word.gradeLevelEstimateSource, 'unknown');
    expect(word.gradeLevelEstimateEvidence['status'], 'unknown');
    expect(word.gradeLevelEstimateEvidence['legacySource'], 'nrw');
    final restored = GermanWord.fromJson(word.toJson());
    expect(
        restored.gradeLevelEstimateEvidence, word.gradeLevelEstimateEvidence);
  });

  test('curriculum copies retain explicit estimate and spelling evidence', () {
    const inherited = {
      'status': 'inherited',
      'sourceField': 'words.grade_level',
      'upstreamSource': 'declared-original-source',
      'upstreamEvidence': {'document': 'original-list'},
    };
    final original = _word({
      'litkey_error_rate': 0.6,
      'gradeLevelEstimate': 3,
      'gradeLevelEstimateSource': 'existing_grade_level',
      'gradeLevelEstimateEvidence': inherited,
    });
    final copy = original.withCurriculumSources(
        sources: ['BW3'], isGrundwortschatzBW: true, features: 0);
    expect(copy.gradeLevelEstimate, 3);
    expect(copy.gradeLevelEstimateSource, 'existing_grade_level');
    expect(copy.gradeLevelEstimateEvidence, inherited);
    expect(copy.spellingDifficultySource, original.spellingDifficultySource);
    expect(
        copy.spellingDifficultyEvidence, original.spellingDifficultyEvidence);
    expect(copy.litekeyErrorRate, 0.6);
  });
}
