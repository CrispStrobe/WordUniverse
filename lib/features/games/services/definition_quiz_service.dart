// lib/features/games/services/definition_quiz_service.dart
//
// Definition Quiz challenge construction, extracted from the screen so it can
// be generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

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

bool _hasUsableGloss(GermanWord word) {
  final definition = word.displayDefinitions.firstOrNull;
  return definition != null && isUsableDefinition(definition);
}

/// Whether a gloss only makes sense next to the sense above it — "The fruit of
/// this tree", "One who does this". Read alone as a quiz prompt it carries no
/// information, so a self-contained sense is preferred when there is one.
bool refersToAnotherSense(String definition) => _anaphora.hasMatch(definition);

/// Demonstratives that point at a neighbouring sense, in both pack languages.
/// Only used to *prefer* another sense, so a false positive costs nothing when
/// the word has no second sense to fall back to.
final RegExp _anaphora = RegExp(
    r'\b(this|these|such|the same|dieser|diese|dieses|diesem|diesen|solche[rsmn]?)\b',
    caseSensitive: false);

/// A long gloss cut at its first clause, when that leaves something usable.
///
/// Public because a prompt has to be traceable back to the pack: see
/// test/live/item_provenance_live_test.dart, which undoes this to check that
/// what a learner reads is what the pack wrote.
///
/// The packs join senses with semicolons — "To make somebody able (to do, or
/// to be, something); to give sufficient ability or power to do or to be" —
/// and the first clause is the sense a learner needs.
String firstClauseIfLong(String definition) {
  if (definition.length <= 120) return definition;
  for (final separator in [';', '. ']) {
    final cut = definition.indexOf(separator);
    if (cut > 20 && cut <= 120) {
      final clause = definition.substring(0, cut).trim();
      if (isUsableDefinition(clause)) return clause;
    }
  }
  return definition;
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
  // A gloss that parses the word ("plural of passerby"), abbreviates it
  // ("Abbreviation of July."), names a place, or is a bare domain label
  // ("Botanik:") is not a meaning to ask about.
  final usable =
      definitions.take(sensesConsidered).where(isUsableDefinition).toList();
  if (usable.isEmpty) return null;
  // A sense longer than the card can show is shortened at its own first
  // clause rather than skipped: skipping took "enable" from "To make somebody
  // able to do something" — 130 characters — down to its archaic second
  // sense, "To affirm; to make firm and strong", which a model reading the
  // items flagged as not matching the word at all.
  final common = [for (final d in usable) firstClauseIfLong(d)];
  var definition = common.firstWhere(
    (d) =>
        d.length <= 120 &&
        !d.toLowerCase().contains(lower) &&
        !refersToAnotherSense(d),
    // A gloss carrying the headword beats one that only points at the sense
    // above it: redaction removes the giveaway and what is left still
    // describes the word, where "The fruit of this tree" describes nothing.
    orElse: () => common.firstWhere(
      (d) => d.length <= 120 && !refersToAnotherSense(d),
      orElse: () => common.firstWhere(
        (d) => d.length <= 120,
        orElse: () => definitions.first,
      ),
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
    // Headwords only, and never a name: "hannibal" sat among the options for
    // "detector" because the pack does not flag it as a proper noun — its
    // gloss ("A male given name from …") does.
    //
    // Nor a misspelling: English grade 6 is full of entries like "residental"
    // (glossed "residentiary"), "controversal" and "undesireable", and three
    // wrong spellings beside one right word is a spelling lesson in reverse.
    // A light word has no gloss to judge, and was filtered when the pack was
    // indexed.
    candidates = candidates.where((w) =>
        w.isHeadword &&
        !namesSomething(w) &&
        isPresentableVocabularyEntry(w) &&
        (!w.isHydrated || _hasUsableGloss(w)));
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
