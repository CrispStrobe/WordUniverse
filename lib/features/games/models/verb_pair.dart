// lib/features/games/models/verb_pair.dart
//
// One falling tile in Trennbare Verben: a verb shown either split into its
// separable parts or joined, for the learner to judge.

class VerbPair {
  final String part1; // e.g., "stehe" or empty for infinitives
  final String part2; // e.g., "auf" or "aufstehen"
  final bool shouldBeSeparated; // true = GETRENNT, false = ZUSAMMEN
  final String context; // Example sentence
  final String explanation; // Rule explanation
  final int difficulty; // 1-3
  final String wordId; // For SRI tracking
  final String formText; // Original form from Wiktionary

  VerbPair({
    required this.part1,
    required this.part2,
    required this.shouldBeSeparated,
    required this.context,
    required this.explanation,
    required this.difficulty,
    required this.wordId,
    required this.formText,
  });
}
