// lib/core/services/cognitive_profile_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/games/tuning.dart';
import '../models/skill_category.dart';

class SkillStats {
  int attempts;
  int successes;

  SkillStats({this.attempts = 0, this.successes = 0});

  Map<String, dynamic> toJson() => {'a': attempts, 's': successes};
  
  factory SkillStats.fromJson(Map<String, dynamic> json) =>
      SkillStats(attempts: json['a'] ?? 0, successes: json['s'] ?? 0);
}

class CognitiveProfileService extends ChangeNotifier {
  Map<SkillCategory, Map<int, SkillStats>> _skillData = {};

  /// Read-only snapshot of all tracked skill stats. Returns fresh copies
  /// so consumers can't mutate internal state.
  Map<SkillCategory, Map<int, SkillStats>> get snapshot {
    return {
      for (final entry in _skillData.entries)
        entry.key: {
          for (final inner in entry.value.entries)
            inner.key: SkillStats(
              attempts: inner.value.attempts,
              successes: inner.value.successes,
            ),
        },
    };
  }

  /// Total attempts logged across all skills/difficulties.
  int get totalAttempts {
    int n = 0;
    for (final diffMap in _skillData.values) {
      for (final stats in diffMap.values) {
        n += stats.attempts;
      }
    }
    return n;
  }

  static const _storageKey = 'cognitive_profile';

  void _log(String message) {
    debugPrint('[COGNITIVE_PROFILE] 🧠 $message');
  }

  void recordAttempt(SkillCategory skill, int difficulty, bool success) {
    _log('Recording attempt for ${skill.name} at difficulty $difficulty: ${success ? "SUCCESS" : "FAILURE"}');
    
    _skillData[skill] ??= {};
    _skillData[skill]![difficulty] ??= SkillStats();

    final stats = _skillData[skill]![difficulty]!;
    stats.attempts++;
    if (success) stats.successes++;

    _log('Updated stats for ${skill.name} @ $difficulty: ${stats.successes}/${stats.attempts}');
    
    notifyListeners();
    saveProfile();
  }

  bool hasMastery(SkillCategory skill, int difficulty,
      {double threshold = kDefaultPassThreshold}) {
    final stats = _skillData[skill]?[difficulty];
    if (stats == null || stats.attempts < kMinAttemptsForMastery) {
      _log('No mastery for ${skill.name} @ $difficulty (insufficient data)');
      return false;
    }
    
    final masteryLevel = stats.successes / stats.attempts;
    final hasMastery = masteryLevel >= threshold;
    _log('Mastery check for ${skill.name} @ $difficulty: ${(masteryLevel * 100).toStringAsFixed(1)}% ${hasMastery ? "✓" : "✗"}');
    
    return hasMastery;
  }

  Future<void> saveProfile() async {
    _log('Saving cognitive profile...');
    try {
      final prefs = await SharedPreferences.getInstance();
      // --- FIX: Save using skill.id as the key, not the object ---
      final json = _skillData.map((skill, diffMap) => MapEntry(
        skill.id, // Use ID for stable serialization
        diffMap.map((diff, stats) => MapEntry(diff.toString(), stats.toJson()))
      ));
      await prefs.setString(_storageKey, jsonEncode(json));
      _log('✅ Cognitive profile saved successfully');
    } catch (e) {
      _log('❌ Error saving profile: $e');
    }
  }

  Future<void> loadProfile() async {
    _log('Loading cognitive profile...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        _skillData = json.map((skillId, diffMap) {
          // --- FIX: Load using SkillCategories.all, not SkillCategory.values ---
          final skill = SkillCategories.all.firstWhere(
            (e) => e.id == skillId, // Find by ID
            orElse: () => SkillCategories.all.first, // Fallback
          );
          final diffMapTyped = (diffMap as Map<String, dynamic>).map(
            (diffStr, statsJson) => MapEntry(
              int.parse(diffStr),
              SkillStats.fromJson(statsJson)
            )
          );
          return MapEntry(skill, diffMapTyped);
        });
        _log('✅ Loaded ${_skillData.length} skill categories');
      } else {
        _log('No saved profile found. Starting fresh.');
      }
    } catch (e) {
      _log('❌ Error loading profile: $e');
      _skillData = {};
    }
    notifyListeners();
  }
}