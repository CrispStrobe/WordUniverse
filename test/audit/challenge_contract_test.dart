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

/// Games whose prompt names the word on purpose, so "the prompt must not
/// contain the answer" does not apply to them.
const Map<String, String> _promptMayNameTheAnswer = {
  'word_find': 'the task is to find the named word in the grid',
  'word_snake': 'the task is to trace the named word',
  'word_builder': 'the task is to build the named word from its letters',
  'word_memory': 'the task is to find the named word\'s pair',
  'word_sort': 'the word is shown; the answer is its word class',
  'word_type_whirl': 'the word is shown; the answer is its word class',
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
      RegExp('\\b${RegExp.escape(answer.trim())}\\b', caseSensitive: false)
          .hasMatch(item.prompt)) {
    fail('the prompt gives the answer away',
        'answer ${_q(answer)} appears in ${_q(item.prompt)}');
  }
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
        for (final entry in generators.entries) {
          final supported = generatorLanguages[entry.key] ?? const ['en', 'de'];
          if (!supported.contains(language)) continue;
          final items = <({int grade, Item item})>[];
          for (final grade in _grades) {
            final generated = await entry.value(pack.context(
              grade: grade,
              count: _perGrade,
              // A fixed seed per grade: a failure here has to be reproducible
              // from the dump with the same WU_DUMP_SEED.
              rng: Random(grade),
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
            '$_perGrade per game per grade');
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
