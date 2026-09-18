@TestOn('browser')
library;

// The feature index is computed with SQLite's JSON1 functions. On the web that
// is sqlite3.wasm, and if JSON1 were missing there the build would fail, the
// index would come back empty, and every game would find an empty word pool —
// silently, because an empty index is also how a pack with no enrichment
// legitimately reads. This runs the real build against the app's own wasm.
//
// Browser suites are not run by CI, and they need a working Chrome:
//   flutter test --platform chrome test/core/services/db_platform
// web_sqlite_capabilities_test.dart guards the same property from the VM, so
// a wasm rebuilt without JSON support fails the suite everywhere.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/db_platform/db_feature_index.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Flutter serves test/ at the URL root; these fixtures link to the app's own
  // binaries, so this is the runtime the deployed build uses.
  final factory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(
      sqlite3WasmUri: Uri.parse('/fixtures/sqlite_web/sqlite3.wasm'),
      sharedWorkerUri: Uri.parse('/fixtures/sqlite_web/sqflite_sw.js'),
    ),
  );

  late String name;
  setUp(() => name = 'features_${DateTime.now().microsecondsSinceEpoch}.db');
  tearDown(() => factory.deleteDatabase(name));

  Future<Database> packFixture() async {
    final db = await factory.openDatabase(name);
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
    Future<void> insert(String word, Map<String, Object?> enrichment,
            Map<String, Object?> metadata) =>
        db.insert('words', {
          'original_id': word,
          'word': word,
          'word_type': 'noun',
          'grade_level': 1,
          'enrichment_json': jsonEncode(enrichment),
          'metadata_json': jsonEncode(metadata),
        });

    await insert('Hund', {
      'definitions': ['ein Haustier'],
      'synonyms': ['Köter'],
      'enrichment_status': 'success',
    }, {
      'sources': ['BERLIN'],
      'commonMistakes': ['Hunt'],
    });
    await insert('Hunt', const {}, const {});
    await insert('accomodate', {
      'definitions': ['Misspelling of accommodate.'],
    }, const {});
    return db;
  }

  test('JSON1 is available in the app\'s sqlite3.wasm', () async {
    final db = await packFixture();
    addTearDown(db.close);

    final result = await db.rawQuery(
        "SELECT json_array_length('[1,2,3]') AS n, "
        "json_extract('{\"a\":\"b\"}', '\\\$.a') AS a");
    expect(result.first['n'], 3);
    expect(result.first['a'], 'b');
  });

  test('the index builds in the browser with the same answers as the VM',
      () async {
    final db = await packFixture();
    addTearDown(db.close);

    final index = await WordFeatureIndex.build(db);

    expect(index.length, 3, reason: 'a failed build would be empty here');
    expect(index.featuresOf(1).hasFeature(WordFeature.definitions), isTrue);
    expect(index.featuresOf(1).hasFeature(WordFeature.synonyms), isTrue);
    expect(index.featuresOf(1).hasFeature(WordFeature.learnerErrors), isTrue);
    expect(index.featuresOf(1).hasFeature(WordFeature.antonyms), isFalse);
    expect(index.sourcesOf(1), ['BERLIN'],
        reason: 'group_concat over json_each has to work here too');

    expect(index.featuresOf(2), 0);
    expect(index.featuresOf(2).hasFeature(WordFeature.knownMisspelling), isTrue,
        reason: '"Hunt" is listed as a common mistake for "Hund"');

    expect(index.isPresentable(3), isFalse,
        reason: 'defined as a misspelling');
    expect(index.isPresentable(1), isTrue);
  });

  test('the index survives a round trip through browser storage', () async {
    final db = await packFixture();
    addTearDown(db.close);
    final cache = MemoryDbPartialCache();

    final built = await loadWordFeatureIndex(db,
        cacheKey: 'pack.db', revision: 'rev-1', cache: cache);
    expect(built.length, 3);

    // Dropping the table proves the second load came from the cache.
    await db.execute('DROP TABLE words');
    final reused = await loadWordFeatureIndex(db,
        cacheKey: 'pack.db', revision: 'rev-1', cache: cache);
    expect(reused.length, 3);
    expect(reused.featuresOf(1), built.featuresOf(1));
    expect(reused.sourcesOf(1), ['BERLIN']);
  });
}
