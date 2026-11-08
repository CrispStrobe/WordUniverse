import '../../../core/models/vocabulary_models.dart';
import 'spelling_spotter_service.dart';

enum RescueSpellingResult { correct, commonMistake, incorrect }

/// The spelling judgement is independent of arcade rewards and hints. A
/// recognisable learner error can receive encouraging feedback, but it is
/// still incorrect evidence for spelling mastery.
RescueSpellingResult evaluateRescueSpelling(
  GermanWord word,
  String response, {
  required bool isGerman,
}) {
  var written = response.trim();
  final article = isGerman ? word.article?.trim() : null;
  if (article != null &&
      article.isNotEmpty &&
      written.toLowerCase().startsWith('${article.toLowerCase()} ')) {
    written = written.substring(article.length + 1).trim();
  }
  final target = word.word.trim();
  final exact = isGerman
      ? written == target
      : written.toLowerCase() == target.toLowerCase();
  if (exact) return RescueSpellingResult.correct;

  final lower = written.toLowerCase();
  if (lower == target.toLowerCase() ||
      word.graphematicVariants.any(
        (variant) => variant.spelling.trim().toLowerCase() == lower,
      ) ||
      parseErrors(
        word.commonMistakes ?? const [],
      ).any((mistake) => mistake.toLowerCase() == lower)) {
    return RescueSpellingResult.commonMistake;
  }
  return RescueSpellingResult.incorrect;
}
