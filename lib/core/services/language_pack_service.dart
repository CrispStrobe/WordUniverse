// lib/core/services/language_pack_service.dart
//
// Owns the install lifecycle of language packs (see models/language_pack.dart)
// and is the single source of truth the UI listens to for pack status and
// download progress:
//
//   * Splash   — makes sure the saved learning language is usable before the
//                home screen appears, with consent + progress, and falls back
//                to the bundled pack when the user says "not now".
//   * Settings — lists every pack with status, size, license, a progress bar
//                while installing, and Download / Retry / Remove actions.
//   * Games    — `ensureLanguagePackReady()` gates every game launch, so a
//                missing pack shows the download sheet instead of crashing
//                somewhere inside a minigame with an empty vocabulary.
//
// The heavy lifting (download, integrity gates, decompression, caching) stays
// in db_platform/*; this service only orchestrates it, tracks progress, and
// guarantees the app is never left without a usable vocabulary.

import 'package:flutter/foundation.dart';

import '../models/language_pack.dart';
import '../models/load_status.dart';
import 'vocabulary_service.dart';
import 'db_platform/db_partial_cache.dart';
import 'db_platform/db_remote.dart';
import 'db_platform/db_storage.dart';

class LanguagePackService with ChangeNotifier {
  /// [partialCache] and [freeSpaceProbe] exist so tests can drive the
  /// resume-and-space behaviour without touching real storage.
  LanguagePackService(
    this._vocabulary, {
    DbPartialCache? partialCache,
    Future<int?> Function()? freeSpaceProbe,
  })  : _partialCacheOverride = partialCache,
        _freeSpaceProbe = freeSpaceProbe ?? availableStorageBytes;

  final VocabularyService _vocabulary;
  final DbPartialCache? _partialCacheOverride;
  final Future<int?> Function() _freeSpaceProbe;

  /// Resolved lazily: touching the platform default from a constructor would
  /// reach for app-support paths in unit tests.
  DbPartialCache get _partialCache =>
      _partialCacheOverride ?? defaultDbPartialCache;
  String? _selectedLanguage;
  String get selectedLanguage => _selectedLanguage ?? activeLanguage;

  Future<void> selectLanguage(String code) async {
    if (!kLanguagePacks.containsKey(code)) return;
    if (await _vocabulary.savedLearningLanguage() != code) {
      await _vocabulary.rememberLearningLanguage(code);
    }
    _selectedLanguage = code;
    notifyListeners();
  }

  DbDownloadController? downloadFor(String code) {
    final url = kLanguagePacks[code]?.remoteUrl;
    return url == null ? null : DbDownloadController.sharedFor(url);
  }

  void pause(String code) => downloadFor(code)?.pause();

  final Map<String, LanguagePackState> _states = {
    for (final pack in kLanguagePacks.values)
      pack.code: LanguagePackState(
        pack: pack,
        // Bundled packs need no install step; downloadable ones start unknown
        // and are resolved by refresh().
        status: pack.requiresDownload
            ? LanguagePackStatus.notInstalled
            : LanguagePackStatus.installed,
      ),
  };

  bool _statusesLoaded = false;
  bool get statusesLoaded => _statusesLoaded;

  /// Packs in display order, with live status.
  List<LanguagePackState> get packs =>
      [for (final pack in orderedLanguagePacks) _states[pack.code]!];

  LanguagePackState stateFor(String code) =>
      _states[code] ??
      LanguagePackState(
        pack: kLanguagePacks[code] ?? kLanguagePacks[kFallbackLanguageCode]!,
        status: LanguagePackStatus.notInstalled,
      );

  /// The pack the games are currently drawing words from.
  String get activeLanguage => _vocabulary.learningLanguage;

  /// True when the active pack is installed AND its vocabulary is loaded —
  /// i.e. it is safe to start a game.
  bool get isActivePackReady => !isAnyInstalling &&
      _vocabulary.isInitialized && activeLanguage == selectedLanguage;

  bool isInstalled(String code) => stateFor(code).isInstalled;

  bool get isAnyInstalling =>
      _states.values.any((state) => state.isInstalling);

  void _log(String message) {
    if (kDebugMode) debugPrint('[LANG_PACK] 📦 $message');
  }

  void _update(String code, LanguagePackState next) {
    _states[code] = next;
    notifyListeners();
  }

  /// Re-reads real storage for every downloadable pack. Cheap for bundled
  /// packs, one DB open per downloadable pack otherwise. Call it when Settings
  /// opens or after an install/removal.
  ///
  /// [probePartialDownloads] additionally reads the checkpoint store to learn
  /// how far a stopped download got. That is storage I/O, so it stays opt-in:
  /// it belongs to Settings drawing a label, not to the install path, which
  /// awaits refresh() and must not grow a disk round trip per install.
  Future<void> refresh({bool probePartialDownloads = false}) async {
    for (final pack in kLanguagePacks.values) {
      final current = _states[pack.code]!;
      // Don't stomp on an install in flight.
      if (current.isInstalling || current.status == LanguagePackStatus.paused) continue;

      final installed = await _vocabulary.isPackInstalled(pack.code);
      // A pack that is only part-way downloaded should say so rather than look
      // untouched; the header read behind this is cheap, but it is still I/O.
      final cached = installed || !probePartialDownloads
          ? null
          : await _cachedBytes(pack);
      _states[pack.code] = current.copyWith(
        status: installed
            ? LanguagePackStatus.installed
            // Keep a previous failure visible unless the pack is now present.
            : (current.status == LanguagePackStatus.failed
                ? LanguagePackStatus.failed
                : LanguagePackStatus.notInstalled),
        progress: installed ? 1.0 : 0.0,
        cachedBytes: cached,
        clearCachedBytes: installed || (probePartialDownloads && cached == null),
        clearError: installed,
      );
    }
    _statusesLoaded = true;
    notifyListeners();
  }

  /// Downloads (if needed) the pack for [code] and makes it the active
  /// learning language.
  ///
  /// Returns true on success. On failure the pack is marked
  /// [LanguagePackStatus.failed] with a user-readable [LanguagePackState.error]
  /// and the previously active language is restored, so the app stays
  /// playable. Never throws.
  ///
  /// Note that installing and activating are one step: only one vocabulary
  /// database is open at a time, so "download this pack" always means "start
  /// using it".
  Future<bool> install(String code) async {
    final pack = kLanguagePacks[code];
    if (pack == null) {
      _log('⚠️ Unknown pack "$code"');
      return false;
    }

    final state = _states[code]!;
    if (isAnyInstalling) {
      _log('Install for "$code" already in flight');
      return false;
    }
    await selectLanguage(code);
    if (state.isInstalled && activeLanguage == code && isActivePackReady) {
      return true;
    }

    // Refuse before downloading anything when the device already cannot hold
    // the installed database. Only browsers report a quota; native returns
    // null and is caught at write time instead.
    final required = pack.requiredFreeBytes;
    if (pack.requiresDownload && required != null) {
      final free = await _freeSpaceProbe();
      if (free != null && free < required) {
        _log('⛔ "$code" needs $required bytes, $free available');
        _update(
          code,
          _states[code]!.copyWith(
            status: LanguagePackStatus.failed,
            progress: 0.0,
            error: 'Not enough free space to install ${pack.nativeName}.',
            errorIsNetwork: false,
            errorIsSpace: true,
          ),
        );
        return false;
      }
    }

    _update(
      code,
      state.copyWith(
        status: LanguagePackStatus.installing,
        progress: 0.0,
        message: const LoadStatus(LoadStage.preparing),
        clearError: true,
      ),
    );

    try {
      downloadFor(code)?.resume();
      await _vocabulary.setLearningLanguage(
        code,
        allowDownload: true,
        onProgress: (progress, message) {
          final current = _states[code]!;
          if (!current.isInstalling) return;
          _update(
            code,
            current.copyWith(
              progress: progress.clamp(0.0, 1.0),
              message: message,
            ),
          );
        },
      );

      _update(
        code,
        _states[code]!.copyWith(
          status: LanguagePackStatus.installed,
          progress: 1.0,
          message: const LoadStatus(LoadStage.ready),
          clearError: true,
        ),
      );
      _log('✅ Pack "$code" installed and active');
      // The rollback path in VocabularyService may have changed which pack is
      // active; keep every row honest.
      await refresh();
      return true;
    } catch (e) {
      if (e is DbDownloadPausedException) {
        _update(code, _states[code]!.copyWith(
          status: LanguagePackStatus.paused,
          message: const LoadStatus(LoadStage.paused), clearError: true,
        ));
        return false;
      }
      final isNetwork = e is DbDownloadException ? e.isNetwork : true;
      _log('❌ Install of "$code" failed: $e');
      _update(
        code,
        _states[code]!.copyWith(
          status: LanguagePackStatus.failed,
          progress: 0.0,
          message: const LoadStatus(LoadStage.ready),
          error: _describeError(e),
          errorIsNetwork: isNetwork,
          errorIsSpace: e is DbInsufficientSpaceException,
        ),
      );
      return false;
    }
  }

  /// Switches to [code] without downloading anything. Returns false when the
  /// pack is not installed (the caller should offer [install] instead) or when
  /// activation failed.
  Future<bool> activate(String code) async {
    if (!kLanguagePacks.containsKey(code)) return false;
    if (isAnyInstalling) return false;
    await selectLanguage(code);
    if (!await _vocabulary.isPackInstalled(code)) return false;
    try {
      await _vocabulary.setLearningLanguage(code);
      await refresh();
      return true;
    } catch (e) {
      _log('❌ Activating "$code" failed: $e');
      _update(
        code,
        _states[code]!.copyWith(
          status: LanguagePackStatus.failed,
          error: _describeError(e),
        ),
      );
      return false;
    }
  }

  /// Frees a downloaded pack's storage. Refuses for the active pack and for
  /// bundled packs. Returns true when something was removed.
  Future<bool> remove(String code) async {
    final pack = kLanguagePacks[code];
    if (pack == null || !pack.requiresDownload) return false;
    if (activeLanguage == code) return false;
    try {
      await _vocabulary.removePack(code);
      _update(
        code,
        _states[code]!.copyWith(
          status: LanguagePackStatus.notInstalled,
          progress: 0.0,
          message: const LoadStatus(LoadStage.ready),
          clearError: true,
        ),
      );
      return true;
    } catch (e) {
      _log('❌ Removing "$code" failed: $e');
      return false;
    }
  }

  /// Falls back to the bundled pack — used when the user declines a download
  /// or a download keeps failing, so the app is usable either way.
  Future<bool> activateFallback() async {
    if (activeLanguage == kFallbackLanguageCode && isActivePackReady) {
      return true;
    }
    // The fallback pack is bundled, so this needs no network.
    final ok = await install(kFallbackLanguageCode);
    if (ok) await _vocabulary.rememberLearningLanguage(kFallbackLanguageCode);
    return ok;
  }

  /// What the saved learning language is and whether it can be used right now.
  /// The splash uses this to decide between "just load it" and "ask first".
  Future<({String code, bool installed})> savedLanguageStatus() async {
    final code = await _vocabulary.savedLearningLanguage();
    _selectedLanguage = code;
    final installed = await _vocabulary.isPackInstalled(code);
    return (code: code, installed: installed);
  }

  /// Looks up how far [code]'s stopped download got and publishes it, so a
  /// consent dialog can say "12.4 of 25 MB downloaded". Safe to call from a
  /// widget's initState: it never throws and does nothing for a pack that is
  /// installed or already downloading.
  Future<void> probePartialDownload(String code) async {
    final pack = kLanguagePacks[code];
    if (pack == null || !pack.requiresDownload) return;
    final current = _states[code]!;
    if (current.isInstalled || current.isInstalling) return;
    final cached = await _cachedBytes(pack);
    if (cached == null || !_states.containsKey(code)) return;
    _update(code, _states[code]!.copyWith(cachedBytes: cached));
  }

  /// Bytes already on disk for a partly downloaded pack. Never throws: this
  /// only decorates a label, and storage can be unavailable.
  Future<int?> _cachedBytes(LanguagePack pack) async {
    final url = pack.remoteUrl;
    if (url == null) return null;
    try {
      final length = await _partialCache.cachedLength(url);
      return (length ?? 0) > 0 ? length : null;
    } catch (_) {
      return null;
    }
  }

  String _describeError(Object error) {
    if (error is DbDownloadException) return error.message;
    if (error is LanguagePackNotInstalledException) {
      return 'The language pack still needs to be downloaded.';
    }
    return error.toString();
  }
}
