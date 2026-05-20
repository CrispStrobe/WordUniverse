// lib/core/services/streak_service.dart
//
// Tracks consecutive-day play streaks. Call [markPlayed] once per app
// open (or per game launch) — the service figures out whether to
// increment, hold, or reset.
//
// Storage layout in SharedPreferences:
//   streak_current : int           current run length, in days
//   streak_longest : int           best ever
//   streak_lastDay : 'yyyy-MM-dd'  last calendar date the player played
//
// Calendar-day arithmetic uses local-time midnight boundaries, which
// matches what kids actually experience.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StreakService extends ChangeNotifier {
  static const _kCurrentKey = 'streak_current';
  static const _kLongestKey = 'streak_longest';
  static const _kLastDayKey = 'streak_lastDay';

  int _current = 0;
  int _longest = 0;
  DateTime? _lastPlayedDay;
  bool _loaded = false;

  int get currentStreak => _current;
  int get longestStreak => _longest;
  DateTime? get lastPlayedDay => _lastPlayedDay;
  bool get isLoaded => _loaded;

  /// True if [markPlayed] was already called today (so calling it again
  /// would be a no-op).
  bool get playedToday {
    final last = _lastPlayedDay;
    if (last == null) return false;
    return _sameDay(last, DateTime.now());
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _current = prefs.getInt(_kCurrentKey) ?? 0;
    _longest = prefs.getInt(_kLongestKey) ?? 0;
    final raw = prefs.getString(_kLastDayKey);
    _lastPlayedDay = raw == null ? null : DateTime.tryParse(raw);

    // Heal an out-of-date streak on load: if the last-played day is older
    // than yesterday, the streak is broken even though no game was opened
    // to trigger markPlayed.
    final last = _lastPlayedDay;
    if (last != null && _current > 0) {
      final today = _dateOnly(DateTime.now());
      final diff = today.difference(_dateOnly(last)).inDays;
      if (diff >= 2) {
        _current = 0;
        await prefs.setInt(_kCurrentKey, 0);
      }
    }

    _loaded = true;
    notifyListeners();
  }

  /// Records that the user played today. Idempotent for repeated calls
  /// on the same calendar day.
  Future<void> markPlayed() async {
    if (!_loaded) await load();

    final now = DateTime.now();
    final today = _dateOnly(now);
    final last = _lastPlayedDay == null ? null : _dateOnly(_lastPlayedDay!);

    if (last != null && _sameDay(last, today)) {
      return; // already counted today
    }

    final yesterday = today.subtract(const Duration(days: 1));
    if (last != null && _sameDay(last, yesterday)) {
      _current += 1; // streak continues
    } else {
      _current = 1; // streak restart
    }

    if (_current > _longest) _longest = _current;
    _lastPlayedDay = today;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCurrentKey, _current);
    await prefs.setInt(_kLongestKey, _longest);
    await prefs.setString(_kLastDayKey, today.toIso8601String());
    notifyListeners();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
