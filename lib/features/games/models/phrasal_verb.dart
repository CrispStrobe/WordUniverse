// lib/features/games/models/phrasal_verb.dart
//
// Model for the EN `phrasal_verbs` table (built by
// pipeline/voc-en/add_phrasal_verbs_en.py). Source: Wiktionary CC-BY-SA 4.0
// phrasal-verb categories + LLM grade-leveled example sentences.

import 'dart:convert';

class PhrasalVerb {
  final String phrasal; // e.g. "give up"
  final String baseVerb; // e.g. "give"
  final String particle; // e.g. "up"
  final String meaning; // short kid-friendly definition
  final List<String> senses; // up to 3 Wiktionary glosses
  final List<String> distractors; // wrong particles for the MCQ
  final Map<String, List<String>> examples; // grade ("1".."6") -> sentences
  final List<String> wiktionaryExamples; // CC-BY-SA fallback sentences
  final int gradeBand; // 3-6
  final double baseZipf;

  const PhrasalVerb({
    required this.phrasal,
    required this.baseVerb,
    required this.particle,
    required this.meaning,
    required this.senses,
    required this.distractors,
    required this.examples,
    required this.wiktionaryExamples,
    required this.gradeBand,
    required this.baseZipf,
  });

  factory PhrasalVerb.fromRow(Map<String, dynamic> row) {
    Map<String, List<String>> parseExamples(dynamic raw) {
      if (raw == null) return const {};
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry(
            k.toString(),
            (v as List?)?.map((e) => e.toString()).toList() ?? const [],
          ));
    }

    List<String> parseList(dynamic raw) {
      if (raw == null) return const [];
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList();
    }

    return PhrasalVerb(
      phrasal: (row['phrasal'] ?? '').toString(),
      baseVerb: (row['base_verb'] ?? '').toString(),
      particle: (row['particle'] ?? '').toString(),
      meaning: (row['meaning'] ?? '').toString(),
      senses: parseList(row['senses_json']),
      distractors: parseList(row['distractors_json']),
      examples: parseExamples(row['examples_json']),
      wiktionaryExamples: parseList(row['wiktionary_examples_json']),
      gradeBand: (row['grade_band'] as num?)?.toInt() ?? 3,
      baseZipf: (row['base_zipf'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
