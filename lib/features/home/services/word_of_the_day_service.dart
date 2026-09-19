// lib/features/home/services/word_of_the_day_service.dart
//
// Pure helpers for WordOfTheDayCard, extracted for unit testing.

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';
import '../../../core/models/word_features.dart';

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
///
/// Works on the light catalogue as well as on decoded words: "has a
/// definition" and "is a known misspelling of another entry" are read from the
/// feature index when the word carries no decoded enrichment, so the card does
/// not have to open the whole pack to choose one word.
/// Returns null when the pool is empty.
GermanWord? pickWordOfTheDay(List<GermanWord> words, DateTime date,
    {int? targetBand}) {
  if (words.isEmpty) return null;

  // Only decoded words can contribute here; for a light pool the same
  // exclusion arrives as WordFeature.knownMisspelling, computed over the whole
  // pack when the feature index was built.
  final knownMisspellings = <String>{
    for (final word in words)
      if (word.isHydrated) ...[
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
          isPresentableVocabularyEntry(w) &&
          // A word presented as the word of the day should be the one a
          // learner would look up. See GermanWord.isHeadword.
          w.isHeadword &&
          !w.has(WordFeature.knownMisspelling) &&
          !knownMisspellings.contains(_normalizeHeadword(w.word)) &&
          _hasDefinition(w))
      .toList();
  if (pool.isEmpty) return null;
  final seed = dayOfYear(date) + date.year * 366;
  return pool[_scatter(seed) % pool.length];
}

/// Spreads consecutive seeds across the pool.
///
/// The index used to be the seed itself, and the pool arrives in catalogue
/// order — so the word of the day walked the dictionary one entry per day:
/// *concern, concerned, concerning, concerns, conclusion…* through January,
/// and *Lexikon, lila, Limonade, Lineal, links…* in German. Still a pure
/// function of the date, so a given day is still the same word for everyone;
/// only the order is no longer alphabetical.
///
/// A 32-bit integer finalizer (MurmurHash3's), which is cheap and mixes
/// adjacent inputs to unrelated outputs.
int _scatter(int seed) {
  var x = seed & 0xffffffff;
  x ^= x >>> 16;
  x = (x * 0x85ebca6b) & 0xffffffff;
  x ^= x >>> 13;
  x = (x * 0xc2b2ae35) & 0xffffffff;
  x ^= x >>> 16;
  return x;
}

/// Whether the word has a definition to show — from the decoded enrichment
/// when it is loaded, from the feature index otherwise.
bool _hasDefinition(GermanWord word) => word.isHydrated
    ? (word.apiEnrichment?.definitions.isNotEmpty ?? false)
    : word.has(WordFeature.definitions);

String _normalizeHeadword(String word) => word.trim().toLowerCase();
