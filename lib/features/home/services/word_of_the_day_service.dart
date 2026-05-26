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
/// Pool: grade 1-3, no proper nouns, no multi-word entries, must have
/// at least one definition in apiEnrichment.
/// Returns null when the pool is empty.
GermanWord? pickWordOfTheDay(List<GermanWord> words, DateTime date) {
  if (words.isEmpty) return null;
  final pool = words
      .where((w) =>
          !w.isProperNoun &&
          w.gradeLevel <= 3 &&
          !w.word.contains(' ') &&
          (w.apiEnrichment?.definitions.isNotEmpty ?? false))
      .toList();
  if (pool.isEmpty) return null;
  final seed = dayOfYear(date) + date.year * 366;
  return pool[seed.abs() % pool.length];
}
