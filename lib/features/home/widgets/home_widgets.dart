import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../../games/providers/game_provider.dart';

// Animated Logo Widget
class AnimatedLogo extends StatefulWidget {
  const AnimatedLogo({super.key});

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with TickerProviderStateMixin {
  
  late AnimationController _rotationController;
  late AnimationController _scaleController;
  late AnimationController _glowController;
  
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _rotationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    
    _scaleController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    
    _glowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(_rotationController);
    
    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));
    
    _glowAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));
  }
  
  @override
  void dispose() {
    _rotationController.dispose();
    _scaleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _rotationAnimation,
        _scaleAnimation,
        _glowAnimation,
      ]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  SpaceTheme.starYellow.withValues(alpha: _glowAnimation.value),
                  SpaceTheme.planetOrange.withValues(alpha: _glowAnimation.value * 0.8),
                  SpaceTheme.deepSpace.withValues(alpha: 0.3),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: SpaceTheme.starYellow.withValues(alpha: _glowAnimation.value * 0.5),
                  blurRadius: 30,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rotating rings
                Transform.rotate(
                  angle: _rotationAnimation.value,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SpaceTheme.alienGreen.withValues(alpha: 0.6),
                        width: 3,
                      ),
                    ),
                  ),
                ),
                
                Transform.rotate(
                  angle: -_rotationAnimation.value * 0.7,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SpaceTheme.cosmicPink.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                
                // Center rocket icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SpaceTheme.starGradient,
                  ),
                  child: const Icon(
                    Icons.rocket_launch,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                
                // App title
                Positioned(
                  bottom: -10,
                  child: Text(
                    S.of(context)!.appTitle,
                    style: SpaceTheme.titleStyle.copyWith(
                      fontSize: 16,
                      shadows: [
                        Shadow(
                          color: SpaceTheme.starYellow.withValues(alpha: 0.8),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Grade Selector Widget
class GradeSelector extends StatelessWidget {
  const GradeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: SpaceTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.school,
                    color: SpaceTheme.starYellow,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context)!.chooseGrade,
                    style: SpaceTheme.titleStyle.copyWith(fontSize: 18),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [3, 4, 5, 6].map((grade) {
                  final isSelected = gameProvider.grade == grade;
                  
                  return GestureDetector(
                    onTap: () => gameProvider.setGrade(grade),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? SpaceTheme.starGradient
                            : LinearGradient(
                                colors: [
                                  SpaceTheme.deepSpace,
                                  SpaceTheme.nebulaPurple,
                                ],
                              ),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isSelected
                              ? SpaceTheme.starYellow
                              : SpaceTheme.moonSilver.withValues(alpha: 0.3),
                          width: 2,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: SpaceTheme.starYellow.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          grade.toString(),
                          style: SpaceTheme.headlineStyle.copyWith(
                            fontSize: 24,
                            color: isSelected ? Colors.white : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              
              const SizedBox(height: 12),
              
              Text(
                _getGradeDescription(context, gameProvider.grade),
                style: SpaceTheme.bodyStyle.copyWith(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
  
  String _getGradeDescription(BuildContext context, int grade) {
    switch (grade) {
      case 3:
        return S.of(context)!.grade3Desc;
      case 4:
        return S.of(context)!.grade4Desc;
      case 5:
        return S.of(context)!.grade5Desc;
      case 6:
        return S.of(context)!.grade6Desc;
      default:
        return '';
    }
  }
}

// Stats Card Widget
class StatsCard extends StatefulWidget {
  const StatsCard({super.key});

  @override
  State<StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<StatsCard>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: SpaceTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.analytics,
                    color: SpaceTheme.starYellow,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context)!.progress,
                    style: SpaceTheme.titleStyle.copyWith(fontSize: 18),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // Score
              _buildStatItem(
                icon: Icons.star,
                label: S.of(context)!.score,
                value: gameProvider.score.toString(),
                color: SpaceTheme.starYellow,
              ),
              
              const SizedBox(height: 12),
              
              // Level
              _buildStatItem(
                icon: Icons.trending_up,
                label: S.of(context)!.level,
                value: gameProvider.level.toString(),
                color: SpaceTheme.alienGreen,
              ),
              
              const SizedBox(height: 12),
              
              // Games played
              _buildStatItem(
                icon: Icons.games,
                label: S.of(context)!.gamesPlayed,
                value: gameProvider.totalGamesPlayed.toString(),
                color: SpaceTheme.cosmicPink,
              ),
              
              const SizedBox(height: 12),
              
              // Achievements
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: _buildStatItem(
                      icon: Icons.emoji_events,
                      label: S.of(context)!.achievements,
                      value: gameProvider.totalAchievements.toString(),
                      color: SpaceTheme.planetOrange,
                    ),
                  );
                },
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
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
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
                style: SpaceTheme.bodyStyle.copyWith(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              Text(
                value,
                style: SpaceTheme.titleStyle.copyWith(
                  fontSize: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Settings Button Widget (for future use)
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: SpaceTheme.moonSilver.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: IconButton(
        icon: const Icon(
          Icons.settings,
          color: SpaceTheme.moonSilver,
          size: 24,
        ),
        onPressed: () {
          // Navigate to settings screen
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context)!.settingsComingSoon),
              backgroundColor: SpaceTheme.nebulaPurple,
            ),
          );
        },
      ),
    );
  }
}

// Quick Stats Widget for smaller spaces
class QuickStats extends StatelessWidget {
  const QuickStats({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildQuickStat(
              icon: Icons.star,
              value: gameProvider.score.toString(),
              color: SpaceTheme.starYellow,
            ),
            _buildQuickStat(
              icon: Icons.trending_up,
              value: gameProvider.level.toString(),
              color: SpaceTheme.alienGreen,
            ),
            _buildQuickStat(
              icon: Icons.emoji_events,
              value: gameProvider.totalAchievements.toString(),
              color: SpaceTheme.planetOrange,
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildQuickStat({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            value,
            style: SpaceTheme.titleStyle.copyWith(
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}