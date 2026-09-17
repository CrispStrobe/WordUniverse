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

  Future<SharedPreferences> open() {
    loads++;
    if (!loadStarted.isCompleted) loadStarted.complete();
    return loading.future;
  }

  @override
  List<String>? getStringList(String key) => List.of(stored);

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    stored = List.of(value);
    return true;
  }
}

String saved(String pack) => jsonEncode(PackFailureEntry(
      timestamp: DateTime.utc(2026, 1, 1),
      pack: pack,
      operation: PackOperation.install,
      stage: LoadStage.preparing,
      cause: PackFailureCause.network,
    ).toJson());

void main() {
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
