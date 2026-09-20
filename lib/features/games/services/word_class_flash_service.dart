// lib/features/games/services/word_class_flash_service.dart
//
// Word Class Flash challenge selection, extracted from the screen so it can be
// generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

class WordClassChallenge {
  const WordClassChallenge({required this.word, required this.correctType});

  final GermanWord word;
  final GermanWordType correctType;
}

/// Words that can be asked about without ambiguity, grade-preferred.
///
/// The packs carry no ambiguity flag, but the same surface form can belong to
/// more than one word class — "laut" is adjective, adverb and noun — and such
/// a round would have more than one defensible answer. Any spelling that
/// appears with conflicting types is dropped, unless that leaves too few words
/// to play with.
List<GermanWord> selectWordClassCandidates({
  required List<GermanWord> catalogue,
  required Set<GermanWordType> askableTypes,
  required int gradeLevel,
  int minimumPool = 10,
  Random? rng,
}) {
  final random = rng ?? Random();
  final candidates = catalogue
      .where((w) =>
          !w.isProperNoun &&
          !namesSomething(w) &&
          !w.word.contains('_') &&
          !w.word.contains(' ') &&
          // "Geheimnisse" is the plural of "Geheimnis"; asking the class of an
          // inflected form teaches the form, not the class.
          w.isHeadword &&
          // "PDS", "SPD": an abbreviation is not a word class question.
          w.word != w.word.toUpperCase() &&
          askableTypes.contains(w.wordType))
      .toList();

  final typesPerSurface = <String, Set<GermanWordType>>{};
  for (final word in candidates) {
    typesPerSurface
        .putIfAbsent(word.word.toLowerCase(), () => <GermanWordType>{})
        .add(word.wordType);
  }
  final unambiguous = candidates
      .where((w) => typesPerSurface[w.word.toLowerCase()]!.length == 1)
      .toList();

  final pool = unambiguous.length >= minimumPool ? unambiguous : candidates;
  if (pool.isEmpty) return const [];

  final graded = pool.where((w) => w.gradeLevel == gradeLevel).toList();
  final chosen = graded.length >= minimumPool ? graded : pool.toList();
  return _roundRobinByType(chosen..shuffle(random));
}

/// Deals the words out one word class at a time.
///
/// German nouns outnumber everything else in the packs, so a shuffled pool
/// gave six noun rounds in a row — "Nomen" every time scored full marks.
List<GermanWord> _roundRobinByType(List<GermanWord> words) {
  final byType = <GermanWordType, List<GermanWord>>{};
  for (final word in words) {
    byType.putIfAbsent(word.wordType, () => []).add(word);
  }
  final queues = byType.values.toList();
  final dealt = <GermanWord>[];
  var index = 0;
  while (dealt.length < words.length) {
    final queue = queues[index % queues.length];
    if (queue.isNotEmpty) dealt.add(queue.removeAt(0));
    index++;
    if (queues.every((queue) => queue.isEmpty)) break;
  }
  return dealt;
}

/// The challenges for [words], which are expected to be hydrated already.
List<WordClassChallenge> buildWordClassChallenges({
  required List<GermanWord> words,
  int maxChallenges = 10,
}) =>
    words
        .take(maxChallenges)
        .map((w) => WordClassChallenge(word: w, correctType: w.wordType))
        .toList();
