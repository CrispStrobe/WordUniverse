@TestOn('vm')
library;

// Prints what the games would actually ask a learner, as text or JSON, so that
// the content can be reviewed in bulk instead of by playing.
//
//   WU_DUMP=all WU_DUMP_COUNT=25 flutter test test/audit/challenge_dump_test.dart
//   WU_DUMP=homophone_drill WU_DUMP_GRADE=4 WU_DUMP_FORMAT=json ...
//   WU_DUMP=all WU_DUMP_LANG=de WU_PACK_DE=/path/to/grundwortschatz.db ...
//
// It is a test only because the app's code needs a Flutter VM; nothing here
// asserts anything about the content. The point is the output: a reviewer — or
// an agent — reads a few hundred generated items and judges whether the
// question is answerable, whether the marked answer is right, and whether the
// distractors are fair.
//
// Coverage is what can be generated headlessly today: the games whose
// challenge construction already lives in a service. The games that build
// theirs inside the widget are listed at the end of a run, so the gap is
// visible rather than implied.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:archive/archive.dart';

import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/dictionary_database_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/services/false_friend_service.dart';
import 'package:WortUniversum/features/games/services/homophone_drill_service.dart';
import 'package:WortUniversum/features/games/services/phrasal_verb_service.dart';
import 'package:WortUniversum/features/games/services/wortfalle_service.dart';
import 'package:WortUniversum/features/home/services/word_of_the_day_service.dart';

/// One generated item, in the shape a reviewer needs: what is asked, what the
/// learner picks from, and which pick is marked correct.
class Item {
  Item({
    required this.game,
    required this.prompt,
    this.options = const [],
    this.answer,
    this.notes = const {},
  });

  final String game;
  final String prompt;
  final List<String> options;
  final String? answer;
  final Map<String, Object?> notes;

  Map<String, Object?> toJson() => {
        'game': game,
        'prompt': prompt,
        if (options.isNotEmpty) 'options': options,
        if (answer != null) 'answer': answer,
        if (notes.isNotEmpty) 'notes': notes,
      };

  String toText() {
    final buffer = StringBuffer()..writeln('  $prompt');
    if (options.isNotEmpty) {
      for (final option in options) {
        buffer.writeln('    ${option == answer ? '✓' : ' '} $option');
      }
    } else if (answer != null) {
      buffer.writeln('    ✓ $answer');
    }
    if (notes.isNotEmpty) {
      buffer.writeln('    · ${notes.entries.map((e) => '${e.key}: ${e.value}').join('  ')}');
    }
    return buffer.toString();
  }
}

/// Games whose challenge construction is callable without a widget.
typedef Generator = Future<List<Item>> Function(_Context context);

/// Which pack a generator makes sense for. The menu filters games by learning
/// language, so dumping a German-only game against the English pack would
/// review content no learner is offered.
const Map<String, List<String>> generatorLanguages = {
  'homophone_drill': ['en'],
  'wortfalle': ['de'],
  'false_friends': ['en'],
  'phrasal_verb_power': ['en'],
  'phrasal_verb_match': ['en'],
  'word_of_the_day': ['en', 'de'],
};

class _Context {
  _Context(this.vocabulary, this.settings, this.grade, this.count, this.rng);
  final VocabularyService vocabulary;
  final GameProvider settings;
  final int grade;
  final int count;
  final Random rng;
}

final Map<String, Generator> generators = {
  'homophone_drill': (c) async {
    final groups = groupsForMode(HomophoneGameMode.homophones);
    final wanted = <String>{
      for (final group in groups)
        for (final word in group.words) word.toLowerCase(),
    };
    final entries = <dynamic>[];
    for (final spelling in wanted) {
      final entry = c.vocabulary.findByWrittenForm(spelling);
      if (entry != null && entry.word.toLowerCase() == spelling) {
        entries.add(entry);
      }
    }
    final words = await c.vocabulary.hydrate(entries.cast());
    return buildHomophoneChallenges(
      allWords: words,
      gradeLevel: c.grade,
      maxChallenges: c.count,
      rng: c.rng,
      groups: groups,
    )
        .map((ch) => Item(
              game: 'homophone_drill',
              prompt: ch.sentence,
              options: ch.options,
              answer: ch.options[ch.correctIndex],
              notes: {'group': ch.groupWords.join('/')},
            ))
        .toList();
  },
  'wortfalle': (c) async => buildWortfalleChallenges(
        maxChallenges: c.count,
        rng: c.rng,
      )
          .map((ch) => Item(
                game: 'wortfalle',
                prompt: ch.sentence,
                options: ch.options,
                answer: ch.options[ch.correctIndex],
                notes: {'pair': ch.words.join('/')},
              ))
          .toList(),
  'false_friends': (c) async {
    final friends = await c.vocabulary.getFalseFriends();
    return buildFalseFriendChallenges(
      friends: friends,
      maxChallenges: c.count,
      rng: c.rng,
    )
        .map((ch) => Item(
              game: 'false_friends',
              prompt: 'What does "${ch.english}" really mean?',
              options: ch.options,
              answer: ch.options[ch.correctIndex],
              notes: {'trap': '${ch.german} = ${ch.germanMeans}'},
            ))
        .toList();
  },
  'phrasal_verb_power': (c) async {
    final verbs = await c.vocabulary.getPhrasalVerbs();
    return buildPhrasalChallenges(
      verbs: verbs,
      gradeLevel: c.grade,
      maxChallenges: c.count,
      rng: c.rng,
    )
        .map((ch) => Item(
              game: 'phrasal_verb_power',
              prompt: ch.sentence,
              options: ch.options,
              answer: ch.options[ch.correctIndex],
              notes: {'phrasal': ch.phrasal, 'means': ch.meaning},
            ))
        .toList();
  },
  'phrasal_verb_match': (c) async {
    final verbs = await c.vocabulary.getPhrasalVerbs();
    return buildPhrasalMatchChallenges(
      verbs: verbs,
      gradeLevel: c.grade,
      maxChallenges: c.count,
      rng: c.rng,
    )
        .map((ch) => Item(
              game: 'phrasal_verb_match',
              prompt: 'What does "${ch.phrasal}" mean?',
              options: ch.options,
              answer: ch.options[ch.correctIndex],
            ))
        .toList();
  },
  'word_of_the_day': (c) async {
    final items = <Item>[];
    final pool = c.vocabulary.getAllWords(c.settings);
    for (var day = 0; day < c.count; day++) {
      final date = DateTime(2026, 1, 1).add(Duration(days: day));
      final chosen = pickWordOfTheDay(pool, date, targetBand: c.grade);
      if (chosen == null) continue;
      final word = await c.vocabulary.hydrateOne(chosen);
      items.add(Item(
        game: 'word_of_the_day',
        prompt: '${date.toIso8601String().substring(0, 10)}: ${word.displayName}',
        answer: word.apiEnrichment?.definitions.firstOrNull,
        notes: {'grade': word.gradeLevel, 'cefr': word.cefrLevel ?? '—'},
      ));
    }
    return items;
  },
};

/// Games that still build their challenges inside the widget, so this harness
/// cannot reach them yet. Printed after a run so the gap stays visible.
const notYetReachable = [
  'definition_quiz', 'synonym_flash', 'antonym_flash', 'hypernym_flash',
  'syllable_count', 'cloze_flash', 'proverb_cloze', 'expression_flash',
  'sentence_completion', 'translation_flash', 'reverse_translation_flash',
  'spelling_spotter', 'sri_review', 'conjugation_drill', 'word_class_flash',
  'word_sort', 'word_type_whirl', 'grossschreib', 'grossstadt', 'verbtrenner',
  'wortbaumeister', 'word_find', 'word_snake', 'word_memory', 'word_builder',
];

void main() {
  final requested = Platform.environment['WU_DUMP'];
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dump generated challenges', () async {
    if (requested == null || requested.isEmpty) {
      markTestSkipped('set WU_DUMP=all or WU_DUMP=<game>[,<game>...]');
      return;
    }
    final language = Platform.environment['WU_DUMP_LANG'] ?? 'en';
    final count = int.tryParse(Platform.environment['WU_DUMP_COUNT'] ?? '') ?? 20;
    final grade = int.tryParse(Platform.environment['WU_DUMP_GRADE'] ?? '') ?? 3;
    final asJson = Platform.environment['WU_DUMP_FORMAT'] == 'json';
    final seed = int.tryParse(Platform.environment['WU_DUMP_SEED'] ?? '') ?? 1;

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('wu_dump_');
    addTearDown(() => directory.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );

    final pack = kLanguagePacks[language]!;
    final List<int> bytes;
    if (language == 'en') {
      bytes = GZipDecoder()
          .decodeBytes(await File('assets/grundwortschatz_en.db.gz').readAsBytes());
    } else {
      final path = Platform.environment['WU_PACK_DE'];
      if (path == null) {
        markTestSkipped('set WU_PACK_DE=/path/to/decompressed/grundwortschatz.db');
        return;
      }
      bytes = await File(path).readAsBytes();
    }
    await File('${directory.path}/${pack.databaseName}').writeAsBytes(bytes);

    final vocabulary = VocabularyService();
    await vocabulary.initialize(learningLanguage: language);
    addTearDown(DictionaryDatabaseService().close);
    final settings = GameProvider(
      progressService: ProgressService(),
      sriService: SriService(),
      cognitiveProfileService: CognitiveProfileService(),
      prefs: await SharedPreferences.getInstance(),
    );

    final names = requested == 'all'
        ? generators.keys.toList()
        : requested.split(',').map((n) => n.trim()).toList();
    final buffer = StringBuffer();
    var total = 0;

    for (final name in names) {
      final supported = generatorLanguages[name] ?? const ['en', 'de'];
      if (!supported.contains(language)) {
        buffer.writeln('\n── $name  skipped: $language is not one of '
            '${supported.join('/')}');
        continue;
      }
      final generator = generators[name];
      if (generator == null) {
        buffer.writeln('!! unknown generator "$name" — '
            'available: ${generators.keys.join(', ')}');
        continue;
      }
      final items = await generator(
          _Context(vocabulary, settings, grade, count, Random(seed)));
      total += items.length;
      if (asJson) {
        for (final item in items) {
          buffer.writeln(jsonEncode(item.toJson()));
        }
      } else {
        buffer.writeln('\n── $name  (${items.length} items, '
            '$language, grade $grade) ${'─' * 20}');
        for (final item in items) {
          buffer.write(item.toText());
        }
      }
    }

    if (!asJson) {
      buffer.writeln('\n$total items from ${names.length} generator(s). '
          'Not reachable headlessly yet (${notYetReachable.length} games): '
          '${notYetReachable.join(', ')}.');
    }

    final out = Platform.environment['WU_DUMP_OUT'];
    if (out != null) {
      await File(out).writeAsString(buffer.toString());
      // ignore: avoid_print
      print('wrote $total items to $out');
    } else {
      // ignore: avoid_print
      print(buffer.toString());
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
