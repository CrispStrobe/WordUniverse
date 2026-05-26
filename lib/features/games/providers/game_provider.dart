// lib/features/games/providers/game_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import '../../../core/services/progress_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/skill_category.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/cognitive_profile_service.dart';
import '../../../core/theme/app_fonts.dart';
import '../models/game_outcome.dart';
import '../tuning.dart';

/// User-facing difficulty mode picked from the menu. Shifts the grade
/// passed into a game so kids can sample easier or harder content
/// without changing their official grade selection.
enum DifficultyMode {
  easy,    // grade - 1 (clamped to 1)
  normal,  // grade
  challenge, // grade + 1
}

extension DifficultyModeShift on DifficultyMode {
  int get gradeShift {
    switch (this) {
      case DifficultyMode.easy:
        return -1;
      case DifficultyMode.normal:
        return 0;
      case DifficultyMode.challenge:
        return 1;
    }
  }
}

// Achievement class
class Achievement {
  final String id;
  final DateTime? unlockedAt;

  Achievement({
    required this.id,
    this.unlockedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'unlockedAt': unlockedAt?.toIso8601String(),
    };
  }

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'],
      unlockedAt: json['unlockedAt'] != null
          ? DateTime.parse(json['unlockedAt'])
          : null,
    );
  }
}

// The GameProvider class.
class GameProvider extends ChangeNotifier {
  final ProgressService _progressService;
  final SriService _sriService;
  final CognitiveProfileService _cognitiveProfileService;
  final SharedPreferences _prefs; 

  Set<String> _activeVocabularySetIds = {};

  String _selectedFontFamily = AppFonts.standard;

  // Getter
  String get selectedFontFamily => _selectedFontFamily;

  // Setter
  void setSelectedFontFamily(String fontFamily) {
    if (AppFonts.selectableFonts.containsKey(fontFamily)) {
      _selectedFontFamily = fontFamily;
      notifyListeners();
      _saveProgress(); 
    }
  }

  Set<String> get activeVocabularySetIds => _activeVocabularySetIds;

  // --- gameSkillMap ---
  final Map<String, SkillCategory> gameSkillMap = {
    'space_word_rescue': SkillCategories.getById('basic_spelling')!,
    'word_snake_game': SkillCategories.getById('basic_spelling')!,
    'word_find_game': SkillCategories.getById('basic_vocab')!,
    'word_sort_game': SkillCategories.getById('word_types')!, 
    'word_memory_game': SkillCategories.getById('basic_spelling')!,
    'word_builder_game': SkillCategories.getById('basic_spelling')!,
    'word_type_whirl_game': SkillCategories.getById('word_types')!,
    'wortbaumeister_game': SkillCategories.getById('word_types')!, 
    'grossstadt_game': SkillCategories.getById('basic_spelling')!, // Capitalization is spelling rules
    'grossschreib_game': SkillCategories.getById('word_types')!,
    'verbtrenner_game': SkillCategories.getById('word_types')!, // Separable verbs
    'spelling_spotter': SkillCategories.getById('basic_spelling')!,
    'sentence_completion': SkillCategories.getById('basic_vocab')!,
  };

  int _score = 0;
  int _level = 1;
  int _grade = 1;
  int _lives = 3;
  bool _soundEnabled = true;
  bool _musicEnabled = true;
  bool _puzzleTimerEnabled = true;
  bool _useAdaptiveDifficulty = false;
  Map<String, int> _gameProgress = {};
  List<Achievement> _achievements = [];
  bool _isFullVersionUnlocked = false;

  DifficultyMode _difficultyMode = DifficultyMode.normal;
  bool _useCustomProblemSettings = false;
  Set<String> _customOperations = {'addition', 'subtraction'}; 
  int _customRangeMin = 1;
  int _customRangeMax = 20;

  // Task Customization Settings 
  bool _tasksCustomizationEnabled = false;
  double _taskWordLengthMin = 2; 
  double _taskWordLengthMax = 10;
  Set<String> _taskIncludedSources = {}; 
  List<String> _taskIncludeWildcards = [];
  List<String> _taskExcludeWildcards = [];

  void toggleActiveVocabularySet(String setId) {
    if (_activeVocabularySetIds.contains(setId)) {
      _activeVocabularySetIds.remove(setId);
    } else {
      _activeVocabularySetIds.add(setId);
    }
    notifyListeners();
    _saveProgress();
  }

  void clearActiveVocabularySets() {
    _activeVocabularySetIds.clear();
    notifyListeners();
    _saveProgress();
  }

  // Constructor
  GameProvider({
    required ProgressService progressService,
    required SriService sriService,
    required CognitiveProfileService cognitiveProfileService,
    required SharedPreferences prefs, 
  })  : _progressService = progressService,
        _sriService = sriService,
        _cognitiveProfileService = cognitiveProfileService,
        _prefs = prefs { 
    if (!AppConfig.inapps_active) {
      _isFullVersionUnlocked = true;
    }
    // Load settings from prefs immediately
    _loadSettingsFromPrefs();
  }
  
  // Load settings from prefs on init
  void _loadSettingsFromPrefs() {
    _tasksCustomizationEnabled = _prefs.getBool('tasksCustomizationEnabled') ?? false;
    _taskWordLengthMin = _prefs.getDouble('taskWordLengthMin') ?? 2.0;
    _taskWordLengthMax = _prefs.getDouble('taskWordLengthMax') ?? 10.0;
    _taskIncludedSources = Set<String>.from(_prefs.getStringList('taskIncludedSources') ?? []);
    _taskIncludeWildcards = _prefs.getStringList('taskIncludeWildcards') ?? [];
    _taskExcludeWildcards = _prefs.getStringList('taskExcludeWildcards') ?? [];
    _activeVocabularySetIds = Set<String>.from(_prefs.getStringList('activeVocabularySetIds') ?? []);
    _selectedFontFamily = _prefs.getString('selectedFontFamily') ?? AppFonts.standard;
    if (!AppFonts.selectableFonts.containsKey(_selectedFontFamily)) {
      _selectedFontFamily = AppFonts.standard;
    }
    
    _score = _prefs.getInt('score') ?? 0;
    _level = _prefs.getInt('level') ?? 1;
    _grade = _prefs.getInt('grade') ?? 1;
    _lives = _prefs.getInt('lives') ?? 3;
    _soundEnabled = _prefs.getBool('soundEnabled') ?? true;
    _musicEnabled = _prefs.getBool('musicEnabled') ?? true;
    _gameProgress = Map<String, int>.from(
      jsonDecode(_prefs.getString('gameProgress') ?? '{}')
    );
    _useAdaptiveDifficulty = _prefs.getBool('useAdaptiveDifficulty') ?? false;
    _isFullVersionUnlocked = _prefs.getBool('isFullVersionUnlocked') ?? false;
    if (!AppConfig.inapps_active) {
      _isFullVersionUnlocked = true;
    }
    final difficultyModeIndex = _prefs.getInt('difficultyMode') ??
        DifficultyMode.normal.index;
    _difficultyMode = DifficultyMode.values[difficultyModeIndex
        .clamp(0, DifficultyMode.values.length - 1)];
    _useCustomProblemSettings = _prefs.getBool('useCustomProblemSettings') ?? false;
    _customOperations = Set<String>.from(_prefs.getStringList('customOperations') ?? ['addition', 'subtraction']);
    _customRangeMin = _prefs.getInt('customRangeMin') ?? 1;
    _customRangeMax = _prefs.getInt('customRangeMax') ?? 20;
    
    // Handle achievements loading safely
    try {
       _achievements = (_prefs.getStringList('achievements') ?? [])
          .map((a) => Achievement.fromJson(jsonDecode(a)))
          .toList();
    } catch (e) {
      debugPrint("Error loading achievements, resetting: $e");
      _achievements = [];
    }

    _currentLevelWins = Map<String, int>.from(
      jsonDecode(_prefs.getString('currentLevelWins') ?? '{}')
    );
  }

  Map<String, int> _currentLevelWins = {};

  // Getter
  bool get isFullVersionUnlocked => _isFullVersionUnlocked;

  // Setter 
  void unlockFullVersion() {
    _isFullVersionUnlocked = true;
    notifyListeners();
    _saveProgress();
  }

  // Getters
  int get score => _score;
  int get level => _level;
  int get grade => _grade; 
  int get lives => _lives;
  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;
  bool get puzzleTimerEnabled => _puzzleTimerEnabled;
  
  bool get useAdaptiveDifficulty => _useAdaptiveDifficulty;

  Map<String, int> get gameProgress => _gameProgress;
  List<Achievement> get achievements => _achievements;

  DifficultyMode get difficultyMode => _difficultyMode;
  bool get useCustomProblemSettings => _useCustomProblemSettings;
  Set<String> get customOperations => _customOperations;
  int get customRangeMin => _customRangeMin;
  int get customRangeMax => _customRangeMax;

  bool get tasksCustomizationEnabled => _tasksCustomizationEnabled;
  double get taskWordLengthMin => _taskWordLengthMin;
  double get taskWordLengthMax => _taskWordLengthMax;
  Set<String> get taskIncludedSources => _taskIncludedSources;
  List<String> get taskIncludeWildcards => _taskIncludeWildcards;
  List<String> get taskExcludeWildcards => _taskExcludeWildcards;

  /// Public wrapper so callers (e.g. app lifecycle handlers) can request
  /// a flush of all GameProvider-owned state to SharedPreferences without
  /// having to fake a recordLevelWin() call.
  Future<void> saveProgress() => _saveProgress();

  Future<void> _saveProgress() async {
    await _prefs.setBool('tasksCustomizationEnabled', _tasksCustomizationEnabled);
    await _prefs.setDouble('taskWordLengthMin', _taskWordLengthMin);
    await _prefs.setDouble('taskWordLengthMax', _taskWordLengthMax);
    await _prefs.setStringList('taskIncludedSources', _taskIncludedSources.toList());
    await _prefs.setStringList('taskIncludeWildcards', _taskIncludeWildcards);
    await _prefs.setStringList('taskExcludeWildcards', _taskExcludeWildcards);
    await _prefs.setStringList('activeVocabularySetIds', _activeVocabularySetIds.toList());
    await _prefs.setString('selectedFontFamily', _selectedFontFamily);
    
    await _prefs.setInt('score', _score);
    await _prefs.setInt('level', _level);
    await _prefs.setInt('grade', _grade);
    await _prefs.setInt('lives', _lives);
    await _prefs.setBool('soundEnabled', _soundEnabled);
    await _prefs.setBool('musicEnabled', _musicEnabled);
    await _prefs.setString('gameProgress', jsonEncode(_gameProgress));
    await _prefs.setBool('useAdaptiveDifficulty', _useAdaptiveDifficulty);
    await _prefs.setBool('isFullVersionUnlocked', _isFullVersionUnlocked);
    await _prefs.setInt('difficultyMode', _difficultyMode.index);
    await _prefs.setBool('useCustomProblemSettings', _useCustomProblemSettings);
    await _prefs.setStringList('customOperations', _customOperations.toList());
    await _prefs.setInt('customRangeMin', _customRangeMin);
    await _prefs.setInt('customRangeMax', _customRangeMax);
    await _prefs.setStringList('achievements', _achievements.map((a) => jsonEncode(a.toJson())).toList());
    await _prefs.setString('currentLevelWins', jsonEncode(_currentLevelWins));
    
    // Call the old ProgressService (in case it does more than just save to prefs)
    _progressService.saveProgress(this);
  }

  /// Canonical end-of-level reporting entry point. Every game should
  /// funnel through here.
  ///
  /// Returns true iff the player advanced to the next level as a result
  /// of this outcome.
  bool reportOutcome(GameOutcome outcome) {
    debugPrint(
        '[GAME_PROVIDER] 🎯 Recording ${outcome.gameType} result: '
        '${outcome.wasSuccessful ? "WIN" : "LOSS"} at difficulty ${outcome.difficulty}');

    if (outcome.wasSuccessful) addScore(outcome.score);

    _currentLevelWins[outcome.gameType] =
        (_currentLevelWins[outcome.gameType] ?? 0) +
            (outcome.wasSuccessful ? 1 : 0);

    final skill = gameSkillMap[outcome.gameType];
    if (skill == null) {
      debugPrint('[GAME_PROVIDER] ⚠️ Unknown game type: ${outcome.gameType}');
      return false;
    }

    if (skill.category != LanguageCategory.rechtschreibung &&
        skill.category != LanguageCategory.grammatik) {
      _cognitiveProfileService.recordAttempt(
          skill, outcome.difficulty, outcome.wasSuccessful);
    }

    bool didAdvance = false;
    if (outcome.wasSuccessful &&
        canAdvanceToNextLevel(
            outcome.gameType, _gameProgress[outcome.gameType] ?? 1)) {
      advanceLevel(outcome.gameType);
      didAdvance = true;
    }

    if (!didAdvance) {
      notifyListeners();
    }

    _saveProgress();
    return didAdvance;
  }

  /// Legacy shim. Prefer [reportOutcome] with a [GameOutcome] factory.
  @Deprecated('Use reportOutcome(GameOutcome.win/.loss/.fromRatio(...))')
  bool recordLevelWin({
    required String gameType,
    required int scoreGained,
    required int difficulty,
    required bool wasSuccessful,
  }) {
    return reportOutcome(GameOutcome(
      gameType: gameType,
      difficulty: difficulty,
      score: scoreGained,
      wasSuccessful: wasSuccessful,
    ));
  }

  bool canAdvanceToNextLevel(String gameType, int currentLevel) {
    if ((_currentLevelWins[gameType] ?? 0) < kWinsRequiredForLevelUp) {
      debugPrint('[GAME_PROVIDER] ❌ $gameType: '
          'Only ${_currentLevelWins[gameType] ?? 0}/$kWinsRequiredForLevelUp wins');
      return false;
    }

    final skill = gameSkillMap[gameType];
    if (skill == null) return false;

    if (skill.category == LanguageCategory.rechtschreibung) {
      return _checkSpellingMastery(currentLevel);
    } else {
      return _cognitiveProfileService.hasMastery(skill, currentLevel);
    }
  }

  void advanceLevel(String gameType) {
    debugPrint('[GAME_PROVIDER] 📈 $gameType advancing to level ${(_gameProgress[gameType] ?? 1) + 1}');
    updateGameProgress(gameType, (_gameProgress[gameType] ?? 1) + 1);
    _currentLevelWins[gameType] = 0;
  }

  bool _checkSpellingMastery(int difficulty) { 
    final breakdown = _sriService.getDetailedBreakdown();
    final gradeStats = breakdown[LanguageSkillType.spelling];
    if (gradeStats == null) return false;

    final stat = gradeStats[_grade]; 
    if (stat == null) return false;

    final hasMastery = stat.tracked >= kMinTrackedItemsForMastery &&
        stat.successRate >= kDefaultPassThreshold;
    debugPrint('[GAME_PROVIDER] Spelling mastery @ Grade $_grade: ${stat.mastered}/${stat.tracked} (${stat.successRate * 100}%) ${hasMastery ? "✓" : "✗"}');
    return hasMastery;
  }

  // --- Setters for Custom Settings ---
  void setDifficultyMode(DifficultyMode mode) {
    if (_difficultyMode == mode) return;
    _difficultyMode = mode;
    notifyListeners();
    _saveProgress();
  }

  void setUseCustomSettings(bool value) {
    _useCustomProblemSettings = value;
    notifyListeners();
  }

  void setCustomOperations(Set<String> operations) {
    _customOperations = operations;
    notifyListeners();
  }

  void setCustomRange({required int min, required int max}) {
    if (min <= max) {
      _customRangeMin = min;
      _customRangeMax = max;
      notifyListeners();
    }
  }

  // --- Setters for Task Customization ---
  void setTasksCustomizationEnabled(bool enabled) {
    _tasksCustomizationEnabled = enabled;
    notifyListeners();
    _saveProgress();
  }

  void setTaskWordLengthRange(double min, double max) {
    _taskWordLengthMin = min;
    _taskWordLengthMax = max;
    notifyListeners();
    _saveProgress();
  }

  void setTaskIncludedSources(Set<String> sources) {
    _taskIncludedSources = sources;
    notifyListeners();
    _saveProgress();
  }

  void setTaskIncludeWildcards(List<String> wildcards) {
    _taskIncludeWildcards = wildcards;
    notifyListeners();
    _saveProgress();
  }

  void setTaskExcludeWildcards(List<String> wildcards) {
    _taskExcludeWildcards = wildcards;
    notifyListeners();
    _saveProgress();
  }

  // Score management
  void addScore(int points) {
    _score += points;
    _checkAchievements();
    notifyListeners();
  }

  void setPuzzleTimer(bool enabled) {
    _puzzleTimerEnabled = enabled;
    notifyListeners();
  }

  void resetScore() {
    _score = 0;
    notifyListeners();
  }

  // Level management
  void nextLevel() {
    _level++;
    notifyListeners();
    _saveProgress();
  }

  void setLevel(int level) {
    _level = level;
    notifyListeners();
  }

  void setDifficulty(int newGrade, int newLevel) {
    _grade = newGrade;
    _level = newLevel;
    notifyListeners();
    _saveProgress();
  }

  // Grade/Skill Level management
  void setGrade(int grade) {
    _grade = grade.clamp(1, 6); 
    _level = 1; 
    notifyListeners();
    _saveProgress();
  }

  // Setter for adaptive difficulty
  void setUseAdaptiveDifficulty(bool value) {
    _useAdaptiveDifficulty = value;
    notifyListeners();
  }

  // Lives management
  void loseLife() {
    if (_lives > 0) {
      _lives--;
      notifyListeners();
    }
  }

  void resetLives() {
    _lives = 3;
    notifyListeners();
  }

  void addLife() {
    _lives++;
    notifyListeners();
  }

  // Settings
  void toggleSound() {
    _soundEnabled = !_soundEnabled;
    notifyListeners();
    _saveProgress(); 
  }

  void toggleMusic() {
    _musicEnabled = !_musicEnabled;
    notifyListeners();
    _saveProgress(); 
  }

  void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
    notifyListeners();
    _saveProgress();
  }

  void setMusicEnabled(bool enabled) {
    _musicEnabled = enabled;
    notifyListeners();
    _saveProgress();
  }

  // Game progress tracking
  void updateGameProgress(String gameType, int level) {
    _gameProgress[gameType] = level;
    _checkAchievements();
    notifyListeners();
    _saveProgress();
  }

  int getGameProgress(String gameType) {
    return _gameProgress[gameType] ?? 0;
  }

  // Achievement system
  void _checkAchievements() {
    final newAchievements = <Achievement>[];
    
    if (_score >= 100 && !hasAchievement('first_century')) { newAchievements.add(Achievement(id: 'first_century')); }
    if (_score >= 500 && !hasAchievement('score_master')) { newAchievements.add(Achievement(id: 'score_master')); }
    if (_score >= 1000 && !hasAchievement('thousand_club')) { newAchievements.add(Achievement(id: 'thousand_club')); }
    if (_level >= 5 && !hasAchievement('level_explorer')) { newAchievements.add(Achievement(id: 'level_explorer')); }
    if (_level >= 10 && !hasAchievement('space_commander')) { newAchievements.add(Achievement(id: 'space_commander')); }
    
    if ((_gameProgress['word_snake_game'] ?? 0) >= 3 && !hasAchievement('triangle_wizard')) { newAchievements.add(Achievement(id: 'triangle_wizard')); }
    if ((_gameProgress['word_sort_game'] ?? 0) >= 3 && !hasAchievement('bubble_popper')) { newAchievements.add(Achievement(id: 'bubble_popper')); }
    if ((_gameProgress['word_find_game'] ?? 0) >= 3 && !hasAchievement('puzzle_solver')) { newAchievements.add(Achievement(id: 'puzzle_solver')); }
    if ((_gameProgress['word_builder_game'] ?? 0) >= 3 && !hasAchievement('number_walls_pro')) { newAchievements.add(Achievement(id: 'number_walls_pro')); }
    if ((_gameProgress['space_word_rescue'] ?? 0) >= 3 && !hasAchievement('codebreaker_pro')) { newAchievements.add(Achievement(id: 'codebreaker_pro')); }
    if ((_gameProgress['wortbaumeister_game'] ?? 0) >= 3 && !hasAchievement('master_builder')) { 
      newAchievements.add(Achievement(id: 'master_builder')); 
    }
    if ((_gameProgress['grossstadt_game'] ?? 0) >= 3 && !hasAchievement('city_planner')) { 
      newAchievements.add(Achievement(id: 'city_planner')); 
    }
    if ((_gameProgress['grossschreib_game'] ?? 0) >= 3 && !hasAchievement('connection_expert')) { 
      newAchievements.add(Achievement(id: 'connection_expert')); 
    }

    if ((_gameProgress['word_memory_game'] ?? 0) >= 5 && 
        (_gameProgress['word_type_whirl_game'] ?? 0) >= 5 &&
        !hasAchievement('arithmetic_ace')) { 
        newAchievements.add(Achievement(id: 'arithmetic_ace')); 
    }

    final gamesCompleted = _gameProgress.values.where((level) => level >= 1).length;
    if (gamesCompleted >= 4 && !hasAchievement('all_rounder')) {
      newAchievements.add(Achievement(id: 'all_rounder'));
    }

    if (newAchievements.isNotEmpty) {
      for (var ach in newAchievements) {
        if (!hasAchievement(ach.id)) {
          _achievements.add(ach);
        }
      }
    }
  }


  bool hasAchievement(String achievementId) {
    return _achievements.any((achievement) => achievement.id == achievementId);
  }

  // Game state management
  void resetGame() {
    _score = 0;
    _level = 1;
    _lives = 3;
    _achievements.clear(); 
    _gameProgress.clear();
    notifyListeners();
    _saveProgress();
  }

  void startNewGame(String gameType) {
    _score = 0;
    _lives = 3;
    notifyListeners();
  }

  // Statistics
  int get totalGamesPlayed {
    if (_gameProgress.isEmpty) return 0;
    return _gameProgress.values.reduce((a, b) => a + b);
  }
  
  int get totalAchievements => _achievements.length;

  double get averageLevel {
    if (_gameProgress.isEmpty) return 0.0;
    final totalLevels = _gameProgress.values.fold(0, (sum, level) => sum + level);
    return totalLevels / _gameProgress.length;
  }

  // Grade progression
  bool canProgressToNextGrade() {
    final totalLevelsInGrade = _gameProgress.values.fold(0, (sum, level) => sum + level);
    final requiredLevels = _grade * 3;
    return totalLevelsInGrade >= requiredLevels;
  }

  void progressToNextGrade() {
    if (canProgressToNextGrade() && _grade < 6) {
      _grade++;
      _level = 1;
      _gameProgress.clear();

      if (!hasAchievement('grade_$_grade')) {
        _achievements.add(Achievement(id: 'grade_$_grade'));
      }

      notifyListeners();
    }
  }
}