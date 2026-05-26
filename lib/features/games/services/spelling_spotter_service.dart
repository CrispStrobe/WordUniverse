// Pure-function helpers for SpellingSpotter challenge building.
// Extracted so the logic can be unit-tested independently of the widget tree.

import '../../../core/models/vocabulary_models.dart';

/// Returns a 0–1 difficulty score used to sort the SpellingSpotter word pool.
///
/// DE: LiTKey empirical child-error rate; null → 0.5 (neutral, no data).
/// EN: Norvig/Wikipedia misspelling variant count, normalised with cap 20.
///     0 variants → 0.3 (probably easy, not "no data"); 20+ → 1.0 (hardest).
double spellingDifficultyScore(GermanWord w, {required bool isDE}) {
  if (isDE) return w.litekeyErrorRate ?? 0.5;
  final count = w.apiEnrichment?.commonLearnerErrors.length ?? 0;
  return count == 0 ? 0.3 : (count / 20.0).clamp(0.0, 1.0);
}

/// Normalize morpheme-boundary underscores and utterance-boundary pipes from
/// LiTKey data. "vorbei_bringen" → "vorbeibringen"; "ab|" → "ab"
String normWord(String w) => w.replaceAll('_', '').replaceAll('|', '');

/// Split comma-separated error entries into individual tokens.
/// "ihn, in" → ["ihn", "in"]
List<String> parseErrors(List<String> raw) => raw
    .expand((e) => e.split(',').map((s) => s.trim()))
    .where((e) => e.isNotEmpty)
    .toList();

/// Returns true when [candidate] is a plausible distractor for [target]:
/// • single token (no spaces, underscores, or commas)
/// • length within [maxLenDelta] characters of target
/// • not itself a valid vocabulary word (i.e. not in [validWords])
/// • not the target itself
bool isDistractorPlausible(
  String candidate,
  String target, {
  required Set<String> validWords,
  int maxLenDelta = 4,
}) {
  if (candidate.isEmpty) return false;
  if (candidate == target) return false;
  if (candidate.contains(' ') ||
      candidate.contains('_') ||
      candidate.contains(',')) return false;
  if ((candidate.length - target.length).abs() > maxLenDelta) return false;
  if (validWords.contains(candidate.toLowerCase())) return false;
  return true;
}
