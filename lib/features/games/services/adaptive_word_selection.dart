// lib/features/games/services/adaptive_word_selection.dart
//
// The word selection the six word-practice games share: due review items
// first, then words the learner has not met, then a grade-appropriate fill.
//
// Word Find, Word Snake, Word Memory, Word Builder, Word Sort and Word Type
// Whirl each had their own copy of this, differing only in the counts and in
// which skill's review queue they draw from. Extracted so the selection can be
// reviewed without running a game — see docs/content-audit.md — and so a fix
// to it reaches every game rather than one.

import 'dart:math';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';
export '../../../core/models/sri_item_identity.dart' show baseWordFromSriId;
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../providers/game_provider.dart';

/// Words to practise, adaptively: overdue items, then unseen words, then fill.
///
/// [isPlayable] is the game's own constraint — a length that fits its grid, a
/// word class it can ask about. Words are returned light; hydrate the ones the
/// game will display.
List<GermanWord> selectAdaptiveWords({
  required VocabularyService vocabulary,
  required SriService sri,
  required GameProvider settings,
  required GradeLevel grade,
  required int count,
  required bool Function(GermanWord word) isPlayable,
  LanguageSkillType? skillFilter,
  double reviewShare = 0.5,
  int? reviewQueueLimit,
  // Seeded by the audit harness so a dumped round can be reproduced; the
  // games leave it null and get a different fill every session.
  Random? rng,
}) {
  final selected = <GermanWord>[];
  final takenIds = <String>{};

  bool offer(GermanWord word) {
    if (selected.length >= count) return false;
    if (takenIds.contains(word.id)) return false;
    // Names are not vocabulary to practise: the catalogue carries them
    // untyped, so "barbara" was being offered as a word to find in a grid.
    if (word.isProperNoun || namesSomething(word)) return false;
    if (!isPlayable(word)) return false;
    selected.add(word);
    takenIds.add(word.id);
    return true;
  }

  // 1. Words the learner is due to review, oldest due first. A game that
  // does not specify its skill defaults to spelling, never another skill's
  // queue that it cannot actually review.
  final reviewTarget = (count * reviewShare).ceil();
  final reviewIds = sri.getItemsForReview(
    limit: reviewQueueLimit ?? reviewTarget * 2,
    skillTypeFilter: skillFilter ?? LanguageSkillType.spelling,
    gradeLevelFilter: grade.index + 1,
    markReturned: false,
  );
  for (final id in reviewIds) {
    if (selected.length >= reviewTarget) break;
    final item = sri.getItemData(id);
    if (item == null) continue;
    // Indexed lookup: this used to scan the whole catalogue per review item.
    final word = vocabulary.findByReviewItem(item);
    if (word != null && word.gradeLevel == grade.index + 1 && offer(word)) {
      sri.markItemsReturned([id]);
    }
  }

  // 2. Words not studied yet, at this grade.
  for (final word in vocabulary.getNewWords(
    sriService: sri,
    grade: grade,
    limit: (count - selected.length) * 2,
    settingsProvider: settings,
    skillType: skillFilter ?? LanguageSkillType.spelling,
    rng: rng,
  )) {
    if (selected.length >= count) break;
    offer(word);
  }

  // 3. Anything else at this grade, so a thin review queue never shortens the
  //    game.
  if (selected.length < count) {
    final fill = vocabulary.getWordsByGrade(grade, settings)..shuffle(rng);
    for (final word in fill) {
      if (selected.length >= count) break;
      offer(word);
    }
  }

  return selected;
}
