@TestOn('vm')
library;

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';
import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:archive/archive.dart';
import 'package:WortUniversum/core/models/load_status.dart';
import 'package:WortUniversum/core/services/db_platform/db_schema.dart';
import 'package:WortUniversum/core/services/dictionary_database_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:WortUniversum/core/services/db_platform/db_platform_mobile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('schema_guard_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('nonempty words with missing core columns is not installed', () async {
    final db = await openDatabase('${directory.path}/pack.db');
    await db.execute('CREATE TABLE words (id INTEGER PRIMARY KEY)');
    await db.insert('words', {'id': 1});
    // The previous readiness criterion accepts this real SQLite fixture.
    expect(
        Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM words LIMIT 1',
        )),
        1);
    await db.close();

    expect(await isPlatformDatabaseInstalled('pack.db'), isFalse);
  });

  const core = {
    'id': 'INTEGER PRIMARY KEY',
    'original_id': 'TEXT',
    'word': 'TEXT',
    'word_type': 'TEXT',
    'grade_level': 'INTEGER',
  };
  Future<void> fixture(
      {String? omit, bool empty = false, bool table = true}) async {
    final db = await openDatabase('${directory.path}/pack.db');
    if (table) {
      await db.execute(
          'CREATE TABLE words (${core.entries.where((e) => e.key != omit).map((e) => '${e.key} ${e.value}').join(', ')})');
      if (!empty) await db.execute('INSERT INTO words DEFAULT VALUES');
    }
    expect(await db.getVersion(), 0);
    await db.close();
  }

  for (final missing in core.keys) {
    test('validator and probe reject missing $missing', () async {
      await fixture(omit: missing);
      expect(await isPlatformDatabaseInstalled('pack.db'), isFalse);
      await expectLater(
          openValidatedDictionary(databaseFactory, '${directory.path}/pack.db'),
          throwsA(isA<DbSchemaException>()));
    });
  }
  for (final table in [true, false]) {
    test('rejects ${table ? 'empty words' : 'missing words table'}', () async {
      await fixture(table: table, empty: true);
      expect(await isPlatformDatabaseInstalled('pack.db'), isFalse);
      await expectLater(
          openValidatedDictionary(databaseFactory, '${directory.path}/pack.db'),
          throwsA(isA<DbSchemaException>()));
    });
  }
  test('valid legacy user_version 0 without optional tables opens and probes',
      () async {
    await fixture();
    final db = await initPlatformDatabase(
        assetPath: 'unused', databaseName: 'pack.db');
    // A probe must not close the live game connection via sqflite singleInstance.
    expect(await isPlatformDatabaseInstalled('pack.db'), isTrue);
    expect(db.isOpen, isTrue);
    expect(await validateDictionarySchema(db), 1);
    await db.close();
  });

  test('artifact change must not treat unchanged schema-compatible cache as current', () async {
    await fixture();
    const old = LanguagePack(code: 'x', nativeName: 'X', databaseName: 'pack.db',
        licenseLabel: 'test', expectedDecompressedSha256: 'old');
    const next = LanguagePack(code: 'x', nativeName: 'X', databaseName: 'pack.db',
        licenseLabel: 'test', expectedDecompressedSha256: 'next');
    await File('${directory.path}/pack.db').rename('${directory.path}/${old.databaseName}');
    expect(await isPlatformDatabaseInstalled(old.databaseName), isTrue);
    expect(await isPlatformDatabaseInstalled(next.databaseName), isFalse);
  });

  Future<void> serveFixtureAsset() async {
    final bytes = await File('${directory.path}/pack.db').readAsBytes();
    final gzip = Uint8List.fromList(GZipEncoder().encode(bytes));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'flutter/assets', (_) async => ByteData.sublistView(gzip));
  }

  test('exact legacy artifact is adopted once offline and retained', () async {
    await fixture();
    final old = File('${directory.path}/pack.db');
    final digest = sha256.convert(await old.readAsBytes()).toString();
    final staging = File('${directory.path}/current.db.installing');
    await staging.writeAsBytes([1, 2, 3]);
    expect(await isPlatformDatabaseInstalled('current.db',
        legacyDatabaseNames: ['pack.db'], expectedDecompressedSha256: digest), isFalse);
    expect(await staging.readAsBytes(), [1, 2, 3]);
    expect(await File('${directory.path}/current.db').exists(), isFalse);
    final adopted = await initPlatformDatabase(assetPath: 'offline-unused', databaseName: 'current.db',
        legacyDatabaseNames: ['pack.db'], expectedDecompressedSha256: digest);
    await adopted.close();
    expect(await old.exists(), isTrue);
    await old.delete();
    expect(await isPlatformDatabaseInstalled('current.db'), isTrue);
    final db = await initPlatformDatabase(assetPath: 'offline-unused', databaseName: 'current.db');
    await db.close();
  });

  test('SQLite writes change legacy hash but not qualified readiness', () async {
    await fixture();
    final old = File('${directory.path}/pack.db');
    final digest = sha256.convert(await old.readAsBytes()).toString();
    final db = await openDatabase(old.path);
    await db.execute('CREATE INDEX local_index ON words(word)');
    await db.close();
    final modified = await old.readAsBytes();
    expect(sha256.convert(modified).toString(), isNot(digest));
    expect(await isPlatformDatabaseInstalled('current.db',
        legacyDatabaseNames: ['pack.db'], expectedDecompressedSha256: digest), isFalse);
    expect(await old.readAsBytes(), modified);
    await old.copy('${directory.path}/current.db');
    expect(await isPlatformDatabaseInstalled('current.db',
        expectedDecompressedSha256: digest), isTrue);
  });

  test('previous pack notice discovers legacy storage without adopting it', () async {
    await fixture();
    final pack = kLanguagePacks['de']!;
    await File('${directory.path}/pack.db').rename('${directory.path}/${pack.legacyDatabaseNames.first}');
    final vocabulary = VocabularyService();
    expect(await vocabulary.hasPreviousPack('de'), isTrue);
    expect(await vocabulary.isPackInstalled('de'), isFalse);
    expect(await File('${directory.path}/${pack.databaseName}').exists(), isFalse);
    vocabulary.dispose();
  });

  test('changed legacy revision retained through failed and valid replacement', () async {
    await fixture();
    final old = File('${directory.path}/pack.db');
    final bytes = await old.readAsBytes();
    expect(await isPlatformDatabaseInstalled('next.db',
        legacyDatabaseNames: ['pack.db'], expectedDecompressedSha256: 'different'), isFalse);
    await serveFixtureAsset();
    // Same-length, schema-compatible payload is not the registered revision.
    await expectLater(initPlatformDatabase(assetPath: 'fixture.gz', databaseName: 'next.db',
        expectedDecompressedSha256: 'different'), throwsA(isA<DbDownloadException>()));
    expect(await old.readAsBytes(), bytes);
    expect(await isPlatformDatabaseInstalled('pack.db'), isTrue);
    final db = await initPlatformDatabase(assetPath: 'fixture.gz', databaseName: 'next.db',
        expectedDecompressedSha256: sha256.convert(bytes).toString());
    await db.close();
    expect(await old.readAsBytes(), bytes);
    expect(await isPlatformDatabaseInstalled('next.db'), isTrue);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
  });

  for (final cached in [false, true]) {
    // Existing schema-validation cases below also cover staging rejection.
    test(
        'init rejects incompatible ${cached ? 'cache and replacement' : 'payload'} without ready or promotion',
        () async {
      await fixture(omit: 'word');
      await serveFixtureAsset();
      if (!cached) await File('${directory.path}/pack.db').delete();
      final stages = <LoadStage>[];
      final service = DictionaryDatabaseService();
      try {
        await expectLater(
            service.initialize(
              assetPath: 'fixture.gz',
              databaseName: 'pack.db',
              onProgress: (_, status) => stages.add(status.stage),
            ),
            throwsA(isA<DbSchemaException>()));
        expect(service.isReady, isFalse);
        expect(stages, isNot(contains(LoadStage.databaseReady)));
        expect(stages, isNot(contains(LoadStage.databaseReadyWords)));
        expect(await File('${directory.path}/pack.db').exists(), isFalse);
        expect(await isPlatformDatabaseInstalled('pack.db'), isFalse);
      } finally {
        await service.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null);
      }
    });
  }
}
