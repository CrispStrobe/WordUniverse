// lib/core/services/audio_service.dart
//
// Intentional stub: no audio assets ship with the app today (assets/sounds/
// is empty). Methods are no-ops in release and log via debugPrint in debug
// so the noise does not survive a release build. To wire real audio,
// replace the bodies below with audioplayers / flutter_tts calls — the
// audioplayers package is already declared in pubspec.yaml.

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

  void playSound(String soundFile) {
    if (!_soundEnabled) return;
    // TODO: AudioPlayer().play(AssetSource('sounds/$soundFile')); when assets exist.
    if (kDebugMode) debugPrint('[AUDIO] stub playSound: $soundFile');
  }

  void playBackgroundMusic() {
    if (!_musicEnabled) return;
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
