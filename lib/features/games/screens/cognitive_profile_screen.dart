// lib/features/games/screens/cognitive_profile_screen.dart
//
// Visual breakdown of the player's mastery across language skill
// categories. Reads from CognitiveProfileService.snapshot.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/services/cognitive_profile_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';

class CognitiveProfileScreen extends StatelessWidget {
  const CognitiveProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final profile = context.watch<CognitiveProfileService>();
    final snapshot = profile.snapshot;
    final totalAttempts = profile.totalAttempts;

    // Group by LanguageCategory for nicer display.
    final byCategory = <LanguageCategory, List<MapEntry<SkillCategory, Map<int, SkillStats>>>>{};
    for (final entry in snapshot.entries) {
      byCategory.putIfAbsent(entry.key.category, () => []).add(entry);
    }

    return Scaffold(
      backgroundColor: SpaceTheme.deepSpace,
      appBar: AppBar(
        title: Text(s.cognitiveProfileTitle),
        backgroundColor: SpaceTheme.deepSpace,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (totalAttempts == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  s.cognitiveProfileEmpty,
                  textAlign: TextAlign.center,
                  style: SpaceTheme.bodyStyle,
                ),
              ),
            )
          else ...[
            Text(
              s.cognitiveProfileAttempts(totalAttempts, snapshot.length),
              style: SpaceTheme.bodyStyle
                  .copyWith(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            for (final cat in byCategory.entries) ...[
              Text(
                _categoryLabel(s, cat.key),
                style: SpaceTheme.titleStyle.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 8),
              for (final entry in cat.value)
                _SkillCard(skill: entry.key, stats: entry.value),
              const SizedBox(height: 16),
            ],
          ],
        ],
      ),
    );
  }

  String _categoryLabel(S s, LanguageCategory c) {
    switch (c) {
      case LanguageCategory.rechtschreibung:
        return s.categorySpelling;
      case LanguageCategory.grammatik:
        return s.categoryGrammar;
      case LanguageCategory.wortschatz:
        return s.categoryVocabulary;
      case LanguageCategory.textverstaendnis:
        return s.categoryTextComprehension;
      case LanguageCategory.ausdruck:
        return s.categoryExpression;
    }
  }
}

class _SkillCard extends StatelessWidget {
  final SkillCategory skill;
  final Map<int, SkillStats> stats;
  const _SkillCard({required this.skill, required this.stats});

  @override
  Widget build(BuildContext context) {
    final attempts =
        stats.values.fold<int>(0, (sum, s) => sum + s.attempts);
    final successes =
        stats.values.fold<int>(0, (sum, s) => sum + s.successes);
    final ratio = attempts > 0 ? successes / attempts : 0.0;
    final difficulties = stats.keys.toList()..sort();

    return Card(
      color: SpaceTheme.nebulaPurple.withValues(alpha: 0.3),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(skill.icon, color: skill.color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    skill.name,
                    style: SpaceTheme.titleStyle.copyWith(fontSize: 15),
                  ),
                ),
                Text(
                  '${(ratio * 100).round()}%',
                  style: SpaceTheme.titleStyle.copyWith(
                    fontSize: 16,
                    color: _colorForRatio(ratio),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              valueColor:
                  AlwaysStoppedAnimation<Color>(_colorForRatio(ratio)),
              minHeight: 5,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final d in difficulties)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: SpaceTheme.deepSpace,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      'K$d: ${stats[d]!.successes}/${stats[d]!.attempts}',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForRatio(double r) {
    if (r >= 0.7) return SpaceTheme.alienGreen;
    if (r >= 0.4) return SpaceTheme.starYellow;
    return SpaceTheme.rocketRed;
  }
}
