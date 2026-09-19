// lib/features/games/services/antonym_flash_service.dart
//
// Antonym Flash challenge construction, extracted from the screen so it can be
// generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

class AntonymChallenge {
  const AntonymChallenge({
    required this.word,
    required this.correctAntonym,
    required this.antonyms,
    required this.options,
    required this.correctIndex,
  });

  final GermanWord word;
  final String correctAntonym;

  /// Every listed antonym: any of them is accepted on tap.
  final List<String> antonyms;
  final List<String> options;
  final int correctIndex;
}

/// Builds up to [maxChallenges] from [pool].
List<AntonymChallenge> buildAntonymChallenges({
  required List<GermanWord> pool,
  required bool isGerman,
  int maxChallenges = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final challenges = <AntonymChallenge>[];
  for (final word in pool) {
    if (challenges.length >= maxChallenges) break;
    final challenge = buildAntonymChallenge(
      word: word,
      allWords: pool,
      isGerman: isGerman,
      optionCount: optionCount,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}

/// One challenge, or null when [word] has no antonym that makes a fair one.
AntonymChallenge? buildAntonymChallenge({
  required GermanWord word,
  required List<GermanWord> allWords,
  required bool isGerman,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  if (namesSomething(word)) return null;

  final antonyms = word.apiEnrichment?.antonyms
          .where((a) => a.trim().isNotEmpty)
          // Same rules as the synonym game: an "antonym" differing only in
          // case is not one, and in English a capitalised answer for a
          // lowercase prompt is a proper-noun sense.
          .where((a) => a.toLowerCase() != word.word.toLowerCase())
          .where((a) =>
              isGerman ||
              word.word != word.word.toLowerCase() ||
              a == a.toLowerCase())
          .toList() ??
      const [];
  if (antonyms.isEmpty) return null;

  // Variety: pick a random antonym among the clean ones as the displayed
  // correct answer (any listed antonym is still accepted on tap).
  final correct = antonyms[random.nextInt(antonyms.length)];

  final antonymsLower = antonyms.map((a) => a.toLowerCase()).toSet();
  bool isUsableDistractor(String t) =>
      t.isNotEmpty &&
      t != word.word &&
      t.toLowerCase() != correct.toLowerCase() &&
      !antonymsLower.contains(t.toLowerCase());

  // Distractor pool: prefer words sharing the prompt's part of speech so the
  // options are grammatically plausible. Fall back to the broader pool only
  // when the same-type pool is too small to fill the options.
  List<String> distractorPool(Iterable<GermanWord> source) => source
      .where((w) => !namesSomething(w))
      .map((w) => w.word)
      .where(isUsableDistractor)
      .toSet()
      .toList();

  var sourceTexts =
      distractorPool(allWords.where((w) => w.wordType == word.wordType));
  if (sourceTexts.length < optionCount - 1) {
    // Not enough same-type words; widen to the full pool (deduped).
    sourceTexts = {...sourceTexts, ...distractorPool(allWords)}.toList();
  }
  // Reshuffle the distractor source per challenge so the same filler words
  // don't recur every round.
  sourceTexts.shuffle(random);

  final distractors = sourceTexts.take(optionCount - 1).toList();
  if (distractors.isEmpty) return null;

  final options = [correct, ...distractors]..shuffle(random);
  final correctIndex = options.indexOf(correct);
  if (correctIndex < 0) return null;

  return AntonymChallenge(
    word: word,
    correctAntonym: correct,
    antonyms: antonyms,
    options: options,
    correctIndex: correctIndex,
  );
}
