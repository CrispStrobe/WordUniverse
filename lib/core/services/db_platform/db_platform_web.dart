// lib/core/services/db_platform/db_platform_web.dart
import 'dart:typed_data'; // Needed for Uint8List
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:archive/archive_io.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<Database> initPlatformDatabase() async {
  print("[DB] 🌐 Web: initializing FFI...");
  
  // Initialize Web FFI
  var factory = databaseFactoryFfiWeb;
  const String webDbName = "grundwortschatz.db";

  print("[DB] 🌐 Web: Loading compressed asset...");
  final ByteData data = await rootBundle.load("assets/grundwortschatz.db.gz");
  final List<int> bytes = data.buffer.asUint8List();
  
  print("[DB] 🌐 Web: Decompressing...");
  final List<int> decompressedBytes = GZipDecoder().decodeBytes(bytes);
  
  print("[DB] 🌐 Web: Writing to virtual FS...");
  
  // --- FIX: CONVERT TO Uint8List ---
  // We must explicitly cast List<int> to Uint8List for the Web FFI
  final Uint8List uint8Bytes = Uint8List.fromList(decompressedBytes);
  
  await factory.writeDatabaseBytes(webDbName, uint8Bytes);
  
  return await factory.openDatabase(webDbName, options: OpenDatabaseOptions(readOnly: true));
}