// lib/features/games/constants/difficulty_manager.dart

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
// Import SRI Service
import '../providers/game_provider.dart';

class DifficultyManager {
  static DifficultyConfig getDifficulty(GameProvider gameProvider, int level) {
    final grade = gameProvider.grade;
    final baseLevel = grade.clamp(1, 4);
    final effectiveGameLevel = level.clamp(1, 20);

    // --- NEW: Check for and apply custom settings ---
    if (gameProvider.useCustomProblemSettings && gameProvider.customOperations.isNotEmpty) {
      debugPrint("[DifficultyManager] 🔧 Using custom problem settings override.");
      final customOps = gameProvider.customOperations.map((opString) {
        return MathOperation.values.firstWhere((e) => e.toString() == 'MathOperation.$opString');
      }).toList();

      return DifficultyConfig(
        grade: baseLevel,
        level: effectiveGameLevel,
        difficultyMultiplier: 1.5, // A fixed multiplier for custom mode
        numberRange: {
          'min': gameProvider.customRangeMin,
          'max': gameProvider.customRangeMax,
        },
        operationTypes: customOps,
        equationProbability: 0.5, // Fixed probability for custom mode
        objectCount: 8,
        timeLimit: 120,
        gameSpeed: 150,
        showHints: true,
        animationSpeed: 1.0,
        visualComplexity: 1.5,
      );
    }
    
    // --- Fallback to original logic if custom settings are off ---
    final levelMultiplier = baseLevel * 0.4; // 0.4, 0.8, 1.2, 1.6
    
    final gameLevelMultiplier = (effectiveGameLevel - 1) * 0.05; // 0 to 0.95
    final totalDifficulty = 1.0 + levelMultiplier + gameLevelMultiplier;
    
    return DifficultyConfig(
      grade: baseLevel, // Still called 'grade' internally for simplicity
      level: effectiveGameLevel,
      difficultyMultiplier: totalDifficulty,
      numberRange: _calculateNumberRange(baseLevel, effectiveGameLevel),
      operationTypes: _getOperationTypes(baseLevel, effectiveGameLevel),
      equationProbability: _calculateEquationProbability(baseLevel, effectiveGameLevel),
      objectCount: _calculateObjectCount(baseLevel, effectiveGameLevel),
      timeLimit: _calculateTimeLimit(baseLevel, effectiveGameLevel),
      gameSpeed: _calculateGameSpeed(baseLevel, effectiveGameLevel),
      showHints: effectiveGameLevel <= 3,
      animationSpeed: 1.0 + (gameLevelMultiplier * 0.5),
      visualComplexity: totalDifficulty,
    );
  }
  
  static Map<String, int> _calculateNumberRange(int skillLevel, int level) {
    final baseMax = [0, 15, 25, 40, 80][skillLevel]; // Index 1-4
    final levelBonus = (level - 1) * 3;
    final maxNumber = baseMax + levelBonus;
    return {'min': level <= 5 ? 1 : 2, 'max': maxNumber,};
  }
  
  static List<MathOperation> _getOperationTypes(int skillLevel, int level) {
    final operations = <MathOperation>[MathOperation.addition];
    if (skillLevel >= 1 || level >= 3) operations.add(MathOperation.subtraction);
    if (skillLevel >= 2 || level >= 5) operations.add(MathOperation.multiplication);
    if (skillLevel >= 3 || level >= 8) operations.add(MathOperation.division);
    return operations;
  }
  
  static double _calculateEquationProbability(int skillLevel, int level) {
    final baseProbability = 0.2 + (skillLevel - 1) * 0.15;
    final levelBonus = (level - 1) * 0.03;
    return (baseProbability + levelBonus).clamp(0.1, 0.8);
  }

  static int _calculateObjectCount(int skillLevel, int level) {
    final baseCount = 4 + skillLevel;
    final levelBonus = (level - 1) ~/ 2;
    return (baseCount + levelBonus).clamp(4, 15);
  }

  static int _calculateTimeLimit(int skillLevel, int level) {
    final baseTime = 120 - (skillLevel - 1) * 15; // 120, 105, 90, 75
    final levelPenalty = (level - 1) * 2;
    return (baseTime - levelPenalty).clamp(45, 180);
  }

  static double _calculateGameSpeed(int skillLevel, int level) {
    final baseSpeed = 60.0 + (skillLevel - 1) * 20.0;
    final levelBonus = (level - 1) * 3.0;
    return baseSpeed + levelBonus;
  }
}

class DifficultyConfig {
  final int grade;
  final int level;
  final double difficultyMultiplier;
  final Map<String, int> numberRange;
  final List<MathOperation> operationTypes;
  final double equationProbability;
  final int objectCount;
  final int timeLimit;
  final double gameSpeed;
  final bool showHints;
  final double animationSpeed;
  final double visualComplexity;
  
  const DifficultyConfig({
    required this.grade,
    required this.level,
    required this.difficultyMultiplier,
    required this.numberRange,
    required this.operationTypes,
    required this.equationProbability,
    required this.objectCount,
    required this.timeLimit,
    required this.gameSpeed,
    required this.showHints,
    required this.animationSpeed,
    required this.visualComplexity,
  });
}