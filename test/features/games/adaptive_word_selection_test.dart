import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/services/adaptive_word_selection.dart';

import '../../game_localization_fixtures.dart';
import 'word_fixture.dart';

class _Vocabulary extends GermanVocabularyFixture {
  _Vocabulary(super.words);
  LanguageSkillType? requestedSkill;

  @override
  GermanWord? findByWrittenForm(String form) => words
      .where((word) => word.word.toLowerCase() == form.trim().toLowerCase())
      .firstOrNull;

  @override
  List<GermanWord> getNewWords({
    required SriService sriService,
    required GameProvider settingsProvider,
    required GradeLevel grade,
    int limit = 5,
    LanguageSkillType skillType = LanguageSkillType.spelling,
    Random? rng,
  }) {
    requestedSkill = skillType;
    return words.take(limit).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 8);

  Future<(SriService, GameProvider)> tracked(
      List<SriLanguageData> cards) async {
    SharedPreferences.setMockInitialValues({
      'sri_language_database': jsonEncode({
        for (final card in cards) card.itemId: card.toJson(),
      }),
    });
    final sri = SriService(clock: () => now);
    await sri.loadSriData();
    final cognitive = CognitiveProfileService();
    final settings = GameProvider(
      progressService: ProgressService(),
      sriService: sri,
      cognitiveProfileService: cognitive,
      prefs: await SharedPreferences.getInstance(),
    );
    addTearDown(sri.dispose);
    addTearDown(cognitive.dispose);
    addTearDown(settings.dispose);
    return (sri, settings);
  }

  SriLanguageData card(String id, LanguageSkillType skill, int overdueDays) =>
      SriLanguageData(
        itemId: id,
        skillType: skill,
        nextReviewDate: now.subtract(Duration(days: overdueDays)),
        metadata: {'gradeLevel': 3},
      );

  test('only playable words at this grade consume this skill review queue',
      () async {
    final vocabulary = _Vocabulary([
      testWord('Hund'),
      testWord('Haus'),
      testWord('Auto', grade: 5),
      testWord('Fernsehapparat'),
    ]);
    addTearDown(vocabulary.dispose);
    final (sri, settings) = await tracked([
      card('WORDTYPE_hund', LanguageSkillType.wordType, 5),
      card('SPELL_fernsehapparat', LanguageSkillType.spelling, 4),
      card('SPELL_auto', LanguageSkillType.spelling, 3),
      card('SPELL_der haus', LanguageSkillType.spelling, 2),
    ]);
    final selected = selectAdaptiveWords(
      vocabulary: vocabulary,
      sri: sri,
      settings: settings,
      grade: GradeLevel.grade3,
      count: 1,
      reviewShare: 1,
      reviewQueueLimit: 10,
      isPlayable: (word) => word.word.length <= 6,
    );
    expect(selected.map((word) => word.word), ['Haus']);
    expect(vocabulary.requestedSkill, LanguageSkillType.spelling);
    expect(sri.getItemsForReview(markReturned: false),
        ['WORDTYPE_hund', 'SPELL_fernsehapparat', 'SPELL_auto']);
  });

  test('legacy word-class id is reviewed and unseen selection uses that skill',
      () async {
    final vocabulary = _Vocabulary([testWord('Hund'), testWord('Haus')]);
    addTearDown(vocabulary.dispose);
    final (sri, settings) = await tracked([
      card('TYPE_hund', LanguageSkillType.wordType, 1),
      card('SPELL_haus', LanguageSkillType.spelling, 2),
    ]);
    final selected = selectAdaptiveWords(
      vocabulary: vocabulary,
      sri: sri,
      settings: settings,
      grade: GradeLevel.grade3,
      count: 1,
      reviewShare: 1,
      skillFilter: LanguageSkillType.wordType,
      isPlayable: (_) => true,
    );
    expect(selected.single.word, 'Hund');
    expect(vocabulary.requestedSkill, LanguageSkillType.wordType);
    expect(sri.getItemsForReview(markReturned: false), ['SPELL_haus']);
  });
}
