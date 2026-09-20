@TestOn('vm')
library;

// Prints what the games would actually ask a learner, as text or JSON, so that
// the content can be reviewed in bulk instead of by playing.
//
//   WU_DUMP=all WU_DUMP_COUNT=25 flutter test test/audit/challenge_dump_test.dart
//   WU_DUMP=homophone_drill WU_DUMP_GRADE=4 WU_DUMP_FORMAT=json ...
//   WU_DUMP=all WU_DUMP_LANG=de WU_PACK_DE=/path/to/grundwortschatz.db ...
//
// tools/audit/dump.sh wraps this with flags instead of environment variables.
//
// It is a test only because the app's code needs a Flutter VM; nothing here
// asserts anything about the content. The point is the output: a reviewer — or
// an agent — reads a few hundred generated items and judges whether the
// question is answerable, whether the marked answer is right, and whether the
// distractors are fair. The invariants that hold for *every* item, and so can
// be machine-checked, live in challenge_contract_test.dart instead.
//
// The generators themselves are in challenge_harness.dart, shared with that
// contract test.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'challenge_harness.dart';

void main() {
  final requested = Platform.environment['WU_DUMP'];
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dump generated challenges', () async {
    if (requested == null || requested.isEmpty) {
      markTestSkipped('set WU_DUMP=all or WU_DUMP=<game>[,<game>...]');
      return;
    }
    final language = Platform.environment['WU_DUMP_LANG'] ?? 'en';
    final count =
        int.tryParse(Platform.environment['WU_DUMP_COUNT'] ?? '') ?? 20;
    final grade =
        int.tryParse(Platform.environment['WU_DUMP_GRADE'] ?? '') ?? 3;
    final asJson = Platform.environment['WU_DUMP_FORMAT'] == 'json';
    final seed = int.tryParse(Platform.environment['WU_DUMP_SEED'] ?? '') ?? 1;

    final AuditPack pack;
    try {
      pack = await openAuditPack(language);
    } on StateError catch (e) {
      markTestSkipped(e.message);
      return;
    }
    addTearDown(pack.dispose);

    final names = requested == 'all'
        ? generators.keys.toList()
        : requested.split(',').map((n) => n.trim()).toList();
    final buffer = StringBuffer();
    var total = 0;

    for (final name in names) {
      final supported = generatorLanguages[name] ?? const ['en', 'de'];
      if (!supported.contains(language)) {
        buffer.writeln('\n── $name  skipped: $language is not one of '
            '${supported.join('/')}');
        continue;
      }
      final generator = generators[name];
      if (generator == null) {
        buffer.writeln('!! unknown generator "$name" — '
            'available: ${generators.keys.join(', ')}');
        continue;
      }
      final items = await generator(
          pack.context(grade: grade, count: count, rng: Random(seed)));
      total += items.length;
      if (asJson) {
        for (final item in items) {
          buffer.writeln(jsonEncode(item.toJson()));
        }
      } else {
        buffer.writeln('\n── $name  (${items.length} items, '
            '$language, grade $grade) ${'─' * 20}');
        for (final item in items) {
          buffer.write(item.toText());
        }
      }
    }

    if (!asJson) {
      buffer.writeln('\n$total items from ${names.length} generator(s).'
          '${notYetReachable.isEmpty ? '' : ' Not reachable headlessly yet '
              '(${notYetReachable.length}): ${notYetReachable.join(', ')}.'}');
    }

    final out = Platform.environment['WU_DUMP_OUT'];
    if (out != null) {
      await File(out).writeAsString(buffer.toString());
      // ignore: avoid_print
      print('wrote $total items to $out');
    } else {
      // ignore: avoid_print
      print(buffer.toString());
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
