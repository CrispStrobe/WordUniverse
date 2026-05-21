// test/features/games/verbtrenner_text_helpers_test.dart
//
// Regression tests for the accusative-object-phrase extractor used by
// the Verb-Trenner game's fallback sentence builder. The original bug:
// the regex matched <article>\s+\w+ where \w+ could swallow a
// preposition / particle ("im", "als", "mit") and produce nonsense
// like "Es scheint wichtig, das im vorgetragen zu sein." We now demand
// that the token after the article starts with a capital letter (i.e.
// a real German noun) and try every match in the text before giving up.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/screens/verbtrenner_text_helpers.dart';

void main() {
  group('extractAccusativeObjectPhrase — rejects the original-bug shapes', () {
    test('"das im X" — preposition after article', () {
      expect(
        extractAccusativeObjectPhrase('Er hat das im Vortrag gesagt.'),
        // "im" is rejected; the next candidate is "im Vortrag" but "im"
        // is not in the article list, so falls back to null.
        isNull,
      );
    });

    test('"die als X" — conjunction after article', () {
      expect(
        extractAccusativeObjectPhrase('Sie nennt die als Beispiel angeführten Punkte.'),
        // "als" is lowercase → rejected; no later <article> <Capital> pair.
        isNull,
      );
    });

    test('"ein mit X" — preposition after article', () {
      expect(
        extractAccusativeObjectPhrase('Wir nutzen ein mit Werkzeug ausgestattetes Auto.'),
        // "mit" lowercase → rejected. "Werkzeug" follows "mit" not an
        // article, so no later valid match either.
        isNull,
      );
    });
  });

  group('extractAccusativeObjectPhrase — happy paths', () {
    test('mid-sentence den + Noun', () {
      expect(
        extractAccusativeObjectPhrase('Ich ziehe den Mantel an.'),
        'den Mantel',
      );
    });

    test('mid-sentence eine + Noun', () {
      expect(
        extractAccusativeObjectPhrase('Sie holt eine Jacke aus dem Schrank.'),
        'eine Jacke',
      );
    });

    test('mid-sentence mein + Noun', () {
      expect(
        extractAccusativeObjectPhrase('Ich rufe meinen Bruder an.'),
        'meinen Bruder',
      );
    });

    test('possessive seine + Noun', () {
      expect(
        extractAccusativeObjectPhrase('Er packt seine Sachen ein.'),
        'seine Sachen',
      );
    });
  });

  group('extractAccusativeObjectPhrase — sentence-start articles get lowercased', () {
    test('"Die Kinder" at sentence start → "die Kinder"', () {
      expect(
        extractAccusativeObjectPhrase('Die Kinder regen mich auf.'),
        'die Kinder',
      );
    });

    test('"Den Mantel" at sentence start → "den Mantel"', () {
      expect(
        extractAccusativeObjectPhrase('Den Mantel zieht er an.'),
        'den Mantel',
      );
    });

    test('"Einen Apfel" at sentence start → "einen Apfel"', () {
      expect(
        extractAccusativeObjectPhrase('Einen Apfel isst sie jeden Tag.'),
        'einen Apfel',
      );
    });
  });

  group('extractAccusativeObjectPhrase — junk-then-good still wins', () {
    test('"das im" rejected, later "den Brief" accepted', () {
      expect(
        extractAccusativeObjectPhrase(
            'Sie liest das im Stillen, dann öffnet sie den Brief.'),
        'den Brief',
      );
    });

    test('"die als" rejected, later "das Buch" accepted', () {
      expect(
        extractAccusativeObjectPhrase(
            'Die als Beispiel angeführten Punkte und das Buch werden besprochen.'),
        'das Buch',
      );
    });
  });

  group('extractAccusativeObjectPhrase — edge cases', () {
    test('empty string → null', () {
      expect(extractAccusativeObjectPhrase(''), isNull);
    });

    test('no article in text → null', () {
      expect(
        extractAccusativeObjectPhrase('Wir kommen morgen früh an.'),
        isNull,
      );
    });

    test('article-less noun → null', () {
      expect(
        extractAccusativeObjectPhrase('Schmetterling fliegt davon.'),
        isNull,
      );
    });

    test('article without following noun → null', () {
      expect(
        extractAccusativeObjectPhrase('Den.'),
        isNull,
      );
    });

    test('acronym noun (all caps) accepted', () {
      expect(
        extractAccusativeObjectPhrase('Wir verlassen die EU heute.'),
        'die EU',
      );
    });

    test('noun with umlaut accepted', () {
      expect(
        extractAccusativeObjectPhrase('Sie öffnet die Tür langsam.'),
        'die Tür',
      );
    });

    test('noun with ß accepted', () {
      expect(
        extractAccusativeObjectPhrase('Er überquert die Straße vorsichtig.'),
        'die Straße',
      );
    });
  });

  group('extractAccusativeObjectPhrase — limitations (documented)', () {
    test('adjective between article and noun → no match (acceptable; falls back)', () {
      // Pragmatic limitation: we don't peek past an interposed
      // adjective. Caller will fall back to the "etwas" default in
      // _findOrBuildContext. Better an honest fallback than a
      // gender/case-broken guess.
      expect(
        extractAccusativeObjectPhrase('Er trägt den großen Mantel.'),
        isNull,
      );
    });

    test('dative article (dem/der) — intentionally not matched', () {
      // We only emit accusative phrases because the templates put the
      // phrase in an accusative slot. Dative would produce wrong-case
      // sentences.
      expect(
        extractAccusativeObjectPhrase('Er hilft dem Mann beim Tragen.'),
        isNull,
      );
    });
  });
}
