// lib/core/services/dictionary_database_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/vocabulary_models.dart';
import '../models/vocabulary_quality.dart';
import '../models/load_status.dart';
import 'db_platform/db_feature_index.dart';
import 'db_platform/db_schema.dart';

// --- CONDITIONAL IMPORT SWITCHER ---
import 'db_platform/db_platform_interface.dart'
    if (dart.library.io) 'db_platform/db_platform_mobile.dart'
    if (dart.library.js_interop) 'db_platform/db_platform_web.dart';

class DictionaryDatabaseService {
  static final DictionaryDatabaseService _instance =
      DictionaryDatabaseService._internal();
  factory DictionaryDatabaseService() => _instance;
  DictionaryDatabaseService._internal();

  Database? _database;
  bool _isInitializing = false;
  String? _assetPath;
  String? _databaseName;
  WordFeatureIndex _featureIndex = const WordFeatureIndex.empty();

  /// Columns that describe a word without touching the enrichment blobs.
  /// Selecting `*` here would move ~72 MB of JSON per pack across the platform
  /// channel and through `jsonDecode` on every launch.
  static const String _lightColumns =
      'id, original_id, word, lemma, article, genus, word_type, '
      'grade_level, audio_path';

  /// Feature bits and sources for the open pack. Empty until a pack is open.
  WordFeatureIndex get featureIndex => _featureIndex;

  /// Initialize the database with optional progress tracking
  /// [onProgress] reports (progress: 0.0-1.0, message: String)
  Future<void> initialize({
    // No defaults on purpose: which database to open follows from the active
    // language pack (see core/models/language_pack.dart). A default would
    // quietly point at the German asset, which is NOT bundled.
    required String assetPath,
    required String databaseName,
    List<String> legacyDatabaseNames = const [],
    String? remoteUrl,
    int? expectedCompressedBytes,
    int? expectedDecompressedBytes,
    String? expectedDecompressedSha256,
    LoadProgress? onProgress,
  }) async {
    // Prevent multiple simultaneous initializations
    if (_database != null) {
      if (_assetPath == assetPath && _databaseName == databaseName) {
        onProgress?.call(1.0, const LoadStatus(LoadStage.databaseReady));
        return;
      }
      await close();
    }

    if (_isInitializing) {
      if (kDebugMode)
        debugPrint(
            "[DB_SERVICE] ⏳ Initialization already in progress, waiting...");
      // Wait for ongoing initialization (with timeout)
      int attempts = 0;
      while (_isInitializing && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (_database != null) {
        onProgress?.call(1.0, const LoadStatus(LoadStage.databaseReady));
        return;
      }
    }

    _isInitializing = true;

    try {
      // PHASE 1: Start initialization (0.0 - 0.05)
      onProgress?.call(0.0, const LoadStatus(LoadStage.preparing));
      if (kDebugMode)
        debugPrint("[DB_SERVICE] 📚 Initializing database service...");

      // PHASE 2: Platform-specific initialization (0.05 - 0.90)
      // This handles the heavy lifting: extraction, decompression, writing
      _database = await initPlatformDatabase(
        assetPath: assetPath,
        databaseName: databaseName,
        legacyDatabaseNames: legacyDatabaseNames,
        remoteUrl: remoteUrl,
        expectedCompressedBytes: expectedCompressedBytes,
        expectedDecompressedBytes: expectedDecompressedBytes,
        expectedDecompressedSha256: expectedDecompressedSha256,
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
      onProgress?.call(0.90, const LoadStatus(LoadStage.verifying));

      final count = await validateDictionarySchema(_database!);

      if (kDebugMode)
        debugPrint("[DB_SERVICE] ✅ Database verified with $count words");
      onProgress?.call(0.95, LoadStatus(LoadStage.verifiedWords, count: count));

      // Derived per-word answers (which enrichment each word carries, whether
      // it is presentable, its sources). Built once per pack revision and
      // cached, so launches never decode the enrichment blobs.
      _featureIndex = await loadWordFeatureIndex(
        _database!,
        cacheKey: databaseName,
        revision: expectedDecompressedSha256 ?? 'words:$count',
      );

      // PHASE 4: Complete (0.95 - 1.0)
      onProgress?.call(1.0, const LoadStatus(LoadStage.databaseReady));
      if (kDebugMode) debugPrint("[DB_SERVICE] ✅ Database service ready");
      _assetPath = assetPath;
      _databaseName = databaseName;
    } catch (e, stackTrace) {
      if (kDebugMode)
        debugPrint("[DB_SERVICE] ❌ Critical error initializing database: $e");
      if (kDebugMode) debugPrint("[DB_SERVICE] Stack trace: $stackTrace");
      onProgress?.call(0.0, const LoadStatus(LoadStage.failed));
      await _database?.close();
      _database = null; // Ensure we can retry
      _assetPath = null;
      _databaseName = null;
      _featureIndex = const WordFeatureIndex.empty();
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Whether [databaseName] is already cached on this device. Used by
  /// `LanguagePackService` to tell an installed language pack from one that
  /// still needs downloading, without trusting a preference flag.
  Future<bool> isDatabaseInstalled(String databaseName, {
    List<String> legacyDatabaseNames = const [],
    String? expectedDecompressedSha256,
  }) => isPlatformDatabaseInstalled(databaseName,
      legacyDatabaseNames: legacyDatabaseNames,
      expectedDecompressedSha256: expectedDecompressedSha256);

  /// Deletes the cached copy of [databaseName]. Closes the active connection
  /// first when it is the database being removed, otherwise the delete fails
  /// (or leaves a half-open handle) on some platforms.
  Future<void> deleteDatabaseFile(String databaseName) async {
    if (_databaseName == databaseName) {
      await close();
    }
    await deletePlatformDatabase(databaseName);
  }

  // --- QUERIES ---

  /// Whether a database is open and ready to be queried. Queries return
  /// empty results rather than initializing on the fly: only the language-pack
  /// layer knows *which* database belongs to the active language, and guessing
  /// here used to reach for the unbundled German asset.
  bool get isReady => _database != null;

  void _warnNotReady(String what) {
    if (kDebugMode) {
      debugPrint("[DB_SERVICE] ⚠️ $what requested before the database was "
          "initialized — returning empty. Initialize the active language pack "
          "first (LanguagePackService).");
    }
  }

  /// Every presentable word, without its enrichment.
  ///
  /// This is the launch query. The returned words carry their feature bits and
  /// sources (from the feature index) but no enrichment: pools are built from
  /// [GermanWord.has], and the words a round actually shows are passed through
  /// [hydrate] first.
  Future<List<GermanWord>> getAllWords() async {
    if (_database == null) {
      _warnNotReady('All words');
      return [];
    }

    try {
      final results =
          await _database!.rawQuery('SELECT $_lightColumns FROM words');
      final words = <GermanWord>[];
      for (final row in results) {
        final word = _mapLightRow(row);
        // The JSON half of presentability lives in the feature index; only the
        // headword shape still needs the word itself.
        if (!_featureIndex.isPresentable(word.rowId ?? -1)) continue;
        if (!isPresentableVocabularyEntry(word)) continue;
        words.add(word);
      }
      if (kDebugMode) {
        debugPrint("[DB_SERVICE] Fetched ${words.length} words "
            "(light, of ${results.length} rows)");
      }
      return words;
    } catch (e) {
      if (kDebugMode) debugPrint("[DB_SERVICE] Error fetching all words: $e");
      return [];
    }
  }

  /// Re-reads [words] with their enrichment decoded.
  ///
  /// Already-hydrated words and words with no pack row are passed through, so
  /// callers can hydrate a mixed list unconditionally. Order is preserved.
  Future<List<GermanWord>> hydrate(Iterable<GermanWord> words) async {
    final pending = <int, int>{}; // rowId -> first position
    final ordered = words.toList();
    for (var i = 0; i < ordered.length; i++) {
      final word = ordered[i];
      if (word.isHydrated || word.rowId == null) continue;
      pending.putIfAbsent(word.rowId!, () => i);
    }
    if (pending.isEmpty || _database == null) return ordered;

    try {
      final byRowId = <int, GermanWord>{};
      // Chunked so the statement stays well inside SQLite's variable limit.
      const chunkSize = 400;
      final rowIds = pending.keys.toList();
      for (var start = 0; start < rowIds.length; start += chunkSize) {
        final chunk = rowIds.sublist(
            start, (start + chunkSize).clamp(0, rowIds.length));
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await _database!.rawQuery(
          'SELECT * FROM words WHERE id IN ($placeholders)',
          chunk,
        );
        for (final row in rows) {
          final word = _mapRowToGermanWord(row);
          if (word.rowId != null) byRowId[word.rowId!] = word;
        }
      }
      for (var i = 0; i < ordered.length; i++) {
        final hydrated = byRowId[ordered[i].rowId];
        if (hydrated != null) ordered[i] = hydrated;
      }
    } catch (e) {
      // A failed hydration leaves the light words in place: a round without
      // definitions is better than a crash.
      if (kDebugMode) debugPrint("[DB_SERVICE] Hydration failed: $e");
    }
    return ordered;
  }

  /// Convenience for the single-word case.
  Future<GermanWord> hydrateOne(GermanWord word) async =>
      (await hydrate([word])).first;

  /// Full-Text Search using FTS5 index
  Future<List<GermanWord>> searchWordsFTS(String query) async {
    if (_database == null) {
      _warnNotReady('FTS search');
      return [];
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

      if (kDebugMode)
        debugPrint(
            "[DB_SERVICE] FTS search for '$query' returned ${results.length} results");
      return _mapPresentableWords(results);
    } catch (e) {
      if (kDebugMode) debugPrint("[DB_SERVICE] FTS search error: $e");
      return [];
    }
  }

  /// Get a single word by ID
  Future<GermanWord?> getWordById(String id) async {
    if (_database == null) {
      _warnNotReady('Word by id');
      return null;
    }

    try {
      final results = await _database!.query(
        'words',
        where: 'original_id = ? OR id = ?',
        whereArgs: [id, id],
        limit: 1,
      );

      if (results.isEmpty) return null;
      final word = _mapRowToGermanWord(results.first);
      return isPresentableVocabularyEntry(word) ? word : null;
    } catch (e) {
      if (kDebugMode)
        debugPrint("[DB_SERVICE] Error fetching word by ID '$id': $e");
      return null;
    }
  }

  /// Get all phrasal verbs (EN database only). Returns rows from the
  /// `phrasal_verbs` table; empty if the table is absent (e.g. DE database).
  Future<List<Map<String, dynamic>>> getPhrasalVerbs() async {
    if (_database == null) {
      _warnNotReady('Query');
      return [];
    }

    try {
      final hasTable = Sqflite.firstIntValue(await _database!.rawQuery(
            "SELECT COUNT(*) FROM sqlite_master "
            "WHERE type='table' AND name='phrasal_verbs'",
          )) ??
          0;
      if (hasTable == 0) {
        if (kDebugMode) {
          debugPrint("[DB_SERVICE] No phrasal_verbs table (non-EN database)");
        }
        return [];
      }
      final results = await _database!.query('phrasal_verbs');
      if (kDebugMode) {
        debugPrint("[DB_SERVICE] Fetched ${results.length} phrasal verbs");
      }
      return results;
    } catch (e) {
      if (kDebugMode)
        debugPrint("[DB_SERVICE] Error fetching phrasal verbs: $e");
      return [];
    }
  }

  /// Get all false friends (EN database only). Empty if the table is absent
  /// (e.g. DE database).
  Future<List<Map<String, dynamic>>> getFalseFriends() async {
    if (_database == null) {
      _warnNotReady('Query');
      return [];
    }

    try {
      final hasTable = Sqflite.firstIntValue(await _database!.rawQuery(
            "SELECT COUNT(*) FROM sqlite_master "
            "WHERE type='table' AND name='false_friends'",
          )) ??
          0;
      if (hasTable == 0) return [];
      return await _database!.query('false_friends');
    } catch (e) {
      if (kDebugMode)
        debugPrint("[DB_SERVICE] Error fetching false friends: $e");
      return [];
    }
  }

  /// Get database statistics
  Future<Map<String, dynamic>> getStatistics() async {
    if (_database == null) {
      _warnNotReady('Statistics');
      return {};
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
      if (kDebugMode) debugPrint("[DB_SERVICE] Error getting statistics: $e");
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
      _featureIndex = const WordFeatureIndex.empty();
      if (kDebugMode) debugPrint("[DB_SERVICE] Database connection closed");
    }
  }

  // --- PRIVATE HELPERS ---

  List<GermanWord> _mapPresentableWords(
    List<Map<String, dynamic>> rows,
  ) =>
      rows
          .map(_mapRowToGermanWord)
          .where(isPresentableVocabularyEntry)
          .toList();

  /// Maps a row of [_lightColumns] to a word with no enrichment decoded.
  ///
  /// Sources and feature bits come from the feature index rather than the
  /// metadata blob, so this touches no JSON at all.
  GermanWord _mapLightRow(Map<String, dynamic> row) {
    final rowId = (row['id'] as num?)?.toInt();
    return GermanWord.fromJson({
      'id': row['original_id'] ?? rowId?.toString() ?? 'unknown',
      'rowId': rowId,
      'features': rowId == null ? 0 : _featureIndex.featuresOf(rowId),
      'isHydrated': false,
      'sources': rowId == null ? const [] : _featureIndex.sourcesOf(rowId),
      'word': row['word'] ?? '',
      'lemma': row['lemma'] ?? row['word'] ?? '',
      'article': row['article'],
      'genus': row['genus'],
      'wordType': row['word_type'] ?? 'andere',
      'gradeLevel': row['grade_level'] ?? 1,
      'audioPath': row['audio_path'],
    });
  }

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
          if (kDebugMode)
            debugPrint("[DB_SERVICE] Error parsing frequency_json: $e");
        }
      }

      if (enrichmentJson != null && enrichmentJson.isNotEmpty) {
        try {
          apiEnrichment = jsonDecode(enrichmentJson) as Map<String, dynamic>;
        } catch (e) {
          if (kDebugMode)
            debugPrint("[DB_SERVICE] Error parsing enrichment_json: $e");
        }
      }

      if (metadataJson != null && metadataJson.isNotEmpty) {
        try {
          metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
        } catch (e) {
          if (kDebugMode)
            debugPrint("[DB_SERVICE] Error parsing metadata_json: $e");
        }
      }

      // grade_examples and gutenberg_examples live in metadata_json;
      // ApiEnrichment.fromJson reads them from the apiEnrichment dict,
      // so inject them there before building the word map.
      for (final key in ['grade_examples', 'gutenberg_examples']) {
        if (metadata.containsKey(key)) {
          apiEnrichment[key] = metadata[key];
        }
      }

      // Build the word map for GermanWord.fromJson
      final rowId = (row['id'] as num?)?.toInt();
      final Map<String, dynamic> wordMap = {
        'id': row['original_id'] ?? row['id']?.toString() ?? 'unknown',
        'rowId': rowId,
        'features': rowId == null ? 0 : _featureIndex.featuresOf(rowId),
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
        // graphematicVariants are stored in enrichment_json by pipeline step 15;
        // expose them at the top level so GermanWord.fromJson can read them.
        if (apiEnrichment['graphematicVariants'] != null)
          'graphematicVariants': apiEnrichment['graphematicVariants'],
      };

      return GermanWord.fromJson(wordMap);
    } catch (e, stackTrace) {
      if (kDebugMode)
        debugPrint("[DB_SERVICE] Error mapping row to GermanWord: $e");
      if (kDebugMode) debugPrint("[DB_SERVICE] Stack trace: $stackTrace");
      if (kDebugMode) debugPrint("[DB_SERVICE] Problematic row: $row");

      // Return a minimal fallback word to prevent crashes. It keeps its rowid
      // and feature bits, so a caller that asked for this row still gets an
      // answer for it rather than silently getting nothing back.
      final rowId = (row['id'] as num?)?.toInt();
      return GermanWord.fromJson({
        'id': row['original_id'] ??
            rowId?.toString() ??
            'error_${DateTime.now().millisecondsSinceEpoch}',
        'rowId': rowId,
        'features': rowId == null ? 0 : _featureIndex.featuresOf(rowId),
        'word': row['word']?.toString() ?? 'ERROR',
        'lemma': row['word']?.toString() ?? 'ERROR',
        'wordType': row['word_type'] ?? 'andere',
        'gradeLevel': row['grade_level'] ?? 1,
      });
    }
  }
}
