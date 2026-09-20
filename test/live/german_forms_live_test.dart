@TestOn('vm')
library;

// Every German word form the games *display* has to be a form the pack
// carries — not one the app derived.
//
//     WU_PACK_DE=/path/to/grundwortschatz.db flutter test test/live/german_forms_live_test.dart
//
// The app copies German almost everywhere: a gloss, an example sentence, an
// inflected form out of Wiktionary's table. In four places it composes German
// itself, and that is where wrong grammar can reach a child while every test
// stays green — a structural check cannot tell "du sprichst" from "du
// sprechst", and a reading pass samples a dozen items per game.
//
// So this asks the pack, over every verb and compound it ships:
//
//   Großstadt        every frame it would show — ICH …, DU …, WIR … — is a
//                    form the pack lists, or the infinitive for a verb that
//                    does not separate.
//   Conjugation      the same, for the drill's present table.
//   Trennbare Verben every tile's form is one the pack lists, and the split
//                    parts rejoin into it.
//   Wortbaumeister   both halves are catalogue nouns and rejoin into the
//                    compound.
//
// It is a live test because it needs the real pack; CI fetches it. The point
// is the *coverage*: thousands of verbs, not the six a reading pass sees.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/dictionary_database_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/services/conjugation_drill_service.dart';
import 'package:WortUniversum/features/games/services/grossstadt_service.dart';
import 'package:WortUniversum/features/games/services/verbtrenner_service.dart';
import 'package:WortUniversum/features/games/services/wortbaumeister_service.dart';

/// Forms as the pack writes them, lowercased and stripped of the markers
/// Wiktionary carries into the text ("selten: leid!", "flieg ab!").
Set<String> packForms(GermanWord verb) => {
      for (final inflection in verb.wiktionaryInflections)
        if (inflection['form_text'] case final String form) _normalize(form),
    };

String _normalize(String form) => form
    .toLowerCase()
    .replaceAll(RegExp(r'^[^:]{1,12}:\s*'), '')
    .replaceAll('!', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  final germanPack = Platform.environment['WU_PACK_DE'];
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late VocabularyService vocabulary;
  late GameProvider settings;

  final skip = germanPack == null
      ? 'set WU_PACK_DE=/path/to/decompressed/grundwortschatz.db'
      : null;

  setUpAll(() async {
    if (germanPack == null) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('german_forms_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    final pack = kLanguagePacks['de']!;
    await File('${directory.path}/${pack.databaseName}')
        .writeAsBytes(await File(germanPack).readAsBytes());
    vocabulary = VocabularyService();
    await vocabulary.initialize(learningLanguage: 'de');
    settings = GameProvider(
      progressService: ProgressService(),
      sriService: SriService(),
      cognitiveProfileService: CognitiveProfileService(),
      prefs: await SharedPreferences.getInstance(),
    );
  });

  tearDownAll(() async {
    if (germanPack == null) return;
    await DictionaryDatabaseService().close();
    await directory.delete(recursive: true);
  });

  /// Every verb the pack carries an inflection table for, hydrated.
  Future<List<GermanWord>> verbs() async {
    final light = vocabulary
        .getAllWords(settings)
        .where((word) =>
            word.wordType == GermanWordType.verb &&
            word.isHeadword &&
            word.has(WordFeature.inflections))
        .toList();
    return vocabulary.hydrate(light);
  }

  test('Großstadt shows no form the pack does not list', () async {
    final wrong = <String>[];
    var checked = 0;
    for (final verb in await verbs()) {
      if (!isInfinitive(verb.lemma)) continue;
      final forms = packForms(verb);
      for (final person in ['ich', 'du', 'wir']) {
        final form = conjugatedForm(verb, person);
        if (form == null) continue;
        checked++;
        final normalized = _normalize(form);
        final fine = forms.contains(normalized) ||
            (person == 'wir' && normalized == verb.lemma.toLowerCase());
        if (!fine) wrong.add('${verb.word}: $person → "$form"');
      }
    }
    // ignore: avoid_print
    print('Großstadt: $checked frames checked');
    expect(checked, greaterThan(500), reason: 'almost nothing was checked');
    expect(wrong, isEmpty,
        reason: '$checked frames checked; these are the app\'s invention, '
            'not the pack\'s German:\n  ${wrong.take(25).join('\n  ')}');
  }, timeout: const Timeout(Duration(minutes: 15)), skip: skip);

  test('the conjugation drill shows no form the pack does not list', () async {
    final wrong = <String>[];
    var checked = 0;
    for (final verb in await verbs()) {
      final praesens = getPraesensForWord(verb);
      if (praesens == null) continue;
      final forms = packForms(verb);
      for (final entry in praesens.entries) {
        checked++;
        if (!forms.contains(_normalize(entry.value))) {
          wrong.add('${verb.word}: ${entry.key} → "${entry.value}"');
        }
      }
    }
    // ignore: avoid_print
    print('drill: $checked forms checked');
    expect(checked, greaterThan(500), reason: 'almost nothing was checked');
    expect(wrong, isEmpty,
        reason: '$checked forms checked:\n  ${wrong.take(25).join('\n  ')}');
  }, timeout: const Timeout(Duration(minutes: 15)), skip: skip);

  test('every Trennbare Verben tile is a form the pack lists', () async {
    final wrong = <String>[];
    var checked = 0;
    for (final verb in await verbs()) {
      if (!isVerbSeparable(verb)) continue;
      final forms = packForms(verb);
      for (final pair in pairsFromVerb(verb)) {
        checked++;
        if (!forms.contains(_normalize(pair.formText))) {
          wrong.add('${verb.word}: tile "${pair.formText}"');
          continue;
        }
        // The two halves are what the learner assembles; they have to make
        // the form back up, apart or joined.
        final rejoined = pair.shouldBeSeparated
            ? '${pair.part1} ${pair.part2}'
            : '${pair.part1}${pair.part2}';
        if (_normalize(rejoined) != _normalize(pair.formText)) {
          wrong.add('${verb.word}: "${pair.part1}" + "${pair.part2}" '
              '≠ "${pair.formText}"');
        }
      }
    }
    // ignore: avoid_print
    print('verbtrenner: $checked tiles checked');
    expect(checked, greaterThan(100), reason: 'almost nothing was checked');
    expect(wrong, isEmpty,
        reason: '$checked tiles checked:\n  ${wrong.take(25).join('\n  ')}');
  }, timeout: const Timeout(Duration(minutes: 15)), skip: skip);

  test('every compound splits into two nouns and back', () async {
    final nouns = vocabulary
        .getAllWords(settings)
        .where((word) => word.wordType == GermanWordType.substantiv)
        .toList();
    final bySpelling = {
      for (final noun in nouns) noun.word.toLowerCase(): noun,
    };
    final wrong = <String>[];
    var checked = 0;
    // Every split the game could ever make, not the twenty a round shows.
    for (final noun in nouns) {
      if (noun.word.length < minCompoundLength) continue;
      final split = findValidCompoundSplit(noun.word, bySpelling);
      if (split == null) continue;
      checked++;
      final rejoined = '${split.part1}${split.part2}'.toLowerCase();
      if (rejoined != noun.word.toLowerCase()) {
        wrong.add('${noun.word}: "${split.part1}" + "${split.part2}" '
            '→ "$rejoined"');
      }
      for (final part in [split.part1, split.part2]) {
        final entry = bySpelling[part.toLowerCase()];
        // A Fugen-s is the one licence the game takes: Arbeit + s + platz.
        final withoutFuge = part.toLowerCase().endsWith('s')
            ? bySpelling[part.toLowerCase().substring(0, part.length - 1)]
            : null;
        if (entry == null && withoutFuge == null) {
          wrong.add('${noun.word}: "$part" is not a noun the pack carries');
        }
      }
    }
    // ignore: avoid_print
    print('wortbaumeister: $checked compounds checked');
    expect(checked, greaterThan(300), reason: 'almost nothing was checked');
    expect(wrong, isEmpty,
        reason:
            '$checked compounds checked:\n  ${wrong.take(25).join('\n  ')}');
  }, timeout: const Timeout(Duration(minutes: 15)), skip: skip);
}
