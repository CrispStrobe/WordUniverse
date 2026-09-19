// lib/features/games/services/syllable_count_service.dart
//
// Syllable Count challenge construction, extracted from the screen so it can
// be generated and reviewed without running the game. See docs/content-audit.md.

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

class SyllableChallenge {
final GermanWord word;
final int syllableCount;
final int correctBucket; // 0→1, 1→2, 2→3, 3→4+
const SyllableChallenge({
  required this.word,
  required this.syllableCount,
  required this.correctBucket,
});
}

int? countSyllables(String rawHyph) {
  if (rawHyph.isEmpty) return null;

  // Some DB entries concatenate two hyphenation forms without a separator,
  // detectable by an uppercase letter that is not at the start and not after
  // a hyphen (e.g. "Bei-spielBei-spie-le"). Truncate to the first form.
  String truncated = rawHyph;
  for (int i = 1; i < rawHyph.length; i++) {
    final ch = rawHyph[i];
    if (ch == ch.toUpperCase() && ch != ch.toLowerCase() && rawHyph[i - 1] != '-') {
      truncated = rawHyph.substring(0, i);
      break;
    }
  }

  final segments = truncated.split('-');
  // Every segment must contain at least one vowel; otherwise the split is
  // character-level noise (e.g. "Fe-b-ru-ar" for Februar).
  const vowels = 'aeiouyäöüAEIOUYÄÖÜ';
  for (final seg in segments) {
    if (!seg.split('').any(vowels.contains)) return null;
  }
  return segments.length;
}

SyllableChallenge? buildSyllableChallenge(GermanWord word) {
  final hyphenations = word.hyphenation;
  // Try each hyphenation entry; use the first that parses cleanly.
  for (final raw in hyphenations) {
    final count = countSyllables(raw);
    if (count != null && count >= 1) {
      return SyllableChallenge(
        word: word,
        syllableCount: count,
        correctBucket: syllableBucket(count),
      );
    }
  }
  return null;
}

/// Which answer bucket a count falls in: 1→0, 2→1, 3→2, 4 or more→3.
int syllableBucket(int count) => count <= 3 ? count - 1 : 3;

/// Builds up to [maxChallenges] from [pool].
List<SyllableChallenge> buildSyllableChallenges({
  required List<GermanWord> pool,
  int maxChallenges = 10,
}) {
  final challenges = <SyllableChallenge>[];
  for (final word in pool) {
    if (challenges.length >= maxChallenges) break;
    if (namesSomething(word)) continue;
    final challenge = buildSyllableChallenge(word);
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}
