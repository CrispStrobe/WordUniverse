// lib/features/games/services/synonym_flash_service.dart
//
// Synonym Flash challenge construction, extracted from the screen so it can be
// generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';
import '../../../core/models/word_features.dart';

class SynonymChallenge {
  const SynonymChallenge({
    required this.word,
    required this.correctSynonym,
    required this.options,
    required this.correctIndex,
  });

  final GermanWord word;
  final String correctSynonym;
  final List<String> options;
  final int correctIndex;
}

/// One challenge, or null when [word] has no synonym that makes a fair one.
/// [allWords] is the round's own sample: the prompts and the distractors come
/// from it. [known] is every entry whose spelling the game could look up —
/// the sample plus the catalogue entries for the synonyms themselves — and is
/// read only to judge how familiar a candidate answer is.
SynonymChallenge? buildSynonymChallenge({
  required GermanWord word,
  required List<GermanWord> allWords,
  required Map<String, GermanWord> known,
  required bool isGerman,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  // Where the pack says which sense a synonym belongs to, use that sense and
  // nothing else: "charge" is an attack, not a point, and "world" is the
  // cosmos, not a man. Pooling every sense together is what put those
  // answers on the card. German carries no senses, and nor do a third of the
  // English entries, so the tiers below still do the work for them.
  final sensed = _synonymsOfItsOwnSense(word);
  final synonyms = sensed ?? word.apiEnrichment?.synonyms ?? const [];
  if (synonyms.isEmpty) return null;
  // "atlantic" glossed as an ocean is a name, not vocabulary.
  if (namesSomething(word)) return null;

  // Rank the clean synonyms by how likely a learner is to know them. The
  // packs list rare and sense-specific ones beside everyday ones — "Almighty"
  // for "creator", "deport" for "behave", "mantle" for "cape" — and picking at
  // random from the whole list asks about the rarest as often as the
  // commonest. Preference: a curriculum word at or below the prompt's band,
  // then any catalogue word near it, then anything else in the catalogue, then
  // synonyms the catalogue does not contain at all.
  final bySpelling = known;
  final curriculumTier = <String>[];
  final nearTier = <String>[];
  final inVocab = <String>[];
  final farTier = <String>[];
  for (final syn in synonyms) {
    final clean = syn.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
    if (!isCleanSynonym(clean)) continue;
    // A synonym that differs from the prompt only in case is no question at
    // all: the pack offered "Creator" for "creator", "Atlantic" for
    // "atlantic".
    if (clean.toLowerCase() == word.word.toLowerCase()) continue;
    // Nor one that is written inside the prompt, or writes the prompt inside
    // itself: "high" for "high-pitched", "lily-white" for "white".
    if (sharesAWrittenPart(clean, word.word)) continue;
    // In English a capitalised synonym for a lowercase word is a proper-noun
    // sense — "Almighty" for "creator", "Romance" for "latin". German
    // capitalises every noun, so the same test cannot be applied there.
    if (!isGerman &&
        word.word == word.word.toLowerCase() &&
        clean != clean.toLowerCase()) {
      continue;
    }
    final entry = bySpelling[clean.toLowerCase()];
    if (entry == null) continue;
    if (entry.has(WordFeature.curriculum) &&
        entry.gradeLevel <= word.gradeLevel) {
      curriculumTier.add(clean);
    } else if (entry.gradeLevel <= word.gradeLevel + 1) {
      nearTier.add(clean);
    } else if (entry.gradeLevel <= word.gradeLevel + 2) {
      inVocab.add(clean);
    } else {
      // In the catalogue, but bands above the prompt: "Menagerie" for "Zoo"
      // in front of a seven-year-old.
      farTier.add(clean);
    }
  }
  // Randomize which valid synonym is the answer (rather than always the
  // first), from the best tier that has one.
  //
  // A synonym the catalogue does not hold at all is never collected. It is a
  // word the learner has never met and never will here, so "which word means
  // the same as später?" was answered "nachmalig", "ziehen" with
  // "umherstreichen" and "conspirator" with "machinator" — none of the three
  // is in either pack. Requiring the answer to be a catalogue word keeps four
  // fifths of the prompts at every grade in both languages.
  final candidates = [curriculumTier, nearTier, inVocab, farTier]
      .firstWhere((tier) => tier.isNotEmpty, orElse: () => const []);
  if (candidates.isEmpty) return null;
  final correctWord = candidates[random.nextInt(candidates.length)];

  // Any of the word's listed synonyms counts as correct, so exclude them all
  // (plus the prompt word itself) from the distractor pool.
  final synSet = synonyms.map((s) => s.toLowerCase()).toSet()
    ..add(word.word.toLowerCase());

  // Restrict distractors to the same word type as the prompt for plausibility;
  // fall back to any word type if too few same-type candidates exist.
  bool eligible(GermanWord w) =>
      !synSet.contains(w.word.toLowerCase()) &&
      w.word.toLowerCase() != correctWord.toLowerCase() &&
      !namesSomething(w);

  final sameType = allWords
      .where((w) => w.wordType == word.wordType && eligible(w))
      .map((w) => w.word)
      .toList()
    ..shuffle(random);
  final anyType = allWords.where(eligible).map((w) => w.word).toList()
    ..shuffle(random);

  final needed = optionCount - 1;
  // Dedupe distractors against each other (case-insensitively) and against
  // the correct answer using a seen-set guard.
  final distractors = <String>[];
  final seen = <String>{correctWord.toLowerCase()};
  for (final source in [sameType, anyType]) {
    for (final t in source) {
      if (distractors.length >= needed) break;
      if (seen.add(t.toLowerCase())) distractors.add(t);
    }
    if (distractors.length >= needed) break;
  }
  if (distractors.isEmpty) return null;

  final options = [correctWord, ...distractors.take(needed)]..shuffle(random);
  final correctIndex =
      options.indexWhere((o) => o.toLowerCase() == correctWord.toLowerCase());
  if (correctIndex < 0) return null;

  return SynonymChallenge(
    word: word,
    correctSynonym: correctWord,
    options: options,
    correctIndex: correctIndex,
  );
}

/// Whether either word is written inside the other as a whole part —
/// "high"/"high-pitched", "white"/"lily-white". The answer is then visible in
/// the prompt, whichever way round it is asked.
bool sharesAWrittenPart(String a, String b) {
  List<String> parts(String word) => word
      .toLowerCase()
      .split(RegExp(r"[-'’\s]+"))
      .where((part) => part.isNotEmpty)
      .toList();
  final first = parts(a);
  final second = parts(b);
  // German writes its compounds without a separator, so splitting sees one
  // part on each side and the intersection is empty however plainly the
  // answer is written in the prompt. The nightly sweep found "Schließfach"
  // answered "Fach", "hinüber" answered "hin" and "selbständig" answered
  // "selbst". Containment is what catches those; it is checked first because
  // it subsumes the equal case as well.
  final plainA = a.toLowerCase();
  final plainB = b.toLowerCase();
  // Only when the shorter one is a word in its own right: "an" and "in" turn
  // up inside plenty of longer words without being visible as the answer.
  if (plainA.length >= 3 &&
      plainB.length >= 3 &&
      (plainA.contains(plainB) || plainB.contains(plainA))) {
    return true;
  }
  // Two plain words share nothing but themselves, and that case is handled
  // before this. "bye-bye" splits into two parts that are the same word, so
  // the count has to be taken before deduplicating.
  if (first.length == 1 && second.length == 1) return false;
  return first.toSet().intersection(second.toSet()).isNotEmpty;
}

/// The synonyms of the word's own leading sense, or null when it has none.
///
/// The first sense of its part of speech whose definition is not a name's.
/// A sense listing no synonyms is skipped rather than ending the search: a
/// word whose leading sense happens to have none is not a word without
/// synonyms.
List<String>? _synonymsOfItsOwnSense(GermanWord word) {
  // German first: openThesaurus groups by sense the way WordNet does, and the
  // groups are ordered with the commonest reading first. A synset with no
  // usable synonyms is skipped rather than ending the search — "Schere" has
  // one of those and a real one after it.
  for (final sense
      in word.apiEnrichment?.thesaurusSenses ?? const <ThesaurusSense>[]) {
    final plain = sense.plainSynonyms;
    if (plain.isNotEmpty) return plain;
  }

  final senses = word.apiEnrichment?.wordnetSenses ?? const <WordNetSense>[];
  if (senses.isEmpty) return null;
  for (final sense in senses) {
    if (!_posMatches(sense.pos, word.wordType)) continue;
    if (senseNamesSomething(sense,
        promptIsLowercase: word.word == word.word.toLowerCase())) {
      continue;
    }
    if (sense.synonyms.isNotEmpty) return sense.synonyms;
  }
  return null;
}

/// Whether a WordNet part of speech is the one the catalogue filed the word
/// under. WordNet writes English names; the catalogue writes German ones.
bool _posMatches(String? pos, GermanWordType type) => switch (pos) {
      'noun' => type == GermanWordType.substantiv,
      'verb' => type == GermanWordType.verb,
      'adjective' || 'adjective satellite' => type == GermanWordType.adjektiv,
      'adverb' => type == GermanWordType.adverb,
      _ => false,
    };

/// Whether a listed synonym is usable as a one-word answer. Letters (any
/// script, so German diacritics pass), hyphen and apostrophe only.
bool isCleanSynonym(String s) {
  if (s.length < 2 || s.contains(' ')) return false;
  if (RegExp(r'\d').hasMatch(s)) return false;
  if (s == s.toUpperCase() && s.length > 1) return false;
  return RegExp(r"^[\p{L}\-' ]+$", unicode: true).hasMatch(s);
}

/// Builds up to [maxChallenges] from [pool].
/// [catalogue] are the entries for the synonyms the pool lists, looked up by
/// spelling. Without them "is this word in the catalogue?" could only mean
/// "is it in these 200 words?", which it almost never was, and the answer fell
/// through to a synonym no pack contains.
List<SynonymChallenge> buildSynonymChallenges({
  required List<GermanWord> pool,
  required bool isGerman,
  List<GermanWord> catalogue = const [],
  int maxChallenges = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final known = <String, GermanWord>{
    for (final w in catalogue) w.word.toLowerCase(): w,
    for (final w in pool) w.word.toLowerCase(): w,
  };
  final challenges = <SynonymChallenge>[];
  for (final word in pool) {
    if (challenges.length >= maxChallenges) break;
    final challenge = buildSynonymChallenge(
      word: word,
      allWords: pool,
      known: known,
      isGerman: isGerman,
      optionCount: optionCount,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}
