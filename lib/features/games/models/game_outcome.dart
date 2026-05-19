// lib/features/games/models/game_outcome.dart
//
// Canonical end-of-level reporting payload. Replaces the named-parameter
// soup of the legacy GameProvider.recordLevelWin(...) signature with a
// single value type, and centralizes the "what counts as success" decision
// in named factories so callers don't reinvent thresholds.
//
// Use `GameOutcome.win` / `.loss` / `.fromRatio` instead of constructing
// the value directly, and report via `gameProvider.reportOutcome(...)`.

class GameOutcome {
  final String gameType;
  final int difficulty;
  final int score;
  final bool wasSuccessful;

  const GameOutcome({
    required this.gameType,
    required this.difficulty,
    required this.score,
    required this.wasSuccessful,
  });

  /// Binary completion: player succeeded. Awards [score] points.
  factory GameOutcome.win({
    required String gameType,
    required int difficulty,
    required int score,
  }) =>
      GameOutcome(
        gameType: gameType,
        difficulty: difficulty,
        score: score,
        wasSuccessful: true,
      );

  /// Binary completion: player failed. No score awarded.
  factory GameOutcome.loss({
    required String gameType,
    required int difficulty,
  }) =>
      GameOutcome(
        gameType: gameType,
        difficulty: difficulty,
        score: 0,
        wasSuccessful: false,
      );

  /// "Got [correct] of [total] right" with the canonical 70% pass mark.
  /// Use this for games where success is gradient, not binary.
  factory GameOutcome.fromRatio({
    required String gameType,
    required int difficulty,
    required int score,
    required int correct,
    required int total,
    double passThreshold = 0.7,
  }) =>
      GameOutcome(
        gameType: gameType,
        difficulty: difficulty,
        score: score,
        wasSuccessful: total > 0 && (correct / total) >= passThreshold,
      );
}
