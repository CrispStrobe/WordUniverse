// lib/features/games/services/synonym_flash_service.dart
//
// Synonym Flash challenge construction, extracted from the screen so it can be
// generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';
import '../../../core/models/word_features.dart';

class SynonymChallenge {
  const SynonymChallenge({
    required this.word,
    required this.correctSynonym,
    required this.options,
    required this.correctIndex,
  });

  final GermanWord word;
  final String correctSynonym;
  final List<String> options;
  final int correctIndex;
}

/// One challenge, or null when [word] has no synonym that makes a fair one.
SynonymChallenge? buildSynonymChallenge({
  required GermanWord word,
  required List<GermanWord> allWords,
  required Set<String> wordSet,
  required bool isGerman,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final synonyms = word.apiEnrichment?.synonyms ?? const [];
  if (synonyms.isEmpty) return null;
  // "atlantic" glossed as an ocean is a name, not vocabulary.
  if (namesSomething(word)) return null;

  // Rank the clean synonyms by how likely a learner is to know them. The
  // packs list rare and sense-specific ones beside everyday ones — "Almighty"
  // for "creator", "deport" for "behave", "mantle" for "cape" — and picking at
  // random from the whole list asks about the rarest as often as the
  // commonest. Preference: a curriculum word at or below the prompt's band,
  // then any catalogue word near it, then anything else in the catalogue, then
  // synonyms the catalogue does not contain at all.
  final bySpelling = {
    for (final candidate in allWords) candidate.word.toLowerCase(): candidate,
  };
  final curriculumTier = <String>[];
  final nearTier = <String>[];
  final inVocab = <String>[];
  final outOfVocab = <String>[];
  for (final syn in synonyms) {
    final clean = syn.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
    if (!_isCleanSynonym(clean)) continue;
    // A synonym that differs from the prompt only in case is no question at
    // all: the pack offered "Creator" for "creator", "Atlantic" for
    // "atlantic".
    if (clean.toLowerCase() == word.word.toLowerCase()) continue;
    // In English a capitalised synonym for a lowercase word is a proper-noun
    // sense — "Almighty" for "creator", "Romance" for "latin". German
    // capitalises every noun, so the same test cannot be applied there.
    if (!isGerman &&
        word.word == word.word.toLowerCase() &&
        clean != clean.toLowerCase()) {
      continue;
    }
    final entry = bySpelling[clean.toLowerCase()];
    if (entry == null) {
      if (wordSet.contains(clean.toLowerCase())) {
        inVocab.add(clean);
      } else {
        outOfVocab.add(clean);
      }
      continue;
    }
    if (entry.has(WordFeature.curriculum) &&
        entry.gradeLevel <= word.gradeLevel) {
      curriculumTier.add(clean);
    } else if (entry.gradeLevel <= word.gradeLevel + 1) {
      nearTier.add(clean);
    } else {
      inVocab.add(clean);
    }
  }
  // Randomize which valid synonym is the answer (rather than always the
  // first), from the best tier that has one.
  final candidates = [curriculumTier, nearTier, inVocab, outOfVocab]
      .firstWhere((tier) => tier.isNotEmpty, orElse: () => const []);
  if (candidates.isEmpty) return null;
  final correctWord = candidates[random.nextInt(candidates.length)];

  // Any of the word's listed synonyms counts as correct, so exclude them all
  // (plus the prompt word itself) from the distractor pool.
  final synSet =
      synonyms.map((s) => s.toLowerCase()).toSet()..add(word.word.toLowerCase());

  // Restrict distractors to the same word type as the prompt for plausibility;
  // fall back to any word type if too few same-type candidates exist.
  bool eligible(GermanWord w) =>
      !synSet.contains(w.word.toLowerCase()) &&
      w.word.toLowerCase() != correctWord.toLowerCase() &&
      !namesSomething(w);

  final sameType = allWords
      .where((w) => w.wordType == word.wordType && eligible(w))
      .map((w) => w.word)
      .toList()
    ..shuffle(random);
  final anyType = allWords
      .where(eligible)
      .map((w) => w.word)
      .toList()
    ..shuffle(random);

  final needed = optionCount - 1;
  // Dedupe distractors against each other (case-insensitively) and against
  // the correct answer using a seen-set guard.
  final distractors = <String>[];
  final seen = <String>{correctWord.toLowerCase()};
  for (final source in [sameType, anyType]) {
    for (final t in source) {
      if (distractors.length >= needed) break;
      if (seen.add(t.toLowerCase())) distractors.add(t);
    }
    if (distractors.length >= needed) break;
  }
  if (distractors.isEmpty) return null;

  final options = [correctWord, ...distractors.take(needed)]..shuffle(random);
  final correctIndex = options.indexWhere(
      (o) => o.toLowerCase() == correctWord.toLowerCase());
  if (correctIndex < 0) return null;

  return SynonymChallenge(
    word: word,
    correctSynonym: correctWord,
    options: options,
    correctIndex: correctIndex,
  );
}

bool _isCleanSynonym(String s) {
  if (s.length < 2 || s.contains(' ')) return false;
  if (RegExp(r'\d').hasMatch(s)) return false;
  if (s == s.toUpperCase() && s.length > 1) return false;
  return RegExp(r"^[\p{L}\-' ]+$", unicode: true).hasMatch(s);
}

/// Builds up to [maxChallenges] from [pool].
List<SynonymChallenge> buildSynonymChallenges({
  required List<GermanWord> pool,
  required bool isGerman,
  int maxChallenges = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final wordSet = pool.map((w) => w.word.toLowerCase()).toSet();
  final challenges = <SynonymChallenge>[];
  for (final word in pool) {
    if (challenges.length >= maxChallenges) break;
    final challenge = buildSynonymChallenge(
      word: word,
      allWords: pool,
      wordSet: wordSet,
      isGerman: isGerman,
      optionCount: optionCount,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}
