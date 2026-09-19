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
// English runs from the repository's own asset; German is downloaded, so point
// WU_PACK_DE at a decompressed copy to cover it too.
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
import 'package:WortUniversum/core/services/dictionary_database_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';

void main() {
  final enabled = Platform.environment['WU_PACK'] == '1';
  // The German pack is a 27 MB download rather than a repository asset, so it
  // is covered only when a decompressed copy is pointed at.
  final germanPack = Platform.environment['WU_PACK_DE'];
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late VocabularyService vocabulary;
  late GameProvider settings;

  /// Puts [source] where the app keeps an installed pack, so initialization
  /// finds it there and the download/asset paths are not exercised.
  Future<void> install(String language, List<int> bytes) async {
    final pack = kLanguagePacks[language]!;
    await File('${directory.path}/${pack.databaseName}').writeAsBytes(bytes);
    vocabulary = VocabularyService();
    await vocabulary.initialize(learningLanguage: language);
    settings = GameProvider(
      progressService: ProgressService(),
      sriService: SriService(),
      cognitiveProfileService: CognitiveProfileService(),
      prefs: await SharedPreferences.getInstance(),
    );
  }

  setUp(() async {
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
  });

  tearDown(() async {
    if (!enabled) return;
    await DictionaryDatabaseService().close();
    await directory.delete(recursive: true);
  });

  Future<void> installEnglish() async {
    final gz = File('assets/grundwortschatz_en.db.gz');
    expect(gz.existsSync(), isTrue, reason: 'run from the repository root');
    await install('en', GZipDecoder().decodeBytes(await gz.readAsBytes()));
  }

  Future<void> installGerman() async =>
      install('de', await File(germanPack!).readAsBytes());

  /// The contract every pack has to meet, whatever language it teaches.
  void packContract(
    String label,
    Future<void> Function() installPack, {
    required String probeWord,
    required Map<WordFeature, String> pools,
    String? skipReason,
  }) {
    final skip = skipReason ?? (enabled ? null : 'set WU_PACK=1');

    group(label, () {
      test('the catalogue loads light and presentable', () async {
        await installPack();
        expect(vocabulary.wordCount, greaterThan(10000));
        final words = vocabulary.getAllWords(settings);
        expect(words.every((w) => !w.isHydrated), isTrue,
            reason: 'launch must not decode enrichment');
        expect(words.any((w) => w.sources.isNotEmpty), isTrue,
            reason: 'sources travel with the feature index');
        expect(words, hasLength(vocabulary.wordCount));
      }, skip: skip);

      test('an indexed lookup finds a shipped word', () async {
        await installPack();
        final word = vocabulary.findByWrittenForm(probeWord);
        expect(word, isNotNull, reason: '"$probeWord" should be in this pack');
        expect((await vocabulary.hydrateOne(word!)).apiEnrichment, isNotNull);
      }, skip: skip);

      test('what the index promises, hydration delivers', () async {
        await installPack();
        // The index is computed in SQL and hydration is computed in Dart, so
        // comparing them over the whole pack catches any row the Dart mapper
        // cannot read — which is how a word ends up a stub with no enrichment.
        final sample =
            await vocabulary.hydrate(vocabulary.getAllWords(settings));

        final broken = <String>[];
        for (final word in sample) {
          if (!word.isHydrated) {
            broken.add('${word.word}: never hydrated');
            continue;
          }
          if (word.has(WordFeature.definitions) &&
              (word.apiEnrichment?.definitions.isEmpty ?? true)) {
            broken.add('${word.word}: index says definitions, mapper found none');
          }
          if (word.has(WordFeature.synonyms) &&
              (word.apiEnrichment?.synonyms.isEmpty ?? true)) {
            broken.add('${word.word}: index says synonyms, mapper found none');
          }
          if (word.has(WordFeature.hyphenation) && word.hyphenation.isEmpty) {
            broken.add('${word.word}: index says hyphenation, mapper found none');
          }
        }
        expect(broken.take(10), isEmpty,
            reason: '${broken.length} of ${sample.length} words disagree');
      }, skip: skip);

      test('every pool a game opens with is populated', () async {
        await installPack();
        final empty = <String>[];
        for (final entry in pools.entries) {
          final pool = await vocabulary.takeWordsWithFeature(
            entry.key,
            settingsProvider: settings,
            gradeLevel: 1,
            limit: 40,
          );
          if (pool.isEmpty) {
            empty.add('${entry.key.name} (${entry.value})');
            continue;
          }
          expect(pool.every((w) => w.isHydrated), isTrue,
              reason: 'a pool is handed over decoded');
          expect(pool.every((w) => w.has(entry.key)), isTrue);
        }
        expect(empty, isEmpty, reason: 'these games would have no words');
      }, skip: skip);
    });
  }

  // Pools both packs carry.
  const shared = <WordFeature, String>{
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

  packContract('english pack (bundled)', installEnglish,
      probeWord: 'dog', pools: shared);

  packContract(
    'german pack (downloaded)',
    installGerman,
    probeWord: 'Hund',
    pools: {
      ...shared,
      // German-only games. Translation asks for the English of a German word,
      // so the English pack carries no data for it by design.
      WordFeature.translations: 'translation flash, reverse translation flash',
      WordFeature.expressions: 'expression flash',
      WordFeature.proverbs: 'proverb cloze',
    },
    skipReason: !enabled
        ? 'set WU_PACK=1'
        : germanPack == null
            ? 'set WU_PACK_DE=/path/to/decompressed/grundwortschatz.db'
            : null,
  );
}
