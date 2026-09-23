// lib/features/games/services/phrasal_verb_service.dart
//
// Challenge-building logic for two EN-only phrasal-verb games sharing the
// `phrasal_verbs` table:
//   • Phrasal Verb Power (#46) — pick the particle that completes a sentence
//     ("Please ___ your toys." → put [away]). Distractor particles form real
//     but contextually-wrong phrasal verbs of the same base verb.
//   • Phrasal Verb Match (#47) — pick the meaning of a phrasal verb. Distractor
//     meanings are real meanings of other phrasal verbs.
//
// Pure logic, no DB dependency — data is loaded via
// DictionaryDatabaseService.getPhrasalVerbs() and passed in.

import 'dart:math';

import '../../../core/models/vocabulary_quality.dart';
import '../models/phrasal_verb.dart';

class PhrasalChallenge {
  final String phrasal; // "give up"
  final String baseVerb; // "give"
  final String particle; // correct particle: "up"
  final String sentence; // "She decided to give ___ smoking."
  final List<String> options; // shuffled particles, length 2-4
  final int correctIndex;
  final String meaning; // shown after answering

  const PhrasalChallenge({
    required this.phrasal,
    required this.baseVerb,
    required this.particle,
    required this.sentence,
    required this.options,
    required this.correctIndex,
    required this.meaning,
  });
}

/// Builds up to [maxChallenges] particle-completion challenges from [verbs],
/// preferring entries whose grade band is near [gradeLevel].
List<PhrasalChallenge> buildPhrasalChallenges({
  required List<PhrasalVerb> verbs,
  required int gradeLevel,
  int maxChallenges = 15,
  Random? rng,
}) {
  final r = rng ?? Random();

  // Order entries: grade-band closeness first, then shuffle within bands so
  // repeated plays vary. Stable for a fixed rng (tests pass a seeded Random).
  // "lie by" is glossed "be intimate with someone" — a real archaic sense,
  // so there is nothing to correct and the entry simply is not taught.
  final pool = verbs.where((v) => phrasalMeaningSuitsAChild(v.meaning)).toList()
    ..shuffle(r);
  pool.sort((a, b) => (a.gradeBand - gradeLevel)
      .abs()
      .compareTo((b.gradeBand - gradeLevel).abs()));

  final challenges = <PhrasalChallenge>[];
  for (final pv in pool) {
    if (challenges.length >= maxChallenges) break;
    if (pv.particle.isEmpty) continue;

    final sentence = _pickSentence(pv, gradeLevel);
    if (sentence == null) continue;

    final options = _buildOptions(pv, r);
    final correctIndex =
        options.indexWhere((o) => o.toLowerCase() == pv.particle.toLowerCase());
    if (correctIndex < 0) continue;
    if (options.length < 3) continue; // avoid 1-2 option (≥50/50) giveaways

    challenges.add(PhrasalChallenge(
      phrasal: pv.phrasal,
      baseVerb: pv.baseVerb,
      particle: pv.particle,
      sentence: sentence,
      options: options,
      correctIndex: correctIndex,
      meaning: pv.meaning,
    ));
  }
  return challenges;
}

/// Correct particle + up to 3 distractors, de-duped and shuffled.
List<String> _buildOptions(PhrasalVerb pv, Random r) {
  final seen = <String>{pv.particle.toLowerCase()};
  final options = <String>[pv.particle];
  for (final d in pv.distractors) {
    if (seen.add(d.toLowerCase())) options.add(d);
    if (options.length >= 4) break;
  }
  options.shuffle(r);
  return options;
}

/// Picks a grade-appropriate sentence (LLM grade examples first, then
/// Wiktionary fallback) and blanks the particle. Returns null if none usable.
String? _pickSentence(PhrasalVerb pv, int gradeLevel) {
  for (final g in _gradeSearchOrder(gradeLevel)) {
    final sentences = pv.examples['$g'];
    if (sentences == null) continue;
    for (final raw in sentences) {
      final blanked = _blankParticle(raw, pv.particle);
      if (blanked != null) return blanked;
    }
  }
  for (final raw in pv.wiktionaryExamples) {
    final blanked = _blankParticle(raw, pv.particle);
    if (blanked != null) return blanked;
  }
  return null;
}

/// Replaces the first whole-word occurrence of [particle] with "___".
/// Returns null if the particle does not appear as a standalone word.
String? _blankParticle(String sentence, String particle) {
  final lower = sentence.toLowerCase();
  final target = particle.toLowerCase();
  var from = 0;
  while (true) {
    final idx = lower.indexOf(target, from);
    if (idx < 0) return null;
    final before = idx > 0 ? lower[idx - 1] : ' ';
    final after =
        idx + target.length < lower.length ? lower[idx + target.length] : ' ';
    if (!_isWordChar(before) && !_isWordChar(after)) {
      return (sentence.substring(0, idx) +
              '___' +
              sentence.substring(idx + particle.length))
          .trim();
    }
    from = idx + target.length;
  }
}

bool _isWordChar(String c) => RegExp(r"[a-zA-Z0-9']").hasMatch(c);

List<int> _gradeSearchOrder(int grade) {
  final result = <int>[grade];
  for (var d = 1; d <= 5; d++) {
    if (grade - d >= 1) result.add(grade - d);
    if (grade + d <= 6) result.add(grade + d);
  }
  return result;
}

// ─── Phrasal Verb Match (#47) ──────────────────────────────────────────────

class PhrasalMatchChallenge {
  final String phrasal; // "give up"
  final String correctMeaning; // "stop trying"
  final List<String> options; // shuffled meanings, length 2-4
  final int correctIndex;
  final String? example; // optional context sentence (not blanked)

  const PhrasalMatchChallenge({
    required this.phrasal,
    required this.correctMeaning,
    required this.options,
    required this.correctIndex,
    this.example,
  });
}

/// Builds up to [maxChallenges] meaning-match challenges from [verbs]. Each
/// shows a phrasal verb; the player picks its meaning from [optionCount]
/// choices. Distractor meanings are real meanings of OTHER phrasal verbs
/// (preferring a different base verb so they read as plausible-but-distinct).
List<PhrasalMatchChallenge> buildPhrasalMatchChallenges({
  required List<PhrasalVerb> verbs,
  required int gradeLevel,
  int maxChallenges = 15,
  int optionCount = 4,
  Random? rng,
}) {
  final r = rng ?? Random();

  final usable = verbs
      .where((v) =>
          v.meaning.trim().isNotEmpty && phrasalMeaningSuitsAChild(v.meaning))
      .toList();
  if (usable.length < 2) return [];

  // Global meaning pool for distractors: (meaning, baseVerb), deduped by
  // lowercased meaning to avoid offering the same gloss twice.
  final pool = <({String meaning, String base})>[];
  final seenMeaning = <String>{};
  for (final v in usable) {
    final key = v.meaning.toLowerCase();
    if (seenMeaning.add(key)) {
      pool.add((meaning: v.meaning, base: v.baseVerb));
    }
  }

  final ordered = List<PhrasalVerb>.from(usable)..shuffle(r);
  ordered.sort((a, b) => (a.gradeBand - gradeLevel)
      .abs()
      .compareTo((b.gradeBand - gradeLevel).abs()));

  final challenges = <PhrasalMatchChallenge>[];
  for (final pv in ordered) {
    if (challenges.length >= maxChallenges) break;

    final correct = pv.meaning.trim();
    final correctKey = correct.toLowerCase();

    // Prefer distractors from a different base verb; fall back to any.
    final candidates = pool
        .where((p) => p.meaning.toLowerCase() != correctKey)
        .toList()
      ..shuffle(r);
    candidates.sort((a, b) {
      final aSame = a.base == pv.baseVerb ? 1 : 0;
      final bSame = b.base == pv.baseVerb ? 1 : 0;
      return aSame.compareTo(bSame); // different-base first
    });

    final distractors = <String>[];
    final used = <String>{correctKey};
    for (final c in candidates) {
      if (distractors.length >= optionCount - 1) break;
      if (used.add(c.meaning.toLowerCase())) distractors.add(c.meaning);
    }
    if (distractors.length < 2) continue; // ≥3 options; avoid 50/50 guessing

    final options = <String>[correct, ...distractors]..shuffle(r);
    final correctIndex =
        options.indexWhere((o) => o.toLowerCase() == correctKey);
    if (correctIndex < 0) continue;

    challenges.add(PhrasalMatchChallenge(
      phrasal: pv.phrasal,
      correctMeaning: correct,
      options: options,
      correctIndex: correctIndex,
      example: _pickExample(pv, gradeLevel),
    ));
  }
  return challenges;
}

/// A context sentence using the phrasal verb (not blanked), grade-preferred.
String? _pickExample(PhrasalVerb pv, int gradeLevel) {
  for (final g in _gradeSearchOrder(gradeLevel)) {
    final sentences = pv.examples['$g'];
    if (sentences != null && sentences.isNotEmpty) return sentences.first;
  }
  return pv.wiktionaryExamples.isNotEmpty ? pv.wiktionaryExamples.first : null;
}
