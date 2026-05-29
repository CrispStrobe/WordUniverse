// lib/features/games/services/wortfalle_service.dart
//
// "Wortfalle" — German confusables drill (#49, DE-only). The German analogue
// of the EN Word Trap (confusable_drill): a sentence with a blank is shown and
// the player picks the correct member of a classic German confusion pair
// (das/dass, seit/seid, Lärche/Lerche, ...).
//
// Self-contained: each pair carries its own example sentences, so the game
// does NOT depend on the words being present in the vocabulary DB. Pure logic,
// no DB dependency. Pairs are factual orthography (well-known confusions);
// reference: LanguageTool German confusion sets / common-error lists.

import 'dart:math';

/// A classic German confusion pair (occasionally a triple).
class ConfusionPair {
  final List<String> words; // e.g. ['das', 'dass']
  final List<String> meanings; // one short German gloss per word, same order
  // example sentences with the target blanked as "___", + the correct word
  final List<({String sentence, String answer})> examples;

  const ConfusionPair({
    required this.words,
    required this.meanings,
    required this.examples,
  });
}

const wortfalleCatalogue = <ConfusionPair>[
  ConfusionPair(words: ['das', 'dass'], meanings: ['Artikel / Pronomen', 'Konjunktion'], examples: [
    (sentence: 'Ich glaube, ___ es bald regnet.', answer: 'dass'),
    (sentence: 'Wo ist ___ Buch, ___ du suchst?', answer: 'das'),
  ]),
  ConfusionPair(words: ['seit', 'seid'], meanings: ['zeitlich (ab)', 'Form von „sein" (ihr)'], examples: [
    (sentence: 'Wir warten ___ einer Stunde.', answer: 'seit'),
    (sentence: 'Wo ___ ihr gewesen?', answer: 'seid'),
  ]),
  ConfusionPair(words: ['wider', 'wieder'], meanings: ['gegen', 'erneut, nochmal'], examples: [
    (sentence: 'Komm bald ___!', answer: 'wieder'),
    (sentence: 'Das war ___ Erwarten gut.', answer: 'wider'),
  ]),
  ConfusionPair(words: ['Stadt', 'statt'], meanings: ['Ort, Großstadt', 'anstelle von'], examples: [
    (sentence: 'Wir fahren in die ___.', answer: 'Stadt'),
    (sentence: 'Ich nehme Tee ___ Kaffee.', answer: 'statt'),
  ]),
  ConfusionPair(words: ['wahr', 'war'], meanings: ['der Wahrheit entsprechend', 'Form von „sein"'], examples: [
    (sentence: 'Die Geschichte ist ___.', answer: 'wahr'),
    (sentence: 'Er ___ gestern krank.', answer: 'war'),
  ]),
  ConfusionPair(words: ['mehr', 'Meer'], meanings: ['eine größere Menge', 'großes Gewässer'], examples: [
    (sentence: 'Ich möchte ___ Eis.', answer: 'mehr'),
    (sentence: 'Im Sommer baden wir im ___.', answer: 'Meer'),
  ]),
  ConfusionPair(words: ['Lid', 'Lied'], meanings: ['Augenlid', 'Gesang'], examples: [
    (sentence: 'Sie singt ein schönes ___.', answer: 'Lied'),
    (sentence: 'Ein Härchen fiel auf mein ___.', answer: 'Lid'),
  ]),
  ConfusionPair(words: ['Saite', 'Seite'], meanings: ['z. B. an einer Gitarre', 'im Buch / Richtung'], examples: [
    (sentence: 'Eine ___ der Gitarre ist gerissen.', answer: 'Saite'),
    (sentence: 'Lies bitte die nächste ___.', answer: 'Seite'),
  ]),
  ConfusionPair(words: ['Waise', 'Weise'], meanings: ['Kind ohne Eltern', 'Art und Weise / weise'], examples: [
    (sentence: 'Das Kind ist eine ___.', answer: 'Waise'),
    (sentence: 'Sie löste es auf kluge ___.', answer: 'Weise'),
  ]),
  ConfusionPair(words: ['Lärche', 'Lerche'], meanings: ['Nadelbaum', 'Singvogel'], examples: [
    (sentence: 'Die ___ verliert im Winter ihre Nadeln.', answer: 'Lärche'),
    (sentence: 'Die ___ singt früh am Morgen.', answer: 'Lerche'),
  ]),
  ConfusionPair(words: ['Rad', 'Rat'], meanings: ['Fahrrad / Reifen', 'Ratschlag'], examples: [
    (sentence: 'Ich fahre mit dem ___ zur Schule.', answer: 'Rad'),
    (sentence: 'Gib mir bitte einen guten ___.', answer: 'Rat'),
  ]),
  ConfusionPair(words: ['Tod', 'tot'], meanings: ['Nomen (das Sterben)', 'Adjektiv (nicht lebendig)'], examples: [
    (sentence: 'Der kleine Käfer ist ___.', answer: 'tot'),
    (sentence: 'Sie trauerten über den ___ des Hundes.', answer: 'Tod'),
  ]),
  ConfusionPair(words: ['fiel', 'viel'], meanings: ['Form von „fallen"', 'eine große Menge'], examples: [
    (sentence: 'Der Apfel ___ vom Baum.', answer: 'fiel'),
    (sentence: 'Ich habe heute ___ gelernt.', answer: 'viel'),
  ]),
  ConfusionPair(words: ['Leib', 'Laib'], meanings: ['Körper', 'z. B. ein Brot'], examples: [
    (sentence: 'Ein ganzer ___ Brot liegt auf dem Tisch.', answer: 'Laib'),
    (sentence: 'Sie ist mit ___ und Seele dabei.', answer: 'Leib'),
  ]),
  ConfusionPair(words: ['man', 'Mann'], meanings: ['unpersönlich (jemand)', 'erwachsene Person'], examples: [
    (sentence: 'So etwas macht ___ nicht.', answer: 'man'),
    (sentence: 'Der ___ liest die Zeitung.', answer: 'Mann'),
  ]),
  ConfusionPair(words: ['den', 'denn'], meanings: ['Artikel (Akkusativ)', 'weil / Fragewort'], examples: [
    (sentence: 'Ich kenne ___ neuen Lehrer.', answer: 'den'),
    (sentence: 'Wir gehen heim, ___ es ist spät.', answer: 'denn'),
  ]),
  ConfusionPair(words: ['wen', 'wenn'], meanings: ['Fragewort (Akkusativ)', 'falls / sobald'], examples: [
    (sentence: 'Sag mir, ___ du eingeladen hast.', answer: 'wen'),
    (sentence: 'Wir bleiben drinnen, ___ es regnet.', answer: 'wenn'),
  ]),
  ConfusionPair(words: ['Stiel', 'Stil'], meanings: ['z. B. an einer Blume', 'Art zu schreiben/gestalten'], examples: [
    (sentence: 'Der ___ der Blume ist lang und grün.', answer: 'Stiel'),
    (sentence: 'Sie schreibt in einem klaren ___.', answer: 'Stil'),
  ]),
  ConfusionPair(words: ['Lehre', 'Leere'], meanings: ['Ausbildung / Lektion', 'das Leersein'], examples: [
    (sentence: 'Er macht eine ___ als Bäcker.', answer: 'Lehre'),
    (sentence: 'Die gähnende ___ des Raums.', answer: 'Leere'),
  ]),
  ConfusionPair(words: ['in', 'ihn'], meanings: ['Ortspräposition', 'Pronomen (ihn)'], examples: [
    (sentence: 'Ich gehe ___ die Schule.', answer: 'in'),
    (sentence: 'Ich habe ___ dort gesehen.', answer: 'ihn'),
  ]),
  // ── expanded from LanguageTool de/confusion_sets.txt (curated 2026-05-29) ──
  ConfusionPair(words: ['Mine', 'Miene'], meanings: ['Bergwerk / Bleistiftmine', 'Gesichtsausdruck'], examples: [
    (sentence: 'Im Bergwerk arbeiten viele Menschen in der ___.', answer: 'Mine'),
    (sentence: 'Er machte eine finstere ___.', answer: 'Miene'),
  ]),
  ConfusionPair(words: ['Mark', 'Markt'], meanings: ['Knochenmark / frühere Währung', 'Platz zum Einkaufen'], examples: [
    (sentence: 'Auf dem ___ kaufen wir frisches Gemüse.', answer: 'Markt'),
    (sentence: 'In dem Knochen steckt das ___.', answer: 'Mark'),
  ]),
  ConfusionPair(words: ['wie', 'wir'], meanings: ['auf welche Art / Vergleich', 'mehrere Personen, ich und andere'], examples: [
    (sentence: 'Heute gehen ___ zusammen ins Kino.', answer: 'wir'),
    (sentence: 'Weißt du, ___ spät es ist?', answer: 'wie'),
  ]),
  ConfusionPair(words: ['ihm', 'im'], meanings: ['einer Person (Dativ von er)', 'in dem'], examples: [
    (sentence: 'Ich gebe ___ das Buch zurück.', answer: 'ihm'),
    (sentence: 'Die Katze schläft ___ Korb.', answer: 'im'),
  ]),
  ConfusionPair(words: ['im', 'um'], meanings: ['in dem', 'rundherum / zeitlich'], examples: [
    (sentence: 'Wir treffen uns ___ drei Uhr.', answer: 'um'),
    (sentence: 'Die Blumen stehen ___ Garten.', answer: 'im'),
  ]),
  ConfusionPair(words: ['fast', 'fasst'], meanings: ['beinahe', 'greift / packt (von fassen)'], examples: [
    (sentence: 'Ich bin ___ fertig mit den Hausaufgaben.', answer: 'fast'),
    (sentence: 'Sie ___ mutig nach dem Seil.', answer: 'fasst'),
  ]),
  ConfusionPair(words: ['hast', 'hasst'], meanings: ['du besitzt (von haben)', 'du magst gar nicht (von hassen)'], examples: [
    (sentence: 'Du ___ ein neues Fahrrad bekommen.', answer: 'hast'),
    (sentence: 'Warum ___ du Spinat so sehr?', answer: 'hasst'),
  ]),
  ConfusionPair(words: ['liest', 'lies'], meanings: ['er oder sie liest gerade', 'Aufforderung: lies vor!'], examples: [
    (sentence: 'Meine Schwester ___ ein spannendes Buch.', answer: 'liest'),
    (sentence: 'Bitte ___ mir die Geschichte vor!', answer: 'lies'),
  ]),
  ConfusionPair(words: ['Mahl', 'Mal'], meanings: ['Essen / Mahlzeit', 'ein Zeitpunkt, x-mal'], examples: [
    (sentence: 'Das Mittagessen war ein leckeres ___.', answer: 'Mahl'),
    (sentence: 'Wir waren schon ein ___ im Zoo.', answer: 'Mal'),
  ]),
  ConfusionPair(words: ['seht', 'sehr'], meanings: ['ihr seht (von sehen)', 'in hohem Maß, viel'], examples: [
    (sentence: 'Das Eis schmeckt mir ___ gut.', answer: 'sehr'),
    (sentence: 'Schaut mal, ___ ihr den Regenbogen?', answer: 'seht'),
  ]),
  ConfusionPair(words: ['seht', 'sieht'], meanings: ['ihr seht (von sehen)', 'er oder sie sieht'], examples: [
    (sentence: 'Mein Bruder ___ den Vogel im Baum.', answer: 'sieht'),
    (sentence: 'Heute Nacht, ___ ihr die Sterne?', answer: 'seht'),
  ]),
  ConfusionPair(words: ['Stich', 'Strich'], meanings: ['kleine Wunde, z. B. von einer Biene', 'gerade gezeichnete Linie'], examples: [
    (sentence: 'Der ___ der Mücke juckt sehr.', answer: 'Stich'),
    (sentence: 'Mit dem Lineal ziehe ich einen geraden ___.', answer: 'Strich'),
  ]),
  ConfusionPair(words: ['weit', 'weint'], meanings: ['eine große Entfernung', 'er oder sie weint (von weinen)'], examples: [
    (sentence: 'Die Schule ist nicht ___ von hier.', answer: 'weit'),
    (sentence: 'Das Baby ___ laut in der Nacht.', answer: 'weint'),
  ]),
  ConfusionPair(words: ['reist', 'reißt'], meanings: ['er oder sie reist, fährt weg', 'er oder sie reißt, macht kaputt'], examples: [
    (sentence: 'Meine Tante ___ gern nach Italien.', answer: 'reist'),
    (sentence: 'Der Hund ___ an der Leine.', answer: 'reißt'),
  ]),
  ConfusionPair(words: ['Städte', 'Stätte'], meanings: ['mehrere große Orte', 'ein bestimmter Platz / Ort'], examples: [
    (sentence: 'Berlin und Hamburg sind große ___.', answer: 'Städte'),
    (sentence: 'Die alte Burg ist eine geschichtliche ___.', answer: 'Stätte'),
  ]),
];

class WortfalleChallenge {
  final String sentence; // with "___"
  final List<String> options; // the confusion words, shuffled (length 2-3)
  final int correctIndex;
  final List<String> words; // full pair, for the hint row
  final List<String> meanings;

  const WortfalleChallenge({
    required this.sentence,
    required this.options,
    required this.correctIndex,
    required this.words,
    required this.meanings,
  });
}

/// Builds up to [maxChallenges] confusable challenges from [catalogue].
List<WortfalleChallenge> buildWortfalleChallenges({
  int maxChallenges = 15,
  Random? rng,
  List<ConfusionPair>? catalogue,
}) {
  final r = rng ?? Random();
  final cat = List<ConfusionPair>.from(catalogue ?? wortfalleCatalogue)..shuffle(r);

  final out = <WortfalleChallenge>[];
  for (final pair in cat) {
    if (out.length >= maxChallenges) break;
    final exes = List.of(pair.examples)..shuffle(r);
    for (final ex in exes) {
      if (out.length >= maxChallenges) break;
      if (!ex.sentence.contains('___')) continue;
      final correctIndex =
          pair.words.indexWhere((w) => w == ex.answer);
      if (correctIndex < 0) continue; // answer must be one of the pair words
      final options = List<String>.from(pair.words)..shuffle(r);
      out.add(WortfalleChallenge(
        sentence: ex.sentence,
        options: options,
        correctIndex: options.indexWhere((w) => w == ex.answer),
        words: pair.words,
        meanings: pair.meanings,
      ));
    }
  }
  return out;
}
