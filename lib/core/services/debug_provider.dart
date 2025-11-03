// lib/core/services/debug_provider.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DebugProvider with ChangeNotifier {
  static const _forceUnlockKey = 'debug_force_unlock';
  bool _isDebugMenuEnabled = false;
  bool _isPaidUnlockedForced = false;

  bool get isDebugMenuEnabled => _isDebugMenuEnabled;
  bool get isPaidUnlockedForced => _isPaidUnlockedForced;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isPaidUnlockedForced = prefs.getBool(_forceUnlockKey) ?? false;
    notifyListeners();
  }

  void enableDebugMenu() {
    _isDebugMenuEnabled = true;
    notifyListeners();
  }

  void setPaidUnlock(bool isUnlocked) {
    _isPaidUnlockedForced = isUnlocked;
    _savePreference(); // Call the save method
    notifyListeners();
  }

  Future<void> _savePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_forceUnlockKey, _isPaidUnlockedForced);
  }

}