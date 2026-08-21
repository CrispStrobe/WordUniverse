import 'dart:convert';

import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy band records do not inflate current achievement totals',
      () async {
    SharedPreferences.setMockInitialValues({
      'achievements': [
        jsonEncode({'id': 'first_century', 'unlockedAt': null}),
        jsonEncode({'id': 'grade_4', 'unlockedAt': null}),
        jsonEncode({'id': 'grade_6', 'unlockedAt': null}),
      ],
    });
    final prefs = await SharedPreferences.getInstance();

    final provider = GameProvider(
      progressService: ProgressService(),
      sriService: SriService(),
      cognitiveProfileService: CognitiveProfileService(),
      prefs: prefs,
    );

    expect(provider.achievements, hasLength(3));
    expect(provider.totalAchievements, 1);
  });
}
