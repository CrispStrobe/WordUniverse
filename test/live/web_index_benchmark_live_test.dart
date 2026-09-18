@TestOn('browser')
library;

// Measures, in a real browser against the real English pack, what the feature
// index costs to build and what a launch costs with and without it.
//
// Skips unless the pack is copied in, because it is a 19 MB artifact that is
// not committed, and it takes minutes:
//
//   mkdir -p test/fixtures/pack
//   cp assets/grundwortschatz_en.db.gz test/fixtures/pack/
//   flutter test --platform chrome test/live/web_index_benchmark_live_test.dart
//
// The fixtures under test/fixtures/sqlite_web/ are symlinks; on a filesystem
// that cannot store them (some network mounts) copy web/sqlite3.wasm and
// web/sqflite_sw.js in place of them first, or the wasm never instantiates and
// every browser test hangs until it times out.
//
// Numbers are in docs/catalogue-loading.md.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'package:WortUniversum/core/services/db_platform/db_feature_index.dart';
import 'package:WortUniversum/core/services/db_platform/db_platform_web.dart';

String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
String ms(int value) => '${value.toString().padLeft(6)} ms';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final factory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(
      sqlite3WasmUri: Uri.parse('/fixtures/sqlite_web/sqlite3.wasm'),
      sharedWorkerUri: Uri.parse('/fixtures/sqlite_web/sqflite_sw.js'),
    ),
  );

  test('english pack: index build and launch cost in the browser', () async {
    webDatabaseFactoryOverride = factory;
    addTearDown(() => webDatabaseFactoryOverride = null);
    final name = 'bench_${DateTime.now().microsecondsSinceEpoch}.db';
    addTearDown(() => factory.deleteDatabase(name));

    // The app reads the pack through rootBundle; serve the real artifact.
    final gz =
        await http.get(Uri.parse('/fixtures/pack/grundwortschatz_en.db.gz'));
    if (gz.statusCode != 200) {
      markTestSkipped('copy assets/grundwortschatz_en.db.gz to '
          'test/fixtures/pack/ to run this benchmark');
      return;
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'flutter/assets', (_) async => ByteData.sublistView(gz.bodyBytes));
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null));

    final install = Stopwatch()..start();
    final db = await initPlatformDatabase(
        assetPath: 'assets/grundwortschatz_en.db.gz', databaseName: name);
    install.stop();
    addTearDown(db.close);

    final rows = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM words'))!;
    final jsonBytes = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT SUM(length(coalesce(enrichment_json, '')) +
                 length(coalesce(metadata_json, '')) +
                 length(coalesce(frequency_json, ''))) FROM words
    '''))!;

    // Old launch: every column, every blob decoded.
    final old = Stopwatch()..start();
    final all = await db.query('words');
    final queried = old.elapsedMilliseconds;
    var decoded = 0;
    for (final row in all) {
      for (final column in [
        'frequency_json',
        'enrichment_json',
        'metadata_json'
      ]) {
        final raw = row[column] as String?;
        if (raw == null || raw.isEmpty) continue;
        jsonDecode(raw);
        decoded++;
      }
    }
    old.stop();

    // New launch: light columns, no JSON.
    final light = Stopwatch()..start();
    await db.rawQuery('SELECT id, original_id, word, lemma, article, genus, '
        'word_type, grade_level, audio_path FROM words');
    light.stop();

    // The index, cold — what a first launch after install pays, once.
    final build = Stopwatch()..start();
    final index = await WordFeatureIndex.build(db);
    build.stop();
    expect(index.length, rows);

    final encode = Stopwatch()..start();
    final record = index.encode('bench');
    encode.stop();

    final decode = Stopwatch()..start();
    final restored = WordFeatureIndex.decode(record, 'bench');
    decode.stop();
    expect(restored!.length, rows);

    // ignore: avoid_print
    print('''

== English pack in Chromium ==========================================
  $rows words, ${mb(jsonBytes)} of enrichment/metadata JSON
  install (fetch + gunzip + IndexedDB write)  ${ms(install.elapsedMilliseconds)}

  OLD launch  SELECT * + jsonDecode           ${ms(old.elapsedMilliseconds)}
    query                                     ${ms(queried)}
    decode ($decoded blobs)                   ${ms(old.elapsedMilliseconds - queried)}

  NEW launch  light columns, no JSON          ${ms(light.elapsedMilliseconds)}
    index build (once per pack revision)      ${ms(build.elapsedMilliseconds)}
    index encode (${mb(record.length)} cached)${ms(encode.elapsedMilliseconds)}
    index decode (every later launch)         ${ms(decode.elapsedMilliseconds)}

  launch speedup  ${(old.elapsedMilliseconds / light.elapsedMilliseconds).toStringAsFixed(0)}x
======================================================================
''');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
