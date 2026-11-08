import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/sri_item_identity.dart';
import 'package:WortUniversum/core/services/sri_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late SriService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 11, 8);
    service = SriService(clock: () => now);
  });

  Future<void> restore(Map<String, dynamic> records) async {
    SharedPreferences.setMockInitialValues({
      'sri_language_database': jsonEncode(records),
    });
    await service.loadSriData();
  }

  SriLanguageData tracked({
    String id = 'SPELL_hund',
    LanguageSkillType skill = LanguageSkillType.spelling,
    int successes = 12,
    int failures = 0,
    int repetitions = 10,
    double easiness = 4,
    Map<String, dynamic>? metadata,
  }) =>
      SriLanguageData(
        itemId: id,
        skillType: skill,
        successCount: successes,
        failureCount: failures,
        repetitions: repetitions,
        easinessFactor: easiness,
        nextReviewDate: now,
        metadata: metadata,
      );

  test(
    'every emitted skill prefix resolves, including contextual suffixes',
    () {
      for (final skill in LanguageSkillType.values) {
        final id = service.getItemId(skillType: skill, baseWord: 'Hund');
        final identity = SriItemIdentity.fromId(id);
        expect(identity.skillType, skill);
        expect(identity.baseWord.toLowerCase(), 'hund');
      }
      expect(baseWordFromSriId('TYPE_laufen'), 'laufen');
      expect(baseWordFromSriId('MEAN_Hund'), 'Hund');
      expect(baseWordFromSriId('GRAM_Hund'), 'Hund');
      expect(baseWordFromSriId('CONJUG_laufen_er/sie/es'), 'laufen');
      expect(
        SriItemIdentity.fromId('CONJUG_laufen_er/sie/es').additionalInfo,
        'er/sie/es',
      );
      expect(baseWordFromSriId('CASE_hund_dativ'), 'hund');
      expect(baseWordFromSriId(''), isNull);
      final contextual = SriItemIdentity.fromId(
        'SENTENCE_context-7',
        metadata: {'baseWord': 'Hund', 'additionalInfo': 'context-7'},
      );
      expect(contextual.baseWord, 'Hund');
      expect(contextual.canonicalId, 'SENTENCE_context-7');
    },
  );

  test(
    'mastered cards remain due for maintenance across all queue counts',
    () async {
      final card = tracked(failures: 20);
      await restore({card.itemId: card.toJson()});
      expect(
        service.isItemMastered(card.itemId),
        isTrue,
        reason: 'past mistakes cannot permanently block recovered mastery',
      );
      expect(service.getBoxFor(service.getItemData(card.itemId)!), 5);
      expect(service.getAvailableReviewCount(), 1);
      expect(
        service.getAvailableReviewsBySkill()[LanguageSkillType.spelling],
        1,
      );
      expect(service.getItemsForReview(), [card.itemId]);
      expect(service.getItemsForReview(), isEmpty);
      service.resetSession();
      expect(service.getItemsForReview(), [card.itemId]);
    },
  );

  test('inspecting candidates does not consume unplayed reviews', () async {
    final card = tracked();
    await restore({card.itemId: card.toJson()});
    expect(service.getItemsForReview(markReturned: false), [card.itemId]);
    expect(service.getAvailableReviewCount(), 1);
    service.markItemsReturned([card.itemId]);
    expect(service.getAvailableReviewCount(), 0);
  });

  test('a new mistake resets mastery and schedules relearning', () async {
    final card = tracked(failures: 9);
    await restore({card.itemId: card.toJson()});
    service.recordReviewResponse(
      itemId: card.itemId,
      assessedSkill: LanguageSkillType.spelling,
      wasCorrect: false,
    );
    final result = service.getItemData(card.itemId)!;
    expect(result.successCount, 12);
    expect(result.failureCount, 10);
    expect(result.repetitions, 0);
    expect(service.isItemMastered(card.itemId), isFalse);
    expect(service.getBoxFor(result), 1);
    expect(result.nextReviewDate, now.add(const Duration(days: 1)));
    expect(service.getAvailableReviewCount(), 0);
    now = now.add(const Duration(days: 1));
    expect(service.getItemsForReview(), [card.itemId]);
  });

  test(
    'assisted success records practice without advancing independent mastery',
    () {
      for (var i = 0; i < 12; i++) {
        service.recordResponse(
          skillType: LanguageSkillType.spelling,
          baseWord: 'Hund',
          wasCorrect: true,
          wasAssisted: true,
        );
      }
      final card = service.getItemData('SPELL_hund')!;
      expect(card.successCount, 12);
      expect(card.assistedSuccessCount, 12);
      expect(card.repetitions, 0);
      expect(card.easinessFactor, 2.5);
      expect(service.isItemMastered(card.itemId), isFalse);
      expect(card.nextReviewDate, now.add(const Duration(days: 1)));
    },
  );

  test(
    'legacy prefixes and display names keep their history and stored ids',
    () async {
      final oldType = tracked(
        id: 'TYPE_hund',
        skill: LanguageSkillType.wordType,
        failures: 4,
      );
      final oldSpelling = tracked(id: 'SPELL_der hund', failures: 5);
      await restore({
        oldType.itemId: oldType.toJson(),
        oldSpelling.itemId: oldSpelling.toJson(),
      });
      service.recordResponse(
        skillType: LanguageSkillType.wordType,
        baseWord: 'Hund',
        wasCorrect: true,
      );
      service.recordResponse(
        skillType: LanguageSkillType.spelling,
        baseWord: 'Hund',
        legacyBaseWords: ['der Hund'],
        wasCorrect: true,
      );
      expect(service.totalTrackedItems, 2);
      expect(service.getItemData('WORDTYPE_hund')!.itemId, 'TYPE_hund');
      expect(service.getItemData('SPELL_hund')!.itemId, 'SPELL_der hund');
      expect(service.getItemData('SPELL_hund')!.identity.baseWord, 'Hund');
      expect(service.getItemData('SPELL_hund')!.failureCount, 5);
      await service.saveSriData();
      final restored = SriService(clock: () => now);
      await restored.loadSriData();
      expect(restored.totalTrackedItems, 2);
      expect(restored.getItemData('WORDTYPE_hund')!.successCount, 13);
      expect(restored.getItemData('SPELL_hund')!.failureCount, 5);
    },
  );

  test(
    'review records exact contextual item and rejects a different skill',
    () async {
      final card = tracked(
        id: 'CONJUG_laufen_du',
        skill: LanguageSkillType.verbConjugation,
      );
      await restore({card.itemId: card.toJson()});
      expect(
        () => service.recordReviewResponse(
          itemId: card.itemId,
          assessedSkill: LanguageSkillType.vocabulary,
          wasCorrect: true,
        ),
        throwsArgumentError,
      );
      service.recordReviewResponse(
        itemId: card.itemId,
        assessedSkill: LanguageSkillType.verbConjugation,
        wasCorrect: true,
      );
      expect(service.totalTrackedItems, 1);
      expect(service.getItemData(card.itemId)!.successCount, 13);
      expect(service.getItemData('CONJUG_laufen'), isNull);
    },
  );

  test(
    'manual box moves preserve lifetime counts and use consistent mastery',
    () async {
      final card = tracked(
        successes: 2,
        failures: 8,
        repetitions: 0,
        easiness: 1.3,
      );
      await restore({card.itemId: card.toJson()});
      for (var box = 1; box <= 5; box++) {
        await service.moveItemToBox(card.itemId, box);
        final result = service.getItemData(card.itemId)!;
        expect(result.successCount, 2);
        expect(result.failureCount, 8);
        expect(service.getBoxFor(result), box);
        expect(service.isItemMastered(result.itemId), box == 5);
      }
      service.recordReviewResponse(
        itemId: card.itemId,
        assessedSkill: LanguageSkillType.spelling,
        wasCorrect: false,
      );
      expect(service.getItemData(card.itemId)!.metadata['manualBox'], isNull);
      expect(service.getBoxFor(service.getItemData(card.itemId)!), 1);
      expect(service.getItemData(card.itemId)!.failureCount, 9);
    },
  );

  test('one unreadable saved record cannot discard the others', () async {
    final good = tracked();
    const future = {'skillType': 999, 'next': 'not-a-date', 'extra': 17};
    await restore({good.itemId: good.toJson(), 'FUTURE_item': future});
    expect(service.totalTrackedItems, 1);
    service.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: 'Hund',
      wasCorrect: true,
    );
    await service.saveSriData();
    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(prefs.getString('sri_language_database')!);
    expect(persisted['FUTURE_item'], future);
    expect(persisted[good.itemId]['s'], 13);
  });

  test('an unreadable database is retained before fresh practice saves',
      () async {
    const damaged = '{"SPELL_hund":';
    SharedPreferences.setMockInitialValues({
      'sri_language_database': damaged,
    });
    await service.loadSriData();
    service.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: 'Hund',
      wasCorrect: true,
    );
    await service.saveSriData();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sri_language_database_recovery'), damaged);
    final persisted = jsonDecode(prefs.getString('sri_language_database')!);
    expect(persisted['SPELL_hund']['s'], 1);
    await service.clearAllData();
    expect(prefs.containsKey('sri_language_database_recovery'), isFalse);
  });

  test(
    'recent items use actual review time, not a future scheduled date',
    () async {
      final old = tracked();
      old.lastReviewedAt = now.subtract(const Duration(days: 20));
      old.nextReviewDate = now.add(const Duration(days: 10));
      await restore({old.itemId: old.toJson()});
      expect(service.getRecentlyLearnedItems(), isEmpty);
      service.recordResponse(
        skillType: LanguageSkillType.spelling,
        baseWord: 'Hund',
        wasCorrect: true,
      );
      expect(service.getRecentlyLearnedItems(), [old.itemId]);
    },
  );
}
