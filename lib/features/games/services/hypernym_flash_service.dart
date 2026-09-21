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
  final all = word.apiEnrichment?.hypernyms ?? [];
  // Curated relations first, in their own order; the unsourced remainder only
  // when the curated list yields nothing usable.
  final hypernyms = [
    ...all.where((h) => (h.source ?? '').isNotEmpty),
    ...all.where((h) => (h.source ?? '').isEmpty),
  ];
  final promptIsLowercase = word.word == word.word.toLowerCase();
  for (final h in hypernyms) {
    final w = (h.word ?? '').trim();
    if (!_isCleanHypernym(w, isDE)) continue;
    // English capitalises only names, so a capitalised answer to a lowercase
    // prompt is a name sense: "a boy is a kind of Black man", "a satyr is a
    // kind of Greek deity". German capitalises every noun, so the signal
    // exists in English only.
    if (!isDE && promptIsLowercase && w != w.toLowerCase()) continue;
    // The packs list the word among its own hypernyms, which would key
    // "launch" as the answer to "a launch is a kind of what?".
    if (w.toLowerCase() == word.word.toLowerCase()) continue;
    if (catalogue == null) return w;
    final entry = catalogue[w.toLowerCase()];
    // The first hypernym the catalogue confirms, in WordNet's own order —
    // nearest sense first. The packs list hypernyms across every sense with no
    // note of which, so a word the catalogue does not hold cannot be checked
    // at all, and unchecked is where "a show is a kind of affirm" and "an
    // archive is a kind of pull in" come from. Nine in ten words that have
    // hypernyms have one the catalogue confirms, at every grade in both
    // languages, so the game loses little by asking only about those.
    if (entry == null) continue;
    if (namesSomething(entry)) continue;
    if (entry.wordType == word.wordType) return w;
  }
  return null;
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
