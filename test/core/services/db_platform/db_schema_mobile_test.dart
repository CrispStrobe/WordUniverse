@TestOn('vm')
library;

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:WortUniversum/core/models/load_status.dart';
import 'package:WortUniversum/core/services/db_platform/db_schema.dart';
import 'package:WortUniversum/core/services/dictionary_database_service.dart';

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

  Future<void> serveFixtureAsset() async {
    final bytes = await File('${directory.path}/pack.db').readAsBytes();
    final gzip = Uint8List.fromList(GZipEncoder().encode(bytes));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'flutter/assets', (_) async => ByteData.sublistView(gzip));
  }

  for (final cached in [false, true]) {
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
