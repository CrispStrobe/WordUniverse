// lib/core/services/vocabulary_service.dart

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';

// Import GameProvider to access settings
import '../../features/games/providers/game_provider.dart';

// --- CLEAN IMPORTS ---
import '../models/skill_category.dart';
import '../models/vocabulary_models.dart';
import 'sri_service.dart';

// Main vocabulary service
class VocabularyService with ChangeNotifier {
  Map<String, GermanWord> _vocabulary = {};
  Map<String, GrammarExercise> _grammarExercises = {};
  Map<String, VocabularySet> _vocabularySets = {};

  Set<String>? _allSourcesCache;

  static const _vocabularyStorageKey = 'german_vocabulary';
  static const _setsStorageKey = 'vocabulary_sets';
  static const _customWordsKey = 'custom_words';

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  void _log(String message) {
    debugPrint('[VOCABULARY_SERVICE] 📚 $message');
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _log('Initializing vocabulary service...');
    try {
      await _loadVocabularyFromAssets();
      await _loadCustomContent();
      await _loadVocabularySets();
      _isInitialized = true;
      _log('✅ Vocabulary service initialized with ${_vocabulary.length} words');
      notifyListeners();
    } catch (e) {
      _log('❌ Error initializing vocabulary service: $e');
      throw Exception('Failed to initialize vocabulary service: $e');
    }
  }

  Future<void> _loadVocabularyFromAssets() async {
    try {
      // --- THIS FILENAME MATCHES OUR ENRICHED JSON ---
      final String jsonString = await rootBundle.loadString(
          'lib/features/games/data/grundwortschatz_safe.json');

      final Map<String, dynamic> jsonData = json.decode(jsonString);
      final List<dynamic> vocabulary = jsonData['vocabulary'] as List<dynamic>;
      for (final wordData in vocabulary) {
        final word = GermanWord.fromJson(wordData as Map<String, dynamic>);
        if (word.word.length <= 1) continue;
        if (word.lemma.contains('(') || word.lemma.contains(')')) continue;
        final wordType = word.wordType;
        if (wordType == GermanWordType.andere ||
            wordType == GermanWordType.affix) continue;
        _vocabulary[word.id] = word;
      }
      if (jsonData.containsKey('grammarExercises')) {
        final exercises = jsonData['grammarExercises'] as List<dynamic>;
        for (final exerciseData in exercises) {
          final exercise =
              GrammarExercise.fromJson(exerciseData as Map<String, dynamic>);
          _grammarExercises[exercise.id] = exercise;
        }
      }
      _log('Loaded ${_vocabulary.length} words from assets');
    } catch (e) {
      _log('Warning: Could not load vocabulary from assets: $e');
      _log(
          'Check that the grundwortschatz json is in your pubspec.yaml');
      _initializeSampleVocabulary();
    }
  }

  GermanWord _parseWordFromCsvRow(List<dynamic> row, int index) {
    return _initializeSampleVocabulary().values.first; // Placeholder
  }

  GermanWordType _determineWordType(
      String word, String? article, String? forms) {
    if (article != null) return GermanWordType.substantiv;
    if (forms != null && forms.contains('du ')) return GermanWordType.verb;
    if (word.endsWith('en') || word.endsWith('ern') || word.endsWith('eln'))
      return GermanWordType.verb;
    if (forms != null && (forms.contains('er') || forms.contains('ste')))
      return GermanWordType.adjektiv;
    if (_isPreposition(word)) return GermanWordType.praeposition;
    if (_isConjunction(word)) return GermanWordType.konjunktion;
    return GermanWordType.andere;
  }

  bool _isPreposition(String word) {
    const prepositions = {
      'ab', 'an', 'auf', 'aus', 'bei', 'bis', 'durch', 'für', 'gegen',
      'hinter', 'in', 'mit', 'nach', 'neben', 'ohne', 'seit', 'über',
      'um', 'unter', 'von', 'vor', 'während', 'wegen', 'zu', 'zwischen'
    };
    return prepositions.contains(word);
  }

  bool _isConjunction(String word) {
    const conjunctions = {
      'und', 'oder', 'aber', 'denn', 'sondern', 'als', 'wenn', 'weil',
      'da', 'dass', 'ob', 'obwohl', 'während', 'bevor', 'nachdem'
    };
    return conjunctions.contains(word);
  }

  SpellingDifficulty _calculateSpellingDifficulty(String word, String? forms) {
    int score = 0;
    if (word.length > 10) score += 2;
    else if (word.length > 7) score += 1;
    if (word.contains('ä') || word.contains('ö') || word.contains('ü')) score += 1;
    if (word.contains('ß')) score += 2;
    if (RegExp(r'(.)\1').hasMatch(word)) score += 1;
    if (word.contains('sch') || word.contains('ch') || word.contains('ck')) score += 1;
    if (forms != null && forms.split(',').length > 2) score += 2;
    if (score <= 1) return SpellingDifficulty.easy;
    if (score <= 3) return SpellingDifficulty.medium;
    if (score <= 5) return SpellingDifficulty.hard;
    return SpellingDifficulty.expert;
  }

  Map<String, GermanWord> _initializeSampleVocabulary() {
    _vocabulary = {
      'word_001': GermanWord(
        id: 'word_001',
        word: 'Haus',
        article: 'das',
        wordType: GermanWordType.substantiv,
        gradeLevel: 1,
        lemma: 'Haus',
        caseSpacy: 'Nom',
        numberSpacy: 'Sing',
        plural: 'Häuser',
        categories: [WordCategory.zuhause],
        exampleSentences: ['Das Haus ist groß.'],
        spellingDifficulty: SpellingDifficulty.easy,
        commonMistakes: ['Hauss'],
        sources: ["A1"],
        isGrundwortschatzBW: true,
        nurImPlural: false,
        graphematicVariants: [
          GraphematicVariant(spelling: "Hauss", probability: 0.5)
        ],
      ),
      'word_002': GermanWord(
        id: 'word_002',
        word: 'spielen',
        wordType: GermanWordType.verb,
        gradeLevel: 1,
        lemma: 'spielen',
        verbFormSpacy: 'Inf',
        categories: [WordCategory.aktivitaeten],
        exampleSentences: ['Die Kinder spielen im Garten.'],
        spellingDifficulty: SpellingDifficulty.easy,
        article: null,
        sources: ["A1"],
        isGrundwortschatzBW: true,
        nurImPlural: false,
        graphematicVariants: [],
      ),
    };
    _log('Initialized with ${_vocabulary.length} sample words');
    return _vocabulary;
  }

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
        _log('Loaded ${customWords.length} custom words');
      }
    } catch (e) {
      _log('Error loading custom content: $e');
    }
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
      if (_vocabularySets.isEmpty) {
        // Cannot call _createDefaultSets here, must be called from provider
      }
      _log('Loaded ${_vocabularySets.length} vocabulary sets');
    } catch (e) {
      _log('Error loading vocabulary sets: $e');
    }
  }

  void createDefaultSets(GameProvider settingsProvider) {
    // Renamed
    final grade1Words = getWordsByGrade(GradeLevel.grade1, settingsProvider);
    if (grade1Words.isNotEmpty) {
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

  Set<String> getAllAvailableSources() {
    if (_allSourcesCache != null) return _allSourcesCache!;
    final sources = <String>{};
    for (final word in _vocabulary.values) {
      if (word.sources.isNotEmpty) {
        sources.addAll(word.sources);
      }
    }
    _allSourcesCache = sources;
    _log('Found ${sources.length} unique sources: $sources');
    return sources;
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
      _log('Invalid wildcard pattern: $pattern');
      return false;
    }
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

    var filteredWords = words.where((word) {
      final text = word.word;
      if (text.length < minLen || text.length > maxLen) return false;
      if (includedSources.isNotEmpty) {
        if (word.sources.isEmpty) return false;
        if (!word.sources.any((s) => includedSources.contains(s))) return false;
      }
      if (excludeWildcards.isNotEmpty) {
        if (excludeWildcards.any((pattern) => _matchesWildcard(text, pattern)))
          return false;
      }
      if (includeWildcards.isNotEmpty) {
        if (!includeWildcards.any((pattern) => _matchesWildcard(text, pattern)))
          return false;
      }
      return true;
    }).toList();

    _log('Applied filters: ${words.length} -> ${filteredWords.length} words');
    return filteredWords;
  }

  // Diese Funktion entscheidet, WELCHE Liste an _applyVocabularyFilters gesendet wird.
  List<GermanWord> _getBaseWordList(
    GameProvider settingsProvider, {
    GradeLevel? grade,
    WordCategory? category,
    GermanWordType? wordType,
  }) {
    // --- PRIORITY 1: Is the entire feature enabled? ---
    if (settingsProvider.tasksCustomizationEnabled) {
      // --- PRIORITY 1A: Are custom sets active? ---
      final activeSetIds = settingsProvider.activeVocabularySetIds;
      if (activeSetIds.isNotEmpty) {
        final allWordIds = <String>{};
        for (final setId in activeSetIds) {
          final activeSet = _vocabularySets[setId];
          if (activeSet != null) {
            allWordIds.addAll(activeSet.wordIds);
          } else {
            _log('Warning: Active set $setId not found.');
          }
        }

        if (allWordIds.isNotEmpty) {
          _log(
              'Using ${allWordIds.length} unique words from ${activeSetIds.length} custom set(s)');
          // Return only the words from these sets
          return allWordIds
              .map((id) => _vocabulary[id])
              .whereType<GermanWord>()
              .toList();
        } else {
          _log('Warning: Active sets were specified but yielded no words.');
          // Fallback: clear the invalid IDs and use automatic filters
          settingsProvider.clearActiveVocabularySets();
        }
      }

      // --- PRIORITY 1B: No custom sets, use automatic filters ---
      _log('Task customization enabled, using all words as base list.');
      return _vocabulary.values.toList(); // Starte mit ALLEN Wörtern
    }

    // --- PRIORITY 2: Feature is OFF. Use standard grade/category logic ---
    _log('Task customization disabled, using standard filters (grade/category).');
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

  List<GermanWord> getFullVocabularyList() {
    return _vocabulary.values.toList()
      ..sort((a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()));
  }

  List<GermanWord> getAllWords(GameProvider settingsProvider) {
    final baseWords = _getBaseWordList(settingsProvider);
    return _applyVocabularyFilters(baseWords, settingsProvider);
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

  GermanWord? getWordById(String id) => _vocabulary[id];

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
      } catch (e) {
        _log(
            'Error finding word for SRI ID: $id. Word: "$wordString" not in vocab?');
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

  VocabularySet? getSetById(String id) => _vocabularySets[id];
  List<VocabularySet> get allSets => _vocabularySets.values.toList();
  List<VocabularySet> getSetsForGrade(GradeLevel grade) {
    return _vocabularySets.values
        .where((set) => set.targetGrade == grade)
        .toList();
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

  Future<void> _saveVocabularySets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final setsJson = json.encode(
          _vocabularySets.map((key, value) => MapEntry(key, value.toJson())));
      await prefs.setString(_setsStorageKey, setsJson);
      _log('Saved ${_vocabularySets.length} vocabulary sets');
    } catch (e) {
      _log('Error saving vocabulary sets: $e');
    }
  }

  List<GrammarExercise> getGrammarExercises({
    GrammarTopic? topic,
    GradeLevel? grade,
  }) {
    return _grammarExercises.values.where((exercise) {
      if (topic != null && exercise.topic != topic) return false;
      if (grade != null && exercise.gradeLevel != grade) return false;
      return true;
    }).toList();
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
      _log(
          "Warning: getRandomWords resulted in an empty list. Returning any words.");
      filtered = _applyVocabularyFilters(
          _vocabulary.values.toList(), settingsProvider);
      if (filtered.isEmpty) {
        _log("CRITICAL: No words even after fallback. Returning empty list.");
        return [];
      }
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
    final variantSpellings =
        baseWord.graphematicVariants.map((v) => v.spelling.toLowerCase()).toSet();

    final allFilteredWords =
        _applyVocabularyFilters(_vocabulary.values.toList(), settingsProvider);

    for (final word in allFilteredWords) {
      if (word.id == baseWord.id) continue;
      if (variantSpellings.contains(word.word.toLowerCase())) {
        similar.add(word);
      }
    }
    if (similar.length < count) {
      var allWords = allFilteredWords.where((w) => w.id != baseWord.id).toList();
      allWords.sort((a, b) =>
          _calculateSimilarity(baseWord.word, a.word)
              .compareTo(_calculateSimilarity(baseWord.word, b.word)));
      similar.addAll(allWords.take(count - similar.length));
    }
    if (similar.length < count) {
      final gradeEnum =
          GradeLevel.values[baseWord.gradeLevel.clamp(0, 5)];
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
    if (word.wordType == GermanWordType.pronomen ||
        word.wordType == GermanWordType.artikel) {
      final caseData = sriService.getItemData(
        sriService.getItemId(
          skillType: LanguageSkillType.caseUsage,
          baseWord: word.word,
        ),
      );
      if (caseData != null) {
        stats['caseMastery'] = caseData.easinessFactor / 5.0;
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
      targetGrade: set.targetGrade, // Or allow changing this
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
      _log('Deleted custom set: $id');
    }
  }

  List<VocabularySet> getCustomSets() {
    return _vocabularySets.values
        .where((set) => set.isCustom)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}