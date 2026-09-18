// Measures what a launch costs on a real pack: the old "decode everything"
// catalogue load against the light load the app does now.
//
//   dart run tools/bench/catalogue_load_benchmark.dart <pack.db>
//
// The pack is opened read-only and never written to.
import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: catalogue_load_benchmark.dart <pack.db>');
    exit(64);
  }
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(args.first,
      options: OpenDatabaseOptions(readOnly: true));

  final rows = (await db.rawQuery('SELECT COUNT(*) AS n FROM words'))
      .first['n'] as int;
  final jsonBytes = (await db.rawQuery('''
    SELECT SUM(length(coalesce(enrichment_json, '')) +
               length(coalesce(metadata_json, '')) +
               length(coalesce(frequency_json, ''))) AS n FROM words
  ''')).first['n'] as int;

  print('pack: ${args.first}');
  print('  $rows words, ${_mb(jsonBytes)} of enrichment/metadata JSON\n');

  // --- Old launch: every column, every blob decoded. ---
  var watch = Stopwatch()..start();
  final all = await db.query('words');
  final queried = watch.elapsedMilliseconds;
  var decoded = 0;
  for (final row in all) {
    for (final column in ['frequency_json', 'enrichment_json', 'metadata_json']) {
      final raw = row[column] as String?;
      if (raw == null || raw.isEmpty) continue;
      jsonDecode(raw);
      decoded++;
    }
  }
  final oldTotal = watch.elapsedMilliseconds;
  print('old: SELECT * + jsonDecode');
  print('  query   ${queried.toString().padLeft(6)} ms');
  print('  decode  ${(oldTotal - queried).toString().padLeft(6)} ms  ($decoded blobs)');
  print('  total   ${oldTotal.toString().padLeft(6)} ms\n');

  // --- New launch: light columns only, no JSON at all. ---
  watch = Stopwatch()..start();
  await db.rawQuery('SELECT id, original_id, word, lemma, article, genus, '
      'word_type, grade_level, audio_path FROM words');
  final lightMs = watch.elapsedMilliseconds;

  // Built once per pack revision, then cached; not part of later launches.
  watch = Stopwatch()..start();
  await db.rawQuery('''
    SELECT id,
           CASE WHEN json_array_length(enrichment_json, '\$.definitions') > 0
                THEN 1 ELSE 0 END AS has_definitions,
           (SELECT group_concat(e.value, ',')
              FROM json_each(words.metadata_json, '\$.sources') AS e) AS sources
      FROM words
  ''');
  final indexMs = watch.elapsedMilliseconds;

  // What a round actually decodes.
  watch = Stopwatch()..start();
  final pool = await db.rawQuery('SELECT * FROM words LIMIT 200');
  for (final row in pool) {
    for (final column in ['enrichment_json', 'metadata_json']) {
      final raw = row[column] as String?;
      if (raw != null && raw.isNotEmpty) jsonDecode(raw);
    }
  }
  final hydrateMs = watch.elapsedMilliseconds;

  print('new: light columns + feature index');
  print('  launch  ${lightMs.toString().padLeft(6)} ms   (light query, no JSON)');
  print('  hydrate ${hydrateMs.toString().padLeft(6)} ms   (200-word pool, decoded)');
  print('  index   ${indexMs.toString().padLeft(6)} ms   (once per pack revision, then cached)\n');
  print('launch speedup: ${(oldTotal / (lightMs == 0 ? 1 : lightMs)).toStringAsFixed(0)}x');

  await db.close();
}
