// lib/core/services/vocabulary_service.dart

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';

import '../models/skill_category.dart';
import 'sri_service.dart';

// NEW: Data model for the graphematic variants
class GraphematicVariant {
  final String spelling;
  final double probability;

  GraphematicVariant({required this.spelling, required this.probability});

  factory GraphematicVariant.fromJson(Map<String, dynamic> json) {
    return GraphematicVariant(
      spelling: json['spelling'],
      probability: (json['probability'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'spelling': spelling,
        'probability': probability,
      };
}

// Data models for vocabulary
/// MODIFIED: This class is now much richer
class GermanWord {
  final String id;
  final String word;
  final String? article;
  final GermanWordType wordType;
  final int gradeLevel;
  final String lemma;
  final String? forms;
  final String? url;

  // --- NEW FIELDS from enriched JSON ---
  final List<String> sources;
  final bool isGrundwortschatzBW;
  final String? genus;
  final bool nurImPlural;
  
  final Map<String, dynamic>? inflectionData;
  final String? ipaPhoneme;

  final String? sampaPhoneme;
  final List<GraphematicVariant> graphematicVariants; // The new variants!

  final String? caseSpacy;
  final String? numberSpacy;
  final String? degreeSpacy;
  final String? pronTypeSpacy;
  final String? verbFormSpacy;

  // Existing fields
  final String? plural;
  final List<WordCategory> categories;
  final List<String> exampleSentences;
  final SpellingDifficulty spellingDifficulty;
  final List<String>? commonMistakes;
  final String? audioPath;

  GermanWord({
    required this.id,
    required this.word,
    this.article,
    required this.wordType,
    required this.gradeLevel,
    required this.lemma,
    this.forms,
    this.url,

    // New fields
    required this.sources,
    required this.isGrundwortschatzBW,
    this.genus,
    required this.nurImPlural,
    
    this.inflectionData,
    this.ipaPhoneme,

    this.sampaPhoneme,
    required this.graphematicVariants,
    this.caseSpacy,
    this.numberSpacy,
    this.degreeSpacy,
    this.pronTypeSpacy,
    this.verbFormSpacy,

    // Existing fields
    this.plural,
    required this.categories,
    required this.exampleSentences,
    required this.spellingDifficulty,
    this.commonMistakes,
    this.audioPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'word': word,
        'article': article,
        'wordType': wordType.toString().split('.').last,
        'gradeLevel': gradeLevel,
        'lemma': lemma,
        'forms': forms,
        'url': url,
        'sources': sources,
        'isGrundwortschatzBW': isGrundwortschatzBW,
        'genus': genus,
        'nurImPlural': nurImPlural,
        'ipaPhoneme': ipaPhoneme,
        'sampaPhoneme': sampaPhoneme,
        'graphematicVariants':
            graphematicVariants.map((v) => v.toJson()).toList(),
        'caseSpacy': caseSpacy,
        'numberSpacy': numberSpacy,
        'degreeSpacy': degreeSpacy,
        'pronTypeSpacy': pronTypeSpacy,
        'verbFormSpacy': verbFormSpacy,
        'plural': plural,
        'categories': categories.map((c) => c.toString().split('.').last).toList(),
        'exampleSentences': exampleSentences,
        'spellingDifficulty': spellingDifficulty.index,
        'commonMistakes': commonMistakes,
        'audioPath': audioPath,
      };

  factory GermanWord.fromJson(Map<String, dynamic> json) {
    // Parse the variants
    final variantsList = (json['graphematicVariants'] as List<dynamic>?) ?? [];
    final variants = variantsList
        .map((v) => GraphematicVariant.fromJson(v as Map<String, dynamic>))
        .toList();

    return GermanWord(
      id: json['id'],
      word: json['word'],
      article: json['article'],
      wordType: GermanWordType.values.firstWhere(
        (e) => e.toString().split('.').last == json['wordType'],
        orElse: () => GermanWordType.andere,
      ),
      gradeLevel: json['gradeLevel'] ?? 1,
      lemma: json['lemma'] ?? json['word'],
      forms: json['forms'],
      url: json['url'],

      // New fields
      sources: List<String>.from(json['sources'] ?? []),
      isGrundwortschatzBW: json['isGrundwortschatzBW'] ?? false,
      genus: json['genus'],
      nurImPlural: json['nurImPlural'] ?? false,
      inflectionData: json['inflectionData'] as Map<String, dynamic>?,
      ipaPhoneme: json['ipaPhoneme'],
      sampaPhoneme: json['sampaPhoneme'],
      graphematicVariants: variants,

      // New fields
      caseSpacy: json['caseSpacy'],
      numberSpacy: json['numberSpacy'],
      degreeSpacy: json['degreeSpacy'],
      pronTypeSpacy: json['pronTypeSpacy'],
      verbFormSpacy: json['verbFormSpacy'],

      // Existing fields
      plural: json['plural'],
      categories: (json['categories'] as List<dynamic>?)
              ?.map((c) => WordCategory.values.firstWhere(
                    (e) => e.toString().split('.').last == c,
                    orElse: () => WordCategory.schule,
                  ))
              .toList() ??
          [],
      exampleSentences: List<String>.from(json['exampleSentences'] ?? []),
      spellingDifficulty:
          SpellingDifficulty.values[json['spellingDifficulty'] ?? 0],
      commonMistakes: json['commonMistakes'] != null
          ? List<String>.from(json['commonMistakes'])
          : null,
      audioPath: json['audioPath'],
    );
  }

  String get displayName {
    if (wordType == GermanWordType.substantiv &&
        article != null &&
        article!.isNotEmpty) {
      return '$article $word';
    }
    return word;
  }
}

enum SpellingDifficulty {
  easy,
  medium,
  hard,
  expert,
}

// Grammar exercise data
class GrammarExercise {
  final String id;
  final GrammarTopic topic;
  final GradeLevel gradeLevel;
  final String instruction;
  final String sentence;
  final List<String> options;
  final String correctAnswer;
  final String explanation;

  GrammarExercise({
    required this.id,
    required this.topic,
    required this.gradeLevel,
    required this.instruction,
    required this.sentence,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
  });

  factory GrammarExercise.fromJson(Map<String, dynamic> json) {
    return GrammarExercise(
      id: json['id'],
      topic: GrammarTopic.values.firstWhere(
        (e) => e.toString().split('.').last == json['topic'],
      ),
      gradeLevel: GradeLevel.values[json['gradeLevel'] ?? 0],
      instruction: json['instruction'],
      sentence: json['sentence'],
      options: List<String>.from(json['options']),
      correctAnswer: json['correctAnswer'],
      explanation: json['explanation'],
    );
  }
}

// Learning set for organizing content
class VocabularySet {
  final String id;
  final String name;
  final String description;
  final List<String> wordIds;
  final GradeLevel targetGrade;
  final DateTime createdAt;
  final bool isCustom;

  VocabularySet({
    required this.id,
    required this.name,
    required this.description,
    required this.wordIds,
    required this.targetGrade,
    required this.createdAt,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'wordIds': wordIds,
        'targetGrade': targetGrade.index,
        'createdAt': createdAt.toIso8601String(),
        'isCustom': isCustom,
      };

  factory VocabularySet.fromJson(Map<String, dynamic> json) {
    return VocabularySet(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      wordIds: List<String>.from(json['wordIds']),
      targetGrade: GradeLevel.values[json['targetGrade'] ?? 0],
      createdAt: DateTime.parse(json['createdAt']),
      isCustom: json['isCustom'] ?? false,
    );
  }
}

// Main vocabulary service
class VocabularyService with ChangeNotifier {
  Map<String, GermanWord> _vocabulary = {};
  Map<String, GrammarExercise> _grammarExercises = {};
  Map<String, VocabularySet> _vocabularySets = {};

  static const _vocabularyStorageKey = 'german_vocabulary';
  static const _setsStorageKey = 'vocabulary_sets';
  static const _customWordsKey = 'custom_words';

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  void _log(String message) {
    debugPrint('[VOCABULARY_SERVICE] 📚 $message');
  }

  // Initialize service and load data
  Future<void> initialize() async {
    if (_isInitialized) return;

    _log('Initializing vocabulary service...');

    try {
      // Load base vocabulary from assets
      await _loadVocabularyFromAssets();

      // Load custom words and sets from storage
      await _loadCustomContent();

      // Load predefined vocabulary sets
      await _loadVocabularySets();

      _isInitialized = true;
      _log('✅ Vocabulary service initialized with ${_vocabulary.length} words');
      notifyListeners();
    } catch (e) {
      _log('❌ Error initializing vocabulary service: $e');
      throw Exception('Failed to initialize vocabulary service: $e');
    }
  }

  // Load vocabulary from JSON assets
  Future<void> _loadVocabularyFromAssets() async {
    try {
      final String jsonString = await rootBundle.loadString(
          'lib/features/games/data/grundwortschatz_variations.json');

      // We decode the file as a Map, not a List
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // Then we get the list of words from the "vocabulary" key inside the map
      final List<dynamic> vocabulary = jsonData['vocabulary'] as List<dynamic>;
      
      for (final wordData in vocabulary) {
        final word = GermanWord.fromJson(wordData as Map<String, dynamic>);
        
        // 1. Skip 1-character words (e.g., "%", "a", ".")
        if (word.word.length <= 1) {
          continue; 
        }
        
        // 2. Skip malformed lemmata
        if (word.lemma.contains('(') || word.lemma.contains(')')) {
          continue; 
        }
        
        // 3. Skip non-content words (symbols, affixes, etc.)
        final wordType = word.wordType;
        if (wordType == GermanWordType.andere || 
            wordType == GermanWordType.affix) {
          continue; 
        }
        
        _vocabulary[word.id] = word;
      }

      // Check if 'grammarExercises' key exists in the map
      if (jsonData.containsKey('grammarExercises')) {
        final exercises = jsonData['grammarExercises'] as List<dynamic>;
        for (final exerciseData in exercises) {
          final exercise = GrammarExercise.fromJson(exerciseData as Map<String, dynamic>);
          _grammarExercises[exercise.id] = exercise;
        }
      }

      _log('Loaded ${_vocabulary.length} words from assets');
    } catch (e) {
      _log('Warning: Could not load vocabulary from assets: $e');
      _log('Check that "lib/features/games/data/grundwortschatz_variations.json" is in your pubspec.yaml');
      _initializeSampleVocabulary();
    }
  }

  // (This method is no longer used to parse CSVs, but we'll keep its helpers)
  GermanWord _parseWordFromCsvRow(List<dynamic> row, int index) {
    // ... (logic removed as it's now handled by JSON)
    // Kept _initializeSampleVocabulary which depends on this class structure
    return _initializeSampleVocabulary().values.first; // Placeholder
  }

  // Helper to determine word type
  GermanWordType _determineWordType(String word, String? article, String? forms) {
    if (article != null) {
      return GermanWordType.substantiv;
    } else if (forms != null && forms.contains('du ')) {
      return GermanWordType.verb;
    } else if (word.endsWith('en') || word.endsWith('ern') || word.endsWith('eln')) {
      return GermanWordType.verb;
    } else if (forms != null && (forms.contains('er') || forms.contains('ste'))) {
      return GermanWordType.adjektiv;
    } else if (_isPreposition(word)) {
      return GermanWordType.praeposition;
    } else if (_isConjunction(word)) {
      return GermanWordType.konjunktion;
    } else {
      return GermanWordType.andere;
    }
  }

  // Helper methods
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

  // Initialize with sample vocabulary (fallback)
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
        // Add new required fields
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
        // Add new required fields
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

  // Load custom words from storage
  Future<void> _loadCustomContent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customWordsJson = prefs.getString(_customWordsKey);

      if (customWordsJson != null) {
        final customWords = json.decode(customWordsJson) as Map<String, dynamic>;
        customWords.forEach((key, value) {
          _vocabulary[key] = GermanWord.fromJson(value);
        });
        _log('Loaded ${customWords.length} custom words');
      }
    } catch (e) {
      _log('Error loading custom content: $e');
    }
  }

  // Load vocabulary sets
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

      // Create default sets if none exist
      if (_vocabularySets.isEmpty) {
        _createDefaultSets();
      }

      _log('Loaded ${_vocabularySets.length} vocabulary sets');
    } catch (e) {
      _log('Error loading vocabulary sets: $e');
      _createDefaultSets();
    }
  }

  // Create default vocabulary sets
  void _createDefaultSets() {
    final grade1Words = getWordsByGrade(GradeLevel.grade1);

    if (grade1Words.isNotEmpty) {
      // Only create if words exist
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

  // Get all words
  List<GermanWord> get allWords => _vocabulary.values.toList();

  // Get words by grade level
  List<GermanWord> getWordsByGrade(GradeLevel grade) {
    int targetGradeLevel;
    switch (grade) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        targetGradeLevel = 1; // Our level 1
        break;
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        targetGradeLevel = 2; // Our level 2 (A2)
        break;
      case GradeLevel.grade5:
      case GradeLevel.grade6:
        targetGradeLevel = 3; // Our level 3 (B1)
        break;
      default:
        targetGradeLevel = 1;
    }

    return _vocabulary.values
        .where((word) => word.gradeLevel == targetGradeLevel)
        .toList();
  }

  // Get words by category
  List<GermanWord> getWordsByCategory(WordCategory category) {
    return _vocabulary.values
        .where((word) => word.categories.contains(category))
        .toList();
  }

  // Get words by word type
  List<GermanWord> getWordsByType(GermanWordType type) {
    return _vocabulary.values
        .where((word) => word.wordType == type)
        .toList();
  }

  // Get specific word by ID
  GermanWord? getWordById(String id) => _vocabulary[id];

  // Search words
  List<GermanWord> searchWords(String query) {
    final lowerQuery = query.toLowerCase();
    return _vocabulary.values
        .where((word) =>
            word.word.toLowerCase().contains(lowerQuery) ||
            (word.forms?.toLowerCase().contains(lowerQuery) ?? false) ||
            (word.plural?.toLowerCase().contains(lowerQuery) ?? false))
        .toList();
  }

  // Get words for review based on SRS data
  List<GermanWord> getWordsForSpellingReview(
    SriService sriService, {
    int limit = 10,
    GradeLevel? gradeFilter,
  }) {
    final reviewIds = sriService.getItemsForReview(
      limit: limit,
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

    return words;
  }

  // Get new words that haven't been studied
  List<GermanWord> getNewWords({
    required SriService sriService,
    required GradeLevel grade,
    int limit = 5,
  }) {
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

    final studiedWords = <String>{};

    for (final word in _vocabulary.values) {
      final spellingId = sriService.getItemId(
        skillType: LanguageSkillType.spelling,
        baseWord: word.word,
      );

      if (sriService.getItemData(spellingId) != null) {
        studiedWords.add(word.id);
      }
    }

    var potentialWords = _vocabulary.values
        .where((word) =>
            word.gradeLevel == targetGradeLevel &&
            !studiedWords.contains(word.id))
        .toList();

    potentialWords.shuffle();
    return potentialWords.take(limit).toList();
  }

  // Get vocabulary set
  VocabularySet? getSetById(String id) => _vocabularySets[id];

  // Get all vocabulary sets
  List<VocabularySet> get allSets => _vocabularySets.values.toList();

  // Get sets for grade
  List<VocabularySet> getSetsForGrade(GradeLevel grade) {
    return _vocabularySets.values
        .where((set) => set.targetGrade == grade)
        .toList();
  }

  // Create custom vocabulary set
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

  // Save vocabulary sets
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

  // Get grammar exercises
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

  // Add custom word (for teacher/parent mode)
  Future<void> addCustomWord(GermanWord word) async {
    _vocabulary[word.id] = word;

    // Save to storage
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

  // Get random words for games
  List<GermanWord> getRandomWords({
    int count = 4,
    GradeLevel? grade,
    WordCategory? category,
    GermanWordType? wordType,
  }) {
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

    if (filtered.isEmpty) {
      _log("Warning: getRandomWords resulted in an empty list. Returning any words.");
      filtered = _vocabulary.values.toList();
    }

    filtered.shuffle();
    return filtered.take(count).toList();
  }

  // Get similar words (for confusion practice)
  List<GermanWord> getSimilarWords(GermanWord baseWord, {int count = 3}) {
    // First, use the pre-calculated graphematic variants
    final similar = <GermanWord>[];
    final variantSpellings =
        baseWord.graphematicVariants.map((v) => v.spelling.toLowerCase()).toSet();

    // Find words in the vocab that match these common misspellings
    for (final word in _vocabulary.values) {
      if (word.id == baseWord.id) continue;
      if (variantSpellings.contains(word.word.toLowerCase())) {
        similar.add(word);
      }
    }

    // If not enough, find words with similar spelling (Levenshtein distance)
    if (similar.length < count) {
      var allWords =
          _vocabulary.values.where((w) => w.id != baseWord.id).toList();
      allWords.sort((a, b) =>
          _calculateSimilarity(baseWord.word, a.word)
              .compareTo(_calculateSimilarity(baseWord.word, b.word)));
      similar.addAll(allWords.take(count - similar.length));
    }

    // If still still not enough, add random ones from the same grade
    if (similar.length < count) {
      final gradeEnum = GradeLevel.values[baseWord.gradeLevel.clamp(0, 5)];
      final random = getRandomWords(
        count: count - similar.length,
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

  /// Get words for Case (Fall) practice
  List<GermanWord> getWordsForCasePractice({
    int count = 10,
    GradeLevel? grade,
    String? specificCase, // e.g., "Dat", "Acc"
  }) {
    var filtered = _vocabulary.values.where((w) {
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
        if (w.gradeLevel != targetGradeLevel) return false;
      }

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

  /// Get verbs for Conjugation practice
  List<GermanWord> getVerbsForConjugationPractice({
    int count = 10,
    GradeLevel? grade,
  }) {
    var filtered = _vocabulary.values.where((w) {
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
        if (w.gradeLevel != targetGradeLevel) return false;
      }

      return w.wordType == GermanWordType.verb && w.verbFormSpacy == 'Inf';
    }).toList();

    filtered.shuffle();
    return filtered.take(count).toList();
  }

  /// NEW: Get adjectives for comparison (Steigerung) practice
  List<GermanWord> getAdjectivesForComparisonPractice({
    int count = 10,
    GradeLevel? grade,
  }) {
    var filtered = _vocabulary.values.where((w) {
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
        if (w.gradeLevel != targetGradeLevel) return false;
      }

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

    // Get SRS data for spelling
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

    // Get SRS data for article
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

    // NEW: Get SRS data for case
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

  // Export learning progress (for parents/teachers)
  Map<String, dynamic> exportProgress(SriService sriService) {
    final progress = <String, dynamic>{
      'exportDate': DateTime.now().toIso8601String(),
      'totalWords': _vocabulary.length,
      'wordProgress': <Map<String, dynamic>>[],
    };

    for (final word in _vocabulary.values) {
      final wordStats = getWordStatistics(word.id, sriService);
      if (wordStats.length > 3) {
        progress['wordProgress'].add(wordStats);
      }
    }

    return progress;
  }
}