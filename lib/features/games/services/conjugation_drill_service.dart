// lib/features/games/services/conjugation_drill_service.dart
//
// Pure helpers for ConjugationDrillGame, extracted for unit testing.

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';

// The 6 Präsens pronouns in canonical display order.
const conjugationPronouns = [
  'ich',
  'du',
  'er/sie/es',
  'wir',
  'ihr',
  'sie',
];

// Subset available from the flat Wiktionary format (positional: ich/du/er).
const _wiktionaryPresentPronouns = ['ich', 'du', 'er/sie/es'];

/// Extract Präsens from the structured inflections_pattern format.
/// Keys: canonical pronoun strings (e.g. 'ich', 'er/sie/es', 'sie/Sie').
Map<String, String>? extractPraesens(Map<String, dynamic>? inflectionData) {
  if (inflectionData == null) return null;
  final conj = inflectionData['conjugation'];
  if (conj == null || conj is! Map) return null;
  final pres = (conj as Map<String, dynamic>)['Präsens'];
  if (pres == null || pres is! Map) return null;
  final result = <String, String>{};
  for (final e in (pres as Map<String, dynamic>).entries) {
    if (e.value is String && (e.value as String).isNotEmpty) {
      result[e.key] = e.value as String;
    }
  }
  return result.isEmpty ? null : result;
}

/// Extract Präsens from the flat Wiktionary tagged-forms list.
///
/// German Wiktionary always lists present forms in table order (ich/du/er/sie/es),
/// tagged exactly `"present"` (no additional tags).  The first three such entries
/// map positionally to ich → du → er/sie/es.
Map<String, String>? extractPraesensFromWiktionary(
    List<Map<String, dynamic>> inflections) {
  final exactPresent = inflections
      .where((f) => f['tags'] == 'present')
      .map((f) => (f['form_text'] as String?)?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
  // Positional mapping only holds for a full ich/du/er row. An impersonal
  // verb lists one form — "geschieht" — and reading it positionally asked
  // "geschehen: ich ___" and keyed the third-person form.
  if (exactPresent.length < _wiktionaryPresentPronouns.length) return null;
  final result = <String, String>{};
  for (var i = 0;
      i < exactPresent.length && i < _wiktionaryPresentPronouns.length;
      i++) {
    result[_wiktionaryPresentPronouns[i]] = exactPresent[i];
  }
  return result.isEmpty ? null : result;
}

/// Returns the best available Präsens table for [w]:
/// structured inflections_pattern first, then flat wiktionaryInflections.
Map<String, String>? getPraesensForWord(GermanWord w) =>
    extractPraesens(w.inflectionData) ??
    extractPraesensFromWiktionary(w.wiktionaryInflections);

/// True when a word is a DE verb with at least one usable Präsens form.
bool isConjugatableVerb(GermanWord w) {
  if (w.wordType != GermanWordType.verb) return false;
  if (w.isProperNoun) return false;
  if (w.word.contains(' ')) return false;
  final pres = getPraesensForWord(w);
  return pres != null && pres.isNotEmpty;
}

/// Build distractors for a given pronoun and correct form from a pool of
/// candidate forms (typically all forms for the same pronoun across verbs).
/// Returns up to [count] distinct strings that are not [correct] and not
/// equal to [verbInfinitive].
List<String> pickDistractors(
  String pronoun,
  String correct,
  String verbInfinitive,
  List<String> candidateForms, {
  int count = 3,
}) {
  final seen = <String>{correct, verbInfinitive};
  final result = <String>[];
  for (final form in candidateForms) {
    if (result.length >= count) break;
    if (!seen.contains(form)) {
      seen.add(form);
      result.add(form);
    }
  }
  return result;
}
