import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/learner_profile_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/streak_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unknown profile skills never become mastery of the first known skill',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final known = SkillCategories.all.last;
    await prefs.setString(
        'cognitive_profile',
        jsonEncode({
          known.id: {
            '2': {'a': 3, 's': 2},
            'broken': {'raw': 'keep this'}
          },
          'retired_skill': {
            '1': {'a': 100, 's': 100}
          }
        }));
    final profile = CognitiveProfileService();
    await profile.loadProfile();
    expect(profile.totalAttempts, 3);
    expect(profile.snapshot[known]![2]!.successes, 2);
    expect(profile.snapshot.containsKey(SkillCategories.all.first), isFalse);
    await profile.saveProfile();
    final saved = jsonDecode(prefs.getString('cognitive_profile')!) as Map;
    expect(saved['retired_skill']['1']['a'], 100);
    expect(saved[known.id]['broken']['raw'], 'keep this');
    final restored = CognitiveProfileService();
    await restored.loadProfile();
    expect(restored.totalAttempts, 3);
  });

  test('unreadable profile is retained before a new attempt is saved',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cognitive_profile', '{unreadable');
    final profile = CognitiveProfileService();
    await profile.loadProfile();
    profile.recordAttempt(SkillCategories.all.first, 1, true);
    await profile.saveProfile();
    expect(prefs.getString('cognitive_profile_recovery'), '{unreadable');
    final restored = CognitiveProfileService();
    await restored.loadProfile();
    expect(restored.totalAttempts, 1);
    await profile.resetProgress();
    expect(prefs.getKeys().where((k) => k.startsWith('cognitive_profile')),
        isEmpty);
  });

  test('a valid reload clears a previously unreadable recovery snapshot',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cognitive_profile', '{unreadable');
    final profile = CognitiveProfileService();
    await profile.loadProfile();

    final known = SkillCategories.all.last;
    await prefs.setString(
        'cognitive_profile',
        jsonEncode({
          known.id: {
            '2': {'a': 4, 's': 3}
          }
        }));
    await profile.loadProfile();
    await profile.saveProfile();

    expect(profile.totalAttempts, 4);
    expect(profile.snapshot[known]![2]!.successes, 3);
    expect(
        prefs
            .getKeys()
            .where((k) => k.startsWith('cognitive_profile_recovery')),
        isEmpty);
  });

  test(
      'reset removes completed-session and streak totals from memory and storage',
      () async {
    SharedPreferences.setMockInitialValues({
      'sessionsPlayed': 12,
      'gameProgress': jsonEncode({'word_builder_game': 3}),
      'currentLevelWins': jsonEncode({'word_builder_game': 2}),
      'learner_sessions_completed': 7,
      'learner_recent_games': ['sri_review'],
      'learner_onboarding_complete': true,
      'learner_goal': LearnerGoal.kompassBw.index,
      'language': 'de',
      'streak_current': 3,
      'streak_longest': 9,
      'streak_lastDay': DateTime.now().toIso8601String()
    });
    final prefs = await SharedPreferences.getInstance();
    final profile = LearnerProfileService(prefs);
    final streak = StreakService();
    await streak.load();
    final game = GameProvider(
        progressService: ProgressService(),
        sriService: SriService(),
        cognitiveProfileService: CognitiveProfileService(),
        prefs: prefs);
    expect(game.totalGamesPlayed, 12);
    expect(game.getGameProgress('word_builder_game'), 3);
    expect(profile.sessionsCompleted, 7);
    // Await the same reset operation used by Settings; an extra save here
    // would hide a reset that returns before its persistence has finished.
    await game.resetGame();
    await profile.resetProgress();
    await streak.resetProgress();
    expect(game.totalGamesPlayed, 0);
    expect(game.getGameProgress('word_builder_game'), 0);
    expect(prefs.getInt('sessionsPlayed'), 0);
    expect(jsonDecode(prefs.getString('gameProgress')!), isEmpty);
    expect(jsonDecode(prefs.getString('currentLevelWins')!), isEmpty);
    final restored = LearnerProfileService(prefs);
    final restoredStreak = StreakService();
    await restoredStreak.load();
    expect(restored.sessionsCompleted, 0);
    expect(restored.recentGameIds, isEmpty);
    expect(restored.dailyCompletedSteps, isEmpty);
    expect(restoredStreak.currentStreak, 0);
    expect(restoredStreak.longestStreak, 0);
    expect(restored.goal, LearnerGoal.kompassBw);
    expect(restored.onboardingComplete, isTrue);
    expect(prefs.getString('language'), 'de');
  });
}
