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
import 'vocabulary_service.dart';
import 'db_platform/db_remote.dart' show DbDownloadException;

class LanguagePackService with ChangeNotifier {
  LanguagePackService(this._vocabulary);

  final VocabularyService _vocabulary;

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
  bool get isActivePackReady => _vocabulary.isInitialized;

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
  Future<void> refresh() async {
    for (final pack in kLanguagePacks.values) {
      final current = _states[pack.code]!;
      // Don't stomp on an install in flight.
      if (current.isInstalling) continue;

      final installed = await _vocabulary.isPackInstalled(pack.code);
      _states[pack.code] = current.copyWith(
        status: installed
            ? LanguagePackStatus.installed
            // Keep a previous failure visible unless the pack is now present.
            : (current.status == LanguagePackStatus.failed
                ? LanguagePackStatus.failed
                : LanguagePackStatus.notInstalled),
        progress: installed ? 1.0 : 0.0,
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
    if (state.isInstalling) {
      _log('Install for "$code" already in flight');
      return false;
    }
    if (state.isInstalled && activeLanguage == code && isActivePackReady) {
      return true;
    }

    _update(
      code,
      state.copyWith(
        status: LanguagePackStatus.installing,
        progress: 0.0,
        message: pack.requiresDownload
            ? 'Preparing download…'
            : 'Preparing ${pack.nativeName}…',
        clearError: true,
      ),
    );

    try {
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
          message: '',
          clearError: true,
        ),
      );
      _log('✅ Pack "$code" installed and active');
      // The rollback path in VocabularyService may have changed which pack is
      // active; keep every row honest.
      await refresh();
      return true;
    } catch (e) {
      final isNetwork = e is DbDownloadException ? e.isNetwork : true;
      _log('❌ Install of "$code" failed: $e');
      _update(
        code,
        _states[code]!.copyWith(
          status: LanguagePackStatus.failed,
          progress: 0.0,
          message: '',
          error: _describeError(e),
          errorIsNetwork: isNetwork,
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
          message: '',
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
    final installed = await _vocabulary.isPackInstalled(code);
    return (code: code, installed: installed);
  }

  String _describeError(Object error) {
    if (error is DbDownloadException) return error.message;
    if (error is LanguagePackNotInstalledException) {
      return 'The language pack still needs to be downloaded.';
    }
    return error.toString();
  }
}
