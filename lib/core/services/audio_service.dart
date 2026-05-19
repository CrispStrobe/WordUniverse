// lib/core/services/audio_service.dart
//
// Lightweight wrapper around the audioplayers package. Sounds live in
// assets/sounds/ and are referenced by short keys (e.g. 'success',
// 'failure'). Each playback gets its own AudioPlayer so concurrent
// effects don't cut each other off.
//
// Background music + TTS are still stubbed — wire them up when the
// games actually need them.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  bool _soundEnabled = true;
  bool _musicEnabled = true;

  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;

  void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
  }

  void setMusicEnabled(bool enabled) {
    _musicEnabled = enabled;
  }

  /// Play a short sound effect by name. Accepts either a bare key
  /// (e.g. 'success') or a filename (e.g. 'success.mp3') so legacy
  /// call sites keep working.
  Future<void> playSound(String name) async {
    if (!_soundEnabled) return;
    final filename = name.endsWith('.mp3') ? name : '$name.mp3';
    try {
      // Each effect gets its own player so a rapid success+tap
      // doesn't truncate the previous sound.
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/$filename'));
      // Dispose after playback completes to free the platform resource.
      player.onPlayerComplete.first.then((_) => player.dispose());
    } catch (e) {
      if (kDebugMode) debugPrint('[AUDIO] playSound failed for $name: $e');
    }
  }

  void playBackgroundMusic() {
    if (!_musicEnabled) return;
    // TODO: wire up looping background music when an actual track exists.
    if (kDebugMode) debugPrint('[AUDIO] stub playBackgroundMusic');
  }

  void stopBackgroundMusic() {
    if (kDebugMode) debugPrint('[AUDIO] stub stopBackgroundMusic');
  }

  void speak(String text) {
    if (!_soundEnabled) return;
    // TODO: flutter_tts integration when speech is wanted.
    if (kDebugMode) debugPrint('[AUDIO] stub speak: $text');
  }
}
