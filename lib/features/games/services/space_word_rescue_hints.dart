import 'package:flutter/widgets.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../generated/l10n.dart';

String generateEducationalHint(
  BuildContext context,
  GermanWord word, {
  bool isPerfect = false,
  bool isCommonMistake = false,
  bool isIncorrect = false,
}) {
  final List<String> hints = [];
  late S s;
  try {
    s = S.of(context)!;
  } catch (e) {
    return '';
  }

  if (isPerfect) {
    switch (word.wordType) {
      case GermanWordType.substantiv:
        if (word.article != null) {
          hints.add('✓ ${word.article} ${word.word}');
        }
        if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
          hints.add('Plural: ${word.plural}');
        }
        if (word.genus != null) {
          hints.add('Genus: ${word.genus}');
        }
        break;
      case GermanWordType.verb:
          hints.add('Verb (Tun-Wort)');
          String? ichForm;
          String? duForm;
          String? erForm;

          if (word.inflectionData != null) {
            try {
              final conjugations = word.inflectionData!['analyses']?['verb']?['conjugation']?['Präsens'] as Map<String, dynamic>?;
              if (conjugations != null) {
                ichForm = conjugations['ich'] as String?;
                duForm = conjugations['du'] as String?;
                erForm = conjugations['er/sie/es'] as String?;
              }
            } catch (e) {
              debugPrint('Error parsing verb inflectionData for ${word.word}: $e');
            }
          }

          if (ichForm != null && duForm != null && erForm != null) {
            hints.add('z.B. ich $ichForm, du $duForm, er $erForm');
          }
          else if (word.forms != null && word.forms!.isNotEmpty) {
            hints.add('Formen: ${word.forms}');
          }
          break;
      case GermanWordType.adjektiv:
        hints.add('Adjektiv (Wie-Wort)');
        String? komparativ;
        String? superlativ;

        if (word.inflectionData != null) {
          try {
            final comparison = word.inflectionData!['analyses']?['adjektiv']?['comparison'] as Map<String, dynamic>?;
            if (comparison != null) {
              komparativ = comparison['Komparativ'] as String?;
              superlativ = comparison['Superlativ'] as String?;
            }
          } catch (e) {
              debugPrint('Error parsing adj inflectionData for ${word.word}: $e');
          }
        }

        if (komparativ != null && superlativ != null) {
          hints.add('Steigerung: $komparativ, $superlativ');
        }
        else if (word.forms != null && word.forms!.isNotEmpty) {
          hints.add('Steigerung: ${word.forms}');
        }
        break;
      default:
        break;
    }
  } else if (isCommonMistake) {
    hints.add('Häufiger Fehler! Merke dir: ${word.word}');
    if (word.graphematicVariants.isNotEmpty) {
      hints.add('Richtige Schreibweise: ${word.word}');
    }
  } else if (isIncorrect) {
    hints.add('Lerne: ${word.displayName}');
    final typeMap = {
      GermanWordType.substantiv: 'Nomen',
      GermanWordType.verb: 'Verb',
      GermanWordType.adjektiv: 'Adjektiv',
    };
    final type = typeMap[word.wordType];
    if (type != null) {
      hints.add(type);
    }
  }

  if (word.exampleSentences.isNotEmpty && hints.length < 2) {
    hints.add('Beispiel: ${word.exampleSentences.first}');
  }

  if (hints.isEmpty && isPerfect) {
    hints.add('✓ ${s.gameplayCorrect}!');
  }

  return hints.join(' • ');
}
