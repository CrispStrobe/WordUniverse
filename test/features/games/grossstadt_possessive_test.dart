// test/features/games/grossstadt_possessive_test.dart
//
// Unit tests for getPossessiveArticle — the function that derives the
// gender-agreeing possessive form ("MEIN"/"DEIN"/"KEIN"/"UNSER") from
// the noun's definite article ("DER"/"DIE"/"DAS").
//
// Bug being guarded: plural/feminine nouns stored without an article in
// the DB were falling back to DAS (neuter) → "DEIN Wangen" instead of
// "DEINE Wangen".

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/services/grossstadt_possessive.dart';

void main() {
  // ─── DIE — feminine singular + all-gender plural ─────────────────────────

  group('DIE nouns (feminine + plural) → -e ending', () {
    test('MEIN + DIE → MEINE  (die Wange → meine Wange)', () {
      expect(getPossessiveArticle('MEIN', 'DIE'), 'MEINE');
    });

    test('DEIN + DIE → DEINE  (die Wange → deine Wange)', () {
      expect(getPossessiveArticle('DEIN', 'DIE'), 'DEINE');
    });

    test('KEIN + DIE → KEINE  (die Katze → keine Katze)', () {
      expect(getPossessiveArticle('KEIN', 'DIE'), 'KEINE');
    });

    test('UNSER + DIE → UNSERE  (die Schule → unsere Schule)', () {
      expect(getPossessiveArticle('UNSER', 'DIE'), 'UNSERE');
    });

    test('plural "die Wangen" also gets -e ending via DIE article', () {
      // The fix: plural nouns use "die" as their definite article; the
      // possessive must agree: "deine Wangen" not "dein Wangen".
      expect(getPossessiveArticle('DEIN', 'DIE'), 'DEINE');
    });

    test('plural "die Kinder" → "unsere Kinder" (UNSER + DIE)', () {
      expect(getPossessiveArticle('UNSER', 'DIE'), 'UNSERE');
    });
  });

  // ─── DER — masculine: no -e ending ───────────────────────────────────────

  group('DER nouns (masculine) → no ending change', () {
    test('MEIN + DER → MEIN  (der Tisch → mein Tisch)', () {
      expect(getPossessiveArticle('MEIN', 'DER'), 'MEIN');
    });

    test('DEIN + DER → DEIN  (der Hund → dein Hund)', () {
      expect(getPossessiveArticle('DEIN', 'DER'), 'DEIN');
    });

    test('KEIN + DER → KEIN  (der Fehler → kein Fehler)', () {
      expect(getPossessiveArticle('KEIN', 'DER'), 'KEIN');
    });

    test('UNSER + DER → UNSER  (der Lehrer → unser Lehrer)', () {
      expect(getPossessiveArticle('UNSER', 'DER'), 'UNSER');
    });
  });

  // ─── DAS — neuter: no -e ending ──────────────────────────────────────────

  group('DAS nouns (neuter) → no ending change', () {
    test('MEIN + DAS → MEIN  (das Haus → mein Haus)', () {
      expect(getPossessiveArticle('MEIN', 'DAS'), 'MEIN');
    });

    test('DEIN + DAS → DEIN  (das Kind → dein Kind)', () {
      expect(getPossessiveArticle('DEIN', 'DAS'), 'DEIN');
    });

    test('KEIN + DAS → KEIN  (das Problem → kein Problem)', () {
      expect(getPossessiveArticle('KEIN', 'DAS'), 'KEIN');
    });

    test('UNSER + DAS → UNSER  (das Haus → unser Haus)', () {
      expect(getPossessiveArticle('UNSER', 'DAS'), 'UNSER');
    });
  });

  // ─── Fallback / unknown article ──────────────────────────────────────────

  group('unknown article → no change (safe fallback)', () {
    test('empty article string → base form returned unchanged', () {
      expect(getPossessiveArticle('DEIN', ''), 'DEIN');
    });

    test('unknown article "EIN" → base form unchanged', () {
      // Normalisation ensures only DER/DIE/DAS reach this function;
      // anything else should not mutate the possessive.
      expect(getPossessiveArticle('MEIN', 'EIN'), 'MEIN');
    });

    test('unknown base possessive with DIE → returned unchanged', () {
      // Future-proof: an unrecognised possessive passes through.
      expect(getPossessiveArticle('EUER', 'DIE'), 'EUER');
    });
  });
}
