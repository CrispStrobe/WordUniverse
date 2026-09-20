// lib/features/games/services/sentence_completion_service.dart
//
// Sentence Completion challenge construction, extracted from the screen so it
// can be generated and reviewed without running the game.
// See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

class SentenceChallenge {
  final GermanWord word;
  final String before; // sentence text before the blank
  final String after; // sentence text after the blank
  final String correctOption;
  final List<String> options;
  final int correctIndex;

  const SentenceChallenge({
    required this.word,
    required this.before,
    required this.after,
    required this.correctOption,
    required this.options,
    required this.correctIndex,
  });
}

bool hasGradeExamples(GermanWord w, int gradeIndex) {
  final ge = w.apiEnrichment?.gradeExamples;
  if (ge == null) return false;
  final key = '$gradeIndex';
  final sents = ge[key] ?? ge.values.firstOrNull;
  return sents != null && sents.isNotEmpty;
}

SentenceChallenge? buildSentenceChallenge({
  required GermanWord word,
  required int gradeIndex,
  required List<GermanWord> pool,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final ge = word.apiEnrichment?.gradeExamples;
  if (ge == null) return null;

  final key = '$gradeIndex';
  final sents = (ge[key] ?? ge.values.firstOrNull) ?? [];
  if (sents.isEmpty) return null;

  // Try each sentence until we find one containing the word
  final shuffledSents = List<String>.from(sents)..shuffle(random);
  for (final sent in shuffledSents) {
    final result = blankWord(sent, word.word);
    if (result == null) continue;
    final (before, after) = result;
    // A sentence that says the word again beside the gap answers itself.
    if (RegExp('\\b${RegExp.escape(word.word)}', caseSensitive: false)
        .hasMatch('$before $after')) {
      continue;
    }

    final correctOption = _sentenceOption(word);
    final distractors = _pickDistractors(
        word, correctOption, pool, gradeIndex, optionCount, random);
    if (distractors.isEmpty) continue;

    final options = [correctOption, ...distractors.take(optionCount - 1)];
    options.shuffle(random);
    final correctIndex = options.indexOf(correctOption);
    if (correctIndex < 0) continue;

    return SentenceChallenge(
      word: word,
      before: before,
      after: after,
      correctOption: correctOption,
      options: options,
      correctIndex: correctIndex,
    );
  }
  return null;
}

(String, String)? blankWord(String sentence, String word) {
  // Try exact whole-word match first (case insensitive)
  final exact =
      RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false);
  var m = exact.firstMatch(sentence);

  // Fall back to starts-with match for inflected forms, but only accept a
  // short suffix (German inflection endings are ≤3 chars: -e/-en/-es/-er/-em
  // /-s/-st…). Prevents blanking an unrelated longer word, e.g. target
  // "Hund" wrongly matching "Hunderte".
  if (m == null) {
    final prefix =
        RegExp(r'\b' + RegExp.escape(word) + r'\w*', caseSensitive: false);
    final pm = prefix.firstMatch(sentence);
    if (pm != null && (pm.end - pm.start) <= word.length + 3) {
      m = pm;
    }
  }

  if (m == null) return null;
  return (sentence.substring(0, m.start), sentence.substring(m.end));
}

String _sentenceOption(GermanWord w) {
  // Do NOT prepend the article here: the cloze sentence already supplies the
  // article in its correct grammatical case ("Ich sehe den ___"), so adding
  // the nominative "der/die/das" would both clash with that case and double
  // the article. Show the bare noun.
  return w.word;
}

List<String> _pickDistractors(GermanWord target, String correctOption,
    List<GermanWord> pool, int gradeIndex, int optionCount, Random random) {
  final distractors = <String>{};

  // Same word type, same grade first
  final sameTypeSameGrade = pool
      .where((w) =>
          w.id != target.id &&
          w.wordType == target.wordType &&
          w.gradeLevel == gradeIndex)
      .toList()
    ..shuffle(random);

  for (final w in sameTypeSameGrade) {
    final opt = _sentenceOption(w);
    if (opt != correctOption) distractors.add(opt);
    if (distractors.length >= optionCount - 1) break;
  }

  // Same word type, any grade
  if (distractors.length < optionCount - 1) {
    final sameType = pool
        .where((w) => w.id != target.id && w.wordType == target.wordType)
        .toList()
      ..shuffle(random);
    for (final w in sameType) {
      final opt = _sentenceOption(w);
      if (opt != correctOption && !distractors.contains(opt)) {
        distractors.add(opt);
      }
      if (distractors.length >= optionCount - 1) break;
    }
  }

  // Any word, same grade as last resort
  if (distractors.length < optionCount - 1) {
    final sameGrade = pool
        .where((w) => w.id != target.id && w.gradeLevel == gradeIndex)
        .toList()
      ..shuffle(random);
    for (final w in sameGrade) {
      final opt = _sentenceOption(w);
      if (opt != correctOption && !distractors.contains(opt)) {
        distractors.add(opt);
      }
      if (distractors.length >= optionCount - 1) break;
    }
  }

  return distractors.toList();
}

/// Builds up to [maxChallenges] from [pool].
List<SentenceChallenge> buildSentenceChallenges({
  required List<GermanWord> pool,
  required int gradeIndex,
  int maxChallenges = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final challenges = <SentenceChallenge>[];
  for (final word in pool) {
    if (challenges.length >= maxChallenges) break;
    if (namesSomething(word)) continue;
    final challenge = buildSentenceChallenge(
      word: word,
      gradeIndex: gradeIndex,
      pool: pool,
      optionCount: optionCount,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}
