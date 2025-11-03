// lib/core/services/progress_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../features/games/providers/game_provider.dart';

class ProgressService {
  static const _progressKey = 'game_progress_data';

  // Verbose logging for saving/loading progress
  void _log(String message) {
    debugPrint('[PROGRESS_SERVICE] 💾 $message');
  }

  Future<void> saveProgress(GameProvider gameProvider) async {
    _log('Saving game progress...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = gameProvider.toJson();
      final jsonString = json.encode(data);
      await prefs.setString(_progressKey, jsonString);
      _log('✅ Game progress saved successfully.');
      _log('Data: $jsonString');
    } catch (e) {
      _log('❌ Error saving progress: $e');
    }
  }

  Future<void> loadProgress(GameProvider gameProvider) async {
    _log('Loading game progress...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_progressKey);
      if (jsonString != null) {
        final Map<String, dynamic> data = json.decode(jsonString);
        gameProvider.fromJson(data);
        _log('✅ Game progress loaded successfully.');
        _log('Data: $jsonString');
      } else {
        _log('No saved progress found.');
      }
    } catch (e) {
      _log('❌ Error loading progress: $e. Starting with default state.');
    }
  }
}