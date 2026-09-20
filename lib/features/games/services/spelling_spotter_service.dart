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
  // It has to be a plausible *misspelling of this word*. Padding the options
  // with another word's errors gave "Which spelling is correct? tüb / ales /
  // nehbehn / Typ", where only one option even resembles the word.
  final a = candidate.toLowerCase();
  final b = target.toLowerCase();
  if (a.isEmpty || b.isEmpty || a[0] != b[0]) return false;
  return editDistance(a, b) <= (b.length / 2).ceil();
}

/// Levenshtein distance, for judging whether one spelling could be a slip of
/// the other. The words are short; the straightforward table is fine.
int editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      current[j] = [substitution, previous[j] + 1, current[j - 1] + 1]
          .reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
