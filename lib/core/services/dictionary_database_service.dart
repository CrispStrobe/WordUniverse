import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/vocabulary_models.dart';

// --- CONDITIONAL IMPORT SWITCHER ---
// This magic line picks the correct file based on the platform running
import 'db_platform/db_platform_interface.dart'
    if (dart.library.io) 'db_platform/db_platform_mobile.dart'
    if (dart.library.html) 'db_platform/db_platform_web.dart';

class DictionaryDatabaseService {
  static final DictionaryDatabaseService _instance =
      DictionaryDatabaseService._internal();

  factory DictionaryDatabaseService() => _instance;
  DictionaryDatabaseService._internal();

  Database? _database;

  Future<void> initialize() async {
    if (_database != null) return;
    try {
      // This calls the platform-specific function from the imports above
      _database = await initPlatformDatabase();
      debugPrint("[DB] ✅ Database initialized successfully");
    } catch (e) {
      debugPrint("[DB] ❌ Critical Error initializing database: $e");
    }
  }

  // --- QUERIES ---

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

    Map<String, dynamic> frequencyData =
        (freqJson != null) ? jsonDecode(freqJson) : {};
    Map<String, dynamic> apiEnrichment =
        (enrichmentJson != null) ? jsonDecode(enrichmentJson) : {};
    Map<String, dynamic> metadata =
        (metadataJson != null) ? jsonDecode(metadataJson) : {};

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