// lib/core/models/language_pack.dart
//
// The single place that describes a learning language and where its
// vocabulary database comes from. Adding a language means adding one entry to
// [kLanguagePacks] — nothing else in the app hardcodes a language code, so a
// new pack automatically appears in Settings, gets a download/progress flow,
// and gates the games until it is installed.
//
// Two delivery modes exist:
//   * BUNDLED  ([assetPath] set, [remoteUrl] null) — shipped inside the app
//     binary, always "installed", no download, no consent. Used for English
//     (CC BY-SA 4.0).
//   * DOWNLOADED ([remoteUrl] set) — fetched once on demand from a
//     GPL-compliant distribution point and cached in the app's storage. Used
//     for German, whose DB is GPL-3.0 (it contains data derived from childLex)
//     and therefore must not be bundled in a store binary. See
//     services/db_platform/db_remote.dart for the licensing rationale and the
//     integrity policy behind the `expected*` pins.
//
// A pack may set both [assetPath] and [remoteUrl]; the remote path wins, the
// asset acts as an offline fallback for non-store builds.

import 'package:flutter/foundation.dart' show immutable;
import 'load_status.dart';

/// Where a language's vocabulary DB comes from, plus the metadata needed to
/// disclose the download (size, license) and to verify what arrives.
@immutable
class LanguagePack {
  /// Language code used as the persisted `learning_language` value.
  final String code;

  /// Endonym shown in the UI ("Deutsch", "English"). Deliberately not
  /// localized: a language picker reads best in its own language.
  final String nativeName;

  /// Filename of the decompressed SQLite DB in app storage / IndexedDB.
  final String databaseName;

  /// Bundled gzipped asset, when the DB ships with the app.
  final String? assetPath;

  /// Remote gzipped DB, when the DB is downloaded on demand.
  final String? remoteUrl;

  /// Integrity pins — see db_remote.dart. Compressed size is also the figure
  /// disclosed to the user before downloading.
  final int? expectedCompressedBytes;

  /// Digest of the published (still gzipped) artifact. The app does not hash
  /// 25 MB at install time — the size pin plus gzip's CRC already gate the
  /// transfer — but CI compares this against the host's published digest, so a
  /// rebuilt pack cannot silently drift from the pins. See
  /// test/live/language_pack_pins_live_test.dart.
  final String? expectedCompressedSha256;
  final int? expectedDecompressedBytes;
  final String? expectedDecompressedSha256;

  /// SPDX-ish label for the data license, shown next to the pack.
  final String licenseLabel;

  /// Where the dataset (and its attribution) lives.
  final String? datasetUrl;

  const LanguagePack({
    required this.code,
    required this.nativeName,
    required this.databaseName,
    required this.licenseLabel,
    this.assetPath,
    this.remoteUrl,
    this.expectedCompressedBytes,
    this.expectedCompressedSha256,
    this.expectedDecompressedBytes,
    this.expectedDecompressedSha256,
    this.datasetUrl,
  });

  /// True when the pack has to be fetched over the network before it can be
  /// used. Bundled packs are usable immediately.
  bool get requiresDownload => remoteUrl != null && remoteUrl!.isNotEmpty;

  /// True when the pack ships inside the binary.
  bool get isBundled => assetPath != null && assetPath!.isNotEmpty;

  /// Download size for disclosure, e.g. "25 MB". Falls back to an estimate
  /// when no pin is set.
  String get downloadSizeLabel => _megabytes(expectedCompressedBytes) ?? '~25 MB';

  /// What the pack occupies once installed, which is what actually has to fit
  /// on the device: the database is stored decompressed. Disclosing only the
  /// download size understates the requirement by roughly six times.
  String? get installedSizeLabel => _megabytes(expectedDecompressedBytes);

  /// Free space an install needs: the decompressed database plus the
  /// compressed copy held while it is being written.
  int? get requiredFreeBytes => expectedDecompressedBytes == null
      ? null
      : expectedDecompressedBytes! + (expectedCompressedBytes ?? 0);

  static String? _megabytes(int? bytes) =>
      bytes == null ? null : '${(bytes / (1024 * 1024)).round()} MB';
}

/// Install state of a pack on this device.
enum LanguagePackStatus {
  /// Requires a download that hasn't happened (or was removed).
  notInstalled,

  /// Downloading / decompressing / writing right now.
  installing,

  /// Transfer checkpoint saved; re-enter installation to resume.
  paused,

  /// Present and usable offline.
  installed,

  /// The last install attempt failed; [LanguagePackState.error] says why.
  failed,
}

/// Observable per-pack state exposed by `LanguagePackService`.
@immutable
class LanguagePackState {
  final LanguagePack pack;
  final LanguagePackStatus status;

  /// 0.0–1.0 while [status] is [LanguagePackStatus.installing].
  final double progress;

  /// Locale-independent step, translated by the listening widget.
  final LoadStatus message;

  /// Failure reason when [status] is [LanguagePackStatus.failed].
  final String? error;

  /// Whether the failure looks retryable (offline / server hiccup) as opposed
  /// to a corrupted or replaced file.
  final bool errorIsNetwork;

  /// The install did not fit. Rendered as a localized "needs N MB free"
  /// message instead of the raw error, because retrying changes nothing until
  /// the user frees space.
  final bool errorIsSpace;

  /// Bytes already downloaded and checkpointed for this pack, so a partly
  /// fetched pack can offer "Resume — 12 of 25 MB" instead of looking
  /// untouched. Null until [LanguagePackService.refresh] has looked.
  final int? cachedBytes;

  const LanguagePackState({
    required this.pack,
    required this.status,
    this.progress = 0.0,
    this.message = const LoadStatus(LoadStage.preparing),
    this.error,
    this.errorIsNetwork = false,
    this.errorIsSpace = false,
    this.cachedBytes,
  });

  /// A download that stopped part-way and can continue from disk.
  bool get isResumable =>
      !isInstalled && !isInstalling && (cachedBytes ?? 0) > 0;

  bool get isInstalled => status == LanguagePackStatus.installed;
  bool get isInstalling => status == LanguagePackStatus.installing;

  LanguagePackState copyWith({
    LanguagePackStatus? status,
    double? progress,
    LoadStatus? message,
    String? error,
    bool? errorIsNetwork,
    bool? errorIsSpace,
    int? cachedBytes,
    bool clearCachedBytes = false,
    bool clearError = false,
  }) {
    return LanguagePackState(
      pack: pack,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      error: clearError ? null : (error ?? this.error),
      errorIsNetwork: clearError ? false : (errorIsNetwork ?? this.errorIsNetwork),
      errorIsSpace: clearError ? false : (errorIsSpace ?? this.errorIsSpace),
      cachedBytes: clearCachedBytes ? null : (cachedBytes ?? this.cachedBytes),
    );
  }
}

/// THE registry. Add a language here and the rest of the app follows.
const Map<String, LanguagePack> kLanguagePacks = {
  'de': LanguagePack(
    code: 'de',
    nativeName: 'Deutsch',
    databaseName: 'grundwortschatz.db',
    // GPL-3.0 data (childLex-derived) → intentionally NOT bundled in store
    // binaries; downloaded once from the Hugging Face dataset instead.
    remoteUrl:
        'https://huggingface.co/datasets/cstr/grundwortschatz-voc-de/resolve/main/grundwortschatz.db.gz',
    // If the DE DB is rebuilt and re-uploaded, bump expectedCompressedBytes
    // and expectedDecompressedSha256 together. The sha256 is a soft check
    // (logged, not fatal — see db_remote.dart), so a forgotten bump degrades
    // gracefully instead of bricking the download.
    expectedCompressedBytes: 26619920,
    expectedCompressedSha256:
        'bb69f27418bbd65673474e2a2934ecba33395fcf838465169a42e8bfec8de86b',
    expectedDecompressedBytes: 156913664,
    expectedDecompressedSha256:
        'c66e3b49192694c00d7c2a171562ac8fe4f54c05d986adb0ebf276f141aa00df',
    licenseLabel: 'GPL-3.0-or-later',
    datasetUrl: 'https://huggingface.co/datasets/cstr/grundwortschatz-voc-de',
  ),
  'en': LanguagePack(
    code: 'en',
    nativeName: 'English',
    databaseName: 'grundwortschatz_en.db',
    assetPath: 'assets/grundwortschatz_en.db.gz',
    licenseLabel: 'CC BY-SA 4.0',
    datasetUrl: 'https://huggingface.co/datasets/cstr/grundwortschatz-voc-en',
  ),
};

/// The pack used when nothing is chosen yet, and the pack we fall back to when
/// a downloaded pack is unavailable. Must be a bundled pack so the fallback
/// can never itself need the network.
const String kFallbackLanguageCode = 'en';

/// Default learning language on a fresh install.
const String kDefaultLanguageCode = 'de';

LanguagePack? languagePackFor(String code) => kLanguagePacks[code];

/// Packs in a stable display order: the default language first, then the rest
/// alphabetically by code.
List<LanguagePack> get orderedLanguagePacks {
  final codes = kLanguagePacks.keys.toList()
    ..sort((a, b) {
      if (a == kDefaultLanguageCode) return -1;
      if (b == kDefaultLanguageCode) return 1;
      return a.compareTo(b);
    });
  return [for (final c in codes) kLanguagePacks[c]!];
}
