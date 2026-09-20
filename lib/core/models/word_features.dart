// lib/core/models/word_features.dart
//
// Which enrichment a word actually carries, as one integer per word.
//
// The enrichment and metadata JSON blobs are ~6 KB per word (≈72 MB per pack).
// Games only ever ask yes/no questions of them when they pick a word pool —
// "does this word have synonyms?", "does it have hyphenation?" — and the
// answers never change for a given pack. Storing those answers as a bitmask
// lets the pools be built from integers, so the JSON is read only for the
// handful of words a round actually shows (see db_feature_index.dart).

/// A yes/no property of a word's enrichment, one bit each.
///
/// Bit positions are persisted in the feature-index cache: append new features
/// at the end and never renumber. [kWordFeatureIndexFormat] must be bumped when
/// the meaning of an existing bit changes, so stale caches are rebuilt.
enum WordFeature {
  definitions(0),
  synonyms(1),
  antonyms(2),
  hyphenation(3),
  translations(4),
  learnerErrors(5),
  gradeExamples(6),
  examples(7),
  hypernyms(8),
  hyponyms(9),
  expressions(10),
  proverbs(11),
  gutenbergExamples(12),
  enrichmentSuccess(13),
  ipa(14),
  inflections(15),

  /// This word's own spelling is recorded as a learner error of some *other*
  /// entry — "didnt" where "didn't" lists it as a common mistake. Such
  /// headwords must never be presented as something to learn.
  knownMisspelling(16),

  /// The word appears on a curriculum or graded word list the packs ship —
  /// a Bundesland Grundwortschatz in German, Cambridge YLE / Dolch / Fry /
  /// UK year lists / CEFR-J in English — rather than reaching the catalogue
  /// only through a frequency corpus.
  curriculum(17),

  /// The entry's enrichment describes this spelling, rather than a lemma it
  /// was derived from. See [GermanWord.isHeadword].
  headword(18),

  /// The entry's own gloss says it names something — a surname, a given name,
  /// a place. The packs carry these untyped, so [GermanWord.isProperNoun]
  /// misses them. See `describesAName`.
  nameLike(19),

  /// The entry's first gloss is a meaning a learner can be asked about —
  /// not a parse ("plural of passerby"), an abbreviation ("Abbreviation of
  /// July."), a bare domain label ("Botanik:"), a single word pointing at
  /// another entry, or a name. See `isUsableDefinition`.
  usableDefinition(20);

  const WordFeature(this.bit);

  /// Position in the mask. Persisted — see the note on [WordFeature].
  final int bit;

  int get mask => 1 << bit;
}

/// Bump when a bit's meaning changes, so cached indexes are discarded.
const int kWordFeatureIndexFormat = 7;

extension WordFeatureMask on int {
  bool hasFeature(WordFeature feature) => this & feature.mask != 0;

  bool hasAllFeatures(Iterable<WordFeature> features) =>
      features.every(hasFeature);

  bool hasAnyFeature(Iterable<WordFeature> features) =>
      features.any(hasFeature);
}
