// lib/features/games/services/spelling_spotter_challenges.dart
//
// Spelling Spotter challenge construction, extracted from the screen so it can
// be generated and reviewed without running the game. The scoring helpers it
// uses live in spelling_spotter_service.dart. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';
import 'spelling_spotter_service.dart';

class SpellingChallenge {
  final GermanWord word;
  final List<String> options; // 4 items, shuffled
  final int correctIndex;
  final String? contextSentence;

  const SpellingChallenge({
    required this.word,
    required this.options,
    required this.correctIndex,
    this.contextSentence,
  });
}

bool hasSpellingErrors(GermanWord w, {required bool isGerman}) {
  if (w.isProperNoun) return false;
  final display = normWord(w.word);
  if (display.contains(' ') || display.isEmpty) return false;
  if (isGerman) {
    return w.commonMistakes?.isNotEmpty ?? false;
  }
  return w.apiEnrichment?.commonLearnerErrors.isNotEmpty ?? false;
}

SpellingChallenge? buildSpellingChallenge({
  required GermanWord word,
  required List<String> allErrors,
  required Set<String> validWords,
  required bool isGerman,
  required int gradeLevel,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final displayWord = normWord(word.word);

  final rawErrors = isGerman
      ? (word.commonMistakes ?? <String>[])
      : (word.apiEnrichment?.commonLearnerErrors ?? <String>[]);

  final errors = parseErrors(rawErrors)
      .map(normWord)
      .where((e) =>
          e.toLowerCase() != displayWord.toLowerCase() &&
          e.isNotEmpty &&
          !e.contains(' ') &&
          // Skip error forms that are themselves valid vocabulary words
          // (e.g. "in" is a commonMistake of "ihn" but is a real word too).
          !validWords.contains(e.toLowerCase()))
      .toList();

  final distractors = <String>{};
  for (final e in errors) {
    distractors.add(e);
    if (distractors.length >= optionCount - 1) break;
  }

  // Pad with errors from other words if needed.
  if (distractors.length < optionCount - 1) {
    final others = allErrors
        .map(normWord)
        .where((e) =>
            !distractors.contains(e) &&
            e.length >= 2 &&
            isDistractorPlausible(e, displayWord, validWords: validWords))
        .toList()
      ..shuffle(random);
    for (final e in others) {
      distractors.add(e);
      if (distractors.length >= optionCount - 1) break;
    }
  }

  // Two options that both look like the word beat four where three do not.
  if (distractors.isEmpty) return null;

  final options = [displayWord, ...distractors.take(optionCount - 1)];
  options.shuffle(random);
  final correctIndex = options.indexOf(displayWord);
  if (correctIndex < 0) return null;

  // Example sentence: for DE prefer Tatoeba (human-verified) > Gutenberg >
  // gradeExamples (LLM). Validate that the sentence contains the word.
  String? context;
  if (isGerman) {
    context = word.exampleSentences
        .where((s) => _sentenceContains(s, displayWord))
        .where(sentenceSuitsAChild)
        .firstOrNull;
  }
  context ??= word.apiEnrichment?.gutenbergExamples
      .where((s) => _sentenceContains(s, displayWord))
      .where(sentenceSuitsAChild)
      .firstOrNull;
  if (context == null) {
    final gradeKey = '\$gradeLevel';
    final ge = word.apiEnrichment?.gradeExamples;
    if (ge != null) {
      final sents = ge[gradeKey] ?? ge.values.firstOrNull ?? [];
      context =
          sents.where((s) => _sentenceContains(s, displayWord)).firstOrNull;
    }
  }

  return SpellingChallenge(
    word: word,
    options: options,
    correctIndex: correctIndex,
    contextSentence: context,
  );
}

bool _sentenceContains(String sentence, String word) =>
    sentence.toLowerCase().contains(word.toLowerCase());

/// The words to ask about, hardest first but drawn from a wider tier so that
/// replays differ. Expects a pool already filtered to words with errors.
List<GermanWord> selectSpellingWords({
  required List<GermanWord> pool,
  required bool isGerman,
  int rounds = 10,
  Random? rng,
}) {
  final random = rng ?? Random();
  final sorted = pool.toList()
    ..sort((a, b) => spellingDifficultyScore(b, isDE: isGerman)
        .compareTo(spellingDifficultyScore(a, isDE: isGerman)));
  final tier = sorted.take(min(sorted.length, rounds * 3)).toList()
    ..shuffle(random);
  return tier.take(rounds).toList();
}

/// Builds up to [rounds] challenges from [pool].
List<SpellingChallenge> buildSpellingChallenges({
  required List<GermanWord> pool,
  required bool isGerman,
  required int gradeLevel,
  int rounds = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final allErrors = parseErrors(pool
          .expand((w) => isGerman
              ? (w.commonMistakes ?? const <String>[])
              : (w.apiEnrichment?.commonLearnerErrors ?? const <String>[]))
          .toList())
      .toSet()
      .toList();
  // Error forms that are themselves real words must never be offered as the
  // wrong spelling: "in" is a recorded mistake for "ihn" and also a word.
  final validWords = pool.map((w) => normWord(w.word).toLowerCase()).toSet();

  final challenges = <SpellingChallenge>[];
  for (final word in selectSpellingWords(
      pool: pool, isGerman: isGerman, rounds: rounds, rng: random)) {
    final challenge = buildSpellingChallenge(
      word: word,
      allErrors: allErrors,
      validWords: validWords,
      isGerman: isGerman,
      gradeLevel: gradeLevel,
      optionCount: optionCount,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}
