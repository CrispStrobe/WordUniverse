// lib/core/services/custom_licenses_registry.dart
//
// Idempotent registration of custom LicenseEntry items for fonts, data
// sources, and bundled libraries. Flutter's showLicensePage() pulls from
// the global LicenseRegistry, so any screen that opens the license page
// must first call ensureCustomLicensesRegistered() to make these entries
// available alongside the auto-discovered pub-package licenses.
//
// The body was extracted from settings_screen.dart's _addCustomLicenses
// so it can be shared with the imprint dialog.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

bool _customLicensesAdded = false;

Future<void> ensureCustomLicensesRegistered() async {
  if (_customLicensesAdded) return;
  try {
    // 1. Load the common OFL.txt file for fonts
    final oflLicense = await rootBundle.loadString('assets/fonts/OFL.txt');

    // ==================== FONT LICENSES ====================

    // 2. Add license for Grundschrift (Unique Author)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Grundschrift'],
          'Credit: Christian Urff\n'
          'License: SIL Open Font License, Version 1.1\n\n'
          '------------------------------------\n\n'
          '$oflLicense',
        ),
      ]);
    });

    // 3. Add license for Didact Gothic (Unique Authors)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['DidactGothic'],
          'Authors: Daniel Johnson, Cyreal\n'
          'License: SIL Open Font License, Version 1.1\n\n'
          '------------------------------------\n\n'
          '$oflLicense',
        ),
      ]);
    });

    // 4. Add license for LetsTrace (Unique Author)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['LetsTrace'],
          'Author: James Kilfiger\n'
          'License: SIL Open Font License, Version 1.1\n\n'
          '------------------------------------\n\n'
          '$oflLicense',
        ),
      ]);
    });

    // 5. Add license for SASBienchen
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['SASBienchen'],
          'License: SIL Open Font License, Version 1.1\n\n'
          '------------------------------------\n\n'
          '$oflLicense',
        ),
      ]);
    });

    // 6. Add all Peter Wiegel fonts
    final peterWiegelFonts = [
      'BernerBasisschrift',
      'EuroScript',
      'Gruenewald',
      'SchulfibelNord',
      'Schulkursiv',
      'SimplePrint',
    ];

    final peterWiegelLicense = 'Author: Peter Wiegel\n'
        'License: SIL Open Font License, Version 1.1\n\n'
        '------------------------------------\n\n'
        '$oflLicense';

    for (final fontFamily in peterWiegelFonts) {
      LicenseRegistry.addLicense(() {
        return Stream<LicenseEntry>.fromIterable([
          LicenseEntryWithLineBreaks(
            [fontFamily],
            peterWiegelLicense,
          ),
        ]);
      });
    }

    // ==================== DATA SOURCE LICENSES ====================

    // 7. Wiktionary (Updated to CC-BY-SA 4.0)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Wiktionary'],
          'Source: Wiktionary (https://www.wiktionary.org/)\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://creativecommons.org/licenses/by-sa/4.0/\n\n'
          'This work contains data from Wiktionary, which is made available under the '
          'Creative Commons Attribution-ShareAlike 4.0 International License.\n\n'
          'Under CC BY-SA 4.0, you are free to:\n'
          '• Share — copy and redistribute the material in any medium or format for any purpose, even commercially\n'
          '• Adapt — remix, transform, and build upon the material for any purpose, even commercially\n\n'
          'Under the following terms:\n'
          '• Attribution — You must give appropriate credit, provide a link to the license, '
          'and indicate if changes were made. You may do so in any reasonable manner, but not in any way '
          'that suggests the licensor endorses you or your use.\n'
          '• ShareAlike — If you remix, transform, or build upon the material, you must distribute '
          'your contributions under the same license as the original.\n'
          '• No additional restrictions — You may not apply legal terms or technological measures '
          'that legally restrict others from doing anything the license permits.\n\n'
          'To view the full license, visit: https://creativecommons.org/licenses/by-sa/4.0/legalcode',
        ),
      ]);
    });

    // 8. OdeNet (Open German WordNet)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['OdeNet'],
          'Source: OdeNet - Open German WordNet\n'
          'Authors: Universität Hamburg, Language Technology Group\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://creativecommons.org/licenses/by-sa/4.0/\n\n'
          'This work contains data from OdeNet, which is made available under the '
          'Creative Commons Attribution-ShareAlike 4.0 International License.\n\n'
          'Under CC BY-SA 4.0, you are free to:\n'
          '• Share — copy and redistribute the material in any medium or format for any purpose, even commercially\n'
          '• Adapt — remix, transform, and build upon the material for any purpose, even commercially\n\n'
          'Under the following terms:\n'
          '• Attribution — You must give appropriate credit, provide a link to the license, '
          'and indicate if changes were made.\n'
          '• ShareAlike — If you remix, transform, or build upon the material, you must distribute '
          'your contributions under the same license as the original.\n'
          '• No additional restrictions — You may not apply legal terms or technological measures '
          'that legally restrict others from doing anything the license permits.',
        ),
      ]);
    });

    // 9. ConceptNet
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['ConceptNet'],
          'Source: ConceptNet 5\n'
          'Authors: Luminoso Technologies, Inc. and contributors\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://creativecommons.org/licenses/by-sa/4.0/\n'
          'Project URL: https://conceptnet.io/\n\n'
          'ConceptNet is a multilingual knowledge graph that connects words and phrases of natural '
          'language with labeled edges. This work uses data from ConceptNet 5.\n\n'
          'Under CC BY-SA 4.0, you are free to:\n'
          '• Share — copy and redistribute the material in any medium or format for any purpose, even commercially\n'
          '• Adapt — remix, transform, and build upon the material for any purpose, even commercially\n\n'
          'Under the following terms:\n'
          '• Attribution — You must give appropriate credit, provide a link to the license, '
          'and indicate if changes were made.\n'
          '• ShareAlike — If you remix, transform, or build upon the material, you must distribute '
          'your contributions under the same license as the original.\n'
          '• No additional restrictions — You may not apply legal terms or technological measures '
          'that legally restrict others from doing anything the license permits.',
        ),
      ]);
    });

    // 9b. OpenThesaurus
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['OpenThesaurus'],
          'Source: OpenThesaurus (https://www.openthesaurus.de/)\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://creativecommons.org/licenses/by-sa/4.0/\n\n'
          'OpenThesaurus is a free German thesaurus. Synonym, hypernym and hyponym '
          'relations from OpenThesaurus are included in this app\'s enrichment data.\n\n'
          'Changes made: The original OpenThesaurus database has been filtered to the '
          'subset of headwords present in this app, and the structured fields have been '
          'reshaped to fit this app\'s enrichment schema.\n\n'
          'Under CC BY-SA 4.0 the same redistribution and ShareAlike conditions apply '
          'as for the other CC BY-SA sources listed in this license page.',
        ),
      ]);
    });

    // 9c. HermitDave FrequencyWords (derived from OpenSubtitles 2018)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['HermitDave FrequencyWords'],
          'Source: HermitDave FrequencyWords (https://github.com/hermitdave/FrequencyWords)\n'
          'Underlying corpus: OpenSubtitles 2018 (http://opus.nlpl.eu/OpenSubtitles2018.php)\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://creativecommons.org/licenses/by-sa/4.0/\n\n'
          'Word-frequency rank and count fields in this app\'s `frequencyData` are '
          'derived from the HermitDave FrequencyWords project, which is itself derived '
          'from the OpenSubtitles 2018 parallel corpus.\n\n'
          'Changes made: Frequency data has been truncated to the top 10,000 ranks per '
          'language and reshaped into integer rank + count fields.\n\n'
          'Under CC BY-SA 4.0 the same redistribution and ShareAlike conditions apply.',
        ),
      ]);
    });

    // 9d. Universität Leipzig Wortschatz
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Leipzig Corpora Collection'],
          'Source: Wortschatz Leipzig (https://wortschatz.uni-leipzig.de/)\n'
          'Authors: Universität Leipzig, Abteilung Automatische Sprachverarbeitung\n'
          'License: Creative Commons Attribution 4.0 International (CC BY 4.0) for the '
          'redistributable wordlists; full Leipzig Corpora Collection is subject to '
          'individual per-corpus licenses (some include Non-Commercial clauses for the '
          'underlying text corpora).\n'
          'URL: https://creativecommons.org/licenses/by/4.0/\n\n'
          'The frequency ranks contributed by Leipzig\'s "Häufigkeitsklassen" are '
          'included as one of several frequency signals fed into the consolidation '
          'pipeline. Only the rank/frequency-class data (which is purely numeric and '
          'considered facts under EU database-right doctrine) is shipped with this app; '
          'no raw Leipzig text corpus is included.\n\n'
          'Citation: Quasthoff, U., Richter, M., Biemann, C. (2006). Corpus Portal for '
          'Search in Monolingual Corpora. In: Proceedings of the LREC 2006 conference.',
        ),
      ]);
    });

    // 9e. NRW Grundwortschatz / Merkwörter / Nachdenkwörter
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['NRW Grundwortschatz'],
          'Source: Ministerium für Schule und Bildung des Landes Nordrhein-Westfalen\n'
          'URL: https://www.schulministerium.nrw/\n'
          'Publications referenced:\n'
          '  • Grundwortschatz für die Grundschule (Klassen 1-2 und 3-4)\n'
          '  • 111 Merkwörter\n'
          '  • 422 Nachdenkwörter\n\n'
          'These wordlists, published by the State of North Rhine-Westphalia for '
          'educational use, form the pedagogical core of the German vocabulary in '
          'this app. They are official curriculum documents intended for use in German '
          'primary schools and are distributed for educational purposes.\n\n'
          'Changes made: The lists have been merged with other pedagogical and '
          'frequency-based sources, deduplicated, and tagged with a normalized grade '
          'level per word. Each word retains a tag indicating which NRW list (if any) '
          'it originated from.',
        ),
      ]);
    });

    // 9g. Wikipedia (general, separate from Wiktionary)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Wikipedia'],
          'Source: Wikipedia (https://www.wikipedia.org/)\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://creativecommons.org/licenses/by-sa/4.0/\n\n'
          'The list of commonly misspelled English words, used to seed the '
          'commonLearnerErrors field for the English vocabulary, is derived from '
          'Wikipedia\'s "Lists of common misspellings" (Wikipedia namespace), '
          'published under CC BY-SA 4.0.\n\n'
          'Changes made: Parsed from the "For machines" subpage flat-list format into '
          'normalized correct/wrong pairs.\n\n'
          'Under CC BY-SA 4.0 the same redistribution and ShareAlike conditions apply '
          'as for the other CC BY-SA sources listed in this license page.',
        ),
      ]);
    });

    // 9h-extra. DWDS Goethe-Zertifikat vocabulary lists (A1/A2/B1)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['DWDS - Goethe-Zertifikat Wortschatz (A1/A2/B1)'],
          'Source: DWDS - Digitales Wörterbuch der deutschen Sprache\n'
          '        (Berlin-Brandenburgische Akademie der Wissenschaften)\n'
          'URLs:\n'
          '  • https://www.dwds.de/lemma/wortschatz-goethe-zertifikat/A1\n'
          '  • https://www.dwds.de/lemma/wortschatz-goethe-zertifikat/A2\n'
          '  • https://www.dwds.de/lemma/wortschatz-goethe-zertifikat/B1\n'
          'Underlying lists: Goethe-Institut e.V. - Goethe-Zertifikat exam '
          'preparation vocabulary lists.\n'
          'API: https://www.dwds.de/d/api\n\n'
          'The CEFR-level lemma lists (A1, A2, B1) used in this app are obtained '
          'via the DWDS public API, which redistributes the Goethe-Institut\'s '
          'official Goethe-Zertifikat vocabulary lists in machine-readable form. '
          'Only the lemma + part-of-speech + grammatical-gender + article fields '
          'are incorporated into the app database.\n\n'
          'Acknowledgments to:\n'
          '  • Goethe-Institut e.V. (https://www.goethe.de) for the source lists\n'
          '  • DWDS / BBAW for the API redistribution\n\n'
          'The Goethe-Institut\'s original wordlists are factual reference material '
          '(specifying which lemmas an A1/A2/B1 learner is expected to master); '
          'the curated selections per level are attributable to the Goethe-Institut.',
        ),
      ]);
    });

    // 9h-extra2. Wiktionary Frequenzliste / Matthias Buchmeier
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Wiktionary German Frequency List (Buchmeier)'],
          'Source: Matthias Buchmeier - German frequency lists, hosted on the '
          'English Wiktionary\n'
          'URL: https://en.wiktionary.org/wiki/User:Matthias_Buchmeier/'
          'German_frequency_list-1-5000\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International '
          '(CC BY-SA 4.0), inherited from Wiktionary\n'
          'URL: https://creativecommons.org/licenses/by-sa/4.0/\n\n'
          'The Buchmeier20k frequency list (the top 20k words of the Buchmeier '
          'compilation) is used as one of several frequency signals during '
          'vocabulary consolidation.\n\n'
          'Changes made: Truncated to top 10k by rank for the build pipeline.\n\n'
          'Credit: Matthias Buchmeier (Wiktionary user). Distributed under the '
          'Wiktionary CC BY-SA 4.0 license.',
        ),
      ]);
    });

    // 9h-extra4. Spelling-pattern categorization (own derivation from NRW)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['German spelling-pattern categorization'],
          'The spelling-pattern category labels used in this app\n'
          '(klangtreu / doppelkonsonant / verwandt / merkwort / morphem / '
          'grossschreibung) are neutral German linguistic-pattern names. They '
          'describe the linguistic feature each word\'s spelling rests on; '
          'they are not borrowed from any branded pedagogical method.\n\n'
          'Pedagogically these categories cover the same ground that several '
          'published German spelling-strategy methods cover, but the labels and '
          'derivation rules here are independent.\n\n'
          'How the labels are produced:\n'
          '  • Source: NRW Grundwortschatz xlsx (Ministerium für Schule und '
          '    Bildung NRW), which contains the underlying linguistic feature '
          '    taxonomy: Doppelkonsonanten, Auslautverhärtung, Umlautung, '
          '    Diphthonge, Reduktionsendungen, etc.\n'
          '  • Mapping: applied algorithmically by the build pipeline (own '
          '    derivation; no third-party curated wordlist is consumed).\n'
          '  • Output: a multi-label category list plus a primary label per '
          '    word, both attached to the apiEnrichment field of each entry.',
        ),
      ]);
    });

    // 9h-extra5. Berliner Grundwortschatz (LISUM 2024)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Berliner Grundwortschatz (LISUM 2024)'],
          'Source: Berliner Grundwortschatz, LISUM 2024 edition\n'
          'Publisher: Landesinstitut für Schule und Medien Berlin-Brandenburg (LISUM), Ludwigsfelde\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://www.berlin.de/sen/bildung/schule/bildungswege/grundschule/berliner-grundwortschatz.pdf\n\n'
          'The Berliner Grundwortschatz publication is explicitly released by LISUM '
          'for re-use under CC BY-SA 4.0: "Soweit nicht abweichend gekennzeichnet '
          'zur Nachnutzung freigegeben unter der Creative Commons Lizenz CC BY-SA 4.0".\n\n'
          'Used as a source-attribution token in this app\'s vocabulary database '
          '(metadata_json.sources includes "BERLIN" for matching lemmas).',
        ),
      ]);
    });

    // 9h-extra6. Brandenburger Grundwortschatz (LISUM 2024)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Brandenburger Grundwortschatz (LISUM 2024)'],
          'Source: Grundwortschatz für die Grundschule in Brandenburg, LISUM 2024 edition\n'
          'Publisher: Landesinstitut für Schule und Medien Berlin-Brandenburg (LISUM), Ludwigsfelde\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://bildungsserver.berlin-brandenburg.de/fileadmin/bbb/unterricht/faecher/sprachen/deutsch/Schulinterne_Fachplaene_und_Planungshilfen/Grundwortschatz_Planungshilfe_Rechtschreiben_2024-08-09.pdf\n\n'
          'The Brandenburger Grundwortschatz publication is explicitly released by '
          'LISUM for re-use under CC BY-SA 4.0 (same license framing as the Berlin '
          'companion publication).\n\n'
          'Used as a source-attribution token (metadata_json.sources includes '
          '"BRANDENBURG" for matching lemmas).',
        ),
      ]);
    });

    // 9h-extra7. Hessen Grundwortschatz (Hess. KuMi 2021)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Hessen Grundwortschatz'],
          'Source: Handreichung zum Grundwortschatz Hessen + companion Wörterliste\n'
          'Publisher: Hessisches Kultusministerium, Luisenplatz 10, 65185 Wiesbaden\n'
          'License: public administrative material (amtliches Werk per §5 UrhG)\n'
          'URL: https://kultus.hessen.de/sites/kultus.hessen.de/files/2022-09/woerterliste_aus_der_handreichung_zum_grundwortschatz_hessen.pdf\n\n'
          'Verbindlich für hessische Grundschulen seit Schuljahr 2021/22. We use '
          'the official Wörterliste to populate metadata_json.sources with "HESSEN" '
          'and metadata_json.hessenCategories with the 53 orthographic-pattern '
          'categories from the source publication.',
        ),
      ]);
    });

    // 9h-extra8. Rheinland-Pfalz Grundwortschatz (Min. f. Bildung Mainz 2021)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Rheinland-Pfalz Grundwortschatz'],
          'Source: Grundwortschatz Rheinland-Pfalz Handreichung (August 2021)\n'
          'Publisher: Ministerium für Bildung, Mittlere Bleiche 61, 55116 Mainz\n'
          'License: public administrative material (amtliches Werk per §5 UrhG); '
          '© Ministerium für Bildung 2021\n'
          'URL: https://static.bildung-rp.de/pl-materialien/Allgemein/RP-07956534_GWS_BM_2021.pdf\n\n'
          'Per the publication\'s own Impressum: "Überarbeitete Fassung der '
          'Handreichung zum Grundwortschatz Hessen (Wiesbaden, März 2020), mit '
          'freundlicher Genehmigung des Hessischen Kultusministeriums."\n\n'
          'Verbindlich für RLP-Grundschulen seit Schuljahr 2022/23. Used as '
          '"RHEINLAND_PFALZ" source token + rheinland_pfalzCategories metadata.',
        ),
      ]);
    });

    // 9h-extra9. Niedersachsen Orientierungswortschatz (Nds. KuMi 2015)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Niedersachsen Orientierungswortschatz'],
          'Source: Materialien für einen kompetenzorientierten Unterricht im '
          'Primarbereich – Orthografie (2015)\n'
          'Publisher: Niedersächsisches Kultusministerium, Schiffgraben 12, '
          '30159 Hannover\n'
          'License: public administrative material (amtliches Werk per §5 UrhG); '
          'free distribution from NiBiS (Niedersächsischer Bildungsserver)\n'
          'URL: https://cuvo.nibis.de/index.php?p=download&upload=116\n\n'
          'Used as "NIEDERSACHSEN" source token. The PDF contains one embedded '
          'illustration carrying a "© 2013 Cornelsen Schulverlage GmbH" notice; '
          'we do not reproduce that illustration, only the headword lists which '
          'are factual reference material.',
        ),
      ]);
    });

    // 9h-extra10. Bayern Grundwortschatz (ISB Bayern)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Bayern Grundwortschatz'],
          'Source: Grundwortschatz für die Jahrgangsstufen 1+2 / 3+4 (ISB Bayern, '
          'Ergänzende Informationen zum LehrplanPLUS)\n'
          'Publisher: Staatsinstitut für Schulqualität und Bildungsforschung (ISB), '
          'München — state agency under the Bayerisches Staatsministerium für '
          'Unterricht und Kultus\n'
          'License: public administrative material (amtliches Werk per §5 UrhG)\n'
          'URLs:\n'
          '  - https://www.lehrplanplus.bayern.de/sixcms/media.php/71/5_Grundwortschatz%201_2.pdf\n'
          '  - https://www.lehrplanplus.bayern.de/sixcms/media.php/71/6_Grundwortschatz%203_4.pdf\n\n'
          'Used as "BAYERN" source token + bayernCategories (43 fine-grained '
          'orthographem-level labels like <er>, <ck>, <ie>, <tz>, Dehnungs <h>).',
        ),
      ]);
    });

    // 9h-extra11. Schleswig-Holstein Rechtschreib-Grundwortschatz (2023)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Schleswig-Holstein Rechtschreib-Grundwortschatz'],
          'Source: "Ebbe, Krabbe, Flut und Seepferdchen – Richtig schreiben lernen '
          'in Schleswig-Holstein mit dem Rechtschreib-Grundwortschatz" (Juni 2023)\n'
          'Publisher: Ministerium für Allgemeine und Berufliche Bildung, '
          'Wissenschaft, Forschung und Kultur des Landes SH, Brunswiker Straße '
          '16-22, 24105 Kiel; Mitwirkung: EUF (Europa-Universität Flensburg) + '
          'IQSH (Institut für Qualitätsentwicklung an Schulen)\n'
          'Autorinnen: Prof. Dr. Johanna Fay, Tanja Šutalo\n'
          'License: public administrative material (amtliches Werk per §5 UrhG)\n'
          'URL: https://www.schleswig-holstein.de/DE/landesregierung/ministerien-behoerden/III/Service/Broschueren/Bildung/grundwortschatz.pdf\n\n'
          'Per the publication\'s Impressum: "Der schleswig-holsteinische '
          'Rechtschreib-Grundwortschatz wurde mit Zustimmung der Schulbehörde '
          'Hamburg in Anlehnung an den Hamburger Basiswortschatz erstellt."\n\n'
          'Used as "SCHLESWIG_HOLSTEIN" source token + 59 hierarchical '
          'schleswig_holsteinCategories.',
        ),
      ]);
    });

    // 9h-extra12. DWDS Lemma-Datenbank (BBAW)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['DWDS Lemma-Datenbank — Häufigkeitsklassen'],
          'Source: DWDS Lemma-Datenbank (full lemma list with frequenzklasse)\n'
          'Publisher: Digitales Wörterbuch der deutschen Sprache (DWDS) / '
          'Berlin-Brandenburgische Akademie der Wissenschaften (BBAW)\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://www.dwds.de/lemma/csv\n'
          'Required attribution: "Digitales Wörterbuch der deutschen Sprache (DWDS), '
          'CC-BY-SA 4.0"\n\n'
          'This is distinct from the existing DWDS Goethe-Zertifikat A1/A2/B1 '
          'entry above. The DWDS Lemma-Datenbank provides a 7-level Häufigkeits-'
          'klasse (0–6) per lemma across the full DWDS reference corpus, used '
          'in this app to populate frequency_json.dwds with a general-purpose '
          'frequency band signal complementing the existing rank metrics from '
          'HermitDave, Buchmeier, Leipzig and Leeds.',
        ),
      ]);
    });

    // 9h-extra12b. DysList — German dyslexia error corpus (Rauschii et al. 2014)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['DysList — German dyslexic children\'s spelling errors'],
          'Source: DysList (German_Annotation_V028.csv)\n'
          'Authors: Rauschii et al. (2014)\n'
          'License: MIT License\n'
          'URL: https://github.com/Rauschii/DysListGerman\n'
          'DOI: 10.5281/zenodo.809801\n'
          'Citation: DysList: An Annotated Resource of Dyslexic Errors '
          '(ACL Anthology L14-1492)\n\n'
          'DysList contains ~1,020 annotated spelling errors produced by '
          'German children with diagnosed dyslexia (ages 6–15), covering '
          'omission, addition, substitution, multierror, and capital-letter '
          'error types. Used in this app to populate the commonMistakes field '
          'for German vocabulary entries (source tag: DYSLIST). '
          'MIT license is compatible with all other data sources in this app.',
        ),
      ]);
    });

    // 9h-extra13. childLex (Schroeder et al. 2015, HU Berlin / MPI Berlin)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['childLex — age-graded German lexical norms'],
          'Source: childLex 0.17.01, a German lexical database for ages 6–12 '
          'derived from a 10M-token corpus of children\'s literature\n'
          'Authors: Sascha Schroeder, Kay-Michael Würzner, Julian Heister, '
          'Alexander Geyken, Reinhold Kliegl (HU Berlin / MPI Berlin)\n'
          'License: GNU General Public License v3.0 (GPL-3.0)\n'
          'URL: https://osf.io/tqgjs/\n'
          'Citation: Schroeder, S., Würzner, K.-M., Heister, J., Geyken, A., & '
          'Kliegl, R. (2015). childLex: A lexical database of German read by '
          'children. Behavior Research Methods, 47(4), 1085–1094.\n\n'
          'childLex provides per-lemma frequency norms across three age bands: '
          'Age 1 (6–8 years / Klasse 1–2), Age 2 (9–10 / Klasse 3–4), Age 3 '
          '(11–12 / Klasse 5–6). Used in this app to populate frequency_json.'
          'childlex with age1_freq_norm / age2_freq_norm / age3_freq_norm per '
          'lemma. 9,008 of 13,040 vocabulary entries have childLex coverage.\n\n'
          'License cascade note: GPL-3.0 is the most restrictive license '
          'among the upstream sources that contribute substantial data to '
          'this app\'s vocabulary database. Per Creative Commons\' 2015 '
          'v4-compatible decision, CC-BY-SA-4.0 is one-way compatible with '
          'GPL-3.0, so combining childLex with the other CC-BY-SA-4.0 sources '
          'cascades the shipped database\'s license to GPL-3.0. The Flutter '
          'app source code is not affected and stays under its own license.',
        ),
      ]);
    });

    // 9h-extra14b. LiTKey corpus (Müller et al. 2021, RUB Bochum)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['LiTKey — German primary-school spelling-error corpus'],
          'Source: LiTKey corpus (Literacy and Key Competencies)\n'
          'Authors: Claudia Müller, Katrin Hein, Sven Schüller, '
          'Stefanie Dipper (Ruhr-Universität Bochum)\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 '
          'International (CC-BY-SA 4.0)\n'
          'URL: https://www.linguistics.rub.de/litkeycorpus/\n'
          'Citation: Müller, C., Hein, K., Schüller, S. & Dipper, S. '
          '(2021). The LiTKey Corpus — a richly annotated longitudinal '
          'corpus of German texts written by primary school children. '
          'Language Resources and Evaluation.\n\n'
          'LiTKey contains 37,000+ annotated spelling-error tokens from '
          'German primary-school children in grades 2–4. Used in this app '
          'to populate the commonMistakes field for German vocabulary '
          'entries (source tag: LITKEY). The CC-BY-SA 4.0 license is '
          'compatible with the database\'s effective GPL-3.0 posture '
          '(see "Vocabulary database — composite license" entry).',
        ),
      ]);
    });

    // 9h-extra14. Database-license posture statement (top-level summary)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Vocabulary database — composite license'],
          'The vocabulary database shipped with this app '
          '(assets/grundwortschatz.db.gz) is a composite work derived from '
          'many upstream sources, each separately attributed in this license '
          'screen.\n\n'
          'Effective license of the COMPOSITE DATABASE FILE: '
          'GNU General Public License v3.0 (GPL-3.0-or-later).\n\n'
          'This follows from combining childLex (GPL-3.0) with the other '
          'CC-BY-SA-4.0 upstream sources (Wiktionary, ConceptNet, OdeNet, '
          'OpenThesaurus, HermitDave/OpenSubtitles, DWDS, Wikipedia, '
          'Berlin/Brandenburg Grundwortschätze, etc.). Per Creative Commons\' '
          'official 2015 v4-compatible designation, CC-BY-SA-4.0 → GPL-3.0 '
          'is one-way compatible: the combined work must be redistributed '
          'under GPL-3.0, with full attribution preserved for every '
          'constituent CC-BY-SA-4.0 source.\n\n'
          'This composite-license posture applies ONLY to the database '
          'file. The Flutter application source code is under its own '
          'separate license. GPL on shipped data does not infect '
          'application code that merely *uses* the data; it only applies '
          'when redistributing derivative data works.\n\n'
          'Plain-administrative-material sources (NRW Grundwortschatz, '
          'BW Grundwortschatz, Hessen/RLP/Niedersachsen/Bayern/SH '
          'Grundwortschätze) are §5 UrhG amtliche Werke and are freely '
          'usable; their attribution requirements are handled by the '
          'individual license entries above.',
        ),
      ]);
    });

    // 9h-extra15. Tatoeba — example sentences (CC-BY 2.0)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Tatoeba — German example sentences'],
          'Source: Tatoeba Project (https://tatoeba.org)\n'
          'License: Creative Commons Attribution 2.0 (CC-BY 2.0)\n'
          'Download: https://downloads.tatoeba.org/exports/per_language/deu/\n\n'
          'Tatoeba is a free collection of example sentences and translations '
          'contributed by volunteers. German sentences (deu_sentences.tsv) are '
          'used in this app to provide short, child-friendly example sentences '
          'for vocabulary entries (field: tatoeba_examples, source tag: TATOEBA). '
          'Sentences are filtered to ≤ 15 words and selected for simplicity. '
          'CC-BY 2.0 is compatible with the database\'s effective GPL-3.0 '
          'posture (see "Vocabulary database — composite license" entry).',
        ),
      ]);
    });

    // 9i. Universal Dependencies (German treebanks)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Universal Dependencies - German treebanks'],
          'Source: Universal Dependencies (https://universaldependencies.org/)\n'
          'Treebanks used: UD_German-GSD, UD_German-HDT, UD_German-LIT, UD_German-PUD\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n'
          'URL: https://creativecommons.org/licenses/by-sa/4.0/\n\n'
          'Verb-government statistics (verb_government.json / verb_government_hdt.json) '
          'used by the inflection enricher were derived from the German UD treebanks. '
          'Only aggregated co-occurrence statistics are shipped with the app; no '
          'sentence-level treebank content is included.\n\n'
          'Citation: Nivre, J., et al. (2020). Universal Dependencies v2: An Evergrowing '
          'Multilingual Treebank Collection. LREC 2020.',
        ),
      ]);
    });

    // 9k. Dolch sight words
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Dolch sight words'],
          'Source: Dolch 220 sight words, Edward William Dolch (1948)\n'
          'License posture: Public domain in the United States as a '
          'pre-1978 work without a continuing copyright notice.\n\n'
          'The English vocabulary database uses the Dolch grade bands as '
          'an early-reading signal for foundational sight-word coverage.',
        ),
      ]);
    });

    // 9n. Open English WordNet
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Open English WordNet'],
          'Source: Open English WordNet\n'
          'License: Creative Commons Attribution 4.0 International '
          '(CC BY 4.0)\n'
          'URL: https://en-word.net/\n'
          'License URL: https://creativecommons.org/licenses/by/4.0/\n\n'
          'The WiktionaryEN enrichment service can use Open English WordNet '
          'for English synonym, antonym, hypernym, hyponym, and definition '
          'signals in the enriched English vocabulary database.',
        ),
      ]);
    });

    // 9o. wordfreq (EN frequency data)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['wordfreq'],
          'Source: wordfreq by Luminoso Technologies, Inc.\n'
          'Code license: Apache License 2.0\n'
          'Data license: Creative Commons Attribution-ShareAlike 4.0 '
          'International (CC BY-SA 4.0)\n'
          'URL: https://github.com/rspeer/wordfreq\n\n'
          'wordfreq provides word frequency data (Zipf scale, occurrences per '
          'million words) for the English vocabulary database. The frequency '
          'band signal is used to estimate vocabulary difficulty and as one '
          'input to the gradeLevelEstimate computation.\n\n'
          'The CC BY-SA 4.0 data license requires attribution and share-alike '
          'distribution of any derived database that includes the frequency data.',
        ),
      ]);
    });

    // 9p. CEFR-J Vocabulary Profile (EN)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['CEFR-J Vocabulary Profile'],
          'Source: CEFR-J Vocabulary Profile v1.5\n'
          'Authors: Tono, Y. & Negishi, M. (Tokyo University of Foreign Studies)\n'
          'License: Creative Commons Attribution-ShareAlike 4.0 International '
          '(CC BY-SA 4.0)\n'
          'URL: https://github.com/openlanguageprofiles/olp-en-cefrj\n\n'
          'The CEFR-J profile assigns 7,020 English headwords to CEFR levels '
          '(A1–B2). These level tags are stored in the English vocabulary '
          'database as cefr_level metadata and inform the gradeLevelEstimate.',
        ),
      ]);
    });

    // 9q. Cambridge Young Learners English (YLE) word lists
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Cambridge Young Learners English (YLE) word lists'],
          'Source: Cambridge Young Learners English Tests — Starters, Movers, '
          'and Flyers vocabulary lists\n'
          'Publisher: Cambridge Assessment English\n'
          'License posture: The word lists are factual reference material '
          '(enumerating vocabulary items learners are expected to know at each '
          'level); as purely factual enumerations they are not subject to '
          'copyright protection under the doctrine of facts and data.\n\n'
          'The YLE level tags (source:cambridge_yle_starters, '
          'source:cambridge_yle_movers, source:cambridge_yle_flyers) are '
          'stored in the English vocabulary database as pedagogical difficulty '
          'signals.',
        ),
      ]);
    });

    // 9r. UK DfE statutory word lists
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['UK DfE statutory spelling word lists'],
          'Source: UK Department for Education — National Curriculum statutory '
          'spelling word lists for Years 1-2, 3-4, and 5-6.\n'
          'License: Open Government Licence v3.0 (OGL v3)\n'
          'URL: https://www.gov.uk/government/publications/national-curriculum-in-england-english-programmes-of-study\n'
          'License URL: https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/\n\n'
          'OGL v3 permits commercial use with attribution. These word lists '
          'are used to tag entries in the English vocabulary database with '
          'source:uk_y1_y2, source:uk_y3_y4, and source:uk_y5_y6 labels, '
          'and as an input to the gradeLevelEstimate computation.',
        ),
      ]);
    });

    // 9s. Norvig spell-errors.txt (EN misspellings)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Norvig spell-errors.txt'],
          'Source: spell-errors.txt by Peter Norvig\n'
          'Code license: MIT (per Norvig\'s "How to Write a Spelling Corrector" '
          'essay header)\n'
          'Data license: Creative Commons Attribution-ShareAlike (upstream Wikipedia '
          'misspelling data; CC BY-SA)\n'
          'URL: https://norvig.com/ngrams/spell-errors.txt\n\n'
          'The Norvig spell-errors corpus contains ~38,000 correct→misspelling pairs '
          'extracted from public domain sources including Wikipedia talk-page archives. '
          'Used in the English vocabulary database to populate commonLearnerErrors '
          'for ~4,600 entries (source tag: norvig). The CC BY-SA data license '
          'requirement is satisfied by the vocabulary database\'s ShareAlike posture.',
        ),
      ]);
    });

    // 9t. Project Gutenberg texts (EN example sentences)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['Project Gutenberg — English example sentences'],
          'Source: Project Gutenberg (https://www.gutenberg.org/)\n'
          'License: Public Domain (all texts used are pre-1928 US publications '
          'with no continuing copyright)\n\n'
          'Example sentences in the English vocabulary database are extracted from '
          '72 public-domain books from Project Gutenberg, including works by '
          'Lewis Carroll, Mark Twain, Robert Louis Stevenson, Louisa May Alcott, '
          'Frances Hodgson Burnett, E. Nesbit, Lucy Maud Montgomery, Rudyard '
          'Kipling, J.M. Barrie, L. Frank Baum, Kenneth Grahame, Beatrix Potter, '
          'George MacDonald, Daniel Defoe, Jonathan Swift, Anna Sewell, and others. '
          'Only sentences containing a target vocabulary word are stored; the full '
          'text is not bundled with the app.',
        ),
      ]);
    });

    // 9u. SCOWL / en-wl wordlist (EN spelling variants)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['SCOWL / en-wl — English spelling variants'],
          'Source: SCOWL (Spell-Checker Oriented Word Lists) / en-wl wordlist\n'
          'Maintainer: Kevin Atkinson (SCOWL); vg/spelling-uk-vs-us subset\n'
          'License: MIT-like permissive (Kevin Atkinson\'s custom license, '
          'CC-BY-4.0 for some wordlist subsets)\n'
          'URL: http://wordlist.aspell.net/\n\n'
          'SCOWL-derived UK vs. US spelling variant pairs (colour/color, '
          'centre/center, organise/organize, etc.) are stored in the English '
          'vocabulary database as spellingVariants with dialect=british or '
          'dialect=american. 264 variant pairs across 150 entries.',
        ),
      ]);
    });

    // ==================== LIBRARY LICENSES ====================

    // 10. spaCy
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['spaCy'],
          'spaCy: Industrial-strength Natural Language Processing (NLP) in Python\n'
          'Copyright © 2016-2024 ExplosionAI GmbH\n'
          'License: MIT License\n'
          'URL: https://spacy.io/\n\n'
          'The MIT License (MIT)\n\n'
          'Permission is hereby granted, free of charge, to any person obtaining a copy '
          'of this software and associated documentation files (the "Software"), to deal '
          'in the Software without restriction, including without limitation the rights '
          'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell '
          'copies of the Software, and to permit persons to whom the Software is '
          'furnished to do so, subject to the following conditions:\n\n'
          'The above copyright notice and this permission notice shall be included in all '
          'copies or substantial portions of the Software.\n\n'
          'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR '
          'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, '
          'FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE '
          'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER '
          'LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, '
          'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE '
          'SOFTWARE.',
        ),
      ]);
    });

    // 11. pattern-de
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['pattern-de', 'Pattern'],
          'Pattern: Web mining module for Python\n'
          'Copyright (c) 2010 University of Antwerp, Belgium\n'
          'Authors: Tom De Smedt, Walter Daelemans\n'
          'License: BSD-3-Clause License\n'
          'URL: https://github.com/clips/pattern\n\n'
          'BSD 3-Clause License\n\n'
          'Redistribution and use in source and binary forms, with or without '
          'modification, are permitted provided that the following conditions are met:\n\n'
          '1. Redistributions of source code must retain the above copyright notice, this '
          'list of conditions and the following disclaimer.\n\n'
          '2. Redistributions in binary form must reproduce the above copyright notice, '
          'this list of conditions and the following disclaimer in the documentation '
          'and/or other materials provided with the distribution.\n\n'
          '3. Neither the name of the copyright holder nor the names of its contributors '
          'may be used to endorse or promote products derived from this software without '
          'specific prior written permission.\n\n'
          'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" '
          'AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE '
          'IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE '
          'DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE '
          'FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL '
          'DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR '
          'SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER '
          'CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, '
          'OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE '
          'OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.',
        ),
      ]);
    });

    // 12. PatternLight
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['PatternLight'],
          'PatternLight: Lightweight fork of the Pattern library\n'
          'Based on Pattern by University of Antwerp, Belgium\n'
          'License: BSD-3-Clause License\n\n'
          'BSD 3-Clause License\n\n'
          'Redistribution and use in source and binary forms, with or without '
          'modification, are permitted provided that the following conditions are met:\n\n'
          '1. Redistributions of source code must retain the above copyright notice, this '
          'list of conditions and the following disclaimer.\n\n'
          '2. Redistributions in binary form must reproduce the above copyright notice, '
          'this list of conditions and the following disclaimer in the documentation '
          'and/or other materials provided with the distribution.\n\n'
          '3. Neither the name of the copyright holder nor the names of its contributors '
          'may be used to endorse or promote products derived from this software without '
          'specific prior written permission.\n\n'
          'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" '
          'AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE '
          'IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE '
          'DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE '
          'FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL '
          'DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR '
          'SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER '
          'CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, '
          'OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE '
          'OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.',
        ),
      ]);
    });

    // 13. HanTa (German morphological analyzer)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['HanTa'],
          'HanTa: Hanover Tagger - a morphological tagger for German\n'
          'Author: Christian Wartena (Hochschule Hannover)\n'
          'License: Apache License 2.0\n'
          'URL: https://github.com/wartaal/HanTa\n\n'
          'HanTa is used server-side on the Hugging Face WiktionaryDE Space to '
          'lemmatize and morphologically analyze German words during the '
          'enrichment step of the pipeline. The structured analysis output is '
          'embedded in the apiEnrichment fields of this app\'s database.\n\n'
          'Licensed under the Apache License, Version 2.0; you may obtain a copy '
          'of the License at: http://www.apache.org/licenses/LICENSE-2.0',
        ),
      ]);
    });

    // 14. IWNLP (German lemmatization based on Wiktionary)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['IWNLP'],
          'IWNLP: A German lemmatization library based on the German Wiktionary\n'
          'Author: Matthias Liebeck\n'
          'License: MIT License\n'
          'URLs:\n'
          '  • https://github.com/Liebeck/IWNLP.Lemmatizer (C#)\n'
          '  • https://github.com/Liebeck/spacy-iwnlp (spaCy integration)\n\n'
          'IWNLP provides Wiktionary-derived lemma mappings used in the '
          'enrichment pipeline on the Hugging Face WiktionaryDE Space.\n\n'
          'The MIT License (MIT)\n\n'
          'Permission is hereby granted, free of charge, to any person obtaining '
          'a copy of this software and associated documentation files (the '
          '"Software"), to deal in the Software without restriction, including '
          'without limitation the rights to use, copy, modify, merge, publish, '
          'distribute, sublicense, and/or sell copies of the Software, and to '
          'permit persons to whom the Software is furnished to do so.',
        ),
      ]);
    });

    // 15. DWDSmor (DWDS morphology)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['DWDSmor'],
          'DWDSmor: Finite-state morphology for German\n'
          'Authors: Berlin-Brandenburgische Akademie der Wissenschaften (BBAW), '
          'DWDS project\n'
          'License: Software under permissive open-source terms; underlying '
          'lexical data subject to DWDS terms\n'
          'URLs:\n'
          '  • https://github.com/dwds/dwdsmor\n'
          '  • https://www.dwds.de/\n\n'
          'DWDSmor provides German morphological analysis (inflection forms, '
          'POS, lemma) and is used server-side on the Hugging Face WiktionaryDE '
          'Space during enrichment. The structured analysis output is embedded '
          'in this app\'s apiEnrichment fields.\n\n'
          'Credit: BBAW / DWDS project. See https://www.dwds.de/ for the '
          'complete attribution and project terms.',
        ),
      ]);
    });

    // 16. wiktextract (extracts structured data from Wiktionary dumps)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['wiktextract'],
          'wiktextract: Wiktionary dump parser\n'
          'Author: Tatu Ylonen\n'
          'License: MIT License\n'
          'URL: https://github.com/tatuylonen/wiktextract\n\n'
          'wiktextract is the parser used to convert raw Wiktionary XML dumps '
          'into structured JSONL data, which is then normalized into the SQLite '
          'datasets that back the Hugging Face WiktionaryDE / WiktionaryEN '
          'Spaces during the enrichment step.\n\n'
          'Released under the MIT License.',
        ),
      ]);
    });

    // 17. phonemizer + espeak-ng (used for IPA generation during build)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['phonemizer + espeak-ng'],
          'phonemizer: Python wrapper for multiple phoneme backends\n'
          'Author: Mathieu Bernard\n'
          'License: GPL-3.0\n'
          'URL: https://github.com/bootphon/phonemizer\n\n'
          'espeak-ng: Speech synthesis engine (used as backend by phonemizer)\n'
          'License: GPL-3.0\n'
          'URL: https://github.com/espeak-ng/espeak-ng\n\n'
          'These tools are used during the build pipeline (step 05) to generate '
          'IPA and X-SAMPA phoneme strings for each headword. The tools '
          'themselves are GPL-3.0 licensed, but only their OUTPUT (phoneme '
          'strings, which are linguistic facts) is shipped in the app database; '
          'the tools are not bundled with the app, so the GPL does not affect '
          'the app\'s license posture.',
        ),
      ]);
    });

    // 18. CMU Pronouncing Dictionary (for EN port)
    LicenseRegistry.addLicense(() {
      return Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          ['CMU Pronouncing Dictionary'],
          'CMU Pronouncing Dictionary (CMUdict)\n'
          'Author: Carnegie Mellon University\n'
          'License: 2-clause BSD-style license (permissive)\n'
          'URL: https://github.com/cmusphinx/cmudict\n\n'
          'CMUdict provides ARPAbet phonetic transcriptions for ~134k English '
          'words, used as the primary phonetic source for the English '
          'vocabulary build (when shipping the English DB).\n\n'
          'Permission to use, copy, modify, and distribute this dictionary for '
          'any purpose and without fee or royalty is hereby granted, provided '
          'that the credit "Pronouncing Dictionary Copyright (C) Carnegie '
          'Mellon University" is preserved.',
        ),
      ]);
    });
    _customLicensesAdded = true;
    if (kDebugMode) debugPrint(
        "[LICENSES] 📚 Custom licenses registered (fonts + data sources + libraries).");
  } catch (e) {
    if (kDebugMode) debugPrint('[LICENSES] ❌ Error registering custom licenses: $e');
  }
}
