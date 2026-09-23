// lib/features/games/services/hypernym_flash_service.dart
//
// Hypernym Flash challenge construction, extracted from the screen so it can
// be generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

class HypernymChallenge {
  final GermanWord word;
  final String correctHypernym;
  final List<String> options;
  final int correctIndex;
  const HypernymChallenge({
    required this.word,
    required this.correctHypernym,
    required this.options,
    required this.correctIndex,
  });
}

const Set<String> _abstractEnglishVerbs = {
  'be',
  'have',
  'do',
  'exist',
  'become',
  'get',
  'make',
  'take',
  'go',
  'come',
  'give',
  'use',
  'find',
  'think',
  'see',
  'know',
  'want',
  'seem',
  'put',
  'move',
  'change',
  'live',
  'try',
  'apply',
  'act',
  'work',
  'play',
  'bring',
  'keep',
  'turn',
  'show',
  'leave',
  'feel',
  'follow',
  'need',
  'run',
  'call',
  'look',
  'set',
  'hold',
  'start',
  'stop',
  'stay',
  'begin',
  'appear',
  'happen',
  // The commonest hypernyms in the English pack, counted: move 875, change
  // 515, go 316, alter 286, modify 265, travel 252. WordNet climbs to these
  // from almost any verb, so they answer "is a kind of what?" for almost any
  // verb, which is the same as answering it for none.
  'alter',
  'modify',
  'travel',
  'locomote',
  'pass',
  'displace',
  'create',
};

/// WordNet's upper ontology. Every noun climbs to these, so they are true of
/// almost anything and mean nothing to a child: "curiosity is a kind of
/// cognitive state" is the sort of answer that follows. A hypernym one step
/// down — "a robin is a kind of bird" — is the question worth asking.
const Set<String> _wordNetAbstractions = {
  'entity',
  'abstraction',
  'abstract entity',
  'physical entity',
  'thing',
  'object',
  'whole',
  'unit',
  'group',
  'grouping',
  'relation',
  'attribute',
  'property',
  'state',
  'condition',
  'cognitive state',
  'psychological feature',
  'cognition',
  'knowledge',
  'event',
  'act',
  'human action',
  'human activity',
  'activity',
  'phenomenon',
  'process',
  'measure',
  'quantity',
  'amount',
  'causal agent',
  'physical object',
  'matter',
  'substance',
  'part',
  'region',
  'location',
  // "a discomfort is a kind of status" — both lanes of a two-model review
  // agreed on that one. WordNet's person nodes belong here too: "actor",
  // "doer" and "worker" mean *one who acts*, not a performer, which is how
  // "a forerunner is a kind of actor" happened. A performer can still be
  // reached through "performer".
  'status',
  'position',
  'actor',
  'doer',
  'worker',
};

bool _isCleanHypernym(String w, bool isDE) {
  if (w.length < 3) return false;
  final tokens = w.split(' ');
  if (tokens.length > 2) return false;
  final lower = w.toLowerCase();
  if (!isDE && _abstractEnglishVerbs.contains(lower)) return false;
  if (!isDE && _wordNetAbstractions.contains(lower)) return false;
  return true;
}

/// How many hypernyms an entry may list and still be worth asking about.
///
/// The packs give no sense for a hypernym, so the longer the list the more
/// senses it silently spans and the more a single answer is a coin flip. The
/// count separates the two cases cleanly: every item a model judged correct
/// came from an entry with eight or fewer — yacht 3, aspirin 5, comedian 7,
/// frost 8 — and the ones it flagged came from entries with fifteen to
/// ninety-three: show 35, water 23, deal 69, fall 93. Those are the common
/// monosyllables that dominate the first two English grades, which is why
/// that band was the last to stay wrong: "water is a kind of food", "a fall
/// is a kind of die".
///
/// Two thirds of the English candidates and nine tenths of the German ones
/// are under the line, at every grade, so the game keeps enough to play.
const int _sensesAWordCanCarry = 8;

/// How many senses of its own class an entry may have before its leading one
/// stops being the one a child means. Measured against the items a model
/// judged: every one it called right came from an entry with one or two
/// senses of its class, bar four; every one it called wrong came from an
/// entry with four or more.
const int _sensesWorthTrusting = 3;

/// Whether the word can be asked "is a kind of what?" at all.
///
/// WordNet has no hypernymy for adjectives or adverbs, so every hypernym on
/// one of them was written for a different word class: "deaf" arrives with
/// "desensitise" (the verb) and "people" (the noun), and neither answers a
/// question about the adjective.
bool _hasHypernymy(GermanWordType type) =>
    type == GermanWordType.substantiv || type == GermanWordType.verb;

/// The hypernym to ask for, or null when none of them makes a fair question.
///
/// [catalogue] maps lowercase spelling to entry. A hypernym is only used when
/// the catalogue holds it with the *same word type* as the prompt: the packs
/// list hypernyms across every WordNet sense, so a noun would otherwise be
/// asked "a crowd is a kind of what?" and keyed "displace" (the verb sense),
/// or "an angle is a kind of what?" keyed "European" (the Germanic tribe).
String? pickHypernym(
  GermanWord word, {
  required bool isGerman,
  Map<String, GermanWord>? catalogue,
}) {
  final isDE = isGerman;
  if (!_hasHypernymy(word.wordType)) return null;
  // Which sense to read depends on which class the word is, so an entry the
  // pack contradicts itself about cannot be asked this. It is the same rule
  // the word-class games use, and it is the same words: "at" is filed as a
  // noun and is astatine, "in" indium, "or" an operating room, "it"
  // information technology, "two" a playing card.
  if (classIsContradicted(word)) return null;

  // Where the pack says which sense a hypernym belongs to, there is nothing
  // to infer, and the pooled list below — every sense poured together — is
  // exactly what that data replaces. So for an entry that has senses, the
  // senses are the whole answer: they give one or the word is not asked.
  // Everything after this is for German, which has no sense-linked
  // hypernyms at all, and for the English entries WordNet does not cover.
  final senses = word.apiEnrichment?.wordnetSenses ?? const <WordNetSense>[];
  if (senses.isNotEmpty) {
    return _fromSenses(word, isDE: isDE, catalogue: catalogue);
  }

  final all = word.apiEnrichment?.hypernyms ?? [];
  if (all.length > _sensesAWordCanCarry) return null;
  // Curated relations first; the unsourced remainder only when the curated
  // ones yield nothing usable.
  final sourced = all.where((h) => (h.source ?? '').isNotEmpty).toList();
  final unsourced = all.where((h) => (h.source ?? '').isEmpty).toList();
  for (final tier in [sourced, unsourced]) {
    final usable = _saidInItsOwnDefinition(
        word, _confirmed(word, tier, isDE: isDE, catalogue: catalogue));
    if (usable.isNotEmpty) return _mostFamiliar(usable, catalogue);
  }
  return null;
}

/// The candidates the word's own leading senses mention, or all of them.
///
/// This is the only thing in the packs that says which sense a hypernym was
/// listed under. Wiktionary and WordNet write the genus into the gloss —
/// "frost: ice crystals forming a white deposit", "a yacht is an expensive
/// vessel", "an idol: a material image of a deity" — so a hypernym the gloss
/// repeats belongs to the sense the gloss describes. Reading only the first
/// three senses keeps it about what the word mostly means: read the whole
/// entry and "frost" matches "poet", from "United States poet Robert Frost".
///
/// It fixes jungle → camp into jungle → forest, idol → lead into idol →
/// image, advantage → point into advantage → benefit.
///
/// Where the entry mentions none of them, the word is not asked about at all.
/// That is what finally clears the first two English grades, whose pool is
/// the common monosyllables and the two-letter entries whose only noun sense
/// is a chemical symbol: "at" is astatine, "in" indium, "he" helium, "it"
/// information technology. None of their glosses says so, and the game was
/// asking a six-year-old whether "at" is a kind of element. It costs the
/// answerable-but-unstated ones too — comedian → actor, debris → trash — and
/// leaves six candidates at English grade 1, where the pool then fills from
/// the grades either side. A word from the next grade up beats a wrong
/// answer.
List<String> _saidInItsOwnDefinition(GermanWord word, List<String> candidates) {
  if (candidates.isEmpty) return candidates;
  final senses = word.displayDefinitions.take(3).join(' ').toLowerCase();
  if (senses.isEmpty) return const [];
  final mentioned = candidates
      .where((c) =>
          RegExp('\\b${RegExp.escape(c.toLowerCase())}\\b').hasMatch(senses))
      .toList();
  return mentioned;
}

/// The answer taken from the word's own sense, or null when it has none.
///
/// The first sense of the word's own part of speech that is not a name — the
/// leading sense of "frost" is Robert Frost the poet, which is where "a frost
/// is a kind of poet" came from, and the leading sense of "chicken" after
/// reduction is the adjective. Its hypernyms belong to that sense and to no
/// other, so "chicken" is poultry, "hand" an extremity, "boat" a vessel.
String? _fromSenses(
  GermanWord word, {
  required bool isDE,
  Map<String, GermanWord>? catalogue,
}) {
  final senses = word.apiEnrichment?.wordnetSenses ?? const <WordNetSense>[];
  if (senses.isEmpty) return null;

  // WordNet orders senses by how common they are in general writing, which
  // is not the same as what a seven-year-old means: "plant" leads with the
  // factory, "program" with "a series of steps" rather than the thing on
  // television. Where an entry has many senses of its own class the leading
  // one is not reliably the one meant, and no signal in the pack says which
  // is — matching the entry's own gloss against the senses was measured and
  // rescues "plant" while breaking "deal", "need" and "process", and
  // "water"'s own leading gloss is a hamlet in Devon.
  //
  // So the same shape of rule as the hypernym count below: ask only where
  // the entry is unambiguous enough for the leading sense to be trusted.
  // It keeps 63% of entries overall and prunes where the polysemy is —
  // 41% kept at grade 2, 97% at grade 6, which is the right way round.
  final ofItsClass =
      senses.where((s) => _posMatches(s.pos, word.wordType)).length;
  if (ofItsClass > _sensesWorthTrusting) return null;

  final promptIsLowercase = word.word == word.word.toLowerCase();
  final lowerPrompt = word.word.toLowerCase();

  for (final sense in senses) {
    if (!_posMatches(sense.pos, word.wordType)) continue;
    if (senseNamesSomething(sense, promptIsLowercase: promptIsLowercase)) {
      continue;
    }
    final usable = <String>[];
    for (final candidate in sense.hypernyms) {
      final w = candidate.trim();
      if (!_isCleanHypernym(w, isDE)) continue;
      if (!isDE && promptIsLowercase && w != w.toLowerCase()) continue;
      final lower = w.toLowerCase();
      // "show" lists itself among its own sense's hypernyms.
      if (lower == lowerPrompt) continue;
      if (lowerPrompt.contains(lower) || lower.contains(lowerPrompt)) continue;
      usable.add(w);
    }
    if (usable.isNotEmpty) return _mostFamiliar(usable, catalogue);
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

/// The hypernyms in [tier] that could fairly be the answer.
List<String> _confirmed(
  GermanWord word,
  List<ApiSemanticTerm> tier, {
  required bool isDE,
  Map<String, GermanWord>? catalogue,
}) {
  final promptIsLowercase = word.word == word.word.toLowerCase();
  final usable = <String>[];
  for (final h in tier) {
    final w = (h.word ?? '').trim();
    if (!_isCleanHypernym(w, isDE)) continue;
    // English capitalises only names, so a capitalised answer to a lowercase
    // prompt is a name sense: "a boy is a kind of Black man", "a satyr is a
    // kind of Greek deity". German capitalises every noun, so the signal
    // exists in English only.
    if (!isDE && promptIsLowercase && w != w.toLowerCase()) continue;
    // The packs list the word among its own hypernyms, which would key
    // "launch" as the answer to "a launch is a kind of what?". A German
    // compound spells its own answer out too: reading the gloss to find the
    // sense turns up "Ball" for "Fußball", and the prompt is then the answer
    // with a word in front of it.
    final lower = w.toLowerCase();
    final promptLower = word.word.toLowerCase();
    if (lower == promptLower) continue;
    if (promptLower.contains(lower) || lower.contains(promptLower)) continue;
    if (catalogue == null) {
      usable.add(w);
      continue;
    }
    final entry = catalogue[w.toLowerCase()];
    // The packs list hypernyms across every sense with no note of which, so a
    // word the catalogue does not hold cannot be checked at all — and
    // unchecked is where "a show is a kind of affirm" and "an archive is a
    // kind of pull in" come from. Nine in ten words that have hypernyms have
    // one the catalogue confirms, at every grade in both languages, so the
    // game loses little by asking only about those.
    if (entry == null) continue;
    if (namesSomething(entry)) continue;
    if (entry.wordType == word.wordType) usable.add(w);
  }
  return usable;
}

/// The one of [candidates] a learner is likeliest to have met.
///
/// Position in the list looked like WordNet's own order, nearest sense first,
/// and it is not: the lists are sense-grouped and alphabetical inside each
/// group, and 38% of the entries with three or more hypernyms were sorted
/// wholesale at some point, which destroys the grouping. So the first entry
/// is often just the alphabetically first — "a boy is a kind of adult male",
/// "a frost is a kind of cold weather", "a comedian is a kind of histrion".
///
/// Familiarity is the honest tiebreak, and it is the one that suits the game:
/// the answer should be a word the learner already has. It gives boy → man,
/// frost → ice, yacht → boat, comedian → actor. It cannot rescue a word whose
/// every listed hypernym belongs to a sense the child does not mean — "show",
/// "hand" — because there is nothing in the data that says which sense a
/// hypernym was listed under.
String _mostFamiliar(
    List<String> candidates, Map<String, GermanWord>? catalogue) {
  if (catalogue == null) return candidates.first;
  final ranked = [...candidates]..sort((a, b) {
      final ga = catalogue[a.toLowerCase()]?.gradeLevel ?? 99;
      final gb = catalogue[b.toLowerCase()]?.gradeLevel ?? 99;
      if (ga != gb) return ga.compareTo(gb);
      // A shorter word at the same grade is the plainer one: "ice" over
      // "cover", "actor" over "performer".
      if (a.length != b.length) return a.length.compareTo(b.length);
      return a.compareTo(b);
    });
  return ranked.first;
}

HypernymChallenge? buildHypernymChallenge({
  required GermanWord word,
  required String correct,
  required List<String> hypernymPool,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  // Exclude EVERY hypernym of this word from the distractor pool, not just
  // the chosen `correct` — a word often has several valid hypernyms, and any
  // of them appearing as a "wrong" option would actually be correct.
  final ownHypernyms = (word.apiEnrichment?.hypernyms ?? [])
      .map((h) => (h.word ?? '').trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();

  final distractors = <String>[];
  for (final h in hypernymPool) {
    if (distractors.length >= optionCount - 1) break;
    final hl = h.toLowerCase();
    if (!ownHypernyms.contains(hl) &&
        !distractors.any((d) => d.toLowerCase() == hl)) {
      distractors.add(h);
    }
  }
  if (distractors.isEmpty) return null;

  final options = [correct, ...distractors.take(optionCount - 1)];
  options.shuffle(random);
  final correctIndex =
      options.indexWhere((o) => o.toLowerCase() == correct.toLowerCase());
  if (correctIndex < 0) return null;

  return HypernymChallenge(
    word: word,
    correctHypernym: correct,
    options: options,
    correctIndex: correctIndex,
  );
}

/// Builds up to [maxChallenges] from [pool].
///
/// The chosen hypernym is computed once per word and reused for the answer and
/// for the distractor pool, so the options can never contain another valid
/// hypernym of the prompt.
/// [candidates] are the catalogue entries for the hypernyms the pool lists.
/// The word-type check below only bites when the catalogue holds the hypernym,
/// and a 200-word sample of words-that-have-hypernyms holds almost none of
/// them, so without these the check quietly does nothing and "a show is a kind
/// of affirm" gets through.
List<HypernymChallenge> buildHypernymChallenges({
  required List<GermanWord> pool,
  required bool isGerman,
  List<GermanWord> candidates = const [],
  int maxChallenges = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final catalogue = {
    for (final word in candidates) word.word.toLowerCase(): word,
    for (final word in pool) word.word.toLowerCase(): word,
  };
  final picked = <GermanWord, String>{};
  for (final word in pool) {
    if (namesSomething(word)) continue;
    final hypernym =
        pickHypernym(word, isGerman: isGerman, catalogue: catalogue);
    if (hypernym != null) picked[word] = hypernym;
  }
  final hypernymPool = picked.values.toList()..shuffle(random);

  final challenges = <HypernymChallenge>[];
  for (final entry in picked.entries) {
    if (challenges.length >= maxChallenges) break;
    final challenge = buildHypernymChallenge(
      word: entry.key,
      correct: entry.value,
      hypernymPool: hypernymPool,
      optionCount: optionCount,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}
