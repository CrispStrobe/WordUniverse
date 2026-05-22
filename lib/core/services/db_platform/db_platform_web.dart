// lib/core/services/db_platform/db_platform_web.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:archive/archive_io.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Top-level entry point passed to [compute]. On mobile/desktop this runs in
/// a background isolate; on web `compute` falls back to the main thread but
/// at least defers the call to a microtask so prior progress UI can flush.
List<int> _decodeGzipBytes(Uint8List bytes) {
  return GZipDecoder().decodeBytes(bytes);
}

Future<Database> initPlatformDatabase({
  required String assetPath,
  required String databaseName,
  void Function(double progress, String message)? onProgress,
}) async {
  try {
    // PHASE 1: Initialize Web FFI (0.0 - 0.10)
    onProgress?.call(0.0, 'Initializing web database engine...');
    debugPrint("[DB_WEB] 🌐 Initializing web FFI database...");

    var factory = databaseFactoryFfiWeb;
    final String webDbName = databaseName;

    // PHASE 2: Check if database already exists in IndexedDB (0.10 - 0.15)
    onProgress?.call(0.10, 'Checking for existing database...');

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
        debugPrint("[DB_WEB] ✅ Using existing database with $count words");
        onProgress?.call(1.0, 'Database ready!');
        return existingDb;
      }

      await existingDb.close();
      debugPrint("[DB_WEB] Existing database is invalid, will re-extract");
      await factory.deleteDatabase(webDbName);
    } catch (e) {
      debugPrint("[DB_WEB] No existing database or corrupted: $e");
      // Continue with extraction
    }

    // PHASE 3: Load compressed asset (0.15 - 0.25)
    onProgress?.call(0.15, 'Loading compressed database...');
    debugPrint("[DB_WEB] Loading compressed asset...");

    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List compressedBytes = data.buffer.asUint8List();
    final compressedSizeMB =
        (compressedBytes.length / (1024 * 1024)).toStringAsFixed(1);

    debugPrint("[DB_WEB] Loaded $compressedSizeMB MB compressed data");
    onProgress?.call(0.25, 'Loaded $compressedSizeMB MB compressed');

    // PHASE 4: Decompress (0.25 - 0.75) - THE LONG PART
    debugPrint("[DB_WEB] Starting decompression...");
    onProgress?.call(0.30, 'Decompressing database...');

    final stopwatch = Stopwatch()..start();
    final List<int> decompressedBytes;

    try {
      // compute() routes through an isolate on mobile/desktop and through a
      // microtask on web; either way the prior progress update has a chance
      // to paint before this long sync call.
      decompressedBytes = await compute(_decodeGzipBytes, compressedBytes);

      final decompressedSizeMB =
          (decompressedBytes.length / (1024 * 1024)).toStringAsFixed(1);
      debugPrint(
          "[DB_WEB] Decompressed to $decompressedSizeMB MB in ${stopwatch.elapsedMilliseconds}ms");
      onProgress?.call(0.75, 'Decompressed to $decompressedSizeMB MB');
    } catch (e) {
      debugPrint("[DB_WEB] ❌ Decompression error: $e");
      onProgress?.call(0.0, 'Decompression failed');
      rethrow;
    }

    // PHASE 5: Convert to Uint8List and write to IndexedDB (0.75 - 0.90)
    onProgress?.call(0.80, 'Writing to browser storage...');
    debugPrint("[DB_WEB] Converting to Uint8List and writing to virtual FS...");

    // CRITICAL: Web FFI requires Uint8List, not List<int>
    final Uint8List uint8Bytes = Uint8List.fromList(decompressedBytes);

    await factory.writeDatabaseBytes(webDbName, uint8Bytes);
    debugPrint("[DB_WEB] Database written to IndexedDB");
    onProgress?.call(0.90, 'Database saved to browser');

    // PHASE 6: Open and verify (0.90 - 1.0)
    onProgress?.call(0.95, 'Opening database...');
    debugPrint("[DB_WEB] Opening database...");

    final db = await factory.openDatabase(
      webDbName,
      options: OpenDatabaseOptions(readOnly: true),
    );

    // Verify word count
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM words'),
    );

    debugPrint("[DB_WEB] ✅ Database opened successfully with $count words");
    debugPrint(
        "[DB_WEB] Total initialization time: ${stopwatch.elapsedMilliseconds}ms");

    onProgress?.call(1.0, 'Database ready with $count words!');

    return db;
  } catch (e, stackTrace) {
    debugPrint("[DB_WEB] ❌ Critical error during initialization: $e");
    debugPrint("[DB_WEB] Stack trace: $stackTrace");
    onProgress?.call(0.0, 'Database initialization failed');
    rethrow;
  }
}
