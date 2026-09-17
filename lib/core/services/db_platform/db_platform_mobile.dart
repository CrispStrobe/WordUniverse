// lib/core/services/db_platform/db_platform_mobile.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'db_gzip.dart';
import 'db_remote.dart';
import '../../models/load_status.dart';

/// Top-level entry point for [compute]. Runs in a background isolate so the
/// ~25MB gzip → ~150MB decompression doesn't block the UI thread.
List<int> _decodeGzipBytes(Uint8List bytes) {
  return decodeDbGzip(bytes);
}

Future<Database> initPlatformDatabase({
  required String assetPath,
  required String databaseName,
  String? remoteUrl,
  int? expectedCompressedBytes,
  int? expectedDecompressedBytes,
  String? expectedDecompressedSha256,
  LoadProgress? onProgress,
}) async {
  try {
    // PHASE 1: Determine database path (0.0 - 0.05)
    onProgress?.call(0.0, const LoadStatus(LoadStage.locatingStorage));
    if (kDebugMode) debugPrint("[DB_MOBILE] 📱 Initializing mobile/desktop database...");

    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, databaseName);
    final File dbFile = File(path);

    // PHASE 2: Check if database already exists and is valid (0.05 - 0.10)
    if (await dbFile.exists()) {
      onProgress?.call(0.05, const LoadStatus(LoadStage.checkingDatabase));
      if (kDebugMode) debugPrint("[DB_MOBILE] Database file exists at: $path");

      try {
        // Quick validation - try to open and query
        final db = await openDatabase(path, readOnly: true);
        final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM words LIMIT 1'),
        );

        if (count != null && count > 0) {
          if (kDebugMode) debugPrint(
              "[DB_MOBILE] ✅ Using existing valid database with $count words");
          onProgress?.call(1.0, const LoadStatus(LoadStage.databaseReady));
          return db;
        }

        // If we got here, database exists but is empty/invalid
        await db.close();
        if (kDebugMode) debugPrint(
            "[DB_MOBILE] ⚠️ Existing database is invalid, will re-extract");
        await dbFile.delete();
      } catch (e) {
        if (kDebugMode) debugPrint("[DB_MOBILE] ⚠️ Existing database is corrupted: $e");
        // Try to delete corrupted database
        try {
          await dbFile.delete();
        } catch (deleteError) {
          if (kDebugMode) debugPrint(
              "[DB_MOBILE] Could not delete corrupted database: $deleteError");
        }
      }
    }

    // PHASE 3: Extract database from assets (0.10 - 1.0)
    if (kDebugMode) debugPrint("[DB_MOBILE] Extracting database from assets...");

    // Ensure directory exists
    onProgress?.call(0.10, const LoadStatus(LoadStage.preparingStorage));
    await Directory(dirname(path)).create(recursive: true);

    // PHASE 4: Obtain compressed bytes — download (GPL DE DB) or asset (0.10 - 0.55)
    final Uint8List compressedBytes;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      if (kDebugMode) debugPrint("[DB_MOBILE] Downloading database from: $remoteUrl");
      compressedBytes = await downloadCompressedDb(
        url: remoteUrl,
        expectedCompressedBytes: expectedCompressedBytes,
        // Download occupies the bulk of first-launch time → map to 0.10-0.55.
        onProgress: (p, m) => onProgress?.call(0.10 + p * 0.45, m),
      );
    } else {
      onProgress?.call(0.15, const LoadStatus(LoadStage.loadingCompressed));
      final ByteData data = await rootBundle.load(assetPath);
      compressedBytes = data.buffer.asUint8List();
    }
    final compressedSizeMB =
        (compressedBytes.length / (1024 * 1024)).toStringAsFixed(1);

    if (kDebugMode) debugPrint("[DB_MOBILE] Have $compressedSizeMB MB compressed data");
    onProgress?.call(0.55, LoadStatus(LoadStage.loadedCompressed, bytes: compressedBytes.length));

    // PHASE 5: Decompress (0.55 - 0.80) - THIS IS THE LONG PART
    if (kDebugMode) debugPrint("[DB_MOBILE] Starting decompression on background isolate...");
    onProgress?.call(0.60, const LoadStatus(LoadStage.decompressing));

    final stopwatch = Stopwatch()..start();
    final List<int> decompressedBytes;
    try {
      // Offload sync gzip decode to a background isolate so the splash
      // animation keeps running smoothly during the ~150MB decompression.
      // gzip's CRC-32 trailer validates the payload here — a corrupt/truncated
      // download throws instead of yielding garbage.
      decompressedBytes = await compute(_decodeGzipBytes, compressedBytes);

      final decompressedSizeMB =
          (decompressedBytes.length / (1024 * 1024)).toStringAsFixed(1);
      if (kDebugMode) debugPrint(
          "[DB_MOBILE] Decompressed to $decompressedSizeMB MB in ${stopwatch.elapsedMilliseconds}ms");
      onProgress?.call(0.80, LoadStatus(LoadStage.decompressed, bytes: decompressedBytes.length));
    } catch (e) {
      if (kDebugMode) debugPrint("[DB_MOBILE] ❌ Decompression error: $e");
      onProgress?.call(0.0, const LoadStatus(LoadStage.decompressionFailed));
      // A failed gzip decode on a downloaded file means corruption.
      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        throw DbDownloadException(
          'The downloaded database was corrupted (decompression failed). '
          'Please check your connection and try again.',
        );
      }
      rethrow;
    }

    // Integrity gate over the decompressed bytes (hard size; soft sha256).
    verifyDecompressedDb(
      decompressedBytes,
      expectedDecompressedBytes: expectedDecompressedBytes,
      expectedDecompressedSha256: expectedDecompressedSha256,
    );

    // PHASE 6: Write to disk (0.80 - 0.90)
    onProgress?.call(0.85, const LoadStatus(LoadStage.writingStorage));
    if (kDebugMode) debugPrint("[DB_MOBILE] Writing database to: $path");

    await dbFile.writeAsBytes(decompressedBytes, flush: true);
    if (kDebugMode) debugPrint("[DB_MOBILE] Database written successfully");
    onProgress?.call(0.90, const LoadStatus(LoadStage.savedDisk));

    // PHASE 7: Open and verify (0.90 - 1.0)
    onProgress?.call(0.95, const LoadStatus(LoadStage.openingDatabase));
    if (kDebugMode) debugPrint("[DB_MOBILE] Opening database...");

    final db = await openDatabase(path, readOnly: true);

    // Verify word count
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM words'),
    );

    if (kDebugMode) debugPrint("[DB_MOBILE] ✅ Database opened successfully with $count words");
    if (kDebugMode) debugPrint(
        "[DB_MOBILE] Total initialization time: ${stopwatch.elapsedMilliseconds}ms");

    onProgress?.call(1.0, LoadStatus(LoadStage.databaseReadyWords, count: count ?? 0));

    return db;
  } catch (e, stackTrace) {
    if (kDebugMode) debugPrint("[DB_MOBILE] ❌ Critical error during initialization: $e");
    if (kDebugMode) debugPrint("[DB_MOBILE] Stack trace: $stackTrace");
    onProgress?.call(0.0, const LoadStatus(LoadStage.failed));
    rethrow;
  }
}

/// See db_platform_interface.dart. Mobile/desktop: the pack is installed when
/// the SQLite file exists and opens with a non-empty `words` table. A file
/// that exists but fails to open (truncated download, corrupted container) is
/// reported as *not* installed so the caller re-downloads instead of crashing
/// later inside a game.
Future<bool> isPlatformDatabaseInstalled(String databaseName) async {
  try {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, databaseName);
    if (!await File(path).exists()) return false;

    final db = await openDatabase(path, readOnly: true);
    try {
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM words LIMIT 1'),
      );
      return count != null && count > 0;
    } finally {
      await db.close();
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint("[DB_MOBILE] Install check failed for $databaseName: $e");
    }
    return false;
  }
}

/// See db_platform_interface.dart.
Future<void> deletePlatformDatabase(String databaseName) async {
  try {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, databaseName);
    // Drop sqflite's journal/WAL siblings too, or a stale -wal can resurrect
    // a partially valid DB on the next open.
    for (final suffix in const ['', '-journal', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
    if (kDebugMode) debugPrint("[DB_MOBILE] 🗑️ Deleted database $databaseName");
  } catch (e) {
    if (kDebugMode) {
      debugPrint("[DB_MOBILE] ⚠️ Could not delete $databaseName: $e");
    }
    rethrow;
  }
}
