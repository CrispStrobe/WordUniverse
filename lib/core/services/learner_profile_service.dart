import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LearnerGoal { balanced, vocabulary, spelling, grammar, dafDaz }

class LearnerProfileService extends ChangeNotifier {
  LearnerProfileService(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static const _onboardingKey = 'learner_onboarding_complete';
  static const _goalKey = 'learner_goal';
  static const _minutesKey = 'learner_session_minutes';
  static const _focusModeKey = 'learner_focus_mode';
  static const _favoritesKey = 'learner_favorite_games';
  static const _recentsKey = 'learner_recent_games';
  static const _dailyDateKey = 'learner_daily_date';
  static const _dailyStepsKey = 'learner_daily_steps';
  static const _sessionsKey = 'learner_sessions_completed';

  bool _onboardingComplete = false;
  LearnerGoal _goal = LearnerGoal.balanced;
  int _sessionMinutes = 10;
  bool _focusMode = false;
  Set<String> _favoriteGameIds = {};
  List<String> _recentGameIds = [];
  Set<int> _dailyCompletedSteps = {};
  int _sessionsCompleted = 0;

  bool get onboardingComplete => _onboardingComplete;
  LearnerGoal get goal => _goal;
  int get sessionMinutes => _sessionMinutes;
  bool get focusMode => _focusMode;
  Set<String> get favoriteGameIds => Set.unmodifiable(_favoriteGameIds);
  List<String> get recentGameIds => List.unmodifiable(_recentGameIds);
  Set<int> get dailyCompletedSteps {
    _resetDailyIfNeeded();
    return Set.unmodifiable(_dailyCompletedSteps);
  }

  int get sessionsCompleted => _sessionsCompleted;

  void _load() {
    _onboardingComplete = _prefs.getBool(_onboardingKey) ?? false;
    final goalIndex = _prefs.getInt(_goalKey) ?? LearnerGoal.balanced.index;
    _goal =
        LearnerGoal.values[goalIndex.clamp(0, LearnerGoal.values.length - 1)];
    _sessionMinutes = _prefs.getInt(_minutesKey) ?? 10;
    _focusMode = _prefs.getBool(_focusModeKey) ?? false;
    _favoriteGameIds = (_prefs.getStringList(_favoritesKey) ?? []).toSet();
    _recentGameIds = _prefs.getStringList(_recentsKey) ?? [];
    _sessionsCompleted = _prefs.getInt(_sessionsKey) ?? 0;
    _resetDailyIfNeeded();
  }

  Future<void> completeOnboarding({
    required LearnerGoal goal,
    required int sessionMinutes,
  }) async {
    _goal = goal;
    _sessionMinutes = sessionMinutes;
    _onboardingComplete = true;
    await _prefs.setInt(_goalKey, goal.index);
    await _prefs.setInt(_minutesKey, sessionMinutes);
    await _prefs.setBool(_onboardingKey, true);
    notifyListeners();
  }

  Future<void> setGoal(LearnerGoal value) async {
    _goal = value;
    await _prefs.setInt(_goalKey, value.index);
    notifyListeners();
  }

  Future<void> setSessionMinutes(int value) async {
    _sessionMinutes = value.clamp(5, 20);
    await _prefs.setInt(_minutesKey, _sessionMinutes);
    notifyListeners();
  }

  Future<void> setFocusMode(bool value) async {
    _focusMode = value;
    await _prefs.setBool(_focusModeKey, value);
    notifyListeners();
  }

  Future<void> toggleFavorite(String gameId) async {
    if (!_favoriteGameIds.add(gameId)) _favoriteGameIds.remove(gameId);
    await _prefs.setStringList(
        _favoritesKey, _favoriteGameIds.toList()..sort());
    notifyListeners();
  }

  Future<void> recordRecentGame(String gameId) async {
    _recentGameIds.remove(gameId);
    _recentGameIds.insert(0, gameId);
    if (_recentGameIds.length > 8)
      _recentGameIds.removeRange(8, _recentGameIds.length);
    await _prefs.setStringList(_recentsKey, _recentGameIds);
    notifyListeners();
  }

  Future<void> completeDailyStep(int step) async {
    _resetDailyIfNeeded();
    final wasComplete = _dailyCompletedSteps.length >= 3;
    _dailyCompletedSteps.add(step);
    await _prefs.setStringList(
        _dailyStepsKey, _dailyCompletedSteps.map((e) => '$e').toList());
    if (!wasComplete && _dailyCompletedSteps.length >= 3) {
      _sessionsCompleted++;
      await _prefs.setInt(_sessionsKey, _sessionsCompleted);
    }
    notifyListeners();
  }

  Future<void> resetDailySession() async {
    _dailyCompletedSteps.clear();
    await _prefs.setString(_dailyDateKey, _todayKey());
    await _prefs.setStringList(_dailyStepsKey, const []);
    notifyListeners();
  }

  void _resetDailyIfNeeded() {
    final today = _todayKey();
    if (_prefs.getString(_dailyDateKey) == today) {
      _dailyCompletedSteps = (_prefs.getStringList(_dailyStepsKey) ?? [])
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
      return;
    }
    _dailyCompletedSteps.clear();
    _prefs.setString(_dailyDateKey, today);
    _prefs.setStringList(_dailyStepsKey, const []);
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
