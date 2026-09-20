// lib/features/games/services/hypernym_flash_service.dart
//
// Hypernym Flash challenge construction, extracted from the screen so it can
// be generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

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

bool _isCleanHypernym(String w, bool isDE) {
  if (w.length < 3) return false;
  final tokens = w.split(' ');
  if (tokens.length > 2) return false;
  if (!isDE && _abstractEnglishVerbs.contains(w.toLowerCase())) return false;
  return true;
}

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
  final hypernyms = word.apiEnrichment?.hypernyms ?? [];
  String? outsideCatalogue;
  for (final h in hypernyms) {
    final w = (h.word ?? '').trim();
    if (!_isCleanHypernym(w, isDE)) continue;
    // The packs list the word among its own hypernyms, which would key
    // "launch" as the answer to "a launch is a kind of what?".
    if (w.toLowerCase() == word.word.toLowerCase()) continue;
    if (catalogue == null) return w;
    final entry = catalogue[w.toLowerCase()];
    if (entry == null) {
      // Remembered, not taken: a hypernym the catalogue holds with the right
      // word type is a better answer, because the learner has met it.
      outsideCatalogue ??= w;
      continue;
    }
    if (namesSomething(entry)) continue;
    if (entry.wordType == word.wordType) return w;
  }
  // Nothing in the catalogue fits. The German pack rarely holds one with the
  // matching word type, and requiring it left the game empty at five of the
  // six grades — an answer the learner has not met beats no game at all.
  return outsideCatalogue;
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
List<HypernymChallenge> buildHypernymChallenges({
  required List<GermanWord> pool,
  required bool isGerman,
  int maxChallenges = 10,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  final catalogue = {
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
