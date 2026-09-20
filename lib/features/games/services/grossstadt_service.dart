// lib/features/games/services/grossstadt_service.dart
//
// Capitalisation item construction for Großstadt, extracted from the screen so
// it can be generated and reviewed without running the game.
// See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import 'conjugation_drill_service.dart' show getPraesensForWord;
import 'grossstadt_possessive.dart';
import 'verbtrenner_service.dart' show hasSeparablePrefix;

class CapitalizationItem {
  final String prefix; // Text before the target word
  final String target; // The word to judge
  final String suffix; // Text after the target word
  final bool shouldBeCapitalized;
  final String rule;
  final String explanation;
  final int difficulty;
  final String wordId; // For SRI tracking
  final String lemma; // The base form for SRI

  CapitalizationItem({
    this.prefix = '',
    required this.target,
    this.suffix = '',
    required this.shouldBeCapitalized,
    required this.rule,
    required this.explanation,
    required this.difficulty,
    required this.wordId,
    required this.lemma,
  });
}

bool isInfinitive(String verb) {
  final lower = verb.toLowerCase();
  return lower.endsWith('en') || lower.endsWith('ern') || lower.endsWith('eln');
}

/// The present-tense form of [word] for [person], or null when the pack does
/// not carry one.
///
/// This used to match Wiktionary tags itself and fall back to regular
/// conjugation. The German pack tags its present forms bare — "present",
/// three of them, in ich/du/er order — so the matcher never fired and every
/// German verb went through the fallback: "du lesst", "du sprechst", "du
/// essst", and for separable verbs "du abbiegst" where German says "du biegst
/// ab". Where a tag did match, it was sometimes the imperative: "du flieg
/// ab!".
///
/// The conjugation drill already reads that convention correctly, so this
/// asks it. Nothing is invented: a verb the pack has no forms for is not
/// asked about.
String? conjugatedForm(GermanWord word, String person) {
  final praesens = getPraesensForWord(word);
  if (praesens == null) return null;
  switch (person) {
    case 'ich':
    case 'du':
      return praesens[person];
    case 'wir':
      // The flat list carries ich/du/er only. First-person plural is the
      // infinitive — but only for a verb that does not separate: "wir
      // brechen ab", not "wir abbrechen".
      return hasSeparablePrefix(word.lemma) ? null : word.lemma.toLowerCase();
    default:
      return null;
  }
}

List<CapitalizationItem> verbVariants(GermanWord word, {Random? rng}) {
  final random = rng ?? Random();
  final items = <CapitalizationItem>[];

  // Skip if lemma is not an infinitive
  if (!isInfinitive(word.lemma)) {
    return items;
  }

  final infinitive = word.lemma.toLowerCase();

  // 1. Nominalization (Groß) -> "DAS LAUFEN"
  final articles = ['DAS', 'BEIM', 'ZUM'];
  final article = articles[random.nextInt(articles.length)];

  items.add(CapitalizationItem(
    prefix: '$article ',
    target: infinitive,
    shouldBeCapitalized: true,
    rule: 'nominalized_verb',
    explanation: 'Nomen-Signal "$article" → Großschreibung',
    difficulty: 2,
    wordId: word.id,
    lemma: word.lemma,
  ));

  // 2. Conjugated (Klein) -> "ICH LAUFE"
  final pronouns = ['ICH', 'DU', 'WIR'];
  final pronoun = pronouns[random.nextInt(pronouns.length)];
  final conjugated = conjugatedForm(word, pronoun.toLowerCase());

  if (conjugated != null) {
    items.add(CapitalizationItem(
      prefix: '$pronoun ',
      target: conjugated,
      shouldBeCapitalized: false,
      rule: 'conjugated_verb',
      explanation: 'Verben im Satz → Kleinschreibung',
      difficulty: 1,
      wordId: word.id,
      lemma: word.lemma,
    ));
  } else {}

  // 3. Modal + Infinitive (Klein) -> "KANN LAUFEN"
  final modals = ['KANN', 'MUSS', 'WILL', 'DARF'];
  final modal = modals[random.nextInt(modals.length)];

  items.add(CapitalizationItem(
    prefix: '$modal ',
    target: infinitive,
    shouldBeCapitalized: false,
    rule: 'infinitive_verb',
    explanation: 'Verben (Infinitiv) → Kleinschreibung',
    difficulty: 1,
    wordId: word.id,
    lemma: word.lemma,
  ));

  return items;
}

List<CapitalizationItem> adjectiveVariants(GermanWord word, {Random? rng}) {
  final random = rng ?? Random();
  final items = <CapitalizationItem>[];

  // Get clean base form
  final adjBase = _getAdjectiveBase(word.lemma);

  // 1. Nominalization (Groß) -> "ETWAS GUTES" — only when we can form the
  //    nominalised word correctly; otherwise skip this variant.
  final nominalizedForm = _nominalizeAdjective(word.lemma);
  if (nominalizedForm != null) {
    final indefinites = ['ETWAS', 'NICHTS', 'VIEL', 'WENIG'];
    final indefinite = indefinites[random.nextInt(indefinites.length)];
    items.add(CapitalizationItem(
      prefix: '$indefinite ',
      target: nominalizedForm,
      shouldBeCapitalized: true,
      rule: 'nominalized_adjective',
      explanation: 'Nach "$indefinite" → Großschreibung',
      difficulty: 3,
      wordId: word.id,
      lemma: adjBase, // Use clean base for SRI
    ));
  }

  // 2. Predicative (Klein) -> "IST GUT"
  final copulas = ['IST', 'WAR', 'SIND'];
  final copula = copulas[random.nextInt(copulas.length)];

  items.add(CapitalizationItem(
    prefix: '$copula ',
    target: adjBase, // Use clean base
    shouldBeCapitalized: false,
    rule: 'predicative_adjective',
    explanation: 'Adjektive (Wie ist es?) → Kleinschreibung',
    difficulty: 1,
    wordId: word.id,
    lemma: adjBase, // Use clean base for SRI
  ));

  return items;
}

List<CapitalizationItem> nounVariants(GermanWord word, {Random? rng}) {
  final random = rng ?? Random();
  final items = <CapitalizationItem>[];
  final noun = word.word;

  // Get proper article
  String article = (word.article ?? 'das').toUpperCase();
  if (!['DER', 'DIE', 'DAS'].contains(article.toUpperCase())) {
    article = 'DAS'; // Default fallback
  }

  // 1. Standard Noun (Groß) -> "DER TISCH"
  items.add(CapitalizationItem(
    prefix: '$article ',
    target: noun,
    shouldBeCapitalized: true,
    rule: 'noun_standard',
    explanation: 'Nomen (Namen für Dinge) → Großschreibung',
    difficulty: 1,
    wordId: word.id,
    lemma: word.lemma,
  ));

  // 2. Possessive Context (Groß) -> "MEIN TISCH" / "MEINE STIRN"
  final possessiveBases = ['MEIN', 'DEIN', 'UNSER', 'KEIN'];
  final basePoss = possessiveBases[random.nextInt(possessiveBases.length)];
  final poss = _getPossessiveArticle(basePoss, article);

  items.add(CapitalizationItem(
    prefix: '$poss ',
    target: noun,
    shouldBeCapitalized: true,
    rule: 'noun_possessive',
    explanation: 'Nach "$poss" → Großschreibung',
    difficulty: 1,
    wordId: word.id,
    lemma: word.lemma,
  ));

  return items;
}

String _getAdjectiveBase(String adjective) {
  // The lemma stored for an adjective IS already the dictionary base form
  // (gut, dunkel, sauer), so stripping "inflectional" endings mangled real
  // stems (sauer→sau, dunkel→dunk). Just normalise case.
  return adjective.toLowerCase();
}

String? _nominalizeAdjective(String adjective) {
  final base = adjective.toLowerCase();
  if (base.length < 3) return null;
  if (base.endsWith('e') ||
      base.endsWith('el') ||
      base.endsWith('er') ||
      base.endsWith('en')) {
    return null;
  }
  return '${base}es';
}

String _getPossessiveArticle(String baseArticle, String nounArticle) {
  final result = getPossessiveArticle(baseArticle, nounArticle);
  return result;
}

/// Every item the three word classes yield, in queue order.
List<CapitalizationItem> buildCapitalizationItems({
  required List<GermanWord> verbs,
  required List<GermanWord> adjectives,
  required List<GermanWord> nouns,
  Random? rng,
}) =>
    [
      for (final word in verbs) ...verbVariants(word, rng: rng),
      for (final word in adjectives) ...adjectiveVariants(word, rng: rng),
      for (final word in nouns) ...nounVariants(word, rng: rng),
    ];
