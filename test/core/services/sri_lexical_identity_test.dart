import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/sri_item_identity.dart';
import 'package:WortUniversum/core/services/sri_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 8);
  late SriService service;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = SriService(clock: () => now);
  });
  tearDown(() => service.dispose());

  String id(String word, String wordId, {String? context}) => service.getItemId(
        skillType: LanguageSkillType.vocabulary,
        baseWord: word,
        wordId: wordId,
        additionalInfo: context,
      );

  void record(String word, String wordId, bool correct, {String? context}) =>
      service.recordResponse(
        skillType: LanguageSkillType.vocabulary,
        baseWord: word,
        wordId: wordId,
        additionalInfo: context,
        wasCorrect: correct,
      );

  Future<void> restore(SriLanguageData old) async {
    SharedPreferences.setMockInitialValues({
      'sri_language_database': jsonEncode({old.itemId: old.toJson()}),
    });
    await service.loadSriData();
  }

  test('case variants and same-spelling senses retain independent histories',
      () async {
    record('Arm', 'noun_arm', true);
    record('arm', 'adjective_arm', false);
    record('sein', 'verb_sein', true);
    record('sein', 'possessive_sein', false);
    record('Arm', 'noun_arm', true);
    expect(service.totalTrackedItems, 4);
    expect(service.getItemData(id('Arm', 'noun_arm'))!.successCount, 2);
    expect(service.getItemData(id('arm', 'adjective_arm'))!.failureCount, 1);
    expect(service.getItemData(id('sein', 'verb_sein'))!.failureCount, 0);
    final possessive = id('sein', 'possessive_sein');
    service.recordReviewResponse(
      itemId: possessive,
      assessedSkill: LanguageSkillType.vocabulary,
      wasCorrect: true,
      metadata: {'wordId': 'possessive_sein'},
    );
    expect(service.getItemData(possessive)!.successCount, 1);
    expect(service.getItemData(id('sein', 'verb_sein'))!.successCount, 1);
    await service.saveSriData();
    final restored = SriService(clock: () => now);
    addTearDown(restored.dispose);
    await restored.loadSriData();
    expect(restored.totalTrackedItems, 4);
    expect(restored.getItemData(possessive)!.failureCount, 1);
    expect(restored.getItemData(id('Arm', 'noun_arm'))!.successCount, 2);
  });

  test(
      'identity follows the stable entry id and encodes all context characters',
      () {
    const wordId = 'de|word_ä/%';
    const context = 'er/sie/es_|present';
    final key = id('sein', wordId, context: context);
    expect(key, id('new visible spelling', wordId, context: context));
    final decoded = SriItemIdentity.fromId(key);
    expect(decoded.wordId, wordId);
    expect(decoded.additionalInfo, context);
    expect(decoded.skillType, LanguageSkillType.vocabulary);
    expect(baseWordFromSriId(key), isNull,
        reason: 'an opaque catalogue id must never be mistaken for a word');
    expect(decoded.canonicalId, key);
  });

  test('contexts for the same lexical word are independent for every skill',
      () {
    for (final skill in LanguageSkillType.values) {
      final first = service.getItemId(
          skillType: skill,
          baseWord: 'laufen',
          wordId: 'verb_laufen',
          additionalInfo: 'DAS Laufen');
      final second = service.getItemId(
          skillType: skill,
          baseWord: 'laufen',
          wordId: 'verb_laufen',
          additionalInfo: 'WIR laufen');
      expect(first, isNot(second), reason: skill.name);
      expect(SriItemIdentity.fromId(first).additionalInfo, 'DAS Laufen');
    }
    record('laufen', 'verb_laufen', true, context: 'DAS Laufen');
    record('laufen', 'verb_laufen', false, context: 'WIR laufen');
    expect(service.totalTrackedItems, 2);
  });

  test('ambiguous legacy history is preserved and never assigned by first use',
      () async {
    final old = SriLanguageData(
      itemId: 'VOCAB_arm',
      skillType: LanguageSkillType.vocabulary,
      nextReviewDate: now,
      successCount: 7,
      failureCount: 3,
    );
    await restore(old);
    record('arm', 'adjective_arm', true);
    record('Arm', 'noun_arm', false);
    expect(service.totalTrackedItems, 3);
    final unchanged = service.getItemData(old.itemId)!;
    expect(unchanged.successCount, 7);
    expect(unchanged.failureCount, 3);
    expect(unchanged.metadata, isEmpty);
    expect(
        service.getItemsForReview(markReturned: false), contains(old.itemId));
  });

  test('explicit legacy case and type evidence keeps the exact old stored key',
      () async {
    final old = SriLanguageData(
      itemId: 'MEAN_arm',
      skillType: LanguageSkillType.vocabulary,
      nextReviewDate: now,
      successCount: 7,
      metadata: {'baseWord': 'Arm', 'wordType': 'GermanWordType.substantiv'},
    );
    await restore(old);
    service.recordResponse(
      skillType: LanguageSkillType.vocabulary,
      baseWord: 'Arm',
      wordId: 'noun_arm',
      wasCorrect: true,
      metadata: {'wordType': 'substantiv'},
    );
    expect(service.totalTrackedItems, 1);
    expect(service.getItemData(id('Arm', 'noun_arm'))!.itemId, 'MEAN_arm');
    expect(service.getItemData(old.itemId)!.successCount, 8);
    record('arm', 'adjective_arm', false);
    expect(service.totalTrackedItems, 2);
    await service.saveSriData();
    final restored = SriService(clock: () => now);
    addTearDown(restored.dispose);
    await restored.loadSriData();
    expect(restored.getItemData(id('Arm', 'noun_arm'))!.itemId, 'MEAN_arm');
    expect(restored.getItemData(id('arm', 'adjective_arm'))!.failureCount, 1);
  });

  test('a resolver binding preserves history and rejects later sense changes',
      () async {
    final old = SriLanguageData(
      itemId: 'VOCAB_arm',
      skillType: LanguageSkillType.vocabulary,
      nextReviewDate: now,
      successCount: 7,
    );
    await restore(old);
    service.bindWordIdentity(
      itemId: old.itemId,
      wordId: 'noun_arm',
      baseWord: 'Arm',
      wordType: GermanWordType.substantiv,
    );
    record('Arm', 'noun_arm', true);
    expect(service.getItemData(old.itemId)!.successCount, 8);
    expect(service.totalTrackedItems, 1);
    expect(
        () => service.recordReviewResponse(
              itemId: old.itemId,
              assessedSkill: LanguageSkillType.vocabulary,
              wasCorrect: true,
              metadata: {'wordId': 'adjective_arm'},
            ),
        throwsArgumentError);
    expect(service.getItemData(old.itemId)!.successCount, 8);
  });

  test('legacy wordId text cannot overwrite a different stable entry',
      () async {
    final old = SriLanguageData(
      itemId: 'VOCAB_arm',
      skillType: LanguageSkillType.vocabulary,
      nextReviewDate: now,
      successCount: 7,
      metadata: {'wordId': 'arm', 'baseWord': 'arm'},
    );
    await restore(old);
    record('arm', 'adjective_arm', true);
    expect(service.totalTrackedItems, 2);
    expect(service.getItemData(old.itemId)!.successCount, 7);
    expect(service.getItemData(id('arm', 'adjective_arm'))!.successCount, 1);
  });
}
