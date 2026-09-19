import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/word_features.dart';
import '../services/sentence_completion_service.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../models/game_outcome.dart';
import '../providers/game_provider.dart';
import '../widgets/cefr_chip.dart';
import '../widgets/etymology_banner.dart';
import '../widgets/space_background.dart';
import '../../../shared/widgets/onboarding_overlay.dart';

class SentenceCompletionGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const SentenceCompletionGame({super.key, required this.gradeLevel});

  @override
  State<SentenceCompletionGame> createState() =>
      _SentenceCompletionGameState();
}



enum _FeedbackState { none, correct, incorrect }

class _SentenceCompletionGameState extends State<SentenceCompletionGame>
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
  List<SentenceChallenge> _challenges = [];
  int _currentIndex = 0;
  int _score = 0;
  int _correct = 0;
  int? _selectedOption;
  _FeedbackState _feedbackState = _FeedbackState.none;

  late AnimationController _pulseController;
  late AnimationController _shakeController;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    _s = S.of(context)!;
    _vocabularyService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();
    if (!_vocabularyService.isInitialized) await _vocabularyService.initialize();
    await _buildChallenges();
    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'sentence_completion',
        title: _s.sentenceCompletionTitle,
        steps: [
          OnboardingStep(
            icon: Icons.edit,
            body: _s.sentenceCompletionOnboardingBody1,
          ),
          OnboardingStep(
            icon: Icons.school,
            body: _s.sentenceCompletionOnboardingBody2,
          ),
          OnboardingStep(
            icon: Icons.tips_and_updates,
            body: _s.sentenceCompletionOnboardingBody3,
          ),
        ],
      );
    }
  }

  // Only blank content words — nouns, verbs, adjectives are uniquely
  // identifiable from sentence context. Adverbs, prepositions, and other
  // function words are too substitutable (multiple fillers are valid).
  static const _contentTypes = {
    GermanWordType.substantiv,
    GermanWordType.verb,
    GermanWordType.adjektiv,
  };

  Future<void> _buildChallenges() async {
    final gradeIndex = widget.gradeLevel.index + 1;

    // Content words only, with grade examples; exclude proper nouns (Vornamen,
    // Ortsnamen) which produce odd fill-in-the-blank challenges.
    //
    // Carrying grade examples at all is answered by the feature index, so only
    // these candidates have their enrichment decoded; whether the examples
    // cover *this* grade still needs the real data, so it is re-checked once
    // the pool comes back hydrated.
    final allWords = (await _vocabularyService.takeWordsWithFeature(
      WordFeature.gradeExamples,
      settingsProvider: _gameProvider,
      gradeLevel: gradeIndex,
      limit: _totalRounds * 10,
      where: (w) =>
          _contentTypes.contains(w.wordType) &&
          !w.isProperNoun &&
          !w.word.contains('_') &&
          !w.word.contains(' '),
      random: _rng,
    ))
        .where((w) => hasGradeExamples(w, gradeIndex))
        .toList();
    if (!mounted) return;

    if (allWords.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final challenges = buildSentenceChallenges(
      pool: allWords,
      gradeIndex: gradeIndex,
      maxChallenges: _totalRounds,
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
      _isLoading = false;
    });
  }





  // Returns (before, after) splitting the sentence at the found word token,
  // or null if the word cannot be found in the sentence.






  void _handleTap(int optionIndex) {
    if (_feedbackState != _FeedbackState.none) return;

    final challenge = _challenges[_currentIndex];
    final isCorrect = optionIndex == challenge.correctIndex;

    setState(() {
      _selectedOption = optionIndex;
      _feedbackState =
          isCorrect ? _FeedbackState.correct : _FeedbackState.incorrect;
    });

    if (isCorrect) {
      _gameProvider.hapticLight();
      _audioService.playSound('success');
      _pulseController.forward(from: 0);
      _score += 10;
      _correct++;
      _sriService.recordResponse(
        skillType: LanguageSkillType.sentenceStructure,
        baseWord: challenge.word.word,
        wasCorrect: true,
      );
    } else {
      _gameProvider.hapticMedium();
      _audioService.playSound('error');
      _shakeController
          .forward(from: 0)
          .then((_) => _shakeController.reverse());
      _sriService.recordResponse(
        skillType: LanguageSkillType.sentenceStructure,
        baseWord: challenge.word.word,
        wasCorrect: false,
      );
    }

    Future.delayed(const Duration(milliseconds: 2200), () {
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
    });
  }

  void _showGameOver() {
    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'sentence_completion',
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
              '$_correct / ${_challenges.length}',
              style: SpaceTheme.titleStyle
                  .copyWith(color: SpaceTheme.starYellow, fontSize: 28),
            ),
            const SizedBox(height: 4),
            Text(
              _s.correct,
              style: SpaceTheme.bodyStyle.copyWith(color: Colors.white70),
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

  // ─── Build ────────────────────────────────────────────────────────────────

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
          _s.noClozeSentences,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  _s.sentenceCompletionPrompt,
                  style: SpaceTheme.headlineStyle
                      .copyWith(color: Colors.white, fontSize: 17),
                  textAlign: TextAlign.center,
                ),
                if (challenge.word.cefrLevel != null) ...[
                  const SizedBox(height: 6),
                  CefrChip(challenge.word.cefrLevel!),
                ],
                const SizedBox(height: 20),
                _buildSentenceCard(challenge),
                const SizedBox(height: 24),
                _buildOptions(challenge),
                if (_feedbackState == _FeedbackState.incorrect) ...[
                  const SizedBox(height: 12),
                  _buildCorrectWordHint(challenge),
                ],
                if (_feedbackState == _FeedbackState.correct) ...[
                  const SizedBox(height: 12),
                  EtymologyBanner(word: challenge.word),
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
                  _s.sentenceCompletionTitle,
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  '${_currentIndex + 1} / ${_challenges.length}',
                  style:
                      SpaceTheme.bodyStyle.copyWith(color: Colors.white60),
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

  Widget _buildSentenceCard(SentenceChallenge challenge) {
    const blankText = '___________';
    final blankColor = _feedbackState == _FeedbackState.correct
        ? SpaceTheme.alienGreen
        : _feedbackState == _FeedbackState.incorrect
            ? Colors.redAccent
            : SpaceTheme.starYellow;

    // Determine what to show in the blank after answer
    final fillText = _feedbackState != _FeedbackState.none
        ? challenge.correctOption
        : blankText;

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final shake = _feedbackState == _FeedbackState.incorrect
            ? sin(_shakeController.value * pi * 5) * 6
            : 0.0;
        return Transform.translate(
          offset: Offset(shake, 0),
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _feedbackState == _FeedbackState.correct
                ? SpaceTheme.alienGreen
                : _feedbackState == _FeedbackState.incorrect
                    ? Colors.redAccent
                    : SpaceTheme.nebulaPurple.withValues(alpha: 0.5),
            width: _feedbackState != _FeedbackState.none ? 2 : 1,
          ),
        ),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
              height: 1.5,
            ),
            children: [
              TextSpan(text: challenge.before),
              TextSpan(
                text: fillText,
                style: TextStyle(
                  color: blankColor,
                  fontWeight: FontWeight.bold,
                  decoration: _feedbackState == _FeedbackState.none
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: blankColor,
                ),
              ),
              TextSpan(text: challenge.after),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptions(SentenceChallenge challenge) {
    return Column(
      children: List.generate(challenge.options.length, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildOption(challenge, i),
        );
      }),
    );
  }

  Widget _buildOption(SentenceChallenge challenge, int index) {
    final option = challenge.options[index];
    final isSelected = _selectedOption == index;
    final isCorrect = index == challenge.correctIndex;
    final hasAnswered = _feedbackState != _FeedbackState.none;

    Color borderColor = SpaceTheme.moonSilver.withValues(alpha: 0.4);
    Color bgColor = SpaceTheme.deepSpace.withValues(alpha: 0.6);
    Color textColor = Colors.white;
    IconData? trailingIcon;

    if (hasAnswered) {
      if (isCorrect) {
        borderColor = Colors.green;
        bgColor = Colors.green.withValues(alpha: 0.2);
        trailingIcon = Icons.check_circle;
      } else if (isSelected) {
        borderColor = Colors.redAccent;
        bgColor = Colors.red.withValues(alpha: 0.15);
        textColor = Colors.redAccent;
        trailingIcon = Icons.cancel;
      }
    } else if (isSelected) {
      borderColor = SpaceTheme.starYellow;
      bgColor = SpaceTheme.starYellow.withValues(alpha: 0.1);
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = (hasAnswered && isCorrect)
            ? 1.0 + (_pulseController.value * 0.03)
            : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: Semantics(
        button: true,
        label: option,
        child: GestureDetector(
          onTap: () => _handleTap(index),
          child: Container(
            width: double.infinity,
            // Enforce the 48dp minimum touch target for accessibility.
            constraints: const BoxConstraints(minHeight: 48),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (trailingIcon != null)
                  Icon(trailingIcon,
                      color: isCorrect ? Colors.green : Colors.redAccent,
                      size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCorrectWordHint(SentenceChallenge challenge) {
    final hint = _s.correctAnswerReveal(challenge.correctOption);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.alienGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: SpaceTheme.alienGreen.withValues(alpha: 0.4)),
      ),
      child: Text(
        hint,
        style: SpaceTheme.bodyStyle
            .copyWith(color: SpaceTheme.alienGreen, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}
