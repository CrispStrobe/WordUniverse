// lib/core/services/db_platform/db_platform_mobile.dart:
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:archive/archive_io.dart';

Future<Database> initPlatformDatabase() async {
  // 1. Get Path
  Directory documentsDirectory = await getApplicationDocumentsDirectory();
  String path = join(documentsDirectory.path, "grundwortschatz.db");

  // 2. Check Exists
  if (!await databaseExists(path)) {
    print("[DB] 📱 Mobile/Desktop: Extracting database...");
    
    // Ensure directory exists
    await Directory(dirname(path)).create(recursive: true);
    
    // Load & Decompress
    final ByteData data = await rootBundle.load("assets/grundwortschatz.db.gz");
    final List<int> bytes = data.buffer.asUint8List();
    final List<int> decompressedBytes = GZipDecoder().decodeBytes(bytes);
    
    // Write to File System
    // writeAsBytes accepts List<int>, so no conversion needed here
    await File(path).writeAsBytes(decompressedBytes, flush: true);
  }

  return await openDatabase(path, readOnly: true);
}