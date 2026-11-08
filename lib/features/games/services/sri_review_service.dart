// lib/features/games/services/sri_review_service.dart
//
// Review challenge construction, extracted from the screen so it can be
// generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';
import '../../../core/services/sri_service.dart';
import '../../../generated/l10n.dart';
import 'cloze_service.dart';
import 'conjugation_drill_service.dart';
import 'definition_quiz_service.dart';
import 'spelling_spotter_service.dart';

enum ReviewChallengeType {
  definition,
  article,
  spelling,
  wordType,
  conjugation,
  plural,
  capitalization,
}

class ReviewChallenge {
  final GermanWord word;
  final SriLanguageData sriData;
  final ReviewChallengeType type;
  final LanguageSkillType assessedSkill;

  /// Prompt displayed above the options (definition, "Der/Die/Das ___?", …)
  final String prompt;
  final List<String> options;
  final int correctIndex;

  const ReviewChallenge({
    required this.word,
    required this.sriData,
    required this.type,
    required this.assessedSkill,
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
  Iterable<GermanWord>? catalogue,
}) {
  final random = rng ?? Random();
  if (word.isProperNoun || namesSomething(word)) return null;
  // A missing format is left due. A definition question is evidence about
  // vocabulary; it must never advance spelling, reading or grammar mastery.
  switch (sriData.skillType) {
    case LanguageSkillType.articleSelection:
      if (!isGerman ||
          word.wordType != GermanWordType.substantiv ||
          !['der', 'die', 'das'].contains(word.article?.toLowerCase())) {
        return null;
      }
      return _articleChallenge(word, sriData, strings: strings, random: random);
    case LanguageSkillType.spelling:
      return _spellingChallenge(
        word,
        sriData,
        validWords,
        strings: strings,
        isGerman: isGerman,
        optionCount: optionCount,
        random: random,
      );
    case LanguageSkillType.vocabulary:
      return _definitionChallenge(
        word,
        sriData,
        allWords,
        isGerman: isGerman,
        optionCount: optionCount,
        random: random,
      );
    case LanguageSkillType.wordType:
      return _wordTypeChallenge(
        word,
        sriData,
        catalogue ?? allWords,
        strings: strings,
        optionCount: optionCount,
        random: random,
      );
    case LanguageSkillType.verbConjugation:
      return isGerman
          ? _conjugationChallenge(
              word,
              sriData,
              strings: strings,
              optionCount: optionCount,
              random: random,
            )
          : null;
    case LanguageSkillType.pluralForm:
      return _pluralChallenge(
        word,
        sriData,
        allWords,
        strings: strings,
        optionCount: optionCount,
        random: random,
      );
    case LanguageSkillType.capitalization:
      return _capitalizationChallenge(
        word,
        sriData,
        strings: strings,
        random: random,
      );
    case LanguageSkillType.reading:
    case LanguageSkillType.sentenceStructure:
    case LanguageSkillType.punctuation:
    case LanguageSkillType.caseUsage:
      // These need their original text and rubric. A base word alone cannot
      // tell us which reading, syntax, punctuation or case task was asked.
      // An arbitrary cloze can have several reasonable answers even when
      // the dictionary labels only one of them as its example headword.
      return null;
  }
}

ReviewChallenge? _articleChallenge(
  GermanWord word,
  SriLanguageData sriData, {
  required S strings,
  required Random random,
}) {
  final correct = word.article!.toLowerCase();
  final wrong = ['der', 'die', 'das'].where((a) => a != correct).toList();
  final options = [correct, ...wrong]..shuffle(random);
  final prompt = strings.articleChallengePrompt(word.word);
  return ReviewChallenge(
    word: word,
    sriData: sriData,
    type: ReviewChallengeType.article,
    assessedSkill: LanguageSkillType.articleSelection,
    prompt: prompt,
    options: options,
    correctIndex: options.indexOf(correct),
  );
}

ReviewChallenge? _spellingChallenge(
  GermanWord word,
  SriLanguageData sriData,
  Set<String> validWords, {
  required S strings,
  required bool isGerman,
  required int optionCount,
  required Random random,
}) {
  final displayWord = normWord(word.word);
  if (displayWord.contains(' ')) return null;

  final rawErrors = isGerman
      ? (word.commonMistakes ?? <String>[])
      : (word.apiEnrichment?.commonLearnerErrors ?? <String>[]);
  // A set, and deduplicated case-insensitively: the packs list the same
  // misspelling twice for some words, and two spellings can normalise to one.
  // Collected into a list without that, the review offered the same wrong
  // spelling twice and one of the two was keyed wrong whichever the learner
  // picked. The nightly sweep found it twice in 22,000 items, which is why
  // the per-push check at forty never did.
  final seen = <String>{displayWord.toLowerCase()};
  final errors = <String>[];
  for (final candidate in parseErrors(rawErrors).map(normWord)) {
    if (errors.length >= optionCount - 1) break;
    final lower = candidate.toLowerCase();
    if (candidate.isEmpty || candidate.contains(' ')) continue;
    if (!seen.add(lower)) continue;
    if (validWords.contains(lower)) continue;
    // The same test Spelling Spotter applies: the English errors come from a
    // typo corpus, and "base" arrives with "pare" and "pase" among its
    // misspellings. This is a spelling question too.
    if (!isDistractorPlausible(
      candidate,
      displayWord,
      validWords: validWords,
    )) {
      continue;
    }
    errors.add(candidate);
  }

  if (errors.isEmpty) return null;

  final options = [displayWord, ...errors]..shuffle(random);
  // "Partizip Präsens des Verbs wüten" is a parse, not a meaning to spell to.
  final definition =
      word.learnerDefinitions.where(isUsableDefinition).firstOrNull;
  final prompt = definition != null
      ? strings.spellingForDefinition(definition)
      : strings.spellingSpotterPrompt;
  return ReviewChallenge(
    word: word,
    sriData: sriData,
    type: ReviewChallengeType.spelling,
    assessedSkill: LanguageSkillType.spelling,
    prompt: prompt,
    options: options,
    correctIndex: options.indexOf(displayWord),
  );
}

ReviewChallenge? _definitionChallenge(
  GermanWord word,
  SriLanguageData sriData,
  List<GermanWord> allWords, {
  required bool isGerman,
  required int optionCount,
  required Random random,
}) {
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
    assessedSkill: LanguageSkillType.vocabulary,
    prompt: '"${quiz.definition}"',
    options: quiz.options,
    correctIndex: quiz.correctIndex,
  );
}

ReviewChallenge? _wordTypeChallenge(
  GermanWord word,
  SriLanguageData item,
  Iterable<GermanWord> catalogue, {
  required S strings,
  required int optionCount,
  required Random random,
}) {
  final labels = <GermanWordType, String>{
    GermanWordType.substantiv: strings.wordTypeNoun,
    GermanWordType.verb: strings.wordTypeVerb,
    GermanWordType.adjektiv: strings.wordTypeAdjective,
    GermanWordType.adverb: strings.wordTypeAdverb,
    GermanWordType.pronomen: strings.wordTypePronoun,
  };
  final correct = labels[word.wordType];
  if (correct == null || !word.isHeadword || !classIsSettled(word)) return null;
  if (catalogue.any(
    (other) =>
        other.word.toLowerCase() == word.word.toLowerCase() &&
        other.wordType != word.wordType,
  )) {
    return null;
  }
  final distractors = labels.values.where((label) => label != correct).toList()
    ..shuffle(random);
  final options = [correct, ...distractors.take(optionCount - 1)]
    ..shuffle(random);
  return ReviewChallenge(
    word: word,
    sriData: item,
    type: ReviewChallengeType.wordType,
    assessedSkill: LanguageSkillType.wordType,
    prompt: '${strings.wordClassFlashPrompt}\n${word.word}',
    options: options,
    correctIndex: options.indexOf(correct),
  );
}

ReviewChallenge? _conjugationChallenge(
  GermanWord word,
  SriLanguageData item, {
  required S strings,
  required int optionCount,
  required Random random,
}) {
  if (!isConjugatableVerb(word)) return null;
  final tense = item.metadata['tense'];
  if (tense != null && tense != 'Präsens' && tense != 'present') return null;
  final forms = getPraesensForWord(word)!;
  final requestedPronoun =
      item.identity.additionalInfo ?? item.metadata['pronoun'];
  final pronouns = conjugationPronouns
      .where(
        (pronoun) =>
            (requestedPronoun == null || requestedPronoun == pronoun) &&
            forms[pronoun] != null &&
            forms[pronoun]!.toLowerCase() != word.word.toLowerCase(),
      )
      .toList()
    ..shuffle(random);
  if (pronouns.isEmpty) return null;
  final pronoun = pronouns.first;
  final correct = forms[pronoun]!;
  // Other persons of this verb are meaningful alternatives. Do not invent
  // malformed conjugations or select a different requested pronoun.
  final distractors = forms.values
      .where((form) => form.toLowerCase() != correct.toLowerCase())
      .toSet()
      .toList()
    ..shuffle(random);
  if (distractors.isEmpty) return null;
  final options = [correct, ...distractors.take(optionCount - 1)]
    ..shuffle(random);
  return ReviewChallenge(
    word: word,
    sriData: item,
    type: ReviewChallengeType.conjugation,
    assessedSkill: LanguageSkillType.verbConjugation,
    prompt: '${strings.conjugationDrillPrompt}\n${word.word}: $pronoun ___',
    options: options,
    correctIndex: options.indexOf(correct),
  );
}

String? _pluralOf(GermanWord word) {
  if (word.wordType != GermanWordType.substantiv || word.nurImPlural)
    return null;
  final raw = word.plural ?? word.apiEnrichment?.inflectionsPattern?['plural'];
  if (raw is! String) return null;
  final plural = raw.trim();
  // Multiple variants require a multi-answer rubric. Do not pretend one
  // spelling is the unique answer here.
  if (!RegExp(r'^[\p{L}][\p{L}\-]*$', unicode: true).hasMatch(plural))
    return null;
  return plural;
}

ReviewChallenge? _pluralChallenge(
  GermanWord word,
  SriLanguageData item,
  List<GermanWord> allWords, {
  required S strings,
  required int optionCount,
  required Random random,
}) {
  final correct = _pluralOf(word);
  if (correct == null) return null;
  final distractors = allWords
      .map(_pluralOf)
      .whereType<String>()
      .where((form) => form.toLowerCase() != correct.toLowerCase())
      .toSet()
      .toList()
    ..shuffle(random);
  if (distractors.isEmpty) return null;
  final options = [correct, ...distractors.take(optionCount - 1)]
    ..shuffle(random);
  return ReviewChallenge(
    word: word,
    sriData: item,
    type: ReviewChallengeType.plural,
    assessedSkill: LanguageSkillType.pluralForm,
    prompt: '${strings.statsPlural}\n${word.displayName} → ___',
    options: options,
    correctIndex: options.indexOf(correct),
  );
}

List<String> _reviewTexts(GermanWord word, SriLanguageData item) {
  final grade = item.metadata['gradeLevel'] ?? word.gradeLevel;
  return [
    ...?word.apiEnrichment?.gradeExamples?['$grade'],
    ...word.exampleSentences,
    ...word.examples.map((example) => example.text).whereType<String>(),
  ];
}

ReviewChallenge? _capitalizationChallenge(
  GermanWord word,
  SriLanguageData item, {
  required S strings,
  required Random random,
}) {
  for (final sentence in _reviewTexts(word, item)) {
    if (!sentenceSuitsAChild(sentence) || !looksLikeAWholeSentence(sentence)) {
      continue;
    }
    final gap = tryBlank(sentence, word.word);
    if (gap == null) continue;
    final lower = gap.matchedForm.toLowerCase();
    if (lower.isEmpty) continue;
    final upper = '${lower[0].toUpperCase()}${lower.substring(1)}';
    if (lower == upper || ![lower, upper].contains(gap.matchedForm)) continue;
    // The actual sentence supplies the correct case; a second visible copy
    // would reveal it rather than testing the learner's choice.
    if (tryBlank('${gap.before} ${gap.after}', word.word) != null) continue;
    final options = [lower, upper]..shuffle(random);
    return ReviewChallenge(
      word: word,
      sriData: item,
      type: ReviewChallengeType.capitalization,
      assessedSkill: LanguageSkillType.capitalization,
      prompt: '${strings.statsCapitalization}\n${gap.before}___${gap.after}',
      options: options,
      correctIndex: options.indexOf(gap.matchedForm),
    );
  }
  return null;
}
