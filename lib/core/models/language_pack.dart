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

  final String _databaseName;

  /// Content-qualified identity, independent of SQLite schema compatibility.
  /// Changing the packaged digest automatically selects a fresh storage slot.
  String get databaseName => expectedDecompressedSha256 == null
      ? _databaseName
      : '${_databaseName.substring(0, _databaseName.length - 3)}-$expectedDecompressedSha256.db';

  /// Historical slots are retained, never silently treated as this revision.
  /// Keep earlier qualified names here when publishing a replacement.
  final List<String> previousDatabaseNames;
  List<String> get legacyDatabaseNames =>
      [_databaseName, ...previousDatabaseNames];

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
    required String databaseName,
    this.previousDatabaseNames = const [],
    required this.licenseLabel,
    this.assetPath,
    this.remoteUrl,
    this.expectedCompressedBytes,
    this.expectedCompressedSha256,
    this.expectedDecompressedBytes,
    this.expectedDecompressedSha256,
    this.datasetUrl,
  }) : _databaseName = databaseName;

  /// True when the pack has to be fetched over the network before it can be
  /// used. Bundled packs are usable immediately.
  bool get requiresDownload => remoteUrl != null && remoteUrl!.isNotEmpty;

  /// True when the pack ships inside the binary.
  bool get isBundled => assetPath != null && assetPath!.isNotEmpty;

  /// Download size for disclosure, e.g. "25 MB". Falls back to an estimate
  /// when no pin is set.
  String get downloadSizeLabel =>
      _megabytes(expectedCompressedBytes) ?? '~25 MB';

  /// What the pack occupies once installed, which is what actually has to fit
  /// on the device: the database is stored decompressed. Disclosing only the
  /// download size understates the requirement by roughly six times.
  String? get installedSizeLabel => _megabytes(expectedDecompressedBytes);

  /// Conservative peak storage budget, not the final footprint or RAM usage.
  /// Use binary units here because the budget is divided by 1024 squared.
  String? get requiredFreeSizeLabel => requiredFreeBytes == null
      ? null
      : '${(requiredFreeBytes! / (1024 * 1024)).round()} MiB';

  /// One decompressed database on either platform: web writes it to its final
  /// name and validates it in place (pinned by "web install writes the database
  /// once" in db_schema_web_test.dart), native writes one staging file and
  /// renames it. Decode buffers are RAM, not an additional free-space
  /// requirement.
  ///
  /// Reserve one compressed download in addition on both platforms. The shared
  /// downloader clears its checkpoint before returning, so this is conservative
  /// headroom, NOT a second file known to coexist with the database. It also
  /// covers checkpoint replacement for the registered pack (much smaller than
  /// its decompressed DB). Filesystem/IndexedDB overhead is platform-dependent.
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
      errorIsNetwork:
          clearError ? false : (errorIsNetwork ?? this.errorIsNetwork),
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
    // The runtime artifact, not the full dataset: the same database with the
    // enrichment the app never reads stripped (tools/pack/slim_pack.py),
    // 149.6 MB -> 83.1 MB, then repaired (tools/pack/repair_pack.py) so that
    // 33 place and person names are typed proper_noun and 122 entries lead
    // with a meaning rather than a parse, and it carries the feature index
    // the app would otherwise derive on first launch
    // (tools/pack/index_pack.sh): 146 KB of download for three seconds of
    // work on every install. `grundwortschatz.db.gz` beside it
    // remains the complete lexical database and is unchanged.
    remoteUrl:
        'https://huggingface.co/datasets/cstr/grundwortschatz-voc-de/resolve/2cba9fdd4bf11c56a5879a960567ac80ffd2d4a3/grundwortschatz-app.db.gz',
    // Update the immutable URL and all pins together; retain this qualified
    // databaseName in previousDatabaseNames when publishing a new artifact.
    expectedCompressedBytes: 15081318,
    expectedCompressedSha256:
        '95454d488cec9f8a9e711c970757e39b76da99686c14b3649ef2768a3d0f3650',
    expectedDecompressedBytes: 88072192,
    expectedDecompressedSha256:
        '85bfe359b428cd8ccf354c589363027909fa05ca3fed5bdd45a93b68372478c1',
    previousDatabaseNames: [
      'grundwortschatz-158bea51ba1b0c0e4bcb696042dd45a03b0ddbccc132337a8ce8ef388117d9f1.db',
      'grundwortschatz-32487bb8280cc5a709abf83119482fe68c84be3ee47aa1251f1aabb494801712.db',
      'grundwortschatz-4088731ba18bb477bbf41faacc633beedc967b5e5e7108a89c75c62d87b5aca1.db',
      'grundwortschatz-2890e0c1b1dd25aacaee53bb133f4a4b3c4e69acb5827ce4c1af1813a2a7af44.db',
      'grundwortschatz-c66e3b49192694c00d7c2a171562ac8fe4f54c05d986adb0ebf276f141aa00df.db',
      'grundwortschatz-1c87cbeed45007e7d61c4f73010c79804478eebf97c61487f806a2789dd6949a.db',
    ],
    licenseLabel: 'GPL-3.0-or-later',
    datasetUrl: 'https://huggingface.co/datasets/cstr/grundwortschatz-voc-de',
  ),
  'en': LanguagePack(
    code: 'en',
    nativeName: 'English',
    databaseName: 'grundwortschatz_en.db',
    assetPath: 'assets/grundwortschatz_en.db.gz',
    // Slimmed 2026-09-18: enrichment no code path reads was stripped from the
    // artifact (tools/pack/slim_pack.py), 93.9 MB -> 58.3 MB decompressed.
    // Repaired 2026-09-20 (tools/pack/repair_pack.py): 853 recorded
    // misspellings marked as such, 620 names typed proper_noun — London,
    // Texas, Canada and Isaac all arrived as ordinary nouns — and 141
    // entries whose leading gloss was a parse or a label had it dropped so a
    // real meaning leads, and carries the feature index the app would
    // otherwise derive on first launch (tools/pack/index_pack.sh): 94 KB of
    // download for three seconds of work on every install. The digest
    // qualifies the storage slot, so this selects a fresh one and the
    // previous slots are listed below rather than silently reused.
    expectedDecompressedSha256:
        '3d2201f21098d96af2864961cb21b065d41f0171022aa53abeea81a96ccc5a1d',
    previousDatabaseNames: [
      'grundwortschatz_en-53365e2ae71884bad1e53b5e34c2cdc543f0f9ba8ba578eca7eb5050235c76d9.db',
      'grundwortschatz_en-cbbdef45fb1b2da6726ada0f98071c5ff622f4fa3903bf13fdf9d5f4f8d2f365.db',
      'grundwortschatz_en-7c810a70430f5e2218e8ef15b91cdf52bb20224afad4963ea6c200e47c0b840d.db',
      'grundwortschatz_en-49e65596954cb7f8a0268e214e3e26c866f593ad781c567481993f08dc8471db.db',
      'grundwortschatz_en-367021742f6c3ae6a3c347a9ef25f162683fb40c8e983f290c6e9667b6216893.db',
    ],
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
