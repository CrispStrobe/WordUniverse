import 'package:unorm_dart/unorm_dart.dart' as unicode;
import '../models/kompass_models.dart';

class KompassPartResult {
  final String partId;
  final double? points;
  final double maxPoints;
  final dynamic response;
  final List<String> competencyIds;
  final List<double> creditSteps;
  final String evaluation;
  final String prompt;
  final List<String> rubric;
  final String? feedback;
  const KompassPartResult({
    required this.partId,
    required this.points,
    required this.maxPoints,
    this.response,
    this.competencyIds = const [],
    this.creditSteps = const [],
    this.evaluation = 'automatic',
    this.prompt = '',
    this.rubric = const [],
    this.feedback,
  });
  bool get needsReview => points == null;
  Map<String, dynamic> toJson() => {
        'partId': partId,
        'points': points,
        'maxPoints': maxPoints,
        'response': response,
        'competencyIds': competencyIds,
        'creditSteps': creditSteps,
        'evaluation': evaluation,
        'prompt': prompt,
        'rubric': rubric,
        'feedback': feedback,
      };
  factory KompassPartResult.fromJson(Map<String, dynamic> json) =>
      KompassPartResult(
        partId: json['partId'] as String,
        points: (json['points'] as num?)?.toDouble(),
        maxPoints: (json['maxPoints'] as num).toDouble(),
        response: json['response'],
        competencyIds: (json['competencyIds'] as List? ?? []).cast<String>(),
        creditSteps: (json['creditSteps'] as List? ?? [])
            .map((v) => (v as num).toDouble())
            .toList(),
        evaluation: json['evaluation'] as String? ??
            (json['points'] == null ? 'pending' : 'automatic'),
        prompt: json['prompt'] as String? ?? '',
        rubric: (json['rubric'] as List? ?? []).cast<String>(),
        feedback: json['feedback'] as String?,
      );

  KompassPartResult reviewed(double value, String reviewer) =>
      KompassPartResult(
        partId: partId,
        points: value,
        maxPoints: maxPoints,
        response: response,
        competencyIds: competencyIds,
        creditSteps: creditSteps,
        evaluation: 'rubric:$reviewer',
        prompt: prompt,
        rubric: rubric,
        feedback: feedback,
      );
}

/// Exact authored policies only. Semantic short answers remain ungraded until
/// an explicit rubric review; fuzzy matching must not invent comprehension.
class KompassGrader {
  static List<KompassPartResult> assess(
    KompassTask task,
    Map<String, dynamic> answers,
  ) =>
      task.parts
          .map(
            (part) => assessPart(
              part,
              answers[part.id],
              competencyIds: part.competencyIds.isEmpty
                  ? task.competencyIds
                  : part.competencyIds,
            ),
          )
          .toList();

  static KompassPartResult assessPart(
    KompassPart part,
    dynamic response, {
    List<String> competencyIds = const [],
  }) {
    double? points;
    if (part.reviewRequired || part.type == 'review') {
      // An empty response is still an explicit review decision, not an
      // automatic fail whose feedback pretends to have understood the answer.
      points = null;
    } else {
      final expected = part.answers;
      var correct = false;
      switch (part.type) {
        case 'singleChoice':
          correct = response is String && expected.contains(response);
        case 'multiChoice':
          if (response is List) {
            final selected = response.map((v) => '$v').toSet();
            correct = response.length == selected.length &&
                selected.length == expected.toSet().length &&
                selected.containsAll(expected);
          }
        case 'order':
          if (response is List && response.length == expected.length) {
            correct = true;
            for (var i = 0; i < expected.length; i++) {
              if (response[i] != expected[i]) correct = false;
            }
          }
        case 'evidence':
          correct = response is String && part.evidenceIds.contains(response);
        case 'text':
          if (response is String && response.trim().isNotEmpty) {
            final actual = normalize(
              response,
              caseSensitive: part.caseSensitive,
            );
            correct = expected.any(
              (e) => normalize(e, caseSensitive: part.caseSensitive) == actual,
            );
          }
      }
      points = correct
          ? part.maxPoints
          : (part.reviewOnMismatch &&
                  response is String &&
                  response.trim().isNotEmpty
              ? null
              : 0);
    }
    return KompassPartResult(
      partId: part.id,
      points: points,
      maxPoints: part.maxPoints,
      response: response,
      competencyIds: competencyIds,
      creditSteps: part.creditSteps,
      evaluation: points == null ? 'pending' : 'automatic',
      prompt: part.prompt,
      rubric: part.rubric,
      feedback: part.feedback,
    );
  }

  static String normalize(String input, {required bool caseSensitive}) {
    // Canonical Unicode equivalence accepts decomposed umlauts, while keeping
    // ä/a, ß/ss, punctuation and capitalization distinct when the skill needs it.
    final text = unicode.nfc(input).trim().replaceAll(RegExp(r'\s+'), ' ');
    return caseSensitive ? text : text.toLowerCase();
  }
}
