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
      
      // --- FIX: REMOVED THIS LINE ---
      // final data = gameProvider.toJson(); 
      // The GameProvider now saves itself to prefs.
      // This service might be used for cloud backup, so we'll
      // keep the save call, but it no longer needs to serialize.
      
      // Example of other save logic (if any):
      // await prefs.setString('some_other_progress', 'value');
      
      _log('✅ Game progress saved.');
    } catch (e) {
      _log('❌ Error saving game progress: $e');
    }
  }

  Future<void> loadProgress(GameProvider gameProvider) async {
    _log('Loading game progress...');
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // --- FIX: REMOVED THIS LOGIC ---
      // final jsonString = prefs.getString(_progressKey);
      // if (jsonString != null) {
      //   final data = json.decode(jsonString);
      //   gameProvider.fromJson(data);
      //   _log('✅ Game progress loaded successfully.');
      //   _log('💾 Data: $jsonString');
      // } else {
      //   _log('No saved progress found.');
      // }
      // --- END FIX ---
      
      // This logic is now handled in the GameProvider's
      // constructor and _loadSettingsFromPrefs() method.
      // This function is called from main.dart *after* the
      // provider is created, so the settings are already loaded.
      _log('✅ Game progress already loaded by GameProvider.');
      
    } catch (e) {
      _log('❌ Error loading game progress: $e');
    }
  }
}