// lib/features/games/screens/spelling_spotter_game.dart
//
// Spelling Spotter — EN-only game using commonLearnerErrors data.
// Shows 4 spelling options (1 correct + 3 misspellings); player taps the
// correctly spelled word. 10 rounds, grade-filtered.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/word_features.dart';
import '../services/spelling_spotter_challenges.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../models/game_outcome.dart';
import '../providers/game_provider.dart';
import '../services/spelling_spotter_service.dart';
import '../widgets/cefr_chip.dart';
import '../widgets/space_background.dart';
import '../widgets/spelling_strategy_badge.dart';
import '../../../shared/widgets/onboarding_overlay.dart';

class SpellingSpotterGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const SpellingSpotterGame({super.key, required this.gradeLevel});

  @override
  State<SpellingSpotterGame> createState() => _SpellingSpotterGameState();
}



enum _FeedbackState { none, correct, incorrect }

class _SpellingSpotterGameState extends State<SpellingSpotterGame>
    with TickerProviderStateMixin {
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;
  late S _s;

  static const int _totalRounds = 10;
  static const int _optionCount = 4;

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<SpellingChallenge> _challenges = [];
  int _currentIndex = 0;
  int _score = 0;
  int _correct = 0;
  int? _selectedOption;
  _FeedbackState _feedbackState = _FeedbackState.none;
  bool _showContext = false;

  late AnimationController _pulseController;
  late AnimationController _shakeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shakeAnimation;

  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _shakeAnimation = Tween<double>(begin: -8.0, end: 8.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  bool get _isDE => _vocabularyService.learningLanguage == 'de';

  Future<void> _init() async {
    setState(() => _isLoading = true);
    _s = S.of(context)!;
    _vocabularyService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();

    if (!_vocabularyService.isInitialized) {
      await _vocabularyService.initialize();
    }
    _buildChallenges();
    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'spelling_spotter',
        title: _s.spellingSpotterTitle,
        steps: [
          OnboardingStep(
            icon: Icons.spellcheck,
            body: _s.spellingSpotterOnboardingBody1,
          ),
          OnboardingStep(
            icon: Icons.school,
            body: _s.spellingSpotterOnboardingBody2,
          ),
        ],
      );
    }
  }

  static String _norm(String w) => normWord(w);

  Future<void> _buildChallenges() async {
    // Whether a word has recorded learner errors at all is answered by the
    // feature index (EN commonLearnerErrors / DE commonMistakes); the exact
    // test still runs, on the hydrated pool.
    final allWords = (await _vocabularyService.takeWordsWithFeature(
      WordFeature.learnerErrors,
      settingsProvider: _gameProvider,
      gradeLevel: widget.gradeLevel.index + 1,
      limit: _totalRounds * 20,
      where: (w) => !w.isProperNoun,
      random: _rng,
    ))
        .where((w) => hasSpellingErrors(w, isGerman: _isDE))
        .toList();
    if (!mounted) return;

    if (allWords.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // Already grade-first, from the pool query.
    final challenges = buildSpellingChallenges(
      pool: allWords,
      isGerman: _isDE,
      gradeLevel: widget.gradeLevel.index + 1,
      rounds: _totalRounds,
      optionCount: _optionCount,
      rng: _rng,
    );

    setState(() {
      _challenges = challenges;
      _currentIndex = 0;
      _score = 0;
      _correct = 0;
      _selectedOption = null;
      _feedbackState = _FeedbackState.none;
      _showContext = false;
      _isLoading = false;
    });
  }






  void _handleTap(int optionIndex) {
    if (_feedbackState != _FeedbackState.none) return;

    final challenge = _challenges[_currentIndex];
    final isCorrect = optionIndex == challenge.correctIndex;

    setState(() {
      _selectedOption = optionIndex;
      _feedbackState =
          isCorrect ? _FeedbackState.correct : _FeedbackState.incorrect;
      _showContext = false;
    });

    if (isCorrect) {
      _gameProvider.hapticLight();
      _audioService.playSound('success');
      _pulseController.forward(from: 0);
      _score += 10;
      _correct++;
      _sriService.recordResponse(
        skillType: LanguageSkillType.spelling,
        baseWord: challenge.word.word,
        wasCorrect: true,
      );
    } else {
      _gameProvider.hapticMedium();
      _audioService.playSound('error');
      _shakeController.forward(from: 0).then((_) => _shakeController.reverse());
      _sriService.recordResponse(
        skillType: LanguageSkillType.spelling,
        baseWord: challenge.word.word,
        wasCorrect: false,
      );
    }

    // Reveal the explanation panel (example sentence + strategy badge / common
    // mistakes) after a short beat. Show it on every answer, correct or wrong,
    // even when no example sentence is available, so the strategy hint always
    // surfaces.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _showContext = true);
    });

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      _advance();
    });
  }

  void _advance() {
    if (_currentIndex + 1 >= _challenges.length) {
      _showGameOver();
      return;
    }
    setState(() {
      _currentIndex++;
      _selectedOption = null;
      _feedbackState = _FeedbackState.none;
      _showContext = false;
    });
  }

  void _showGameOver() {
    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'spelling_spotter',
      difficulty: widget.gradeLevel.index + 1,
      score: _score,
      wasSuccessful: _correct >= (_challenges.length * 0.7),
    ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_s.gameOver, style: SpaceTheme.headlineStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_correct / ${_challenges.length} ${_s.correct}',
              style: SpaceTheme.titleStyle
                  .copyWith(color: SpaceTheme.starYellow),
            ),
            const SizedBox(height: 8),
            Text('${_s.score}: $_score', style: SpaceTheme.bodyStyle),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text(_s.backToMenu),
          ),
          ElevatedButton(
            autofocus: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              _buildChallenges();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: SpaceTheme.planetOrange),
            child: Text(_s.playAgain),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _challenges.isEmpty
                  ? _buildEmptyState()
                  : _buildGame(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _s.noSpellingData,
          style: SpaceTheme.bodyStyle,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildGame() {
    final challenge = _challenges[_currentIndex];
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                const SizedBox(height: 12),
                _buildPrompt(challenge),
                const SizedBox(height: 28),
                _buildOptions(challenge),
                const SizedBox(height: 16),
                if (_showContext && challenge.contextSentence != null)
                  _buildContext(challenge),
                // Show the spelling-strategy explanation after BOTH correct and
                // wrong answers — the pedagogical hint matters most right after
                // a mistake.
                if (_showContext &&
                    _feedbackState != _FeedbackState.none) ...[
                  const SizedBox(height: 8),
                  SpellingStrategyBadge(word: challenge.word),
                  if (!_isDE) ...[
                    const SizedBox(height: 6),
                    _buildEnMisspellingsNote(challenge.word),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s.spellingSpotterTitle,
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  '${_currentIndex + 1} / ${_challenges.length}',
                  style: SpaceTheme.bodyStyle.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          Text(
            '${_s.score}: $_score',
            style: SpaceTheme.bodyStyle
                .copyWith(color: SpaceTheme.starYellow, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPrompt(SpellingChallenge challenge) {
    final definition = challenge.word.displayDefinitions.firstOrNull;
    final cefr = challenge.word.cefrLevel;
    return Column(
      children: [
        Text(
          _s.spellingSpotterPrompt,
          style: SpaceTheme.headlineStyle
              .copyWith(color: Colors.white, fontSize: 18),
          textAlign: TextAlign.center,
        ),
        if (cefr != null) ...[
          const SizedBox(height: 6),
          CefrChip(cefr),
        ],
        if (definition != null) ...[
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: SpaceTheme.deepSpace.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: SpaceTheme.moonSilver.withValues(alpha: 0.3)),
            ),
            child: Text(
              '"$definition"',
              style: SpaceTheme.bodyStyle.copyWith(
                color: Colors.white70,
                fontStyle: FontStyle.italic,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }


  Widget _buildOptions(SpellingChallenge challenge) {
    return Column(
      children: List.generate(challenge.options.length, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildOption(challenge, i),
        );
      }),
    );
  }

  Widget _buildOption(SpellingChallenge challenge, int index) {
    final option = challenge.options[index];
    final isSelected = _selectedOption == index;
    final isCorrect = index == challenge.correctIndex;
    final hasAnswered = _feedbackState != _FeedbackState.none;

    Color borderColor = SpaceTheme.moonSilver.withValues(alpha: 0.4);
    Color bgColor = SpaceTheme.deepSpace.withValues(alpha: 0.6);
    Color textColor = Colors.white;
    IconData? icon;

    if (hasAnswered) {
      if (isCorrect) {
        borderColor = Colors.green;
        bgColor = Colors.green.withValues(alpha: 0.2);
        icon = Icons.check_circle;
        textColor = Colors.green.shade200;
      } else if (isSelected) {
        borderColor = SpaceTheme.rocketRed;
        bgColor = SpaceTheme.rocketRed.withValues(alpha: 0.2);
        icon = Icons.cancel;
        textColor = SpaceTheme.rocketRed;
      } else {
        borderColor = SpaceTheme.moonSilver.withValues(alpha: 0.2);
        bgColor = SpaceTheme.deepSpace.withValues(alpha: 0.3);
        textColor = Colors.white38;
      }
    } else if (isSelected) {
      borderColor = SpaceTheme.starYellow;
      bgColor = SpaceTheme.starYellow.withValues(alpha: 0.15);
    }

    Widget tile = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            option,
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );

    // a11y: expose each option as a button (≥48dp tap target enforced above).
    tile = Semantics(
      button: true,
      enabled: !hasAnswered,
      label: option,
      child: hasAnswered
          ? tile
          : GestureDetector(
              onTap: () => _handleTap(index),
              child: tile,
            ),
    );

    if (hasAnswered && isCorrect && _feedbackState == _FeedbackState.correct) {
      tile = ScaleTransition(scale: _pulseAnimation, child: tile);
    }
    if (hasAnswered && isSelected && !isCorrect) {
      tile = AnimatedBuilder(
        animation: _shakeAnimation,
        builder: (_, child) => Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        ),
        child: tile,
      );
    }

    return tile;
  }

  Widget _buildEnMisspellingsNote(GermanWord word) {
    final errors = word.apiEnrichment?.commonLearnerErrors ?? [];
    if (errors.isEmpty) return const SizedBox.shrink();
    final topErrors = errors
        .map(_norm)
        .where((e) => e.isNotEmpty && !e.contains(' '))
        .take(3)
        .toList();
    if (topErrors.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 12, color: Colors.white38),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _s.spellingSpotterCommonMistakes(topErrors.join(' • ')),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContext(SpellingChallenge challenge) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: _showContext ? 1.0 : 0.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: SpaceTheme.nebulaPurple.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: SpaceTheme.starYellow.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _s.exampleLabel,
              style: SpaceTheme.bodyStyle.copyWith(
                color: SpaceTheme.starYellow,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              challenge.contextSentence ?? '',
              style: SpaceTheme.bodyStyle.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
