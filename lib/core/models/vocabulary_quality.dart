import 'vocabulary_models.dart';
import 'word_features.dart';

/// Returns whether [entry] is safe to present as a vocabulary headword.
///
/// The source databases contain a small number of learner-error records whose
/// definitions explicitly describe them as misspellings. They are useful as
/// distractors, but must never become prompts or catalogue entries.
///
/// For an un-hydrated word the definition check is skipped: it was already
/// applied — over the same markers, in SQL — when the pack's feature index was
/// built, which is what lets the catalogue load without decoding enrichment.
/// See db_feature_index.dart.
bool isPresentableVocabularyEntry(GermanWord entry) {
  if (!_cleanHeadword.hasMatch(entry.word.trim())) return false;
  if (entry.sources.any(_isMisspellingSource)) return false;
  if (!entry.isHydrated) return true;

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

/// Whether a gloss describes a name or a place rather than a meaning.
///
/// Wiktionary writes proper nouns with a fixed set of openings, and the packs
/// do not always type them as proper nouns: "franklin" arrives as an ordinary
/// grade-3 word glossed "A surname transferred from the nickname", and
/// "columbia" as "America; the United States; an appellation given in honor of
/// Christopher Columbus". Neither is vocabulary a learner can reason about.
bool describesAName(String definition) {
  final lower = definition.toLowerCase();
  return kNameGlossOpenings.any(lower.startsWith) ||
      kNameGlossPhrases.any(lower.contains);
}

/// Gloss openings Wiktionary uses for names. Also compiled into SQL when the
/// feature index is built, so a light word can answer the same question.
const List<String> kNameGlossOpenings = [
  'a surname', 'a male given name', 'a female given name', 'a given name',
  'a unisex given name', 'a placename', 'a place name', 'an appellation',
  'a diminutive of the male', 'a diminutive of the female',
];

/// Gloss phrases that name a place or person wherever they appear.
///
/// Deliberately not anchored to the start: Wiktionary writes "A
/// transcontinental country in the Caucasus" for Georgia, so a leading "a
/// country in" misses it. "Official name:" and "Capital:" are that style's
/// own markers and are the most reliable of these.
const List<String> kNameGlossPhrases = [
  'official name:', 'capital:',
  ' country in ', ' country of ', ' city in ', ' town in ', ' village in ',
  ' county in ', ' river in ', ' lake in ', ' province of ', ' state of ',
  'an unincorporated community', 'a census-designated place',
  'an island', 'an archipelago', 'a peninsula', 'a continent',
  'a mountain range', 'a sea ', 'an ocean', 'a capital of', 'a capital city',
  // Figures rather than places: "Mother of the prophet Samuel in the Old
  // Testament" is a name, not vocabulary.
  'in the old testament', 'in the new testament', 'in greek mythology',
  'in roman mythology', 'in norse mythology',
];
/// Whether the entry's own gloss says it is a name or a place.
///
/// Brands, surnames and placenames reach the catalogue untyped — "a sony",
/// "columbia", "atlantic", "pennsylvania" — so [GermanWord.isProperNoun] does
/// not catch them. A name is not a word whose meaning a learner can reason
/// about, as a prompt or as a distractor.
bool namesSomething(GermanWord word) {
  // A light word has no gloss to read; the feature index answered this for it
  // when the pack was indexed.
  if (!word.isHydrated) return word.has(WordFeature.nameLike);
  final definition = word.displayDefinitions.firstOrNull;
  return definition != null && describesAName(definition);
}
