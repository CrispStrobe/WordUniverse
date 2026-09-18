@TestOn('vm')
library;

// Runs the SHIPPED English pack through the real launch path, then asks for
// every word pool a game asks for.
//
// The unit suite uses fixtures, so it cannot see the failure that matters most
// after moving pools onto the feature index: a game that quietly finds zero
// words because the pack spells a JSON key differently than the index expects.
// This opens the real artifact and checks each pool is actually populated.
//
// Skipped unless WU_PACK=1, because it decompresses ~98 MB.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';

void main() {
  final enabled = Platform.environment['WU_PACK'] == '1';
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late VocabularyService vocabulary;
  late GameProvider settings;

  setUpAll(() async {
    if (!enabled) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});

    directory = await Directory.systemTemp.createTemp('shipped_pack_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );

    // Unpack the repository's own asset into the app's documents directory,
    // under the name the registry gives it, so initialization finds it there
    // and the bundled-asset path is not exercised.
    final pack = kLanguagePacks['en']!;
    final gz = File('assets/grundwortschatz_en.db.gz');
    expect(gz.existsSync(), isTrue, reason: 'run from the repository root');
    await File('${directory.path}/${pack.databaseName}').writeAsBytes(
      GZipDecoder().decodeBytes(await gz.readAsBytes()),
    );

    vocabulary = VocabularyService();
    await vocabulary.initialize(learningLanguage: 'en');
    settings = GameProvider(
      progressService: ProgressService(),
      sriService: SriService(),
      cognitiveProfileService: CognitiveProfileService(),
      prefs: await SharedPreferences.getInstance(),
    );
  });

  tearDownAll(() async {
    if (!enabled) return;
    await directory.delete(recursive: true);
  });

  test('the catalogue loads light and presentable', () async {
    expect(vocabulary.wordCount, greaterThan(10000));
    final words = vocabulary.getAllWords(settings);
    expect(words.every((w) => !w.isHydrated), isTrue,
        reason: 'launch must not decode enrichment');
    expect(words.any((w) => w.sources.isNotEmpty), isTrue,
        reason: 'sources travel with the feature index');
    expect(words, hasLength(vocabulary.wordCount));
  }, skip: enabled ? false : 'set WU_PACK=1');

  test('an indexed lookup finds a shipped word', () async {
    final word = vocabulary.findByWrittenForm('dog');
    expect(word, isNotNull);
    expect((await vocabulary.hydrateOne(word!)).apiEnrichment, isNotNull);
  }, skip: enabled ? false : 'set WU_PACK=1');

  // Each entry is a pool some game opens with. An empty one is a game with
  // nothing to play.
  const poolsEveryGameNeeds = <WordFeature, String>{
    WordFeature.definitions: 'definition quiz, word memory, SRI review',
    WordFeature.synonyms: 'synonym flash',
    WordFeature.antonyms: 'antonym flash',
    WordFeature.hyphenation: 'syllable count',
    WordFeature.learnerErrors: 'spelling spotter',
    WordFeature.gradeExamples: 'sentence completion, homophone drill',
    WordFeature.examples: 'cloze flash, capitalisation, compound builder',
    WordFeature.hypernyms: 'hypernym flash',
    WordFeature.inflections: 'conjugation drill, separable verbs',
    WordFeature.enrichmentSuccess: 'word sort, word type whirl',
  };

  poolsEveryGameNeeds.forEach((feature, games) {
    test('pool for ${feature.name} is populated ($games)', () async {
      final pool = await vocabulary.takeWordsWithFeature(
        feature,
        settingsProvider: settings,
        gradeLevel: 1,
        limit: 40,
      );
      expect(pool, isNotEmpty, reason: '$games would have no words');
      expect(pool.every((w) => w.isHydrated), isTrue,
          reason: 'a pool is handed over decoded');
      expect(pool.every((w) => w.has(feature)), isTrue);
    }, skip: enabled ? false : 'set WU_PACK=1');
  });
}
