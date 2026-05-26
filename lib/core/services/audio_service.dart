// lib/core/services/audio_service.dart
//
// Lightweight wrapper around audioplayers (sound effects) and flutter_tts
// (word pronunciation). Each sound effect gets its own AudioPlayer so rapid
// taps don't cut each other off. TTS is a singleton FlutterTts instance;
// concurrent speak() calls stop the previous utterance first.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AudioService {
  bool _soundEnabled = true;
  bool _musicEnabled = true;

  // TTS — initialized lazily on first speak() call.
  FlutterTts? _tts;
  String _ttsLang = 'de-DE'; // updated by setTtsLanguage()
  bool _ttsReady = false;

  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;

  void setSoundEnabled(bool enabled) => _soundEnabled = enabled;
  void setMusicEnabled(bool enabled) => _musicEnabled = enabled;

  /// Call once when the vocabulary language is known (e.g. 'de' or 'en').
  /// Maps the two-letter code to a BCP-47 locale suitable for FlutterTts.
  void setTtsLanguage(String lang) {
    _ttsLang = lang == 'en' ? 'en-US' : 'de-DE';
    // Re-apply to an existing instance if already initialised.
    _tts?.setLanguage(_ttsLang);
  }

  /// Play a short sound effect by name. Accepts either a bare key
  /// (e.g. 'success') or a filename (e.g. 'success.mp3') so legacy
  /// call sites keep working.
  Future<void> playSound(String name) async {
    if (!_soundEnabled) return;
    final filename = name.endsWith('.mp3') ? name : '$name.mp3';
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/$filename'));
      player.onPlayerComplete.first.then((_) => player.dispose());
    } catch (e) {
      if (kDebugMode) debugPrint('[AUDIO] playSound failed for $name: $e');
    }
  }

  void playBackgroundMusic() {
    if (!_musicEnabled) return;
    if (kDebugMode) debugPrint('[AUDIO] stub playBackgroundMusic');
  }

  void stopBackgroundMusic() {
    if (kDebugMode) debugPrint('[AUDIO] stub stopBackgroundMusic');
  }

  /// Speak [text] using the device TTS engine.
  /// No-ops when sound is disabled or on platforms where TTS is unavailable.
  /// Stops any in-progress utterance before starting the new one.
  Future<void> speak(String text, {String? lang}) async {
    if (!_soundEnabled || text.isEmpty) return;
    // Web TTS support is inconsistent across browsers; skip silently.
    if (kIsWeb) return;
    try {
      final tts = await _getTts();
      if (lang != null) await tts.setLanguage(lang);
      await tts.stop();
      await tts.speak(text);
      // Restore configured language if we overrode it.
      if (lang != null) await tts.setLanguage(_ttsLang);
    } catch (e) {
      if (kDebugMode) debugPrint('[AUDIO] TTS speak failed: $e');
    }
  }

  /// Stop any in-progress TTS utterance.
  Future<void> stopSpeaking() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  Future<FlutterTts> _getTts() async {
    if (_tts != null && _ttsReady) return _tts!;
    final tts = FlutterTts();
    await tts.setLanguage(_ttsLang);
    // Slightly slower than native for language-learning context.
    await tts.setSpeechRate(0.48);
    await tts.setVolume(1.0);
    await tts.setPitch(1.0);
    // Ensure audio plays even when the device is in silent/ring mode (iOS).
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await tts.setSharedInstance(true);
      await tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }
    _tts = tts;
    _ttsReady = true;
    return tts;
  }

  Future<void> dispose() async {
    await _tts?.stop();
  }
}
