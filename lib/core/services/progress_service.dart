// lib/core/services/progress_service.dart
import 'package:flutter/foundation.dart';
import '../../../features/games/providers/game_provider.dart';

class ProgressService {
  // Verbose logging for saving/loading progress
  void _log(String message) {
    if (kDebugMode) debugPrint('[PROGRESS_SERVICE] 💾 $message');
  }

  Future<void> saveProgress(GameProvider gameProvider) async {
    _log('Saving game progress...');
    // GameProvider now persists itself to SharedPreferences.
    // Kept as a hook for future cloud-backup logic.
    _log('✅ Game progress saved.');
  }

  Future<void> loadProgress(GameProvider gameProvider) async {
    _log('Loading game progress...');
    // GameProvider loads its own state from SharedPreferences in its
    // constructor / _loadSettingsFromPrefs(), so nothing to do here.
    _log('✅ Game progress already loaded by GameProvider.');
  }
}
