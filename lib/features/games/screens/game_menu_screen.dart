// lib/features/games/screens/game_menu_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/debug_provider.dart';
import '../../../core/services/learner_profile_service.dart';
import '../../../core/services/language_pack_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../core/models/skill_category.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/space_background.dart';

import 'definition_quiz_game.dart';
import 'sentence_completion_game.dart';
import 'antonym_flash_game.dart';
import 'conjugation_drill_game.dart';
import 'homophone_drill_game.dart';
import 'phrasal_verb_power_game.dart';
import 'phrasal_verb_match_game.dart';
import 'false_friends_game.dart';
import 'wortfalle_game.dart';
import '../services/homophone_drill_service.dart' show HomophoneGameMode;
import 'cloze_flash_game.dart';
import 'expression_flash_game.dart';
import 'hypernym_flash_game.dart';
import 'proverb_cloze_game.dart';
import 'reverse_translation_flash_game.dart';
import 'syllable_count_game.dart';
import 'word_class_flash_game.dart';
import 'synonym_flash_game.dart';
import 'translation_flash_game.dart';
import 'sri_review_game.dart';
import 'space_word_rescue_game.dart';
import 'spelling_spotter_game.dart';
import 'word_find_game.dart';
import 'word_sort_game.dart';
import 'word_snake_game.dart';
import 'word_memory_game.dart';
import 'word_builder_game.dart';
import 'word_type_whirl_game.dart';
import 'wortbaumeister_game.dart';
import 'grossstadt_game.dart';
import 'grossschreib_game.dart';
import 'verbtrenner_game.dart';

import '../widgets/debug_panel.dart';
import '../../settings/screens/settings_screen.dart';
import '../../achievements/screens/achievements_screen.dart';
import '../../../shared/widgets/purchase_dialog.dart';
import '../../../shared/widgets/parental_gate.dart';
import '../../../shared/widgets/imprint_dialog.dart';
import '../../../shared/widgets/language_pack_dialog.dart';

class GameMenuScreen extends StatefulWidget {
  const GameMenuScreen({super.key});

  @override
  State<GameMenuScreen> createState() => _GameMenuScreenState();
}

enum _GameFilter {
  recommended,
  vocabulary,
  spelling,
  grammar,
  fast,
  favorites,
  recent,
  all
}

enum _GameCategory { vocabulary, spelling, grammar, fast }

class _GameMenuScreenState extends State<GameMenuScreen>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _floatController;
  late List<Animation<Offset>> _cardAnimations;
  late Animation<double> _floatAnimation;
  final TextEditingController _searchController = TextEditingController();
  _GameFilter _filter = _GameFilter.recommended;

  // for new games, we must manually update game count
  static const int _gameCount = 32;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
        duration: const Duration(milliseconds: 1500), vsync: this);
    _floatController =
        AnimationController(duration: const Duration(seconds: 3), vsync: this)
          ..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: -10.0, end: 10.0).animate(
        CurvedAnimation(parent: _floatController, curve: Curves.easeInOut));
    _cardAnimations = List.generate(_gameCount, (index) {
      return Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero)
          .animate(CurvedAnimation(
        parent: _slideController,
        curve: Interval(
          (index * 0.1).clamp(0.0, 1.0),
          (0.5 + (index * 0.1)).clamp(0.0, 1.0),
          curve: Curves.elasticOut,
        ),
      ));
    });
    _slideController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _slideController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  void _showDebugPanel() {
    showDialog(
      context: context,
      builder: (context) => DebugPanel(),
    );
  }

  void _navigateToSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _navigateToAchievements() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AchievementsScreen()));
  }

  /// Every game launch goes through here, and every game needs a loaded
  /// vocabulary. If the active language pack isn't installed (e.g. the German
  /// DB was never downloaded), offer the download instead of pushing a game
  /// that would run on an empty word list and crash.
  Future<void> _navigateToGame(Widget gameScreen) async {
    if (!await ensureLanguagePackReady(context)) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => gameScreen));
  }

  void _showPurchaseFlow(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ParentalGateDialog(
        onSuccess: () {
          Navigator.of(context).pop(); // Close the gate dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const PurchaseDialog(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // We use LayoutBuilder to make decisions based on available space, not just screen size
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildMissingPackBanner(),
              _buildDifficultyPicker(),
              _buildDiscoveryControls(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      child: _buildResponsiveGrid(constraints),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Visible warning when the active language pack isn't loaded, so the
  /// reason games can't start is obvious before tapping one.
  Widget _buildMissingPackBanner() {
    return Consumer<LanguagePackService>(
      builder: (context, packs, _) {
        if (packs.isActivePackReady) return const SizedBox.shrink();
        final pack = packs.stateFor(packs.activeLanguage).pack;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: SpaceTheme.planetOrange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => ensureLanguagePackReady(context),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_download_outlined,
                        color: SpaceTheme.planetOrange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        S.of(context)!.packMissingBanner(pack.nativeName),
                        style: SpaceTheme.bodyStyle.copyWith(fontSize: 12),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: SpaceTheme.moonSilver, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final debugProvider = context.watch<DebugProvider>();
    return Container(
      padding: const EdgeInsets.all(16), // Reduced padding slightly
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E2235), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios,
                color: Colors.white, size: 24), // Slightly smaller
            style: IconButton.styleFrom(
              backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
              padding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Use FittedBox to prevent overflow on small screens
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(S.of(context)!.gameMenu,
                      style: SpaceTheme.headlineStyle.copyWith(fontSize: 32)),
                ),
                Consumer<GameProvider>(
                  builder: (context, gameProvider, child) {
                    final difficulty = switch (gameProvider.difficultyMode) {
                      DifficultyMode.easy => S.of(context)!.difficultyEasy,
                      DifficultyMode.normal => S.of(context)!.difficultyNormal,
                      DifficultyMode.challenge =>
                        S.of(context)!.difficultyChallenge,
                    };
                    return Text(
                      '${S.of(context)!.gradeN(gameProvider.grade)} • $difficulty',
                      style: SpaceTheme.bodyStyle
                          .copyWith(color: SpaceTheme.starYellow, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ],
            ),
          ),

          // Score Display
          Consumer<GameProvider>(
            builder: (context, gameProvider, child) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: SpaceTheme.deepSpace.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star,
                        color: SpaceTheme.starYellow, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      gameProvider.score.toString(),
                      style: SpaceTheme.titleStyle
                          .copyWith(color: SpaceTheme.starYellow, fontSize: 16),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(width: 8),
          // Wrap actions in a Row. On very small screens, this might be tight,
          // but icon buttons are fixed size.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionButton(Icons.emoji_events, SpaceTheme.starYellow,
                  S.of(context)!.achievements, _navigateToAchievements),
              const SizedBox(width: 4),
              _buildActionButton(Icons.gavel_rounded, SpaceTheme.moonSilver,
                  S.of(context)!.imprintTitle, () {
                showDialog(
                  context: context,
                  builder: (context) => const ImprintDialog(),
                );
              }),
              const SizedBox(width: 4),
              _buildActionButton(Icons.settings, SpaceTheme.moonSilver,
                  S.of(context)!.settings, _navigateToSettings),
              if (debugProvider.isDebugMenuEnabled) ...[
                const SizedBox(width: 4),
                _buildActionButton(
                    Icons.bug_report,
                    debugProvider.isPaidUnlockedForced
                        ? SpaceTheme.alienGreen
                        : SpaceTheme.moonSilver,
                    S.of(context)!.debugPanelTitle,
                    _showDebugPanel),
              ]
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, Color color, String tooltip, VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20), // Smaller icon size
      color: color,
      tooltip: tooltip,
      padding: const EdgeInsets.all(
          8), // Reduce tap target padding slightly for density
      constraints: const BoxConstraints(), // Remove minimum size constraints
      style: IconButton.styleFrom(
          backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8)),
    );
  }

  Widget _buildResponsiveGrid(BoxConstraints constraints) {
    // Determine crossAxisCount based on width available
    final double width = constraints.maxWidth;
    int crossAxisCount = 2;
    double aspectRatio = 0.85;

    if (width > 1100) {
      crossAxisCount = 5;
      aspectRatio = 1.1;
    } else if (width > 800) {
      crossAxisCount = 4;
      aspectRatio = 1.1;
    } else if (width > 600) {
      crossAxisCount = 3;
      aspectRatio = 1.0;
    } else if (width < 360) {
      // Very small screens (older iPhones, small Androids)
      crossAxisCount = 2;
      aspectRatio = 0.75; // Taller cards to fit text vertically
    } else {
      // Standard Portrait
      crossAxisCount = 2;
      aspectRatio = 0.85;
    }

    final games = _buildGames();

    if (games.isEmpty) {
      return Center(
        child: Text(S.of(context)!.catalogNoGames,
            style: SpaceTheme.bodyStyle, textAlign: TextAlign.center),
      );
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: aspectRatio,
      ),
      itemCount: games.length,
      itemBuilder: (context, index) => _buildGameCard(index, games[index]),
    );
  }

  List<GameInfo> _buildGames() {
    final gameProvider = context.read<GameProvider>();
    final learningLanguage =
        context.watch<VocabularyService>().learningLanguage;
    final s = S.of(context)!;

    final games = [
      GameInfo(
        title: s.spaceWordRescueTitle,
        description: s.spaceWordRescueInstructions,
        icon: Icons.rocket_launch,
        gradient: const LinearGradient(
            colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)]),
        supportedLearningLanguages: const ['de', 'en'],
        onTap: () => _navigateToGame(SpaceWordRescueGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.wordFindTitle,
        description: s.wordFindDescription,
        icon: Icons.grid_on,
        gradient: const LinearGradient(
            colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)]),
        supportedLearningLanguages: const ['de', 'en'],
        onTap: () => _navigateToGame(WordFindGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.wordSortTitle,
        description: s.wordSortDescription,
        icon: Icons.sort_by_alpha,
        gradient: const LinearGradient(
            colors: [Color(0xFFf953c6), Color(0xFFb91d73)]),
        supportedLearningLanguages: const ['de', 'en'],
        onTap: () => _navigateToGame(WordSortGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.wordSnakeTitle,
        description: s.wordSnakeDescription,
        icon: Icons.timeline,
        gradient: const LinearGradient(
            colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)]),
        supportedLearningLanguages: const ['de', 'en'],
        onTap: () => _navigateToGame(WordSnakeGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.wordMemoryTitle,
        description: s.wordMemoryDescription,
        icon: Icons.psychology,
        gradient: const LinearGradient(
            colors: [Color(0xFFFA8BFF), Color(0xFF2BD2FF)]),
        supportedLearningLanguages: const ['de', 'en'],
        onTap: () => _navigateToGame(WordMemoryGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.wordBuilderTitle,
        description: s.wordBuilderDescription,
        icon: Icons.construction,
        gradient: const LinearGradient(
            colors: [Color(0xFFFFA500), Color(0xFFFF6347)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(WordBuilderGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.wordWhirlTitle,
        description: s.wordWhirlDescription,
        icon: Icons.tornado,
        gradient: const LinearGradient(
            colors: [Color(0xFF667eea), Color(0xFF764ba2)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(WordTypeWhirlGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.spellingSpotterTitle,
        description: s.spellingSpotterDescription,
        icon: Icons.spellcheck,
        gradient: const LinearGradient(
            colors: [Color(0xFF00B4DB), Color(0xFF0083B0)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(SpellingSpotterGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.sentenceCompletionTitle,
        description: s.sentenceCompletionDescription,
        icon: Icons.text_fields,
        gradient: const LinearGradient(
            colors: [Color(0xFF43C6AC), Color(0xFF191654)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(SentenceCompletionGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.definitionQuizTitle,
        description: s.definitionQuizDescription,
        icon: Icons.quiz,
        gradient: const LinearGradient(
            colors: [Color(0xFFDA22FF), Color(0xFF9733EE)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(DefinitionQuizGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.sriReviewTitle,
        description: s.sriReviewDescription,
        icon: Icons.repeat,
        gradient: const LinearGradient(
            colors: [Color(0xFF11998E), Color(0xFF38EF7D)]),
        supportedLearningLanguages: const ['de', 'en'],
        onTap: () => _navigateToGame(const SriReviewGame()),
      ),
      GameInfo(
        title: s.antonymFlashTitle,
        description: s.antonymFlashDescription,
        icon: Icons.swap_horiz,
        gradient: const LinearGradient(
            colors: [Color(0xFFFC4A1A), Color(0xFFF7B733)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(AntonymFlashGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.synonymFlashTitle,
        description: s.synonymFlashDescription,
        icon: Icons.sync_alt,
        gradient: const LinearGradient(
            colors: [Color(0xFF11998E), Color(0xFF38EF7D)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(SynonymFlashGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.conjugationDrillTitle,
        description: s.conjugationDrillDescription,
        icon: Icons.text_fields,
        gradient: const LinearGradient(
            colors: [Color(0xFF00B09B), Color(0xFF96C93D)]),
        supportedLearningLanguages: const ['de'],
        isPremium: true,
        onTap: () => _navigateToGame(ConjugationDrillGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.translationFlashTitle,
        description: s.translationFlashDescription,
        icon: Icons.translate,
        gradient: const LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF3F51B5)]),
        supportedLearningLanguages: const ['de'],
        onTap: () => _navigateToGame(TranslationFlashGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.syllableCountTitle,
        description: s.syllableCountDescription,
        icon: Icons.record_voice_over_outlined,
        gradient: const LinearGradient(
            colors: [Color(0xFF009FFF), Color(0xFFec2F4B)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(SyllableCountGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.clozeFlashTitle,
        description: s.clozeFlashDescription,
        icon: Icons.edit_note,
        gradient: const LinearGradient(
            colors: [Color(0xFFF7971E), Color(0xFFFFD200)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(ClozeFlashGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.expressionFlashTitle,
        description: s.expressionFlashDescription,
        icon: Icons.format_quote,
        gradient: const LinearGradient(
            colors: [Color(0xFF2193b0), Color(0xFF6dd5ed)]),
        supportedLearningLanguages: const ['de'],
        isPremium: true,
        onTap: () => _navigateToGame(ExpressionFlashGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.homophoneDrillTitle,
        description: s.homophoneDrillDescription,
        icon: Icons.record_voice_over,
        gradient: const LinearGradient(
            colors: [Color(0xFF4776E6), Color(0xFF8E54E9)]),
        supportedLearningLanguages: const ['en'],
        isPremium: true,
        onTap: () => _navigateToGame(HomophoneDrillGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.confusableDrillTitle,
        description: s.confusableDrillDescription,
        icon: Icons.warning_amber,
        gradient: const LinearGradient(
            colors: [Color(0xFFEB3349), Color(0xFFF45C43)]),
        supportedLearningLanguages: const ['en'],
        isPremium: true,
        onTap: () => _navigateToGame(HomophoneDrillGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade),
            mode: HomophoneGameMode.confusables)),
      ),
      GameInfo(
        title: s.phrasalVerbPowerTitle,
        description: s.phrasalVerbPowerDescription,
        icon: Icons.bolt,
        gradient: const LinearGradient(
            colors: [Color(0xFF11998e), Color(0xFF38ef7d)]),
        supportedLearningLanguages: const ['en'],
        isPremium: true,
        onTap: () => _navigateToGame(PhrasalVerbPowerGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.phrasalVerbMatchTitle,
        description: s.phrasalVerbMatchDescription,
        icon: Icons.link,
        gradient: const LinearGradient(
            colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)]),
        supportedLearningLanguages: const ['en'],
        isPremium: true,
        onTap: () => _navigateToGame(PhrasalVerbMatchGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.falseFriendsTitle,
        description: s.falseFriendsDescription,
        icon: Icons.warning_amber,
        gradient: const LinearGradient(
            colors: [Color(0xFFee0979), Color(0xFFff6a00)]),
        supportedLearningLanguages: const ['en'],
        isPremium: true,
        onTap: () => _navigateToGame(FalseFriendsGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.wortfalleTitle,
        description: s.wortfalleDescription,
        icon: Icons.report_problem,
        gradient: const LinearGradient(
            colors: [Color(0xFFc31432), Color(0xFF240b36)]),
        supportedLearningLanguages: const ['de'],
        isPremium: true,
        onTap: () => _navigateToGame(WortfalleGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.wortbaumeisterCardTitle,
        description: s.wortbaumeisterCardDescription,
        icon: Icons.handyman,
        gradient: const LinearGradient(
            colors: [Color(0xFFF2994A), Color(0xFFF2C94C)]),
        supportedLearningLanguages: const ['de'],
        isPremium: true,
        onTap: () => _navigateToGame(WortbaumeisterGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.grossstadtCardTitle,
        description: s.grossstadtCardDescription,
        icon: Icons.location_city,
        gradient: const LinearGradient(
            colors: [Color(0xFF30E8BF), Color(0xFFFF8235)]),
        supportedLearningLanguages: const ['de'],
        isPremium: true,
        onTap: () => _navigateToGame(GrossstadtGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.grossschreibTitle,
        description: s.grossschreibDescription,
        icon: Icons.call_split,
        gradient: const LinearGradient(
            colors: [Color(0xFF11998e), Color(0xFF38ef7d)]),
        supportedLearningLanguages: const ['de'],
        isPremium: true,
        onTap: () => _navigateToGame(GrossschreibungsGalaxieGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.verbtrennerCardTitle,
        description: s.verbtrennerCardDescription,
        icon: Icons.compare_arrows,
        gradient: const LinearGradient(
            colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
        supportedLearningLanguages: const ['de'],
        isPremium: true,
        onTap: () => _navigateToGame(VerbtrennerGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.hypernymFlashTitle,
        description: s.hypernymFlashDescription,
        icon: Icons.account_tree_outlined,
        gradient: const LinearGradient(
            colors: [Color(0xFF7F00FF), Color(0xFFE100FF)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(HypernymFlashGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.wordClassFlashTitle,
        description: s.wordClassFlashDescription,
        icon: Icons.label_outline,
        gradient: const LinearGradient(
            colors: [Color(0xFF203A43), Color(0xFF2C5364)]),
        supportedLearningLanguages: const ['de', 'en'],
        isPremium: true,
        onTap: () => _navigateToGame(WordClassFlashGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.proverbClozeTitle,
        description: s.proverbClozeDescription,
        icon: Icons.auto_stories,
        gradient: const LinearGradient(
            colors: [Color(0xFFc6a700), Color(0xFF5f0f40)]),
        supportedLearningLanguages: const ['de'],
        isPremium: true,
        onTap: () => _navigateToGame(ProverbClozeGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
      GameInfo(
        title: s.reverseTranslationTitle,
        description: s.reverseTranslationDescription,
        icon: Icons.swap_vert,
        gradient: const LinearGradient(
            colors: [Color(0xFF134E5E), Color(0xFF71B280)]),
        supportedLearningLanguages: const ['de'],
        isPremium: true,
        onTap: () => _navigateToGame(ReverseTranslationFlashGame(
            gradeLevel: _getGradeLevelFromInt(gameProvider.grade))),
      ),
    ];

    final profile = context.watch<LearnerProfileService>();
    final query = _searchController.text.trim().toLowerCase();
    return games
        .where((game) =>
            game.supportedLearningLanguages.contains(learningLanguage))
        .where((game) =>
            query.isEmpty ||
            game.title.toLowerCase().contains(query) ||
            game.description.toLowerCase().contains(query))
        .where((game) {
      final id = _gameId(game, s);
      final category = _category(game, s);
      return switch (_filter) {
        _GameFilter.all => true,
        _GameFilter.recommended => _isRecommended(game, s, profile.goal),
        _GameFilter.vocabulary => category == _GameCategory.vocabulary,
        _GameFilter.spelling => category == _GameCategory.spelling,
        _GameFilter.grammar => category == _GameCategory.grammar,
        _GameFilter.fast => category == _GameCategory.fast,
        _GameFilter.favorites => profile.favoriteGameIds.contains(id),
        _GameFilter.recent => profile.recentGameIds.contains(id),
      };
    }).toList(growable: false);
  }

  Widget _buildDiscoveryControls() {
    final s = S.of(context)!;
    final filters = <(_GameFilter, String)>[
      (_GameFilter.recommended, s.catalogRecommended),
      (_GameFilter.vocabulary, s.categoryVocabulary),
      (_GameFilter.spelling, s.categorySpelling),
      (_GameFilter.grammar, s.categoryGrammar),
      (_GameFilter.fast, s.catalogFast),
      (_GameFilter.favorites, s.catalogFavorites),
      (_GameFilter.recent, s.catalogRecent),
      (_GameFilter.all, s.catalogAll),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(children: [
        SizedBox(
          height: 42,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: s.catalogSearch,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
              filled: true,
              fillColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, index) {
              final item = filters[index];
              return FilterChip(
                label: Text(item.$2),
                selected: _filter == item.$1,
                onSelected: (_) => setState(() => _filter = item.$1),
              );
            },
          ),
        ),
      ]),
    );
  }

  String _gameId(GameInfo game, S s) {
    final entries = <String, String>{
      s.spaceWordRescueTitle: 'space_word_rescue',
      s.wordFindTitle: 'word_find',
      s.wordSortTitle: 'word_sort',
      s.wordSnakeTitle: 'word_snake',
      s.wordMemoryTitle: 'word_memory',
      s.wordBuilderTitle: 'word_builder',
      s.wordWhirlTitle: 'word_whirl',
      s.spellingSpotterTitle: 'spelling_spotter',
      s.sentenceCompletionTitle: 'sentence_completion',
      s.definitionQuizTitle: 'definition_quiz',
      s.sriReviewTitle: 'sri_review',
      s.antonymFlashTitle: 'antonym_flash',
      s.synonymFlashTitle: 'synonym_flash',
      s.conjugationDrillTitle: 'conjugation_drill',
      s.translationFlashTitle: 'translation_flash',
      s.syllableCountTitle: 'syllable_count',
      s.clozeFlashTitle: 'cloze_flash',
      s.expressionFlashTitle: 'expression_flash',
      s.homophoneDrillTitle: 'homophone_drill',
      s.confusableDrillTitle: 'confusable_drill',
      s.phrasalVerbPowerTitle: 'phrasal_verb_power',
      s.phrasalVerbMatchTitle: 'phrasal_verb_match',
      s.falseFriendsTitle: 'false_friends',
      s.wortfalleTitle: 'wortfalle',
      s.wortbaumeisterCardTitle: 'wortbaumeister',
      s.grossstadtCardTitle: 'grossstadt',
      s.grossschreibTitle: 'grossschreib',
      s.verbtrennerCardTitle: 'verbtrenner',
      s.hypernymFlashTitle: 'hypernym_flash',
      s.wordClassFlashTitle: 'word_class_flash',
      s.proverbClozeTitle: 'proverb_cloze',
      s.reverseTranslationTitle: 'reverse_translation',
    };
    return entries[game.title] ?? game.title;
  }

  _GameCategory _category(GameInfo game, S s) {
    if ({
      s.spaceWordRescueTitle,
      s.spellingSpotterTitle,
      s.syllableCountTitle,
      s.homophoneDrillTitle,
      s.confusableDrillTitle,
      s.wortfalleTitle,
      s.grossstadtCardTitle,
      s.grossschreibTitle
    }.contains(game.title)) {
      return _GameCategory.spelling;
    }
    if ({
      s.wordSortTitle,
      s.wordWhirlTitle,
      s.conjugationDrillTitle,
      s.phrasalVerbPowerTitle,
      s.verbtrennerCardTitle,
      s.wordClassFlashTitle,
      s.wortbaumeisterCardTitle
    }.contains(game.title)) {
      return _GameCategory.grammar;
    }
    if ({
      s.antonymFlashTitle,
      s.synonymFlashTitle,
      s.translationFlashTitle,
      s.hypernymFlashTitle,
      s.reverseTranslationTitle
    }.contains(game.title)) {
      return _GameCategory.fast;
    }
    return _GameCategory.vocabulary;
  }

  bool _isRecommended(GameInfo game, S s, LearnerGoal goal) {
    if (game.title == s.sriReviewTitle) return true;
    final category = _category(game, s);
    return switch (goal) {
      LearnerGoal.spelling => category == _GameCategory.spelling,
      LearnerGoal.grammar => category == _GameCategory.grammar,
      LearnerGoal.vocabulary ||
      LearnerGoal.dafDaz =>
        category == _GameCategory.vocabulary,
      LearnerGoal.balanced => {
          s.spaceWordRescueTitle,
          s.sentenceCompletionTitle,
          s.definitionQuizTitle,
          s.wordSortTitle,
          s.sriReviewTitle
        }.contains(game.title),
    };
  }

  Widget _buildGameCard(int index, GameInfo game) {
    final gameProvider = context.read<GameProvider>();
    final debugProvider = context.read<DebugProvider>();
    final bool isUnlocked = gameProvider.isFullVersionUnlocked ||
        debugProvider.isPaidUnlockedForced;
    final bool isLocked = game.isPremium && !isUnlocked;
    final profile = context.watch<LearnerProfileService>();
    final s = S.of(context)!;
    final id = _gameId(game, s);
    final category = _category(game, s);
    final categoryLabel = switch (category) {
      _GameCategory.vocabulary => s.categoryVocabulary,
      _GameCategory.spelling => s.categorySpelling,
      _GameCategory.grammar => s.categoryGrammar,
      _GameCategory.fast => s.catalogFast,
    };

    if (index >= _cardAnimations.length) return const SizedBox.shrink();

    return SlideTransition(
      position: _cardAnimations[index],
      child: AnimatedBuilder(
        animation: _floatAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: profile.focusMode
                ? Offset.zero
                : Offset(
                    0,
                    _floatAnimation.value * (index % 3 + 1) * 0.3,
                  ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                GameCard(
                  game: game,
                  categoryLabel: categoryLabel,
                  minutes: category == _GameCategory.fast ? 3 : 6,
                  isFavorite: profile.favoriteGameIds.contains(id),
                  onFavorite: () => profile.toggleFavorite(id),
                  onTap: isLocked
                      ? () => _showPurchaseFlow(context)
                      : () {
                          profile.recordRecentGame(id);
                          game.onTap();
                        },
                ),
                if (isLocked)
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(25)),
                  ),
                if (isLocked)
                  Icon(Icons.lock,
                      color: SpaceTheme.starYellow,
                      size: 50,
                      shadows: [
                        Shadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 10)
                      ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDifficultyPicker() {
    return Consumer<GameProvider>(
      builder: (context, gp, _) {
        final s = S.of(context)!;
        final mode = gp.difficultyMode;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DifficultyButton(
                label: s.difficultyEasy,
                icon: Icons.spa,
                selected: mode == DifficultyMode.easy,
                onTap: () => gp.setDifficultyMode(DifficultyMode.easy),
              ),
              const SizedBox(width: 8),
              _DifficultyButton(
                label: s.difficultyNormal,
                icon: Icons.school,
                selected: mode == DifficultyMode.normal,
                onTap: () => gp.setDifficultyMode(DifficultyMode.normal),
              ),
              const SizedBox(width: 8),
              _DifficultyButton(
                label: s.difficultyChallenge,
                icon: Icons.local_fire_department,
                selected: mode == DifficultyMode.challenge,
                onTap: () => gp.setDifficultyMode(DifficultyMode.challenge),
              ),
            ],
          ),
        );
      },
    );
  }

  GradeLevel _getGradeLevelFromInt(int grade) {
    // Apply the current difficulty mode's grade shift so the game
    // launches one band easier/harder than the player's official grade
    // when requested.
    final gameProvider = context.read<GameProvider>();
    final shifted =
        (grade + gameProvider.difficultyMode.gradeShift).clamp(1, 6);
    switch (shifted) {
      case 1:
        return GradeLevel.grade1;
      case 2:
        return GradeLevel.grade2;
      case 3:
        return GradeLevel.grade3;
      case 4:
        return GradeLevel.grade4;
      case 5:
        return GradeLevel.grade5;
      case 6:
        return GradeLevel.grade6;
      default:
        return GradeLevel.grade1;
    }
  }
}

class GameInfo {
  final String title;
  final String description;
  final IconData icon;
  final Gradient gradient;
  final List<String> supportedLearningLanguages;
  final VoidCallback onTap;
  final bool isPremium;
  GameInfo(
      {required this.title,
      required this.description,
      required this.icon,
      required this.gradient,
      this.supportedLearningLanguages = const ['de'],
      required this.onTap,
      this.isPremium = false});
}

class GameCard extends StatefulWidget {
  final GameInfo game;
  final VoidCallback onTap;
  final String categoryLabel;
  final int minutes;
  final bool isFavorite;
  final VoidCallback onFavorite;
  const GameCard({
    super.key,
    required this.game,
    required this.onTap,
    required this.categoryLabel,
    required this.minutes,
    required this.isFavorite,
    required this.onFavorite,
  });

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
        duration: const Duration(milliseconds: 200), vsync: this);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
        CurvedAnimation(parent: _hoverController, curve: Curves.easeOut));
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
        CurvedAnimation(parent: _hoverController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  void _onHover(bool isHovered) {
    if (isHovered) {
      _hoverController.forward();
    } else {
      _hoverController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: MouseRegion(
            onEnter: (_) => _onHover(true),
            onExit: (_) => _onHover(false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                decoration: BoxDecoration(
                  gradient: widget.game.gradient,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8)),
                    BoxShadow(
                        color: widget.game.gradient.colors.first
                            .withValues(alpha: _glowAnimation.value),
                        blurRadius: 25,
                        spreadRadius: 2),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate responsiveness based on card size
                    final double height = constraints.maxHeight;
                    final double width = constraints.maxWidth;
                    final bool isSmall = width < 160 || height < 180;
                    final bool isTiny = width < 140 || height < 140;

                    // Adaptive Font Sizes
                    final double titleSize = isTiny ? 12 : (isSmall ? 13 : 15);
                    final double descSize = isTiny ? 8 : (isSmall ? 9 : 10);
                    final double iconSize = isTiny ? 20 : 24;
                    final double buttonSize = isTiny ? 10 : 12;

                    return Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: isTiny ? 8 : 12,
                          vertical: isTiny ? 6 : 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: EdgeInsets.all(isTiny ? 6 : 8),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle),
                                child: Icon(widget.game.icon,
                                    size: iconSize, color: Colors.white),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: widget.isFavorite
                                    ? S.of(context)!.catalogRemoveFavorite
                                    : S.of(context)!.catalogAddFavorite,
                                onPressed: widget.onFavorite,
                                icon: Icon(
                                  widget.isFavorite
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: SpaceTheme.starYellow,
                                  size: iconSize,
                                ),
                              ),
                            ],
                          ),

                          // TITLE
                          Text(
                            widget.game.title,
                            style: SpaceTheme.headlineStyle
                                .copyWith(fontSize: titleSize),
                            textAlign: TextAlign.center,
                            maxLines: 2, // Allow 2 lines for long German titles
                            overflow: TextOverflow.ellipsis,
                          ),

                          // DESCRIPTION (Hide on tiny screens to prioritize title/button)
                          if (!isTiny)
                            Text(
                              widget.game.description,
                              style: SpaceTheme.bodyStyle
                                  .copyWith(fontSize: descSize),
                              textAlign: TextAlign.center,
                              maxLines: isSmall ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),

                          if (!isTiny)
                            Text(
                              '${widget.categoryLabel} • ~${widget.minutes} min',
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 9),
                            ),

                          // BUTTON
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: isTiny ? 8 : 16,
                                vertical: isTiny ? 4 : 6),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow,
                                    color: Colors.white, size: buttonSize + 2),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    S.of(context)!.launch,
                                    style: SpaceTheme.buttonStyle
                                        .copyWith(fontSize: buttonSize),
                                    maxLines: 1,
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DifficultyButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _DifficultyButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? SpaceTheme.starYellow.withValues(alpha: 0.25)
                : SpaceTheme.deepSpace.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? SpaceTheme.starYellow : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? SpaceTheme.starYellow : Colors.white60),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
