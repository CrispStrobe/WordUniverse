// lib/features/games/services/conjugation_drill_challenges.dart
//
// Conjugation Drill challenge construction, extracted from the screen so it
// can be generated and reviewed without running the game. The Präsens lookup
// and distractor picking live in conjugation_drill_service.dart.
// See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import 'conjugation_drill_service.dart';

class ConjugationChallenge {
final GermanWord verb;
final String pronoun;
final String correctForm;
final List<String> options; // length 4, shuffled
final int correctIndex;

const ConjugationChallenge({
  required this.verb,
  required this.pronoun,
  required this.correctForm,
  required this.options,
  required this.correctIndex,
});
}

/// Builds up to [maxChallenges] from [verbs], which must already be filtered
/// with `isConjugatableVerb`.
List<ConjugationChallenge> buildConjugationChallenges({
  required List<GermanWord> verbs,
  int maxChallenges = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();

  // Every form of every verb, per pronoun, so distractors are forms a learner
  // could plausibly confuse rather than arbitrary words.
  final formsByPronoun = <String, List<String>>{};
  for (final pronoun in conjugationPronouns) {
    formsByPronoun[pronoun] = verbs
        .map((verb) => getPraesensForWord(verb)?[pronoun])
        .whereType<String>()
        .toList()
      ..shuffle(random);
  }

  final challenges = <ConjugationChallenge>[];
  for (final verb in verbs) {
    if (challenges.length >= maxChallenges) break;
    final present = getPraesensForWord(verb);
    if (present == null) continue;

    // Skip pronouns whose Präsens form is identical to the infinitive shown on
    // the verb card (wir/sie/Sie -> "wir laufen"): the answer would just be the
    // displayed word. Keep ich/du/er-sie-es, where the stem changes.
    final available = conjugationPronouns
        .where((p) =>
            present.containsKey(p) &&
            present[p]!.toLowerCase() != verb.word.toLowerCase())
        .toList()
      ..shuffle(random);
    if (available.isEmpty) continue;

    final pronoun = available.first;
    final correct = present[pronoun]!;
    final distractors = pickDistractors(
      pronoun,
      correct,
      verb.word,
      formsByPronoun[pronoun] ?? const [],
      count: optionCount - 1,
    );
    if (distractors.length < 2) continue;

    final options = [correct, ...distractors]..shuffle(random);
    final correctIndex = options.indexOf(correct);
    if (correctIndex < 0) continue;

    challenges.add(ConjugationChallenge(
      verb: verb,
      pronoun: pronoun,
      correctForm: correct,
      options: options,
      correctIndex: correctIndex,
    ));
  }
  return challenges;
}
