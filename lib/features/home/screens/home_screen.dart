// lib/features/home/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../../core/services/debug_provider.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/streak_service.dart';
import '../../../core/services/learner_profile_service.dart';
import '../../../shared/widgets/purchase_dialog.dart';
import '../../../shared/widgets/parental_gate.dart';
import '../../games/screens/karteikasten_screen.dart';
import '../../games/screens/cognitive_profile_screen.dart';
import '../../achievements/screens/achievements_screen.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../../games/providers/game_provider.dart';
import '../../games/widgets/space_background.dart';

import '../../games/screens/game_menu_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../../shared/widgets/imprint_dialog.dart';
import '../widgets/word_of_the_day_card.dart';
import 'daily_session_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  int _debugTapCount = 0;
  Timer? _debugResetTimer;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _slideController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _debugResetTimer?.cancel();
    super.dispose();
  }

  void _navigateToGameMenu() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const GameMenuScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _navigateToDailySession() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const DailySessionScreen(),
    ));
  }

  void _navigateToSettings() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const SettingsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;

    // Better responsive breakpoints
    final isVerySmall = screenSize.height < 600 || screenSize.width < 360;
    final horizontalPadding = isVerySmall ? 12.0 : 20.0;
    final verticalPadding = isVerySmall ? 8.0 : 16.0;

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Column(
              children: [
                _buildHeader(isVerySmall),
                SizedBox(height: isVerySmall ? 8 : 12),
                Expanded(
                  child: isLandscape
                      ? _buildLandscapeLayout(isVerySmall)
                      : _buildPortraitLayout(isVerySmall),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isVerySmall) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              _debugResetTimer?.cancel();

              setState(() {
                _debugTapCount++;
              });

              if (_debugTapCount >= 7) {
                context.read<DebugProvider>().enableDebugMenu();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(S.of(context)!.debugModeEnabled),
                    backgroundColor: SpaceTheme.alienGreen,
                  ),
                );
                setState(() {
                  _debugTapCount = 0;
                });
              } else {
                _debugResetTimer = Timer(const Duration(seconds: 2), () {
                  setState(() {
                    _debugTapCount = 0;
                  });
                });
              }
            },
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                S.of(context)!.appTitle,
                style: SpaceTheme.headlineStyle.copyWith(
                  fontSize: isVerySmall ? 18 : 24,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const ImprintDialog(),
                );
              },
              icon: Icon(
                Icons.gavel_rounded,
                color: Colors.white,
                size: isVerySmall ? 22 : 28,
              ),
              style: IconButton.styleFrom(
                backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
                padding: EdgeInsets.all(isVerySmall ? 8 : 12),
              ),
              tooltip: S.of(context)!.imprintTitle,
            ),
            const SizedBox(width: 4),
            Consumer<StreakService>(
              builder: (context, streak, _) {
                if (!streak.isLoaded || streak.currentStreak == 0) {
                  return const SizedBox.shrink();
                }
                final label =
                    '🔥 ${streak.currentStreak} Tage am Stück — Rekord: ${streak.longestStreak}';
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: label,
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(label),
                              duration: const Duration(seconds: 3),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Semantics(
                          button: true,
                          label: label,
                          child: ExcludeSemantics(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    SpaceTheme.deepSpace.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: SpaceTheme.rocketRed
                                        .withValues(alpha: 0.6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('🔥',
                                      style: TextStyle(fontSize: 16)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${streak.currentStreak}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Consumer2<SriService, GameProvider>(
              builder: (context, sri, gameProvider, _) {
                final debugProvider = context.read<DebugProvider>();
                final isUnlocked = gameProvider.isFullVersionUnlocked ||
                    debugProvider.isPaidUnlockedForced;
                final due = sri.getAvailableReviewCount();
                final btn = IconButton(
                  onPressed: () {
                    if (isUnlocked) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const KarteikastenScreen(),
                      ));
                    } else {
                      showDialog(
                        context: context,
                        builder: (_) => ParentalGateDialog(
                          onSuccess: () {
                            Navigator.of(context).pop();
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const PurchaseDialog(),
                            );
                          },
                        ),
                      );
                    }
                  },
                  icon: Icon(
                    isUnlocked ? Icons.menu_book : Icons.menu_book_outlined,
                    color: isUnlocked ? Colors.white : SpaceTheme.moonSilver,
                    size: isVerySmall ? 22 : 28,
                  ),
                  tooltip: 'Review',
                  style: IconButton.styleFrom(
                    backgroundColor:
                        SpaceTheme.deepSpace.withValues(alpha: 0.8),
                    padding: EdgeInsets.all(isVerySmall ? 8 : 12),
                  ),
                );
                if (!isUnlocked) return btn;
                return due > 0 ? Badge.count(count: due, child: btn) : btn;
              },
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const CognitiveProfileScreen(),
                ));
              },
              icon: Icon(
                Icons.psychology,
                color: Colors.white,
                size: isVerySmall ? 22 : 28,
              ),
              tooltip: 'Lernprofil',
              style: IconButton.styleFrom(
                backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
                padding: EdgeInsets.all(isVerySmall ? 8 : 12),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AchievementsScreen(),
                ));
              },
              icon: Icon(
                Icons.emoji_events,
                color: Colors.white,
                size: isVerySmall ? 22 : 28,
              ),
              tooltip: 'Erfolge',
              style: IconButton.styleFrom(
                backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
                padding: EdgeInsets.all(isVerySmall ? 8 : 12),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _navigateToSettings,
              icon: Icon(
                Icons.settings,
                color: Colors.white,
                size: isVerySmall ? 22 : 28,
              ),
              style: IconButton.styleFrom(
                backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
                padding: EdgeInsets.all(isVerySmall ? 8 : 12),
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildLandscapeLayout(bool isVerySmall) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 800 || screenHeight < 500;

    return Row(
      children: [
        // LEFT SIDE
        Expanded(
          flex: isSmallScreen ? 5 : 6,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: AnimatedLogo(
                    size: isVerySmall ? 60 : (isSmallScreen ? 80 : 120),
                  ),
                ),
                if (!isSmallScreen) ...[
                  SizedBox(height: isVerySmall ? 12 : 16),
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        S.of(context)!.welcome,
                        style: SpaceTheme.headlineStyle.copyWith(
                          fontSize: isVerySmall ? 18 : 24,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: isVerySmall ? 8 : (isSmallScreen ? 12 : 20)),
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: CompactGradeSelector(isVerySmall: isVerySmall),
                  ),
                ),
                SizedBox(height: isVerySmall ? 8 : (isSmallScreen ? 12 : 20)),
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildStartButton(isSmallScreen, isVerySmall),
                  ),
                ),
                const SizedBox(height: 8),
                _buildBrowseButton(),
              ],
            ),
          ),
        ),

        SizedBox(width: isSmallScreen ? 8 : 16),

        // RIGHT SIDE
        Expanded(
          flex: isSmallScreen ? 4 : 5,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: CompactStatsCard(
                      isSmallScreen: isSmallScreen,
                      isVerySmall: isVerySmall,
                    ),
                  ),
                ),
                SizedBox(height: isVerySmall ? 6 : (isSmallScreen ? 8 : 12)),
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: CompactAchievementsPreview(
                      isSmallScreen: isSmallScreen,
                      isVerySmall: isVerySmall,
                    ),
                  ),
                ),
                SizedBox(height: isVerySmall ? 6 : (isSmallScreen ? 8 : 12)),
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: WordOfTheDayCard(isVerySmall: isVerySmall),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(bool isVerySmall) {
    final focusMode = context.watch<LearnerProfileService>().focusMode;
    return SingleChildScrollView(
      child: Column(
        children: [
          FadeTransition(
            opacity: _fadeAnimation,
            child: AnimatedLogo(size: isVerySmall ? 80 : 120),
          ),
          SizedBox(height: isVerySmall ? 8 : 12),
          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                S.of(context)!.welcome,
                style: SpaceTheme.headlineStyle.copyWith(
                  fontSize: isVerySmall ? 18 : 24,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          SizedBox(height: isVerySmall ? 12 : 16),

          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: CompactStatsCard(isVerySmall: isVerySmall),
            ),
          ),
          SizedBox(height: isVerySmall ? 8 : 12),
          if (!focusMode) ...[
            SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: CompactAchievementsPreview(isVerySmall: isVerySmall),
              ),
            ),
            SizedBox(height: isVerySmall ? 8 : 12),
          ],
          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: WordOfTheDayCard(isVerySmall: isVerySmall),
            ),
          ),
          SizedBox(height: isVerySmall ? 8 : 12),
          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: CompactGradeSelector(isVerySmall: isVerySmall),
            ),
          ),

          SizedBox(height: isVerySmall ? 12 : 16),

          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _buildStartButton(false, isVerySmall),
            ),
          ),
          const SizedBox(height: 8),
          _buildBrowseButton(),

          SizedBox(height: isVerySmall ? 8 : 12), // Bottom padding
        ],
      ),
    );
  }

  Widget _buildStartButton(bool isSmallScreen, bool isVerySmall) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: isVerySmall ? 240 : (isSmallScreen ? 280 : 380),
        minHeight: isVerySmall ? 44 : (isSmallScreen ? 48 : 60),
      ),
      decoration: BoxDecoration(
        gradient: SpaceTheme.starGradient,
        borderRadius: BorderRadius.circular(
          isVerySmall ? 12 : (isSmallScreen ? 16 : 30),
        ),
        boxShadow: [
          BoxShadow(
            color: SpaceTheme.starYellow.withValues(alpha: 0.4),
            blurRadius: isVerySmall ? 8 : (isSmallScreen ? 10 : 20),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(
            isVerySmall ? 12 : (isSmallScreen ? 16 : 30),
          ),
          onTap: _navigateToDailySession,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isVerySmall ? 16.0 : (isSmallScreen ? 20.0 : 24.0),
              vertical: isVerySmall ? 10.0 : (isSmallScreen ? 12.0 : 16.0),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.rocket_launch,
                  color: Colors.white,
                  size: isVerySmall ? 18 : (isSmallScreen ? 20 : 24),
                ),
                SizedBox(width: isVerySmall ? 6 : (isSmallScreen ? 8 : 12)),
                Flexible(
                  child: Consumer<LearnerProfileService>(
                    builder: (context, profile, child) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          S.of(context)!.dailySessionTitle,
                          textAlign: TextAlign.center,
                          style: SpaceTheme.buttonStyle.copyWith(
                            fontSize:
                                isVerySmall ? 14 : (isSmallScreen ? 15 : 18),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!isVerySmall)
                          Text(
                            S.of(context)!.dailySessionSubtitle(
                                  profile.sessionMinutes,
                                ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrowseButton() => TextButton.icon(
        onPressed: _navigateToGameMenu,
        icon: const Icon(Icons.grid_view),
        label: Text(S.of(context)!.browseAllGames),
      );
}

// Updated AnimatedLogo with size parameter
class AnimatedLogo extends StatefulWidget {
  final double size;

  const AnimatedLogo({super.key, this.size = 150});

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focusMode = context.watch<LearnerProfileService>().focusMode;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: focusMode ? 1.0 : _animation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFD700),
                  Color(0xFFFF6B35),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              Icons.auto_stories,
              color: Colors.white,
              size: widget.size * 0.4,
            ),
          ),
        );
      },
    );
  }
}

// Updated CompactStatsCard with better responsive sizing
class CompactStatsCard extends StatelessWidget {
  final bool isSmallScreen;
  final bool isVerySmall;

  const CompactStatsCard({
    super.key,
    this.isSmallScreen = false,
    this.isVerySmall = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        return Container(
          padding: EdgeInsets.all(isVerySmall ? 10 : (isSmallScreen ? 12 : 16)),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2A2D3E),
                Color(0xFF1E2235),
              ],
            ),
            borderRadius: BorderRadius.circular(
                isVerySmall ? 10 : (isSmallScreen ? 12 : 16)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.analytics,
                    color: const Color(0xFFFFD700),
                    size: isVerySmall ? 16 : (isSmallScreen ? 18 : 20),
                  ),
                  SizedBox(width: isVerySmall ? 6 : 8),
                  Flexible(
                    child: Text(
                      S.of(context)!.progress,
                      style: TextStyle(
                        fontSize: isVerySmall ? 13 : (isSmallScreen ? 14 : 16),
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isVerySmall ? 8 : (isSmallScreen ? 10 : 12)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCompactStatItem(
                    context: context,
                    icon: Icons.star,
                    label: S.of(context)!.score,
                    value: gameProvider.score.toString(),
                    color: const Color(0xFFFFD700),
                    isSmallScreen: isSmallScreen,
                    isVerySmall: isVerySmall,
                  ),
                  _buildCompactStatItem(
                    context: context,
                    icon: Icons.games,
                    label: S.of(context)!.gamesPlayed,
                    value: gameProvider.totalGamesPlayed.toString(),
                    color: const Color(0xFF06FFA5),
                    isSmallScreen: isSmallScreen,
                    isVerySmall: isVerySmall,
                  ),
                  _buildCompactStatItem(
                    context: context,
                    icon: Icons.emoji_events,
                    label: S.of(context)!.achievements,
                    value: gameProvider.totalAchievements.toString(),
                    color: const Color(0xFFFF6B35),
                    isSmallScreen: isSmallScreen,
                    isVerySmall: isVerySmall,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactStatItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isSmallScreen,
    required bool isVerySmall,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isVerySmall ? 28 : (isSmallScreen ? 32 : 40),
          height: isVerySmall ? 28 : (isSmallScreen ? 32 : 40),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(isVerySmall ? 6 : 8),
          ),
          child: Icon(
            icon,
            color: color,
            size: isVerySmall ? 14 : (isSmallScreen ? 16 : 20),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: isVerySmall ? 12 : (isSmallScreen ? 13 : 16),
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (!isSmallScreen && !isVerySmall)
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white70,
            ),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

// Updated CompactAchievementsPreview with better responsive sizing
class CompactAchievementsPreview extends StatelessWidget {
  final bool isSmallScreen;
  final bool isVerySmall;

  const CompactAchievementsPreview({
    super.key,
    this.isSmallScreen = false,
    this.isVerySmall = false,
  });

  AchievementUIData _getAchievementUIData(BuildContext context, String id) {
    final s = S.of(context)!;
    switch (id) {
      case 'first_century':
        return AchievementUIData(
            title: s.achievementFirstCenturyTitle,
            description: s.achievementFirstCenturyDesc,
            icon: '💯');
      case 'score_master':
        return AchievementUIData(
            title: s.achievementScoreMasterTitle,
            description: s.achievementScoreMasterDesc,
            icon: '⭐');
      case 'word_rescuer':
        return AchievementUIData(
            title: s.achievementWordRescuerTitle,
            description: s.achievementWordRescuerDesc,
            icon: '🚀');
      default:
        return AchievementUIData(
            title: s.achievementAllRounderTitle,
            description: s.achievementAllRounderDesc,
            icon: '🎯');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        final achievements =
            gameProvider.achievements.reversed.take(2).toList();

        return Container(
          padding: EdgeInsets.all(isVerySmall ? 8 : (isSmallScreen ? 10 : 12)),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2A2D3E),
                Color(0xFF1E2235),
              ],
            ),
            borderRadius: BorderRadius.circular(
                isVerySmall ? 10 : (isSmallScreen ? 12 : 16)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.emoji_events,
                    color: SpaceTheme.starYellow,
                    size: isVerySmall ? 14 : (isSmallScreen ? 16 : 18),
                  ),
                  SizedBox(width: isVerySmall ? 4 : 6),
                  Flexible(
                    child: Text(
                      S.of(context)!.achievements,
                      style: SpaceTheme.titleStyle.copyWith(
                        fontSize: isVerySmall ? 11 : (isSmallScreen ? 12 : 14),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isVerySmall ? 4 : 6),
              if (achievements.isEmpty)
                Text(
                  S.of(context)!.playToUnlock,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: isVerySmall ? 9 : (isSmallScreen ? 10 : 11),
                  ),
                  textAlign: TextAlign.center,
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: achievements.map((achievement) {
                    final uiData =
                        _getAchievementUIData(context, achievement.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            uiData.icon,
                            style: TextStyle(
                              fontSize:
                                  isVerySmall ? 10 : (isSmallScreen ? 12 : 14),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              uiData.title,
                              style: SpaceTheme.bodyStyle.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize:
                                    isVerySmall ? 9 : (isSmallScreen ? 10 : 11),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}

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

// COMPACT Grade Selector with better responsive sizing
class CompactGradeSelector extends StatelessWidget {
  final bool isVerySmall;

  const CompactGradeSelector({super.key, this.isVerySmall = false});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        return Container(
          padding: EdgeInsets.all(isVerySmall ? 10 : 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2A2D3E),
                Color(0xFF1E2235),
              ],
            ),
            borderRadius: BorderRadius.circular(isVerySmall ? 10 : 15),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    color: const Color(0xFFFFD700),
                    size: isVerySmall ? 16 : 20,
                  ),
                  SizedBox(width: isVerySmall ? 6 : 8),
                  Flexible(
                    child: Text(
                      S.of(context)!.gradeN(gameProvider.grade),
                      style: TextStyle(
                        fontSize: isVerySmall ? 13 : 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isVerySmall ? 8 : 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [1, 2, 3, 4].map((level) {
                  final isSelected = gameProvider.grade == level;

                  return GestureDetector(
                    onTap: () => gameProvider.setGrade(level),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: isVerySmall ? 36 : 40,
                      height: isVerySmall ? 36 : 40,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFFFFD700),
                                  Color(0xFFFF6B35),
                                ],
                              )
                            : const LinearGradient(
                                colors: [
                                  Color(0xFF1A1A2E),
                                  Color(0xFF16213E),
                                ],
                              ),
                        borderRadius:
                            BorderRadius.circular(isVerySmall ? 8 : 10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFFD700)
                              : const Color(0xFFC0C0C0).withValues(alpha: 0.3),
                          width: 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFFFD700)
                                      .withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          level.toString(),
                          style: TextStyle(
                            fontSize: isVerySmall ? 16 : 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
