// lib/features/games/services/sri_review_service.dart
//
// Review challenge construction, extracted from the screen so it can be
// generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/services/sri_service.dart';
import '../../../generated/l10n.dart';
import 'definition_quiz_service.dart';
import 'spelling_spotter_service.dart';

enum ReviewChallengeType { definition, article, spelling }

class ReviewChallenge {
  final GermanWord word;
  final SriLanguageData sriData;
  final ReviewChallengeType type;

  /// Prompt displayed above the options (definition, "Der/Die/Das ___?", …)
  final String prompt;
  final List<String> options;
  final int correctIndex;

  const ReviewChallenge({
    required this.word,
    required this.sriData,
    required this.type,
    required this.prompt,
    required this.options,
    required this.correctIndex,
  });
}

ReviewChallenge? buildReviewChallenge(
  GermanWord word,
  SriLanguageData sriData,
  List<GermanWord> allWords,
  Set<String> validWords, {
  required S strings,
  required bool isGerman,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  // Try the skill-specific format first, fall back to definition quiz.
  if (sriData.skillType == LanguageSkillType.articleSelection &&
      isGerman &&
      word.wordType == GermanWordType.substantiv &&
      word.article != null &&
      ['der', 'die', 'das'].contains(word.article!.toLowerCase())) {
    return _articleChallenge(word, sriData, strings: strings, random: random);
  }

  if (sriData.skillType == LanguageSkillType.spelling) {
    final c = _spellingChallenge(word, sriData, validWords,
        strings: strings,
        isGerman: isGerman,
        optionCount: optionCount,
        random: random);
    if (c != null) return c;
  }

  return _definitionChallenge(word, sriData, allWords,
      isGerman: isGerman, optionCount: optionCount, random: random);
}

ReviewChallenge? _articleChallenge(GermanWord word, SriLanguageData sriData,
    {required S strings, required Random random}) {
  final correct = word.article!.toLowerCase();
  final wrong = ['der', 'die', 'das'].where((a) => a != correct).toList();
  final options = [correct, ...wrong]..shuffle(random);
  final prompt = strings.articleChallengePrompt(word.word);
  return ReviewChallenge(
    word: word,
    sriData: sriData,
    type: ReviewChallengeType.article,
    prompt: prompt,
    options: options,
    correctIndex: options.indexOf(correct),
  );
}

ReviewChallenge? _spellingChallenge(
    GermanWord word, SriLanguageData sriData, Set<String> validWords,
    {required S strings,
    required bool isGerman,
    required int optionCount,
    required Random random}) {
  final displayWord = normWord(word.word);
  if (displayWord.contains(' ')) return null;

  final rawErrors = isGerman
      ? (word.commonMistakes ?? <String>[])
      : (word.apiEnrichment?.commonLearnerErrors ?? <String>[]);
  final errors = parseErrors(rawErrors)
      .map(normWord)
      .where((e) =>
          e.toLowerCase() != displayWord.toLowerCase() &&
          e.isNotEmpty &&
          !e.contains(' ') &&
          !validWords.contains(e.toLowerCase()))
      .take(optionCount - 1)
      .toList();

  if (errors.isEmpty) return null;

  final options = [displayWord, ...errors]..shuffle(random);
  final definition = word.displayDefinitions.firstOrNull;
  final prompt = definition != null
      ? strings.spellingForDefinition(definition)
      : strings.spellingSpotterPrompt;
  return ReviewChallenge(
    word: word,
    sriData: sriData,
    type: ReviewChallengeType.spelling,
    prompt: prompt,
    options: options,
    correctIndex: options.indexOf(displayWord),
  );
}

ReviewChallenge? _definitionChallenge(
    GermanWord word, SriLanguageData sriData, List<GermanWord> allWords,
    {required bool isGerman,
    required int optionCount,
    required Random random}) {
  // Shared with the Definition Quiz so the review inherits its fairness rules:
  // the headword is redacted out of the gloss, name glosses are rejected, and
  // German nouns are offered with their article.
  final quiz = buildDefinitionChallenge(
    word: word,
    pool: allWords,
    isGerman: isGerman,
    optionCount: optionCount,
    rng: random,
  );
  if (quiz == null) return null;
  return ReviewChallenge(
    word: word,
    sriData: sriData,
    type: ReviewChallengeType.definition,
    prompt: '"${quiz.definition}"',
    options: quiz.options,
    correctIndex: quiz.correctIndex,
  );
}
