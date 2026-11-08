import 'dart:convert';

/// Course identifiers are strings and content is versioned independently of
/// the app's historical grade/skill enums (which are persisted by index).
class KompassCourse {
  final String id;
  final int version;
  final String locale;
  final List<KompassCompetency> competencies;
  final Map<String, KompassStimulus> stimuli;
  final List<KompassTask> tasks;
  final List<KompassTest> tests;
  final Map<String, dynamic> metadata;

  KompassCourse.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      version = (json['version'] as num).toInt(),
      locale = json['locale'] as String? ?? 'de-DE',
      competencies = _maps(
        json['competencies'],
      ).map(KompassCompetency.fromJson).toList(growable: false),
      stimuli = {
        for (final s in _maps(json['stimuli']))
          s['id'] as String: KompassStimulus.fromJson(s),
      },
      tasks = _maps(
        json['tasks'],
      ).map(KompassTask.fromJson).toList(growable: false),
      tests = _maps(
        json['tests'],
      ).map(KompassTest.fromJson).toList(growable: false),
      metadata = Map.unmodifiable(json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported Kompass course schema');
    }
    _validate();
  }

  factory KompassCourse.decode(String source) =>
      KompassCourse.fromJson(jsonDecode(source) as Map<String, dynamic>);

  KompassTask? taskById(String id) =>
      tasks.where((t) => t.id == id).firstOrNull;
  KompassStimulus? stimulusById(String? id) => stimuli[id];
  KompassCompetency? competencyById(String id) =>
      competencies.where((c) => c.id == id).firstOrNull;

  void _validate() {
    final ids = <String>{};
    final skills = competencies.map((c) => c.id).toSet();
    if (skills.length != competencies.length) {
      throw const FormatException('Duplicate competency ID');
    }
    for (final task in tasks) {
      if (!ids.add(task.id)) throw FormatException('Duplicate task ${task.id}');
      if (task.competencyIds.isEmpty ||
          task.competencyIds.any((id) => !skills.contains(id))) {
        throw FormatException('Unknown competency on ${task.id}');
      }
      if (task.stimulusId != null && !stimuli.containsKey(task.stimulusId)) {
        throw FormatException('Missing passage for ${task.id}');
      }
      if (task.parts.isEmpty ||
          task.parts.map((p) => p.id).toSet().length != task.parts.length) {
        throw FormatException('Invalid response parts on ${task.id}');
      }
      if ((task.parts.fold<double>(0, (sum, p) => sum + p.maxPoints) -
                  task.points)
              .abs() >
          0.000001) {
        throw FormatException('Point total differs on ${task.id}');
      }
      for (final part in task.parts) {
        if (!const {
              'singleChoice',
              'multiChoice',
              'text',
              'evidence',
              'order',
              'review',
            }.contains(part.type) ||
            part.maxPoints < 0) {
          throw FormatException('Invalid part ${task.id}/${part.id}');
        }
        if (!part.reviewRequired &&
            part.type != 'review' &&
            part.answers.isEmpty &&
            part.evidenceIds.isEmpty) {
          throw FormatException('Missing answer policy ${task.id}/${part.id}');
        }
        if (part.type == 'evidence') {
          final anchors =
              stimulusById(task.stimulusId)?.lines.map((l) => l.id).toSet() ??
              <String>{};
          if (part.evidenceIds.any((id) => !anchors.contains(id))) {
            throw FormatException(
              'Invalid evidence anchor ${task.id}/${part.id}',
            );
          }
        }
      }
    }
    for (final test in tests) {
      if (test.taskIds.any((id) => !ids.contains(id))) {
        throw FormatException('Missing task in ${test.id}');
      }
    }
  }
}

class KompassCompetency {
  final String id, domain, title, goal;
  final String? easier,
      harder,
      commonErrors,
      observation,
      evidence,
      curriculumUrl;
  final List<String> prerequisites;
  final Map<String, dynamic> metadata;
  KompassCompetency.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      domain = json['domain'] as String? ?? _domain(json['bereich'] as String?),
      title = (json['title'] ?? json['teilkompetenz'] ?? json['id']) as String,
      goal = (json['goal'] ?? json['lernziel'] ?? '') as String,
      easier = (json['easier'] ?? json['leichter']) as String?,
      harder = (json['harder'] ?? json['anspruchsvoller']) as String?,
      commonErrors = (json['commonErrors'] ?? json['fehler']) as String?,
      observation = (json['observation'] ?? json['profilindikator']) as String?,
      evidence = (json['evidence'] ?? json['evidenz']) as String?,
      curriculumUrl = (json['curriculumUrl'] ?? json['bp_url']) as String?,
      prerequisites = _strings(json['prerequisites']),
      metadata = Map.unmodifiable(json);
}

class KompassLine {
  final String id, text, label;
  KompassLine.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      text = json['text'] as String,
      label = '${json['label'] ?? ''}';
}

class KompassStimulus {
  final String id, title;
  final List<KompassLine> lines;
  final List<Map<String, dynamic>> blocks;
  final int readingSeconds;
  KompassStimulus.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String? ?? '',
      lines = _maps(
        json['lines'],
      ).map(KompassLine.fromJson).toList(growable: false),
      blocks = _maps(json['blocks']),
      readingSeconds = (json['readingSeconds'] as num?)?.toInt() ?? 300;
}

class KompassOption {
  final String id, text;
  KompassOption.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      text = json['text'] as String;
}

class KompassPart {
  final String id, type, prompt;
  final List<KompassOption> options;
  final List<String> answers, evidenceIds, rubric, competencyIds;
  final double maxPoints;
  final bool caseSensitive, reviewRequired, reviewOnMismatch;
  final String? feedback;
  final Map<String, dynamic> metadata;
  KompassPart.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      type = json['type'] as String,
      prompt = json['prompt'] as String? ?? '',
      options = _maps(
        json['options'],
      ).map(KompassOption.fromJson).toList(growable: false),
      answers = _strings(json['answers']),
      evidenceIds = _strings(json['evidenceIds']),
      rubric = _strings(json['rubric']),
      competencyIds = _strings(json['competencyIds']),
      maxPoints = (json['maxPoints'] as num).toDouble(),
      caseSensitive = json['caseSensitive'] as bool? ?? true,
      reviewRequired = json['reviewRequired'] as bool? ?? false,
      reviewOnMismatch = json['reviewOnMismatch'] as bool? ?? false,
      feedback = json['feedback'] as String?,
      metadata = Map.unmodifiable(json);
  List<double> get creditSteps => metadata['creditSteps'] is List
      ? (metadata['creditSteps'] as List)
            .map((v) => (v as num).toDouble())
            .toList()
      : [0, maxPoints];
}

class KompassTask {
  final String id, title, domain, kind, reviewStatus;
  final int version, estimatedSeconds;
  final double points;
  final String? stimulusId;
  final List<String> competencyIds, hints, misconceptionTags;
  final List<Map<String, dynamic>> blocks;
  final List<KompassPart> parts;
  final Map<String, dynamic> metadata;
  KompassTask.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      domain = json['domain'] as String,
      kind = json['kind'] as String? ?? 'practice',
      reviewStatus = json['reviewStatus'] as String? ?? 'draft',
      version = (json['version'] as num?)?.toInt() ?? 1,
      points = (json['points'] as num).toDouble(),
      estimatedSeconds = (json['estimatedSeconds'] as num?)?.toInt() ?? 60,
      stimulusId = json['stimulusId'] as String?,
      competencyIds = _strings(json['competencyIds']),
      hints = _strings(json['hints']),
      misconceptionTags = _strings(json['misconceptionTags']),
      blocks = _maps(json['blocks']),
      parts = _maps(
        json['parts'],
      ).map(KompassPart.fromJson).toList(growable: false),
      metadata = Map.unmodifiable(json);
}

class KompassTest {
  final String id, title, printUrl, printAsset, solutionsAsset;
  final List<String> taskIds;
  final Map<String, dynamic> timing;
  final List<Map<String, dynamic>> sections;
  KompassTest.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      printUrl = json['printUrl'] as String? ?? '',
      printAsset = json['printAsset'] as String? ?? '',
      solutionsAsset = json['solutionsAsset'] as String? ?? '',
      taskIds = _strings(json['taskIds']),
      timing = Map<String, dynamic>.from(json['timing'] as Map? ?? {}),
      sections = _maps(json['sections']);
  int get totalSeconds => (timing['totalSeconds'] as num?)?.toInt() ?? 2700;
}

List<Map<String, dynamic>> _maps(dynamic value) => (value as List? ?? const [])
    .map((v) => Map<String, dynamic>.from(v as Map))
    .toList(growable: false);
List<String> _strings(dynamic value) =>
    (value as List? ?? const []).map((v) => '$v').toList(growable: false);
String _domain(String? value) => switch (value) {
  'Lesen' => 'reading',
  'Rechtschreibung' => 'spelling',
  'Sprachgebrauch' => 'language',
  _ => 'instructions',
};
