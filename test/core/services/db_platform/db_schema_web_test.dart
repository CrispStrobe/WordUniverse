@TestOn('browser')
library;

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:WortUniversum/core/models/load_status.dart';
import 'package:WortUniversum/core/services/db_platform/db_platform_web.dart';
import 'package:WortUniversum/core/services/db_platform/db_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Flutter serves test/ at the URL root. These fixtures link to the app's
  // binaries so we exercise its real worker-backed SQLite/IndexedDB setup.
  final factory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(
      sqlite3WasmUri: Uri.parse('/fixtures/sqlite_web/sqlite3.wasm'),
      sharedWorkerUri: Uri.parse('/fixtures/sqlite_web/sqflite_sw.js'),
    ),
  );
  setUpAll(() {
    webDatabaseFactoryOverride = factory;
  });
  tearDownAll(() {
    webDatabaseFactoryOverride = null;
  });
  late String name;
  setUp(() {
    name = 'schema_${DateTime.now().microsecondsSinceEpoch}.db';
  });
  tearDown(() async {
    await factory.deleteDatabase(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
  for (final kind in ['legacy', 'missing columns', 'missing table', 'empty']) {
    test('web probe/open $kind', () async {
      final db = await factory.openDatabase(name);
      if (kind != 'missing table') {
        await db.execute(kind == 'missing columns'
            ? 'CREATE TABLE words (id INTEGER)'
            : 'CREATE TABLE words (id INTEGER, original_id TEXT, word TEXT, word_type TEXT, grade_level INTEGER)');
        if (kind != 'empty')
          await db.execute('INSERT INTO words (id) VALUES (1)');
      }
      expect(await db.getVersion(), 0);
      await db.close();
      expect(await isPlatformDatabaseInstalled(name), kind == 'legacy');
      if (kind == 'legacy') {
        final opened =
            await initPlatformDatabase(assetPath: 'unused', databaseName: name);
        expect(await isPlatformDatabaseInstalled(name), isTrue);
        expect(opened.isOpen, isTrue);
        await opened.close();
      } else {
        await expectLater(openValidatedDictionary(factory, name),
            throwsA(isA<DbSchemaException>()));
      }
    });
  }
  test('web incompatible payload never promoted or ready', () async {
    final db = await factory.openDatabase(name);
    await db.execute('CREATE TABLE words (id INTEGER)');
    await db.execute('INSERT INTO words VALUES (1)');
    await db.close();
    final gzip = Uint8List.fromList(
        GZipEncoder().encode(await factory.readDatabaseBytes(name)));
    await factory.deleteDatabase(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'flutter/assets', (_) async => ByteData.sublistView(gzip));
    final stages = <LoadStage>[];
    await expectLater(
        initPlatformDatabase(
            assetPath: 'fixture.gz',
            databaseName: name,
            onProgress: (_, s) => stages.add(s.stage)),
        throwsA(isA<DbSchemaException>()));
    expect(stages, isNot(contains(LoadStage.databaseReadyWords)));
    expect(await factory.databaseExists(name), isFalse);
    expect(await isPlatformDatabaseInstalled(name), isFalse);
  });
}
