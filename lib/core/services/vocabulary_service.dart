// lib/core/services/vocabulary_service.dart

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- APP IMPORTS ---
import '../../features/games/models/false_friend.dart';
import '../../features/games/models/phrasal_verb.dart';
import '../../features/games/providers/game_provider.dart';
import '../models/skill_category.dart';
import '../models/vocabulary_models.dart';
import 'sri_service.dart';
import 'dictionary_database_service.dart';

/// Where a language's compressed vocabulary DB comes from. The English DB is
/// CC-BY-SA-4.0 and stays bundled as an asset for instant first launch. The
/// German DB is GPL-3.0 (it includes data derived from childLex) and is
/// intentionally NOT bundled in any store binary — it is downloaded once on
/// first launch from the GPL-compliant Hugging Face dataset and cached. See
/// db_remote.dart for the licensing rationale (the VLC-on-App-Store / FairPlay
/// DRM conflict) and the integrity policy.
class _DbSource {
  final String databaseName;
  final String? assetPath; // bundled (EN); null when remote-only
  final String? remoteUrl; // HF resolve URL (DE); null when asset-only
  final int? expectedCompressedBytes;
  final int? expectedDecompressedBytes;
  final String? expectedDecompressedSha256;
  const _DbSource({
    required this.databaseName,
    this.assetPath,
    this.remoteUrl,
    this.expectedCompressedBytes,
    this.expectedDecompressedBytes,
    this.expectedDecompressedSha256,
  });
}

/// Result of [VocabularyService.remoteDownloadInfo]: whether the next
/// initialize() for a language would trigger a first-time remote download the
/// user should consent to, and how big it is (compressed bytes) for disclosure.
/// Apple App Store Review Guidelines §2.4.2/§4.2.3 require disclosing the size
/// and prompting before downloading resources on first launch.
class RemoteDownloadInfo {
  final bool consentRequired;
  final int? compressedBytes;
  const RemoteDownloadInfo({
    required this.consentRequired,
    this.compressedBytes,
  });
}

class VocabularyService with ChangeNotifier {
  // In-memory cache for fast game logic access
  Map<String, GermanWord> _vocabulary = {};
  Map<String, VocabularySet> _vocabularySets = {};

  Set<String>? _allSourcesCache;

  // Database Service Instance
  final DictionaryDatabaseService _dbService = DictionaryDatabaseService();

  // Storage Keys
  static const _setsStorageKey = 'vocabulary_sets';
  static const _customWordsKey = 'custom_words';
  static const _learningLanguageKey = 'learning_language';
  // Integrity pins for the downloaded German DB. If the German DB is ever
  // rebuilt and re-uploaded to Hugging Face, update expectedCompressedBytes
  // (compressed size) and expectedDecompressedSha256 (sha256 of the .db). The
  // sha256 is a soft check (logged, not fatal — see db_remote.dart), so a
  // forgotten bump degrades gracefully rather than bricking first launch.
  static const _dbSources = <String, _DbSource>{
    'de': _DbSource(
      databaseName: 'grundwortschatz.db',
      remoteUrl:
          'https://huggingface.co/datasets/cstr/grundwortschatz-voc-de/resolve/main/grundwortschatz.db.gz',
      expectedCompressedBytes: 26619920,
      expectedDecompressedBytes: 156913664,
      expectedDecompressedSha256:
          'c66e3b49192694c00d7c2a171562ac8fe4f54c05d986adb0ebf276f141aa00df',
    ),
    'en': _DbSource(
      databaseName: 'grundwortschatz_en.db',
      assetPath: 'assets/grundwortschatz_en.db.gz',
    ),
  };

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  String _learningLanguage = 'de';
  String get learningLanguage => _learningLanguage;

  /// Set when initialize() fails. Surfaced to the splash screen so the
  /// retry dialog can be shown instead of silently broken games.
  Object? _initError;
  Object? get initError => _initError;

  void _log(String message) {
    if (kDebugMode) debugPrint('[VOCABULARY_SERVICE] 📚 $message');
  }

  /// Initializes the service by loading data from SQLite and SharedPrefs
  Future<void> initialize({
    String? learningLanguage,
    void Function(double progress, String message)? onProgress,
  }) async {
    final requestedLanguage = learningLanguage ?? await _loadLearningLanguage();
    if (!_dbSources.containsKey(requestedLanguage)) {
      throw ArgumentError.value(
        requestedLanguage,
        'learningLanguage',
        'Unsupported learning language',
      );
    }

    if (_isInitialized && _learningLanguage == requestedLanguage) return;
    if (_isInitialized && _learningLanguage != requestedLanguage) {
      await _dbService.close();
      _vocabulary.clear();
      _vocabularySets.clear();
      _allSourcesCache = null;
      _isInitialized = false;
    }

    _learningLanguage = requestedLanguage;
    _log('Initializing vocabulary service for $_learningLanguage...');
    try {
      // 1. Initialize DB with progress tracking
      onProgress?.call(0.0, 'Preparing vocabulary database...');
      final source = _dbSources[_learningLanguage]!;
      await _dbService.initialize(
        assetPath: source.assetPath ?? '',
        databaseName: source.databaseName,
        remoteUrl: source.remoteUrl,
        expectedCompressedBytes: source.expectedCompressedBytes,
        expectedDecompressedBytes: source.expectedDecompressedBytes,
        expectedDecompressedSha256: source.expectedDecompressedSha256,
        onProgress: (dbProgress, dbMessage) {
          // Map DB progress (0.0-1.0) to vocabulary service progress (0.0-0.6)
          onProgress?.call(dbProgress * 0.6, dbMessage);
        },
      );

      // 2. Load Words from SQLite
      onProgress?.call(0.6, 'Loading words...');
      await _loadVocabularyFromDB();

      // 3. Load User Customizations
      onProgress?.call(0.9, 'Loading your customizations...');
      await _loadCustomContent();
      await _loadVocabularySets();

      if (_vocabulary.isEmpty) {
        // Treat empty vocabulary as a hard error so the splash retry
        // dialog fires instead of letting games launch with no content.
        throw StateError(
          'Vocabulary loaded successfully but contains 0 words. '
          'DB asset may be missing or corrupted.',
        );
      }

      onProgress?.call(1.0, 'Ready!');
      _isInitialized = true;
      _initError = null;
      // Remember that a remotely-downloaded DB is now cached, so we don't
      // re-prompt for consent on subsequent launches.
      if (source.remoteUrl != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_downloadedFlagKey(_learningLanguage), true);
      }
      _log('✅ Vocabulary service initialized with ${_vocabulary.length} words');
      notifyListeners();
    } catch (e) {
      _log('❌ Error initializing vocabulary service: $e');
      _initError = e;
      _isInitialized = false;
      notifyListeners();
      rethrow;
    }
  }

  static String _downloadedFlagKey(String language) =>
      'db_downloaded_$language';

  /// Whether starting [language] (or the saved language) would trigger a
  /// first-time remote DB download, plus its size for disclosure. Returns
  /// `consentRequired: false` for bundled languages (e.g. English) and for a
  /// remote language whose DB is already cached on this device.
  Future<RemoteDownloadInfo> remoteDownloadInfo({String? language}) async {
    final lang = language ?? await _loadLearningLanguage();
    final source = _dbSources[lang];
    if (source?.remoteUrl == null) {
      return const RemoteDownloadInfo(consentRequired: false);
    }
    final prefs = await SharedPreferences.getInstance();
    final alreadyDownloaded =
        prefs.getBool(_downloadedFlagKey(lang)) ?? false;
    return RemoteDownloadInfo(
      consentRequired: !alreadyDownloaded,
      compressedBytes: source!.expectedCompressedBytes,
    );
  }

  Future<String> _loadLearningLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString(_learningLanguageKey) ?? 'de';
    return _dbSources.containsKey(language) ? language : 'de';
  }

  Future<void> setLearningLanguage(String language) async {
    if (!_dbSources.containsKey(language)) {
      throw ArgumentError.value(
        language,
        'language',
        'Unsupported learning language',
      );
    }
    if (language == _learningLanguage && _isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_learningLanguageKey, language);
    await initialize(learningLanguage: language);
  }

  /// Loads all words from SQLite into memory for game logic performance.
  /// Errors propagate to [initialize] so they can be surfaced to the user.
  Future<void> _loadVocabularyFromDB() async {
    final words = await _dbService.getAllWords();
    if (words.isNotEmpty) {
      _vocabulary = {for (var w in words) w.id: w};
      _log('Loaded ${_vocabulary.length} words from SQLite DB');
    } else {
      _log('⚠️ DB returned 0 words. Checking assets or DB integrity...');
    }
  }

  // ---------------------------------------------------------------------------
  // SEARCH METHODS
  // ---------------------------------------------------------------------------

  /// FAST ASYNC SEARCH: Uses SQLite FTS5 index.
  Future<List<GermanWord>> searchWordsAsync(String query) async {
    if (query.trim().isEmpty) return [];
    return await _dbService.searchWordsFTS(query);
  }

  /// SYNCHRONOUS SEARCH: Filters the in-memory map.
  List<GermanWord> searchWords(
    String query,
    GameProvider settingsProvider,
  ) {
    final baseWords = _getBaseWordList(settingsProvider);
    final filteredWords = _applyVocabularyFilters(baseWords, settingsProvider);

    final lowerQuery = query.toLowerCase();
    return filteredWords
        .where((word) =>
            word.word.toLowerCase().contains(lowerQuery) ||
            (word.forms?.toLowerCase().contains(lowerQuery) ?? false) ||
            (word.plural?.toLowerCase().contains(lowerQuery) ?? false))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // GAME LOGIC & FILTERING (Preserved from original)
  // ---------------------------------------------------------------------------

  GermanWord? getWordById(String id) => _vocabulary[id];

  List<GermanWord> getFullVocabularyList() {
    return _vocabulary.values.toList()
      ..sort((a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()));
  }

  List<GermanWord> getAllWords(GameProvider settingsProvider) {
    final baseWords = _getBaseWordList(settingsProvider);
    return _applyVocabularyFilters(baseWords, settingsProvider);
  }

  /// Phrasal verbs for the EN-only Phrasal Verb Power game. Empty for the
  /// German database (the `phrasal_verbs` table only exists in the EN DB).
  Future<List<PhrasalVerb>> getPhrasalVerbs() async {
    final rows = await _dbService.getPhrasalVerbs();
    return rows.map(PhrasalVerb.fromRow).toList();
  }

  /// DE↔EN false friends (EN database only). Empty for the German database.
  Future<List<FalseFriend>> getFalseFriends() async {
    final rows = await _dbService.getFalseFriends();
    return rows.map(FalseFriend.fromRow).toList();
  }

  List<GermanWord> getWordsByGrade(
    GradeLevel grade,
    GameProvider settingsProvider,
  ) {
    final baseWords = _getBaseWordList(settingsProvider, grade: grade);
    return _applyVocabularyFilters(baseWords, settingsProvider);
  }

  List<GermanWord> getWordsByCategory(
    WordCategory category,
    GameProvider settingsProvider,
  ) {
    final baseWords = _getBaseWordList(settingsProvider, category: category);
    return _applyVocabularyFilters(baseWords, settingsProvider);
  }

  List<GermanWord> getWordsByType(
    GermanWordType type,
    GameProvider settingsProvider,
  ) {
    final baseWords = _getBaseWordList(settingsProvider, wordType: type);
    return _applyVocabularyFilters(baseWords, settingsProvider);
  }

  // --- INTERNAL FILTERING LOGIC ---

  List<GermanWord> _getBaseWordList(
    GameProvider settingsProvider, {
    GradeLevel? grade,
    WordCategory? category,
    GermanWordType? wordType,
  }) {
    // 1. Custom Task Settings (Overrides standard logic)
    if (settingsProvider.tasksCustomizationEnabled) {
      final activeSetIds = settingsProvider.activeVocabularySetIds;

      // 1A. Specific Sets Selected
      if (activeSetIds.isNotEmpty) {
        final allWordIds = <String>{};
        for (final setId in activeSetIds) {
          final activeSet = _vocabularySets[setId];
          if (activeSet != null) {
            allWordIds.addAll(activeSet.wordIds);
          }
        }

        if (allWordIds.isNotEmpty) {
          return allWordIds
              .map((id) => _vocabulary[id])
              .whereType<GermanWord>()
              .toList();
        } else {
          settingsProvider.clearActiveVocabularySets();
        }
      }

      // 1B. Customization ON but no sets -> Use ALL words as base
      return _vocabulary.values.toList();
    }

    // 2. Standard Logic (Grade/Category/Type)
    var filtered = _vocabulary.values.toList();

    if (grade != null) {
      int targetGradeLevel;
      switch (grade) {
        case GradeLevel.grade1:
        case GradeLevel.grade2:
          targetGradeLevel = 1;
          break;
        case GradeLevel.grade3:
        case GradeLevel.grade4:
          targetGradeLevel = 2;
          break;
        default:
          targetGradeLevel = 3;
      }
      filtered =
          filtered.where((w) => w.gradeLevel == targetGradeLevel).toList();
    }
    if (category != null) {
      filtered =
          filtered.where((w) => w.categories.contains(category)).toList();
    }
    if (wordType != null) {
      filtered = filtered.where((w) => w.wordType == wordType).toList();
    }
    return filtered;
  }

  List<GermanWord> _applyVocabularyFilters(
    List<GermanWord> words,
    GameProvider settings,
  ) {
    if (!settings.tasksCustomizationEnabled) {
      return words;
    }

    final minLen = settings.taskWordLengthMin.round();
    final maxLen = settings.taskWordLengthMax.round();
    final includedSources = settings.taskIncludedSources;
    final includeWildcards = settings.taskIncludeWildcards;
    final excludeWildcards = settings.taskExcludeWildcards;

    return words.where((word) {
      final text = word.word;
      if (text.length < minLen || text.length > maxLen) return false;

      if (includedSources.isNotEmpty) {
        if (word.sources.isEmpty) return false;
        if (!word.sources.any((s) => includedSources.contains(s))) return false;
      }

      if (excludeWildcards.isNotEmpty) {
        if (excludeWildcards
            .any((pattern) => _matchesWildcard(text, pattern))) {
          return false;
        }
      }

      if (includeWildcards.isNotEmpty) {
        if (!includeWildcards
            .any((pattern) => _matchesWildcard(text, pattern))) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  bool _matchesWildcard(String text, String pattern) {
    try {
      final regexPattern = pattern
          .replaceAllMapped(
              RegExp(r'[.+^${}()|[\]\\]'), (match) => '\\${match.group(0)}')
          .replaceAll(r'*', '.*')
          .replaceAll(r'?', '.');
      return RegExp('^$regexPattern\$', caseSensitive: false).hasMatch(text);
    } catch (e) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // GENERATION LOGIC (Review, New Words, Random)
  // ---------------------------------------------------------------------------

  List<GermanWord> getWordsForSpellingReview(
    SriService sriService,
    GameProvider settingsProvider, {
    int limit = 10,
    GradeLevel? gradeFilter,
  }) {
    final reviewIds = sriService.getItemsForReview(
      limit: limit * 5,
      skillTypeFilter: LanguageSkillType.spelling,
      gradeLevelFilter: gradeFilter != null ? (gradeFilter.index + 1) : null,
    );

    final words = <GermanWord>[];
    for (final id in reviewIds) {
      final wordString = id.replaceFirst('SPELL_', '');
      try {
        final word = _vocabulary.values.firstWhere(
          (w) => w.word.toLowerCase() == wordString,
        );
        words.add(word);
      } catch (_) {
        // Word ID in SRI doesn't match current vocab
      }
    }
    final filteredWords = _applyVocabularyFilters(words, settingsProvider);
    return filteredWords.take(limit).toList();
  }

  List<GermanWord> getNewWords({
    required SriService sriService,
    required GameProvider settingsProvider,
    required GradeLevel grade,
    int limit = 5,
  }) {
    final potentialWords = _getBaseWordList(settingsProvider, grade: grade);
    var newWords = _applyVocabularyFilters(potentialWords, settingsProvider);

    final studiedWords = <String>{};
    for (final word in newWords) {
      final spellingId = sriService.getItemId(
        skillType: LanguageSkillType.spelling,
        baseWord: word.word,
      );
      if (sriService.getItemData(spellingId) != null) {
        studiedWords.add(word.id);
      }
    }

    var unstudiedWords =
        newWords.where((word) => !studiedWords.contains(word.id)).toList();

    unstudiedWords.shuffle();
    return unstudiedWords.take(limit).toList();
  }

  List<GermanWord> getRandomWords({
    int count = 4,
    required GameProvider settingsProvider,
    GradeLevel? grade,
    WordCategory? category,
    GermanWordType? wordType,
  }) {
    var filtered = _getBaseWordList(
      settingsProvider,
      grade: grade,
      category: category,
      wordType: wordType,
    );
    filtered = _applyVocabularyFilters(filtered, settingsProvider);

    if (filtered.isEmpty) {
      // Fallback: Try global list
      filtered = _applyVocabularyFilters(
          _vocabulary.values.toList(), settingsProvider);
      if (filtered.isEmpty) return [];
    }

    filtered.shuffle();
    return filtered.take(count).toList();
  }

  List<GermanWord> getSimilarWords(
    GermanWord baseWord, {
    int count = 3,
    required GameProvider settingsProvider,
  }) {
    final similar = <GermanWord>[];

    // 1. Check Graph. Variants
    final variantSpellings = baseWord.graphematicVariants
        .map((v) => v.spelling.toLowerCase())
        .toSet();

    final allFilteredWords =
        _applyVocabularyFilters(_vocabulary.values.toList(), settingsProvider);

    for (final word in allFilteredWords) {
      if (word.id == baseWord.id) continue;
      if (variantSpellings.contains(word.word.toLowerCase())) {
        similar.add(word);
      }
    }

    // 2. Check Levenshtein/Substring Similarity
    if (similar.length < count) {
      var allWords =
          allFilteredWords.where((w) => w.id != baseWord.id).toList();
      allWords.sort((a, b) => _calculateSimilarity(baseWord.word, a.word)
          .compareTo(_calculateSimilarity(baseWord.word, b.word)));
      similar.addAll(allWords.take(count - similar.length));
    }

    // 3. Fallback to random within grade
    if (similar.length < count) {
      final gradeEnum = GradeLevel.values[baseWord.gradeLevel.clamp(0, 5)];
      final random = getRandomWords(
        count: count - similar.length,
        settingsProvider: settingsProvider,
        grade: gradeEnum,
      ).where((w) => w.id != baseWord.id && !similar.contains(w));
      similar.addAll(random);
    }
    return similar.take(count).toList();
  }

  int _calculateSimilarity(String word1, String word2) {
    int diff = (word1.length - word2.length).abs();
    if (word1.startsWith(word2.substring(0, min(3, word2.length))) ||
        word2.startsWith(word1.substring(0, min(3, word1.length)))) {
      diff -= 3;
    }
    return diff;
  }

  // ---------------------------------------------------------------------------
  // CUSTOM CONTENT & SETS
  // ---------------------------------------------------------------------------

  Future<void> _loadCustomContent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customWordsJson = prefs.getString(_customWordsKey);
      if (customWordsJson != null) {
        final customWords =
            json.decode(customWordsJson) as Map<String, dynamic>;
        customWords.forEach((key, value) {
          _vocabulary[key] = GermanWord.fromJson(value);
        });
      }
    } catch (e) {
      _log('Error loading custom content: $e');
    }
  }

  Future<void> addCustomWord(GermanWord word) async {
    _vocabulary[word.id] = word;
    final prefs = await SharedPreferences.getInstance();
    final customWords = <String, dynamic>{};
    _vocabulary.forEach((key, value) {
      if (key.startsWith('custom_')) {
        customWords[key] = value.toJson();
      }
    });
    await prefs.setString(_customWordsKey, json.encode(customWords));
    notifyListeners();
  }

  // --- VOCABULARY SETS ---

  VocabularySet? getSetById(String id) => _vocabularySets[id];
  List<VocabularySet> get allSets => _vocabularySets.values.toList();

  List<VocabularySet> getSetsForGrade(GradeLevel grade) {
    return _vocabularySets.values
        .where((set) => set.targetGrade == grade)
        .toList();
  }

  List<VocabularySet> getCustomSets() {
    return _vocabularySets.values.where((set) => set.isCustom).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _loadVocabularySets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final setsJson = prefs.getString(_setsStorageKey);
      if (setsJson != null) {
        final sets = json.decode(setsJson) as Map<String, dynamic>;
        sets.forEach((key, value) {
          _vocabularySets[key] = VocabularySet.fromJson(value);
        });
      }
      _log('Loaded ${_vocabularySets.length} vocabulary sets');
    } catch (e) {
      _log('Error loading vocabulary sets: $e');
    }
  }

  void createDefaultSets(GameProvider settingsProvider) {
    final grade1Words = getWordsByGrade(GradeLevel.grade1, settingsProvider);
    if (grade1Words.isNotEmpty) {
      // Only create if it doesn't exist
      if (!_vocabularySets.containsKey('set_grade1_basics')) {
        _vocabularySets['set_grade1_basics'] = VocabularySet(
          id: 'set_grade1_basics',
          name: '1. Klasse Grundwortschatz',
          description: 'Die wichtigsten Wörter für die erste Klasse',
          wordIds: grade1Words.take(50).map((w) => w.id).toList(),
          targetGrade: GradeLevel.grade1,
          createdAt: DateTime.now(),
        );
      }
    }
  }

  Future<void> createCustomSet({
    required String name,
    required String description,
    required List<String> wordIds,
    required GradeLevel targetGrade,
  }) async {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    _vocabularySets[id] = VocabularySet(
      id: id,
      name: name,
      description: description,
      wordIds: wordIds,
      targetGrade: targetGrade,
      createdAt: DateTime.now(),
      isCustom: true,
    );
    await _saveVocabularySets();
    notifyListeners();
  }

  Future<void> updateCustomSet({
    required String id,
    String? name,
    String? description,
    List<String>? wordIds,
  }) async {
    final set = _vocabularySets[id];
    if (set == null || !set.isCustom) return;

    _vocabularySets[id] = VocabularySet(
      id: id,
      name: name ?? set.name,
      description: description ?? set.description,
      wordIds: wordIds ?? set.wordIds,
      targetGrade: set.targetGrade,
      createdAt: set.createdAt,
      isCustom: true,
    );
    await _saveVocabularySets();
    notifyListeners();
  }

  Future<void> deleteCustomSet(String id) async {
    final set = _vocabularySets.remove(id);
    if (set != null && set.isCustom) {
      await _saveVocabularySets();
      notifyListeners();
    }
  }

  Future<void> _saveVocabularySets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final setsJson = json.encode(
          _vocabularySets.map((key, value) => MapEntry(key, value.toJson())));
      await prefs.setString(_setsStorageKey, setsJson);
    } catch (e) {
      _log('Error saving vocabulary sets: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // UTILITIES & STATISTICS
  // ---------------------------------------------------------------------------

  Set<String> getAllAvailableSources() {
    if (_allSourcesCache != null) return _allSourcesCache!;
    final sources = <String>{};
    for (final word in _vocabulary.values) {
      if (word.sources.isNotEmpty) {
        sources.addAll(word.sources);
      }
    }
    _allSourcesCache = sources;
    return sources;
  }

  // Specific practice getters (Verbs/Cases/Adjectives)

  List<GermanWord> getWordsForCasePractice({
    int count = 10,
    required GameProvider settingsProvider,
    GradeLevel? grade,
    String? specificCase,
  }) {
    var baseWords = _getBaseWordList(settingsProvider, grade: grade);
    var filtered = _applyVocabularyFilters(baseWords, settingsProvider);

    filtered = filtered.where((w) {
      if (w.wordType != GermanWordType.pronomen &&
          w.wordType != GermanWordType.artikel) return false;
      if (w.caseSpacy == null || w.caseSpacy!.isEmpty) return false;
      if (specificCase != null && !w.caseSpacy!.contains(specificCase))
        return false;
      return true;
    }).toList();

    filtered.shuffle();
    return filtered.take(count).toList();
  }

  List<GermanWord> getVerbsForConjugationPractice({
    int count = 10,
    required GameProvider settingsProvider,
    GradeLevel? grade,
  }) {
    var baseWords = _getBaseWordList(settingsProvider, grade: grade);
    var filtered = _applyVocabularyFilters(baseWords, settingsProvider);

    filtered = filtered.where((w) {
      return w.wordType == GermanWordType.verb && w.verbFormSpacy == 'Inf';
    }).toList();

    filtered.shuffle();
    return filtered.take(count).toList();
  }

  List<GermanWord> getAdjectivesForComparisonPractice({
    int count = 10,
    required GameProvider settingsProvider,
    GradeLevel? grade,
  }) {
    var baseWords = _getBaseWordList(settingsProvider, grade: grade);
    var filtered = _applyVocabularyFilters(baseWords, settingsProvider);

    filtered = filtered.where((w) {
      return w.wordType == GermanWordType.adjektiv && w.degreeSpacy == 'Pos';
    }).toList();

    filtered.shuffle();
    return filtered.take(count).toList();
  }

  Map<String, dynamic> getWordStatistics(String wordId, SriService sriService) {
    final word = _vocabulary[wordId];
    if (word == null) return {};

    final stats = <String, dynamic>{
      'word': word.word,
      'gradeLevel': word.gradeLevel,
      'wordType': word.wordType,
    };

    // Spelling Stats
    final spellingData = sriService.getItemData(
      sriService.getItemId(
        skillType: LanguageSkillType.spelling,
        baseWord: word.word,
      ),
    );
    if (spellingData != null) {
      stats['spellingMastery'] = spellingData.easinessFactor / 5.0;
      final spellingAttempts =
          spellingData.successCount + spellingData.failureCount;
      stats['spellingAttempts'] = spellingAttempts;
      stats['spellingSuccessRate'] = spellingAttempts > 0
          ? spellingData.successCount / spellingAttempts
          : 0.0;
    }

    // Article Stats
    if (word.wordType == GermanWordType.substantiv &&
        word.article != null &&
        word.article!.isNotEmpty) {
      final articleData = sriService.getItemData(
        sriService.getItemId(
          skillType: LanguageSkillType.articleSelection,
          baseWord: word.word,
        ),
      );
      if (articleData != null) {
        stats['articleMastery'] = articleData.easinessFactor / 5.0;
      }
    }

    return stats;
  }

  Map<String, dynamic> exportProgress(
    SriService sriService,
    GameProvider settingsProvider,
  ) {
    final progress = <String, dynamic>{
      'exportDate': DateTime.now().toIso8601String(),
      'totalWords': _vocabulary.length,
      'wordProgress': <Map<String, dynamic>>[],
    };
    final wordsToExport = getAllWords(settingsProvider);
    for (final word in wordsToExport) {
      final wordStats = getWordStatistics(word.id, sriService);
      if (wordStats.length > 3) {
        progress['wordProgress'].add(wordStats);
      }
    }
    return progress;
  }
}
