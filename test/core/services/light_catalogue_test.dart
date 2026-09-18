@TestOn('vm')
library;

// The catalogue loads without decoding any enrichment, and the enrichment is
// filled in only for the words a round actually uses. See db_feature_index.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/dictionary_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('light_catalogue_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
  });

  tearDown(() async {
    await DictionaryDatabaseService().close();
    await directory.delete(recursive: true);
  });

  Future<DictionaryDatabaseService> openPack() async {
    final db = await databaseFactory.openDatabase('${directory.path}/pack.db');
    await db.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_id TEXT UNIQUE,
        word TEXT NOT NULL,
        lemma TEXT,
        article TEXT,
        genus TEXT,
        word_type TEXT,
        grade_level INTEGER,
        audio_path TEXT,
        frequency_json TEXT,
        enrichment_json TEXT,
        metadata_json TEXT
      )''');
    await db.insert('words', {
      'original_id': 'w-hund',
      'word': 'Hund',
      'lemma': 'Hund',
      'article': 'der',
      'word_type': 'noun',
      'grade_level': 1,
      'enrichment_json': jsonEncode({
        'definitions': ['ein Haustier'],
        'synonyms': ['Köter'],
      }),
      'metadata_json': jsonEncode({'sources': ['BERLIN']}),
    });
    await db.insert('words', {
      'original_id': 'w-baum',
      'word': 'Baum',
      'lemma': 'Baum',
      'word_type': 'noun',
      'grade_level': 2,
      'enrichment_json': jsonEncode({'definitions': ['eine Pflanze']}),
      'metadata_json': jsonEncode({}),
    });
    // Must never reach the catalogue: shipped as a known misspelling.
    await db.insert('words', {
      'original_id': 'w-hunt',
      'word': 'Hunt',
      'word_type': 'noun',
      'grade_level': 1,
      'enrichment_json': jsonEncode({'definitions': ['Misspelling of Hund.']}),
      'metadata_json': jsonEncode({}),
    });
    await db.close();

    final service = DictionaryDatabaseService();
    await service.initialize(
      assetPath: 'offline-unused',
      databaseName: 'pack.db',
    );
    return service;
  }

  test('the catalogue loads light, with features and sources but no enrichment',
      () async {
    final service = await openPack();
    final words = await service.getAllWords();

    expect(words.map((w) => w.word), ['Hund', 'Baum'],
        reason: 'the entry defined as a misspelling is not presentable');

    final hund = words.first;
    expect(hund.isHydrated, isFalse);
    expect(hund.article, 'der', reason: 'light columns are still loaded');
    expect(hund.sources, ['BERLIN'], reason: 'sources travel with the index');
    expect(hund.has(WordFeature.definitions), isTrue);
    expect(hund.has(WordFeature.synonyms), isTrue);
    expect(hund.has(WordFeature.antonyms), isFalse);
    expect(words[1].has(WordFeature.synonyms), isFalse);
  });

  test('hydration fills the enrichment and preserves order', () async {
    final service = await openPack();
    final words = await service.getAllWords();
    expect(words.first.apiEnrichment, isNull);

    final hydrated = await service.hydrate(words.reversed);

    expect(hydrated.map((w) => w.word), ['Baum', 'Hund'],
        reason: 'hydrate returns the words in the order it was given them');
    expect(hydrated.every((w) => w.isHydrated), isTrue);
    expect(hydrated.last.apiEnrichment!.definitions, ['ein Haustier']);
    expect(hydrated.last.apiEnrichment!.synonyms, ['Köter']);
    expect(hydrated.last.sources, ['BERLIN'],
        reason: 'the decoded row carries the same sources as the light one');
    expect(hydrated.last.has(WordFeature.definitions), isTrue,
        reason: 'feature bits survive hydration');
  });

  test('already-hydrated words pass through hydrate unchanged', () async {
    final service = await openPack();
    final once = await service.hydrate(await service.getAllWords());
    final twice = await service.hydrate(once);

    expect(twice.map((w) => w.word), once.map((w) => w.word));
    expect(twice.every((w) => w.isHydrated), isTrue);
  });
}
