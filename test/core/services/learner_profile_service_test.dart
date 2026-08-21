import 'package:WortUniversum/core/services/learner_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists the learner setup and preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final profile = LearnerProfileService(prefs);

    await profile.completeOnboarding(
      goal: LearnerGoal.dafDaz,
      sessionMinutes: 15,
    );
    await profile.setFocusMode(true);
    await profile.toggleFavorite('cloze_flash');
    await profile.recordRecentGame('cloze_flash');

    final restored = LearnerProfileService(prefs);
    expect(restored.onboardingComplete, isTrue);
    expect(restored.goal, LearnerGoal.dafDaz);
    expect(restored.sessionMinutes, 15);
    expect(restored.focusMode, isTrue);
    expect(restored.favoriteGameIds, contains('cloze_flash'));
    expect(restored.recentGameIds.first, 'cloze_flash');
  });

  test('counts a completed daily session only once', () async {
    final prefs = await SharedPreferences.getInstance();
    final profile = LearnerProfileService(prefs);

    await profile.completeDailyStep(0);
    await profile.completeDailyStep(1);
    await profile.completeDailyStep(2);
    await profile.completeDailyStep(2);

    expect(profile.dailyCompletedSteps, {0, 1, 2});
    expect(profile.sessionsCompleted, 1);
  });

  test('keeps only the eight most recent unique games', () async {
    final prefs = await SharedPreferences.getInstance();
    final profile = LearnerProfileService(prefs);

    for (var i = 0; i < 10; i++) {
      await profile.recordRecentGame('game_$i');
    }
    await profile.recordRecentGame('game_5');

    expect(profile.recentGameIds, hasLength(8));
    expect(profile.recentGameIds.first, 'game_5');
    expect(profile.recentGameIds.toSet(), hasLength(8));
  });
}
