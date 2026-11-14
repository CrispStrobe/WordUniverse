import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/features/kompass/models/kompass_models.dart';
import 'package:WortUniversum/features/kompass/models/kompass_touch.dart';
import 'package:WortUniversum/features/kompass/screens/kompass_player_screen.dart';
import 'package:WortUniversum/features/kompass/services/kompass_course_service.dart';
import 'package:WortUniversum/features/kompass/services/kompass_grader.dart';
import 'package:WortUniversum/features/kompass/services/kompass_progress_service.dart';
import 'package:WortUniversum/features/kompass/widgets/kompass_touch_input.dart';

final _source = File('assets/kompass/bw_de_v1.json').readAsStringSync();
final _course = KompassCourse.decode(_source);

/// Whether [answers] earn every point of [parts] (a mismatch that would go
/// to review does not count).
bool _full(KompassTask task, List<String> parts, Map<String, String> answers) {
  final results = KompassGrader.assess(task, answers);
  return parts.every((id) {
    final r = results.firstWhere((p) => p.partId == id);
    return r.points == r.maxPoints;
  });
}

Iterable<List<int>> _subsets(int n, int maxSize) sync* {
  for (var mask = 1; mask < 1 << n; mask++) {
    final picked = [
      for (var i = 0; i < n; i++)
        if (mask & (1 << i) != 0) i
    ];
    if (picked.length <= maxSize) yield picked;
  }
}

Iterable<List<int>> _permutations(List<int> items) sync* {
  if (items.length <= 1) {
    yield items;
    return;
  }
  for (var i = 0; i < items.length; i++) {
    final rest = List<int>.from(items)..removeAt(i);
    for (final p in _permutations(rest)) {
      yield [items[i], ...p];
    }
  }
}

/// The taps a child who knows the answer makes, found by trying them.
Map<String, dynamic>? _solve(KompassTask task, KompassTouch touch) {
  final parts = {for (final p in task.parts) p.id: p};
  bool ok(Map<String, dynamic> state) =>
      _full(task, touch.partIds, touch.values(state));
  switch (touch.kind) {
    case 'choice':
      final right = [
        for (var i = 0; i < touch.options.length; i++)
          if (ok({'i': i})) i
      ];
      expect(right, hasLength(1),
          reason: '${task.id}: exactly one option is right');
      return {'i': right.single};
    case 'rank':
      final order = List<int>.filled(touch.partIds.length, 0);
      for (var row = 0; row < touch.partIds.length; row++) {
        order[int.parse(parts[touch.partIds[row]]!.answers.first) - 1] = row;
      }
      return {'order': order};
    case 'select':
      for (final sel in _subsets(touch.words.length, 6)) {
        if (ok({'sel': sel})) return {'sel': sel};
      }
      return null;
    case 'span':
      for (var a = 0; a < touch.word.length; a++) {
        for (var b = a; b < touch.word.length; b++) {
          if (ok({'a': a, 'b': b})) return {'a': a, 'b': b};
        }
      }
      return null;
    case 'fix':
      final chosen = <String, dynamic>{};
      var cursor = 0;
      for (final id in touch.partIds) {
        final answers = parts[id]!.answers;
        for (var i = cursor; i < touch.words.length; i++) {
          final hit = touch.spellings[i].where(answers.contains);
          if (hit.isNotEmpty) {
            chosen['$i'] = hit.first;
            cursor = i + 1;
            break;
          }
        }
      }
      return ok({'ch': chosen}) ? {'ch': chosen} : null;
    case 'split':
      for (final cuts in _subsets(touch.words.length - 1, 6)) {
        if (ok({'cuts': cuts})) return {'cuts': cuts};
      }
      return null;
    case 'letters':
      final answer = parts[touch.partIds.first]!.answers.first;
      final words = answer.replaceAll(touch.end, '').split(' ');
      final cuts = <int>[], caps = <int>[];
      var at = 0;
      for (final w in words) {
        if (w[0] != w[0].toLowerCase()) caps.add(at);
        at += w.length;
        cuts.add(at - 1);
      }
      cuts.removeLast();
      final state = {'cuts': cuts, 'caps': caps};
      return ok(state) ? state : null;
    case 'punctuate':
      final answer = parts[touch.partIds.first]!.answers.first;
      final gaps = <String>[];
      var cursor = 0;
      for (var i = 0; i < touch.words.length; i++) {
        final at = answer.indexOf(touch.words[i], cursor);
        if (i > 0) gaps.add(answer.substring(cursor, at).replaceAll(' ', ''));
        cursor = at + touch.words[i].length;
      }
      gaps.add(answer.substring(cursor).replaceAll(' ', ''));
      final state = {'gaps': gaps};
      return ok(state) ? state : null;
    case 'arrange':
      for (final seq
          in _permutations(List.generate(touch.tiles.length, (i) => i))) {
        if (ok({'seq': seq})) return {'seq': seq};
      }
      return null;
  }
  return null;
}

class _Bundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async => _source;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(_source)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every typed answer of the course can be tapped instead', () {
    for (final task in _course.tasks) {
      final covered = {for (final w in task.touch) ...w.partIds};
      for (final part in task.parts.where((p) => p.type == 'text')) {
        expect(covered, contains(part.id), reason: '${task.id}/${part.id}');
      }
    }
  });

  test('the right taps earn every point, on every touch widget', () {
    var widgets = 0;
    for (final task in _course.tasks) {
      for (final touch in task.touch.where((w) => w.kind != 'quote')) {
        final state = _solve(task, touch);
        expect(state, isNotNull, reason: '${task.id} ${touch.kind}');
        widgets++;
      }
    }
    expect(widgets, greaterThan(100));
  });

  test('nothing tapped is no answer, and a wrong tap is a wrong answer', () {
    final task = _course.taskById('d1_13')!;
    final touch = task.touch.first;
    expect(touch.values({}), {'a': ''});
    expect(touch.values({'i': 0}), {'a': 'heiss'});
    expect(_full(task, ['a'], touch.values({'i': 0})), isFalse);
    expect(touch.values({'i': 1}), {'a': 'heiß'});
  });

  test('marks join their words the way they are written', () {
    expect(
        assemblePunctuation(['Paul', 'sagt', 'Der', 'Bus', 'kommt', 'gleich'],
            ['', ':„', '', '', '', '.“']),
        'Paul sagt: „Der Bus kommt gleich.“');
    expect(assemblePunctuation(['Nora', 'fragt', 'Wo'], ['', ':', '?']),
        'Nora fragt: Wo?');
  });

  group('tapping in the widget', () {
    Future<Map<String, String>> drive(WidgetTester tester, String taskId,
        int index, Future<void> Function() taps) async {
      final task = _course.taskById(taskId)!;
      final touch = task.touch[index];
      var state = <String, dynamic>{};
      var values = <String, String>{};
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        locale: const Locale('de'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => KompassTouchInput(
                touch: touch,
                state: state,
                onChanged: (s, v) => setState(() {
                  state = s;
                  values = v;
                }),
              ),
            ),
          ),
        ),
      ));
      await taps();
      expect(tester.takeException(), isNull);
      return values;
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }

    testWidgets('a gap in a word takes the letters a child picks',
        (tester) async {
      final values =
          await drive(tester, 'd1_13', 0, () => tap(tester, 'touch-a-1'));
      expect(values, {'a': 'heiß'});
    });

    testWidgets('quotes and a colon go where they are tapped', (tester) async {
      final values = await drive(tester, 'd1_15', 0, () async {
        await tap(tester, 'touch-gap-1');
        await tap(tester, 'touch-mark-:');
        await tap(tester, 'touch-mark-„');
        await tap(tester, 'touch-gap-5');
        await tap(tester, 'touch-mark-.');
        await tap(tester, 'touch-mark-“');
      });
      expect(values.values.toSet(), {'Paul sagt: „Der Bus kommt gleich.“'});
    });

    testWidgets('a misspelt word is tapped and corrected', (tester) async {
      final values = await drive(tester, 'd1_14', 0, () async {
        await tap(tester, 'touch-fix-1');
        await tap(tester, 'touch-spelling-1-Mittwoch');
        await tap(tester, 'touch-fix-13');
        await tap(tester, 'touch-spelling-13-Tisch');
      });
      expect(values,
          {'word1': 'Mittwoch', 'word2': 'Tisch', 'word3': '', 'word4': ''});
    });

    testWidgets('bars between the words make the Satzglieder', (tester) async {
      final values = await drive(tester, 'd1_24', 0, () async {
        for (final gap in [2, 3, 4]) {
          await tap(tester, 'touch-cut-$gap');
        }
      });
      expect(values, {
        'group1': 'Vor dem Haus',
        'group2': 'fegt',
        'group3': 'Leni',
        'group4': 'die Treppe'
      });
    });

    testWidgets('letters are cut into words and a word gets its capital',
        (tester) async {
      // DER|VOGEL|BAUT|SEIN|NEST|IM|BAUM
      final values = await drive(tester, 'd2_16', 0, () async {
        for (final gap in [2, 7, 11, 15, 19, 21]) {
          await tap(tester, 'touch-cut-$gap');
        }
        for (final start in [0, 3, 16, 22]) {
          await tap(tester, 'touch-case-$start');
        }
      });
      expect(values.values.toSet(), {'Der Vogel baut sein Nest im Baum.'});
    });

    testWidgets('the stem is the letters between two taps', (tester) async {
      final values = await drive(tester, 'd1_19', 2, () async {
        await tap(tester, 'touch-letter-stem3-0');
        await tap(tester, 'touch-letter-stem3-2');
      });
      expect(values, {'stem3': 'Bau'});
    });

    testWidgets('sentences are numbered in the order they are tapped',
        (tester) async {
      final values = await drive(tester, 'd1_06', 0, () async {
        for (final row in [2, 3, 0, 1]) {
          await tap(tester, 'touch-rank-$row');
        }
      });
      expect(values, {
        'position1': '3',
        'position2': '4',
        'position3': '1',
        'position4': '2'
      });
    });

    testWidgets('every touch widget of the course fits a phone',
        (tester) async {
      for (final task in _course.tasks) {
        for (var i = 0; i < task.touch.length; i++) {
          if (task.touch[i].kind == 'quote') continue;
          await drive(tester, task.id, i, () async {});
        }
      }
    });
  });

  testWidgets('the player answers by tapping, records it, and can type instead',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final courses = KompassCourseService(assets: _Bundle());
    await courses.load();
    final progress = KompassProgressService(prefs);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: courses),
        ChangeNotifierProvider.value(value: progress),
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const KompassPlayerScreen(taskIds: ['d1_13', 'd1_10']),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.byKey(const ValueKey('touch-a-1')));
    await tester.tap(find.byKey(const ValueKey('touch-b-0')));
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const ValueKey('kompass-player-primary')));
    await tester.tap(find.byKey(const ValueKey('kompass-player-primary')));
    await tester.pumpAndSettle();
    final attempt = progress.attempts.single;
    expect(attempt.earnedPoints, 2);
    expect(attempt.inputMode, 'touch');
    expect(KompassAttempt.fromJson(attempt.toJson()).inputMode, 'touch');

    // Switching to typing keeps what was tapped, in an ordinary field.
    await tester.tap(find.byKey(const ValueKey('kompass-player-primary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('touch-a-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('kompass-input-mode')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Berg'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
