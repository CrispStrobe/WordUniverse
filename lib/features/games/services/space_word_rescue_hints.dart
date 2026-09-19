import 'package:flutter/widgets.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../generated/l10n.dart';
import 'example_sentence_selector.dart';

String generateEducationalHint(
  BuildContext context,
  GermanWord word, {
  bool isPerfect = false,
  bool isCommonMistake = false,
  bool isIncorrect = false,
  GradeLevel? gradeLevel,
}) {
  final List<String> hints = [];
  late S s;
  try {
    s = S.of(context)!;
  } catch (e) {
    return '';
  }

  final api = word.apiEnrichment;

  if (isPerfect) {
    switch (word.wordType) {
      case GermanWordType.substantiv:
        if (word.article != null && word.article!.isNotEmpty) {
          hints.add('✓ ${word.article} ${word.word}');
        }
        if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
          hints.add('Plural: ${word.plural}');
        }
        // Try new inflectionsPattern first, fall back to old inflectionData
        final pattern = api?.inflectionsPattern;
        if (pattern != null) {
          final plural = pattern['plural'];
          if (plural is String && plural.isNotEmpty && plural != '-' &&
              (word.plural == null || word.plural!.isEmpty)) {
            hints.add('Plural: $plural');
          }
        }
        if (word.genus != null) hints.add('Genus: ${word.genus}');
        break;

      case GermanWordType.verb:
        hints.add('Verb (Tun-Wort)');
        String? ichForm;
        String? duForm;
        String? erForm;

        // Prefer new inflectionsPattern
        final pattern = api?.inflectionsPattern;
        if (pattern != null) {
          try {
            final pres = pattern['conjugation']?['Präsens'] as Map?;
            ichForm = pres?['ich'] as String?;
            duForm = pres?['du'] as String?;
            erForm = (pres?['er/sie/es'] ?? pres?['er']) as String?;
          } catch (_) {}
        }
        // Fall back to legacy inflectionData
        if (ichForm == null && word.inflectionData != null) {
          try {
            final conj = word.inflectionData!['analyses']?['verb']
                ?['conjugation']?['Präsens'] as Map<String, dynamic>?;
            ichForm = conj?['ich'] as String?;
            duForm = conj?['du'] as String?;
            erForm = conj?['er/sie/es'] as String?;
          } catch (_) {}
        }

        if (ichForm != null && duForm != null && erForm != null) {
          hints.add('z.B. ich $ichForm, du $duForm, er $erForm');
        } else if (word.forms != null && word.forms!.isNotEmpty) {
          hints.add('Formen: ${word.forms}');
        }
        break;

      case GermanWordType.adjektiv:
        hints.add('Adjektiv (Wie-Wort)');
        String? komp;
        String? sup;

        final pattern = api?.inflectionsPattern;
        if (pattern != null) {
          komp = pattern['comparative'] as String?;
          sup = pattern['superlative'] as String?;
        }
        if (komp == null && word.inflectionData != null) {
          try {
            final cmp = word.inflectionData!['analyses']?['adjektiv']
                ?['comparison'] as Map<String, dynamic>?;
            komp = cmp?['Komparativ'] as String?;
            sup = cmp?['Superlativ'] as String?;
          } catch (_) {}
        }

        if (komp != null && sup != null) {
          hints.add('Steigerung: $komp, $sup');
        } else if (komp != null) {
          hints.add('Komparativ: $komp');
        } else if (word.forms != null && word.forms!.isNotEmpty) {
          hints.add('Steigerung: ${word.forms}');
        }
        break;

      default:
        break;
    }

    // Add definition if we have room
    final def = word.displayDefinitions.firstOrNull;
    if (def != null && def.isNotEmpty && hints.length < 2) {
      final truncated = def.length > 70 ? '${def.substring(0, 67)}…' : def;
      hints.add('"$truncated"');
    }

    // Add synonyms as bonus enrichment
    if ((api?.synonyms.isNotEmpty ?? false) && hints.length < 3) {
      hints.add('= ${api!.synonyms.take(2).join(', ')}');
    }

  } else if (isCommonMistake) {
    hints.add(s.rescueHintCommonMistake(word.word));
    // Show actual misspellings so learner knows what to avoid
    final mistakes = word.commonMistakes ?? api?.commonLearnerErrors ?? [];
    if (mistakes.isNotEmpty) {
      final shown = mistakes.take(2).join(', ');
      hints.add(s.rescueHintNot(shown));
    } else if (word.graphematicVariants.isNotEmpty) {
      hints.add(s.rescueHintCorrectSpelling(word.word));
    }

  } else if (isIncorrect) {
    hints.add(s.rescueHintLearn(word.displayName));
    final typeMap = {
      GermanWordType.substantiv: 'Nomen',
      GermanWordType.verb: 'Verb',
      GermanWordType.adjektiv: 'Adjektiv',
    };
    final type = typeMap[word.wordType];
    if (type != null) hints.add(type);

    // Add definition to help the learner remember
    final def = word.displayDefinitions.firstOrNull;
    if (def != null && def.isNotEmpty) {
      final truncated = def.length > 70 ? '${def.substring(0, 67)}…' : def;
      hints.add('"$truncated"');
    }
  }

  // Grade-appropriate example sentence, with Gutenberg as fallback.
  if (hints.length < 3) {
    final ex = pickExampleSentence(word, gradeLevel: gradeLevel);
    if (ex != null) hints.add('${ex.label}: ${ex.text}');
  }

  if (hints.isEmpty && isPerfect) {
    hints.add('✓ ${s.gameplayCorrect}!');
  }

  return hints.join(' • ');
}
