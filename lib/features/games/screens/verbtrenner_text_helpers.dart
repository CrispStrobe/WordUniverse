// lib/features/games/screens/verbtrenner_text_helpers.dart
//
// Pure helpers for the Verb-Trenner game's sentence generation. Kept
// separate from the widget code so they can be unit-tested without a
// Flutter test environment.

/// Find the first accusative noun phrase in [text] of the form
/// `<article> <Noun>` (article one of den/die/das/einen/eine/ein and
/// possessives, noun must start with a capital letter so we don't grab
/// `das im` / `die als` / similar preposition / particle pollution).
///
/// Returns the phrase with a lowercased article (so it reads naturally
/// when spliced mid-sentence), or `null` if no qualifying phrase is found.
String? extractAccusativeObjectPhrase(String text) {
  // Article case-insensitive (handles sentence-start "Die ..."); the
  // following token is captured separately and we verify in code that it
  // starts with a capital letter so case-insensitivity doesn't defeat us.
  final pattern = RegExp(
    r'\b(den|die|das|einen|eine|ein|meinen|meine|mein|deinen|deine|dein|seinen|seine|sein)\s+([\wäöüÄÖÜß]+)\b',
    caseSensitive: false,
  );

  for (final match in pattern.allMatches(text)) {
    final noun = match.group(2);
    if (noun == null || noun.isEmpty) continue;
    final first = noun[0];
    final isCapital =
        first == first.toUpperCase() && first != first.toLowerCase();
    if (!isCapital) continue;

    final phrase = match.group(0)!;
    return phrase[0].toLowerCase() + phrase.substring(1);
  }
  return null;
}
