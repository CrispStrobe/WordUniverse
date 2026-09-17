// lib/core/services/db_platform/db_platform_web.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'db_gzip.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'db_remote.dart';
import '../../models/load_status.dart';


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
    // PHASE 1: Initialize Web FFI (0.0 - 0.10)
    onProgress?.call(0.0, const LoadStatus(LoadStage.webEngine));
    if (kDebugMode) debugPrint("[DB_WEB] 🌐 Initializing web FFI database...");

    var factory = databaseFactoryFfiWeb;
    final String webDbName = databaseName;

    // PHASE 2: Check if database already exists in IndexedDB (0.10 - 0.15)
    onProgress?.call(0.10, const LoadStatus(LoadStage.checkingDatabase));

    try {
      // Try to open existing database
      final existingDb = await factory.openDatabase(
        webDbName,
        options: OpenDatabaseOptions(readOnly: true),
      );

      // Verify it's valid
      final count = Sqflite.firstIntValue(
        await existingDb.rawQuery('SELECT COUNT(*) FROM words LIMIT 1'),
      );

      if (count != null && count > 0) {
        if (kDebugMode) debugPrint("[DB_WEB] ✅ Using existing database with $count words");
        onProgress?.call(1.0, const LoadStatus(LoadStage.databaseReady));
        return existingDb;
      }

      await existingDb.close();
      if (kDebugMode) debugPrint("[DB_WEB] Existing database is invalid, will re-extract");
      await factory.deleteDatabase(webDbName);
    } catch (e) {
      if (kDebugMode) debugPrint("[DB_WEB] No existing database or corrupted: $e");
      // Continue with extraction
    }

    // PHASE 3: Obtain compressed bytes — download (GPL DE DB) or asset (0.15 - 0.55)
    final Uint8List compressedBytes;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      if (kDebugMode) debugPrint("[DB_WEB] Downloading database from: $remoteUrl");
      // http 1.6 streams browser fetch responses; the shared transport also
      // aborts fetch on pause and checkpoints compressed bytes in IndexedDB.
      compressedBytes = await downloadCompressedDb(
        url: remoteUrl,
        expectedCompressedBytes: expectedCompressedBytes,
        onProgress: (p, m) => onProgress?.call(0.15 + p * 0.40, m),
      );
    } else {
      onProgress?.call(0.15, const LoadStatus(LoadStage.loadingCompressed));
      if (kDebugMode) debugPrint("[DB_WEB] Loading compressed asset...");
      final ByteData data = await rootBundle.load(assetPath);
      compressedBytes = data.buffer.asUint8List();
    }
    final compressedSizeMB =
        (compressedBytes.length / (1024 * 1024)).toStringAsFixed(1);

    if (kDebugMode) debugPrint("[DB_WEB] Have $compressedSizeMB MB compressed data");
    onProgress?.call(0.55, LoadStatus(LoadStage.loadedCompressed, bytes: compressedBytes.length));

    // PHASE 4: Decompress (0.55 - 0.75) - THE LONG PART
    if (kDebugMode) debugPrint("[DB_WEB] Starting decompression...");
    onProgress?.call(0.60, const LoadStatus(LoadStage.decompressing));

    final stopwatch = Stopwatch()..start();
    final List<int> decompressedBytes;

    try {
      // compute() routes through an isolate on mobile/desktop and through a
      // microtask on web; either way the prior progress update has a chance
      // to paint before this long sync call. gzip's CRC-32 validates the
      // payload — a corrupt download throws here. The payload gates ride along
      // so the SHA pass is never a separate UI-thread stall.
      decompressedBytes = await compute(
        decodeAndVerifyDbGzip,
        DbGzipJob(
          compressed: compressedBytes,
          expectedDecompressedBytes: expectedDecompressedBytes,
          expectedDecompressedSha256: expectedDecompressedSha256,
          requireSha256: remoteUrl != null &&
              remoteUrl.isNotEmpty &&
              DbDownloadController.sharedFor(remoteUrl)
                  .resumedWithoutValidator,
        ),
      );

      final decompressedSizeMB =
          (decompressedBytes.length / (1024 * 1024)).toStringAsFixed(1);
      if (kDebugMode) debugPrint(
          "[DB_WEB] Decompressed to $decompressedSizeMB MB in ${stopwatch.elapsedMilliseconds}ms");
      onProgress?.call(0.75, LoadStatus(LoadStage.decompressed, bytes: decompressedBytes.length));
    } on DbPayloadException catch (e) {
      // A payload gate (size or an enforced checksum) already says exactly
      // what was wrong; don't flatten it into "decompression failed".
      if (kDebugMode) debugPrint("[DB_WEB] ❌ Payload gate: ${e.message}");
      onProgress?.call(0.0, const LoadStatus(LoadStage.decompressionFailed));
      throw DbDownloadException(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint("[DB_WEB] ❌ Decompression error: $e");
      onProgress?.call(0.0, const LoadStatus(LoadStage.decompressionFailed));
      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        throw DbDownloadException(
          'The downloaded database was corrupted (decompression failed). '
          'Please check your connection and try again.',
        );
      }
      rethrow;
    }

    // PHASE 5: Convert to Uint8List and write to IndexedDB (0.75 - 0.90)
    onProgress?.call(0.80, const LoadStatus(LoadStage.writingBrowserStorage));
    if (kDebugMode) debugPrint("[DB_WEB] Converting to Uint8List and writing to virtual FS...");

    // CRITICAL: Web FFI requires Uint8List, not List<int>
    final Uint8List uint8Bytes = Uint8List.fromList(decompressedBytes);

    await factory.writeDatabaseBytes(webDbName, uint8Bytes);
    if (kDebugMode) debugPrint("[DB_WEB] Database written to IndexedDB");
    onProgress?.call(0.90, const LoadStatus(LoadStage.savedBrowser));

    // PHASE 6: Open and verify (0.90 - 1.0)
    onProgress?.call(0.95, const LoadStatus(LoadStage.openingDatabase));
    if (kDebugMode) debugPrint("[DB_WEB] Opening database...");

    final db = await factory.openDatabase(
      webDbName,
      options: OpenDatabaseOptions(readOnly: true),
    );

    // Verify word count
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM words'),
    );

    if (kDebugMode) debugPrint("[DB_WEB] ✅ Database opened successfully with $count words");
    if (kDebugMode) debugPrint(
        "[DB_WEB] Total initialization time: ${stopwatch.elapsedMilliseconds}ms");

    onProgress?.call(1.0, LoadStatus(LoadStage.databaseReadyWords, count: count ?? 0));

    return db;
  } catch (e, stackTrace) {
    if (kDebugMode) debugPrint("[DB_WEB] ❌ Critical error during initialization: $e");
    if (kDebugMode) debugPrint("[DB_WEB] Stack trace: $stackTrace");
    onProgress?.call(0.0, const LoadStatus(LoadStage.failed));
    rethrow;
  }
}

/// See db_platform_interface.dart. Web: the pack is installed when the DB
/// opens out of the browser's virtual filesystem with a non-empty `words`
/// table. Anything else (missing, cleared site data, corrupted) counts as not
/// installed so the caller re-downloads.
Future<bool> isPlatformDatabaseInstalled(String databaseName) async {
  try {
    final factory = databaseFactoryFfiWeb;
    final db = await factory.openDatabase(
      databaseName,
      options: OpenDatabaseOptions(readOnly: true),
    );
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
      debugPrint("[DB_WEB] Install check failed for $databaseName: $e");
    }
    return false;
  }
}

/// See db_platform_interface.dart.
Future<void> deletePlatformDatabase(String databaseName) async {
  try {
    await databaseFactoryFfiWeb.deleteDatabase(databaseName);
    if (kDebugMode) debugPrint("[DB_WEB] 🗑️ Deleted database $databaseName");
  } catch (e) {
    if (kDebugMode) debugPrint("[DB_WEB] ⚠️ Could not delete $databaseName: $e");
    rethrow;
  }
}
