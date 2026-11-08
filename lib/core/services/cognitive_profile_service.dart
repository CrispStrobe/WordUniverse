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
  Map<String, dynamic> _preservedProfile = {};
  String? _unreadableProfile;

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
    if (kDebugMode) debugPrint('[COGNITIVE_PROFILE] 🧠 $message');
  }

  void recordAttempt(SkillCategory skill, int difficulty, bool success) {
    _log(
        'Recording attempt for ${skill.name} at difficulty $difficulty: ${success ? "SUCCESS" : "FAILURE"}');

    _skillData[skill] ??= {};
    _skillData[skill]![difficulty] ??= SkillStats();

    final stats = _skillData[skill]![difficulty]!;
    stats.attempts++;
    if (success) stats.successes++;

    _log(
        'Updated stats for ${skill.name} @ $difficulty: ${stats.successes}/${stats.attempts}');

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
    _log(
        'Mastery check for ${skill.name} @ $difficulty: ${(masteryLevel * 100).toStringAsFixed(1)}% ${hasMastery ? "✓" : "✗"}');

    return hasMastery;
  }

  Future<void> saveProfile() async {
    _log('Saving cognitive profile...');
    try {
      final prefs = await SharedPreferences.getInstance();
      // --- FIX: Save using skill.id as the key, not the object ---
      if (_unreadableProfile != null) {
        final key = prefs.containsKey('${_storageKey}_recovery')
            ? '${_storageKey}_recovery_${DateTime.now().microsecondsSinceEpoch}'
            : '${_storageKey}_recovery';
        if (!await prefs.setString(key, _unreadableProfile!)) {
          throw StateError('Could not preserve unreadable profile');
        }
        _unreadableProfile = null;
      }
      final json = <String, dynamic>{
        ..._preservedProfile,
        ..._skillData.map((skill, diffMap) => MapEntry(
                skill.id, // Use ID for stable serialization
                <String, dynamic>{
                  if (_preservedProfile[skill.id] is Map)
                    ...Map<String, dynamic>.from(
                        _preservedProfile[skill.id] as Map),
                  ...diffMap.map((diff, stats) =>
                      MapEntry(diff.toString(), stats.toJson()))
                }))
      };
      await prefs.setString(_storageKey, jsonEncode(json));
      _log('✅ Cognitive profile saved successfully');
    } catch (e) {
      _log('❌ Error saving profile: $e');
    }
  }

  Future<void> loadProfile() async {
    _log('Loading cognitive profile...');
    _unreadableProfile = null;
    String? original;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      original = jsonString;
      _skillData = {};
      _preservedProfile = {};
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        _preservedProfile = Map.from(json);
        for (final entry in json.entries) {
          final skill =
              SkillCategories.all.where((s) => s.id == entry.key).firstOrNull;
          // Unknown skills remain serialized without being credited to the
          // first known category. Malformed neighbours cannot erase good rows.
          if (skill == null) continue;
          if (entry.value is! Map) {
            _unreadableProfile = jsonString;
            continue;
          }
          for (final row in (entry.value as Map).entries) {
            final difficulty = int.tryParse('${row.key}');
            final value = row.value;
            if (difficulty == null ||
                value is! Map ||
                value['a'] is! int ||
                value['s'] is! int ||
                value['a'] < 0 ||
                value['s'] < 0 ||
                value['s'] > value['a']) {
              _unreadableProfile = jsonString;
              continue;
            }
            (_skillData[skill] ??= {})[difficulty] = SkillStats(
                attempts: value['a'] as int, successes: value['s'] as int);
          }
        }
        _log('✅ Loaded ${_skillData.length} skill categories');
      } else {
        _log('No saved profile found. Starting fresh.');
      }
    } catch (e) {
      _log('❌ Error loading profile: $e');
      _skillData = {};
      _unreadableProfile = original;
    }
    notifyListeners();
  }

  Future<void> resetProgress() async {
    _skillData.clear();
    _preservedProfile.clear();
    _unreadableProfile = null;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((key) =>
        key == _storageKey || key.startsWith('${_storageKey}_recovery'))) {
      await prefs.remove(key);
    }
    notifyListeners();
  }
}
