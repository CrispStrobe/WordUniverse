@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_quality.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/bw_vocabulary_overlay.dart';
import 'package:WortUniversum/core/services/dictionary_database_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/features/games/services/sri_review_service.dart';
import 'package:WortUniversum/generated/l10n.dart';

import '../audit/challenge_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuditPack pack;
  final skip = germanPackPath == null
      ? 'set WU_PACK_DE to the verified German app pack'
      : null;
  setUpAll(() async {
    if (skip == null) pack = await openAuditPack('de');
  });
  tearDownAll(() async {
    if (skip == null) await pack.dispose();
  });

  test('BW preset covers every exact source spelling and only its proper band',
      () async {
    await pack.settings.applyBwVocabularyPreset();
    final membership =
        jsonDecode(File(BwVocabularyOverlay.membershipAsset).readAsStringSync())
            as Map;
    for (final band in ['BW1', 'BW3']) {
      pack.settings.setTaskIncludedSources({band});
      final expected = (membership['memberships'] as List)
          .cast<Map>()
          .where((entry) => (entry['sourceBands'] as List).contains(band))
          .map((entry) => entry['word'] as String)
          .toSet();
      final words = pack.vocabulary.getAllWords(pack.settings);
      expect(words.map((word) => word.word).toSet(), expected,
          reason:
              '$band must not merge case variants or retain inherited wrong tags');
      expect(words.every((word) => word.isGrundwortschatzBW), isTrue);
      expect(words.every((word) => !word.isHydrated), isTrue);
      final sein = words.where((word) => word.word == 'sein').single;
      expect(sein.wordType,
          band == 'BW1' ? GermanWordType.verb : GermanWordType.pronomen);
    }
  }, skip: skip);

  test('feature candidates and hydration include corrected ordinary nouns',
      () async {
    await pack.settings.applyBwVocabularyPreset();
    final selected = await pack.vocabulary.takeWordsWithFeature(
      WordFeature.definitions,
      settingsProvider: pack.settings,
      limit: 2000,
      where: (word) => !word.isProperNoun && !namesSomething(word),
      random: Random(1),
    );
    for (final written in [
      'August',
      'Gabel',
      'Herr',
      'Luchs',
      'Mandarine',
      'E-Mail',
      'vergesslich',
      'Zeh',
      'Zylinder'
    ]) {
      final word = selected.singleWhere((word) => word.word == written);
      expect(word.isHydrated, isTrue);
      expect(word.isHeadword, isTrue);
      expect(word.has(WordFeature.definitions), isTrue);
      expect(word.learnerDefinitions, isNotEmpty);
      expect(namesSomething(word), isFalse);
    }
    // August: the reviewed pack of 2026-11-10 corrected Gabel at the source,
    // but still types this row as a given name.
    final untouched =
        await DictionaryDatabaseService().getWordById('word_00692');
    expect(untouched!.isProperNoun, isTrue,
        reason: 'the downloaded database retains its original bytes and rows');
  }, skip: skip);

  test('exact lookup, async search and old review resolution preserve identity',
      () async {
    for (final pair in [
      ('Arm', 'arm'),
      ('Paar', 'paar'),
      ('Weg', 'weg'),
      ('Sie', 'sie')
    ]) {
      final upper = pack.vocabulary.findByWrittenForm(pair.$1)!;
      final lower = pack.vocabulary.findByWrittenForm(pair.$2)!;
      expect(upper.word, pair.$1);
      expect(lower.word, pair.$2);
      expect(upper.id, isNot(lower.id));
    }
    final email = await pack.vocabulary.searchWordsAsync('E-Mail');
    expect(
        email.any((word) => word.word == 'E-Mail' && word.isHydrated), isTrue);
    final old = SriLanguageData(
      itemId: 'SPELL_arm',
      skillType: LanguageSkillType.spelling,
      nextReviewDate: DateTime.utc(2020),
    );
    expect(pack.vocabulary.findByReviewItem(old), isNull,
        reason:
            'a case-folded old key alone cannot identify which sense was practised');
    old.metadata['wordType'] = 'GermanWordType.substantiv';
    expect(pack.vocabulary.findByReviewItem(old)!.word, 'Arm');
    old.metadata['wordId'] = 'bw_lexical_v1_arm_adj';
    expect(pack.vocabulary.findByReviewItem(old)!.word, 'arm');
    final ambiguousSense = SriLanguageData(
      itemId: 'VOCAB_sein',
      skillType: LanguageSkillType.vocabulary,
      nextReviewDate: DateTime.utc(2020),
      metadata: {'baseWord': 'sein'},
    );
    expect(pack.vocabulary.findByReviewItem(ambiguousSense), isNull,
        reason: 'exact spelling alone does not distinguish the two senses');
    ambiguousSense.metadata['wordType'] = 'pronomen';
    expect(pack.vocabulary.findByReviewItem(ambiguousSense)!.id,
        'bw_lexical_v1_sein_possessive');
    final missingEntry = SriLanguageData(
      itemId: 'SPELL_@2|entry-from-another-pack|',
      skillType: LanguageSkillType.spelling,
      nextReviewDate: DateTime.utc(2020),
      metadata: {'baseWord': 'Arm'},
    );
    expect(pack.vocabulary.findByReviewItem(missingEntry), isNull,
        reason:
            'a missing stable id cannot become another entry with that word');
  }, skip: skip);

  test('actual case and same-spelling senses record and review independently',
      () async {
    await pack.settings.applyBwVocabularyPreset();
    var now = DateTime.utc(2026, 11, 8);
    final sri = SriService(clock: () => now);
    addTearDown(sri.dispose);
    final contexts = [
      ('word_00527', 'Ich hebe meinen ', 'Arm', '.', true),
      ('bw_lexical_v1_arm_adj', 'Die Familie ist ', 'arm', '.', false),
      ('word_08011', 'Wir wollen freundlich ', 'sein', '.', false),
      ('bw_lexical_v1_sein_possessive', 'Das ist ', 'sein', ' Ball.', false),
    ];
    for (final entry in contexts) {
      final word = pack.vocabulary.getWordById(entry.$1)!;
      sri.recordResponse(
        skillType: LanguageSkillType.capitalization,
        baseWord: word.word,
        wordId: word.id,
        additionalInfo: '${entry.$2}|${entry.$4}',
        wasCorrect: false,
        metadata: {
          'wordType': word.wordType.name,
          'contextBefore': entry.$2,
          'contextTarget': entry.$3,
          'contextAfter': entry.$4,
          'expectedCapitalized': entry.$5,
        },
      );
    }
    now = now.add(const Duration(days: 2));
    final due = sri.getItemsForReview(markReturned: false);
    expect(due.toSet(), hasLength(4));
    final challenges = await buildDueReviewChallenges(
      vocabulary: pack.vocabulary,
      sri: sri,
      settings: pack.settings,
      strings: lookupS(const Locale('de')),
      rng: Random(1),
    );
    expect(challenges, hasLength(4));
    expect(challenges.map((challenge) => challenge.word.id).toSet(),
        contexts.map((entry) => entry.$1).toSet());
    expect(sri.getItemsForReview(markReturned: false), due,
        reason: 'preparing a round does not consume any due card');
    for (final challenge in challenges) {
      final entry =
          contexts.singleWhere((entry) => entry.$1 == challenge.word.id);
      expect(challenge.prompt, contains('${entry.$2}___${entry.$4}'));
      expect(challenge.options[challenge.correctIndex], entry.$3);
      sri.recordReviewResponse(
        itemId: challenge.sriData.itemId,
        assessedSkill: challenge.assessedSkill,
        wasCorrect: challenge.word.id == 'word_00527',
        metadata: {'wordId': challenge.word.id},
      );
    }
    expect(sri.totalTrackedItems, 4);
    final histories = due.map(sri.getItemData).toList();
    expect(
        histories
            .singleWhere((data) => data!.identity.wordId == 'word_00527')!
            .successCount,
        1);
    for (final data
        in histories.where((data) => data!.identity.wordId != 'word_00527')) {
      expect(data!.successCount, 0);
      expect(data.failureCount, 2);
    }
  }, skip: skip);
}
