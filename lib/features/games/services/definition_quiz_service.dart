// lib/features/games/services/definition_quiz_service.dart
//
// Definition Quiz challenge construction, extracted from the screen so it can
// be generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';

class DefinitionChallenge {
  const DefinitionChallenge({
    required this.word,
    required this.definition,
    required this.options,
    required this.correctIndex,
  });

  final GermanWord word;
  final String definition;

  /// Display labels, shuffled.
  final List<String> options;
  final int correctIndex;
}

/// How a word is offered as an answer: German nouns carry their article.
String definitionOptionLabel(GermanWord word, {required bool isGerman}) {
  if (isGerman &&
      word.wordType == GermanWordType.substantiv &&
      word.article != null &&
      word.article!.isNotEmpty) {
    return '${word.article} ${word.word}';
  }
  return word.word;
}

/// Builds up to [maxChallenges] from [pool], drawing distractors from the same
/// pool. [pool] is expected grade-first and hydrated — see
/// `VocabularyService.takeWordsWithFeature`.
List<DefinitionChallenge> buildDefinitionChallenges({
  required List<GermanWord> pool,
  required bool isGerman,
  int maxChallenges = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final challenges = <DefinitionChallenge>[];
  for (final word in pool) {
    if (challenges.length >= maxChallenges) break;
    final challenge = buildDefinitionChallenge(
      word: word,
      pool: pool,
      isGerman: isGerman,
      optionCount: optionCount,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}

/// One challenge, or null when [word] cannot make a fair one.
DefinitionChallenge? buildDefinitionChallenge({
  required GermanWord word,
  required List<GermanWord> pool,
  required bool isGerman,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  // displayDefinitions, not apiEnrichment.definitions: an entry whose
  // enrichment belongs to another word would be keyed to that word's meaning.
  final definitions = word.displayDefinitions;
  if (definitions.isEmpty) return null;

  // Pick a definition that is reasonably short for display and — crucially —
  // does not contain the headword (many dictionary glosses start with it,
  // which would give the answer away). Redact any residual occurrence.
  //
  // Only the first couple of senses are considered. Scanning the whole list
  // for a headword-free gloss reaches obscure ones: "male" was being keyed to
  // "A bacterium which has the F factor", because every common sense of it
  // contains the word. Redaction already prevents a gloss from giving the
  // answer away, so falling back to the primary sense is better than asking
  // about a meaning no learner will meet.
  const sensesConsidered = 2;
  final lower = word.word.toLowerCase();
  final common = definitions.take(sensesConsidered);
  var definition = common.firstWhere(
    (d) => d.length <= 120 && !d.toLowerCase().contains(lower),
    orElse: () => common.firstWhere(
      (d) => d.length <= 120,
      orElse: () => definitions.first,
    ),
  );
  // Word boundaries: an unanchored replace redacted the headword inside other
  // words — "The larger part of an ___ism" for "organ".
  definition = definition.replaceAll(
    RegExp('\\b${RegExp.escape(word.word)}\\b', caseSensitive: false),
    '___',
  );
  if (describesAName(definition)) return null;

  final correct = definitionOptionLabel(word, isGerman: isGerman);
  final distractors = pickDefinitionDistractors(
    target: word,
    correctOption: correct,
    pool: pool,
    isGerman: isGerman,
    optionCount: optionCount,
    rng: random,
  );
  if (distractors.length < optionCount - 1) return null;

  final options = [correct, ...distractors.take(optionCount - 1)]
    ..shuffle(random);
  final correctIndex = options.indexOf(correct);
  if (correctIndex < 0) return null;

  return DefinitionChallenge(
    word: word,
    definition: definition,
    options: options,
    correctIndex: correctIndex,
  );
}

/// Plausible wrong answers: same CEFR level and word type first, then same
/// word type and grade, then anything.
List<String> pickDefinitionDistractors({
  required GermanWord target,
  required String correctOption,
  required List<GermanWord> pool,
  required bool isGerman,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final distractors = <String>{};

  void drawFrom(Iterable<GermanWord> candidates) {
    if (distractors.length >= optionCount - 1) return;
    // Headwords only, as for the answer: an inflected form among the options
    // reads as a different kind of thing ("interests" beside "conviction").
    candidates = candidates.where((w) => w.isHeadword);
    final shuffled = candidates.toList()..shuffle(random);
    for (final word in shuffled) {
      final option = definitionOptionLabel(word, isGerman: isGerman);
      if (option != correctOption) distractors.add(option);
      if (distractors.length >= optionCount - 1) break;
    }
  }

  drawFrom(pool.where((w) =>
      w.id != target.id &&
      w.cefrLevel == target.cefrLevel &&
      w.wordType == target.wordType));
  drawFrom(pool.where((w) =>
      w.id != target.id &&
      w.wordType == target.wordType &&
      w.gradeLevel == target.gradeLevel));
  drawFrom(pool.where((w) => w.id != target.id));

  return distractors.toList();
}

/// Whether a gloss describes a name or a place rather than a meaning.
///
/// Wiktionary writes proper nouns with a fixed set of openings, and the packs
/// do not always type them as proper nouns: "franklin" arrives as an ordinary
/// grade-3 word glossed "A surname transferred from the nickname", and
/// "columbia" as "America; the United States; an appellation given in honor of
/// Christopher Columbus". Neither is vocabulary a learner can reason about.
bool describesAName(String definition) {
  final lower = definition.toLowerCase();
  const openings = [
    'a surname', 'a male given name', 'a female given name', 'a given name',
    'a unisex given name', 'a placename', 'a place name', 'an appellation',
    'a diminutive of the male', 'a diminutive of the female',
  ];
  if (openings.any(lower.startsWith)) return true;
  const settlements = [
    'a city in', 'a town in', 'a village in', 'a county in', 'a river in',
    'a lake in', 'a state of', 'a province of', 'an unincorporated community',
    'a census-designated place',
  ];
  return settlements.any(lower.contains);
}
