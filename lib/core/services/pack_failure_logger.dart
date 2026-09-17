import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/load_status.dart';
import 'db_platform/db_download_exception.dart';
import 'db_platform/db_gzip.dart';
import 'db_platform/db_schema.dart';

enum PackFailureCause { insufficientSpace, storage, schema, payload, network, download, unknown }
enum PackOperation { install, activate }

class PackFailureEntry {
  const PackFailureEntry({required this.timestamp, required this.pack,
    required this.operation, required this.stage, required this.cause,
    this.requiredBytes, this.availableBytes});
  final DateTime timestamp;
  final String pack;
  final PackOperation operation;
  final LoadStage stage;
  final PackFailureCause cause;
  final int? requiredBytes;
  final int? availableBytes;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toIso8601String(), 'pack': pack,
    'operation': operation.name, 'stage': stage.name, 'cause': cause.name,
    if (requiredBytes != null) 'requiredBytes': requiredBytes,
    if (availableBytes != null) 'availableBytes': availableBytes,
  };

  factory PackFailureEntry.fromJson(Map<String, dynamic> json) => PackFailureEntry(
    timestamp: DateTime.parse(json['timestamp'] as String),
    pack: json['pack'] as String,
    operation: PackOperation.values.byName(json['operation'] as String),
    stage: LoadStage.values.byName(json['stage'] as String),
    cause: PackFailureCause.values.byName(json['cause'] as String),
    requiredBytes: json['requiredBytes'] as int?,
    availableBytes: json['availableBytes'] as int?,
  );
}

/// Same local-first, best-effort pattern as CrashLogger, but for handled pack
/// failures, not crashes. No global handlers, raw exceptions, stack traces or
/// network uploads. Preferences also work in browsers where dart:io does not.
class PackFailureLogger {
  PackFailureLogger({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;
  final Future<SharedPreferences> Function() _preferences;
  static final instance = PackFailureLogger();
  static const storageKey = 'pack_failures_v1';
  static const maxEntries = 20;
  final _entries = <PackFailureEntry>[];
  bool _loaded = false;

  /// Used only by tests to drop the in-memory cache between cases.
  void resetForTests() {
    _entries.clear();
    _loaded = false;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await _preferences();
      for (final text in prefs.getStringList(storageKey) ?? <String>[]) {
        try {
          _entries.add(PackFailureEntry.fromJson(jsonDecode(text) as Map<String, dynamic>));
        } catch (_) {
          // One unreadable record must not hide the rest.
        }
      }
    } catch (_) {
      // Diagnostics must never break the install path they observe.
    }
  }

  Future<void> record({required String pack, required PackOperation operation,
    required LoadStage stage, required Object error, int? requiredBytes,
    int? availableBytes}) async {
    await _load();
    final space = error is DbInsufficientSpaceException ? error : null;
    final cause = switch (error) {
      DbInsufficientSpaceException() => PackFailureCause.insufficientSpace,
      DbStorageException() => PackFailureCause.storage,
      DbSchemaException() => PackFailureCause.schema,
      DbPayloadException() => PackFailureCause.payload,
      DbDownloadException(isNetwork: true) => PackFailureCause.network,
      DbDownloadException() => PackFailureCause.download,
      _ => PackFailureCause.unknown,
    };
    final entry = PackFailureEntry(timestamp: DateTime.now(), pack: pack,
      operation: operation, stage: stage, cause: cause,
      requiredBytes: space?.requiredBytes ?? requiredBytes,
      availableBytes: space?.availableBytes ?? availableBytes);
    _entries.add(entry);
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    await _persist();
  }

  Future<void> clear() async {
    await _load();
    _entries.clear();
    await _persist();
  }

  Future<void> _persist() async {
    if (!_loaded) return;
    try {
      final prefs = await _preferences();
      await prefs.setStringList(storageKey, _entries.map((e) => jsonEncode(e.toJson())).toList());
    } catch (_) {
      // Best-effort: the in-memory list keeps the failure visible this session.
    }
  }

  Future<List<PackFailureEntry>> readAll() async {
    await _load();
    return List.unmodifiable(_entries);
  }
}
