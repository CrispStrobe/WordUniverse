// lib/features/games/widgets/spelling_strategy_badge.dart
//
// Shows the German orthographic strategy for a word (e.g. "Stammprinzip",
// "Merkwort") as a small info chip. Only rendered for DE words that have
// spellingStrategyPrimary set in their ApiEnrichment.

import 'package:flutter/material.dart';

import '../../../core/models/vocabulary_models.dart';

/// Map from pipeline key → human-readable German label + one-line explanation.
const _strategyInfo = {
  'grossschreibung': (
    label: 'Großschreibung',
    tip: 'Nomen und nominalisierte Wörter werden großgeschrieben.',
    icon: Icons.text_fields,
    color: Color(0xFF1565C0),
  ),
  'klangtreu': (
    label: 'Klangtreu',
    tip: 'Das Wort wird so geschrieben, wie es klingt (Lautprinzip).',
    icon: Icons.hearing,
    color: Color(0xFF2E7D32),
  ),
  'morphem': (
    label: 'Stammprinzip',
    tip: 'Verwandte Wörter behalten denselben Stamm: „Kind" → „Kinder".',
    icon: Icons.account_tree,
    color: Color(0xFF6A1B9A),
  ),
  'verwandt': (
    label: 'Verwandtschaft',
    tip: 'Die Schreibweise folgt aus einem verwandten Wort: „Hände" → „Hand".',
    icon: Icons.link,
    color: Color(0xFFE65100),
  ),
  'doppelkonsonant': (
    label: 'Doppelkonsonant',
    tip: 'Kurzer Vokal vor Doppelkonsonant: „rennen", „Wasser".',
    icon: Icons.format_bold,
    color: Color(0xFFC62828),
  ),
  'merkwort': (
    label: 'Merkwort',
    tip: 'Sonderfall — dieses Wort musst du dir merken.',
    icon: Icons.star,
    color: Color(0xFFF57F17),
  ),
};

/// Returns a small badge + tooltip explaining the spelling strategy for [word].
/// Returns [SizedBox.shrink] for EN words or words without strategy data.
class SpellingStrategyBadge extends StatelessWidget {
  final GermanWord word;
  const SpellingStrategyBadge({super.key, required this.word});

  @override
  Widget build(BuildContext context) {
    final strategy = word.apiEnrichment?.spellingStrategyPrimary;
    if (strategy == null) return const SizedBox.shrink();
    final info = _strategyInfo[strategy];
    if (info == null) return const SizedBox.shrink();

    return Tooltip(
      message: info.tip,
      preferBelow: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: info.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: info.color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(info.icon, color: info.color, size: 13),
            const SizedBox(width: 5),
            Text(
              info.label,
              style: TextStyle(
                color: info.color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.info_outline, color: info.color.withValues(alpha: 0.6), size: 11),
          ],
        ),
      ),
    );
  }
}

/// Returns the display label for a strategy key, or null if unknown.
String? spellingStrategyLabel(String? key) =>
    key != null ? _strategyInfo[key]?.label : null;
