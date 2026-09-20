@TestOn('vm')
library;

// A frozen sample of what the games ask, so that a change to the content
// shows up as a diff someone reads rather than as nothing at all.
//
//     flutter test test/audit/challenge_golden_test.dart
//     WU_GOLDEN_UPDATE=1 flutter test test/audit/challenge_golden_test.dart
//
// The contract test says the items are well formed; the dump lets a person
// judge them. Neither notices when a change quietly makes the games ask
// *different* questions — a repaired pack that drops a gloss, a tightened
// filter that empties a tier, a reordered distractor pool. Those arrive here
// as a diff against a file in the repository.
//
// Keep the sample small and seeded: it is a tripwire, not a corpus.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'challenge_harness.dart';

const _grade = 3;
const _perGame = 4;
const _seed = 1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final update = Platform.environment['WU_GOLDEN_UPDATE'] == '1';

  for (final language in ['en', 'de']) {
    test('$language: the games ask what they asked before', () async {
      if (language == 'de' && germanPackPath == null) {
        markTestSkipped('set WU_PACK_DE=/path/to/grundwortschatz.db');
        return;
      }
      final pack = await openAuditPack(language);
      addTearDown(pack.dispose);

      final buffer = StringBuffer();
      for (final name in generators.keys.toList()..sort()) {
        final supported = generatorLanguages[name] ?? const ['en', 'de'];
        if (!supported.contains(language)) continue;
        final items = await generators[name]!(pack.context(
          grade: _grade,
          count: _perGame,
          rng: Random(_seed),
        ));
        buffer.writeln('── $name (${items.length})');
        for (final item in items) {
          buffer.write(item.toText());
        }
      }

      final golden = File('test/audit/golden/${language}_g$_grade.txt');
      final current = buffer.toString();
      if (update || !golden.existsSync()) {
        golden.writeAsStringSync(current);
        // ignore: avoid_print
        print('wrote ${golden.path}');
        return;
      }
      expect(current, golden.readAsStringSync(),
          reason: 'The games ask something different than the frozen sample '
              'in ${golden.path}. Read the diff: if the change is intended, '
              'rerun with WU_GOLDEN_UPDATE=1 and commit the new sample.');
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}
