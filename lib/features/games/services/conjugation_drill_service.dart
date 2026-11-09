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
/// The forms tagged exactly `"present"` come in table order, ich → du →
/// er/sie/es, but a verb with variants lists every variant in turn:
/// backen gives [backe, bäckst, backst, bäckt, backt] and abmachen
/// [mache ab, mach ab, machst ab, macht ab]. Read by position, the drill
/// keyed "er backst" and "er machst ab". So each person is found by its
/// ending: du is the first form in -st, er/sie/es the first after it in -t
/// (not -st, unless nothing else is there: er liest, er ist), ich the first
/// form before du, preferring one in -e.
Map<String, String>? extractPraesensFromWiktionary(
    List<Map<String, dynamic>> inflections) {
  final forms = inflections
      .where((f) => f['tags'] == 'present')
      .map((f) => (f['form_text'] as String?)?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
  // An impersonal verb lists one form — "geschieht" — and reading it as a
  // table asked "geschehen: ich ___" and keyed the third-person form.
  if (forms.length < _wiktionaryPresentPronouns.length) return null;
  String verbOf(String form) => form.split(' ').first;

  final du = forms.indexWhere((f) => verbOf(f).endsWith('st'));
  if (du <= 0) return null;
  final before = forms.sublist(0, du);
  final ich = before.firstWhere((f) => verbOf(f).endsWith('e'),
      orElse: () => before.first);
  final after = forms.sublist(du + 1);
  final er = after.where((f) {
        final v = verbOf(f);
        return v.endsWith('t') && !v.endsWith('st');
      }).firstOrNull ??
      after.where((f) => verbOf(f).endsWith('t')).firstOrNull ??
      after.firstOrNull;
  if (er == null) return null;
  return {'ich': ich, 'du': forms[du], 'er/sie/es': er};
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
  // "gefilmt: ich ___", "nahm: du ___": an inflected form is not a verb to
  // conjugate. Its own lemma has to be itself.
  if (!w.isHeadword) return false;
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
