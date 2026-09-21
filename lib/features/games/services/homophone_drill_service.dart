// lib/features/games/services/homophone_drill_service.dart
//
// Data and challenge-building logic for the Homophone Drill (#38) and
// Confusable Drill (#40) games.
// HomophoneGroup is shared by both catalogues; HomophoneGameMode selects
// which catalogue to use.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

// ─── Homophone catalogue ──────────────────────────────────────────────────────

class HomophoneGroup {
  final List<String> words;
  final List<String> meanings; // one short gloss per word, same order

  const HomophoneGroup({required this.words, required this.meanings});
}

const homophoneGroups = <HomophoneGroup>[
  // Grade 1-2 core homophones
  HomophoneGroup(
    words: ['to', 'too', 'two'],
    meanings: ['preposition / towards', 'also; excessively', 'the number 2'],
  ),
  HomophoneGroup(
    words: ['there', 'their'],
    meanings: ['that place / exists', 'belonging to them'],
  ),
  HomophoneGroup(
    words: ['hear', 'here'],
    meanings: ['perceive with ears', 'at this place'],
  ),
  HomophoneGroup(
    words: ['know', 'no'],
    meanings: ['to be aware of', 'negative / refusal'],
  ),
  HomophoneGroup(
    words: ['see', 'sea'],
    meanings: ['perceive with eyes', 'large body of salt water'],
  ),
  HomophoneGroup(
    words: ['son', 'sun'],
    meanings: ['male child', 'the star at centre of solar system'],
  ),
  HomophoneGroup(
    words: ['by', 'buy'],
    meanings: ['near / past / through', 'to purchase'],
  ),
  HomophoneGroup(
    words: ['new', 'knew'],
    meanings: ['recently made / just begun', 'past tense of know'],
  ),
  // Grade 2-3
  HomophoneGroup(
    words: ['write', 'right'],
    meanings: ['to form letters / author', 'correct; opposite of left'],
  ),
  HomophoneGroup(
    words: ['meet', 'meat'],
    meanings: ['to encounter someone', 'animal flesh as food'],
  ),
  HomophoneGroup(
    words: ['weak', 'week'],
    meanings: ['not strong', 'seven days'],
  ),
  HomophoneGroup(
    words: ['bear', 'bare'],
    meanings: ['the large mammal; to carry', 'uncovered; plain; empty'],
  ),
  HomophoneGroup(
    words: ['brake', 'break'],
    meanings: ['device to slow a vehicle', 'to shatter; a pause / rest'],
  ),
  HomophoneGroup(
    words: ['flour', 'flower'],
    meanings: ['ground grain for baking', 'the bloom of a plant'],
  ),
  HomophoneGroup(
    words: ['mail', 'male'],
    meanings: ['post / letters delivered', 'the masculine sex'],
  ),
  HomophoneGroup(
    words: ['tale', 'tail'],
    meanings: ['a story', 'rear appendage of an animal'],
  ),
  HomophoneGroup(
    words: ['plain', 'plane'],
    meanings: ['simple; flat grassland', 'aircraft; flat surface'],
  ),
  HomophoneGroup(
    words: ['sail', 'sale'],
    meanings: ['canvas to catch the wind', 'selling at reduced price'],
  ),
  // Grade 3-4
  HomophoneGroup(
    words: ['peace', 'piece'],
    meanings: ['absence of war; calm', 'a portion or part'],
  ),
  HomophoneGroup(
    words: ['hole', 'whole'],
    meanings: ['an opening or gap', 'complete; entire'],
  ),
  HomophoneGroup(
    words: ['pair', 'pear'],
    meanings: ['two matching things', 'the sweet fruit'],
  ),
  HomophoneGroup(
    words: ['night', 'knight'],
    meanings: ['hours of darkness', 'armoured warrior; chess piece'],
  ),
  HomophoneGroup(
    words: ['wear', 'where'],
    meanings: ['to have on one\'s body', 'at or in what place'],
  ),
  HomophoneGroup(
    words: ['weather', 'whether'],
    meanings: ['atmospheric conditions', 'introducing an alternative'],
  ),
  HomophoneGroup(
    words: ['allowed', 'aloud'],
    meanings: ['permitted', 'spoken out loud; audibly'],
  ),
  // Grade 4-5
  HomophoneGroup(
    words: ['role', 'roll'],
    meanings: ['a part played; function', 'to turn over; bread roll'],
  ),
  HomophoneGroup(
    words: ['road', 'rode'],
    meanings: ['a paved route', 'past tense of ride'],
  ),
  HomophoneGroup(
    words: ['four', 'for'],
    meanings: ['the number 4', 'in favour of; intended for'],
  ),
];

// ─── Confusable catalogue (#40) ───────────────────────────────────────────────
//
// Words that are commonly confused not because they sound the same but because
// they are semantically similar, have overlapping spellings, or are used
// interchangeably by mistake. All entries verified present in the EN DB.

const confusableGroups = <HomophoneGroup>[
  // Spelling traps (look-alikes)
  HomophoneGroup(
    words: ['lose', 'loose'],
    meanings: ['to fail to keep; to be defeated', 'not tight; free; not confined'],
  ),
  HomophoneGroup(
    words: ['than', 'then'],
    meanings: ['used for comparisons (bigger than)', 'relating to time (first…then)'],
  ),
  HomophoneGroup(
    words: ['bought', 'brought'],
    meanings: ['past tense of buy (purchased)', 'past tense of bring (carried here)'],
  ),
  HomophoneGroup(
    words: ['desert', 'dessert'],
    meanings: ['dry sandy landscape; to abandon', 'sweet food eaten after a meal'],
  ),
  // Verb/noun pairs
  HomophoneGroup(
    words: ['advice', 'advise'],
    meanings: ['noun: a recommendation', 'verb: to recommend or counsel'],
  ),
  HomophoneGroup(
    words: ['affect', 'effect'],
    meanings: ['verb: to influence something', 'noun: the result or outcome'],
  ),
  // Semantic confusables
  HomophoneGroup(
    words: ['fewer', 'less'],
    meanings: ['for countable things (fewer apples)', 'for uncountable things (less water)'],
  ),
  HomophoneGroup(
    words: ['further', 'farther'],
    meanings: ['abstract or figurative distance (study further)', 'physical measurable distance'],
  ),
  HomophoneGroup(
    words: ['lay', 'lie'],
    meanings: ['to put something down (lay the book)', 'to recline or rest (lie on the bed)'],
  ),
  HomophoneGroup(
    words: ['imply', 'infer'],
    meanings: ['speaker suggests without stating (he implied)', 'listener concludes from evidence (I infer)'],
  ),
  HomophoneGroup(
    words: ['ensure', 'assure'],
    meanings: ['to make certain something happens', 'to tell someone confidently; to reassure'],
  ),
  HomophoneGroup(
    words: ['principal', 'principle'],
    meanings: ['the head of a school; main (principal reason)', 'a fundamental rule or belief'],
  ),
  HomophoneGroup(
    words: ['complement', 'compliment'],
    meanings: ['to complete or go well with something', 'to praise or express admiration'],
  ),
  HomophoneGroup(
    words: ['accept', 'except'],
    meanings: ['to receive willingly; to agree to', 'excluding; not including'],
  ),
  HomophoneGroup(
    words: ['practice', 'practise'],
    meanings: ['noun: a session of rehearsal or training', 'verb: to rehearse or do repeatedly'],
  ),
  HomophoneGroup(
    words: ['continual', 'continuous'],
    meanings: ['repeatedly occurring with breaks (continual interruptions)', 'without any interruption (continuous noise)'],
  ),
  HomophoneGroup(
    words: ['historic', 'historical'],
    meanings: ['famous or important in history (a historic day)', 'relating to past events (historical records)'],
  ),
];

// ─── Game mode ────────────────────────────────────────────────────────────────

enum HomophoneGameMode { homophones, confusables }

List<HomophoneGroup> groupsForMode(HomophoneGameMode mode) =>
    mode == HomophoneGameMode.homophones ? homophoneGroups : confusableGroups;

// ─── Challenge model ──────────────────────────────────────────────────────────

class HomophoneChallenge {
  final String correctWord;
  final String sentence; // e.g. "I go ___ school."
  final List<String> options; // shuffled, length 2-3
  final int correctIndex;
  final List<String> groupWords;   // full group for the hint row
  final List<String> groupMeanings;

  const HomophoneChallenge({
    required this.correctWord,
    required this.sentence,
    required this.options,
    required this.correctIndex,
    required this.groupWords,
    required this.groupMeanings,
  });
}

// ─── Challenge builder ────────────────────────────────────────────────────────

/// Returns up to [maxChallenges] challenges drawn from [allWords] at the
/// given [gradeLevel] (1-6). [groups] defaults to [homophoneGroups]; pass
/// [confusableGroups] for the Word Trap mode.
List<HomophoneChallenge> buildHomophoneChallenges({
  required List<GermanWord> allWords,
  required int gradeLevel,
  int maxChallenges = 15,
  Random? rng,
  List<HomophoneGroup>? groups,
}) {
  final r = rng ?? Random();
  final byWord = <String, GermanWord>{};
  for (final w in allWords) {
    byWord[w.word.toLowerCase()] = w;
  }

  final catalogue = groups ?? homophoneGroups;

  // Collect all viable groups (all members found in DB).
  final viableGroups = catalogue.where((g) {
    return g.words.every((w) => byWord.containsKey(w.toLowerCase()));
  }).toList();

  // Build one or more challenges per viable group.
  final challenges = <HomophoneChallenge>[];
  final shuffledGroups = List<HomophoneGroup>.from(viableGroups)..shuffle(r);

  for (final group in shuffledGroups) {
    if (challenges.length >= maxChallenges) break;
    // For each word in the group, try to build a challenge using its examples.
    final wordOrder = List.of(group.words)..shuffle(r);
    for (final targetWord in wordOrder) {
      if (challenges.length >= maxChallenges) break;
      final entry = byWord[targetWord.toLowerCase()];
      if (entry == null) continue;

      final sentence = _pickSentence(entry, gradeLevel, targetWord);
      if (sentence == null) continue;

      final options = List.of(group.words)..shuffle(r);
      // Preserve capitalisation of the first word if sentence starts with it.
      final correctIndex = options.indexWhere(
          (o) => o.toLowerCase() == targetWord.toLowerCase());
      if (correctIndex < 0) continue;

      challenges.add(HomophoneChallenge(
        correctWord: targetWord,
        sentence: sentence,
        options: options,
        correctIndex: correctIndex,
        groupWords: group.words,
        groupMeanings: group.meanings,
      ));
    }
  }
  return challenges;
}

/// Picks a grade-appropriate example sentence from [entry] and replaces the
/// target word with "___". Returns null if no suitable sentence is found.
String? _pickSentence(GermanWord entry, int gradeLevel, String targetWord) {
  final examples = entry.apiEnrichment?.gradeExamples;
  if (examples == null || examples.isEmpty) return null;

  // Try the requested grade first, then adjacent grades, then any grade.
  final gradesToTry = _gradeSearchOrder(gradeLevel);
  for (final g in gradesToTry) {
    final key = '$g';
    final sentences = examples[key];
    if (sentences == null || sentences.isEmpty) continue;
    for (final raw in sentences) {
      if (!looksLikeAWholeSentence(raw)) continue;
      final blanked = _blankWord(raw, targetWord);
      if (blanked != null) return blanked;
    }
  }
  return null;
}

/// Replaces the first occurrence of [word] (case-insensitive) with "___".
/// Returns null if the word does not appear in the sentence.
String? _blankWord(String sentence, String word) {
  final lower = sentence.toLowerCase();
  final target = word.toLowerCase();
  final idx = lower.indexOf(target);
  if (idx < 0) return null;
  // Only accept whole-word matches (not "two" inside "towards").
  final before = idx > 0 ? lower[idx - 1] : ' ';
  final after = idx + target.length < lower.length
      ? lower[idx + target.length]
      : ' ';
  if (_isWordChar(before) || _isWordChar(after)) return null;

  final blanked = sentence.substring(0, idx) +
      '___' +
      sentence.substring(idx + word.length);
  return blanked.trim();
}

bool _isWordChar(String c) =>
    RegExp(r"[a-zA-Z0-9']").hasMatch(c);

List<int> _gradeSearchOrder(int grade) {
  final result = <int>[grade];
  for (var d = 1; d <= 5; d++) {
    if (grade - d >= 1) result.add(grade - d);
    if (grade + d <= 6) result.add(grade + d);
  }
  return result;
}
