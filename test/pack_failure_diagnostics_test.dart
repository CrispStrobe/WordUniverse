import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/load_status.dart';
import 'package:WortUniversum/core/services/language_pack_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/core/services/db_platform/db_download_exception.dart';
import 'package:WortUniversum/core/services/pack_failure_logger.dart';

class FakeVocabulary extends VocabularyService {
  FakeVocabulary({Set<String>? installed, this.active = 'en', this.failWith})
      : installed = installed ?? {};
  final Set<String> installed;
  String active;
  Object? failWith;
  @override
  String get learningLanguage => active;
  @override
  bool get isInitialized => true;
  @override
  Future<String> savedLearningLanguage() async => 'de';
  @override
  Future<bool> isPackInstalled(String language) async =>
      installed.contains(language);
  @override
  Future<void> rememberLearningLanguage(String language) async {}
  @override
  Future<void> setLearningLanguage(String language, {bool allowDownload = false, LoadProgress? onProgress}) async {
    if (failWith != null) {
      final f = failWith!;
      if (f is Function) return await (f as Function)(language, allowDownload, onProgress);
      throw f;
    }
    installed.add(language);
    active = language;
  }
}

class FailingVocabulary extends FakeVocabulary {
  FailingVocabulary() : super(active: 'en');
  @override
  Future<void> setLearningLanguage(String language, {bool allowDownload = false, LoadProgress? onProgress}) async {
    onProgress?.call(.5, const LoadStatus(LoadStage.writingStorage));
    throw DbInsufficientSpaceException(requiredBytes: 200, availableBytes: 100);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackFailureLogger.instance.resetForTests();
  });

  test('caught install failure persists structured local diagnostics', () async {
    final service = LanguagePackService(FailingVocabulary(), freeSpaceProbe: () async => null);
    expect(await service.install('de'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.getStringList(PackFailureLogger.storageKey) ?? [];
    expect(records, hasLength(1));
    final record = jsonDecode(records.single) as Map;
    expect(record['pack'], 'de');
    expect(record['operation'], 'install');
    expect(record['stage'], 'writingStorage');
    expect(record['cause'], 'insufficientSpace');
    expect(record['requiredBytes'], 200);
    expect(record['availableBytes'], 100);
    expect(record.containsKey('stack'), isFalse);
  });

  test('caught activation failure is recorded as a distinct operation', () async {
    final vocab = FakeVocabulary(installed: {'de'}, failWith: DbStorageException('write refused', errorName: 'quota'));
    final service = LanguagePackService(vocab);
    expect(await service.activate('de'), isFalse);
    final entries = await PackFailureLogger.instance.readAll();
    expect(entries.single.operation, PackOperation.activate);
    expect(entries.single.cause, PackFailureCause.storage);
  });

  test('preflight refusal is durable with available bytes', () async {
    final service = LanguagePackService(FakeVocabulary(), freeSpaceProbe: () async => 1);
    expect(await service.install('de'), isFalse);
    expect((await PackFailureLogger.instance.readAll()).single.availableBytes, 1);
  });

  test('clear before read removes persisted entries', () async {
    final logger = PackFailureLogger();
    await logger.record(pack: 'de', operation: PackOperation.install, stage: LoadStage.preparing, error: StateError('private'));
    final restarted = PackFailureLogger();
    await restarted.clear();
    expect(await PackFailureLogger().readAll(), isEmpty);
  });

  test('success paths record nothing', () async {
    final service = LanguagePackService(FakeVocabulary());
    expect(await service.install('de'), isTrue);
    expect(await PackFailureLogger.instance.readAll(), isEmpty);
  });

  test('the local record is bounded at 20 failures', () async {
    final service = LanguagePackService(FailingVocabulary(), freeSpaceProbe: () async => null);
    for (var i = 0; i < 25; i++) {
      await service.install('de');
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(PackFailureLogger.storageKey), hasLength(20));
    expect((jsonDecode(prefs.getStringList(PackFailureLogger.storageKey)!.first) as Map)['requiredBytes'], 200);
  });

  test('corrupt stored failures are skipped without losing the good ones', () async {
    SharedPreferences.setMockInitialValues({
      PackFailureLogger.storageKey: ['{"pack":"de"', jsonEncode(PackFailureEntry(timestamp: DateTime(2026, 1, 2), pack: 'de', operation: PackOperation.install, stage: LoadStage.ready, cause: PackFailureCause.network).toJson())],
    });
    final entries = await PackFailureLogger.instance.readAll();
    expect(entries.single.cause, PackFailureCause.network);
    final service = LanguagePackService(FailingVocabulary(), freeSpaceProbe: () async => null);
    await service.install('de');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(PackFailureLogger.storageKey), hasLength(2));
  });
}
