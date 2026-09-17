// Unit tests for LanguagePackService — the install/gating lifecycle.
//
// The service is the only thing standing between a game launch and an empty
// vocabulary database, so these tests care less about the happy path than
// about the refusals: a download that fails must leave the app playable, a
// pack in use must not be deletable, and activating something that was never
// downloaded must not silently start a download.
//
// VocabularyService is faked by subclassing. The real one opens SQLite and
// talks to the network; none of that is under test here, and the seam the
// service actually depends on is small — six methods and two getters.

import 'dart:async';
import 'package:WortUniversum/core/models/load_status.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';
import 'package:WortUniversum/core/services/language_pack_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';

/// A VocabularyService that keeps its state in memory.
class _FakeVocabulary extends VocabularyService {
  _FakeVocabulary({
    Set<String>? installed,
    this.active = kFallbackLanguageCode,
    this.ready = true,
    String? saved,
  })  : installed = installed ?? {kFallbackLanguageCode},
        saved = saved ?? kDefaultLanguageCode;

  Set<String> installed;
  String active;
  bool ready;
  String saved;

  /// Set to make the next setLearningLanguage throw.
  Object? failWith;

  /// Set to hold setLearningLanguage open until completed, so a second
  /// install can be attempted while the first is still in flight.
  Completer<void>? block;

  /// Progress values to emit before completing, for the download UI.
  List<(double, LoadStatus)> emitProgress = const [];

  final List<String> calls = [];

  @override
  String get learningLanguage => active;

  @override
  bool get isInitialized => ready;

  @override
  Future<bool> isPackInstalled(String language) async =>
      installed.contains(language);

  @override
  Future<String> savedLearningLanguage() async => saved;

  @override
  Future<void> rememberLearningLanguage(String language) async {
    calls.add('remember:$language');
    saved = language;
  }

  @override
  Future<void> removePack(String language) async {
    calls.add('remove:$language');
    installed.remove(language);
  }

  @override
  Future<void> setLearningLanguage(
    String language, {
    bool allowDownload = false,
    LoadProgress? onProgress,
  }) async {
    calls.add('set:$language:allowDownload=$allowDownload');
    for (final (p, m) in emitProgress) {
      onProgress?.call(p, m);
    }
    if (block != null) await block!.future;
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
    installed.add(language);
    active = language;
    ready = true;
  }
}

void main() {
  // 'de' is the default and is downloaded; 'en' is bundled and is the
  // fallback. The tests lean on that split, so assert it rather than assume.
  test('registry assumptions these tests rely on', () {
    expect(kLanguagePacks[kDefaultLanguageCode]!.requiresDownload, isTrue,
        reason: 'the default pack is the one that needs downloading');
    expect(kLanguagePacks[kFallbackLanguageCode]!.requiresDownload, isFalse,
        reason: 'the fallback must work with no network');
  });

  group('initial state and gating', () {
    test('a bundled pack starts installed, a downloadable one does not', () {
      final service = LanguagePackService(_FakeVocabulary());
      expect(service.isInstalled(kFallbackLanguageCode), isTrue);
      expect(service.isInstalled(kDefaultLanguageCode), isFalse);
    });

    test('isActivePackReady follows the vocabulary, since that is what a game '
        'actually reads from', () {
      final vocab = _FakeVocabulary(ready: false);
      final service = LanguagePackService(vocab);
      expect(service.isActivePackReady, isFalse);
      vocab.ready = true;
      expect(service.isActivePackReady, isTrue);
    });

    test('an unknown code yields a fallback state instead of throwing', () {
      final service = LanguagePackService(_FakeVocabulary());
      final state = service.stateFor('zz');
      expect(state.pack.code, kFallbackLanguageCode);
      expect(state.isInstalled, isFalse);
    });

    test('packs lists every registered pack, default first', () {
      final service = LanguagePackService(_FakeVocabulary());
      expect(service.packs.length, kLanguagePacks.length);
      expect(service.packs.first.pack.code, kDefaultLanguageCode);
    });
  });

  group('install', () {
    test('an unknown pack is refused rather than downloaded', () async {
      final vocab = _FakeVocabulary();
      final service = LanguagePackService(vocab);
      expect(await service.install('zz'), isFalse);
      expect(vocab.calls, isEmpty);
    });

    test('a successful install ends installed, complete and error-free',
        () async {
      final vocab = _FakeVocabulary();
      final service = LanguagePackService(vocab);

      expect(await service.install(kDefaultLanguageCode), isTrue);

      final state = service.stateFor(kDefaultLanguageCode);
      expect(state.status, LanguagePackStatus.installed);
      expect(state.progress, 1.0);
      expect(state.error, isNull);
      expect(vocab.calls, contains('set:de:allowDownload=true'));
    });

    test('download progress reaches the state and notifies listeners',
        () async {
      final vocab = _FakeVocabulary()
        ..emitProgress = const [(0.25, LoadStatus(LoadStage.downloading)), (0.8, LoadStatus(LoadStage.decompressing))];
      final service = LanguagePackService(vocab);

      var notifications = 0;
      service.addListener(() => notifications++);

      await service.install(kDefaultLanguageCode);

      expect(notifications, greaterThan(1),
          reason: 'the progress bar needs a rebuild per step');
      expect(service.stateFor(kDefaultLanguageCode).progress, 1.0);
    });

    test('progress is clamped, so a bad callback cannot break the bar',
        () async {
      final vocab = _FakeVocabulary()
        ..emitProgress = const [(-3.0, LoadStatus(LoadStage.preparing)), (42.0, LoadStatus(LoadStage.ready))];
      final service = LanguagePackService(vocab);

      late double seen;
      service.addListener(
          () => seen = service.stateFor(kDefaultLanguageCode).progress);

      await service.install(kDefaultLanguageCode);
      expect(seen, inInclusiveRange(0.0, 1.0));
    });

    test('a failed download leaves the app playable and says why', () async {
      final vocab = _FakeVocabulary()
        ..failWith = DbDownloadException('Could not reach the server',
            isNetwork: true);
      final service = LanguagePackService(vocab);

      expect(await service.install(kDefaultLanguageCode), isFalse);

      final state = service.stateFor(kDefaultLanguageCode);
      expect(state.status, LanguagePackStatus.failed);
      expect(state.progress, 0.0);
      expect(state.error, 'Could not reach the server');
      expect(state.errorIsNetwork, isTrue,
          reason: 'a network failure should offer Retry, not just an error');
    });

    test('a non-network failure is still reported, and never throws out',
        () async {
      final vocab = _FakeVocabulary()..failWith = StateError('disk full');
      final service = LanguagePackService(vocab);

      expect(await service.install(kDefaultLanguageCode), isFalse);
      expect(service.stateFor(kDefaultLanguageCode).status,
          LanguagePackStatus.failed);
      expect(service.stateFor(kDefaultLanguageCode).error, isNotNull);
    });

    test('a second install is refused while the first is still running',
        () async {
      final vocab = _FakeVocabulary()..block = Completer<void>();
      final service = LanguagePackService(vocab);

      final first = service.install(kDefaultLanguageCode);
      await Future<void>.delayed(Duration.zero);
      expect(service.stateFor(kDefaultLanguageCode).isInstalling, isTrue);

      // Double-tapping Download must not start a second download.
      expect(await service.install(kDefaultLanguageCode), isFalse);

      vocab.block!.complete();
      expect(await first, isTrue);
      expect(vocab.calls.where((c) => c.startsWith('set:de')).length, 1);
    });

    test('installing the pack already in use is a no-op', () async {
      final vocab = _FakeVocabulary(
        installed: {kFallbackLanguageCode, kDefaultLanguageCode},
        active: kDefaultLanguageCode,
      );
      final service = LanguagePackService(vocab);
      // The short-circuit reads in-memory status, which only reflects real
      // storage after a refresh — which is what Settings does when it opens.
      // Without this the service still believes the pack is missing and
      // re-installs it.
      await service.refresh();

      expect(await service.install(kDefaultLanguageCode), isTrue);
      expect(vocab.calls, isEmpty, reason: 'nothing needed doing');
    });

    test('without a refresh first, install re-runs rather than short-circuits',
        () async {
      // Documents the precondition above: the guard is not a storage check.
      final vocab = _FakeVocabulary(
        installed: {kFallbackLanguageCode, kDefaultLanguageCode},
        active: kDefaultLanguageCode,
      );
      final service = LanguagePackService(vocab);

      expect(await service.install(kDefaultLanguageCode), isTrue);
      expect(vocab.calls, contains('set:de:allowDownload=true'));
    });
  });

  group('activate', () {
    test('a pack that was never downloaded is refused, not fetched', () async {
      final vocab = _FakeVocabulary(installed: {kFallbackLanguageCode});
      final service = LanguagePackService(vocab);

      expect(await service.activate(kDefaultLanguageCode), isFalse);
      expect(vocab.calls, isEmpty,
          reason: 'activate must never start a download behind the user');
    });

    test('an unknown code is refused', () async {
      final service = LanguagePackService(_FakeVocabulary());
      expect(await service.activate('zz'), isFalse);
    });

    test('an installed pack activates', () async {
      final vocab = _FakeVocabulary(
        installed: {kFallbackLanguageCode, kDefaultLanguageCode},
      );
      final service = LanguagePackService(vocab);

      expect(await service.activate(kDefaultLanguageCode), isTrue);
      expect(vocab.active, kDefaultLanguageCode);
    });

    test('a failure during activation is reported, not thrown', () async {
      final vocab = _FakeVocabulary(
        installed: {kFallbackLanguageCode, kDefaultLanguageCode},
      )..failWith = StateError('corrupt');
      final service = LanguagePackService(vocab);

      expect(await service.activate(kDefaultLanguageCode), isFalse);
      expect(service.stateFor(kDefaultLanguageCode).status,
          LanguagePackStatus.failed);
    });
  });

  group('remove', () {
    test('the bundled pack cannot be removed — nothing to free, and the app '
        'would lose its offline fallback', () async {
      final vocab = _FakeVocabulary();
      final service = LanguagePackService(vocab);

      expect(await service.remove(kFallbackLanguageCode), isFalse);
      expect(vocab.calls, isEmpty);
    });

    test('the pack currently in use cannot be removed', () async {
      final vocab = _FakeVocabulary(
        installed: {kFallbackLanguageCode, kDefaultLanguageCode},
        active: kDefaultLanguageCode,
      );
      final service = LanguagePackService(vocab);

      expect(await service.remove(kDefaultLanguageCode), isFalse);
      expect(vocab.calls, isEmpty,
          reason: 'removing the live database would empty every game');
    });

    test('an idle downloaded pack is removed and marked notInstalled',
        () async {
      final vocab = _FakeVocabulary(
        installed: {kFallbackLanguageCode, kDefaultLanguageCode},
        active: kFallbackLanguageCode,
      );
      final service = LanguagePackService(vocab);

      expect(await service.remove(kDefaultLanguageCode), isTrue);
      expect(service.stateFor(kDefaultLanguageCode).status,
          LanguagePackStatus.notInstalled);
      expect(vocab.installed, isNot(contains(kDefaultLanguageCode)));
    });
  });

  group('fallback', () {
    test('already on the bundled pack and ready: nothing to do', () async {
      final vocab = _FakeVocabulary(active: kFallbackLanguageCode, ready: true);
      final service = LanguagePackService(vocab);

      expect(await service.activateFallback(), isTrue);
      expect(vocab.calls, isEmpty);
    });

    test('declining a download falls back and remembers the choice', () async {
      // The splash path: saved language is German, user says "not now".
      final vocab = _FakeVocabulary(
        installed: {kFallbackLanguageCode},
        active: kDefaultLanguageCode,
        ready: false,
      );
      final service = LanguagePackService(vocab);

      expect(await service.activateFallback(), isTrue);
      expect(vocab.active, kFallbackLanguageCode);
      expect(vocab.calls, contains('remember:en'),
          reason: 'otherwise the prompt reappears on every launch');
    });
  });

  group('savedLanguageStatus', () {
    test('reports the saved language and whether it can be used now',
        () async {
      final service = LanguagePackService(_FakeVocabulary(
        saved: kDefaultLanguageCode,
        installed: {kFallbackLanguageCode},
      ));

      final status = await service.savedLanguageStatus();
      expect(status.code, kDefaultLanguageCode);
      expect(status.installed, isFalse,
          reason: 'the splash uses this to decide whether to prompt');
    });

    test('an installed saved language needs no prompt', () async {
      final service = LanguagePackService(_FakeVocabulary(
        saved: kDefaultLanguageCode,
        installed: {kFallbackLanguageCode, kDefaultLanguageCode},
      ));

      expect((await service.savedLanguageStatus()).installed, isTrue);
    });
  });

  group('refresh', () {
    test('re-reads storage and marks statusesLoaded', () async {
      final vocab = _FakeVocabulary(
        installed: {kFallbackLanguageCode, kDefaultLanguageCode},
      );
      final service = LanguagePackService(vocab);
      expect(service.statusesLoaded, isFalse);

      await service.refresh();

      expect(service.statusesLoaded, isTrue);
      expect(service.isInstalled(kDefaultLanguageCode), isTrue);
    });

    test('does not stomp an install that is still in flight', () async {
      final vocab = _FakeVocabulary()..block = Completer<void>();
      final service = LanguagePackService(vocab);

      final installing = service.install(kDefaultLanguageCode);
      await Future<void>.delayed(Duration.zero);

      await service.refresh();
      expect(service.stateFor(kDefaultLanguageCode).isInstalling, isTrue,
          reason: 'a refresh mid-download must not reset the progress bar');

      vocab.block!.complete();
      await installing;
    });

    test('a previous failure stays visible until the pack is really there',
        () async {
      final vocab = _FakeVocabulary()..failWith = StateError('nope');
      final service = LanguagePackService(vocab);

      await service.install(kDefaultLanguageCode);
      expect(service.stateFor(kDefaultLanguageCode).status,
          LanguagePackStatus.failed);

      await service.refresh();
      expect(service.stateFor(kDefaultLanguageCode).status,
          LanguagePackStatus.failed,
          reason: 'Retry should remain offered, not silently become "not '
              'installed"');

      vocab.installed.add(kDefaultLanguageCode);
      await service.refresh();
      expect(service.stateFor(kDefaultLanguageCode).status,
          LanguagePackStatus.installed);
    });
  });
}
