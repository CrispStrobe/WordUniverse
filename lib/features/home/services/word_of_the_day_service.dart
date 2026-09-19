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

  bool eligible(GermanWord w) =>
      !w.isProperNoun &&
      isPresentableVocabularyEntry(w) &&
      // A word presented as the word of the day should be the one a learner
      // would look up. See GermanWord.isHeadword.
      w.isHeadword &&
      !w.has(WordFeature.knownMisspelling) &&
      !knownMisspellings.contains(_normalizeHeadword(w.word)) &&
      _hasDefinition(w) &&
      // Brands and place names reach the catalogue untyped — "a sony",
      // "columbia" — and a name is not a word to learn the meaning of.
      !_namesSomething(w);

  final eligibleWords = words.where(eligible).toList();
  if (eligibleWords.isEmpty) return null;

  for (final pool in _poolsInPreferenceOrder(eligibleWords, targetBand)) {
    if (pool.isNotEmpty) return pool[_indexForDay(date, pool.length)];
  }
  return null;
}

/// Which entry of a pool of [length] belongs to [date].
///
/// A hash of the date collides: "server" came up twice in ten days. Walking
/// the pool by a stride coprime with its length visits every entry before
/// repeating any, so a word cannot return until the pool is exhausted, while
/// the day still decides the word on its own.
int _indexForDay(DateTime date, int length) {
  if (length <= 1) return 0;
  final start = _scatter(date.year) % length;
  return (start + dayOfYear(date) * _strideFor(length, date.year)) % length;
}

/// A step that is coprime with [length], so repeated stepping is a cycle over
/// the whole pool rather than a short orbit within it.
int _strideFor(int length, int year) {
  if (length <= 2) return 1;
  var stride = 1 + _scatter(year * 7919) % (length - 1);
  while (_greatestCommonDivisor(stride, length) != 1) {
    stride = stride % (length - 1) + 1;
  }
  return stride;
}

int _greatestCommonDivisor(int a, int b) {
  while (b != 0) {
    final remainder = a % b;
    a = b;
    b = remainder;
  }
  return a;
}

/// How far above the learner's own band the word of the day aims.
///
/// The card is a place to meet a word rather than to be tested on one, so it
/// stretches: a band above what the learner is practising, two when that band
/// is empty, and drawn from words a curriculum actually prescribes rather than
/// from whatever a frequency corpus happened to contain.
///
/// One band first, deliberately. Two bands up put a band-2 learner on
/// "prosperity" and "paralyse"; a stretch should be reachable.
const List<int> kWordOfTheDayStretch = [1, 2, 0];

/// Candidate pools, best first. Each falls back to the next when a pack cannot
/// fill it, so a narrow band or a pack without curriculum tagging still yields
/// a word instead of an empty card.
Iterable<List<GermanWord>> _poolsInPreferenceOrder(
    List<GermanWord> words, int? targetBand) sync* {
  final curriculum = words.where((w) => w.has(WordFeature.curriculum)).toList();

  if (targetBand != null) {
    for (final source in [curriculum, words]) {
      for (final stretch in kWordOfTheDayStretch) {
        final band = (targetBand + stretch).clamp(1, 6);
        yield source.where((w) => w.gradeLevel == band).toList();
      }
    }
  }
  // No band asked for: the original behaviour, curriculum words first.
  yield curriculum.where((w) => w.gradeLevel <= 3).toList();
  yield words.where((w) => w.gradeLevel <= 3).toList();
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

/// Whether the word's own gloss says it is a name or a place.
///
/// Only decoded words can be checked; a light pool is filtered by the same
/// rule once the chosen word is hydrated for display.
bool _namesSomething(GermanWord word) {
  final definition = word.displayDefinitions.firstOrNull;
  return definition != null && describesAName(definition);
}

String _normalizeHeadword(String word) => word.trim().toLowerCase();
