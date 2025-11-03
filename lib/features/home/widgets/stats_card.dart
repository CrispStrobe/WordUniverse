import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../generated/l10n.dart'; // Import S
import '../../games/providers/game_provider.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2A2D3E),
                Color(0xFF1E2235),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.analytics,
                    color: Color(0xFFFFD700), // starYellow
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context)!.progress,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildStatItem(
                context: context, // Pass context
                icon: Icons.star,
                label: S.of(context)!.score,
                value: gameProvider.score.toString(),
                color: const Color(0xFFFFD700), // starYellow
              ),
              const SizedBox(height: 12),
              _buildStatItem(
                context: context,
                icon: Icons.trending_up,
                label: S.of(context)!.level,
                value: gameProvider.level.toString(),
                color: const Color(0xFF06FFA5), // alienGreen
              ),
              const SizedBox(height: 12),
              _buildStatItem(
                context: context,
                icon: Icons.games,
                label: S.of(context)!.gamesPlayed,
                value: gameProvider.totalGamesPlayed.toString(),
                color: const Color(0xFFFF69B4), // cosmicPink
              ),
              const SizedBox(height: 12),
              _buildStatItem(
                context: context,
                icon: Icons.emoji_events,
                label: S.of(context)!.achievements,
                value: gameProvider.totalAchievements.toString(),
                color: const Color(0xFFFF6B35), // planetOrange
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem({
    required BuildContext context, // Receive context here
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}