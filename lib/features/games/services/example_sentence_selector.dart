// lib/features/games/services/example_sentence_selector.dart
//
// Pure helper for picking the best available example sentence for a word.
// Priority: grade-specific example → general exampleSentences → Gutenberg.
// Extracted from generateEducationalHint() for unit testing.

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';

const int kExampleMaxLen = 80;

/// Result of [pickExampleSentence].
class ExampleResult {
  final String text;
  /// "Beispiel" for grade/word examples, "Aus einem echten Buch" for Gutenberg.
  final String label;
  const ExampleResult({required this.text, required this.label});
}

/// Picks the best available example sentence for [word].
///
/// - [gradeLevel]: when provided, tries the matching grade-keyed sentence first.
/// - Returns null when no example is available from any source.
ExampleResult? pickExampleSentence(
  GermanWord word, {
  GradeLevel? gradeLevel,
}) {
  final api = word.apiEnrichment;
  String? text;
  String label = 'Beispiel';

  // 1. Grade-specific example from LLM-generated gradeExamples.
  if (gradeLevel != null && api?.gradeExamples != null) {
    final gradeKey = '${gradeLevel.index + 1}';
    final map = api!.gradeExamples!;
    final sents = map[gradeKey] ?? map.values.firstOrNull;
    text = sents?.firstOrNull;
  }

  // 2. General exampleSentences on the word.
  text ??= word.exampleSentences.firstOrNull;

  // 3. Gutenberg public-domain sentence as last resort.
  if (text == null) {
    final gut = api?.gutenbergExamples;
    if (gut != null && gut.isNotEmpty) {
      text = gut.first;
      label = 'Aus einem echten Buch';
    }
  }

  if (text == null || text.isEmpty) return null;
  // Truncate to exactly kExampleMaxLen: keep kExampleMaxLen-1 chars + '…'.
  final truncated =
      text.length > kExampleMaxLen ? '${text.substring(0, kExampleMaxLen - 1)}…' : text;
  return ExampleResult(text: truncated, label: label);
}
