import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/kompass_models.dart';
import 'kompass_grader.dart';

class KompassAttempt {
  final String id, courseId, taskId, mode, reviewer, taskKind;
  final String? stimulusId, sessionId, courseFingerprint;
  final int taskVersion, courseVersion, elapsedSeconds;
  final DateTime occurredAt;
  final List<String> competencyIds, assistance;
  final bool firstAttempt;
  final List<KompassPartResult> parts;

  const KompassAttempt({
    required this.id,
    required this.courseId,
    required this.taskId,
    required this.taskVersion,
    required this.courseVersion,
    required this.mode,
    required this.occurredAt,
    required this.competencyIds,
    required this.assistance,
    required this.firstAttempt,
    required this.elapsedSeconds,
    required this.parts,
    this.reviewer = 'automatic',
    this.taskKind = 'practice',
    this.stimulusId,
    this.sessionId,
    this.courseFingerprint,
  });

  double get earnedPoints => parts.fold(0, (sum, p) => sum + (p.points ?? 0));
  double get possiblePoints => parts.fold(0, (sum, p) => sum + p.maxPoints);
  double get pendingPoints =>
      parts.where((p) => p.needsReview).fold(0, (sum, p) => sum + p.maxPoints);
  bool get independent =>
      firstAttempt &&
      assistance.isEmpty &&
      const {'independent', 'startCheck'}.contains(mode);

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'taskId': taskId,
        'taskVersion': taskVersion,
        'courseVersion': courseVersion,
        'mode': mode,
        'occurredAt': occurredAt.toIso8601String(),
        'competencyIds': competencyIds,
        'assistance': assistance,
        'firstAttempt': firstAttempt,
        'elapsedSeconds': elapsedSeconds,
        'parts': parts.map((p) => p.toJson()).toList(),
        'reviewer': reviewer,
        'taskKind': taskKind,
        'stimulusId': stimulusId,
        'sessionId': sessionId,
        'courseFingerprint': courseFingerprint,
      };

  factory KompassAttempt.fromJson(Map<String, dynamic> json) {
    final parts = (json['parts'] as List)
        .map(
          (p) =>
              KompassPartResult.fromJson(Map<String, dynamic>.from(p as Map)),
        )
        .toList();
    if (parts.isEmpty ||
        parts.any(
          (p) =>
              !p.maxPoints.isFinite ||
              p.maxPoints < 0 ||
              (p.points != null &&
                  (!p.points!.isFinite ||
                      p.points! < 0 ||
                      p.points! > p.maxPoints)),
        )) {
      throw const FormatException('Invalid saved task scores');
    }
    return KompassAttempt(
      id: json['id'] as String,
      courseId: json['courseId'] as String,
      taskId: json['taskId'] as String,
      taskVersion: json['taskVersion'] as int,
      courseVersion: json['courseVersion'] as int,
      mode: json['mode'] as String,
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      competencyIds: (json['competencyIds'] as List).cast<String>(),
      assistance: (json['assistance'] as List).cast<String>(),
      firstAttempt: json['firstAttempt'] as bool,
      elapsedSeconds: json['elapsedSeconds'] as int,
      parts: parts,
      reviewer: json['reviewer'] as String? ?? 'automatic',
      taskKind: json['taskKind'] as String? ?? 'practice',
      stimulusId: json['stimulusId'] as String?,
      sessionId: json['sessionId'] as String?,
      courseFingerprint: json['courseFingerprint'] as String?,
    );
  }

  KompassAttempt withReview(
    List<KompassPartResult> reviewedParts,
    String source,
  ) =>
      KompassAttempt(
        id: id,
        courseId: courseId,
        taskId: taskId,
        taskVersion: taskVersion,
        courseVersion: courseVersion,
        mode: mode,
        occurredAt: occurredAt,
        competencyIds: competencyIds,
        assistance: assistance,
        firstAttempt: firstAttempt,
        elapsedSeconds: elapsedSeconds,
        parts: reviewedParts,
        reviewer: source,
        taskKind: taskKind,
        stimulusId: stimulusId,
        sessionId: sessionId,
        courseFingerprint: courseFingerprint,
      );
}

class KompassSkillStats {
  final int attempts, independentCount, supportedCount, pendingCount;
  final double? successRate;
  final String state;
  const KompassSkillStats({
    required this.attempts,
    required this.independentCount,
    required this.supportedCount,
    required this.pendingCount,
    required this.successRate,
    required this.state,
  });
}

/// Local observations, not a prediction of an official test level. Raw answers,
/// assistance and per-part review provenance survive reloads and rubric review.
class KompassProgressService extends ChangeNotifier {
  KompassProgressService(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _load();
  }
  static const storageKey = 'kompass_progress_v1';
  static const recoveryKey = 'kompass_progress_v1_recovery';
  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  final List<KompassAttempt> _attempts = [];
  final Set<String> _notTaught = {};
  final List<dynamic> _unreadableRecords = [];
  Map<String, dynamic>? _activeSession;
  String? _recoveryRaw;
  String? _storageError;
  Future<void> _writes = Future.value();
  int _sequence = 0;

  List<KompassAttempt> get attempts => List.unmodifiable(_attempts);
  Set<String> get notTaught => Set.unmodifiable(_notTaught);
  Map<String, dynamic>? get activeSession => _activeSession == null
      ? null
      : Map<String, dynamic>.from(
          jsonDecode(jsonEncode(_activeSession)) as Map,
        );
  String? get storageError => _storageError;
  DateTime get now => _clock();

  void _load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['schemaVersion'] != 1)
        throw const FormatException('Unsupported progress version');
      final ids = <String>{};
      for (final row in data['attempts'] as List? ?? []) {
        try {
          final attempt = KompassAttempt.fromJson(
            Map<String, dynamic>.from(row as Map),
          );
          if (!ids.add(attempt.id))
            throw const FormatException('Duplicate attempt');
          _attempts.add(attempt);
        } catch (_) {
          _unreadableRecords.add(row);
        }
      }
      _unreadableRecords.addAll(data['unreadableRecords'] as List? ?? []);
      _notTaught.addAll((data['notTaught'] as List? ?? []).whereType<String>());
      if (data['activeSession'] != null &&
          !_validSession(data['activeSession'])) {
        _unreadableRecords.add({'unreadableSession': data['activeSession']});
      } else if (data['activeSession'] is Map) {
        _activeSession = Map<String, dynamic>.from(
          data['activeSession'] as Map,
        );
      }
      if (_unreadableRecords.isNotEmpty) {
        _storageError =
            'Some saved observations could not be read. Their original data is retained.';
      }
    } catch (_) {
      _recoveryRaw = raw;
      _storageError =
          'Saved progress needs recovery. The original data will be preserved before new progress is saved.';
    }
  }

  Future<void> _persist() {
    final snapshot = jsonEncode({
      'schemaVersion': 1,
      'attempts': _attempts.map((a) => a.toJson()).toList(),
      'notTaught': _notTaught.toList()..sort(),
      'activeSession': _activeSession,
      'unreadableRecords': _unreadableRecords,
    });
    _writes = _writes.then((_) async {
      try {
        if (_recoveryRaw != null) {
          if (!await _prefs.setString(recoveryKey, _recoveryRaw!)) {
            throw StateError('Could not preserve original progress');
          }
          _recoveryRaw = null;
        }
        if (!await _prefs.setString(storageKey, snapshot))
          throw StateError('Could not save progress');
        _storageError = _unreadableRecords.isEmpty
            ? null
            : 'Some saved observations could not be read. Their original data is retained.';
      } catch (_) {
        _storageError =
            'Progress could not be saved on this device. Keep this session open and try again.';
      }
      notifyListeners();
    });
    return _writes;
  }

  Future<void> setNotTaught(String skillId, bool value) async {
    if (value) {
      _notTaught.add(skillId);
    } else {
      _notTaught.remove(skillId);
    }
    await _persist();
  }

  Future<void> saveSession(Map<String, dynamic>? session) async {
    if (session != null && !_validSession(session))
      throw ArgumentError('Invalid course session');
    _activeSession = session == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(session)) as Map);
    await _persist();
  }

  static bool _validSession(dynamic raw) {
    if (raw is! Map ||
        raw['courseId'] is! String ||
        raw['courseVersion'] is! int ||
        raw['taskIds'] is! List ||
        !(raw['taskIds'] as List).every((id) => id is String) ||
        !const {'practice', 'independent', 'startCheck', 'paper'}
            .contains(raw['mode']) ||
        (raw['schemaVersion'] != null && raw['schemaVersion'] != 1) ||
        (raw['courseFingerprint'] != null &&
            raw['courseFingerprint'] is! String) ||
        (raw['sessionId'] != null && raw['sessionId'] is! String) ||
        (raw['index'] != null && raw['index'] is! int) ||
        (raw['timeLimitSeconds'] != null && raw['timeLimitSeconds'] is! int))
      return false;
    bool mapOf(String key, bool Function(dynamic) valid) =>
        raw[key] == null ||
        (raw[key] is Map &&
            (raw[key] as Map)
                .entries
                .every((e) => e.key is String && valid(e.value)));
    bool strings(dynamic value) =>
        value is List && value.every((v) => v is String);
    if (!mapOf(
            'answers',
            (v) =>
                v is Map &&
                v.entries.every((e) =>
                    e.key is String &&
                    (e.value == null ||
                        e.value is String ||
                        strings(e.value)))) ||
        !mapOf('assistance', strings) ||
        !mapOf('attemptIds', (v) => v is String) ||
        !mapOf('elapsed', (v) => v is int && v >= 0) ||
        !mapOf('hintCounts', (v) => v is int && v >= 0)) return false;
    return ['skipped', 'seenStimuli']
        .every((key) => raw[key] == null || strings(raw[key]));
  }

  Future<KompassAttempt> recordAttempt({
    required KompassCourse course,
    required KompassTask task,
    required Map<String, dynamic> answers,
    required String mode,
    Set<String> assistance = const {},
    int elapsedSeconds = 0,
    String? sessionId,
  }) async {
    if (!const {
      'practice',
      'independent',
      'startCheck',
      'paper',
    }.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', 'Unknown practice mode');
    }
    if (course.taskById(task.id)?.version != task.version) {
      throw ArgumentError('Task does not belong to this course version');
    }
    final first = !_attempts.any(
      (a) =>
          a.courseId == course.id &&
          a.taskId == task.id &&
          a.taskVersion == task.version,
    );
    final knownPassage = task.stimulusId != null &&
        _attempts.any((a) =>
            a.courseId == course.id &&
            a.stimulusId == task.stimulusId &&
            (sessionId == null || a.sessionId != sessionId));
    final supports = {
      ...assistance,
      if (!first) 'retry',
      if (knownPassage && const {'independent', 'startCheck'}.contains(mode))
        'knownPassage'
    }.toList()
      ..sort();
    final captured = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(answers)) as Map,
    );
    final instant = _clock();
    final attempt = KompassAttempt(
      id: '${instant.microsecondsSinceEpoch}-${_sequence++}-${_attempts.length}',
      courseId: course.id,
      taskId: task.id,
      taskVersion: task.version,
      courseVersion: course.version,
      mode: mode,
      occurredAt: instant,
      competencyIds: task.competencyIds,
      assistance: supports,
      firstAttempt: first,
      elapsedSeconds: elapsedSeconds < 0 ? 0 : elapsedSeconds,
      parts: KompassGrader.assess(task, captured),
      taskKind: task.kind,
      stimulusId: task.stimulusId,
      sessionId: sessionId,
      courseFingerprint: course.fingerprint,
    );
    _attempts.add(attempt);
    await _persist();
    return attempt;
  }

  Future<void> reviewAttempt(
    String id,
    Map<String, double> scores, {
    String reviewer = 'self',
  }) async {
    if (!const {'self', 'parent', 'teacher'}.contains(reviewer))
      throw ArgumentError('Unknown reviewer');
    final index = _attempts.indexWhere((a) => a.id == id);
    if (index < 0) throw ArgumentError('Unknown attempt');
    final attempt = _attempts[index];
    for (final entry in scores.entries) {
      final part =
          attempt.parts.where((p) => p.partId == entry.key).firstOrNull;
      if (part == null ||
          !part.needsReview ||
          !entry.value.isFinite ||
          entry.value < 0 ||
          entry.value > part.maxPoints ||
          (part.creditSteps.isNotEmpty &&
              !part.creditSteps.contains(entry.value))) {
        throw ArgumentError(
          'Score must match an unreviewed part and its rubric steps',
        );
      }
    }
    _attempts[index] = attempt.withReview(
      attempt.parts
          .map(
            (p) => scores.containsKey(p.partId)
                ? p.reviewed(scores[p.partId]!, reviewer)
                : p,
          )
          .toList(),
      reviewer,
    );
    await _persist();
  }

  KompassAttempt? latestAttempt(String taskId) =>
      _attempts.reversed.where((a) => a.taskId == taskId).firstOrNull;

  KompassSkillStats statsFor(String skillId) {
    final relevant = _attempts
        .where((a) =>
            a.taskKind != 'instruction' && a.competencyIds.contains(skillId))
        .toList();
    // Recent, distinct first attempts allow recovery after earlier difficulties.
    // Repeated answers never displace fresh evidence in this window.
    final recent = relevant.reversed
        .where((a) => a.independent)
        .take(3)
        .map((a) => a.id)
        .toSet();
    var independent = 0, supported = 0, pending = 0;
    double earned = 0, possible = 0;
    final successfulTasks = <String>{},
        days = <String>{},
        contexts = <String>{};
    DateTime? lastIndependent, lastScoredAt;
    double? latestScore;
    var incompleteIndependent = false;
    for (final attempt in relevant) {
      final parts = attempt.parts
          .where((p) =>
              p.competencyIds.isEmpty || p.competencyIds.contains(skillId))
          .toList();
      if (parts.any((p) => p.needsReview)) pending++;
      final automatic = parts
          .where((p) => !p.needsReview && p.evaluation == 'automatic')
          .toList();
      if (automatic.any((p) => p.maxPoints > 0) &&
          (lastScoredAt == null ||
              !attempt.occurredAt.isBefore(lastScoredAt))) {
        lastScoredAt = attempt.occurredAt;
        latestScore = automatic.fold<double>(0, (sum, p) => sum + p.points!) /
            automatic.fold<double>(0, (sum, p) => sum + p.maxPoints);
      }
      if (attempt.independent && automatic.any((p) => p.maxPoints > 0))
        independent++;
      if (recent.contains(attempt.id)) {
        if (automatic.length != parts.length) {
          // Preserve exact subpart evidence without turning an unresolved or
          // rubric-reviewed sibling for the same skill into secure mastery.
          incompleteIndependent = true;
        } else if (automatic.any((p) => p.maxPoints > 0)) {
          if (lastIndependent == null ||
              attempt.occurredAt.isAfter(lastIndependent)) {
            lastIndependent = attempt.occurredAt;
          }
          final total =
              automatic.fold<double>(0, (sum, p) => sum + p.maxPoints);
          final score = automatic.fold<double>(0, (sum, p) => sum + p.points!);
          earned += score;
          possible += total;
          if (score / total >= 0.8) {
            successfulTasks.add(attempt.taskId);
            contexts.add(attempt.stimulusId ?? attempt.taskId);
            days.add(
                '${attempt.occurredAt.year}-${attempt.occurredAt.month}-${attempt.occurredAt.day}');
          }
        }
      }
      if (!attempt.independent ||
          parts.any((p) => p.evaluation.startsWith('rubric:'))) supported++;
    }
    final rate = possible == 0 ? null : earned / possible;
    final state = relevant.isEmpty
        ? 'unobserved'
        : independent == 0
            ? (supported > 0 ? 'supported' : 'learning')
            : rate == null ||
                    rate < 0.8 ||
                    (latestScore != null && latestScore < 0.8)
                ? 'learning'
                : !incompleteIndependent &&
                        successfulTasks.length >= 3 &&
                        days.length >= 2 &&
                        contexts.length >= 2 &&
                        lastIndependent != null &&
                        now.difference(lastIndependent).inDays <= 14
                    ? 'secure'
                    : 'developing';
    return KompassSkillStats(
        attempts: relevant.length,
        independentCount: independent,
        supportedCount: supported,
        pendingCount: pending,
        successRate: rate,
        state: state);
  }

  Future<void> clear() async {
    await _writes;
    _attempts.clear();
    _notTaught.clear();
    _unreadableRecords.clear();
    _activeSession = null;
    _recoveryRaw = null;
    await _prefs.remove(recoveryKey);
    await _persist();
  }
}
