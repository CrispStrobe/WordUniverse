// lib/core/services/db_platform/db_platform_web.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'db_digest_web.dart';
import 'db_gzip.dart';
import 'db_gzip_web.dart';
import 'db_schema.dart';
import 'db_revision.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'db_remote.dart';
import '../../models/load_status.dart';

@visibleForTesting
DatabaseFactory? webDatabaseFactoryOverride;

DatabaseFactory get _factory => webDatabaseFactoryOverride ?? databaseFactoryFfiWeb;

/// Decompresses and gates a pack, natively where the browser allows it.
///
/// The portable path is pure Dart and `compute()` is only a microtask on the
/// web, so it runs on the main thread: 60 s of gunzip and 190 s of SHA-256 for
/// the English pack, more for the German one. The browser does the same work
/// in about two seconds, so it is tried first and the Dart path is kept as the
/// fallback for browsers without the APIs — or without a secure context, where
/// crypto.subtle does not exist.
///
/// A bad payload throws from either path; only "this browser cannot" falls
/// back, so a gate is never skipped.
Future<List<int>> _decompress(DbGzipJob job) async {
  final watch = Stopwatch()..start();
  if (supportsNativeGzip) {
    try {
      final decoded = await decodeAndVerifyDbGzipNative(job);
      logGzipPath('browser gzip', watch.elapsedMilliseconds, decoded.length);
      return decoded;
    } catch (error) {
      if (!isNativeGzipUnavailable(error)) rethrow;
      if (kDebugMode) {
        debugPrint('[DB_WEB] native digest unavailable; using the Dart path');
      }
    }
  }
  final decoded = await compute(decodeAndVerifyDbGzip, job);
  logGzipPath('dart gzip', watch.elapsedMilliseconds, decoded.length);
  return decoded;
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
    // PHASE 1: Initialize Web FFI (0.0 - 0.10)
    onProgress?.call(0.0, const LoadStatus(LoadStage.webEngine));
    if (kDebugMode) debugPrint("[DB_WEB] 🌐 Initializing web FFI database...");

    final factory = _factory;
    final String webDbName = databaseName;

    // Never migrate from a readiness probe: this may require two full DB writes.
    if (!await factory.databaseExists(webDbName) && expectedDecompressedSha256 != null) {
      await adoptLegacyDatabase(
        factory: factory, destination: webDbName,
        candidates: legacyDatabaseNames, digest: expectedDecompressedSha256,
        // No streaming in the browser, so the whole artifact is buffered
        // either way — but the browser can hash it in under a second where
        // package:crypto needs minutes on the main thread (see
        // db_digest_web.dart). Falls back when crypto.subtle is unavailable.
        digestOf: (name) async {
          final bytes = await factory.readDatabaseBytes(name);
          return supportsNativeDigest
              ? await nativeSha256HexOfBytes(bytes)
              : await compute(databaseDigest, bytes);
        },
        copy: (source, staging) async => factory.writeDatabaseBytes(
            staging, await factory.readDatabaseBytes(source)),
        promote: (staging, target) async => factory.writeDatabaseBytes(
            target, await factory.readDatabaseBytes(staging)),
      );
    }

    // PHASE 2: Check if database already exists in IndexedDB (0.10 - 0.15)
    onProgress?.call(0.10, const LoadStatus(LoadStage.checkingDatabase));

    try {
      final existingDb = await openValidatedDictionary(factory, webDbName);
      onProgress?.call(1.0, const LoadStatus(LoadStage.databaseReady));
      return existingDb;
    } catch (e) {
      if (kDebugMode)
        debugPrint("[DB_WEB] No existing database or corrupted: $e");
      // Continue with extraction
      await factory.deleteDatabase(webDbName);
    }

    // PHASE 3: Obtain compressed bytes — download (GPL DE DB) or asset (0.15 - 0.55)
    final Uint8List compressedBytes;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      if (kDebugMode)
        debugPrint("[DB_WEB] Downloading database from: $remoteUrl");
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

    if (kDebugMode)
      debugPrint("[DB_WEB] Have $compressedSizeMB MB compressed data");
    onProgress?.call(0.55,
        LoadStatus(LoadStage.loadedCompressed, bytes: compressedBytes.length));

    // PHASE 4: Decompress (0.55 - 0.75) - THE LONG PART
    if (kDebugMode) debugPrint("[DB_WEB] Starting decompression...");
    onProgress?.call(0.60, const LoadStatus(LoadStage.decompressing));

    final stopwatch = Stopwatch()..start();
    final List<int> decompressedBytes;

    try {
      // The browser's own gzip and SHA-256 where they exist, the portable
      // Dart path otherwise — see _decompress and db_gzip_web.dart. gzip's
      // CRC-32 validates the payload either way, and the payload gates ride
      // along so the SHA pass is never a separate stall.
      final job = DbGzipJob(
        compressed: compressedBytes,
        expectedDecompressedBytes: expectedDecompressedBytes,
        expectedDecompressedSha256: expectedDecompressedSha256,
        requireSha256: expectedDecompressedSha256 != null ||
            (remoteUrl != null && remoteUrl.isNotEmpty &&
                DbDownloadController.sharedFor(remoteUrl).resumedWithoutValidator),
      );
      decompressedBytes = await _decompress(job);

      final decompressedSizeMB =
          (decompressedBytes.length / (1024 * 1024)).toStringAsFixed(1);
      if (kDebugMode)
        debugPrint(
            "[DB_WEB] Decompressed to $decompressedSizeMB MB in ${stopwatch.elapsedMilliseconds}ms");
      onProgress?.call(0.75,
          LoadStatus(LoadStage.decompressed, bytes: decompressedBytes.length));
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
    if (kDebugMode)
      debugPrint(
          "[DB_WEB] Converting to Uint8List and writing to virtual FS...");

    // CRITICAL: Web FFI requires Uint8List, not List<int>. The decoder already
    // returns one, so don't copy the whole database again to restate its type.
    final Uint8List uint8Bytes = decompressedBytes is Uint8List
        ? decompressedBytes
        : Uint8List.fromList(decompressedBytes);

    // Phase 2 removed any database already under this name, so staging a copy
    // guards nothing here — and with no rename on web it means shipping a whole
    // decompressed database to the worker and into IndexedDB twice, doubling
    // both the main-thread cost of the install and the storage it needs at its
    // peak. Write once and validate in place, deleting the bytes if they turn
    // out to be unusable so a failed install still leaves nothing behind.
    try {
      await factory.writeDatabaseBytes(webDbName, uint8Bytes);
      final candidate = await openValidatedDictionary(factory, webDbName);
      await candidate.close();
    } catch (e) {
      // Never let cleanup replace the real failure.
      try {
        await factory.deleteDatabase(webDbName);
      } catch (_) {}
      // Browsers surface a full/blocked store as a quota error; say so plainly
      // instead of "download failed".
      if (e.toString().toLowerCase().contains('quota')) {
        throw DbInsufficientSpaceException(requiredBytes: uint8Bytes.length);
      }
      rethrow;
    }
    if (kDebugMode) debugPrint("[DB_WEB] Database written to IndexedDB");
    onProgress?.call(0.90, const LoadStatus(LoadStage.savedBrowser));

    // PHASE 6: Open and verify (0.90 - 1.0)
    onProgress?.call(0.95, const LoadStatus(LoadStage.openingDatabase));
    if (kDebugMode) debugPrint("[DB_WEB] Opening database...");

    final db = await openValidatedDictionary(factory, webDbName);

    // Verify word count
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM words'),
    );

    if (kDebugMode)
      debugPrint("[DB_WEB] ✅ Database opened successfully with $count words");
    if (kDebugMode)
      debugPrint(
          "[DB_WEB] Total initialization time: ${stopwatch.elapsedMilliseconds}ms");

    onProgress?.call(
        1.0, LoadStatus(LoadStage.databaseReadyWords, count: count ?? 0));

    return db;
  } catch (e, stackTrace) {
    if (kDebugMode)
      debugPrint("[DB_WEB] ❌ Critical error during initialization: $e");
    if (kDebugMode) debugPrint("[DB_WEB] Stack trace: $stackTrace");
    onProgress?.call(0.0, const LoadStatus(LoadStage.failed));
    rethrow;
  }
}

/// See db_platform_interface.dart. Web: the pack is installed when the DB
/// opens out of the browser's virtual filesystem with a non-empty `words`
/// table. Anything else (missing, cleared site data, corrupted) counts as not
/// installed so the caller re-downloads.
Future<bool> isPlatformDatabaseInstalled(String databaseName, {
  List<String> legacyDatabaseNames = const [],
  String? expectedDecompressedSha256,
}) async {
  try {
    final factory = _factory;
    if (!await factory.databaseExists(databaseName)) {
      return false;
    }
    final db = await openValidatedDictionary(factory, databaseName);
    await db.close();
    return true;
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
    await _factory.deleteDatabase(databaseName);
    if (kDebugMode) debugPrint("[DB_WEB] 🗑️ Deleted database $databaseName");
  } catch (e) {
    if (kDebugMode)
      debugPrint("[DB_WEB] ⚠️ Could not delete $databaseName: $e");
    rethrow;
  }
}
