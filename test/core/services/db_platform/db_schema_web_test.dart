@TestOn('browser')
library;
import 'package:crypto/crypto.dart';
import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';

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
  test('web revision change gates stale cache; exact legacy adopts offline', () async {
    final old = LanguagePack(code: 'x', nativeName: 'X', databaseName: name,
        licenseLabel: 'test', expectedDecompressedSha256: 'old');
    final next = LanguagePack(code: 'x', nativeName: 'X', databaseName: name,
        licenseLabel: 'test', expectedDecompressedSha256: 'next');
    final db = await factory.openDatabase(old.databaseName);
    await db.execute('CREATE TABLE words (id INTEGER, original_id TEXT, word TEXT, word_type TEXT, grade_level INTEGER)');
    await db.execute('INSERT INTO words (id) VALUES (1)');
    await db.close();
    final bytes = await factory.readDatabaseBytes(old.databaseName);
    try {
      expect(await isPlatformDatabaseInstalled(old.databaseName), isTrue);
      expect(await isPlatformDatabaseInstalled(next.databaseName,
          legacyDatabaseNames: [old.databaseName], expectedDecompressedSha256: 'next'), isFalse);
      final gzip = Uint8List.fromList(GZipEncoder().encode(bytes));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets', (_) async => ByteData.sublistView(gzip));
      await expectLater(initPlatformDatabase(assetPath: 'fixture.gz', databaseName: next.databaseName,
          expectedDecompressedSha256: 'next'), throwsA(isA<DbDownloadException>()));
      expect(await factory.readDatabaseBytes(old.databaseName), bytes);
      expect(await isPlatformDatabaseInstalled(next.databaseName), isFalse);
      expect(await isPlatformDatabaseInstalled(next.databaseName,
          legacyDatabaseNames: [old.databaseName], expectedDecompressedSha256: sha256.convert(bytes).toString()), isFalse);
      final adopted = await initPlatformDatabase(assetPath: 'offline-unused', databaseName: next.databaseName,
          legacyDatabaseNames: [old.databaseName], expectedDecompressedSha256: sha256.convert(bytes).toString());
      await adopted.close();
      expect(await factory.readDatabaseBytes(old.databaseName), bytes);
      await factory.deleteDatabase(old.databaseName);
      final opened = await initPlatformDatabase(assetPath: 'offline-unused', databaseName: next.databaseName);
      await opened.close();
      expect(await isPlatformDatabaseInstalled(next.databaseName), isTrue);
    } finally {
      await factory.deleteDatabase(old.databaseName);
      await factory.deleteDatabase(next.databaseName);
    }
  });

  test('web install writes the database once, staging no second copy', () async {
    // Each write ships a whole decompressed database to the worker and into
    // IndexedDB, so a staged copy doubles both the main-thread cost and the
    // peak browser storage the install needs.
    final db = await factory.openDatabase(name);
    await db.execute('CREATE TABLE words (id INTEGER, original_id TEXT, word TEXT, word_type TEXT, grade_level INTEGER)');
    await db.execute('INSERT INTO words (id) VALUES (1)');
    await db.close();
    final gzip = Uint8List.fromList(
        GZipEncoder().encode(await factory.readDatabaseBytes(name)));
    await factory.deleteDatabase(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'flutter/assets', (_) async => ByteData.sublistView(gzip));
    final counting = _CountingFactory(factory);
    webDatabaseFactoryOverride = counting;
    try {
      final opened =
          await initPlatformDatabase(assetPath: 'fixture.gz', databaseName: name);
      await opened.close();
      expect(counting.writes, [name]);
      expect(await factory.databaseExists('$name.installing'), isFalse);
      expect(await isPlatformDatabaseInstalled(name), isTrue);
    } finally {
      webDatabaseFactoryOverride = factory;
    }
  });

  test('web incompatible payload never promoted or ready', () async {
    // Schema validation is independent of artifact revision identity.
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

/// Records which database names are written, delegating everything else.
class _CountingFactory implements DatabaseFactory {
  _CountingFactory(this._inner);
  final DatabaseFactory _inner;
  final List<String> writes = [];

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) {
    writes.add(path);
    return _inner.writeDatabaseBytes(path, bytes);
  }

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) =>
      _inner.openDatabase(path, options: options);
  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      _inner.readDatabaseBytes(path);
  @override
  Future<bool> databaseExists(String path) => _inner.databaseExists(path);
  @override
  Future<void> deleteDatabase(String path) => _inner.deleteDatabase(path);
  @override
  Future<String> getDatabasesPath() => _inner.getDatabasesPath();
  @override
  Future<void> setDatabasesPath(String path) => _inner.setDatabasesPath(path);
}
