// lib/features/achievements/screens/achievements_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../../games/providers/game_provider.dart';
import '../../games/widgets/space_background.dart';

// Helper class for UI data
class AchievementUIData {
  final String title;
  final String description;
  final String icon;

  AchievementUIData({
    required this.title,
    required this.description,
    required this.icon,
  });
}

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _sparkleController;
  late List<Animation<Offset>> _achievementAnimations;
  late Animation<double> _sparkleAnimation;

  // FIX: This list now contains all *possible* achievement IDs
  final List<String> _allAchievementIds = [
    'first_century',
    'score_master',
    'thousand_club',
    'level_explorer',
    'space_commander',
    'word_rescuer', // <-- New
    'all_rounder',
    'speed_demon',
    'perfectionist',
  ];

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _sparkleController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _sparkleAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(_sparkleController);

    // Use the length of the new ID list
    _achievementAnimations = List.generate(_allAchievementIds.length, (index) {
      return Tween<Offset>(
        begin: Offset(1.0 + (index * 0.1), 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Interval(
          index * 0.05,
          (0.5 + (index * 0.05)).clamp(0.0, 1.0),
          curve: Curves.easeOutBack,
        ),
      ));
    });

    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }
  
  // FIX: This helper method is now updated to only handle valid, non-math achievements
  AchievementUIData _getAchievementUIData(BuildContext context, String id) {
    final s = S.of(context)!; // Helper for brevity
    switch (id) {
      case 'first_century':
        return AchievementUIData(title: s.achievementFirstCenturyTitle, description: s.achievementFirstCenturyDesc, icon: '💯');
      case 'score_master':
        return AchievementUIData(title: s.achievementScoreMasterTitle, description: s.achievementScoreMasterDesc, icon: '⭐');
      case 'thousand_club':
        return AchievementUIData(title: s.achievementThousandClubTitle, description: s.achievementThousandClubDesc, icon: '🚀');
      case 'level_explorer':
        return AchievementUIData(title: s.achievementLevelExplorerTitle, description: s.achievementLevelExplorerDesc, icon: '🌟');
      case 'space_commander':
        return AchievementUIData(title: s.achievementSpaceCommanderTitle, description: s.achievementSpaceCommanderDesc, icon: '👨‍🚀');
      case 'word_rescuer':
        return AchievementUIData(title: s.achievementWordRescuerTitle, description: s.achievementWordRescuerDesc, icon: '🛰️');
      case 'all_rounder':
        return AchievementUIData(title: s.achievementAllRounderTitle, description: s.achievementAllRounderDesc, icon: '🎯');
      case 'speed_demon':
        return AchievementUIData(title: s.achievementSpeedDemonTitle, description: s.achievementSpeedDemonDesc, icon: '⚡');
      case 'perfectionist':
        return AchievementUIData(title: s.achievementPerfectionistTitle, description: s.achievementPerfectionistDesc, icon: '💎');
      default:
        return AchievementUIData(title: 'Unknown', description: 'Error', icon: '❓');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildStats(),
              Expanded(
                child: _buildAchievementsList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E2235),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 28,
            ),
            style: IconButton.styleFrom(
              backgroundColor: SpaceTheme.deepSpace.withOpacity(0.8),
              padding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context)!.achievements,
                  style: SpaceTheme.headlineStyle.copyWith(fontSize: 32),
                ),
                Text(
                  S.of(context)!.spaceExplorerProgress,
                  style: SpaceTheme.bodyStyle.copyWith(
                    color: SpaceTheme.starYellow,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _sparkleAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _sparkleAnimation.value,
                child: const Icon(
                  Icons.emoji_events,
                  color: SpaceTheme.starYellow,
                  size: 40,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        final totalAchievements = _allAchievementIds.length;
        final unlockedAchievements = gameProvider.totalAchievements;
        final completionPercentage = totalAchievements > 0
            ? (unlockedAchievements / totalAchievements * 100).round()
            : 0;

        return Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: SpaceTheme.cardDecoration,
          child: Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.star,
                  label: S.of(context)!.unlocked,
                  value: '$unlockedAchievements / $totalAchievements',
                  color: SpaceTheme.starYellow,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.2),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.percent,
                  label: S.of(context)!.complete,
                  value: '$completionPercentage%',
                  color: SpaceTheme.alienGreen,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.2),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.trending_up,
                  label: S.of(context)!.progress,
                  value: _getProgressLevel(unlockedAchievements),
                  color: SpaceTheme.cosmicPink,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: SpaceTheme.titleStyle.copyWith(
            color: color,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementsList() {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        final unlockedIds = gameProvider.achievements.map((a) => a.id).toSet();

        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _getCrossAxisCount(context),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: _allAchievementIds.length,
          itemBuilder: (context, index) {
            final achievementId = _allAchievementIds[index];
            final isUnlocked = unlockedIds.contains(achievementId);
            final achievementUiData = _getAchievementUIData(context, achievementId);

            return SlideTransition(
              position: _achievementAnimations[index],
              child: AchievementCard(
                uiData: achievementUiData,
                isUnlocked: isUnlocked,
                sparkleAnimation: _sparkleAnimation,
              ),
            );
          },
        );
      },
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 4;
    if (width > 800) return 3;
    return 2;
  }

  String _getProgressLevel(int achievementCount) {
    final s = S.of(context)!;
    // FIX: Adjusted counts for fewer achievements
    if (achievementCount < 2) return s.rankRookie;
    if (achievementCount < 4) return s.rankExplorer;
    if (achievementCount < 6) return s.rankVeteran;
    if (achievementCount < 8) return s.rankExpert;
    return s.rankLegend;
  }
}

class AchievementCard extends StatefulWidget {
  final AchievementUIData uiData;
  final bool isUnlocked;
  final Animation<double> sparkleAnimation;

  const AchievementCard({
    super.key,
    required this.uiData,
    required this.isUnlocked,
    required this.sparkleAnimation,
  });

  @override
  State<AchievementCard> createState() => _AchievementCardState();
}

class _AchievementCardState extends State<AchievementCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTap: widget.isUnlocked ? _showAchievementDetails : null,
            onTapDown: (_) => _hoverController.forward(),
            onTapUp: (_) => _hoverController.reverse(),
            onTapCancel: () => _hoverController.reverse(),
            child: Container(
              decoration: BoxDecoration(
                gradient: widget.isUnlocked
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          SpaceTheme.starYellow,
                          SpaceTheme.planetOrange,
                        ],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          SpaceTheme.deepSpace.withOpacity(0.8),
                          SpaceTheme.nebulaPurple.withOpacity(0.6),
                        ],
                      ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: widget.isUnlocked
                    ? [
                        BoxShadow(
                          color: SpaceTheme.starYellow.withOpacity(0.5),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Stack(
                children: [
                  if (widget.isUnlocked)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: widget.sparkleAnimation,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: SparklePainter(
                              animation: widget.sparkleAnimation.value,
                            ),
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: widget.isUnlocked
                                ? Colors.white.withOpacity(0.2)
                                : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Center(
                            child: Text(
                              widget.uiData.icon,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.uiData.title,
                          style: SpaceTheme.titleStyle.copyWith(
                            fontSize: 16,
                            color: widget.isUnlocked
                                ? Colors.white
                                : Colors.white60,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.uiData.description,
                          style: SpaceTheme.bodyStyle.copyWith(
                            fontSize: 12,
                            color: widget.isUnlocked
                                ? Colors.white
                                : Colors.white54,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isUnlocked
                                ? SpaceTheme.alienGreen
                                // FIX: Use a more subtle color for the locked badge
                                : Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.isUnlocked
                                ? S.of(context)!.unlockedStatus
                                : S.of(context)!.lockedStatus,
                            style: TextStyle(
                              color: widget.isUnlocked
                                  // FIX: Make text readable on green
                                  ? SpaceTheme.deepSpace
                                  : Colors.white60,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.isUnlocked)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.lock,
                            color: Colors.white60,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAchievementDetails() {
    showDialog(
      context: context,
      builder: (context) => AchievementDialog(
        uiData: widget.uiData,
      ),
    );
  }
}

class AchievementDialog extends StatelessWidget {
  final AchievementUIData uiData;

  const AchievementDialog({
    super.key,
    required this.uiData,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: SpaceTheme.cardDecoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: SpaceTheme.starGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  uiData.icon,
                  style: const TextStyle(fontSize: 40),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              uiData.title,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              uiData.description,
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: SpaceTheme.alienGreen,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                S.of(context)!.achievementUnlocked,
                style: const TextStyle(
                  // FIX: Make text readable on green
                  color: SpaceTheme.deepSpace,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: SpaceTheme.primaryButtonStyle,
              child: Text(S.of(context)!.continueExploring),
            ),
          ],
        ),
      ),
    );
  }
}

class SparklePainter extends CustomPainter {
  final double animation;

  SparklePainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    final random = math.Random(42);

    for (int i = 0; i < 8; i++) {
      final angle = (i * 2 * math.pi / 8) + animation;
      final radius = (size.width / 4) + math.sin(animation + i) * (size.width / 10);

      final x = size.width / 2 + math.cos(angle) * radius;
      final y = size.height / 2 + math.sin(angle) * radius;

      canvas.drawCircle(
        Offset(x, y),
        2 + math.sin(animation * 2 + i) * 1,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SparklePainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}