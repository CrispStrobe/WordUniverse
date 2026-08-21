import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameProvider _provider(SharedPreferences prefs) => GameProvider(
      progressService: ProgressService(),
      sriService: SriService(),
      cognitiveProfileService: CognitiveProfileService(),
      prefs: prefs,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('puzzle timer preference survives provider reconstruction', () async {
    SharedPreferences.setMockInitialValues({
      'puzzle_timer_enabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final provider = _provider(prefs);

    expect(provider.puzzleTimerEnabled, isFalse);

    provider.setPuzzleTimer(true);
    await provider.saveProgress();

    expect(_provider(prefs).puzzleTimerEnabled, isTrue);
  });

  test('provider-owned customization settings round-trip together', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final provider = _provider(prefs);

    provider.setUseAdaptiveDifficulty(true);
    provider.setUseCustomSettings(true);
    provider.setCustomOperations({'addition'});
    provider.setCustomRange(min: 4, max: 12);
    await provider.saveProgress();

    final restored = _provider(prefs);
    expect(restored.useAdaptiveDifficulty, isTrue);
    expect(restored.useCustomProblemSettings, isTrue);
    expect(restored.customOperations, {'addition'});
    expect(restored.customRangeMin, 4);
    expect(restored.customRangeMax, 12);
  });
}
