import 'vocabulary_models.dart';

/// Returns whether [entry] is safe to present as a vocabulary headword.
///
/// The source databases contain a small number of learner-error records whose
/// definitions explicitly describe them as misspellings. They are useful as
/// distractors, but must never become prompts or catalogue entries.
bool isPresentableVocabularyEntry(GermanWord entry) {
  if (!_cleanHeadword.hasMatch(entry.word.trim())) return false;
  if (entry.sources.any(_isMisspellingSource)) return false;

  final enrichment = entry.apiEnrichment;
  if (enrichment == null) return true;
  final description = [
    ...enrichment.definitions,
    ...enrichment.entryNotes,
  ].join(' ').toLowerCase();
  return !_invalidSpellingMarkers.any(description.contains);
}

final RegExp _cleanHeadword = RegExp(
  r"^[A-Za-zÀ-ÖØ-öø-ÿẞ]+(?:[-'’][A-Za-zÀ-ÖØ-öø-ÿẞ]+)*$",
);

bool _isMisspellingSource(String source) {
  final normalized = source.toUpperCase();
  return normalized.contains('COMMON_MISSPELLED') ||
      normalized.contains('COMMON_MISSPELLING');
}

const _invalidSpellingMarkers = <String>[
  'misspelling of',
  'misspelt form of',
  'misspelled form of',
  'incorrect spelling of',
  'nonstandard spelling of',
  'obsolete spelling of',
  'obsolete form of',
  'falschschreibung von',
];
