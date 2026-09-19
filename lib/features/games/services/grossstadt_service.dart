// lib/features/games/services/grossstadt_service.dart
//
// Capitalisation item construction for Großstadt, extracted from the screen so
// it can be generated and reviewed without running the game.
// See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import 'grossstadt_possessive.dart';

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

String? conjugatedForm(GermanWord word, String person) {
  // Try API data first
  if (word.wiktionaryInflections.isNotEmpty) {
    for (final inflection in word.wiktionaryInflections) {
      final formText = inflection['form_text'] as String?;
      final tagsRaw = inflection['tags'];

      if (formText == null || tagsRaw == null) continue;

      // Handle both String and List<dynamic> for tags
      String tagString;
      if (tagsRaw is String) {
        tagString = tagsRaw.toLowerCase();
      } else if (tagsRaw is List) {
        tagString = tagsRaw.join('|').toLowerCase();
      } else {
        continue;
      }

      // Must be present tense and match person
      if (!tagString.contains('present') && !tagString.contains('pres'))
        continue;
      if (tagString.contains('past') || tagString.contains('participle'))
        continue;

      bool matches = false;
      if (person == 'ich' &&
          tagString.contains('first-person') &&
          tagString.contains('singular')) {
        matches = true;
      } else if (person == 'du' &&
          tagString.contains('second-person') &&
          tagString.contains('singular')) {
        matches = true;
      } else if (person == 'wir' &&
          tagString.contains('first-person') &&
          tagString.contains('plural')) {
        matches = true;
      }

      if (matches) {
        return formText;
      }
    }
  }

  // Fallback: Basic regular verb conjugation
  final lemma = word.lemma.toLowerCase();
  if (lemma.endsWith('en')) {
    final stem = lemma.substring(0, lemma.length - 2);
    String result;
    if (person == 'ich') {
      result = '${stem}e';
    } else if (person == 'du') {
      result = '${stem}st';
    } else if (person == 'wir') {
      result = lemma; // Same as infinitive
    } else {
      return null;
    }
    return result;
  }

  return null;
}

List<CapitalizationItem> verbVariants(GermanWord word) {
  final items = <CapitalizationItem>[];

  // Skip if lemma is not an infinitive
  if (!isInfinitive(word.lemma)) {
    return items;
  }

  final infinitive = word.lemma.toLowerCase();

  // 1. Nominalization (Groß) -> "DAS LAUFEN"
  final articles = ['DAS', 'BEIM', 'ZUM'];
  final article = articles[Random().nextInt(articles.length)];

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
  final pronoun = pronouns[Random().nextInt(pronouns.length)];
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
  final modal = modals[Random().nextInt(modals.length)];

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

List<CapitalizationItem> adjectiveVariants(GermanWord word) {
  final items = <CapitalizationItem>[];

  // Get clean base form
  final adjBase = _getAdjectiveBase(word.lemma);

  // 1. Nominalization (Groß) -> "ETWAS GUTES" — only when we can form the
  //    nominalised word correctly; otherwise skip this variant.
  final nominalizedForm = _nominalizeAdjective(word.lemma);
  if (nominalizedForm != null) {
    final indefinites = ['ETWAS', 'NICHTS', 'VIEL', 'WENIG'];
    final indefinite = indefinites[Random().nextInt(indefinites.length)];
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
  final copula = copulas[Random().nextInt(copulas.length)];

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

List<CapitalizationItem> nounVariants(GermanWord word) {
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
  final basePoss = possessiveBases[Random().nextInt(possessiveBases.length)];
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
}) =>
    [
      for (final word in verbs) ...verbVariants(word),
      for (final word in adjectives) ...adjectiveVariants(word),
      for (final word in nouns) ...nounVariants(word),
    ];
