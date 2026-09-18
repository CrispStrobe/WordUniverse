// lib/core/services/db_platform/db_platform_mobile.dart

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'db_gzip.dart';
import 'db_schema.dart';
import 'db_revision.dart';
import 'db_remote.dart';
import '../../models/load_status.dart';

/// How adoption reads a legacy artifact.
///
/// Adoption must stream: a ~150 MB pack must never be buffered on a device that
/// is merely upgrading. "Streaming" is only observable from the outside as the
/// size of the reads that reach the hash and the copy, so tests watch those
/// reads through [adoptionReadObserver] — process memory is not a portable
/// proxy for it (allocator behaviour, GC timing and SQLite's page cache all
/// land in RSS).
///
/// The observer only watches: the production read path is the same with it
/// installed or not, so a test cannot accidentally assert on its own reader.
@visibleForTesting
void Function(int chunkBytes)? adoptionReadObserver;

Stream<List<int>> _readFileStreamed(String path) {
  final stream = File(path).openRead();
  final observer = adoptionReadObserver;
  if (observer == null) return stream;
  return stream.map((chunk) {
    observer(chunk.length);
    return chunk;
  });
}

Future<Database> initPlatformDatabase({
  required String assetPath,
  required String databaseName,
  List<String> legacyDatabaseNames = const [],
  String? remoteUrl,
  int? expectedCompressedBytes,
  int? expectedDecompressedBytes,
  String? expectedDecompressedSha256,
  LoadProgress? onProgress,
}) async {
  try {
    // PHASE 1: Determine database path (0.0 - 0.05)
    onProgress?.call(0.0, const LoadStatus(LoadStage.locatingStorage));
    if (kDebugMode)
      debugPrint("[DB_MOBILE] 📱 Initializing mobile/desktop database...");

    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, databaseName);
    final File dbFile = File(path);

    // Adoption belongs to explicit initialization, after consent/quota checks.
    // Readiness probes must never allocate/copy a full artifact or touch staging.
    if (!await dbFile.exists() && expectedDecompressedSha256 != null) {
      await adoptLegacyDatabase(
        factory: databaseFactory, destination: path,
        candidates: [for (final name in legacyDatabaseNames) join(documentsDirectory.path, name)],
        digest: expectedDecompressedSha256,
        // Streamed: a ~150 MB artifact must never be buffered, let alone
        // copied into an isolate, on a device that is merely upgrading.
        digestOf: (name) async =>
            (await sha256.bind(_readFileStreamed(name)).first).toString(),
        copy: (source, staging) async {
          final sink = File(staging).openWrite();
          try {
            await _readFileStreamed(source).pipe(sink);
          } finally {
            await sink.close();
          }
        },
        promote: (staging, target) async { await File(staging).rename(target); },
      );
    }

    // PHASE 2: Check if database already exists and is valid (0.05 - 0.10)
    if (await dbFile.exists()) {
      onProgress?.call(0.05, const LoadStatus(LoadStage.checkingDatabase));
      if (kDebugMode) debugPrint("[DB_MOBILE] Database file exists at: $path");

      try {
        final db = await openValidatedDictionary(databaseFactory, path);
        onProgress?.call(1.0, const LoadStatus(LoadStage.databaseReady));
        return db;
      } catch (e) {
        if (kDebugMode)
          debugPrint("[DB_MOBILE] ⚠️ Existing database is corrupted: $e");
        // Try to delete corrupted database
        try {
          await dbFile.delete();
        } catch (deleteError) {
          if (kDebugMode)
            debugPrint(
                "[DB_MOBILE] Could not delete corrupted database: $deleteError");
        }
      }
    }

    // PHASE 3: Extract database from assets (0.10 - 1.0)
    if (kDebugMode)
      debugPrint("[DB_MOBILE] Extracting database from assets...");

    // Ensure directory exists
    onProgress?.call(0.10, const LoadStatus(LoadStage.preparingStorage));
    await Directory(dirname(path)).create(recursive: true);

    // PHASE 4: Obtain compressed bytes — download (GPL DE DB) or asset (0.10 - 0.55)
    final Uint8List compressedBytes;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      if (kDebugMode)
        debugPrint("[DB_MOBILE] Downloading database from: $remoteUrl");
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

    if (kDebugMode)
      debugPrint("[DB_MOBILE] Have $compressedSizeMB MB compressed data");
    onProgress?.call(0.55,
        LoadStatus(LoadStage.loadedCompressed, bytes: compressedBytes.length));

    // PHASE 5: Decompress (0.55 - 0.80) - THIS IS THE LONG PART
    if (kDebugMode)
      debugPrint("[DB_MOBILE] Starting decompression on background isolate...");
    onProgress?.call(0.60, const LoadStatus(LoadStage.decompressing));

    final stopwatch = Stopwatch()..start();
    final List<int> decompressedBytes;
    try {
      // Offload decode AND the payload gates to a background isolate so the
      // splash animation keeps running through the ~150MB decompression, and
      // so nothing hashes 150MB on the UI thread for an advisory check.
      // gzip's CRC-32 trailer validates the payload here — a corrupt/truncated
      // download throws instead of yielding garbage.
      decompressedBytes = await compute(
        decodeAndVerifyDbGzip,
        DbGzipJob(
          compressed: compressedBytes,
          expectedDecompressedBytes: expectedDecompressedBytes,
          expectedDecompressedSha256: expectedDecompressedSha256,
          requireSha256: expectedDecompressedSha256 != null ||
              (remoteUrl != null && remoteUrl.isNotEmpty &&
                  DbDownloadController.sharedFor(remoteUrl).resumedWithoutValidator),
        ),
      );

      final decompressedSizeMB =
          (decompressedBytes.length / (1024 * 1024)).toStringAsFixed(1);
      if (kDebugMode)
        debugPrint(
            "[DB_MOBILE] Decompressed to $decompressedSizeMB MB in ${stopwatch.elapsedMilliseconds}ms");
      onProgress?.call(0.80,
          LoadStatus(LoadStage.decompressed, bytes: decompressedBytes.length));
    } on DbPayloadException catch (e) {
      // A payload gate (size or an enforced checksum) already says exactly
      // what was wrong; don't flatten it into "decompression failed".
      if (kDebugMode) debugPrint("[DB_MOBILE] ❌ Payload gate: ${e.message}");
      onProgress?.call(0.0, const LoadStatus(LoadStage.decompressionFailed));
      throw DbDownloadException(e.message);
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

    // PHASE 6: Write to disk (0.80 - 0.90)
    onProgress?.call(0.85, const LoadStatus(LoadStage.writingStorage));
    if (kDebugMode) debugPrint("[DB_MOBILE] Writing database to: $path");

    final staging = File('$path.installing');
    try {
      await staging.writeAsBytes(decompressedBytes, flush: true);
      final candidate =
          await openValidatedDictionary(databaseFactory, staging.path);
      await candidate.close();
      await staging.rename(path);
    } on FileSystemException catch (e) {
      // ENOSPC (28 on Android/iOS/Linux). Native has no reliable pre-check, so
      // this is where a full device becomes a message the user can act on.
      if (e.osError?.errorCode == 28 ||
          (e.osError?.message ?? '').toLowerCase().contains('no space')) {
        // Don't leave a truncated database behind to be opened later.
        try {
          if (await dbFile.exists()) await dbFile.delete();
        } catch (_) {}
        throw DbInsufficientSpaceException(
            requiredBytes: decompressedBytes.length);
      }
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete();
    }
    if (kDebugMode) debugPrint("[DB_MOBILE] Database written successfully");
    onProgress?.call(0.90, const LoadStatus(LoadStage.savedDisk));

    // PHASE 7: Open and verify (0.90 - 1.0)
    onProgress?.call(0.95, const LoadStatus(LoadStage.openingDatabase));
    if (kDebugMode) debugPrint("[DB_MOBILE] Opening database...");

    final db = await openValidatedDictionary(databaseFactory, path);
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM words'),
    );

    if (kDebugMode)
      debugPrint(
          "[DB_MOBILE] ✅ Database opened successfully with $count words");
    if (kDebugMode)
      debugPrint(
          "[DB_MOBILE] Total initialization time: ${stopwatch.elapsedMilliseconds}ms");

    onProgress?.call(
        1.0, LoadStatus(LoadStage.databaseReadyWords, count: count ?? 0));

    return db;
  } catch (e, stackTrace) {
    if (kDebugMode)
      debugPrint("[DB_MOBILE] ❌ Critical error during initialization: $e");
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
Future<bool> isPlatformDatabaseInstalled(String databaseName, {
  List<String> legacyDatabaseNames = const [],
  String? expectedDecompressedSha256,
}) async {
  try {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, databaseName);
    if (!await File(path).exists()) {
      return false;
    }

    final db = await openValidatedDictionary(databaseFactory, path);
    await db.close();
    return true;
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
    if (kDebugMode)
      debugPrint("[DB_MOBILE] 🗑️ Deleted database $databaseName");
  } catch (e) {
    if (kDebugMode) {
      debugPrint("[DB_MOBILE] ⚠️ Could not delete $databaseName: $e");
    }
    rethrow;
  }
}
