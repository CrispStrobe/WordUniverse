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
