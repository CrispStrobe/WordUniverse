@TestOn('vm')
library;

// Writes the feature index into a pack, so that no device has to derive it.
//
//     WU_INDEX_PACK=/path/to/pack.db flutter test test/audit/index_pack_test.dart
//
// tools/pack/index_pack.sh wraps this. It is a test only because the app's
// code needs the Flutter VM — `dart run` cannot compile the dependency graph.
//
// The index is what lets the catalogue load without decoding enrichment: a
// bitmask per row saying which fields that row has, plus its sources.
// Deriving it costs a couple of seconds over a hundred thousand JSON blobs,
// once per install and again whenever the bit layout changes — work every
// device repeats for an answer that is the same everywhere.
//
// It is derived here by the app's own code, not by a reimplementation, and
// the app verifies the format and the row count before trusting what it
// reads. A pack whose index is stale or malformed is derived at runtime as
// before.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/db_platform/db_feature_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('write the feature index into a pack', () async {
    final path = Platform.environment['WU_INDEX_PACK'];
    if (path == null || path.isEmpty) {
      markTestSkipped('set WU_INDEX_PACK=/path/to/pack.db');
      return;
    }
    expect(File(path).existsSync(), isTrue, reason: 'no pack at $path');

    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(path);
    addTearDown(db.close);

    await db.execute('DROP TABLE IF EXISTS ${WordFeatureIndex.shippedTable}');
    await db
        .execute('DROP TABLE IF EXISTS ${WordFeatureIndex.shippedMetaTable}');

    final started = DateTime.now();
    final index = await WordFeatureIndex.build(db);
    final derived = DateTime.now().difference(started);
    expect(index.isEmpty, isFalse, reason: 'nothing to write');

    await db.execute('CREATE TABLE ${WordFeatureIndex.shippedTable} ('
        'row_id INTEGER PRIMARY KEY, flags INTEGER NOT NULL, sources TEXT)');
    await db.execute('CREATE TABLE ${WordFeatureIndex.shippedMetaTable} ('
        'format INTEGER NOT NULL, rows INTEGER NOT NULL)');

    final rows = index.shippedRows;
    final batch = db.batch();
    for (final (rowId, flags, sources) in rows) {
      batch.insert(WordFeatureIndex.shippedTable, {
        'row_id': rowId,
        'flags': flags,
        'sources': sources.isEmpty ? null : sources,
      });
    }
    await batch.commit(noResult: true);
    await db.insert(WordFeatureIndex.shippedMetaTable,
        {'format': kWordFeatureIndexFormat, 'rows': rows.length});
    await db.execute('VACUUM');

    // What the app will do on first open, against what was just derived.
    final readBack = await WordFeatureIndex.readShipped(db);
    expect(readBack, isNotNull, reason: 'the app would not read this index');
    expect(readBack!.length, index.length);
    for (final (rowId, _, _) in rows) {
      expect(readBack.featuresOf(rowId), index.featuresOf(rowId));
      expect(readBack.sourcesOf(rowId), index.sourcesOf(rowId));
      expect(readBack.isPresentable(rowId), index.isPresentable(rowId));
    }

    // ignore: avoid_print
    print('indexed ${rows.length} rows into ${path.split('/').last} '
        '(format $kWordFeatureIndexFormat, derived in '
        '${derived.inMilliseconds} ms, now '
        '${(File(path).lengthSync() / 1048576).toStringAsFixed(1)} MB)');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
