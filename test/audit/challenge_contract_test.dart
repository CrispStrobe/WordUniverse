@TestOn('vm')
library;

// What has to be true of every item every game generates, checked over the
// whole grade range of both packs — a few thousand items per run.
//
// challenge_dump_test.dart prints items for a person to judge; the judgements
// that do not need a person are here. Everything this file asserts was a real
// bug first: options that repeated, a prompt that contained its own answer, a
// game whose pool had been empty for weeks without a single test noticing.
//
// The English pack ships as an asset, so the en half runs everywhere,
// including CI. The German pack is a download; set WU_PACK_DE to a
// decompressed copy to check it too, or the de half skips.
//
//   flutter test test/audit/challenge_contract_test.dart
//   WU_PACK_DE=/path/to/grundwortschatz.db flutter test test/audit/challenge_contract_test.dart

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'challenge_harness.dart';

/// Grades a learner can be in. Every game is asked for every one of them.
/// Grades a learner can be in. Every game is asked for every one of them —
/// or for the ones WU_CONTRACT_GRADES names, so a sweep can be sharded.
List<int> get _grades {
  final requested = Platform.environment['WU_CONTRACT_GRADES'];
  if (requested == null || requested.isEmpty) return const [1, 2, 3, 4, 5, 6];
  return [
    for (final part in requested.split(','))
      if (int.tryParse(part.trim()) case final grade?) grade,
  ];
}

/// Items requested per game per grade.
///
/// Ten on every push: enough to catch a generator that broke, fast enough not
/// to be noticed. The nightly sweep raises it far higher — the games can
/// produce on the order of a hundred thousand distinct items, and a rule that
/// holds for ten of them is not yet a rule that holds.
int get _perGrade =>
    int.tryParse(Platform.environment['WU_CONTRACT_COUNT'] ?? '') ?? 10;

/// The games to check, or all of them.
///
/// Several games draw on a table small enough to finish: 400 phrasal verbs,
/// 62 false friends, a few hundred mutual antonym pairs. For those, sampling
/// is the wrong shape of check — asked for more items than the table holds,
/// the generator simply runs out, and what comes back is every item the game
/// can ever produce. Naming them lets one job do that while the sweep keeps
/// sampling the games whose space has no end.
List<String>? get _games {
  final requested = Platform.environment['WU_CONTRACT_GAMES'];
  if (requested == null || requested.isEmpty) return null;
  return [
    for (final part in requested.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// What the generators are seeded with, offset per grade.
///
/// It used to be the grade alone, which made every run check the same items —
/// a fine regression detector and a useless explorer. The nightly sweep had
/// re-derived the identical 54,000 items every night since it was written and
/// had never looked at a 54,001st.
///
/// The reason for pinning it was real, so it is kept: a failure has to be
/// reproducible. The seed is printed with the result and can be set, so a red
/// sweep is re-run with WU_CONTRACT_SEED=<the number it printed> and generates
/// exactly the same items again.
int get _seed =>
    int.tryParse(Platform.environment['WU_CONTRACT_SEED'] ?? '') ?? 0;

/// Games whose prompt names the word on purpose, so "the prompt must not
/// contain the answer" does not apply to them.
const Map<String, String> _promptMayNameTheAnswer = {
  'word_find': 'the task is to find the named word in the grid',
  'word_snake': 'the task is to trace the named word',
  'word_builder': 'the task is to build the named word from its letters',
  'word_memory': 'the task is to find the named word\'s pair',
  'word_sort': 'the word is shown; the answer is its word class',
  'word_type_whirl': 'the word is shown; the answer is its word class',
  // The same shape, and it needed saying only once the rule below learned to
  // read inside a word: the answer is the label "Verb", and "verbieten" and
  // "verbrennen" happen to start with those letters.
  'word_class_flash': 'the word is shown; the answer is its word class',
  'syllable_count': 'the word is shown; the answer is a number of syllables',
  'grossstadt': 'the word is shown; the answer is whether to capitalise it',
  'grossschreib': 'the word is shown in a sentence; the answer is GROSS/klein',
  'verbtrenner': 'the form is shown; the answer is whether it separates',
  'conjugation_drill': 'the infinitive is shown; the answer is a form of it',
  'word_of_the_day': 'the card names the word and shows what it means',
  'sri_review': 'the article challenge shows the noun it asks the article for',
  'spelling_spotter': 'the prompt is a fixed question that names no word, so '
      'an answer like "is" only collides with ordinary English',
  'phrasal_verb_power': 'the answer is a particle, and prepositions recur: '
      '"The expression ___ her face lets on her true feelings"',
  // The same reasoning, and worth stating once for the whole family: a game
  // whose answer is a function word cannot be held to "the prompt must not
  // contain it". "I need ___ finish my homework to go outside." keys "to",
  // and which of to/too/two fits the gap is exactly what is being asked.
  'homophone_drill': 'the answer is a function word, which recurs',
  'wortfalle': 'the same: das/dass, wie/wir, wer/Wehr',
};

/// Games where the answer being written inside the prompt is the lesson, not
/// a leak, so only a whole-word collision counts.
///
/// Negation prefixes make the commonest antonyms there are — balance and
/// unbalance, national and international, appear and disappear, adequate and
/// inadequate — and a child learning that un- turns a word around is learning
/// exactly what the game is for. Reading inside the word would throw away
/// nineteen of them in a single sweep and leave the arbitrary pairs behind.
const Map<String, String> _answerMayBeWrittenInside = {
  'antonym_flash': 'un-, dis-, in- and ir- are how most antonyms are built',
};

/// Games where two options differing only in case is the question itself, so
/// options are compared exactly rather than case-insensitively.
const Map<String, String> _caseIsTheQuestion = {
  'wortfalle': 'the trap is Wagen (noun) against wagen (verb)',
  'grossstadt': 'the answer is whether the word is capitalised',
  'grossschreib': 'the answer is whether the word is capitalised',
};

class _Violation {
  _Violation(this.language, this.game, this.grade, this.rule, this.detail);
  final String language;
  final String game;
  final int grade;
  final String rule;
  final String detail;

  @override
  String toString() => '[$language $game grade $grade] $rule\n      $detail';
}

String _q(String s) => s.length > 90 ? '"${s.substring(0, 90)}…"' : '"$s"';

void _checkItem(Item item, String language, int grade, List<_Violation> out) {
  void fail(String rule, String detail) =>
      out.add(_Violation(language, item.game, grade, rule, detail));

  if (item.prompt.trim().isEmpty) {
    fail('empty prompt', 'the learner would be asked a blank question');
  }
  // A Dart interpolation that printed nothing. English only: "null" is an
  // ordinary German word, and the pack glosses "nichts" as "null, nichts,
  // Null" — no heuristic tells that from a leak, and the leak is what a
  // reader of the dump would spot anyway.
  if (language == 'en' && RegExp(r'\bnull\b').hasMatch(item.prompt)) {
    fail('"null" in the prompt', _q(item.prompt));
  }
  final answer = item.answer;
  if (answer != null && answer.trim().isEmpty) {
    fail('blank answer', 'prompt was ${_q(item.prompt)}');
  }

  if (item.options.isNotEmpty) {
    if (item.options.length < 2) {
      fail('single option', 'nothing to choose between');
    }
    if (answer == null) {
      fail('no keyed answer', 'options ${item.options} have no correct one');
    } else if (!item.options.contains(answer)) {
      fail('answer is not among the options',
          'answer ${_q(answer)}, options ${item.options}');
    }
    for (final option in item.options) {
      if (option.trim().isEmpty) {
        fail('blank option', 'options ${item.options}');
      }
    }
    final caseMatters = _caseIsTheQuestion.containsKey(item.game);
    final seen = <String>{};
    for (final option in item.options) {
      final key = caseMatters ? option.trim() : option.trim().toLowerCase();
      if (!seen.add(key)) {
        fail(
            'duplicate options',
            'the same answer twice: ${item.options} — one of them is keyed '
                'wrong whichever the learner picks');
      }
    }
  }

  if (answer != null &&
      item.options.isNotEmpty &&
      !_promptMayNameTheAnswer.containsKey(item.game) &&
      _promptShowsTheAnswer(item.prompt, answer.trim(), item.game)) {
    fail('the prompt gives the answer away',
        'answer ${_q(answer)} appears in ${_q(item.prompt)}');
  }
}

/// Whether a learner would see the answer written in the prompt.
///
/// Two readings, because a one-word prompt and a sentence are read
/// differently. In a sentence the eye goes word by word, so "und" inside
/// "Hund" gives nothing away and only a whole word counts. A one-word prompt
/// is read as a word, and German writes its compounds without a separator, so
/// "Schließfach" shows "Fach" and "hinüber" shows "hin". A prompt with a space
/// in it — "tube top", which was keyed "Top" — is a sentence for this purpose
/// and the word-level rule already catches it.
///
/// Dart's `\b` is ASCII, which is why this was ever in doubt. It treats ß and
/// ü as non-word characters, so it invented a boundary inside "Schließfach"
/// and caught that compound by accident while a plain one like "Handtuch"
/// would have slipped past. Whichever rule applies should apply on purpose.
bool _promptShowsTheAnswer(String prompt, String answer, String game) {
  if (answer.isEmpty) return false;
  final lowerPrompt = prompt.toLowerCase();
  final lowerAnswer = answer.toLowerCase();
  if (!_answerMayBeWrittenInside.containsKey(game) &&
      !prompt.trim().contains(RegExp(r'\s'))) {
    // Short answers turn up inside longer words by coincidence rather than by
    // showing through, so they are still held to the word-level rule.
    if (lowerAnswer.length >= 3) return lowerPrompt.contains(lowerAnswer);
  }
  return RegExp('\\b${RegExp.escape(answer)}\\b', caseSensitive: false)
      .hasMatch(prompt);
}

/// Violations grouped by game and rule: a broken generator produces hundreds
/// of near-identical lines, and what a reader needs is which games broke which
/// rule, with a few examples of each.
String _summarize(List<_Violation> violations) {
  final grouped = <String, List<_Violation>>{};
  for (final violation in violations) {
    grouped
        .putIfAbsent(
            '${violation.language} ${violation.game}: '
            '${violation.rule}',
            () => [])
        .add(violation);
  }
  final buffer = StringBuffer();
  final keys = grouped.keys.toList()..sort();
  for (final key in keys) {
    final group = grouped[key]!;
    final grades = group.map((v) => v.grade).toSet().toList()..sort();
    buffer.writeln('  $key — ${group.length}x, grade(s) ${grades.join(',')}');
    for (final violation in group.take(3)) {
      buffer.writeln('      ${violation.detail}');
    }
  }
  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A sharded sweep runs one pack per job; by default both are checked.
  final languages = (Platform.environment['WU_CONTRACT_LANGUAGES'] ?? 'en,de')
      .split(',')
      .map((code) => code.trim())
      .where((code) => code.isNotEmpty);

  for (final language in languages) {
    group('$language pack', () {
      late AuditPack pack;
      var opened = false;

      setUpAll(() async {
        if (language == 'de' && germanPackPath == null) return;
        pack = await openAuditPack(language);
        opened = true;
      });

      tearDownAll(() async {
        if (opened) await pack.dispose();
      });

      /// Generates every game across the grade range once, so both tests read
      /// the same items rather than generating them twice.
      Future<Map<String, List<({int grade, Item item})>>> generateAll() async {
        final byGame = <String, List<({int grade, Item item})>>{};
        final only = _games;
        for (final entry in generators.entries) {
          final supported = generatorLanguages[entry.key] ?? const ['en', 'de'];
          if (!supported.contains(language)) continue;
          if (only != null && !only.contains(entry.key)) continue;
          final items = <({int grade, Item item})>[];
          for (final grade in _grades) {
            final generated = await entry.value(pack.context(
              grade: grade,
              count: _perGrade,
              // Seeded per grade so a shard is independent, and offset by
              // WU_CONTRACT_SEED so successive runs explore new items.
              rng: Random(_seed + grade),
            ));
            items.addAll(generated.map((item) => (grade: grade, item: item)));
          }
          byGame[entry.key] = items;
        }
        return byGame;
      }

      test('the catalogue keeps its ordinary words', () async {
        if (!opened) {
          markTestSkipped('set WU_PACK_DE=/path/to/grundwortschatz.db');
          return;
        }
        // A quality rule that reads the packs' own tags can be read
        // backwards: `often_misspelled` marks the *pair*, so filtering on it
        // took "add", "all" and "and" out of the English catalogue, and
        // nothing failed — every game still produced well-formed items from
        // what was left.
        final words = pack.vocabulary
            .getAllWords(pack.settings)
            .map((word) => word.word.toLowerCase())
            .toSet();
        final common = language == 'en'
            ? ['add', 'all', 'and', 'also', 'area', 'water', 'school']
            : ['und', 'haus', 'schule', 'wasser', 'gehen', 'gut'];
        for (final word in common) {
          expect(words, contains(word), reason: 'the catalogue lost "$word"');
        }
        expect(words.length, greaterThan(9000),
            reason: 'the catalogue shrank far below what the pack ships');
      }, timeout: const Timeout(Duration(minutes: 10)));

      test('every item is well formed', () async {
        if (!opened) {
          markTestSkipped('set WU_PACK_DE=/path/to/grundwortschatz.db');
          return;
        }
        final byGame = await generateAll();
        final violations = <_Violation>[];
        var checked = 0;
        for (final entry in byGame.entries) {
          for (final generated in entry.value) {
            checked++;
            _checkItem(generated.item, language, generated.grade, violations);
          }
        }
        // ignore: avoid_print
        print('$language: $checked items checked across '
            '${byGame.length} games, grade(s) ${_grades.join(',')}, '
            '$_perGrade per game per grade, WU_CONTRACT_SEED=$_seed');
        // How much of each game was actually seen. Asked for more than the
        // game can produce, distinct stops short of the request and that
        // number is the whole of it — which is the difference between "500
        // checked" and "all of them checked".
        for (final game in byGame.keys.toList()..sort()) {
          final items = byGame[game]!;
          final distinct = items
              .map((e) => '${e.item.prompt}\u0000${e.item.answer}')
              .toSet()
              .length;
          final asked = _perGrade * _grades.length;
          // ignore: avoid_print
          print('  $language $game: $distinct distinct of ${items.length} '
              'generated, $asked asked for'
              '${items.length < asked ? " — exhausted" : ""}');
        }
        expect(checked, greaterThan(100),
            reason: 'the sweep itself produced almost nothing to check');
        expect(
          violations,
          isEmpty,
          reason: '$checked items checked, ${violations.length} bad.\n'
              '${_summarize(violations)}',
        );
      }, timeout: const Timeout(Duration(minutes: 15)));

      test('every game can fill a round', () async {
        if (!opened) {
          markTestSkipped('set WU_PACK_DE=/path/to/grundwortschatz.db');
          return;
        }
        final byGame = await generateAll();
        // A game that generates nothing is offered in the menu and then opens
        // empty. Translation Flash did exactly that for weeks: the feature bit
        // it filtered on read a JSON key neither pack uses.
        final empty = byGame.entries
            .where((e) => e.value.isEmpty)
            .map((e) => e.key)
            .toList();
        expect(empty, isEmpty,
            reason: 'these games produced no item at any grade 1-6');

        // A game that can only ever fill one grade is a narrower failure of
        // the same kind, and is worth seeing even when it is intended. Only
        // meaningful when the run covers more than one grade: a sharded
        // sweep asks for one at a time.
        if (_grades.length < 2) return;
        final thin = <String>[];
        for (final entry in byGame.entries) {
          final grades =
              entry.value.map((generated) => generated.grade).toSet().length;
          if (grades < 2) thin.add('${entry.key} (only $grades grade)');
        }
        expect(thin, isEmpty,
            reason: 'these games reach only one grade band of the six');
      }, timeout: const Timeout(Duration(minutes: 15)));
    });
  }
}
