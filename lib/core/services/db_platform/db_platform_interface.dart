// lib/core/services/db_platform/db_platform_interface.dart

import 'package:sqflite/sqflite.dart';

/// Platform-specific database initialization interface
/// 
/// [onProgress] optional callback for progress updates
///   - progress: 0.0 to 1.0
///   - message: descriptive status message
Future<Database> initPlatformDatabase({
  void Function(double progress, String message)? onProgress,
}) {
  throw UnsupportedError(
    'Cannot init database: Unknown platform. '
    'Ensure conditional imports are configured correctly.',
  );
}