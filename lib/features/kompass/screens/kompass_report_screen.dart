import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/kompass_models.dart';
import '../services/kompass_course_service.dart';
import '../services/kompass_progress_service.dart';
import '../widgets/kompass_strings.dart';
import '../widgets/kompass_ui.dart';
import '../widgets/kompass_review_sheet.dart';

class KompassReportScreen extends StatelessWidget {
  const KompassReportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final course = context.watch<KompassCourseService>().course;
    final progress = context.watch<KompassProgressService>();
    final s = KompassStrings.of(context);
    if (course == null)
      return KompassPage(
          title: s.report,
          child: const Center(child: CircularProgressIndicator()));
    final pending = progress.attempts
        .where((a) => a.pendingPoints > 0)
        .toList()
        .reversed
        .toList();
    return KompassPage(
        title: s.report,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KompassSectionTitle(
                        title: s.choose('Was du schon gezeigt hast',
                            'What you have already shown'),
                        subtitle: s.choose(
                            'Ein Lernbild wächst mit verschiedenen Aufgaben und mehreren Versuchen.',
                            'A learning picture grows through different tasks and several attempts.')),
                    KompassNotice(
                        text: s.choose(
                            'Selbstständige Versuche, Hilfe und offene Rückmeldungen werden getrennt betrachtet. Wenige Aufgaben sind nur ein erster Eindruck. Wiederholte Lösungen derselben Aufgabe belegen noch keinen sicheren Transfer.',
                            'Independent attempts, support and pending reviews are considered separately. A few tasks give only an initial impression. Repeating the same task does not yet show secure transfer.')),
                    const SizedBox(height: 18),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      KompassBadge(
                          label: s.choose(
                              '${progress.attempts.length} bearbeitete Aufgaben',
                              '${progress.attempts.length} task attempts'),
                          icon: Icons.edit_note_rounded),
                      KompassBadge(
                          label: s.choose(
                              '${progress.attempts.where((a) => a.independent).length} ohne Hilfe',
                              '${progress.attempts.where((a) => a.independent).length} without assistance'),
                          icon: Icons.person_outline_rounded),
                      KompassBadge(
                          label: '${pending.length} ${s.pending}',
                          icon: Icons.rate_review_outlined,
                          color: const Color(0xFFFFEFCE)),
                    ]),
                    if (progress.storageError != null) ...[
                      const SizedBox(height: 14),
                      KompassNotice(
                          text: s.storageWarning,
                          color: const Color(0xFFFFEFCE))
                    ],
                    if (pending.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      KompassSectionTitle(
                          title: s.pending,
                          subtitle: s.choose(
                              'Diese Antworten brauchen einen Menschen und die Kriterien.',
                              'These answers need a person and the rubric.')),
                      for (final attempt in pending)
                        Builder(builder: (context) {
                          final task = course.taskById(attempt.taskId);
                          if (task == null) return const SizedBox.shrink();
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: KompassCard(
                                child: Wrap(
                                  spacing: 16,
                                  runSpacing: 12,
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(task.title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: kompassInk,
                                                  fontSize: 17)),
                                          const SizedBox(height: 6),
                                          Text(
                                              s.choose(
                                                  '${kompassPoints(attempt.pendingPoints)} Punkte noch offen',
                                                  '${kompassPoints(attempt.pendingPoints)} points pending'),
                                              style: const TextStyle(
                                                  color: kompassMuted)),
                                        ]),
                                    OutlinedButton.icon(
                                        onPressed: () => showKompassReview(
                                            context, task, attempt),
                                        icon: const Icon(
                                            Icons.rate_review_outlined),
                                        label: Text(s.review)),
                                  ],
                                ),
                              ));
                        }),
                    ],
                    for (final domain in [
                      'reading',
                      'spelling',
                      'language'
                    ]) ...[
                      const SizedBox(height: 20),
                      KompassSectionTitle(title: s.domain(domain)),
                      for (final skill in course.competencies
                          .where((c) => c.domain == domain))
                        _skill(context, skill, progress),
                    ],
                    const SizedBox(height: 20),
                    KompassSectionTitle(
                        title: s.domain('instructions'),
                        subtitle: s.choose(
                            'Aufträge üben hilft beim Bearbeiten. Diese Übung allein belegt keine Deutsch-Fachkompetenz.',
                            'Practising instructions helps you work through tasks. It does not by itself demonstrate German subject skills.')),
                    for (final task in course.tasks
                        .where((t) => t.domain == 'instructions'))
                      Builder(builder: (context) {
                        final attempts = progress.attempts
                            .where((a) => a.taskId == task.id)
                            .toList();
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: KompassCard(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                  Icon(
                                      attempts.isEmpty
                                          ? Icons.radio_button_unchecked
                                          : Icons.check_circle_outline_rounded,
                                      color: kompassMuted),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text(task.title,
                                          style: const TextStyle(
                                              color: kompassInk,
                                              fontWeight: FontWeight.w600))),
                                  const SizedBox(width: 8),
                                  Text(
                                      s.choose('${attempts.length} Versuche',
                                          '${attempts.length} attempts'),
                                      style: const TextStyle(
                                          color: kompassMuted, fontSize: 12)),
                                ])));
                      }),
                    const SizedBox(height: 20),
                    KompassNotice(
                        text: s.choose(
                            '„Noch nicht gelernt“ nimmt eine Fähigkeit aus der automatischen Lernrunde. Du kannst sie hier jederzeit wieder einschalten. Das ist kein Fehler und keine Bewertung.',
                            '“Not taught yet” removes a skill from automatic practice sessions. You can include it again here at any time. It is not an error or an assessment.')),
                    const SizedBox(height: 20),
                    Text(s.saved,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: kompassMuted, fontSize: 12)),
                  ],
                )),
          ),
        ));
  }

  Widget _skill(BuildContext context, KompassCompetency skill,
      KompassProgressService progress) {
    final s = KompassStrings.of(context);
    final stats = progress.statsFor(skill.id);
    final excluded = progress.notTaught.contains(skill.id);
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: KompassCard(
          padding: const EdgeInsets.all(8),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(kompassDomainIcon(skill.domain), color: kompassMuted),
            title: Text(skill.title,
                style: const TextStyle(
                    color: kompassInk, fontWeight: FontWeight.w600)),
            subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(excluded ? s.notTaught : s.state(stats.state),
                    style: TextStyle(
                        color: stats.state == 'secure'
                            ? const Color(0xFF21725B)
                            : kompassMuted,
                        fontSize: 13))),
            childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(skill.goal,
                      style: const TextStyle(color: kompassInk, height: 1.5))),
              const SizedBox(height: 14),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      KompassBadge(
                          label: s.choose(
                              '${stats.independentCount} selbstständig',
                              '${stats.independentCount} independent')),
                      KompassBadge(
                          label: s.choose('${stats.supportedCount} mit Hilfe',
                              '${stats.supportedCount} supported'),
                          color: const Color(0xFFE9E5F8)),
                      KompassBadge(
                          label: '${stats.pendingCount} ${s.pending}',
                          color: const Color(0xFFFFEFCE)),
                    ],
                  )),
              if (skill.easier != null && stats.state != 'secure') ...[
                const SizedBox(height: 14),
                KompassNotice(
                    text:
                        '${s.choose('Ein nächster kleiner Schritt:', 'A small next step:')}\n${skill.easier}',
                    icon: Icons.lightbulb_outline_rounded),
              ],
              if (skill.harder != null && stats.state == 'secure') ...[
                const SizedBox(height: 14),
                KompassNotice(
                    text:
                        '${s.choose('Eine neue Herausforderung:', 'A new challenge:')}\n${skill.harder}',
                    icon: Icons.explore_outlined),
              ],
              SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: excluded,
                  onChanged: (value) => progress.setNotTaught(skill.id, value),
                  title: Text(s.notTaught,
                      style: const TextStyle(color: kompassInk, fontSize: 15))),
              if (skill.curriculumUrl != null)
                Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        onPressed: () => launchUrl(
                            Uri.parse(skill.curriculumUrl!),
                            mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: Text(s.choose('Im Bildungsplan nachlesen',
                            'Read the curriculum reference')))),
            ],
          ),
        ));
  }
}
