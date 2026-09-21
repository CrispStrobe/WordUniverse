// lib/features/games/services/wortbaumeister_service.dart
//
// Compound-word challenge construction, extracted from the screen so it can be
// generated and reviewed without running the game. See docs/content-audit.md.

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

enum GameMode { trennbareVerben, nomenKomposita }

bool _isValidNoun(String key, Map<String, GermanWord> map) {
  final w = map[key];
  return w != null && w.wordType == GermanWordType.substantiv;
}

/// Shortest noun worth splitting into a compound.
const int minCompoundLength = 8;

class WordChallenge {
  final String part1;
  final String part2;
  final bool shouldBeTogether;
  final String context;
  final String explanation;
  final int difficulty;
  final String wordId; // Base Lemma
  final GameMode mode;
  final String fullWord; // Specific Form

  WordChallenge({
    required this.part1,
    required this.part2,
    required this.shouldBeTogether,
    required this.context,
    required this.explanation,
    required this.difficulty,
    required this.wordId,
    required this.mode,
    required this.fullWord,
  });
}

class CompoundSplit {
  final String part1;
  final String part2;
  final int difficulty;

  CompoundSplit({
    required this.part1,
    required this.part2,
    required this.difficulty,
  });
}

List<WordChallenge> buildCompoundChallenges(
    List<GermanWord> nouns, Map<String, GermanWord> nounMap) {
  final challenges = <WordChallenge>[];

  for (final noun in nouns) {
    if (challenges.length > 20) break;
    if (noun.word.length < minCompoundLength) continue;

    final split = findValidCompoundSplit(noun.word, nounMap);

    if (split != null) {
      String context = 'Das Wort "${noun.word}" wird so geschrieben.';
      if (noun.examples.isNotEmpty) {
        final ex = noun.examples.firstWhere(
            (e) =>
                e.text != null &&
                e.text!.length < 100 &&
                sentenceSuitsAChild(e.text!),
            // --- FIX 3: Use ApiExample class, not Example ---
            orElse: () => ApiExample(text: null));
        if (ex.text != null) context = ex.text!;
      }

      challenges.add(WordChallenge(
        part1: split.part1,
        part2: split.part2,
        shouldBeTogether: true,
        context: context,
        explanation: 'Nomen-Komposita schreibt man immer zusammen.',
        difficulty: 1,
        wordId: noun.word,
        mode: GameMode.nomenKomposita,
        fullWord: noun.word,
      ));
    }
  }
  return challenges;
}

CompoundSplit? findValidCompoundSplit(
    String word, Map<String, GermanWord> nounMap) {
  // Collect every split where both halves are real DB nouns (≥4 chars each),
  // then pick the most BALANCED one (largest min-part-length). Returning the
  // first match favoured a tiny coincidental modifier and produced wrong
  // decompositions; balanced splits track real compound boundaries better.
  CompoundSplit? best;
  int bestScore = -1;
  for (int i = 4; i < word.length - 3; i++) {
    final String p1 = word.substring(0, i);
    final String p2 = word.substring(i);
    final String p1Lower = p1.toLowerCase();
    final String p2Lower = p2.toLowerCase();

    bool valid =
        _isValidNoun(p1Lower, nounMap) && _isValidNoun(p2Lower, nounMap);
    // Allow a single Fugen-s on the modifier (Geburts+tag).
    if (!valid && p1Lower.endsWith('s')) {
      valid = _isValidNoun(p1Lower.substring(0, p1Lower.length - 1), nounMap) &&
          _isValidNoun(p2Lower, nounMap);
    }
    if (valid) {
      final score = p1.length < p2.length ? p1.length : p2.length;
      if (score > bestScore) {
        bestScore = score;
        best = CompoundSplit(part1: p1, part2: p2, difficulty: 1);
      }
    }
  }
  return best;
}
