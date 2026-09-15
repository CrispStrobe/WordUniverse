// lib/core/services/db_platform/db_platform_interface.dart

import 'package:sqflite/sqflite.dart';

/// Platform-specific database initialization interface
///
/// The compressed DB is obtained from either a bundled asset ([assetPath]) or,
/// when [remoteUrl] is non-null, downloaded on first launch and cached (used
/// for the GPL-3.0 German DB, which is intentionally not bundled — see
/// db_remote.dart). The `expected*` values drive integrity checks.
///
/// [onProgress] optional callback for progress updates
///   - progress: 0.0 to 1.0
///   - message: descriptive status message
Future<Database> initPlatformDatabase({
  required String assetPath,
  required String databaseName,
  String? remoteUrl,
  int? expectedCompressedBytes,
  int? expectedDecompressedBytes,
  String? expectedDecompressedSha256,
  void Function(double progress, String message)? onProgress,
}) {
  throw UnsupportedError(
    'Cannot init database: Unknown platform. '
    'Ensure conditional imports are configured correctly.',
  );
}

/// Whether [databaseName] is already present and usable on this device, i.e.
/// whether a downloaded language pack still needs fetching. Authoritative:
/// it inspects real storage rather than a preference flag, so a cleared app
/// container or wiped browser storage is detected.
Future<bool> isPlatformDatabaseInstalled(String databaseName) {
  throw UnsupportedError(
    'Cannot query database: Unknown platform. '
    'Ensure conditional imports are configured correctly.',
  );
}

/// Deletes the cached copy of [databaseName], freeing its storage. Used when
/// the user removes a downloaded language pack. A no-op when nothing is
/// cached.
Future<void> deletePlatformDatabase(String databaseName) {
  throw UnsupportedError(
    'Cannot delete database: Unknown platform. '
    'Ensure conditional imports are configured correctly.',
  );
}
