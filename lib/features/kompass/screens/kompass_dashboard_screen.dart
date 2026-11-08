import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/learner_profile_service.dart';
import '../models/kompass_models.dart';
import '../services/kompass_course_service.dart';
import '../services/kompass_progress_service.dart';
import '../services/kompass_planner.dart';
import '../widgets/kompass_strings.dart';
import '../widgets/kompass_ui.dart';
import 'kompass_player_screen.dart';
import 'kompass_report_screen.dart';
import 'kompass_print_screen.dart';

class KompassDashboardScreen extends StatefulWidget {
  static const routeName = '/kompass';
  const KompassDashboardScreen({super.key});
  @override
  State<KompassDashboardScreen> createState() => _KompassDashboardScreenState();
}

class _KompassDashboardScreenState extends State<KompassDashboardScreen> {
  int _minutes = 10;
  @override
  void initState() {
    super.initState();
    _minutes = context.read<LearnerProfileService?>()?.sessionMinutes ?? 10;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<KompassCourseService>().load();
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<KompassCourseService>();
    final progress = context.watch<KompassProgressService>();
    final s = KompassStrings.of(context);
    final course = service.course;
    return KompassPage(
      title: s.title,
      actions: [
        IconButton(
            tooltip: s.report,
            icon: const Icon(Icons.insights_rounded),
            onPressed: course == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const KompassReportScreen()))),
        const SizedBox(width: 8),
      ],
      child: service.loading && course == null
          ? const Center(child: CircularProgressIndicator())
          : course == null
              ? KompassEmpty(
                  title: s.choose(
                      'Kurs wird vorbereitet', 'Preparing your course'),
                  message: s.choose(
                      'Der Kurs konnte nicht geladen werden. Versuche es noch einmal.',
                      'The course could not be loaded. Please try again.'),
                  action: FilledButton.icon(
                      onPressed: service.load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(s.retry)))
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                        padding: EdgeInsets.all(
                            constraints.maxWidth < 600 ? 16 : 28),
                        child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1160),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _hero(context),
                                  const SizedBox(height: 20),
                                  if (progress.storageError != null) ...[
                                    KompassNotice(
                                        text: s.storageWarning,
                                        icon: Icons.cloud_off_rounded,
                                        color: const Color(0xFFFFEFCE)),
                                    const SizedBox(height: 16),
                                  ],
                                  if (progress.activeSession != null) ...[
                                    _resume(context, progress.activeSession!),
                                    const SizedBox(height: 16),
                                  ],
                                  _daily(context, course, progress),
                                  const SizedBox(height: 16),
                                  KompassSectionTitle(
                                      title: s.choose(
                                          'Woran möchtest du arbeiten?',
                                          'What would you like to practise?'),
                                      subtitle: s.choose(
                                          'Vier Lernorte. Zeit für jeden Schritt.',
                                          'Four learning spaces. Time for every step.')),
                                  LayoutBuilder(builder: (context, c) {
                                    final columns = c.maxWidth >= 1000
                                        ? 4
                                        : c.maxWidth >= 560
                                            ? 2
                                            : 1;
                                    final width =
                                        (c.maxWidth - (columns - 1) * 14) /
                                            columns;
                                    return Wrap(
                                        spacing: 14,
                                        runSpacing: 14,
                                        children: [
                                          for (final domain in [
                                            'reading',
                                            'spelling',
                                            'language',
                                            'instructions'
                                          ])
                                            SizedBox(
                                                width: width,
                                                child: _domain(context, course,
                                                    progress, domain)),
                                        ]);
                                  }),
                                  const SizedBox(height: 24),
                                  KompassSectionTitle(
                                      title: s.choose('Eine ganze Übungsarbeit',
                                          'A complete practice paper'),
                                      subtitle: s.choose(
                                          'Vier eigene Übungsarbeiten aus unserem Kompass4-Projekt. Je 24 Aufgaben mit Lesetext und Lösungen.',
                                          'Four practice papers from our Kompass4 project. Each has 24 tasks, a reading passage and solutions.')),
                                  for (var i = 0; i < course.tests.length; i++)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: _testCard(
                                          context, course.tests[i], i + 1),
                                    ),
                                  const SizedBox(height: 18),
                                  KompassNotice(
                                      text: s.choose(
                                          'Hier übst du Fähigkeiten für Deutsch in Klasse 3/4. Dein Lernbild zeigt Beobachtungen aus diesen Aufgaben. Es ist keine Vorhersage für ein Testergebnis oder eine Schulartempfehlung.',
                                          'Practise German skills for grades 3/4 here. Your learning picture describes observations from these tasks. It does not predict a test result or recommend a school type.')),
                                  const SizedBox(height: 16),
                                  Text(
                                      s.choose(
                                          'Deine Antworten bleiben auf diesem Gerät. Die Lerninhalte sind auf Deutsch.',
                                          'Your answers stay on this device. Learning content is in German.'),
                                      style: const TextStyle(
                                          color: kompassMuted, fontSize: 12),
                                      textAlign: TextAlign.center),
                                ],
                              ),
                            )),
                      )),
    );
  }

  Widget _hero(BuildContext context) {
    final s = KompassStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
              colors: [Color(0xFF152A46), Color(0xFF204F5D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
      child: LayoutBuilder(
          builder: (context, c) =>
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const KompassBadge(
                          label: 'BADEN-WÜRTTEMBERG · KLASSE 3/4',
                          color: kompassTeal,
                          icon: Icons.explore_rounded),
                      const SizedBox(height: 18),
                      Text(
                          s.choose('Schritt für Schritt\nsicherer werden.',
                              'Grow more confident,\none step at a time.'),
                          style: TextStyle(
                              fontSize: c.maxWidth < 500 ? 28 : 36,
                              height: 1.15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 14),
                      Text(
                          s.choose(
                              'Lies genau. Prüfe Wörter. Verstehe Sätze.\nFinde heraus, was du schon kannst und was dir als Nächstes hilft.',
                              'Read closely. Check words. Understand sentences.\nDiscover what you can do and what will help you next.'),
                          style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFFD4E5ED),
                              height: 1.6)),
                    ])),
                if (c.maxWidth > 680)
                  const Padding(
                      padding: EdgeInsets.only(left: 28, top: 10),
                      child: Icon(Icons.explore_rounded,
                          size: 130, color: kompassTeal)),
              ])),
    );
  }

  Widget _resume(BuildContext context, Map<String, dynamic> session) {
    final s = KompassStrings.of(context);
    return KompassCard(
        color: const Color(0xFFE2F3ED),
        child: Wrap(
          spacing: 20,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  s.choose(
                      'Deine Runde wartet auf dich', 'Your session is waiting'),
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: kompassInk)),
              const SizedBox(height: 6),
              Text(s.mode('${session['mode'] ?? 'practice'}'),
                  style: const TextStyle(color: kompassMuted)),
            ]),
            FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => KompassPlayerScreen.resume(session))),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(s.continueLabel)),
          ],
        ));
  }

  Widget _daily(BuildContext context, KompassCourse course,
      KompassProgressService progress) {
    final s = KompassStrings.of(context);
    return KompassCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.auto_awesome_rounded, color: Color(0xFF1A796B)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
                s.choose(
                    'Deine nächste kleine Runde', 'Your next small session'),
                style: const TextStyle(
                    color: kompassInk,
                    fontWeight: FontWeight.bold,
                    fontSize: 23)))
      ]),
      const SizedBox(height: 10),
      Text(
          s.choose(
              'Eine passende Mischung aus Wiederholen und neuen Aufgaben. Der Lesetext bekommt seine eigene Zeit.',
              'A suitable mix of review and new tasks, with time set aside for reading the passage.'),
          style: const TextStyle(color: kompassMuted, height: 1.5)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final minutes in ([
          ...{5, 10, 15, 20, _minutes}
        ]..sort()))
          ChoiceChip(
              label: Text('$minutes ${s.minutes}'),
              selected: _minutes == minutes,
              onSelected: (_) {
                setState(() => _minutes = minutes);
                context
                    .read<LearnerProfileService?>()
                    ?.setSessionMinutes(minutes);
              }),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 10, children: [
        FilledButton.icon(
            key: const ValueKey('kompass-daily-start'),
            onPressed: () {
              final plan = KompassPlanner.build(course, progress, _minutes);
              _openPlan(context, plan.tasks, 'practice',
                  s.choose('Meine Lernrunde', 'My practice session'));
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(s.choose('Jetzt üben', 'Start practising'))),
        OutlinedButton.icon(
            key: const ValueKey('kompass-start-check'),
            onPressed: () {
              final plan = KompassPlanner.startCheck(course, progress,
                  minutes: _minutes);
              _openPlan(context, plan.tasks, 'startCheck', s.startCheck);
            },
            icon: const Icon(Icons.track_changes_rounded),
            label: Text(s.startCheck)),
        TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const KompassReportScreen())),
            icon: const Icon(Icons.insights_rounded),
            label: Text(s.report)),
      ]),
      const SizedBox(height: 8),
      Text(
          s.choose(
              'Beim Start-Check gibt es keine Hilfen. „Noch nicht gelernt“ und Überspringen sind immer erlaubt.',
              'The starting check has no hints. You can always choose “Not taught yet” or skip.'),
          style:
              const TextStyle(color: kompassMuted, fontSize: 12, height: 1.4)),
    ]));
  }

  Widget _domain(BuildContext context, KompassCourse course,
      KompassProgressService progress, String domain) {
    final s = KompassStrings.of(context);
    final skills =
        course.competencies.where((c) => c.domain == domain).toList();
    final instructionIds = course.tasks
        .where((t) => t.domain == 'instructions')
        .map((t) => t.id)
        .toSet();
    final isInstructions = domain == 'instructions';
    final total = isInstructions ? instructionIds.length : skills.length;
    final observed = isInstructions
        ? progress.attempts
            .where((a) => instructionIds.contains(a.taskId))
            .map((a) => a.taskId)
            .toSet()
            .length
        : skills
            .where((skill) => progress.statsFor(skill.id).attempts > 0)
            .length;
    return KompassCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
          alignment: Alignment.centerLeft,
          child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: kompassDomainColor(domain),
                  borderRadius: BorderRadius.circular(15)),
              child: Icon(kompassDomainIcon(domain),
                  color: kompassInk, size: 30))),
      const SizedBox(height: 16),
      Text(s.game(domain),
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: kompassInk, fontSize: 21)),
      const SizedBox(height: 8),
      Text(s.gameGoal(domain),
          style: const TextStyle(color: kompassMuted, height: 1.5)),
      const SizedBox(height: 14),
      Text(
          isInstructions
              ? s.choose('$observed von $total Aufträgen bearbeitet',
                  '$observed of $total instruction tasks attempted')
              : s.choose('$observed von $total Fähigkeiten beobachtet',
                  '$observed of $total skills observed'),
          style: const TextStyle(color: kompassMuted, fontSize: 12)),
      const SizedBox(height: 6),
      ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
              value: total == 0 ? 0 : observed / total,
              backgroundColor: const Color(0xFFE6ECF2),
              color: const Color(0xFF2B7C75),
              minHeight: 5)),
      const SizedBox(height: 16),
      OutlinedButton(
          onPressed: () {
            final plan = KompassPlanner.build(course, progress, _minutes,
                domain: domain);
            _openPlan(context, plan.tasks, 'practice', s.game(domain));
          },
          child: Text(s.choose('Hier üben', 'Practise here'))),
    ]));
  }

  Widget _testCard(BuildContext context, KompassTest test, int index) {
    final s = KompassStrings.of(context);
    return KompassCard(child: LayoutBuilder(builder: (context, c) {
      final heading =
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
            backgroundColor: const Color(0xFFE9EFF6),
            foregroundColor: kompassInk,
            child: Text('$index',
                style: const TextStyle(fontWeight: FontWeight.bold))),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(test.title,
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: kompassInk)),
          const SizedBox(height: 5),
          Text(
              s.choose(
                  '${test.taskIds.length} Aufgaben · ${test.totalSeconds ~/ 60} Minuten mit Uhr',
                  '${test.taskIds.length} tasks · ${test.totalSeconds ~/ 60} minutes when timed'),
              style: const TextStyle(color: kompassMuted, height: 1.4)),
        ])),
      ]);
      final controls = Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(
            onPressed: () => _startPaper(context, test),
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(s.independent)),
        OutlinedButton.icon(
            onPressed: () {
              final course = context.read<KompassCourseService>().course!;
              _openPlan(
                  context,
                  test.taskIds
                      .map(course.taskById)
                      .whereType<KompassTask>()
                      .toList(),
                  'practice',
                  test.title);
            },
            icon: const Icon(Icons.lightbulb_outline_rounded),
            label: Text(s.choose('Mit Hilfe üben', 'Practise with support'))),
        OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => KompassPrintScreen(test: test))),
            icon: const Icon(Icons.print_outlined),
            label: Text(s.choose('Papier', 'Paper'))),
      ]);
      return c.maxWidth < 1050
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, const SizedBox(height: 16), controls])
          : Row(children: [
              Expanded(child: heading),
              const SizedBox(width: 20),
              controls
            ]);
    }));
  }

  Future<bool> _replaceSession(BuildContext context) async {
    final progress = context.read<KompassProgressService>();
    if (progress.activeSession == null) return true;
    final s = KompassStrings.of(context);
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(s.choose(
                      'Eine neue Runde beginnen?', 'Start a new session?')),
                  content: Text(s.choose(
                      'Der gespeicherte Zwischenstand wird ersetzt. Bereits geprüfte Antworten bleiben in deinem Lernbild.',
                      'This replaces your saved session draft. Previously reviewed answers remain in your learning picture.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(s.cancel)),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(s.choose('Neue Runde', 'New session')))
                  ],
                )) ??
        false;
  }

  Future<void> _openPlan(BuildContext context, List<KompassTask> tasks,
      String mode, String title) async {
    final s = KompassStrings.of(context);
    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.choose(
              'Hier ist gerade keine passende Aufgabe frei. Prüfe im Lernbild „Noch nicht gelernt“ oder wähle einen anderen Lernort.',
              'There is no suitable task available here. Check “Not taught yet” in your learning picture or choose another area.'))));
      return;
    }
    if (!await _replaceSession(context) || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => KompassPlayerScreen(
            taskIds: tasks.map((t) => t.id).toList(),
            mode: mode,
            title: title)));
  }

  Future<void> _startPaper(BuildContext context, KompassTest test) async {
    final s = KompassStrings.of(context);
    final progress = context.read<KompassProgressService>();
    final course = context.read<KompassCourseService>().course!;
    final freshIds = test.taskIds
        .where((id) =>
            KompassPlanner.isFresh(course, progress, course.taskById(id)!))
        .toList();
    if (freshIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.choose(
              'Diese Aufgaben kennst du schon. Wähle „Mit Hilfe üben“ für eine Wiederholung oder eine andere Übungsarbeit für neue Aufgaben.',
              'You have seen these tasks already. Choose supported practice to repeat them or another paper for fresh tasks.'))));
      return;
    }
    final partial = freshIds.length != test.taskIds.length;
    var timed = !partial;
    final start = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                title: Text(s.independent),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(s.choose(
                          'Bearbeite die Aufgaben in Ruhe. Lösungen und Rückmeldungen erscheinen erst am Ende. Du kannst zu Aufgaben zurückgehen oder sie überspringen.',
                          'Work through the tasks at your own pace. Solutions and feedback appear at the end. You can revisit or skip tasks.')),
                      if (partial)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                                s.choose(
                                    '${freshIds.length} neue Aufgaben zu behandelten Themen sind noch frei. Bekannte Aufgaben und Lesetexte werden hier nicht erneut bewertet. Diese Teilrunde hat keine Uhr.',
                                    '${freshIds.length} fresh tasks on taught topics are available. Familiar tasks and passages are excluded from this independent attempt. This partial session is untimed.'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                      const SizedBox(height: 12),
                      if (!partial)
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: timed,
                            onChanged: (value) =>
                                update(() => timed = value ?? true),
                            title: Text(s.choose(
                                'Mit ${test.totalSeconds ~/ 60}-Minuten-Uhr',
                                'Use a ${test.totalSeconds ~/ 60}-minute timer'))),
                      if (timed)
                        Text(
                            s.choose(
                                'Die Uhr läuft auch weiter, wenn du die App verlässt.',
                                'The timer continues while you are away from the app.'),
                            style: const TextStyle(
                                fontSize: 12, color: kompassMuted)),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(s.cancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(s.choose('Beginnen', 'Begin')))
                ],
              ),
            ));
    if (start != true || !context.mounted) return;
    if (!await _replaceSession(context) || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => KompassPlayerScreen(
            taskIds: freshIds,
            mode: 'independent',
            title: partial
                ? s.choose('Neue Aufgaben · ${test.title}',
                    'Fresh tasks · ${test.title}')
                : test.title,
            timeLimitSeconds: timed ? test.totalSeconds : null)));
  }
}
