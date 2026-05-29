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
  // ── homophones harvested from Wiktionary Verzeichnis:Deutsch/Homophone (CC-BY-SA) + classic confusables, curated 2026-05-29 ──
  ConfusionPair(words: ['Wal', 'Wahl'], meanings: ['großes Tier im Meer', 'eine Entscheidung treffen'], examples: [
    (sentence: 'Im Meer schwimmt ein riesiger ___ vorbei.', answer: 'Wal'),
    (sentence: 'Bei der ___ darf jeder seine Stimme abgeben.', answer: 'Wahl'),
  ]),
  ConfusionPair(words: ['Bad', 'bat'], meanings: ['Raum zum Waschen / Schwimmen', 'Form von bitten'], examples: [
    (sentence: 'Nach dem Sport gehe ich ins ___ und dusche.', answer: 'Bad'),
    (sentence: 'Er ___ seine Mutter um ein Eis.', answer: 'bat'),
  ]),
  ConfusionPair(words: ['rein', 'Rain'], meanings: ['sauber / hinein', 'schmaler Streifen am Feldrand'], examples: [
    (sentence: 'Komm schnell ___ ins warme Haus.', answer: 'rein'),
    (sentence: 'Am ___ zwischen den Feldern wachsen Blumen.', answer: 'Rain'),
  ]),
  ConfusionPair(words: ['Zuname', 'Zunahme'], meanings: ['der Nachname', 'das Mehrwerden'], examples: [
    (sentence: 'Trag deinen Vornamen und deinen ___ ein.', answer: 'Zuname'),
    (sentence: 'Der Arzt freut sich über die ___ an Gewicht.', answer: 'Zunahme'),
  ]),
  ConfusionPair(words: ['Bote', 'Boote'], meanings: ['jemand, der etwas überbringt', 'mehrere kleine Schiffe'], examples: [
    (sentence: 'Der ___ bringt uns ein wichtiges Päckchen.', answer: 'Bote'),
    (sentence: 'Am Steg liegen viele bunte ___ im Wasser.', answer: 'Boote'),
  ]),
  ConfusionPair(words: ['bunt', 'Bund'], meanings: ['viele Farben', 'eine Gruppe / ein Gebinde'], examples: [
    (sentence: 'Im Frühling ist die Wiese ___ und voller Farben.', answer: 'bunt'),
    (sentence: 'Sie kauft einen ___ frische Möhren.', answer: 'Bund'),
  ]),
  ConfusionPair(words: ['hol', 'hohl'], meanings: ['Form von holen', 'innen leer'], examples: [
    (sentence: 'Bitte ___ mir mal das Buch vom Regal.', answer: 'hol'),
    (sentence: 'Der alte Baumstamm ist innen ganz ___.', answer: 'hohl'),
  ]),
  ConfusionPair(words: ['malen', 'mahlen'], meanings: ['ein Bild machen', 'Korn zu Mehl zerkleinern'], examples: [
    (sentence: 'Im Kunstunterricht ___ wir ein buntes Bild.', answer: 'malen'),
    (sentence: 'In der Mühle ___ sie das Korn zu Mehl.', answer: 'mahlen'),
  ]),
  ConfusionPair(words: ['wer', 'Wehr'], meanings: ['Frage nach einer Person', 'Feuerwehr / Stauwerk im Fluss'], examples: [
    (sentence: 'Weißt du, ___ heute Geburtstag hat?', answer: 'wer'),
    (sentence: 'Am Fluss staut ein ___ das Wasser auf.', answer: 'Wehr'),
  ]),
  ConfusionPair(words: ['Wände', 'Wende'], meanings: ['mehrere Mauern eines Raumes', 'Kehrtwende / Drehung'], examples: [
    (sentence: 'Die ___ in meinem Zimmer sind hellblau.', answer: 'Wände'),
    (sentence: 'Beim Schwimmen mache ich an der ___ kehrt.', answer: 'Wende'),
  ]),
  ConfusionPair(words: ['Namen', 'nahmen'], meanings: ['wie jemand heißt', 'Form von nehmen'], examples: [
    (sentence: 'Schreib bitte deinen ___ auf das Blatt.', answer: 'Namen'),
    (sentence: 'Sie ___ sich gestern ein großes Stück Kuchen.', answer: 'nahmen'),
  ]),
  ConfusionPair(words: ['Verben', 'werben'], meanings: ['Tunwörter', 'Reklame machen'], examples: [
    (sentence: 'In dem Satz sollst du alle ___ unterstreichen.', answer: 'Verben'),
    (sentence: 'Die Firma will mit Plakaten für ihr Spielzeug ___.', answer: 'werben'),
  ]),
  ConfusionPair(words: ['ist', 'isst'], meanings: ['Form von sein', 'Form von essen'], examples: [
    (sentence: 'Mein kleiner Bruder ___ erst drei Jahre alt.', answer: 'ist'),
    (sentence: 'Sie ___ am liebsten Nudeln mit Tomatensoße.', answer: 'isst'),
  ]),
  ConfusionPair(words: ['gibt', 'gebt'], meanings: ['er/sie gibt', 'ihr gebt'], examples: [
    (sentence: 'Die Lehrerin ___ uns morgen die Hefte zurück.', answer: 'gibt'),
    (sentence: 'Ihr ___ dem Hund bitte frisches Wasser.', answer: 'gebt'),
  ]),
  ConfusionPair(words: ['nimmt', 'nehmt'], meanings: ['er/sie nimmt', 'ihr nehmt'], examples: [
    (sentence: 'Oma ___ sich noch ein Stück Schokolade.', answer: 'nimmt'),
    (sentence: 'Ihr ___ bitte eure Jacken mit nach draußen.', answer: 'nehmt'),
  ]),
  ConfusionPair(words: ['fährt', 'fahrt'], meanings: ['er/sie fährt', 'ihr fahrt'], examples: [
    (sentence: 'Der Bus ___ jeden Morgen um acht Uhr ab.', answer: 'fährt'),
    (sentence: 'Ihr ___ in den Ferien ans Meer.', answer: 'fahrt'),
  ]),
  ConfusionPair(words: ['Recht', 'recht'], meanings: ['Anspruch / Gesetz', 'richtig / ziemlich'], examples: [
    (sentence: 'Jedes Kind hat ein ___ auf Schule und Spiel.', answer: 'Recht'),
    (sentence: 'Du hast völlig ___, das stimmt genau so.', answer: 'recht'),
  ]),
  ConfusionPair(words: ['Weg', 'weg'], meanings: ['Pfad / Strecke', 'fort / verschwunden'], examples: [
    (sentence: 'Der schmale ___ führt durch den Wald zum See.', answer: 'Weg'),
    (sentence: 'Mein Radiergummi ist plötzlich ___.', answer: 'weg'),
  ]),
  ConfusionPair(words: ['Wagen', 'wagen'], meanings: ['Auto / Fahrzeug', 'sich trauen'], examples: [
    (sentence: 'Vor dem Haus steht ein roter ___.', answer: 'Wagen'),
    (sentence: 'Ich möchte den Sprung vom Brett endlich ___.', answer: 'wagen'),
  ]),
  ConfusionPair(words: ['Leid', 'leid'], meanings: ['großer Kummer', 'in „es tut mir leid"'], examples: [
    (sentence: 'Das große ___ der Familie macht alle traurig.', answer: 'Leid'),
    (sentence: 'Es tut mir sehr ___, dass ich zu spät komme.', answer: 'leid'),
  ]),
  ConfusionPair(words: ['Ofen', 'offen'], meanings: ['Gerät zum Heizen / Backen', 'nicht zu, geöffnet'], examples: [
    (sentence: 'Der Kuchen backt im heißen ___ goldgelb.', answer: 'Ofen'),
    (sentence: 'Das Fenster steht weit ___ und es zieht.', answer: 'offen'),
  ]),
  ConfusionPair(words: ['Bett', 'Beet'], meanings: ['Möbel zum Schlafen', 'Stück Erde für Pflanzen'], examples: [
    (sentence: 'Am Abend kuschle ich mich müde in mein ___.', answer: 'Bett'),
    (sentence: 'Im ___ vor dem Haus blühen rote Tulpen.', answer: 'Beet'),
  ]),
  ConfusionPair(words: ['Tür', 'Tier'], meanings: ['Eingang zu einem Raum', 'Lebewesen wie Hund oder Katze'], examples: [
    (sentence: 'Bitte mach die ___ leise zu, wenn du gehst.', answer: 'Tür'),
    (sentence: 'Das süßeste ___ im Zoo ist für mich der Panda.', answer: 'Tier'),
  ]),
  ConfusionPair(words: ['Nadel', 'Nudel'], meanings: ['spitzes Ding zum Nähen', 'Essen aus Teig'], examples: [
    (sentence: 'Mit ___ und Faden näht Oma den Knopf an.', answer: 'Nadel'),
    (sentence: 'Eine lange ___ rutscht mir von der Gabel.', answer: 'Nudel'),
  ]),
  ConfusionPair(words: ['Kirsche', 'Kirche'], meanings: ['rote süße Frucht', 'Gebäude zum Beten'], examples: [
    (sentence: 'Ich pflücke eine reife rote ___ vom Baum.', answer: 'Kirsche'),
    (sentence: 'Sonntags läuten die Glocken der ___ im Dorf.', answer: 'Kirche'),
  ]),
  ConfusionPair(words: ['Schule', 'Schale'], meanings: ['Ort zum Lernen', 'Hülle einer Frucht / ein Gefäß'], examples: [
    (sentence: 'Jeden Morgen gehe ich mit dem Ranzen zur ___.', answer: 'Schule'),
    (sentence: 'Die ___ der Banane werfe ich in den Müll.', answer: 'Schale'),
  ]),
  ConfusionPair(words: ['singen', 'sinken'], meanings: ['mit der Stimme Töne machen', 'nach unten gehen, untergehen'], examples: [
    (sentence: 'Im Chor ___ wir gemeinsam ein fröhliches Lied.', answer: 'singen'),
    (sentence: 'Das Spielzeugboot beginnt langsam zu ___.', answer: 'sinken'),
  ]),
  ConfusionPair(words: ['Grad', 'Grat'], meanings: ['Maß für Temperatur / Winkel', 'schmaler Bergkamm'], examples: [
    (sentence: 'Heute sind es draußen dreißig ___ im Schatten.', answer: 'Grad'),
    (sentence: 'Die Wanderer gehen vorsichtig über den schmalen ___.', answer: 'Grat'),
  ]),
  ConfusionPair(words: ['Waage', 'wage'], meanings: ['Gerät zum Wiegen', 'Form von wagen'], examples: [
    (sentence: 'Der Apfel liegt auf der ___ und wird gewogen.', answer: 'Waage'),
    (sentence: 'Ich ___ es kaum, vom hohen Turm zu springen.', answer: 'wage'),
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
