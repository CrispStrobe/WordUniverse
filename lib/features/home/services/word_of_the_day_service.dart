// lib/features/home/services/word_of_the_day_service.dart
//
// Pure helpers for WordOfTheDayCard, extracted for unit testing.

import '../../../core/models/vocabulary_models.dart';

/// Returns the 0-based day index within the year (Jan 1 = 0).
int dayOfYear(DateTime d) {
  final start = DateTime(d.year, 1, 1);
  return d.difference(start).inDays;
}

/// Picks a deterministic word for [date] from [words].
///
/// By default, uses levels 1–3. When [targetBand] is supplied, the word is
/// selected from that learning band. Proper nouns and multi-word entries are
/// excluded, malformed headwords and known misspellings are rejected, and a
/// definition must be available.
/// Returns null when the pool is empty.
GermanWord? pickWordOfTheDay(List<GermanWord> words, DateTime date,
    {int? targetBand}) {
  if (words.isEmpty) return null;

  final knownMisspellings = <String>{
    for (final word in words) ...[
      ...?word.commonMistakes?.map(_normalizeHeadword),
      ...?word.apiEnrichment?.commonLearnerErrors.map(_normalizeHeadword),
    ],
  }..removeWhere((word) => word.isEmpty);

  final pool = words
      .where((w) =>
          !w.isProperNoun &&
          (targetBand == null
              ? w.gradeLevel <= 3
              : w.gradeLevel == targetBand) &&
          _hasCleanHeadword(w.word) &&
          !knownMisspellings.contains(_normalizeHeadword(w.word)) &&
          !w.sources.contains('COMMON_MISSPELLED') &&
          !_definitionMarksInvalidSpelling(w) &&
          (w.apiEnrichment?.definitions.isNotEmpty ?? false))
      .toList();
  if (pool.isEmpty) return null;
  final seed = dayOfYear(date) + date.year * 366;
  return pool[seed.abs() % pool.length];
}

final RegExp _cleanHeadword = RegExp(
  r"^[A-Za-zÀ-ÖØ-öø-ÿẞ]+(?:[-'’][A-Za-zÀ-ÖØ-öø-ÿẞ]+)*$",
);

bool _hasCleanHeadword(String word) => _cleanHeadword.hasMatch(word.trim());

String _normalizeHeadword(String word) => word.trim().toLowerCase();

bool _definitionMarksInvalidSpelling(GermanWord word) {
  final enrichment = word.apiEnrichment;
  if (enrichment == null) return false;
  final description = [
    ...enrichment.definitions,
    ...enrichment.entryNotes,
  ].join(' ').toLowerCase();
  return _invalidSpellingMarkers.any(description.contains);
}

const _invalidSpellingMarkers = <String>[
  'misspelling of',
  'misspelt form of',
  'misspelled form of',
  'incorrect spelling of',
  'nonstandard spelling of',
  'falschschreibung von',
];
