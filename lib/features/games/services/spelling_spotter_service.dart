// Pure-function helpers for SpellingSpotter challenge building.
// Extracted so the logic can be unit-tested independently of the widget tree.

/// Normalize morpheme-boundary underscores from LiTKey data.
/// "vorbei_bringen" → "vorbeibringen"
String normWord(String w) => w.replaceAll('_', '');

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
