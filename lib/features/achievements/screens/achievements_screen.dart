// lib/features/achievements/screens/achievements_screen.dart
//
// Shows the player which achievements they've unlocked from
// GameProvider._achievements. Read-only — unlocks happen in
// GameProvider._checkAchievements() on score/progress events.
//
// Strings are inline German on purpose: voc is a German learning app
// and these are surface labels, not the kind of UI chrome where a full
// English+German split pays off yet.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/space_theme.dart';
import '../../games/providers/game_provider.dart';

class _AchievementInfo {
  final String title;
  final String description;
  final String icon;
  const _AchievementInfo(this.title, this.description, this.icon);
}

const Map<String, _AchievementInfo> _kCatalog = {
  // Score-based
  'first_century': _AchievementInfo(
      'Erste 100', 'Erreiche 100 Punkte zum ersten Mal.', '💯'),
  'score_master': _AchievementInfo(
      'Punkte-Profi', 'Erreiche 500 Punkte.', '⭐'),
  'thousand_club': _AchievementInfo(
      'Club der 1000', 'Erreiche 1000 Punkte.', '🚀'),

  // Level-based
  'level_explorer': _AchievementInfo(
      'Level-Forscher', 'Erreiche Level 5 in einem Spiel.', '🌟'),
  'space_commander': _AchievementInfo(
      'Weltraum-Kommandant', 'Erreiche Level 10 in einem Spiel.', '👨‍🚀'),

  // Per-game (3 levels)
  'triangle_wizard': _AchievementInfo(
      'Wort-Schlange-Meister', 'Schaffe Level 3 in Wort-Schlange.', '🐍'),
  'bubble_popper': _AchievementInfo(
      'Sortier-Champion', 'Schaffe Level 3 in Wort-Sortierung.', '🏆'),
  'puzzle_solver': _AchievementInfo(
      'Wort-Finder', 'Schaffe Level 3 in Wortsuche.', '🔍'),
  'number_walls_pro': _AchievementInfo(
      'Wort-Baumeister', 'Schaffe Level 3 in Wort-Stückler.', '🧱'),
  'codebreaker_pro': _AchievementInfo(
      'Weltraum-Retter', 'Schaffe Level 3 in Weltraum-Wort-Rettung.', '🪐'),
  'master_builder': _AchievementInfo(
      'Wortbaumeister', 'Schaffe Level 3 im Wortbaumeister.', '🏗️'),
  'city_planner': _AchievementInfo(
      'Stadt-Planer', 'Schaffe Level 3 in Wort-Sortierer.', '🏙️'),
  'connection_expert': _AchievementInfo(
      'Galaxie-Experte', 'Schaffe Level 3 in Wort-Galaxie.', '🌌'),

  // Cross-game milestones
  'arithmetic_ace': _AchievementInfo(
      'Gedächtnis-Ass',
      'Erreiche Level 5 in Memory und Wortarten-Wirbel.',
      '🎯'),
  'all_rounder': _AchievementInfo(
      'Vielseitig',
      'Spiele mindestens vier verschiedene Spiele.',
      '🎮'),
};

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gp = context.watch<GameProvider>();
    final unlockedById = {
      for (final a in gp.achievements) a.id: a,
    };
    final allIds = _kCatalog.keys.toList();
    final unlockedCount =
        allIds.where(unlockedById.containsKey).length;
    final totalCount = allIds.length;

    return Scaffold(
      backgroundColor: SpaceTheme.deepSpace,
      appBar: AppBar(
        title: const Text('Erfolge'),
        backgroundColor: SpaceTheme.deepSpace,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _ProgressBanner(
                unlocked: unlockedCount, total: totalCount),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: allIds.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final id = allIds[i];
                final info = _kCatalog[id]!;
                final unlocked = unlockedById[id];
                return _AchievementTile(
                  info: info,
                  unlockedAt: unlocked?.unlockedAt,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  final int unlocked;
  final int total;
  const _ProgressBanner({required this.unlocked, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? unlocked / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SpaceTheme.nebulaPurple, SpaceTheme.spaceBlue],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$unlocked von $total Erfolgen freigeschaltet',
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(SpaceTheme.starYellow),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final _AchievementInfo info;
  final DateTime? unlockedAt;
  const _AchievementTile({required this.info, required this.unlockedAt});

  @override
  Widget build(BuildContext context) {
    final isUnlocked = unlockedAt != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUnlocked
            ? SpaceTheme.nebulaPurple.withValues(alpha: 0.35)
            : SpaceTheme.deepSpace,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnlocked
              ? SpaceTheme.starYellow.withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Opacity(
            opacity: isUnlocked ? 1.0 : 0.35,
            child: Text(info.icon, style: const TextStyle(fontSize: 32)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  style: SpaceTheme.titleStyle.copyWith(
                    fontSize: 15,
                    color: isUnlocked ? Colors.white : Colors.white54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.description,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    color: isUnlocked ? Colors.white70 : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
          if (isUnlocked)
            const Icon(Icons.check_circle,
                color: SpaceTheme.alienGreen, size: 24)
          else
            const Icon(Icons.lock_outline,
                color: Colors.white24, size: 22),
        ],
      ),
    );
  }
}
