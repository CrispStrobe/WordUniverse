// lib/core/services/db_platform/db_platform_mobile.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:archive/archive_io.dart';

/// Top-level entry point for [compute]. Runs in a background isolate so the
/// ~14MB gzip → ~50MB decompression doesn't block the UI thread.
List<int> _decodeGzipBytes(Uint8List bytes) {
  return GZipDecoder().decodeBytes(bytes);
}

Future<Database> initPlatformDatabase({
  void Function(double progress, String message)? onProgress,
}) async {
  try {
    // PHASE 1: Determine database path (0.0 - 0.05)
    onProgress?.call(0.0, 'Locating database storage...');
    debugPrint("[DB_MOBILE] 📱 Initializing mobile/desktop database...");
    
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, "grundwortschatz.db");
    final File dbFile = File(path);

    // PHASE 2: Check if database already exists and is valid (0.05 - 0.10)
    if (await dbFile.exists()) {
      onProgress?.call(0.05, 'Checking existing database...');
      debugPrint("[DB_MOBILE] Database file exists at: $path");
      
      try {
        // Quick validation - try to open and query
        final db = await openDatabase(path, readOnly: true);
        final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM words LIMIT 1'),
        );
        
        if (count != null && count > 0) {
          debugPrint("[DB_MOBILE] ✅ Using existing valid database with $count words");
          onProgress?.call(1.0, 'Database ready!');
          return db;
        }
        
        // If we got here, database exists but is empty/invalid
        await db.close();
        debugPrint("[DB_MOBILE] ⚠️ Existing database is invalid, will re-extract");
        await dbFile.delete();
      } catch (e) {
        debugPrint("[DB_MOBILE] ⚠️ Existing database is corrupted: $e");
        // Try to delete corrupted database
        try {
          await dbFile.delete();
        } catch (deleteError) {
          debugPrint("[DB_MOBILE] Could not delete corrupted database: $deleteError");
        }
      }
    }

    // PHASE 3: Extract database from assets (0.10 - 1.0)
    debugPrint("[DB_MOBILE] Extracting database from assets...");
    
    // Ensure directory exists
    onProgress?.call(0.10, 'Preparing storage...');
    await Directory(dirname(path)).create(recursive: true);
    
    // PHASE 4: Load compressed asset (0.10 - 0.20)
    onProgress?.call(0.15, 'Loading compressed database from assets...');
    final ByteData data = await rootBundle.load("assets/grundwortschatz.db.gz");
    final Uint8List compressedBytes = data.buffer.asUint8List();
    final compressedSizeMB = (compressedBytes.length / (1024 * 1024)).toStringAsFixed(1);

    debugPrint("[DB_MOBILE] Loaded $compressedSizeMB MB compressed data");
    onProgress?.call(0.20, 'Loaded $compressedSizeMB MB compressed data');

    // PHASE 5: Decompress (0.20 - 0.80) - THIS IS THE LONG PART
    debugPrint("[DB_MOBILE] Starting decompression on background isolate...");
    onProgress?.call(0.25, 'Decompressing database...');

    final stopwatch = Stopwatch()..start();
    final List<int> decompressedBytes;
    try {
      // Offload sync gzip decode to a background isolate so the splash
      // animation keeps running smoothly during the ~50MB decompression.
      decompressedBytes = await compute(_decodeGzipBytes, compressedBytes);

      final decompressedSizeMB = (decompressedBytes.length / (1024 * 1024)).toStringAsFixed(1);
      debugPrint("[DB_MOBILE] Decompressed to $decompressedSizeMB MB in ${stopwatch.elapsedMilliseconds}ms");
      onProgress?.call(0.80, 'Decompressed to $decompressedSizeMB MB');
    } catch (e) {
      debugPrint("[DB_MOBILE] ❌ Decompression error: $e");
      onProgress?.call(0.0, 'Decompression failed: $e');
      rethrow;
    }

    // PHASE 6: Write to disk (0.80 - 0.90)
    onProgress?.call(0.85, 'Writing database to storage...');
    debugPrint("[DB_MOBILE] Writing database to: $path");
    
    await dbFile.writeAsBytes(decompressedBytes, flush: true);
    debugPrint("[DB_MOBILE] Database written successfully");
    onProgress?.call(0.90, 'Database saved to disk');

    // PHASE 7: Open and verify (0.90 - 1.0)
    onProgress?.call(0.95, 'Opening database...');
    debugPrint("[DB_MOBILE] Opening database...");
    
    final db = await openDatabase(path, readOnly: true);
    
    // Verify word count
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM words'),
    );
    
    debugPrint("[DB_MOBILE] ✅ Database opened successfully with $count words");
    debugPrint("[DB_MOBILE] Total initialization time: ${stopwatch.elapsedMilliseconds}ms");
    
    onProgress?.call(1.0, 'Database ready with $count words!');
    
    return db;
    
  } catch (e, stackTrace) {
    debugPrint("[DB_MOBILE] ❌ Critical error during initialization: $e");
    debugPrint("[DB_MOBILE] Stack trace: $stackTrace");
    onProgress?.call(0.0, 'Database initialization failed');
    rethrow;
  }
}