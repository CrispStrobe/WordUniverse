import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/load_status.dart';
import 'package:WortUniversum/core/services/pack_failure_logger.dart';

class DelayedPreferences extends Fake implements SharedPreferences {
  DelayedPreferences([List<String> initial = const []])
      : stored = List.of(initial);

  final loading = Completer<SharedPreferences>();
  final loadStarted = Completer<void>();
  int loads = 0;
  List<String> stored;
  final writes = <List<String>>[];
  final writeStarted = Completer<void>();
  Completer<void>? firstWrite;
  bool writeResult = true;
  bool throwOnWrite = false;

  Future<SharedPreferences> open() {
    loads++;
    if (!loadStarted.isCompleted) loadStarted.complete();
    return loading.future;
  }

  @override
  List<String>? getStringList(String key) => List.of(stored);

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    writes.add(List.of(value));
    if (writes.length == 1) {
      writeStarted.complete();
      await firstWrite?.future;
    }
    if (throwOnWrite) throw StateError('storage unavailable');
    if (writeResult) stored = List.of(value);
    return writeResult;
  }
}

String saved(String pack) => jsonEncode(PackFailureEntry(
      timestamp: DateTime.utc(2026, 1, 1),
      pack: pack,
      operation: PackOperation.install,
      stage: LoadStage.preparing,
      cause: PackFailureCause.network,
    ).toJson());

Future<void> record(PackFailureLogger logger, String pack) => logger.record(
      pack: pack,
      operation: PackOperation.install,
      stage: LoadStage.preparing,
      error: StateError('private'),
    );

List<String> packs(List<String> records) =>
    records.map((text) => (jsonDecode(text) as Map)['pack'] as String).toList();

void main() {
  for (final synchronous in [false, true]) {
    test('unavailable preferences preserve bounded session history (sync: $synchronous)', () async {
      final logger = PackFailureLogger(preferences: () {
        if (synchronous) throw StateError('preferences unavailable');
        return Future<SharedPreferences>.error(StateError('preferences unavailable'));
      });
      expect(await logger.readAll(), isEmpty);
      await Future.wait([for (var i = 0; i < 25; i++) record(logger, 'pack-$i')]);
      expect((await logger.readAll()).map((e) => e.pack),
          [for (var i = 5; i < 25; i++) 'pack-$i']);
      await logger.clear();
      expect(await logger.readAll(), isEmpty);
      await record(logger, 'after-clear');
      expect((await logger.readAll()).single.pack, 'after-clear');
    });
  }

  for (final throwing in [false, true]) {
    test('failed writes preserve session entries and do not poison the queue (throwing: $throwing)', () async {
      final prefs = DelayedPreferences([saved('old')])
        ..writeResult = false
        ..throwOnWrite = throwing;
      prefs.loading.complete(prefs);
      final logger = PackFailureLogger(preferences: prefs.open);
      await Future.wait([record(logger, 'one'), record(logger, 'two')]);
      expect((await logger.readAll()).map((e) => e.pack), ['old', 'one', 'two']);
      expect(packs(prefs.stored), ['old']);
      await logger.clear();
      expect(await logger.readAll(), isEmpty);
      await record(logger, 'session-only');
      expect((await logger.readAll()).single.pack, 'session-only');
      prefs.writeResult = true;
      prefs.throwOnWrite = false;
      await record(logger, 'recovered');
      expect(packs(prefs.stored), ['session-only', 'recovered']);
      final restarted = PackFailureLogger(preferences: prefs.open);
      expect((await restarted.readAll()).map((e) => e.pack), ['session-only', 'recovered']);
    });
  }

  test('loading retains the newest 20 valid records, ignoring corrupt records', () async {
    final prefs = DelayedPreferences([
      for (var i = 0; i < 25; i++) ...[saved('pack-$i'), 'invalid json'],
    ]);
    prefs.loading.complete(prefs);
    final logger = PackFailureLogger(preferences: prefs.open);
    final expected = [for (var i = 5; i < 25; i++) 'pack-$i'];
    expect((await logger.readAll()).map((e) => e.pack), expected);
    await record(logger, 'new');
    expect(packs(prefs.stored), [...expected.skip(1), 'new']);
  });

  test('delayed record, read, clear and record complete in invocation order', () async {
    final prefs = DelayedPreferences()..firstWrite = Completer<void>();
    prefs.loading.complete(prefs);
    final logger = PackFailureLogger(preferences: prefs.open);
    final first = record(logger, 'before-clear');
    await prefs.writeStarted.future;
    final snapshot = logger.readAll();
    final clearing = logger.clear();
    final emptySnapshot = logger.readAll();
    final last = record(logger, 'after-clear');
    var completed = false;
    final lastCompletion = last.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    final writesWhileBlocked = prefs.writes.length;
    final completedWhileBlocked = completed;
    prefs.firstWrite!.complete();
    await Future.wait([first, clearing, lastCompletion]);

    expect(writesWhileBlocked, 1);
    expect(completedWhileBlocked, isFalse);
    expect((await snapshot).map((e) => e.pack), ['before-clear']);
    expect(await emptySnapshot, isEmpty);
    expect(prefs.writes.map(packs), [
      ['before-clear'],
      <String>[],
      ['after-clear'],
    ]);
    expect((await logger.readAll()).map((e) => e.pack), ['after-clear']);
    final restarted = PackFailureLogger(preferences: prefs.open);
    expect((await restarted.readAll()).map((e) => e.pack), ['after-clear']);
  });

  test('clear queued during cold read cannot resurrect persisted history', () async {
    final prefs = DelayedPreferences([saved('old')]);
    final logger = PackFailureLogger(preferences: prefs.open);
    final reading = logger.readAll();
    await prefs.loadStarted.future;
    final clearing = logger.clear();
    // Drain queued continuations while initialization remains explicitly held.
    await Future<void>.delayed(Duration.zero);
    prefs.loading.complete(prefs);
    expect((await reading).map((e) => e.pack), ['old']);
    await clearing;
    expect(await logger.readAll(), isEmpty);
    expect(prefs.stored, isEmpty);
  });
}
