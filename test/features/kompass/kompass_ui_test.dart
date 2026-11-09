import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/features/kompass/models/kompass_models.dart';
import 'package:WortUniversum/core/services/learner_profile_service.dart';
import 'package:WortUniversum/features/kompass/widgets/kompass_blocks.dart';
import 'package:WortUniversum/features/kompass/services/kompass_course_service.dart';
import 'package:WortUniversum/features/kompass/services/kompass_progress_service.dart';
import 'package:WortUniversum/features/kompass/services/kompass_planner.dart';
import 'package:WortUniversum/features/kompass/screens/kompass_dashboard_screen.dart';
import 'package:WortUniversum/features/kompass/screens/kompass_player_screen.dart';
import 'package:WortUniversum/features/kompass/widgets/kompass_part_input.dart';
import 'package:WortUniversum/features/kompass/widgets/kompass_review_sheet.dart';
import 'package:WortUniversum/features/kompass/widgets/kompass_strings.dart';
import 'package:WortUniversum/features/kompass/widgets/kompass_ui.dart';

class _Bundle extends CachingAssetBundle {
  final String json;
  _Bundle(this.json);
  @override
  Future<String> loadString(String key, {bool cache = true}) async => json;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(json)));
}

Map<String, dynamic> _task(String id, {bool grouped = false}) => {
      'id': id,
      'title': 'Wörter erforschen',
      'domain': 'spelling',
      'points': grouped ? 1.5 : 1,
      'competencyIds': ['D-R01'],
      'version': 1,
      'hints': ['Prüfe die Wortfamilie.'],
      'blocks': [
        {
          'type': 'paragraph',
          'style': 'instruction',
          'text': 'Schreibe deine Antwort.'
        }
      ],
      'parts': grouped
          ? [
              {
                'id': 'a',
                'type': 'review',
                'prompt': 'Satzanfang',
                'maxPoints': 1,
                'reviewRequired': true,
                'rubric': ['1 Punkt für den richtigen Satzanfang.'],
                'responseGroupId': 'sentence',
                'responseGroupPrompt': 'Schreibe den ganzen Satz.'
              },
              {
                'id': 'b',
                'type': 'review',
                'prompt': 'Satzende',
                'maxPoints': .5,
                'reviewRequired': true,
                'creditSteps': [0, .5],
                'rubric': ['Ein halber Punkt für das Satzende.'],
                'responseGroupId': 'sentence'
              },
            ]
          : [
              {
                'id': 'a',
                'type': 'text',
                'prompt': 'Nenne das verwandte Wort.',
                'answers': ['kalt'],
                'maxPoints': 1,
                'caseSensitive': true
              },
            ],
    };

String _fixture({bool grouped = false, int count = 1}) => jsonEncode({
      'schemaVersion': 1,
      'id': 'test-course',
      'version': 1,
      'locale': 'de-DE',
      'competencies': [
        {
          'id': 'D-R01',
          'domain': 'spelling',
          'title': 'Wortfamilien',
          'goal': 'Ich prüfe Wörter.'
        }
      ],
      'stimuli': [],
      'tasks': [
        for (var i = 0; i < count; i++) _task('task$i', grouped: grouped)
      ],
      'tests': [],
    });

Future<(KompassCourseService, KompassProgressService)> _services(
    String content) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final courses = KompassCourseService(assets: _Bundle(content));
  await courses.load();
  return (courses, KompassProgressService(prefs));
}

Widget _app(Widget home, KompassCourseService courses,
        KompassProgressService progress,
        {Locale locale = const Locale('de'), double scale = 1}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: courses),
        ChangeNotifierProvider.value(value: progress)
      ],
      child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('de'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: home),
    );

Future<void> _show(WidgetTester tester, Widget widget,
    {Size size = const Size(1000, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'actual course dashboard fits portrait and landscape with enlarged text',
      (tester) async {
    final (courses, progress) = await _services(
        File('assets/kompass/bw_de_v1.json').readAsStringSync());
    expect(courses.course!.tasks.length, greaterThanOrEqualTo(113));
    for (final size in [const Size(390, 844), const Size(900, 450)]) {
      await _show(tester,
          _app(const KompassDashboardScreen(), courses, progress, scale: 1.3),
          size: size);
      expect(find.text('Kompass 4 · Deutsch'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
      'independent answers resume locally and no solution is shown before finishing',
      (tester) async {
    final (courses, progress) = await _services(_fixture());
    await _show(
        tester,
        _app(const KompassPlayerScreen(taskIds: ['task0'], mode: 'independent'),
            courses, progress));
    expect(find.text('Tipp 1'), findsNothing);
    expect(find.textContaining('Lösung:'), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'kalt');
    await tester.pump(const Duration(milliseconds: 400));
    final saved = progress.activeSession!;
    expect((saved['answers'] as Map)['task0'], {'a': 'kalt'});
    expect(progress.attempts, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _show(
        tester, _app(KompassPlayerScreen.resume(saved), courses, progress));
    expect(find.text('kalt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kompass-player-primary')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, 'Runde abschließen').last);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('kompass-session-summary')), findsOneWidget);
    expect(progress.attempts.single.earnedPoints, 1);
    expect(progress.attempts.single.independent, isTrue);
    expect(progress.activeSession, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
      'shared free response is entered once, copied to criteria, and remains pending',
      (tester) async {
    final (courses, progress) = await _services(_fixture(grouped: true));
    await _show(tester,
        _app(const KompassPlayerScreen(taskIds: ['task0']), courses, progress));
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Schreibe den ganzen Satz.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Der Hund schläft.');
    await tester.tap(find.byKey(const ValueKey('kompass-player-primary')));
    await tester.pumpAndSettle();
    final attempt = progress.attempts.single;
    expect(attempt.pendingPoints, 1.5);
    expect(attempt.parts.map((p) => p.response),
        everyElement('Der Hund schläft.'));
    expect(attempt.parts.every((p) => p.needsReview), isTrue);
    expect(kompassScoreLabel(const KompassStrings(true), 0, 1.5, pending: 1.5),
        'Rückmeldung offen: 1.5 Punkte');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
      'rubric review preserves half points and requires explicit criteria choices',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final (courses, progress) = await _services(_fixture(grouped: true));
    final course = courses.course!;
    final task = course.tasks.single;
    final attempt = await progress.recordAttempt(
        course: course,
        task: task,
        answers: {'a': 'Der Hund schläft.', 'b': 'Der Hund schläft.'},
        mode: 'practice');
    await _show(
        tester,
        _app(Scaffold(body: KompassReviewSheet(task: task, attempt: attempt)),
            courses, progress));
    expect(find.bySemanticsLabel(RegExp(RegExp.escape('Der Hund schläft.'))),
        findsWidgets);
    final save = find.byKey(const ValueKey('kompass-review-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '1 / 1 Punkte'));
    await tester.tap(find.widgetWithText(ChoiceChip, '1 / 1 Punkte'));
    await tester.pump();
    await tester
        .ensureVisible(find.widgetWithText(ChoiceChip, '0.5 / 0.5 Punkte'));
    await tester.tap(find.widgetWithText(ChoiceChip, '0.5 / 0.5 Punkte'));
    await tester.pump();
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(progress.attempts.single.earnedPoints, 1.5);
    expect(progress.attempts.single.pendingPoints, 0);
    expect(progress.attempts.single.reviewer, 'self');
    expect(tester.takeException(), isNull);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    semantics.dispose();
  });

  testWidgets('hint is recorded before answer scoring', (tester) async {
    final semantics = tester.ensureSemantics();
    final (courses, progress) = await _services(_fixture());
    await _show(tester,
        _app(const KompassPlayerScreen(taskIds: ['task0']), courses, progress));
    await tester.ensureVisible(find.text('Tipp 1'));
    await tester.tap(find.text('Tipp 1'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'kalt');
    await tester.tap(find.byKey(const ValueKey('kompass-player-primary')));
    await tester.pumpAndSettle();
    expect(progress.attempts.single.assistance, contains('hint'));
    expect(progress.attempts.single.independent, isFalse);
    expect(find.bySemanticsLabel(RegExp('Lösung: kalt')), findsWidgets);
    expect(progress.attempts.single.earnedPoints, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    semantics.dispose();
  });

  testWidgets('leaving a viewed draft keeps later checks fresh', (
    tester,
  ) async {
    final (courses, progress) = await _services(_fixture(count: 2));
    await _show(
      tester,
      _app(
        const KompassPlayerScreen(taskIds: ['task0', 'task1']),
        courses,
        progress,
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, 'ka');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final course = courses.course!;
    expect(progress.attempts, isEmpty);
    expect(
      KompassPlanner.isFresh(course, progress, course.taskById('task0')!),
      isFalse,
    );
    expect(
      KompassPlanner.isFresh(course, progress, course.taskById('task1')!),
      isTrue,
    );
    await progress.saveSession(null, course: course);
    final restored = KompassProgressService(
      await SharedPreferences.getInstance(),
    );
    expect(
      KompassPlanner.isFresh(course, restored, course.taskById('task0')!),
      isFalse,
    );
    expect(KompassPlanner.startCheck(course, restored).tasks.map((t) => t.id), [
      'task1',
    ]);
    expect(restored.statsFor('D-R01').state, 'unobserved');
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('unanswered skipped tasks do not produce a zero-score attempt',
      (tester) async {
    final (courses, progress) = await _services(_fixture(count: 2));
    await _show(
        tester,
        _app(
            const KompassPlayerScreen(
                taskIds: ['task0', 'task1'], mode: 'startCheck'),
            courses,
            progress));
    await tester.ensureVisible(find.text('Überspringen'));
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    expect(find.text('Aufgabe 2 von 2'), findsOneWidget);
    expect(progress.attempts, isEmpty);
    await tester.tap(find.byKey(const ValueKey('kompass-player-primary')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, 'Runde abschließen').last);
    await tester.pumpAndSettle();
    expect(progress.attempts, isEmpty);
    expect(
        find.textContaining('2 Aufgaben bleiben unbeobachtet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
      'order controls require an explicit response and preserve stable option IDs',
      (tester) async {
    final part = KompassPart.fromJson({
      'id': 'order',
      'type': 'order',
      'maxPoints': 1,
      'answers': ['b', 'a'],
      'options': [
        {'id': 'a', 'text': 'Zweiter Schritt'},
        {'id': 'b', 'text': 'Erster Schritt'}
      ]
    });
    dynamic response;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, update) => KompassPartInput(
                    part: part,
                    value: response,
                    onChanged: (value) => update(() => response = value))))));
    expect(response, isNull);
    await tester.tap(find.byTooltip('Move down').first);
    await tester.pump();
    expect(response, ['b', 'a']);
    expect(tester.takeException(), isNull);
  });

  test(
      'authored inline emphasis preserves the marked target without exposing tags',
      () {
    final span = KompassRichText.span(
        'Er <b>trägt</b> eine Kiste.<br>Ein <i>Test</i>.', null);
    expect(span.toPlainText(), 'Er trägt eine Kiste.\nEin Test.');
    final target = span.children!
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == 'trägt');
    expect(target.style!.fontWeight, FontWeight.bold);
  });

  testWidgets(
      'read-only passage, instructions and table expose text labels before focus',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final (courses, progress) = await _services(_fixture());
    final stimulus = KompassStimulus.fromJson({
      'id': 'reading',
      'title': 'Ein Spielewagen',
      'lines': [
        {
          'id': 'reading:L25',
          'label': '25',
          'text': 'Am Montag wird der Wagen ausprobiert.',
        },
      ],
    });
    await _show(
        tester,
        _app(
            Scaffold(
                body: SingleChildScrollView(
                    child: Column(children: [
              KompassPassage(stimulus: stimulus),
              const KompassRichText('Prüfe das <b>Wort</b>.'),
              const KompassBlocks(blocks: [
                {
                  'type': 'table',
                  'headers': ['Ort', 'Zeit'],
                  'rows': [
                    ['Schulhof', '10 Uhr']
                  ],
                },
              ]),
            ]))),
            courses,
            progress));
    // Screen readers receive labels immediately; none of this content depends
    // on focusing a read-only editable field to initialize its value.
    for (final text in [
      'Zeile 25',
      'Am Montag wird der Wagen ausprobiert.',
      'Prüfe das Wort.',
      'Schulhof',
      '10 Uhr',
    ]) {
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(text))), findsWidgets,
          reason: text);
    }
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    semantics.dispose();
  });

  testWidgets(
      'dashboard uses and persists the learner duration including five minutes',
      (tester) async {
    final (courses, progress) = await _services(_fixture());
    final prefs = await SharedPreferences.getInstance();
    final profile = LearnerProfileService(prefs);
    await profile.setSessionMinutes(5);
    await _show(
        tester,
        ChangeNotifierProvider.value(
            value: profile,
            child: _app(const KompassDashboardScreen(), courses, progress)));
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '5 Minuten'))
            .selected,
        isTrue);
    await tester.tap(find.widgetWithText(ChoiceChip, '15 Minuten'));
    await tester.pumpAndSettle();
    expect(profile.sessionMinutes, 15);
    expect(LearnerProfileService(prefs).sessionMinutes, 15);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
      'resuming an expired timed draft saves its answers once and completes',
      (tester) async {
    final (courses, progress) = await _services(_fixture());
    final draft = <String, dynamic>{
      'courseId': 'test-course',
      'courseVersion': 1,
      'taskIds': ['task0'],
      'mode': 'independent',
      'title': 'Zeitversuch',
      'timeLimitSeconds': 60,
      'deadline':
          DateTime.now().subtract(const Duration(seconds: 2)).toIso8601String(),
      'answers': {
        'task0': {'a': 'kalt'}
      },
    };
    await _show(
        tester, _app(KompassPlayerScreen.resume(draft), courses, progress));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(progress.attempts.length, 1);
    expect(progress.attempts.single.earnedPoints, 1);
    expect(progress.activeSession, isNull);
    expect(find.text('Die Zeit ist um.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
