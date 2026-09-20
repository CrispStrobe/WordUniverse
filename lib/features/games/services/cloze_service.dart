// lib/features/games/services/cloze_service.dart
//
// Shared construction for the three games that blank a word out of a piece of
// text: Cloze Flash (example sentences), Expression Flash (expressions) and
// Proverb Cloze (proverbs). They differ only in where the text comes from.
//
// Extracted from the screens so the output can be generated and reviewed
// without running the games. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

/// Where a game gets the texts it may blank a word out of.
typedef ClozeTexts = List<String> Function(GermanWord word);

class ClozeResult {
  const ClozeResult({
    required this.before,
    required this.after,
    required this.matchedForm,
  });

  final String before;
  final String after;

  /// The exact form found in the text, which may be inflected.
  final String matchedForm;
}

class ClozeChallenge {
  const ClozeChallenge({
    required this.word,
    required this.source,
    required this.before,
    required this.after,
    required this.matchedForm,
    required this.options,
    required this.correctIndex,
  });

  final GermanWord word;

  /// The full text the blank was cut from.
  final String source;
  final String before;
  final String after;
  final String matchedForm;
  final List<String> options;
  final int correctIndex;
}

bool _isLetter(String c) => RegExp(r'[a-zA-ZäöüÄÖÜßéèêáàâ]').hasMatch(c);

/// Blanks [target] out of [sentence] on a whole-word boundary.
ClozeResult? tryBlank(String sentence, String target) {
  if (target.isEmpty) return null;
  final lowerSentence = sentence.toLowerCase();
  final lowerTarget = target.toLowerCase();
  var pos = 0;
  while (pos < lowerSentence.length) {
    final index = lowerSentence.indexOf(lowerTarget, pos);
    if (index < 0) return null;
    final end = index + lowerTarget.length;
    final beforeOk = index == 0 || !_isLetter(lowerSentence[index - 1]);
    final afterOk =
        end >= lowerSentence.length || !_isLetter(lowerSentence[end]);
    if (beforeOk && afterOk) {
      return ClozeResult(
        before: sentence.substring(0, index),
        after: sentence.substring(end),
        matchedForm: sentence.substring(index, end),
      );
    }
    pos = index + 1;
  }
  return null;
}

/// How many words remain visible around a blank.
int visibleWordCount(ClozeResult cloze) => (cloze.before + cloze.after)
    .trim()
    .split(RegExp(r'\s+'))
    .where((word) => word.trim().isNotEmpty)
    .length;

/// Whether the target still stands, as a whole word, in what is left visible
/// around the blank — in which case the gap is not a question.
bool _saysItAgain(ClozeResult cloze, String lemma) {
  final visible = '${cloze.before} ${cloze.after}';
  for (final form in {lemma, cloze.matchedForm}) {
    if (tryBlank(visible, form) != null) return true;
  }
  return false;
}

/// Builds up to [maxChallenges] by blanking each word out of one of its texts.
List<ClozeChallenge> buildClozeChallenges({
  required List<GermanWord> pool,
  required ClozeTexts texts,
  int maxChallenges = 10,
  int optionCount = 4,
  int minLength = 20,
  int maxLength = 180,
  int minVisibleWords = 0,
  Random? rng,
}) {
  final random = rng ?? Random();

  // Distractor pools: bucketed by word type so options match the target's part
  // of speech, plus a global fallback, all shuffled.
  final byType = <GermanWordType, List<String>>{};
  for (final word in pool) {
    if (namesSomething(word)) continue;
    byType.putIfAbsent(word.wordType, () => []).add(word.word);
  }
  for (final list in byType.values) {
    list.shuffle(random);
  }
  final anyType = [
    for (final word in pool)
      if (!namesSomething(word)) word.word,
  ]..shuffle(random);

  final challenges = <ClozeChallenge>[];
  for (final word in pool) {
    if (challenges.length >= maxChallenges) break;
    if (namesSomething(word)) continue;
    final challenge = buildClozeChallenge(
      word: word,
      texts: texts(word),
      byType: byType,
      anyType: anyType,
      optionCount: optionCount,
      minLength: minLength,
      maxLength: maxLength,
      minVisibleWords: minVisibleWords,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}

/// One challenge, or null when no text of [word] can be blanked fairly.
ClozeChallenge? buildClozeChallenge({
  required GermanWord word,
  required List<String> texts,
  required Map<GermanWordType, List<String>> byType,
  required List<String> anyType,
  int optionCount = 4,
  int minLength = 20,
  int maxLength = 180,
  int minVisibleWords = 0,
  Random? rng,
}) {
  final random = rng ?? Random();

  final candidates = <(String, ClozeResult)>[];
  for (final text in texts) {
    if (text.length < minLength || text.length > maxLength) continue;
    final cloze = tryBlank(text, word.word);
    if (cloze == null) continue;
    // A proverb with one word left beside the blank is not a question.
    if (visibleWordCount(cloze) < minVisibleWords) continue;
    // Neither is a sentence that says the word again beside the gap: "I asked
    // Mary, but ___ said that she didn't know."
    if (_saysItAgain(cloze, word.word)) continue;
    candidates.add((text, cloze));
  }
  if (candidates.isEmpty) return null;

  // The blank is filled by the form that actually appears in the text, which
  // can be inflected, while the options are bare lemmas. Prefer texts where
  // the matched form is the lemma so the correct option reads naturally;
  // otherwise offer the matched form, so that it actually fits the gap.
  candidates.sort((a, b) {
    final aExact =
        a.$2.matchedForm.toLowerCase() == word.word.toLowerCase() ? 0 : 1;
    final bExact =
        b.$2.matchedForm.toLowerCase() == word.word.toLowerCase() ? 0 : 1;
    return aExact.compareTo(bExact);
  });

  final (source, cloze) = candidates.first;
  final correctForm = cloze.matchedForm;

  // Distractors restricted to the target's word type, deduped against the
  // answer, the lemma and each other, and never a word the learner can
  // already read beside the gap. (Expression Flash had that last rule before
  // the three games were unified; it belongs to all of them.)
  final visibleText = '${cloze.before}${cloze.after}'.toLowerCase();
  final distractors = <String>[];
  // Shuffled per challenge: taking from the front of one list put the same
  // three words beside every gap — "Schule, Eltern, Schwein", round after
  // round.
  final sameType = (byType[word.wordType] ?? const <String>[]).toList()
    ..shuffle(random);
  final anyOther = anyType.toList()..shuffle(random);
  for (final candidate in [...sameType, ...anyOther]) {
    if (distractors.length >= optionCount - 1) break;
    if (candidate.toLowerCase() == correctForm.toLowerCase()) continue;
    if (candidate.toLowerCase() == word.word.toLowerCase()) continue;
    if (visibleText.contains(candidate.toLowerCase())) continue;
    if (distractors.any((d) => d.toLowerCase() == candidate.toLowerCase())) {
      continue;
    }
    distractors.add(candidate);
  }
  if (distractors.isEmpty) return null;

  final options = [correctForm, ...distractors.take(optionCount - 1)]
    ..shuffle(random);
  final correctIndex =
      options.indexWhere((o) => o.toLowerCase() == correctForm.toLowerCase());
  if (correctIndex < 0) return null;

  return ClozeChallenge(
    word: word,
    source: source,
    before: cloze.before,
    after: cloze.after,
    matchedForm: correctForm,
    options: options,
    correctIndex: correctIndex,
  );
}
