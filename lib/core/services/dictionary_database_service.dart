// lib/core/services/dictionary_database_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart'; // IMPORT ARCHIVE
import '../models/vocabulary_models.dart';

class DictionaryDatabaseService {
  static final DictionaryDatabaseService _instance =
      DictionaryDatabaseService._internal();

  factory DictionaryDatabaseService() => _instance;
  DictionaryDatabaseService._internal();

  Database? _database;

  Future<void> initialize() async {
    if (_database != null) return;
    try {
      _database = await _initDatabase();
      debugPrint("[DB] ✅ Database initialized successfully");
    } catch (e) {
      debugPrint("[DB] ❌ Critical Error initializing database: $e");
    }
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, "grundwortschatz.db");

    bool exists = await databaseExists(path);

    if (!exists) {
      debugPrint("[DB] 📦 Database not found. Preparing to extract from compressed asset...");
      try {
        // Ensure directory exists
        await Directory(dirname(path)).create(recursive: true);
        
        // 1. Load the Compressed Asset
        debugPrint("[DB] Loading asset: assets/grundwortschatz.db.gz");
        ByteData data = await rootBundle.load("assets/grundwortschatz.db.gz");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        
        // 2. Decompress
        debugPrint("[DB] Decompressing (this may take a moment)...");
        final List<int> decompressedBytes = GZipDecoder().decodeBytes(bytes);
        
        // 3. Write to File
        debugPrint("[DB] Writing to storage...");
        await File(path).writeAsBytes(decompressedBytes, flush: true);
        
        debugPrint("[DB] ✅ Database extraction complete.");
      } catch (e) {
        debugPrint("[DB] ❌ Error extracting database: $e");
        // Cleanup partial file on error
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        throw Exception("Failed to extract database from assets: $e");
      }
    } else {
      debugPrint("[DB] Opening existing database.");
    }

    return await openDatabase(path, readOnly: true);
  }

  // --- Existing Methods (getAllWords, searchWordsFTS) remain unchanged ---
  
  Future<List<GermanWord>> getAllWords() async {
    if (_database == null) {
       await initialize();
       if (_database == null) return [];
    }
    try {
      final List<Map<String, dynamic>> results = await _database!.query('words');
      return results.map((row) => _mapRowToGermanWord(row)).toList();
    } catch (e) {
      debugPrint("[DB] Error fetching all words: $e");
      return [];
    }
  }

  Future<List<GermanWord>> searchWordsFTS(String query) async {
    if (_database == null) await initialize();
    if (query.trim().isEmpty) return [];

    final sanitized = query.replaceAll(RegExp(r'[^a-zA-Z0-9äöüÄÖÜß]'), '');
    if (sanitized.isEmpty) return [];

    try {
      final results = await _database!.rawQuery('''
        SELECT words.* FROM words 
        JOIN search_index ON words.id = search_index.rowid 
        WHERE search_index MATCH '$sanitized*' 
        ORDER BY length(words.word) ASC 
        LIMIT 50
      ''');
      return results.map((row) => _mapRowToGermanWord(row)).toList();
    } catch (e) {
      debugPrint("[DB] FTS Search Error: $e");
      return [];
    }
  }

  GermanWord _mapRowToGermanWord(Map<String, dynamic> row) {
    final freqJson = row['frequency_json'] as String?;
    final enrichmentJson = row['enrichment_json'] as String?;
    final metadataJson = row['metadata_json'] as String?;

    Map<String, dynamic> frequencyData = (freqJson != null) ? jsonDecode(freqJson) : {};
    Map<String, dynamic> apiEnrichment = (enrichmentJson != null) ? jsonDecode(enrichmentJson) : {};
    Map<String, dynamic> metadata = (metadataJson != null) ? jsonDecode(metadataJson) : {};

    final Map<String, dynamic> wordMap = {
      'id': row['original_id'] ?? row['id'].toString(),
      'word': row['word'],
      'lemma': row['lemma'],
      'article': row['article'],
      'genus': row['genus'],
      'wordType': row['word_type'], 
      'gradeLevel': row['grade_level'],
      'audioPath': row['audio_path'],
      'frequencyData': frequencyData,
      'apiEnrichment': apiEnrichment,
      ...metadata,
    };

    return GermanWord.fromJson(wordMap);
  }
}