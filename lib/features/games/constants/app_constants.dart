// lib/features/games/constants/app_constants.dart:

class AppConstants {
  // App Information
  static const String appName = 'Word Mastery';
  static const String appVersion = '1.0.0';
  
  // Game Configuration
  static const int minGrade = 3;
  static const int maxGrade = 6;
  static const int maxLives = 3;
  static const int baseTimeLimit = 60; // seconds
  
  // Scoring System
  static const int correctAnswerPoints = 10;
  static const int levelCompleteBonus = 100;
  static const int timeBonus = 5; // points per second remaining
  static const int perfectGameBonus = 200;
  
  // Game Types
  static const String magicTrianglesGame = 'magic_triangles';
  static const String bubbleMathGame = 'bubble_math';
  static const String puzzleMathGame = 'puzzle_math';
  
  // Animation Durations
  static const Duration fastAnimation = Duration(milliseconds: 200);
  static const Duration normalAnimation = Duration(milliseconds: 400);
  static const Duration slowAnimation = Duration(milliseconds: 800);
  
  // Sound Files
  static const String correctSound = 'correct.mp3';
  static const String incorrectSound = 'incorrect.mp3';
  static const String levelCompleteSound = 'level_complete.mp3';
  static const String backgroundMusic = 'space_ambient.mp3';
  static const String buttonClickSound = 'button_click.mp3';
  
  // Achievement IDs
  static const String firstCenturyAchievement = 'first_century';
  static const String scoreMasterAchievement = 'score_master';
  static const String thousandClubAchievement = 'thousand_club';
  static const String triangleWizardAchievement = 'triangle_wizard';
  static const String bubblePopperAchievement = 'bubble_popper';
  static const String puzzleSolverAchievement = 'puzzle_solver';
  static const String allRounderAchievement = 'all_rounder';
  static const String arithmeticAceAchievement = 'arithmetic_ace';
  static const String logicGridMasterAchievement = 'logic_grid_master';
  
  // Math Operation Symbols
  static const String additionSymbol = '+';
  static const String subtractionSymbol = '-';
  static const String multiplicationSymbol = '×';
  static const String divisionSymbol = '÷';
  
  // Difficulty Settings
  static Map<int, DifficultySettings> get difficultyByGrade => {
    3: const DifficultySettings(
      maxNumber: 20,
      operationsCount: 2,
      bubbleCount: 6,
      puzzlePieces: 4,
      timeLimit: 90,
    ),
    4: const DifficultySettings(
      maxNumber: 50,
      operationsCount: 3,
      bubbleCount: 8,
      puzzlePieces: 6,
      timeLimit: 80,
    ),
    5: const DifficultySettings(
      maxNumber: 100,
      operationsCount: 4,
      bubbleCount: 10,
      puzzlePieces: 8,
      timeLimit: 70,
    ),
    6: const DifficultySettings(
      maxNumber: 200,
      operationsCount: 4,
      bubbleCount: 12,
      puzzlePieces: 9,
      timeLimit: 60,
    ),
  };
  
  // Storage Keys
  static const String gameDataKey = 'game_data';
  static const String settingsKey = 'settings';
  static const String achievementsKey = 'achievements';
  static const String progressKey = 'progress';
  
  // UI Constants
  static const double cardBorderRadius = 20.0;
  static const double buttonBorderRadius = 25.0;
  static const double defaultPadding = 16.0;
  static const double largePadding = 24.0;
  
  // Screen Breakpoints
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 900.0;
  static const double desktopBreakpoint = 1200.0;
  
  // Game Rules
  static const int maxAttemptsPerLevel = 3;
  static const int levelsPerGrade = 10;
  static const double minimumAccuracy = 0.7; // 70% to pass level
  
  // Asset Paths
  static const String imagesPath = 'assets/images/';
  static const String soundsPath = 'assets/sounds/';
  static const String animationsPath = 'assets/animations/';
  static const String fontsPath = 'assets/fonts/';
  
  // Network/API (for future features)
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
  
  // Accessibility
  static const Duration tooltipDuration = Duration(seconds: 3);
  static const double minimumTouchTarget = 44.0;
  static const double textScaleFactor = 1.0;
  
  // Performance
  static const int maxCachedImages = 50;
  static const int maxCachedSounds = 20;
  static const Duration cacheExpiry = Duration(hours: 24);
}

class DifficultySettings {
  final int maxNumber;
  final int operationsCount;
  final int bubbleCount;
  final int puzzlePieces;
  final int timeLimit;
  
  const DifficultySettings({
    required this.maxNumber,
    required this.operationsCount,
    required this.bubbleCount,
    required this.puzzlePieces,
    required this.timeLimit,
  });
}

// Grade-specific math operations
class MathOperations {
  static List<String> getOperationsForGrade(int grade) {
    switch (grade) {
      case 3:
        return [AppConstants.additionSymbol, AppConstants.subtractionSymbol];
      case 4:
        return [
          AppConstants.additionSymbol,
          AppConstants.subtractionSymbol,
          AppConstants.multiplicationSymbol,
        ];
      case 5:
      case 6:
      default:
        return [
          AppConstants.additionSymbol,
          AppConstants.subtractionSymbol,
          AppConstants.multiplicationSymbol,
          AppConstants.divisionSymbol,
        ];
    }
  }
  
  static Map<String, int> getNumberRangesForGrade(int grade) {
    switch (grade) {
      case 3:
        return {'min': 1, 'max': 20};
      case 4:
        return {'min': 1, 'max': 50};
      case 5:
        return {'min': 1, 'max': 100};
      case 6:
      default:
        return {'min': 1, 'max': 200};
    }
  }
}


class AchievementConfig {
  final String title;
  final String description;
  final String icon;
  final int requirement;
  final AchievementType type;
  
  const AchievementConfig({
    required this.title,
    required this.description,
    required this.icon,
    required this.requirement,
    required this.type,
  });
}

enum AchievementType {
  score,
  level,
  games,
  accuracy,
  speed,
  consecutive,
}

// Game State Enums
enum GameState {
  menu,
  playing,
  paused,
  completed,
  gameOver,
}

enum GameResult {
  win,
  lose,
  timeout,
  perfect,
}

enum MathOperation {
  addition,
  subtraction,
  multiplication,
  division,
}

// Difficulty Levels
enum DifficultyLevel {
  easy,
  medium,
  hard,
  expert,
}

// Settings
class DefaultSettings {
  static const bool soundEnabled = true;
  static const bool musicEnabled = true;
  static const bool hapticFeedback = true;
  static const bool showHints = true;
  static const bool autoSave = true;
  static const String defaultLanguage = 'en';
  static const double masterVolume = 0.7;
  static const double sfxVolume = 0.8;
  static const double musicVolume = 0.5;
}
