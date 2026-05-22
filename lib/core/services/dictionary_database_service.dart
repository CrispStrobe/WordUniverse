// lib/core/services/dictionary_database_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/vocabulary_models.dart';

// --- CONDITIONAL IMPORT SWITCHER ---
import 'db_platform/db_platform_interface.dart'
    if (dart.library.io) 'db_platform/db_platform_mobile.dart'
    if (dart.library.html) 'db_platform/db_platform_web.dart';

class DictionaryDatabaseService {
  static final DictionaryDatabaseService _instance =
      DictionaryDatabaseService._internal();
  factory DictionaryDatabaseService() => _instance;
  DictionaryDatabaseService._internal();

  Database? _database;
  bool _isInitializing = false;
  String? _assetPath;
  String? _databaseName;

  /// Initialize the database with optional progress tracking
  /// [onProgress] reports (progress: 0.0-1.0, message: String)
  Future<void> initialize({
    String assetPath = 'assets/grundwortschatz.db.gz',
    String databaseName = 'grundwortschatz.db',
    void Function(double progress, String message)? onProgress,
  }) async {
    // Prevent multiple simultaneous initializations
    if (_database != null) {
      if (_assetPath == assetPath && _databaseName == databaseName) {
        onProgress?.call(1.0, 'Database already initialized');
        return;
      }
      await close();
    }

    if (_isInitializing) {
      debugPrint(
          "[DB_SERVICE] ⏳ Initialization already in progress, waiting...");
      // Wait for ongoing initialization (with timeout)
      int attempts = 0;
      while (_isInitializing && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (_database != null) {
        onProgress?.call(1.0, 'Database initialized by another call');
        return;
      }
    }

    _isInitializing = true;

    try {
      // PHASE 1: Start initialization (0.0 - 0.05)
      onProgress?.call(0.0, 'Starting database initialization...');
      debugPrint("[DB_SERVICE] 📚 Initializing database service...");

      // PHASE 2: Platform-specific initialization (0.05 - 0.90)
      // This handles the heavy lifting: extraction, decompression, writing
      _database = await initPlatformDatabase(
        assetPath: assetPath,
        databaseName: databaseName,
        onProgress: (platformProgress, platformMessage) {
          // Map platform progress (0.0-1.0) to our phase (0.05-0.90)
          final mappedProgress = 0.05 + (platformProgress * 0.85);
          onProgress?.call(mappedProgress, platformMessage);
        },
      );

      if (_database == null) {
        throw Exception('Platform initialization returned null database');
      }

      // PHASE 3: Verify database integrity (0.90 - 0.95)
      onProgress?.call(0.90, 'Verifying database integrity...');

      final count = Sqflite.firstIntValue(
        await _database!.rawQuery('SELECT COUNT(*) FROM words'),
      );

      if (count == null || count == 0) {
        throw Exception('Database is empty or invalid');
      }

      debugPrint("[DB_SERVICE] ✅ Database verified with $count words");
      onProgress?.call(0.95, 'Database verified: $count words');

      // PHASE 4: Complete (0.95 - 1.0)
      onProgress?.call(1.0, 'Database initialization complete!');
      debugPrint("[DB_SERVICE] ✅ Database service ready");
      _assetPath = assetPath;
      _databaseName = databaseName;
    } catch (e, stackTrace) {
      debugPrint("[DB_SERVICE] ❌ Critical error initializing database: $e");
      debugPrint("[DB_SERVICE] Stack trace: $stackTrace");
      onProgress?.call(0.0, 'Database initialization failed: $e');
      _database = null; // Ensure we can retry
      _assetPath = null;
      _databaseName = null;
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  // --- QUERIES ---

  /// Get all words from the database
  Future<List<GermanWord>> getAllWords() async {
    if (_database == null) {
      debugPrint("[DB_SERVICE] Database not initialized, initializing now...");
      await initialize();
      if (_database == null) return [];
    }

    try {
      final List<Map<String, dynamic>> results =
          await _database!.query('words');
      debugPrint("[DB_SERVICE] Fetched ${results.length} words");
      return results.map((row) => _mapRowToGermanWord(row)).toList();
    } catch (e) {
      debugPrint("[DB_SERVICE] Error fetching all words: $e");
      return [];
    }
  }

  /// Full-Text Search using FTS5 index
  Future<List<GermanWord>> searchWordsFTS(String query) async {
    if (_database == null) {
      await initialize();
      if (_database == null) return [];
    }

    if (query.trim().isEmpty) return [];

    // Sanitize input for FTS5
    final sanitized =
        query.replaceAll(RegExp(r'[^a-zA-Z0-9äöüÄÖÜß\s]'), '').trim();

    if (sanitized.isEmpty) return [];

    try {
      final results = await _database!.rawQuery('''
        SELECT words.* FROM words 
        JOIN search_index ON words.id = search_index.rowid 
        WHERE search_index MATCH ? 
        ORDER BY length(words.word) ASC 
        LIMIT 50
      ''', ['$sanitized*']);

      debugPrint(
          "[DB_SERVICE] FTS search for '$query' returned ${results.length} results");
      return results.map((row) => _mapRowToGermanWord(row)).toList();
    } catch (e) {
      debugPrint("[DB_SERVICE] FTS search error: $e");
      return [];
    }
  }

  /// Get a single word by ID
  Future<GermanWord?> getWordById(String id) async {
    if (_database == null) {
      await initialize();
      if (_database == null) return null;
    }

    try {
      final results = await _database!.query(
        'words',
        where: 'original_id = ? OR id = ?',
        whereArgs: [id, id],
        limit: 1,
      );

      if (results.isEmpty) return null;
      return _mapRowToGermanWord(results.first);
    } catch (e) {
      debugPrint("[DB_SERVICE] Error fetching word by ID '$id': $e");
      return null;
    }
  }

  /// Get words by grade level
  Future<List<GermanWord>> getWordsByGrade(int gradeLevel) async {
    if (_database == null) {
      await initialize();
      if (_database == null) return [];
    }

    try {
      final results = await _database!.query(
        'words',
        where: 'grade_level = ?',
        whereArgs: [gradeLevel],
      );

      debugPrint(
          "[DB_SERVICE] Fetched ${results.length} words for grade $gradeLevel");
      return results.map((row) => _mapRowToGermanWord(row)).toList();
    } catch (e) {
      debugPrint("[DB_SERVICE] Error fetching words by grade $gradeLevel: $e");
      return [];
    }
  }

  /// Get database statistics
  Future<Map<String, dynamic>> getStatistics() async {
    if (_database == null) {
      await initialize();
      if (_database == null) return {};
    }

    try {
      final totalWords = Sqflite.firstIntValue(
            await _database!.rawQuery('SELECT COUNT(*) FROM words'),
          ) ??
          0;

      final gradeDistribution = await _database!.rawQuery('''
        SELECT grade_level, COUNT(*) as count 
        FROM words 
        GROUP BY grade_level 
        ORDER BY grade_level
      ''');

      final typeDistribution = await _database!.rawQuery('''
        SELECT word_type, COUNT(*) as count 
        FROM words 
        GROUP BY word_type 
        ORDER BY count DESC
        LIMIT 10
      ''');

      return {
        'totalWords': totalWords,
        'gradeDistribution': gradeDistribution,
        'typeDistribution': typeDistribution,
      };
    } catch (e) {
      debugPrint("[DB_SERVICE] Error getting statistics: $e");
      return {};
    }
  }

  /// Close the database connection
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _assetPath = null;
      _databaseName = null;
      debugPrint("[DB_SERVICE] Database connection closed");
    }
  }

  // --- PRIVATE HELPERS ---

  /// Maps a database row to a GermanWord object
  GermanWord _mapRowToGermanWord(Map<String, dynamic> row) {
    try {
      // Parse JSON columns safely
      final freqJson = row['frequency_json'] as String?;
      final enrichmentJson = row['enrichment_json'] as String?;
      final metadataJson = row['metadata_json'] as String?;

      Map<String, dynamic> frequencyData = {};
      Map<String, dynamic> apiEnrichment = {};
      Map<String, dynamic> metadata = {};

      // Safe JSON parsing with error handling
      if (freqJson != null && freqJson.isNotEmpty) {
        try {
          frequencyData = jsonDecode(freqJson) as Map<String, dynamic>;
        } catch (e) {
          debugPrint("[DB_SERVICE] Error parsing frequency_json: $e");
        }
      }

      if (enrichmentJson != null && enrichmentJson.isNotEmpty) {
        try {
          apiEnrichment = jsonDecode(enrichmentJson) as Map<String, dynamic>;
        } catch (e) {
          debugPrint("[DB_SERVICE] Error parsing enrichment_json: $e");
        }
      }

      if (metadataJson != null && metadataJson.isNotEmpty) {
        try {
          metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
        } catch (e) {
          debugPrint("[DB_SERVICE] Error parsing metadata_json: $e");
        }
      }

      // Build the word map for GermanWord.fromJson
      final Map<String, dynamic> wordMap = {
        'id': row['original_id'] ?? row['id']?.toString() ?? 'unknown',
        'word': row['word'] ?? '',
        'lemma': row['lemma'] ?? row['word'] ?? '',
        'article': row['article'],
        'genus': row['genus'],
        'wordType': row['word_type'] ?? 'andere',
        'gradeLevel': row['grade_level'] ?? 1,
        'audioPath': row['audio_path'],
        'frequencyData': frequencyData,
        'apiEnrichment': apiEnrichment,
        ...metadata,
      };

      return GermanWord.fromJson(wordMap);
    } catch (e, stackTrace) {
      debugPrint("[DB_SERVICE] Error mapping row to GermanWord: $e");
      debugPrint("[DB_SERVICE] Stack trace: $stackTrace");
      debugPrint("[DB_SERVICE] Problematic row: $row");

      // Return a minimal fallback word to prevent crashes
      return GermanWord.fromJson({
        'id': row['id']?.toString() ??
            'error_${DateTime.now().millisecondsSinceEpoch}',
        'word': row['word']?.toString() ?? 'ERROR',
        'lemma': row['word']?.toString() ?? 'ERROR',
        'wordType': 'andere',
        'gradeLevel': 1,
      });
    }
  }
}
