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

/// Misspellings of a German word that a child plausibly writes, one rule
/// each: the error types a German spelling lesson drills.
///
/// Padding the options with other words' recorded errors put "rrtter",
/// "retzel" and "reten" beside "Rätsel" and "ferstehen" beside "frieren":
/// only one option resembled the word, so the game asked nothing. Each
/// variant here changes one spot by one rule, so every option is the word as
/// somebody might really write it.
List<String> germanMisspellings(String word) {
  final out = <String>{};
  void swap(String from, String to) {
    var start = 0;
    while (true) {
      final i = word.indexOf(from, start);
      if (i < 0) break;
      out.add(word.substring(0, i) + to + word.substring(i + from.length));
      start = i + 1;
    }
  }

  // Umlaut and its spelling by sound.
  swap('äu', 'eu');
  swap('eu', 'äu');
  swap('ä', 'e');
  swap('Ä', 'E');
  // Long i, Dehnungs-h, and the doubled vowel.
  swap('ie', 'i');
  swap('ieh', 'ie');
  for (final v in ['ah', 'eh', 'oh', 'uh', 'äh', 'öh', 'üh']) {
    swap(v, v[0]);
  }
  swap('aa', 'a');
  swap('ee', 'e');
  swap('oo', 'o');
  // s-sounds.
  swap('ß', 'ss');
  swap('ss', 'ß');
  // Doubled consonants, ck and tz.
  for (final c in ['ll', 'mm', 'nn', 'pp', 'rr', 'tt', 'ff']) {
    swap(c, c[0]);
  }
  swap('ck', 'k');
  swap('tz', 'z');
  // Hardening at the end of a word.
  for (final pair in [('d', 't'), ('b', 'p'), ('g', 'k')]) {
    if (word.endsWith(pair.$1)) {
      out.add(word.substring(0, word.length - 1) + pair.$2);
    }
  }
  // v sounds like f.
  if (word.startsWith('v')) out.add('f${word.substring(1)}');
  if (word.startsWith('V')) out.add('F${word.substring(1)}');
  // A single consonant between short-vowel syllables doubled.
  final single = RegExp(r'([aeiouäöü])([lmnprt])([aeiouäöü])');
  for (final m in single.allMatches(word)) {
    out.add(word.substring(0, m.start + 1) +
        m.group(2)! +
        word.substring(m.start + 1));
  }
  // A noun written small, an adjective or verb written capitalised.
  if (word.isNotEmpty) {
    final first = word[0];
    final flipped = first == first.toUpperCase()
        ? first.toLowerCase()
        : first.toUpperCase();
    out.add(flipped + word.substring(1));
  }
  out.remove(word);
  return out.toList();
}
