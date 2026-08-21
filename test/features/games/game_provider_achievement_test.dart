import 'dart:convert';

import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/models/game_outcome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy band records do not inflate current achievement totals',
      () async {
    SharedPreferences.setMockInitialValues({
      'achievements': [
        jsonEncode({'id': 'first_century', 'unlockedAt': null}),
        jsonEncode({'id': 'first_century', 'unlockedAt': null}),
        jsonEncode({'id': 'grade_4', 'unlockedAt': null}),
        jsonEncode({'id': 'grade_6', 'unlockedAt': null}),
        jsonEncode({'id': 'level_explorer', 'unlockedAt': null}),
        jsonEncode({'id': 'space_commander', 'unlockedAt': null}),
      ],
    });
    final prefs = await SharedPreferences.getInstance();

    final provider = GameProvider(
      progressService: ProgressService(),
      sriService: SriService(),
      cognitiveProfileService: CognitiveProfileService(),
      prefs: prefs,
    );

    expect(provider.achievements, hasLength(6));
    expect(provider.totalAchievements, 1);
    expect(
      provider.achievements
          .every((item) => item.toJson()['unlockedAt'] != null),
      isTrue,
    );
  });

  test('new achievements always receive an unlock timestamp', () {
    final before = DateTime.now();
    final achievement = Achievement(id: 'first_century');

    expect(achievement.unlockedAt.isBefore(before), isFalse);
    expect(achievement.toJson()['unlockedAt'], isNotNull);
  });

  test('a successful outcome awards its score exactly once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final provider = GameProvider(
      progressService: ProgressService(),
      sriService: SriService(),
      cognitiveProfileService: CognitiveProfileService(),
      prefs: prefs,
    );

    provider.reportOutcome(GameOutcome.win(
      gameType: 'synonym_flash',
      difficulty: 1,
      score: 30,
    ));

    expect(provider.score, 30);
  });
}
