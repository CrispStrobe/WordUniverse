// Sentence Completion asks for a word using a meaning clue and a source
// sentence. It practises vocabulary in context; it does not assess sentence
// construction. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

class SentenceChallenge {
  final GermanWord word;
  final String source;
  final String before;
  final String after;

  /// An unchanged, learner-readable gloss from this headword. The UI says the
  /// word *can* have this meaning: the pack does not link examples to senses.
  /// A context such as "The town has a special ___" alone is underdetermined.
  final String meaningCue;

  /// Exact source span, including its inflection and capitalization. The
  /// accepted option must restore [source], not substitute the dictionary form.
  final String matchedForm;
  final String correctOption;
  final List<String> options;
  final int correctIndex;

  const SentenceChallenge({
    required this.word,
    required this.source,
    required this.before,
    required this.after,
    required this.meaningCue,
    required this.matchedForm,
    required this.correctOption,
    required this.options,
    required this.correctIndex,
  });

  LanguageSkillType get skillType => LanguageSkillType.vocabulary;
}

const _contentTypes = {
  GermanWordType.substantiv,
  GermanWordType.verb,
  GermanWordType.adjektiv,
};

bool hasGradeExamples(GermanWord w, int gradeIndex) {
  final ge = w.apiEnrichment?.gradeExamples;
  if (ge == null) return false;
  final sents = ge['$gradeIndex'] ?? ge.values.firstOrNull;
  return sents != null && sents.isNotEmpty;
}

SentenceChallenge? buildSentenceChallenge({
  required GermanWord word,
  required int gradeIndex,
  required List<GermanWord> pool,
  bool isGerman = true,
  int optionCount = 4,
  Random? rng,
}) {
  if (optionCount < 2 || !_usableAsPrompt(word)) return null;
  final random = rng ?? Random();
  final ge = word.apiEnrichment?.gradeExamples;
  final sents = ge?['$gradeIndex'] ?? ge?.values.firstOrNull ?? const [];
  if (sents.isEmpty) return null;

  final forms = _declaredForms(word, isGerman: isGerman);
  final meaningCue = word.learnerDefinitions.first.trim();
  // Do not switch to a different dictionary sense to avoid a giveaway. If the
  // primary clue names the answer, leave this item for another exercise.
  if (_cueNamesAnswer(meaningCue, forms)) return null;

  final shuffledSents = List<String>.from(sents)..shuffle(random);
  for (final sent in shuffledSents) {
    if (!sentenceSuitsAChild(sent) || !looksLikeAWholeSentence(sent)) continue;
    final result =
        blankWord(sent, word.word, forms: forms.map((form) => form.text));
    if (result == null) continue;
    final (before, after) = result;
    final matchedForm =
        sent.substring(before.length, sent.length - after.length);
    if (_unsupportedAdjectiveContext(word, matchedForm, before, after,
        isGerman: isGerman)) continue;
    // Repeated occurrences, including known inflections, answer the gap.
    if (blankWord('$before $after', word.word,
            forms: forms.map((form) => form.text)) !=
        null) {
      continue;
    }

    final distractors = _pickDistractors(
      target: word,
      targetForms: forms,
      correctOption: matchedForm,
      meaningCue: meaningCue,
      before: before,
      after: after,
      pool: pool,
      gradeIndex: gradeIndex,
      optionCount: optionCount,
      isGerman: isGerman,
      random: random,
    );
    if (distractors.isEmpty) continue;
    final options = [matchedForm, ...distractors]..shuffle(random);

    return SentenceChallenge(
      word: word,
      source: sent,
      before: before,
      after: after,
      meaningCue: meaningCue,
      matchedForm: matchedForm,
      correctOption: matchedForm,
      options: options,
      correctIndex: options.indexOf(matchedForm),
    );
  }
  return null;
}

/// Cut an exact whole token from [sentence]. [forms] must come from explicit
/// inflection data. A short shared prefix is not evidence of an inflection:
/// "Hund" must never blank "Hundert", nor "arm" the word "Armee".
///
/// Unicode boundaries preserve umlauts and accented letters. Prefix, suffix,
/// and punctuation remain exactly as written in the source.
(String, String)? blankWord(String sentence, String word,
    {Iterable<String> forms = const []}) {
  if (word.isEmpty) return null;
  for (final form in <String>{word, ...forms}) {
    if (!_singleWord.hasMatch(form)) continue;
    final pattern = RegExp(
      r'(^|[^\p{L}\p{M}\p{N}_\p{Pd}])(' +
          RegExp.escape(form) +
          r')(?=$|[^\p{L}\p{M}\p{N}_\p{Pd}])',
      caseSensitive: false,
      unicode: true,
    );
    final match = pattern.firstMatch(sentence);
    if (match == null) continue;
    final start = match.start + match.group(1)!.length;
    return (sentence.substring(0, start), sentence.substring(match.end));
  }
  return null;
}

final _singleWord =
    RegExp(r"^[\p{L}\p{M}]+(?:[-'’][\p{L}\p{M}]+)*$", unicode: true);
final _followingCapitalizedWord =
    RegExp(r'^\s+\p{Lu}[\p{L}\p{M}]*', unicode: true);

/// The verified pack itself contains "Ein sonnig Tag ..." and "Ich mag
/// sonnig Tage". We cannot repair agreement from a lemma and nearby text.
/// Conservatively skip a bare German adjective directly before a noun; this
/// can also skip valid indeclinable adjectives. It is a narrow rejection rule,
/// not a claim that every remaining source sentence is grammatically correct.
bool _unsupportedAdjectiveContext(
    GermanWord word, String matchedForm, String before, String after,
    {required bool isGerman}) {
  if (word.wordType != GermanWordType.adjektiv) return false;
  if (isGerman) {
    return matchedForm.toLowerCase() == word.word.toLowerCase() &&
        _followingCapitalizedWord.hasMatch(after);
  }
  // The English adjective entry `accomplished` ships finite-verb examples:
  // "They accomplished their goal." Do not credit the adjective entry for
  // that use. Restrict this guard to a sentence-initial personal pronoun;
  // a question such as "Is she happy?" is a valid adjective context.
  return RegExp(r'(^|[.!?]\s+)(I|you|he|she|it|we|they)\s+$',
          caseSensitive: false)
      .hasMatch(before);
}

class _DeclaredForm {
  final String text;
  final String signature;
  const _DeclaredForm(this.text, this.signature);
}

const _grammarTags = {
  'singular',
  'plural',
  'nominative',
  'accusative',
  'dative',
  'genitive',
  'masculine',
  'feminine',
  'neuter',
  'positive',
  'comparative',
  'superlative',
  'strong',
  'weak',
  'mixed',
  'present',
  'past',
  'perfect',
  'future',
  'first-person',
  'second-person',
  'third-person',
  'indicative',
  'subjunctive',
  'subjunctive-i',
  'subjunctive-ii',
  'imperative',
  'infinitive',
  'participle',
  'participle-1',
  'participle-2',
  'active',
  'passive',
};
final _unsupportedFormTag = RegExp(
    r'auxiliary|abbreviation|diminutive|archaic|obsolete|regional|dialect');
final _articlePrefix = RegExp(
    r'^(?:der|die|das|den|dem|des|\((?:der|die|das|den|dem|des)\))\s+',
    caseSensitive: false);

List<_DeclaredForm> _declaredForms(GermanWord word, {required bool isGerman}) {
  final forms = <_DeclaredForm>[_DeclaredForm(word.word, '')];
  final plural = word.plural;
  if (plural != null && _singleWord.hasMatch(plural)) {
    forms.add(_DeclaredForm(plural, 'plural'));
  }
  for (final entry in [
    ...?word.apiEnrichment?.inflections,
    ...word.wiktionaryInflections,
  ]) {
    final rawText = entry['form_text'];
    if (rawText is! String) continue;
    final rawTags = entry['tags'];
    final tagText = rawTags is List ? rawTags.join(',') : '$rawTags';
    if (_unsupportedFormTag.hasMatch(tagText.toLowerCase())) continue;
    var text = rawText.trim();
    if (isGerman && word.wordType == GermanWordType.substantiv) {
      // Leave the article already present in the source sentence untouched.
      text = text.replaceFirst(_articlePrefix, '');
    }
    // Multi-word forms, auxiliary phrases, and unlabelled free-text `forms`
    // fields do not establish one token that can safely replace this gap.
    if (!_singleWord.hasMatch(text)) continue;
    final tags = tagText
        .toLowerCase()
        .split(RegExp(r'[,;]\s*'))
        .where(_grammarTags.contains)
        .toSet()
        .toList()
      ..sort();
    forms.add(_DeclaredForm(text, tags.join(',')));
  }
  return forms;
}

/// `sufficient` is stored as a noun but its dictionary analysis says
/// determiner. A contradictory entry cannot supply either a prompt or a
/// same-class option. Missing analysis alone does not invent a contradiction.
bool _partOfSpeechMatches(GermanWord word) {
  final pos = word.apiEnrichment?.primaryPos?.trim().toLowerCase();
  if (pos == null || pos.isEmpty) return true;
  return switch (word.wordType) {
    GermanWordType.substantiv => {'noun', 'substantiv'}.contains(pos),
    GermanWordType.verb => pos == 'verb',
    GermanWordType.adjektiv => {'adjective', 'adjektiv', 'adj'}.contains(pos),
    _ => false,
  };
}

/// A source token cannot be cut out of a compound, but a clue such as
/// "bulb-shaped" still writes the answer `bulb` in front of the learner.
/// Treat hyphens as boundaries here without loosening source-span matching.
bool _cueNamesAnswer(String cue, List<_DeclaredForm> forms) =>
    forms.any((form) => RegExp(
            r'(^|[^\p{L}\p{M}\p{N}_])' +
                RegExp.escape(form.text) +
                r'(?=$|[^\p{L}\p{M}\p{N}_])',
            unicode: true,
            caseSensitive: false)
        .hasMatch(cue));

bool _usableAsOption(GermanWord word) =>
    _contentTypes.contains(word.wordType) &&
    // The English pack types "and" and "don't" as nouns, so the content-type
    // test passed them, and "Dogs ___ bark loud" took don't and can alike.
    !isClosedClassEntry(word) &&
    _partOfSpeechMatches(word) &&
    word.isHeadword &&
    !word.isProperNoun &&
    isPresentableVocabularyEntry(word) &&
    !namesSomething(word) &&
    (!word.isHydrated || !_hasUnusableGloss(word));

bool _usableAsPrompt(GermanWord word) =>
    _usableAsOption(word) && _hasUsableGloss(word);

bool _hasUnusableGloss(GermanWord word) {
  final definition = word.learnerDefinitions.firstOrNull;
  return definition != null && !isUsableDefinition(definition);
}

bool _hasUsableGloss(GermanWord word) {
  final definition = word.learnerDefinitions.firstOrNull;
  return definition != null && isUsableDefinition(definition);
}

String _normalizedMeaning(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

List<String> _pickDistractors({
  required GermanWord target,
  required List<_DeclaredForm> targetForms,
  required String correctOption,
  required String meaningCue,
  required String before,
  required String after,
  required List<GermanWord> pool,
  required int gradeIndex,
  required int optionCount,
  required bool isGerman,
  required Random random,
}) {
  final targetLemma = target.word.toLowerCase();
  final targetSynonyms = target.everySynonym;
  final inflected = correctOption.toLowerCase() != targetLemma;
  final signatures = targetForms
      .where((form) =>
          form.text.toLowerCase() == correctOption.toLowerCase() &&
          form.signature.isNotEmpty)
      .map((form) => form.signature)
      .toSet();
  if (inflected && signatures.isEmpty) return [];

  final sameType = pool
      .where((word) =>
          word.id != target.id &&
          word.wordType == target.wordType &&
          _usableAsOption(word))
      .toList();
  final sameGrade = sameType.where((w) => w.gradeLevel == gradeIndex).toList()
    ..shuffle(random);
  final otherGrades = sameType.where((w) => w.gradeLevel != gradeIndex).toList()
    ..shuffle(random);
  final distractors = <String>[];
  final used = {correctOption.toLowerCase(), targetLemma};
  final initial =
      before.trim().isEmpty || RegExp(r'[.!?]["”’)]?\s*$').hasMatch(before);

  for (final word in [...sameGrade, ...otherGrades]) {
    final lemma = word.word.toLowerCase();
    if (lemma == targetLemma ||
        targetSynonyms.contains(lemma) ||
        word.everySynonym.contains(targetLemma)) continue;
    // Same meaning under another headword is not a wrong answer, even when
    // the pack forgot to list the pair as synonyms.
    if (word.learnerDefinitions.any((definition) =>
        _normalizedMeaning(definition) == _normalizedMeaning(meaningCue))) {
      continue;
    }
    if (blankWord('$before $after $meaningCue', word.word) != null) continue;

    var option = word.word;
    if (inflected) {
      final supported = _declaredForms(word, isGerman: isGerman)
          .where((form) => signatures.contains(form.signature))
          .map((form) => form.text)
          .toSet();
      // Tags such as just `present` may name several person forms. Do not
      // guess which one fits the source. Use another candidate or skip it.
      if (supported.length != 1) continue;
      option = supported.single;
    }
    if (initial) option = option[0].toUpperCase() + option.substring(1);
    if (!used.add(option.toLowerCase())) continue;
    distractors.add(option);
    if (distractors.length >= optionCount - 1) break;
  }
  return distractors;
}

List<SentenceChallenge> buildSentenceChallenges({
  required List<GermanWord> pool,
  required int gradeIndex,
  bool isGerman = true,
  int maxChallenges = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  // Keep prompt and option eligibility separate: a missing meaning cannot
  // supply a clue, although its spelling may still be a useful distractor.
  final challenges = <SentenceChallenge>[];
  for (final word in pool.where(_usableAsPrompt)) {
    if (challenges.length >= maxChallenges) break;
    final challenge = buildSentenceChallenge(
      word: word,
      gradeIndex: gradeIndex,
      pool: pool,
      isGerman: isGerman,
      optionCount: optionCount,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}
