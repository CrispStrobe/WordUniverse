@TestOn('vm')
library;

// Every string a game shows is either the pack's, verbatim, or a
// transformation of it this test can undo.
//
//     WU_PACK=1 [WU_PACK_DE=...] flutter test test/live/item_provenance_live_test.dart
//
// german_forms_live_test.dart checks the German the app *composes*. English is
// the other case: the app composes almost none of it — it blanks a word out of
// a sentence the pack wrote, redacts a headword out of a gloss, offers a
// translation the pack lists. So the question is not "is this grammatical"
// (the pack's sentence was) but "is this still the pack's sentence".
//
// That is checkable, exactly, and it catches the whole class of bug where an
// offset, an inflection or a redaction quietly changes what the learner reads:
//
//   cloze games      before + the blanked form + after == the source text
//   sentence gaps    the same, against one of the pack's grade examples
//   homophones       filling the gap back in gives a sentence the pack ships
//   definitions      the prompt is a pack gloss with the headword redacted
//   translations     the answer is one the pack lists for that word
//   syllables        the keyed bucket is the pack's own hyphenation, counted
//   phrasal verbs    the filled sentence contains the phrasal verb it teaches

import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:archive/archive.dart';

import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/dictionary_database_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/services/cloze_service.dart';
import 'package:WortUniversum/features/games/services/definition_quiz_service.dart';
import 'package:WortUniversum/features/games/services/homophone_drill_service.dart';
import 'package:WortUniversum/features/games/services/phrasal_verb_service.dart';
import 'package:WortUniversum/features/games/services/sentence_completion_service.dart';
import 'package:WortUniversum/features/games/services/syllable_count_service.dart';
import 'package:WortUniversum/features/games/services/translation_flash_service.dart';

const _grade = 3;

/// How many words each check draws on, and where in the catalogue it starts.
///
/// Every generator here was seeded `Random(_seed)`, so the oracle re-derived the
/// same ~3,700 items on every run and had never looked past them — the same
/// blindness the nightly sweep had. The forms oracle beside it does not
/// sample at all: it walks every verb the pack carries a table for, which is
/// the better shape where the space allows it. This one cannot, because its
/// pool is the whole catalogue, so it explores instead.
///
/// WU_PROVENANCE_SEED moves the window and is printed with the result, so a
/// failure is reproduced exactly. The default is 1, which is what every run
/// until now used, to the item.
int get _seed =>
    int.tryParse(Platform.environment['WU_PROVENANCE_SEED'] ?? '') ?? 1;

int get _pool =>
    int.tryParse(Platform.environment['WU_PROVENANCE_POOL'] ?? '') ?? 400;

void main() {
  final enabled = Platform.environment['WU_PACK'] == '1';
  final germanPack = Platform.environment['WU_PACK_DE'];
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late VocabularyService vocabulary;
  late GameProvider settings;

  Future<void> install(String language, List<int> bytes) async {
    final pack = kLanguagePacks[language]!;
    await File('${directory.path}/${pack.databaseName}').writeAsBytes(bytes);
    vocabulary = VocabularyService();
    await vocabulary.initialize(learningLanguage: language);
    settings = GameProvider(
      progressService: ProgressService(),
      sriService: SriService(),
      cognitiveProfileService: CognitiveProfileService(),
      prefs: await SharedPreferences.getInstance(),
    );
  }

  setUp(() async {
    if (!enabled) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('provenance_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
  });

  tearDown(() async {
    if (!enabled) return;
    await DictionaryDatabaseService().close();
    await directory.delete(recursive: true);
  });

  Future<List<GermanWord>> pool(WordFeature feature,
          {bool Function(GermanWord)? where}) =>
      vocabulary.takeWordsWithFeature(
        feature,
        settingsProvider: settings,
        gradeLevel: _grade,
        limit: _pool,
        where: where,
        random: Random(_seed),
      );

  void provenanceContract(String label, Future<void> Function() installPack,
      {String? skipReason, required bool isGerman}) {
    group(label, () {
      test('a blanked sentence puts itself back together', () async {
        await installPack();
        final words = await pool(WordFeature.examples,
            where: (w) => !w.isProperNoun && !w.word.contains(' '));
        final challenges = buildClozeChallenges(
          pool: words,
          texts: (w) => [
            for (final example in w.apiEnrichment?.examples ?? const [])
              if (example.text case final text?) text,
          ],
          maxChallenges: 400,
          rng: Random(_seed),
        );
        final wrong = <String>[];
        for (final challenge in challenges) {
          final rebuilt =
              '${challenge.before}${challenge.matchedForm}${challenge.after}';
          if (rebuilt != challenge.source) {
            wrong.add('${challenge.word.word}: "$rebuilt" ≠ '
                '"${challenge.source}"');
          }
        }
        // ignore: avoid_print
        print('$label cloze: ${challenges.length} sentences (seed $_seed)');
        expect(challenges.length, greaterThan(20));
        expect(wrong, isEmpty, reason: wrong.take(10).join('\n  '));
      }, skip: skipReason, timeout: const Timeout(Duration(minutes: 10)));

      test('a sentence gap is one of the pack\'s own sentences', () async {
        await installPack();
        final words = await pool(WordFeature.gradeExamples,
            where: (w) => !w.isProperNoun && !w.word.contains(' '));
        final challenges = buildSentenceChallenges(
            pool: words,
            gradeIndex: _grade,
            maxChallenges: 400,
            rng: Random(_seed));
        final wrong = <String>[];
        for (final challenge in challenges) {
          final rebuilt =
              '${challenge.before}${challenge.matchedForm}${challenge.after}';
          final examples =
              challenge.word.apiEnrichment?.gradeExamples?.values.expand(
                    (sentences) => sentences,
                  ) ??
                  const <String>[];
          if (!examples.contains(rebuilt)) {
            wrong.add('${challenge.word.word}: "$rebuilt"');
          }
        }
        // ignore: avoid_print
        print(
            '$label sentence completion: ${challenges.length} sentences (seed $_seed)');
        expect(challenges.length, greaterThan(20));
        expect(wrong, isEmpty, reason: wrong.take(10).join('\n  '));
      }, skip: skipReason, timeout: const Timeout(Duration(minutes: 10)));

      test('a definition prompt is a pack gloss with the word redacted',
          () async {
        await installPack();
        final words = await pool(WordFeature.definitions,
            where: (w) => !w.isProperNoun && w.isHeadword);
        final wrong = <String>[];
        var checked = 0;
        for (final word in words) {
          final challenge = buildDefinitionChallenge(
              word: word, pool: words, isGerman: isGerman, rng: Random(_seed));
          if (challenge == null) continue;
          checked++;
          // The two transformations the quiz makes, undone: a long sense is
          // cut at its first clause, and the headword is redacted out.
          final redacted = word.displayDefinitions
              .expand(
                  (definition) => [definition, firstClauseIfLong(definition)])
              .map((definition) => definition.replaceAll(
                    RegExp('\\b${RegExp.escape(word.word)}\\b',
                        caseSensitive: false),
                    '___',
                  ))
              .toSet();
          if (!redacted.contains(challenge.definition)) {
            wrong.add('${word.word}: "${challenge.definition}"');
          }
        }
        // ignore: avoid_print
        print('$label definition quiz: $checked prompts (seed $_seed)');
        expect(checked, greaterThan(20));
        expect(wrong, isEmpty, reason: wrong.take(10).join('\n  '));
      }, skip: skipReason, timeout: const Timeout(Duration(minutes: 10)));

      test('the keyed syllable count is the pack\'s hyphenation', () async {
        await installPack();
        final words = await pool(WordFeature.hyphenation);
        final challenges =
            buildSyllableChallenges(pool: words, maxChallenges: 400);
        final wrong = <String>[];
        for (final challenge in challenges) {
          final counted = challenge.word.hyphenation
              .map(countSyllables)
              .firstWhere((count) => count != null && count >= 1,
                  orElse: () => null);
          if (counted != challenge.syllableCount ||
              syllableBucket(counted!) != challenge.correctBucket) {
            wrong.add('${challenge.word.word}: keyed '
                '${challenge.syllableCount} / bucket '
                '${challenge.correctBucket}');
          }
        }
        // ignore: avoid_print
        print(
            '$label syllable count: ${challenges.length} items (seed $_seed)');
        expect(challenges.length, greaterThan(20));
        expect(wrong, isEmpty, reason: wrong.take(10).join('\n  '));
      }, skip: skipReason, timeout: const Timeout(Duration(minutes: 10)));
    });
  }

  provenanceContract('english pack', () async {
    final gz = File('assets/grundwortschatz_en.db.gz');
    expect(gz.existsSync(), isTrue, reason: 'run from the repository root');
    await install('en', GZipDecoder().decodeBytes(await gz.readAsBytes()));
  },
      isGerman: false,
      skipReason: enabled ? null : 'set WU_PACK=1 to run against real packs');

  provenanceContract('german pack',
      () async => install('de', await File(germanPack!).readAsBytes()),
      isGerman: true,
      skipReason: !enabled
          ? 'set WU_PACK=1 to run against real packs'
          : germanPack == null
              ? 'set WU_PACK_DE=/path/to/grundwortschatz.db'
              : null);

  // English-only games: what the pack teaches has to survive into the item.
  group('english only', () {
    final skipReason =
        enabled ? null : 'set WU_PACK=1 to run against real packs';

    Future<void> installEnglish() async {
      final gz = File('assets/grundwortschatz_en.db.gz');
      await install('en', GZipDecoder().decodeBytes(await gz.readAsBytes()));
    }

    test('a homophone gap fills back into a sentence the pack ships', () async {
      await installEnglish();
      final groups = groupsForMode(HomophoneGameMode.homophones);
      final wanted = <String>{
        for (final group in groups)
          for (final word in group.words) word.toLowerCase(),
      };
      final entries = <GermanWord>[];
      for (final spelling in wanted) {
        final entry = vocabulary.findByWrittenForm(spelling);
        if (entry != null && entry.word.toLowerCase() == spelling) {
          entries.add(entry);
        }
      }
      final words = await vocabulary.hydrate(entries);
      final challenges = buildHomophoneChallenges(
          allWords: words,
          gradeLevel: _grade,
          maxChallenges: 200,
          rng: Random(_seed),
          groups: groups);
      final wrong = <String>[];
      for (final challenge in challenges) {
        final word = words.firstWhere(
            (w) => w.word.toLowerCase() == challenge.correctWord.toLowerCase());
        final filled =
            challenge.sentence.replaceAll('___', challenge.correctWord);
        final examples = word.apiEnrichment?.gradeExamples?.values
                .expand((sentences) => sentences) ??
            const <String>[];
        if (!examples.any(
            (sentence) => sentence.toLowerCase() == filled.toLowerCase())) {
          wrong.add('${challenge.correctWord}: "$filled"');
        }
        if (!challenge.options.contains(challenge.correctWord)) {
          wrong.add('${challenge.correctWord}: not among its own options');
        }
      }
      // ignore: avoid_print
      print('homophone drill: ${challenges.length} items (seed $_seed)');
      expect(challenges.length, greaterThan(20));
      expect(wrong, isEmpty, reason: wrong.take(10).join('\n  '));
    }, skip: skipReason, timeout: const Timeout(Duration(minutes: 10)));

    test('a phrasal verb sentence contains the phrasal verb', () async {
      await installEnglish();
      final verbs = await vocabulary.getPhrasalVerbs();
      final challenges = buildPhrasalChallenges(
          verbs: verbs,
          gradeLevel: _grade,
          maxChallenges: 400,
          rng: Random(_seed));
      final wrong = <String>[];
      for (final challenge in challenges) {
        final keyed = challenge.options[challenge.correctIndex];
        final filled =
            challenge.sentence.replaceAll('___', keyed).toLowerCase();
        // The particle is the answer, so it is the part that has to line up.
        // The verb cannot be: "carry out" is taught and the sentence says
        // "carries out", which nothing here can match without lemmatising
        // English. What this can insist on is that the keyed option is one of
        // the phrasal verb's own particles, and that it ends up in what the
        // learner reads.
        // One of the phrasal's own particles — "get on with" is keyed on
        // "on", not on "with".
        final particles =
            challenge.phrasal.toLowerCase().split(' ').skip(1).toList();
        if (!particles.contains(keyed.toLowerCase())) {
          wrong.add('"${challenge.phrasal}" keyed "$keyed"');
        }
        if (!filled.contains(keyed.toLowerCase())) {
          wrong.add('"$keyed" not in "$filled"');
        }
      }
      // ignore: avoid_print
      print('phrasal verbs: ${challenges.length} items (seed $_seed)');
      expect(challenges.length, greaterThan(20));
      expect(wrong, isEmpty, reason: wrong.take(10).join('\n  '));
    }, skip: skipReason, timeout: const Timeout(Duration(minutes: 10)));

    test('a translation is one the pack lists for that word', () async {
      await installEnglish();
      // English learns German words; the German pack is the one with
      // translations, so this runs there. Kept here so both directions of the
      // same check live together.
      if (germanPack == null) {
        markTestSkipped('set WU_PACK_DE=/path/to/grundwortschatz.db');
        return;
      }
      await DictionaryDatabaseService().close();
      await install('de', await File(germanPack).readAsBytes());
      final words = await pool(WordFeature.translations,
          where: (w) => !w.isProperNoun && w.isHeadword);
      final challenges = buildTranslationChallenges(
          pool: words, maxChallenges: 400, rng: Random(_seed));
      final wrong = <String>[];
      for (final challenge in challenges) {
        final listed = englishTranslations(challenge.word);
        if (!listed.contains(challenge.translation.toLowerCase())) {
          wrong.add('${challenge.word.word} → ${challenge.translation}');
        }
      }
      // ignore: avoid_print
      print('translation flash: ${challenges.length} items (seed $_seed)');
      expect(challenges.length, greaterThan(20));
      expect(wrong, isEmpty, reason: wrong.take(10).join('\n  '));
    }, skip: skipReason, timeout: const Timeout(Duration(minutes: 10)));
  });
}
