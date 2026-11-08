import '../models/kompass_models.dart';
import 'kompass_progress_service.dart';

class KompassPlan {
  final List<KompassTask> tasks;
  final int estimatedSeconds;
  final String reason;
  const KompassPlan({
    required this.tasks,
    required this.estimatedSeconds,
    required this.reason,
  });
}

/// Content estimates are a planning aid, not a speed target. Reading a shared
/// passage is budgeted once per session, even if it was seen on a previous day.
class KompassPlanner {
  static bool isFresh(
      KompassCourse course, KompassProgressService progress, KompassTask task) {
    if (task.kind == 'instruction' || progress.latestAttempt(task.id) != null)
      return false;
    if (task.competencyIds.any(progress.notTaught.contains) ||
        task.prerequisiteCompetencyIds.any(progress.notTaught.contains))
      return false;
    if (task.competencyIds.any((id) =>
        (course.competencyById(id)?.prerequisites ?? [])
            .any(progress.notTaught.contains))) return false;
    return task.stimulusId == null ||
        !progress.attempts.any(
            (a) => a.courseId == course.id && a.stimulusId == task.stimulusId);
  }

  static KompassPlan build(
    KompassCourse course,
    KompassProgressService progress,
    int minutes, {
    String? domain,
  }) =>
      _plan(course, progress, minutes, domain: domain);

  static KompassPlan startCheck(
    KompassCourse course,
    KompassProgressService progress, {
    int minutes = 10,
  }) =>
      _plan(course, progress, minutes, independent: true);

  static KompassPlan _plan(
    KompassCourse course,
    KompassProgressService progress,
    int minutes, {
    String? domain,
    bool independent = false,
  }) {
    final budget = minutes.clamp(1, 60) * 60;
    final candidates = course.tasks.where((task) {
      if (domain != null && task.domain != domain) return false;
      if (task.competencyIds.any(progress.notTaught.contains)) return false;
      if (task.prerequisiteCompetencyIds.any(progress.notTaught.contains))
        return false;
      if (task.competencyIds.any(
        (id) => (course.competencyById(id)?.prerequisites ?? []).any(
          progress.notTaught.contains,
        ),
      )) return false;
      if (independent) return isFresh(course, progress, task);
      return task.kind != 'transfer';
    }).toList();

    double priority(KompassTask task) {
      final last = progress.latestAttempt(task.id);
      var score = last == null ? 30.0 : 0.0;
      for (final skill in task.competencyIds) {
        final stats = progress.statsFor(skill);
        score += (switch (stats.state) {
              'unobserved' => 20,
              'learning' => 35,
              'supported' => 25,
              'developing' => 15,
              _ => 5,
            }) /
            task.competencyIds.length;
      }
      if (last != null) {
        final days = progress.now.difference(last.occurredAt).inHours / 24;
        score += days.clamp(0, 14) * 2;
        final scored = last.possiblePoints - last.pendingPoints;
        if (scored > 0 && last.earnedPoints / scored < 0.8) score += 20;
        if (days < 1) score -= 45;
      }
      if (independent && task.kind == 'transfer') score += 50;
      return score;
    }

    final priorities = {for (final task in candidates) task.id: priority(task)};
    final chosen = <KompassTask>[];
    final passages = <String>{}, domains = <String>{};
    var used = 0;
    while (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final aPriority =
            priorities[a.id]! + (domains.contains(a.domain) ? 0 : 45);
        final bPriority =
            priorities[b.id]! + (domains.contains(b.domain) ? 0 : 45);
        final byScore = bPriority.compareTo(aPriority);
        return byScore != 0 ? byScore : a.id.compareTo(b.id);
      });
      KompassTask? next;
      var cost = 0;
      for (final task in candidates) {
        if (domain == null &&
            task.kind == 'instruction' &&
            chosen.any((t) => t.kind == 'instruction')) continue;
        final passage = course.stimulusById(task.stimulusId);
        final seconds = task.estimatedSeconds +
            (passage != null && !passages.contains(passage.id)
                ? passage.readingSeconds
                : 0);
        if (seconds <= budget - used) {
          next = task;
          cost = seconds;
          break;
        }
      }
      if (next == null) break;
      chosen.add(next);
      candidates.remove(next);
      used += cost;
      domains.add(next.domain);
      if (next.stimulusId != null) passages.add(next.stimulusId!);
    }
    return KompassPlan(
      tasks: List.unmodifiable(chosen),
      estimatedSeconds: used,
      reason: chosen.isEmpty
          ? (independent
              ? 'Keine ungesehenen Aufgaben passen in diese Zeit und zu den behandelten Themen. Wähle mehr Zeit oder übe gezielt.'
              : 'Keine passenden Aufgaben in dieser Zeit. Wähle mehr Zeit oder prüfe die noch nicht behandelten Themen.')
          : independent
              ? 'Ungesehene Aufgaben zeigen, was du schon selbstständig kannst. Offene Antworten werden mit einer Rubrik besprochen.'
              : 'Dein Plan berücksichtigt Übungsbedarf, Wiederholungen, behandelte Themen und Zeit zum Lesen. Die Zeiten sind Schätzungen.',
    );
  }
}
