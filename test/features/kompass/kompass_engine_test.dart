import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/features/kompass/models/kompass_models.dart';
import 'package:WortUniversum/features/kompass/services/kompass_grader.dart';
import 'package:WortUniversum/features/kompass/services/kompass_planner.dart';
import 'package:WortUniversum/features/kompass/services/kompass_progress_service.dart';

Map<String, dynamic> part(String id,
        {String skill = 's',
        String type = 'text',
        List<String> answers = const ['Häuser'],
        bool review = false,
        bool mismatch = false,
        double points = 1}) =>
    {
      'id': id,
      'type': type,
      'prompt': id,
      'answers': answers,
      'maxPoints': points,
      'caseSensitive': true,
      'reviewRequired': review,
      'reviewOnMismatch': mismatch,
      'competencyIds': [skill],
      if (review) 'creditSteps': [0, 0.5, 1],
      if (review) 'rubric': ['0, 0.5 oder 1 Punkt nach Kriterium.']
    };

KompassCourse fixture({bool sameSkill = false}) => KompassCourse.fromJson({
      'schemaVersion': 1,
      'id': 'fixture',
      'version': 1,
      'locale': 'de-DE',
      'competencies': [
        {
          'id': 's',
          'domain': 'spelling',
          'title': 'Schreiben',
          'goal': 'Schreiben'
        },
        {
          'id': 'r',
          'domain': 'reading',
          'title': 'Begründen',
          'goal': 'Begründen'
        }
      ],
      'tasks': [
        for (var i = 0; i < 5; i++)
          {
            'id': 't$i',
            'title': 'Task $i',
            'domain': 'spelling',
            'competencyIds': ['s'],
            'points': 1,
            'estimatedSeconds': 60,
            'parts': [part('a')]
          },
        {
          'id': 'mixed',
          'title': 'Mixed',
          'domain': 'spelling',
          'competencyIds': ['s', if (!sameSkill) 'r'],
          'points': 2,
          'parts': [
            part('a'),
            part('b', skill: sameSkill ? 's' : 'r', review: true)
          ]
        },
        {
          'id': 'operator',
          'title': 'Operator',
          'domain': 'instructions',
          'kind': 'instruction',
          'competencyIds': ['s'],
          'points': 1,
          'parts': [part('a')]
        },
      ]
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KompassCourse real;
  setUpAll(() {
    real = KompassCourse.decode(
        File('assets/kompass/bw_de_v1.json').readAsStringSync());
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'all original forms, source points, competencies and PDF bytes survive export',
      () {
    expect(real.tasks, hasLength(113));
    expect(real.competencies, hasLength(27));
    expect(real.stimuli, hasLength(6));
    expect(real.tests, hasLength(4));
    expect(real.tasks.where((t) => t.kind == 'transfer'), hasLength(9));
    expect(real.tasks.where((t) => t.kind == 'instruction'), hasLength(8));
    for (final test in real.tests) {
      expect(test.taskIds, hasLength(24));
      expect(test.totalSeconds, 2700);
      expect(
          test.taskIds
              .map(real.taskById)
              .fold<double>(0, (sum, t) => sum + t!.points),
          48);
      final raw = (real.metadata['tests'] as List)
          .cast<Map>()
          .firstWhere((t) => t['id'] == test.id);
      for (final pair in [
        (test.printAsset, 'printSha256'),
        (test.solutionsAsset, 'solutionsSha256')
      ]) {
        final bytes = File(pair.$1).readAsBytesSync();
        expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        expect(sha256.convert(bytes).toString(), raw[pair.$2]);
      }
    }
    for (final task in real.tasks) {
      expect(task.reviewStatus, isNot('teacher-reviewed'));
      for (final p in task.parts) {
        expect(p.competencyIds.every(task.competencyIds.contains), isTrue);
        if (p.reviewRequired || p.reviewOnMismatch)
          expect(p.rubric, isNotEmpty);
      }
    }
  });

  test('orthography retains case, umlauts and sharp s, but normalizes Unicode',
      () {
    final p = KompassPart.fromJson(part('a'));
    expect(KompassGrader.assessPart(p, 'Ha\u0308user').points, 1);
    expect(KompassGrader.assessPart(p, ' Häuser  ').points, 1);
    expect(KompassGrader.assessPart(p, 'häuser').points, 0);
    expect(KompassGrader.assessPart(p, 'Hauser').points, 0);
    final sharp = KompassPart.fromJson(part('b', answers: ['Straße']));
    expect(KompassGrader.assessPart(sharp, 'Strasse').points, 0);
  });

  test(
      'semantic variants remain pending, exact forms score and blanks do not earn credit',
      () {
    final p =
        KompassPart.fromJson(part('a', answers: ['Montag'], mismatch: true));
    expect(KompassGrader.assessPart(p, 'Montag').points, 1);
    expect(KompassGrader.assessPart(p, 'am ersten Montag').needsReview, isTrue);
    expect(KompassGrader.assessPart(p, '').points, 0);
    expect(
        KompassGrader.assessPart(
                KompassPart.fromJson(part('b', review: true)), '')
            .needsReview,
        isTrue);
  });

  test(
      'choice, sequence, multi-answer and source anchors follow exact policies',
      () {
    final multi = KompassPart.fromJson(
        part('m', type: 'multiChoice', answers: ['a', 'c'], points: 0.5));
    expect(KompassGrader.assessPart(multi, ['c', 'a']).points, 0.5);
    expect(KompassGrader.assessPart(multi, ['c', 'a', 'b']).points, 0);
    expect(KompassGrader.assessPart(multi, ['c', 'a', 'a']).points, 0);
    final order =
        KompassPart.fromJson(part('o', type: 'order', answers: ['a', 'c']));
    expect(KompassGrader.assessPart(order, ['a', 'c']).points, 1);
    expect(KompassGrader.assessPart(order, ['c', 'a']).points, 0);
    final evidence = KompassPart.fromJson({
      ...part('e', type: 'evidence', answers: []),
      'evidenceIds': ['line-7']
    });
    expect(KompassGrader.assessPart(evidence, 'line-7').points, 1);
    expect(KompassGrader.assessPart(evidence, '7').points, 0);
    final choice =
        KompassPart.fromJson(part('c', type: 'singleChoice', answers: ['a']));
    expect(KompassGrader.assessPart(choice, ['a', 'b']).points, 0);
  });

  test('rubric half-points persist without overwriting another skill evidence',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final progress = KompassProgressService(prefs);
    final course = fixture();
    final a = await progress.recordAttempt(
        course: course,
        task: course.taskById('mixed')!,
        answers: {'a': 'Häuser', 'b': 'Meine Begründung'},
        mode: 'independent');
    expect(a.earnedPoints, 1);
    expect(a.pendingPoints, 1);
    expect(progress.statsFor('s').successRate, 1);
    expect(progress.statsFor('r').successRate, isNull);
    await expectLater(
        progress.reviewAttempt(a.id, {'b': 0.7}), throwsArgumentError);
    await expectLater(
        progress.reviewAttempt(a.id, {'a': 0}), throwsArgumentError);
    await progress.reviewAttempt(a.id, {'b': 0.5}, reviewer: 'parent');
    final restored = KompassProgressService(prefs);
    expect(restored.attempts.single.earnedPoints, 1.5);
    expect(restored.attempts.single.parts.last.response, 'Meine Begründung');
    expect(restored.attempts.single.parts.last.evaluation, 'rubric:parent');
    expect(restored.statsFor('s').independentCount, 1);
    expect(restored.statsFor('r').independentCount, 0);
  });

  test('a partial answer cannot produce a full independent skill score',
      () async {
    final progress =
        KompassProgressService(await SharedPreferences.getInstance());
    final course = fixture(sameSkill: true);
    final a = await progress.recordAttempt(
        course: course,
        task: course.taskById('mixed')!,
        answers: {'a': 'Häuser', 'b': 'offene Antwort'},
        mode: 'independent');
    expect(progress.statsFor('s').successRate, isNull);
    expect(progress.statsFor('s').pendingCount, 1);
    await progress.reviewAttempt(a.id, {'b': 0}, reviewer: 'teacher');
    expect(progress.statsFor('s').successRate, isNull);
    expect(progress.statsFor('s').state, isNot('secure'));
    expect(progress.attempts.single.parts.first.evaluation, 'automatic');
  });

  test(
      'hints, practice, retries and instructions do not inflate independent mastery',
      () async {
    final progress =
        KompassProgressService(await SharedPreferences.getInstance());
    final course = fixture();
    Future<KompassAttempt> answer(String id, String mode,
            {Set<String> assistance = const {}}) =>
        progress.recordAttempt(
            course: course,
            task: course.taskById(id)!,
            answers: {'a': 'Häuser'},
            mode: mode,
            assistance: assistance);
    await answer('operator', 'independent');
    expect(progress.statsFor('s').attempts, 0);
    await answer('t0', 'practice');
    await answer('t1', 'independent', assistance: {'hint'});
    final repeat = await answer('t0', 'independent');
    expect(repeat.assistance, contains('retry'));
    expect(repeat.firstAttempt, isFalse);
    expect(progress.statsFor('s').independentCount, 0);
    expect(progress.statsFor('s').state, 'supported');
  });

  test(
      'secure observations need varied first attempts across days and allow recovery',
      () async {
    var now = DateTime(2026, 11, 1);
    final progress = KompassProgressService(
        await SharedPreferences.getInstance(),
        clock: () => now);
    final course = fixture();
    for (var i = 0; i < 4; i++) {
      await progress.recordAttempt(
          course: course,
          task: course.taskById('t$i')!,
          answers: {'a': i == 0 ? 'Hauser' : 'Häuser'},
          mode: 'independent');
      if (i == 2) expect(progress.statsFor('s').state, isNot('secure'));
      now = now.add(const Duration(days: 1));
    }
    expect(progress.statsFor('s').state, 'secure');
    now = now.add(const Duration(days: 20));
    expect(progress.statsFor('s').state, 'developing');
  });

  test('saved plans and valid attempts survive malformed neighbours', () async {
    final prefs = await SharedPreferences.getInstance();
    final course = fixture();
    final progress = KompassProgressService(prefs);
    await progress.recordAttempt(
        course: course,
        task: course.tasks.first,
        answers: {'a': 'Häuser'},
        mode: 'practice');
    await progress.saveSession({
      'courseId': course.id,
      'courseVersion': 1,
      'mode': 'practice',
      'taskIds': ['t0'],
      'answers': {
        't0': {'a': 'Hä'}
      }
    });
    final payload =
        jsonDecode(prefs.getString(KompassProgressService.storageKey)!)
            as Map<String, dynamic>;
    (payload['attempts'] as List).insert(0, {'broken': 'original data'});
    await prefs.setString(
        KompassProgressService.storageKey, jsonEncode(payload));
    final restored = KompassProgressService(prefs);
    expect(restored.attempts, hasLength(1));
    expect(restored.storageError, isNotNull);
    expect(restored.activeSession!['answers']['t0']['a'], 'Hä');
    await restored.setNotTaught('s', true);
    expect(prefs.getString(KompassProgressService.storageKey),
        contains('original data'));
    await restored.clear();
    expect(KompassProgressService(prefs).attempts, isEmpty);
    expect(KompassProgressService(prefs).activeSession, isNull);
  });

  test(
      'unreadable whole progress is backed up before new observations overwrite it',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KompassProgressService.storageKey, '{bad json');
    final progress = KompassProgressService(prefs);
    expect(progress.storageError, isNotNull);
    await progress.setNotTaught('s', true);
    expect(prefs.getString(KompassProgressService.recoveryKey), '{bad json');
    expect(KompassProgressService(prefs).notTaught, {'s'});
  });

  test(
      'daily plans fit budgets including each passage once and reserve transfer',
      () async {
    final progress =
        KompassProgressService(await SharedPreferences.getInstance());
    for (final minutes in [5, 10, 15, 20]) {
      final plan = KompassPlanner.build(real, progress, minutes);
      expect(plan.tasks, isNotEmpty);
      expect(plan.estimatedSeconds, lessThanOrEqualTo(minutes * 60));
      expect(plan.tasks.where((t) => t.kind == 'transfer'), isEmpty);
      expect(plan.tasks.where((t) => t.kind == 'instruction').length,
          lessThanOrEqualTo(1));
      final passages =
          plan.tasks.map((t) => t.stimulusId).whereType<String>().toSet();
      final expected =
          plan.tasks.fold<int>(0, (sum, t) => sum + t.estimatedSeconds) +
              passages.fold<int>(
                  0, (sum, id) => sum + real.stimulusById(id)!.readingSeconds);
      expect(plan.estimatedSeconds, expected);
    }
    final check = KompassPlanner.startCheck(real, progress);
    expect(check.tasks.map((t) => t.domain).toSet(),
        containsAll(['reading', 'spelling', 'language']));
    expect(check.tasks.any((t) => t.kind == 'transfer'), isTrue);
    expect(check.tasks.where((t) => t.kind == 'instruction'), isEmpty);
    await progress.recordAttempt(
        course: real, task: check.tasks.first, answers: {}, mode: 'startCheck');
    expect(KompassPlanner.startCheck(real, progress).tasks.map((t) => t.id),
        isNot(contains(check.tasks.first.id)));
  });

  test('new questions on familiar passages are not fresh transfer evidence',
      () async {
    final progress =
        KompassProgressService(await SharedPreferences.getInstance());
    final first = await progress.recordAttempt(
        course: real,
        task: real.taskById('d1_01')!,
        answers: {'a': 'Montag', 'b': 'Abstellraum'},
        mode: 'independent',
        sessionId: 'one');
    final sameSession = await progress.recordAttempt(
        course: real,
        task: real.taskById('d1_02')!,
        answers: {},
        mode: 'independent',
        sessionId: 'one');
    final later = await progress.recordAttempt(
        course: real,
        task: real.taskById('d1_03')!,
        answers: {},
        mode: 'independent',
        sessionId: 'two');
    expect(first.independent, isTrue);
    expect(sameSession.independent, isTrue);
    expect(later.independent, isFalse);
    expect(later.assistance, contains('knownPassage'));
    expect(KompassPlanner.isFresh(real, progress, real.taskById('d1_04')!),
        isFalse);
    expect(KompassPlanner.isFresh(real, progress, real.taskById('d2_04')!),
        isTrue);
  });

  test('saved criterion text and course fingerprint survive content revisions',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final original = fixture();
    final progress = KompassProgressService(prefs);
    await progress.recordAttempt(
        course: original,
        task: original.taskById('mixed')!,
        answers: {'a': 'Häuser', 'b': 'Begründung'},
        mode: 'practice');
    final revisedJson =
        jsonDecode(jsonEncode(original.metadata)) as Map<String, dynamic>;
    final changed =
        (revisedJson['tasks'] as List).firstWhere((t) => t['id'] == 'mixed');
    changed['parts'][1]['rubric'] = ['A different future criterion'];
    final revised = KompassCourse.fromJson(revisedJson);
    expect(revised.fingerprint, isNot(original.fingerprint));
    final restored = KompassProgressService(prefs).attempts.single;
    expect(restored.courseFingerprint, original.fingerprint);
    expect(restored.parts.last.rubric, ['0, 0.5 oder 1 Punkt nach Kriterium.']);
    expect(restored.parts.last.prompt, 'b');
  });

  test(
    'abandoned drafts retain exposure without inventing skill observations',
    () async {
      final prefs = await SharedPreferences.getInstance();
      var progress = KompassProgressService(prefs);
      await progress.saveSession({
        'courseId': real.id,
        'courseVersion': real.version,
        'sessionId': 'practice-one',
        'mode': 'practice',
        'taskIds': ['d1_01', 'd2_01'],
        'index': 0,
        'answers': {
          'd1_01': {'a': 'Mon'},
        },
        'assistance': {
          'd1_01': ['hint'],
        },
      }, course: real);
      expect(progress.attempts, isEmpty);
      expect(progress.statsFor('D-L01').state, 'unobserved');
      expect(
        KompassPlanner.isFresh(real, progress, real.taskById('d1_01')!),
        isFalse,
      );
      expect(
        KompassPlanner.isFresh(real, progress, real.taskById('d1_02')!),
        isFalse,
      );
      expect(
        KompassPlanner.isFresh(real, progress, real.taskById('d2_01')!),
        isTrue,
        reason: 'A queued page has not been read yet.',
      );

      await progress.saveSession(null, course: real);
      progress = KompassProgressService(prefs);
      expect(progress.activeSession, isNull);
      expect(progress.attempts, isEmpty);
      expect(
        KompassPlanner.isFresh(real, progress, real.taskById('d1_01')!),
        isFalse,
      );
      expect(
        KompassPlanner.isFresh(real, progress, real.taskById('d1_02')!),
        isFalse,
      );
      final repeated = await progress.recordAttempt(
        course: real,
        task: real.taskById('d1_01')!,
        answers: {'a': 'Montag', 'b': 'Abstellraum'},
        mode: 'independent',
        sessionId: 'check-two',
      );
      expect(repeated.firstAttempt, isTrue);
      expect(repeated.independent, isFalse);
      expect(repeated.assistance, containsAll(['knownTask', 'knownPassage']));
      await progress.clear();
      final cleared = KompassProgressService(prefs);
      expect(
        KompassPlanner.isFresh(real, cleared, real.taskById('d1_01')!),
        isTrue,
      );
    },
  );

  test(
    'viewing and resuming within one new check preserves independent evidence',
    () async {
      final prefs = await SharedPreferences.getInstance();
      var progress = KompassProgressService(prefs);
      await progress.saveSession({
        'courseId': real.id,
        'courseVersion': real.version,
        'sessionId': 'new-check',
        'mode': 'independent',
        'taskIds': ['d1_01', 'd1_02'],
        'index': 1,
        'elapsed': {'d1_01': 10, 'd1_02': 0},
      }, course: real);
      progress = KompassProgressService(prefs);
      for (final id in ['d1_01', 'd1_02']) {
        final attempt = await progress.recordAttempt(
          course: real,
          task: real.taskById(id)!,
          answers: {},
          mode: 'independent',
          sessionId: 'new-check',
        );
        expect(attempt.independent, isTrue);
      }
      final later = await progress.recordAttempt(
        course: real,
        task: real.taskById('d1_03')!,
        answers: {},
        mode: 'independent',
        sessionId: 'later-check',
      );
      expect(later.independent, isFalse);
      expect(later.assistance, contains('knownPassage'));
    },
  );

  test(
    'legacy drafts preserve viewed pages when a new session replaces them',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final course = fixture();
      await prefs.setString(
        KompassProgressService.storageKey,
        jsonEncode({
          'schemaVersion': 1,
          'attempts': [],
          'activeSession': {
            'courseId': course.id,
            'courseVersion': course.version,
            'mode': 'practice',
            'taskIds': ['t0', 't1', 't2'],
            'index': 1,
            'elapsed': {'t0': 7},
          },
        }),
      );
      final progress = KompassProgressService(prefs);
      expect(
        KompassPlanner.isFresh(course, progress, course.taskById('t0')!),
        isFalse,
      );
      expect(
        KompassPlanner.isFresh(course, progress, course.taskById('t1')!),
        isFalse,
      );
      expect(
        KompassPlanner.isFresh(course, progress, course.taskById('t2')!),
        isTrue,
      );
      await progress.saveSession({
        'courseId': course.id,
        'courseVersion': course.version,
        'sessionId': 'replacement',
        'mode': 'independent',
        'taskIds': ['t2'],
      }, course: course);
      final restored = KompassProgressService(prefs);
      expect(
        KompassPlanner.isFresh(course, restored, course.taskById('t0')!),
        isFalse,
      );
      expect(
        KompassPlanner.isFresh(course, restored, course.taskById('t1')!),
        isFalse,
      );
      expect(restored.attempts, isEmpty);
    },
  );

  test('malformed draft is preserved without crashing resume', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        KompassProgressService.storageKey,
        jsonEncode({
          'schemaVersion': 1,
          'attempts': [],
          'activeSession': {
            'courseId': 'fixture',
            'courseVersion': 1,
            'taskIds': ['t0'],
            'mode': 'practice',
            'answers': ['broken draft']
          }
        }));
    final progress = KompassProgressService(prefs);
    expect(progress.activeSession, isNull);
    expect(progress.storageError, isNotNull);
    await progress.setNotTaught('s', true);
    expect(prefs.getString(KompassProgressService.storageKey),
        contains('broken draft'));
  });

  test('not-yet-taught skills exclude tasks without recording failure',
      () async {
    final progress =
        KompassProgressService(await SharedPreferences.getInstance());
    await progress.setNotTaught('D-L02', true);
    final plan = KompassPlanner.build(real, progress, 20);
    expect(plan.tasks.where((t) => t.competencyIds.contains('D-L02')), isEmpty);
    expect(progress.statsFor('D-L02').attempts, 0);
    for (final c in real.competencies) {
      await progress.setNotTaught(c.id, true);
    }
    expect(KompassPlanner.build(real, progress, 20).tasks, isEmpty);
    expect(KompassPlanner.startCheck(real, progress).tasks, isEmpty);
  });
}
