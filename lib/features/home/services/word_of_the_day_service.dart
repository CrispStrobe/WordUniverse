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

/// The words for [date], best first: the card walks them and shows the first
/// whose decoded gloss is worth reading. A light word cannot be judged on its
/// gloss — "jul" is glossed "Abbreviation of July." — so the check has to
/// happen after hydration, which means offering more than one candidate.
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
/// Returns an empty list when nothing is eligible.
List<GermanWord> wordOfTheDayCandidates(List<GermanWord> words, DateTime date,
    {int? targetBand, int count = 1}) {
  if (words.isEmpty) return const [];

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
      !namesSomething(w);

  final eligibleWords = words.where(eligible).toList();
  if (eligibleWords.isEmpty) return const [];

  List<GermanWord>? fallback;
  var chosen = const <GermanWord>[];
  for (final pool in _poolsInPreferenceOrder(eligibleWords, targetBand)) {
    if (pool.isEmpty) continue;
    fallback ??= pool;
    if (pool.length < kWordOfTheDayMinimumPool) continue;
    chosen = pool;
    break;
  }
  if (chosen.isEmpty) {
    if (fallback == null) return const [];
    chosen = fallback;
  }
  {
    // Permuted per year, then walked: the pool arrives in catalogue order, so
    // stepping through it by a stride showed the alphabet — das Dorf, elf,
    // feiern, früher, der Grad, hoch, krank, der Mensch. The permutation is a
    // pure function of the word and the year, so the day still decides the
    // word and everyone sees the same one.
    final pool = chosen.toList()
      ..sort((a, b) =>
          _orderKey(a.word, date.year).compareTo(_orderKey(b.word, date.year)));
    final start = _indexForDay(date, pool.length);
    // A second stride for the candidates, distinct from the one the days walk
    // by. With one stride, today's second candidate is tomorrow's first — and
    // when today's first was rejected for its gloss, "sorry" came up twice in
    // a row.
    final stride = _candidateStrideFor(pool.length, date.year);
    return [
      for (var step = 0; step < count && step < pool.length; step++)
        pool[(start + step * stride) % pool.length],
    ];
  }
}

/// The word for [date], or null when nothing in [words] can be shown.
GermanWord? pickWordOfTheDay(List<GermanWord> words, DateTime date,
        {int? targetBand}) =>
    wordOfTheDayCandidates(words, date, targetBand: targetBand, count: 1)
        .firstOrNull;

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

/// A pool smaller than this is passed over, because the card walks it one
/// entry per day: the English pack's curriculum tagging reaches five words at
/// grade 5 — and four of them are "jun", "jul", "html" and "linux", a Fry
/// word list that imported badly — so the same word came round every few
/// days. Only the last resort ignores this, so the card is never empty.
const int kWordOfTheDayMinimumPool = 14;

/// Candidate pools, best first. Each falls back to the next when a pack cannot
/// fill it, so a narrow band or a pack without curriculum tagging still yields
/// a word instead of an empty card.
Iterable<List<GermanWord>> _poolsInPreferenceOrder(
    List<GermanWord> words, int? targetBand) sync* {
  final curriculum = words.where((w) => w.has(WordFeature.curriculum)).toList();

  if (targetBand != null) {
    // A curriculum word from a band below beats an untagged word at the right
    // one. Without this, an English grade-5 learner got "a jun", "a html" and
    // "a linux" — the untagged tail of a frequency list — because no
    // curriculum list reaches that far.
    for (final band in _curriculumBands(targetBand)) {
      yield curriculum.where((w) => w.gradeLevel == band).toList();
    }
    for (final stretch in kWordOfTheDayStretch) {
      final band = (targetBand + stretch).clamp(1, 6);
      yield words.where((w) => w.gradeLevel == band).toList();
    }
  }
  // No band asked for: the original behaviour, curriculum words first.
  yield curriculum.where((w) => w.gradeLevel <= 3).toList();
  yield words.where((w) => w.gradeLevel <= 3).toList();
}

/// Bands to look for a curriculum word in: the stretch first, then downwards.
Iterable<int> _curriculumBands(int targetBand) sync* {
  final seen = <int>{};
  for (final stretch in kWordOfTheDayStretch) {
    final band = (targetBand + stretch).clamp(1, 6);
    if (seen.add(band)) yield band;
  }
  for (var band = targetBand - 1; band >= 1; band--) {
    if (seen.add(band)) yield band;
  }
}

/// A stride for walking candidates within one day, coprime with [length] and
/// different from the stride the days themselves advance by.
int _candidateStrideFor(int length, int year) {
  if (length <= 2) return 1;
  final daily = _strideFor(length, year);
  var stride = 1 + _scatter(year * 104729 + length) % (length - 1);
  var guard = 0;
  while ((stride == daily || _greatestCommonDivisor(stride, length) != 1) &&
      guard++ < length) {
    stride = stride % (length - 1) + 1;
  }
  return stride;
}

/// A stable per-year sort key for a word. Dart's String.hashCode is not
/// guaranteed stable across platforms, and the word of the day has to be the
/// same on every device, so this hashes the code units itself (FNV-1a).
int _orderKey(String word, int year) {
  var hash = 2166136261 ^ _scatter(year);
  for (final unit in word.toLowerCase().codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0xffffffff;
  }
  return _scatter(hash);
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
/// Whether the word has a meaning worth showing on the card — from the
/// decoded gloss when it is loaded, from the feature index otherwise, where
/// the same rule was applied in SQL when the pack was indexed.
bool _hasDefinition(GermanWord word) => word.isHydrated
    ? _hasUsableGloss(word)
    : word.has(WordFeature.usableDefinition);

bool _hasUsableGloss(GermanWord word) {
  final definition = word.displayDefinitions.firstOrNull;
  return definition != null && isUsableDefinition(definition);
}

String _normalizeHeadword(String word) => word.trim().toLowerCase();
