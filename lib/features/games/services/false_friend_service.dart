// lib/features/games/services/false_friend_service.dart
//
// Challenge-building logic for the False Friends game (EN-only, #48).
// Show an English false-friend word; the player picks its real German meaning.
// The trap distractor is the German look-alike word itself (e.g. for "gift"
// the trap is "Gift" — which a German reader knows is poison). The other
// distractors are real meanings of other false friends.
//
// Pure logic, no DB dependency — data via VocabularyService.getFalseFriends().

import 'dart:math';

import '../models/false_friend.dart';

class FalseFriendChallenge {
  final String english; // "gift"
  final String german; // "Gift" (the look-alike trap)
  final String correctMeaning; // "Geschenk" (englishMeans)
  final List<String> options; // shuffled German meanings, length 2-4
  final int correctIndex;
  final String germanMeans; // "poison" — shown in the explanation

  const FalseFriendChallenge({
    required this.english,
    required this.german,
    required this.correctMeaning,
    required this.options,
    required this.correctIndex,
    required this.germanMeans,
  });
}

/// Builds up to [maxChallenges] false-friend challenges from [friends].
/// Options = correct meaning + the look-alike trap + real meanings of other
/// false friends, de-duped and shuffled.
List<FalseFriendChallenge> buildFalseFriendChallenges({
  required List<FalseFriend> friends,
  int maxChallenges = 15,
  int optionCount = 4,
  Random? rng,
}) {
  final r = rng ?? Random();

  final usable = friends
      .where((f) => f.english.trim().isNotEmpty && f.englishMeans.trim().isNotEmpty)
      .toList();
  if (usable.length < 2) return [];

  // Pool of meanings for filler distractors (deduped, lowercased key).
  final meaningPool = <String>[];
  final seenPool = <String>{};
  for (final f in usable) {
    if (seenPool.add(f.englishMeans.toLowerCase())) {
      meaningPool.add(f.englishMeans);
    }
  }

  final order = List<FalseFriend>.from(usable)..shuffle(r);
  final challenges = <FalseFriendChallenge>[];
  for (final f in order) {
    if (challenges.length >= maxChallenges) break;

    final correct = f.englishMeans.trim();
    final used = <String>{correct.toLowerCase()};
    final options = <String>[correct];

    // The pedagogical trap: the German look-alike word itself.
    final trap = f.german.trim();
    if (trap.isNotEmpty && used.add(trap.toLowerCase())) {
      options.add(trap);
    }

    // Fill the rest with other false friends' meanings.
    final fillers = meaningPool.where((m) => !used.contains(m.toLowerCase())).toList()
      ..shuffle(r);
    for (final m in fillers) {
      if (options.length >= optionCount) break;
      if (used.add(m.toLowerCase())) options.add(m);
    }
    if (options.length < 2) continue;

    options.shuffle(r);
    final correctIndex =
        options.indexWhere((o) => o.toLowerCase() == correct.toLowerCase());
    if (correctIndex < 0) continue;

    challenges.add(FalseFriendChallenge(
      english: f.english,
      german: f.german,
      correctMeaning: correct,
      options: options,
      correctIndex: correctIndex,
      germanMeans: f.germanMeans,
    ));
  }
  return challenges;
}
