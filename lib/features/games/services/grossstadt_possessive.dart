// Possessive article agreement for Großstadt-Großschreibung game.
// Extracted for unit-testability.

/// Returns the gender-agreeing possessive form of [basePossessive]
/// ("MEIN" / "DEIN" / "KEIN" / "UNSER") given the normalised definite
/// article of the noun ([nounArticle]: "DER" / "DIE" / "DAS").
///
/// "DIE" covers both feminine singular and all-gender plural — both need
/// the -e ending (e.g. "deine Wange", "deine Wangen").
String getPossessiveArticle(String basePossessive, String nounArticle) {
  if (nounArticle != 'DIE') return basePossessive; // DER and DAS: no -e
  return switch (basePossessive) {
    'MEIN' => 'MEINE',
    'DEIN' => 'DEINE',
    'KEIN' => 'KEINE',
    'UNSER' => 'UNSERE',
    _ => basePossessive,
  };
}
