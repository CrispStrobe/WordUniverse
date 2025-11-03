// lib/core/services/audio_service.dart

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
    if (_soundEnabled) {
      // TODO: Implement sound playing using audioplayers package
      // AudioPlayer().play(AssetSource('sounds/$soundFile'));
      print('Playing sound: $soundFile');
    }
  }
  
  void playBackgroundMusic() {
    if (_musicEnabled) {
      // TODO: Implement background music
      print('Playing background music');
    }
  }
  
  void stopBackgroundMusic() {
    // TODO: Implement stop background music
    print('Stopping background music');
  }

  // --- FIX: Added missing speak method ---
  void speak(String text) {
    if (_soundEnabled) {
      // TODO: Implement TTS using a package like flutter_tts
      print('Speaking: $text');
    }
  }
}