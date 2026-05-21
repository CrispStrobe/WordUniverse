// lib/features/settings/screens/settings_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/space_theme.dart';
import '../../../core/services/debug_provider.dart';

import '../../../core/theme/app_fonts.dart';

// Import VocabularyService to get sources
import '../../../core/services/vocabulary_service.dart';
import '../../../core/services/sri_service.dart';

import '../../../shared/widgets/imprint_dialog.dart';
import 'diagnostics_screen.dart';
import '../../games/screens/parent_dashboard_screen.dart';
import '../../../shared/widgets/privacy_policy_dialog.dart';
import '../../../shared/widgets/parental_gate.dart';

import '../../../generated/l10n.dart';

// We import this for the Grade definitions
import '../../games/providers/game_provider.dart';
import '../../games/widgets/space_background.dart';
// We import the dialog separately
import '../widgets/sri_statistics_dialog.dart';

import '../widgets/manage_sets_dialog.dart';

// For LicenseRegistry
import 'package:flutter/services.dart' show rootBundle;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  
  late AnimationController _slideController;
  late List<Animation<Offset>> _settingAnimations;
  String currentLocale = 'en'; // Safe default
  bool _isLoading = false;
  bool _hasLoadedLocale = false; 

  bool _customLicensesAdded = false;

  // NEW: State for dynamic vocabulary sources
  Set<String> _availableSources = {};
  bool _sourcesLoaded = false;
  
  // NEW: Controllers for wildcard text fields
  final TextEditingController _includeController = TextEditingController();
  final TextEditingController _excludeController = TextEditingController();


  @override
  void initState() {
    super.initState();
    debugPrint("[SETTINGS] 🔧 initState() starting...");
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _settingAnimations = List.generate(7, (index) {
      return Tween<Offset>(
        begin: const Offset(-1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Interval(
          (index * 0.1).clamp(0.0, 0.5),
          (0.4 + (index * 0.1)).clamp(0.1, 1.0),
          curve: Curves.easeOutCubic,
        ),
      ));
    });
    
    debugPrint("[SETTINGS] 🔧 initState() completed - 7 animations ready");
    _slideController.forward();
    _addCustomLicenses();
  }

  /// Adds custom font, data source, and library licenses to the app's license registry.
  /// This method ensures all third-party components are properly attributed in the
  /// "About" section of the app.
  Future<void> _addCustomLicenses() async {
    // Only run this once per app session.
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

      final peterWiegelLicense = 
          'Author: Peter Wiegel\n'
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

      // 9f. UK National Curriculum English Programmes of Study
      LicenseRegistry.addLicense(() {
        return Stream<LicenseEntry>.fromIterable([
          LicenseEntryWithLineBreaks(
            ['UK National Curriculum - Statutory Spelling Lists'],
            'Source: Department for Education (England), '
            'English Programmes of Study, Appendix 1\n'
            'URL: https://www.gov.uk/government/publications/national-curriculum-in-england-english-programmes-of-study\n'
            'License: Open Government Licence v3.0 (OGL v3.0)\n'
            'License URL: https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/\n\n'
            'The statutory spelling lists for Years 1-2, 3-4 and 5-6 from the English '
            'National Curriculum are used as the pedagogical primary signal for the '
            'English vocabulary in this app (when shipping the English DB).\n\n'
            'Contains public sector information licensed under the Open Government '
            'Licence v3.0. You are free to copy, publish, distribute and transmit the '
            'information, adapt it, and exploit it commercially, provided that the '
            'source is acknowledged.',
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

      // 9h-extra3. Tacke / Menzel "100 häufigsten Fehlerwörter"
      LicenseRegistry.addLicense(() {
        return Stream<LicenseEntry>.fromIterable([
          LicenseEntryWithLineBreaks(
            ['Häufigste Fehlerwörter (Tacke / Menzel)'],
            'Authors: Dr. Gero Tacke (Schulpsychologe, Heidelberg);\n'
            '         underlying study: Wolfgang Menzel (1985)\n'
            'Source: "Die 100 häufigsten Fehlerwörter der deutschen Sprache" - '
            'widely redistributed by German schools as PDF reference material '
            'for educational use.\n'
            'License: Freely distributed for educational purposes by schools and '
            'educational platforms; no formal open-source / Creative Commons '
            'license. Authorship credit retained by Dr. Gero Tacke.\n\n'
            'The 100Fehler / 300Fehler / 400Fehler error-word lists used to seed '
            'the commonLearnerErrors pool for the German vocabulary derive from '
            'this Tacke / Menzel material. Only the correct headwords are present '
            'in the shipped vocabulary database; the example sentences and '
            'related-form fields published in the original Tacke materials are '
            'not redistributed in the app.\n\n'
            'Credit: Dr. Gero Tacke (Heidelberg) for the curation; Wolfgang Menzel '
            '(1985) for the underlying empirical study of 2000 student essays.',
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

      setState(() {
        _customLicensesAdded = true;
      });
      debugPrint("[SETTINGS] 📚 Successfully added all custom licenses (fonts + data sources + libraries).");

    } catch (e) {
      debugPrint("[SETTINGS] ❌ Error loading custom licenses: $e");
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint("[SETTINGS] 🌍 didChangeDependencies() called");
    
    if (!_hasLoadedLocale) {
      _loadCurrentLocaleAndSettings();
      _hasLoadedLocale = true;
    }
  }

  Widget _buildFontSelector(GameProvider gameProvider) {
    // TODO: add these strings to S.of(context) files
    final String title = "Schriftart"; // s.fontFamilyTitle
    final String subtitle = "Wähle eine Schriftart für Lerninhalte"; // s.fontFamilySubtitle

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          const Icon(Icons.font_download, color: SpaceTheme.alienGreen, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),

          // The Dropdown Button
          DropdownButton<String>(
            value: gameProvider.selectedFontFamily,
            dropdownColor: SpaceTheme.deepSpace,
            style: SpaceTheme.bodyStyle,
            onChanged: (String? newValue) {
              if (newValue != null) {
                gameProvider.setSelectedFontFamily(newValue);
              }
            },
            items: AppFonts.selectableFonts.entries.map((entry) {
              return DropdownMenuItem<String>(
                value: entry.key, // e.g., "SASBienchen"
                child: Text(entry.value), // e.g., "SAS Bienchen"
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomSetSelector(
    BuildContext context,
    GameProvider gameProvider,
    VocabularyService vocabService,
  ) {
    final s = S.of(context)!;
    final customSets = vocabService.getCustomSets();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Title
        Text(
          s.taskActiveSetTitle,
          style: SpaceTheme.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          s.taskActiveSetDesc,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 12,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 12),

        // 2. List of Checkboxes
        if (customSets.isEmpty)
          Center(
            child: Text(
              "No custom sets created yet.",
              style: SpaceTheme.bodyStyle.copyWith(color: Colors.white54, fontStyle: FontStyle.italic),
            ),
          )
        else
          Container(
            height: 150, // Constrain height to make it scrollable
            decoration: BoxDecoration(
              color: SpaceTheme.deepSpace.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: ListView.builder(
              itemCount: customSets.length,
              itemBuilder: (context, index) {
                final set = customSets[index];
                return CheckboxListTile(
                  title: Text(set.name, style: SpaceTheme.bodyStyle),
                  subtitle: Text(
                    set.description,
                    style: SpaceTheme.bodyStyle.copyWith(fontSize: 10, color: Colors.white60),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: gameProvider.activeVocabularySetIds.contains(set.id),
                  onChanged: (bool? value) {
                    gameProvider.toggleActiveVocabularySet(set.id);
                  },
                  activeColor: SpaceTheme.alienGreen,
                  checkColor: Colors.black,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
        
        const SizedBox(height: 16),

        // 3. Button to manage/create sets
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.edit_rounded),
            label: Text(s.taskManageSets),
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.cosmicPink,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const ManageSetsDialog(),
              );
            },
          ),
        ),
      ],
    );
  }

  // NEW: Helper to load vocab sources
  Future<void> _loadVocabularySources() async {
    if (_sourcesLoaded) return;
    
    try {
      final vocabService = context.read<VocabularyService>();
      final sources = vocabService.getAllAvailableSources();
      
      // Sort sources alphabetically for consistent display
      final sortedSources = sources.toList()..sort();
      
      if (mounted) {
        setState(() {
          _availableSources = sortedSources.toSet();
          _sourcesLoaded = true;
        });
        debugPrint("[SETTINGS] 📚 Loaded ${_availableSources.length} vocab sources");
      }
    } catch (e) {
      debugPrint("[SETTINGS] ❌ Error loading vocab sources: $e");
    }
  }
  
  @override
  void dispose() {
    debugPrint("[SETTINGS] 🗑️ Disposing settings screen");
    _slideController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  void _loadCurrentLocaleAndSettings() async {
    debugPrint("[SETTINGS] 📱 Loading current locale and settings...");
    
    try {
      final contextLocale = Localizations.localeOf(context).languageCode;
      debugPrint("[SETTINGS] 🌍 Context locale: $contextLocale");
      
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString('language');
      debugPrint("[SETTINGS] 💾 Saved locale from SharedPreferences: $savedLocale");
      
      setState(() {
        currentLocale = savedLocale ?? contextLocale;
      });
      
      debugPrint("[SETTINGS] ✅ Final locale set to: $currentLocale");
      
      await _loadAllSettings();
      
      // NEW: Load vocab sources *after* locale is set
      await _loadVocabularySources();
      
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Error loading locale/settings: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
      setState(() {
        currentLocale = 'en';
      });
    }
  }
  
  Future<void> _loadAllSettings() async {
    debugPrint("[SETTINGS] 📚 Loading all application settings...");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final keys = prefs.getKeys();
      debugPrint("[SETTINGS] 🔑 Found ${keys.length} preference keys: $keys");
      
      final soundEnabled = prefs.getBool('sound_enabled') ?? true;
      final musicEnabled = prefs.getBool('music_enabled') ?? true;
      final hintsEnabled = prefs.getBool('hints_enabled') ?? true;
      final hapticEnabled = prefs.getBool('haptic_enabled') ?? true;
      final puzzleTimerEnabled = prefs.getBool('puzzle_timer_enabled') ?? true;
      
      debugPrint("[SETTINGS] 🔊 Sound enabled: $soundEnabled");
      debugPrint("[SETTINGS] 🎵 Music enabled: $musicEnabled");
      debugPrint("[SETTINGS] 💡 Hints enabled: $hintsEnabled");
      debugPrint("[SETTINGS] 📳 Haptic enabled: $hapticEnabled");
      debugPrint("[SETTINGS] ⏱️ Puzzle timer enabled: $puzzleTimerEnabled");
      
      if (mounted) {
        final gameProvider = context.read<GameProvider>();
        gameProvider.setSoundEnabled(soundEnabled);
        gameProvider.setMusicEnabled(musicEnabled);
        gameProvider.setPuzzleTimer(puzzleTimerEnabled);
        
        debugPrint("[SETTINGS] ✅ Applied settings to GameProvider");
      }
      
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Error loading settings: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildAudioSettings(),
                      const SizedBox(height: 20),
                      _buildGameplaySettings(),
                      const SizedBox(height: 20),
                      _buildTaskCustomizationSettings(),
                      const SizedBox(height: 20),
                      _buildLanguageSettings(),
                      const SizedBox(height: 20),
                      _buildDifficultySettings(),
                      const SizedBox(height: 20),
                      _buildProgressSettings(),
                      const SizedBox(height: 20),
                      _buildAboutSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E2235),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              debugPrint("[SETTINGS] 🔙 Back button pressed");
              Navigator.of(context).pop();
            },
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 28,
            ),
            style: IconButton.styleFrom(
              backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
              padding: const EdgeInsets.all(12),
            ),
          ),
          
          const SizedBox(width: 20),
          
          Expanded(
            child: Text(
              S.of(context)!.settings,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 32),
            ),
          ),
          
          const Icon(
            Icons.settings,
            color: SpaceTheme.starYellow,
            size: 32,
          ),
        ],
      ),
    );
  }
  
  Widget _buildAudioSettings() {
    return SlideTransition(
      position: _settingAnimations[0],
      child: _buildSettingsCard(
        title: S.of(context)!.audioSettings,
        icon: Icons.volume_up,
        children: [
          Consumer<GameProvider>(
            builder: (context, gameProvider, child) {
              return Column(
                children: [
                  _buildSwitchTile(
                    title: S.of(context)!.sound,
                    subtitle: S.of(context)!.soundEffects,
                    value: gameProvider.soundEnabled,
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 🔊 Sound setting changed to: $value");
                      gameProvider.setSoundEnabled(value);
                      _saveSetting('sound_enabled', value);
                    },
                    icon: Icons.music_note,
                  ),
                  
                  _buildSwitchTile(
                    title: S.of(context)!.music,
                    subtitle: S.of(context)!.backgroundMusicDesc,
                    value: gameProvider.musicEnabled,
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 🎵 Music setting changed to: $value");
                      gameProvider.setMusicEnabled(value);
                      _saveSetting('music_enabled', value);
                    },
                    icon: Icons.library_music,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildGameplaySettings() {
    return SlideTransition(
      position: _settingAnimations[1],
      child: _buildSettingsCard(
        title: S.of(context)!.gameplay,
        icon: Icons.games,
        children: [
          Consumer2<GameProvider, DebugProvider>(
            builder: (context, gameProvider, debugProvider, child) {
              final isUnlocked = gameProvider.isFullVersionUnlocked || debugProvider.isPaidUnlockedForced;
            
              return Column(
                children: [
                  _buildSwitchTile(
                    title: S.of(context)!.adaptiveDifficulty, 
                    subtitle: S.of(context)!.adjustProblems,
                    value: gameProvider.useAdaptiveDifficulty,
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 🧠 Adaptive difficulty changed to: $value");
                      gameProvider.setUseAdaptiveDifficulty(value);
                      _saveSetting('use_adaptive_difficulty', value);
                    },
                    icon: Icons.auto_awesome,
                  ),
                  _buildSwitchTile(
                    title: S.of(context)!.puzzleTimer,
                    subtitle: S.of(context)!.puzzleTimerDesc,
                    value: gameProvider.puzzleTimerEnabled,
                    onChanged: (value) {
                      debugPrint("[SETTINGS] ⏱️ Puzzle timer setting changed to: $value");
                      gameProvider.setPuzzleTimer(value);
                      _saveSetting('puzzle_timer_enabled', value);
                    },
                    icon: Icons.timer,
                  ),
                  
                  _buildSwitchTile(
                    title: S.of(context)!.showHints,
                    subtitle: S.of(context)!.showHintsDesc,
                    value: true, // TODO: Add to GameProvider
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 💡 Hints setting changed to: $value");
                      _saveSetting('hints_enabled', value);
                    },
                    icon: Icons.lightbulb,
                  ),
                  
                  _buildSwitchTile(
                    title: S.of(context)!.hapticFeedback,
                    subtitle: S.of(context)!.hapticFeedbackDesc,
                    value: true, // TODO: Add to GameProvider
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 📳 Haptic feedback setting changed to: $value");
                      _saveSetting('haptic_enabled', value);
                    },
                    icon: Icons.vibration,
                  ),

                  const Divider(color: SpaceTheme.nebulaPurple, height: 24),
                    _buildFeatureRow(
                    title: S.of(context)!.sriStatisticsTitle,
                    subtitle: S.of(context)!.sriStatisticsDesc,
                    icon: Icons.bar_chart,
                    isLocked: !isUnlocked,
                    onTap: () {
                        if (isUnlocked) {
                        showDialog(
                            context: context,
                            builder: (context) => const SriStatisticsDialog(),
                        );
                        } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                            content: Text(S.of(context)!.premiumFeature),
                            backgroundColor: SpaceTheme.planetOrange,
                            ),
                        );
                        }
                    },
                    ),

                  const Divider(color: SpaceTheme.nebulaPurple, height: 24),
                  _buildFontSelector(gameProvider),

                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildTaskCustomizationSettings() {
    return SlideTransition(
      position: _settingAnimations[2],
      child: Consumer2<GameProvider, VocabularyService>(
        builder: (context, gameProvider, vocabService, child) {
          
          final bool customSetIsActive = gameProvider.activeVocabularySetIds.isNotEmpty;

          return _buildSettingsCard(
            title: S.of(context)!.taskCustomizationTitle,
            icon: Icons.filter_list,
            children: [
              _buildSwitchTile(
                title: S.of(context)!.taskCustomizationEnable,
                subtitle: S.of(context)!.taskCustomizationEnableDesc,
                value: gameProvider.tasksCustomizationEnabled,
                onChanged: (value) {
                  debugPrint("[SETTINGS] 🛠️ Task Customization changed to: $value");
                  gameProvider.setTasksCustomizationEnabled(value);

                  if (value == false) {
                    gameProvider.clearActiveVocabularySets();
                    debugPrint("[SETTINGS] 🧹 Cleared active vocabulary sets.");
                  }
                },
                icon: Icons.edit_note,
              ),

              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: gameProvider.tasksCustomizationEnabled
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(color: SpaceTheme.nebulaPurple, height: 24),

                        _buildCustomSetSelector(context, gameProvider, vocabService),
                        
                        const Divider(color: SpaceTheme.nebulaPurple, height: 24),

                        if (customSetIsActive)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Text(
                              S.of(context)!.taskFiltersDisabled,
                              style: SpaceTheme.bodyStyle.copyWith(
                                color: SpaceTheme.starYellow,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        
                        IgnorePointer(
                          ignoring: customSetIsActive,
                          child: Opacity(
                            opacity: customSetIsActive ? 0.5 : 1.0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildWordLengthSlider(gameProvider),
                                const SizedBox(height: 20),

                                _buildSourceSelector(gameProvider),
                                const SizedBox(height: 20),

                                _buildWildcardInputSection(
                                  title: S.of(context)!.taskWildcardIncludeTitle,
                                  desc: S.of(context)!.taskWildcardIncludeDesc,
                                  controller: _includeController,
                                  currentFilters: gameProvider.taskIncludeWildcards,
                                  onAdd: (filter) {
                                    final newList = List<String>.from(gameProvider.taskIncludeWildcards)..add(filter);
                                    gameProvider.setTaskIncludeWildcards(newList);
                                  },
                                  onRemove: (filter) {
                                    final newList = List<String>.from(gameProvider.taskIncludeWildcards)..remove(filter);
                                    gameProvider.setTaskIncludeWildcards(newList);
                                  },
                                ),
                                const SizedBox(height: 20),
                                
                                _buildWildcardInputSection(
                                  title: S.of(context)!.taskWildcardExcludeTitle,
                                  desc: S.of(context)!.taskWildcardExcludeDesc,
                                  controller: _excludeController,
                                  currentFilters: gameProvider.taskExcludeWildcards,
                                  onAdd: (filter) {
                                    final newList = List<String>.from(gameProvider.taskExcludeWildcards)..add(filter);
                                    gameProvider.setTaskExcludeWildcards(newList);
                                  },
                                  onRemove: (filter) {
                                    final newList = List<String>.from(gameProvider.taskExcludeWildcards)..remove(filter);
                                    gameProvider.setTaskExcludeWildcards(newList);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
                ),
              ],
            );
        },
      ),
    );
  }

  Widget _buildWordLengthSlider(GameProvider gameProvider) {
    final min = gameProvider.taskWordLengthMin;
    final max = gameProvider.taskWordLengthMax;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context)!.taskWordLengthTitle,
          style: SpaceTheme.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              "2",
              style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.moonSilver),
            ),
            Expanded(
              child: RangeSlider(
                min: 2,
                max: 20,
                divisions: 18,
                values: RangeValues(min, max),
                activeColor: SpaceTheme.alienGreen,
                inactiveColor: SpaceTheme.deepSpace,
                labels: RangeLabels(
                  min.round().toString(),
                  max.round().toString(),
                ),
                onChanged: (values) {
                  gameProvider.setTaskWordLengthRange(values.start, values.end);
                },
              ),
            ),
            Text(
              "20",
              style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.moonSilver),
            ),
          ],
        ),
        Center(
          child: Text(
            S.of(context)!.taskWordLengthRange(min.round(), max.round()),
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceSelector(GameProvider gameProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context)!.taskIncludedSourcesTitle,
          style: SpaceTheme.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          S.of(context)!.taskIncludedSourcesDesc,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 12,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 12),
        !_sourcesLoaded
          ? const Center(child: CircularProgressIndicator())
          : _availableSources.isEmpty
            ? Center(
                child: Text(
                  "Keine Quellen gefunden",
                  style: SpaceTheme.bodyStyle.copyWith(color: Colors.white54),
                ),
              )
            : Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: _availableSources.map((source) {
                  final isSelected = gameProvider.taskIncludedSources.contains(source);
                  return FilterChip(
                    label: Text(source),
                    selected: isSelected,
                    onSelected: (selected) {
                      final currentSources = Set<String>.from(gameProvider.taskIncludedSources);
                      if (selected) {
                        currentSources.add(source);
                      } else {
                        currentSources.remove(source);
                      }
                      gameProvider.setTaskIncludedSources(currentSources);
                    },
                    backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
                    selectedColor: SpaceTheme.alienGreen.withValues(alpha: 0.3),
                    labelStyle: TextStyle(
                      color: isSelected ? SpaceTheme.alienGreen : Colors.white,
                    ),
                    checkmarkColor: SpaceTheme.alienGreen,
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: isSelected ? SpaceTheme.alienGreen : Colors.white24,
                      ),
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildWildcardInputSection({
    required String title,
    required String desc,
    required TextEditingController controller,
    required List<String> currentFilters,
    required Function(String) onAdd,
    required Function(String) onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: SpaceTheme.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          desc,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 12,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          style: SpaceTheme.bodyStyle,
          decoration: InputDecoration(
            hintText: S.of(context)!.taskWildcardHint,
            hintStyle: SpaceTheme.bodyStyle.copyWith(color: Colors.white38),
            filled: true,
            fillColor: SpaceTheme.deepSpace.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: SpaceTheme.alienGreen),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_circle, color: SpaceTheme.alienGreen),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty && !currentFilters.contains(text)) {
                  onAdd(text);
                  controller.clear();
                }
              },
            ),
          ),
          onSubmitted: (value) {
            final text = value.trim();
            if (text.isNotEmpty && !currentFilters.contains(text)) {
              onAdd(text);
              controller.clear();
            }
          },
        ),
        const SizedBox(height: 8),
        if (currentFilters.isNotEmpty)
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: currentFilters.map((filter) {
              return Chip(
                label: Text(filter),
                labelStyle: const TextStyle(color: Colors.white),
                backgroundColor: SpaceTheme.nebulaPurple.withValues(alpha: 0.7),
                onDeleted: () {
                  onRemove(filter);
                },
                deleteIcon: const Icon(Icons.cancel, size: 18),
                deleteIconColor: Colors.white70,
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildFeatureRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isLocked,
    required VoidCallback onTap,
    }) {
    return InkWell(
      onTap: isLocked ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
      opacity: isLocked ? 0.6 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: isLocked ? Colors.grey : SpaceTheme.alienGreen,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SpaceTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
            if (isLocked)
              const Icon(Icons.lock, color: SpaceTheme.starYellow, size: 20)
            else
              const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
      ),
    );
    }
  
  Widget _buildLanguageSettings() {
    return SlideTransition(
      position: _settingAnimations[3],
      child: _buildSettingsCard(
        title: S.of(context)!.language,
        icon: Icons.language,
        children: [
          _buildLanguageSelector(),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SpaceTheme.alienGreen.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.translate,
                color: SpaceTheme.alienGreen,
                size: 24,
              ),
              
              const SizedBox(width: 16),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.of(context)!.appLanguage,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      S.of(context)!.appLanguageDesc,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          _buildLanguageOption(S.of(context)!.languageEnglish, 'en'),
          const SizedBox(height: 12),
          _buildLanguageOption(S.of(context)!.languageGerman, 'de'),
        ],
      ),
    );
  }
  
  Widget _buildLanguageOption(String displayName, String localeCode) {
    final isSelected = currentLocale == localeCode;
    
    return GestureDetector(
      onTap: _isLoading ? null : () => _changeLanguage(localeCode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected 
              ? SpaceTheme.alienGreen.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected 
                ? SpaceTheme.alienGreen 
                : Colors.white.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? SpaceTheme.alienGreen : Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  color: isSelected ? SpaceTheme.alienGreen : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                ),
              ),
            ),
            if (isSelected) 
              Icon(
                Icons.check,
                color: SpaceTheme.alienGreen,
                size: 20,
              ),
            if (_isLoading && isSelected)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(SpaceTheme.alienGreen),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultySettings() {
    return SlideTransition(
      position: _settingAnimations[4],
      child: _buildSettingsCard(
        title: S.of(context)!.difficulty,
        icon: Icons.tune,
        children: [
          Consumer<GameProvider>(
            builder: (context, gameProvider, child) {
              return Column(
                children: [
                  _buildStatRow(
                    label: S.of(context)!.currentGrade,
                    value: S.of(context)!.gradeN(gameProvider.grade),
                    icon: Icons.school,
                    onTap: () => _showGradeSelector(gameProvider),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  _buildStatRow(
                    label: S.of(context)!.currentLevelDesc,
                    value: gameProvider.level.toString(),
                    icon: Icons.trending_up,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Text(
                    _getDifficultyDescription(gameProvider.grade),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildProgressSettings() {
    return SlideTransition(
      position: _settingAnimations[5],
      child: _buildSettingsCard(
        title: S.of(context)!.progress,
        icon: Icons.analytics,
        children: [
          Consumer<GameProvider>(
            builder: (context, gameProvider, child) {
              return Column(
                children: [
                  _buildStatRow(
                    label: S.of(context)!.totalScore,
                    value: gameProvider.score.toString(),
                    icon: Icons.star,
                  ),
                  
                  _buildStatRow(
                    label: S.of(context)!.gamesPlayed,
                    value: gameProvider.totalGamesPlayed.toString(),
                    icon: Icons.games,
                  ),
                  
                  _buildStatRow(
                    label: S.of(context)!.achievements,
                    value: gameProvider.totalAchievements.toString(),
                    icon: Icons.emoji_events,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showResetDialog,
                      icon: const Icon(Icons.refresh),
                      label: Text(S.of(context)!.resetProgress),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SpaceTheme.rocketRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildAboutSection() {
    return SlideTransition(
      position: _settingAnimations[6],
      child: _buildSettingsCard(
        title: S.of(context)!.about,
        icon: Icons.info,
        children: [
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final v = snap.data == null
                  ? '…'
                  : '${snap.data!.version} (${snap.data!.buildNumber})';
              return _buildInfoRow(S.of(context)!.appVersion, v);
            },
          ),
          _buildInfoRow(S.of(context)!.developer, S.of(context)!.developerName),
          _buildInfoRow(S.of(context)!.targetAge, S.of(context)!.targetAgeRange),

          const Divider(color: SpaceTheme.nebulaPurple, height: 24),
          _buildFeatureRow(
            title: S.of(context)!.imprintTitle,
            subtitle: S.of(context)!.viewLegalNotice,
            icon: Icons.gavel_rounded,
            isLocked: false,
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => const ImprintDialog(),
              );
            },
          ),
          
          _buildFeatureRow(
            title: 'Diagnostics',
            subtitle: 'View crash log (stays on device)',
            icon: Icons.bug_report,
            isLocked: false,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DiagnosticsScreen(),
                ),
              );
            },
          ),

          _buildFeatureRow(
            title: 'Eltern-Übersicht',
            subtitle: 'Fortschritt, mit PIN geschützt',
            icon: Icons.family_restroom,
            isLocked: false,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ParentDashboardScreen(),
                ),
              );
            },
          ),

          _buildFeatureRow(
            title: 'Datenschutz',
            subtitle: 'Was auf diesem Gerät gespeichert wird',
            icon: Icons.shield_outlined,
            isLocked: false,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const PrivacyPolicyDialog(),
              );
            },
          ),

          _buildFeatureRow(
            title: 'Alle Daten löschen',
            subtitle: 'Fortschritt auf diesem Gerät zurücksetzen',
            icon: Icons.delete_forever,
            isLocked: false,
            onTap: () => _confirmResetAllData(context),
          ),

          _buildFeatureRow(
            title: S.of(context)!.licensesTitle,
            subtitle: S.of(context)!.viewOssLicenses,
            icon: Icons.article_rounded,
            isLocked: false,
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: S.of(context)!.appName, 
                applicationVersion: '1.0.3',
                applicationLegalese: S.of(context)!.appLegalese, 
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Icon(
                    Icons.rocket_launch,
                    size: 48,
                    color: SpaceTheme.starYellow,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          Text(
            S.of(context)!.aboutApp,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: SpaceTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SpaceTheme.starYellow.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: SpaceTheme.starYellow,
                  size: 24,
                ),
              ),
              
              const SizedBox(width: 16),
              
              Text(
                title,
                style: SpaceTheme.titleStyle.copyWith(fontSize: 20),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          ...children,
        ],
      ),
    );
  }
  
  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    bool isLocked = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: SpaceTheme.alienGreen,
            size: 24,
          ),
          
          const SizedBox(width: 16),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          
          Switch(
            value: value,
            onChanged: isLocked ? null : onChanged,
            activeThumbColor: SpaceTheme.alienGreen,
            inactiveThumbColor: SpaceTheme.moonSilver,
            inactiveTrackColor: SpaceTheme.deepSpace,
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatRow({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              icon,
              color: SpaceTheme.cosmicPink,
              size: 20,
            ),
            
            const SizedBox(width: 12),
            
            Expanded(
              child: Text(
                label,
                style: SpaceTheme.bodyStyle.copyWith(fontSize: 14),
              ),
            ),
            
            Text(
              value,
              style: SpaceTheme.titleStyle.copyWith(
                fontSize: 16,
                color: SpaceTheme.starYellow,
              ),
            ),
            
            if (onTap != null)
              const SizedBox(
                width: 4,
                child: Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: SpaceTheme.bodyStyle.copyWith(fontSize: 14),
          ),
          Text(
            value,
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 14,
              color: SpaceTheme.starYellow,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    debugPrint("[SETTINGS] 💾 Saving setting: $key = $value");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
      
      debugPrint("[SETTINGS] ✅ Successfully saved $key");
      
      final savedValue = _getSettingValue(prefs, key, value.runtimeType);
      debugPrint("[SETTINGS] 🔍 Verification - $key now reads: $savedValue");
      
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Failed to save $key: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
    }
  }
  
  dynamic _getSettingValue(SharedPreferences prefs, String key, Type type) {
    switch (type) {
      case bool:
        return prefs.getBool(key);
      case String:
        return prefs.getString(key);
      case int:
        return prefs.getInt(key);
      case double:
        return prefs.getDouble(key);
      case const (List<String>):
        return prefs.getStringList(key);
      default:
        return prefs.get(key);
    }
  }

  void _changeLanguage(String localeCode) async {
    if (localeCode == currentLocale) {
      debugPrint("[SETTINGS] 🌍 Language unchanged: $localeCode");
      return;
    }
    
    debugPrint("[SETTINGS] 🌍 Changing language from $currentLocale to $localeCode");
    
    setState(() {
      _isLoading = true;
      currentLocale = localeCode;
    });
    
    try {
      await _saveLanguagePreference(localeCode);
      
      if (mounted) {
        _showLanguageChangeDialog(localeCode);
      }
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Failed to change language: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to change language: $e'),
            backgroundColor: SpaceTheme.rocketRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _saveLanguagePreference(String localeCode) async {
    debugPrint("[SETTINGS] 🌍 Saving language preference: $localeCode");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', localeCode);
      
      final savedLocale = prefs.getString('language');
      debugPrint("[SETTINGS] ✅ Language saved successfully");
      debugPrint("[SETTINGS] 🔍 Verification - language now reads: $savedLocale");
      
      final allKeys = prefs.getKeys();
      debugPrint("[SETTINGS] 🗂️ All current preferences:");
      for (final key in allKeys) {
        final value = prefs.get(key);
        debugPrint("[SETTINGS]   $key: $value");
      }
      
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Failed to save language preference: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
      rethrow;
    }
  }
  
  void _showLanguageChangeDialog(String localeCode) {
    debugPrint("[SETTINGS] 🔄 Showing language change dialog for: $localeCode");
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          S.of(context)!.languageChanged,
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          S.of(context)!.languageChangedDesc,
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint("[SETTINGS] 🔄 User chose to restart later");
              Navigator.of(context).pop();
            },
            child: Text(
              S.of(context)!.later,
              style: TextStyle(color: SpaceTheme.moonSilver),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              debugPrint("[SETTINGS] 🔄 User chose to restart now");
              Navigator.of(context).pop();
              _triggerAppRestart();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.alienGreen,
            ),
            child: Text(S.of(context)!.restartNow),
          ),
        ],
      ),
    );
  }

  void _showGradeSelector(GameProvider gameProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          S.of(context)!.selectGrade,
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [1, 2, 3, 4].map((grade) { 
            final isSelected = gameProvider.grade == grade;
            return GestureDetector(
              onTap: () {
                debugPrint("[SETTINGS] 🎓 Grade changed to: $grade");
                gameProvider.setGrade(grade);
                Navigator.of(context).pop();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? SpaceTheme.starYellow.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected 
                        ? SpaceTheme.starYellow 
                        : Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.school,
                      color: isSelected ? SpaceTheme.starYellow : Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      S.of(context)!.gradeN(grade),
                      style: TextStyle(
                        color: isSelected ? SpaceTheme.starYellow : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _getDifficultyDescription(grade),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              S.of(context)!.cancel,
              style: TextStyle(color: SpaceTheme.moonSilver),
            ),
          ),
        ],
      ),
    );
  }
  
  String _getDifficultyDescription(int grade) {
    switch (grade) {
      case 1:
        return S.of(context)!.difficultyDescGrade3;
      case 2:
        return S.of(context)!.difficultyDescGrade4;
      case 3:
        return S.of(context)!.difficultyDescGrade5;
      case 4:
        return S.of(context)!.difficultyDescGrade6;
      default:
        return '';
    }
  }

  void _triggerAppRestart() {
    debugPrint("[SETTINGS] 🔄 Triggering app restart notification");
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context)!.restartToApplyChanges),
        backgroundColor: SpaceTheme.alienGreen,
        duration: Duration(seconds: 4),
      ),
    );
  }
  
  /// Parental-gated full reset. Math challenge first, then existing
  /// confirmation dialog.
  void _confirmResetAllData(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ParentalGateDialog(
        onSuccess: () {
          Navigator.of(context).pop();
          _showResetDialog();
        },
      ),
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          S.of(context)!.resetProgress,
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          S.of(context)!.resetProgressConfirmation,
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              S.of(context)!.cancel,
              style: TextStyle(color: SpaceTheme.moonSilver),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              debugPrint("[SETTINGS] 🗑️ Resetting all game progress");
              context.read<GameProvider>().resetGame();
              context.read<SriService>().clearAllData();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.of(context)!.progressResetSuccess),
                  backgroundColor: SpaceTheme.alienGreen,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.rocketRed,
            ),
            child: Text(S.of(context)!.reset),
          ),
        ],
      ),
    );
  }
}