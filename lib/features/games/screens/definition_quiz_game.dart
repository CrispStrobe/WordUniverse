import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
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

class DefinitionQuizGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const DefinitionQuizGame({super.key, required this.gradeLevel});

  @override
  State<DefinitionQuizGame> createState() => _DefinitionQuizGameState();
}

class _DefChallenge {
  final GermanWord word;
  final String definition;
  final List<String> options; // display labels, shuffled
  final int correctIndex;

  const _DefChallenge({
    required this.word,
    required this.definition,
    required this.options,
    required this.correctIndex,
  });
}

enum _FeedbackState { none, correct, incorrect }

class _DefinitionQuizGameState extends State<DefinitionQuizGame>
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
  List<_DefChallenge> _challenges = [];
  int _currentIndex = 0;
  int _score = 0;
  int _correct = 0;
  int? _selectedOption;
  _FeedbackState _feedbackState = _FeedbackState.none;
  // Bumped each time we answer; the delayed auto-advance captures the value at
  // schedule time and bails out if a tap-to-advance already moved us on, so a
  // stale timer can't skip the next round.
  int _advanceToken = 0;

  late AnimationController _pulseController;
  late AnimationController _shakeController;

  final _rng = Random();

  bool get _isDE => _vocabularyService.learningLanguage == 'de';

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
    _buildChallenges();
    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'definition_quiz',
        title: _s.definitionQuizTitle,
        steps: [
          OnboardingStep(
            icon: Icons.menu_book,
            body: _s.definitionQuizOnboardingBody1,
          ),
          OnboardingStep(
            icon: Icons.school,
            body: _s.definitionQuizOnboardingBody2,
          ),
          OnboardingStep(
            icon: Icons.tips_and_updates,
            body: _s.definitionQuizOnboardingBody3,
          ),
        ],
      );
    }
  }

  void _buildChallenges() {
    final gradeIndex = widget.gradeLevel.index + 1;

    // Words with at least one definition; skip proper nouns (names produce
    // definitions like "a given name" which make trivial / odd challenges).
    final allWords = _vocabularyService
        .getAllWords(_gameProvider)
        .where((w) =>
            !w.isProperNoun &&
            (w.apiEnrichment?.definitions.isNotEmpty ?? false))
        .toList();

    if (allWords.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // Prefer same-grade words; SRI weights handled by shuffle + grade filter
    final gradeWords = allWords
        .where((w) => w.gradeLevel == gradeIndex)
        .toList()
      ..shuffle(_rng);
    // Shuffle each candidate list exactly once; copy `allWords` so the shared
    // list isn't mutated. (The old `? : ..shuffle` cascade double-shuffled
    // gradeWords and read as if it shuffled allWords.)
    final List<GermanWord> pool;
    if (gradeWords.length >= _totalRounds) {
      pool = gradeWords;
    } else {
      pool = allWords.toList()..shuffle(_rng);
    }

    final challenges = <_DefChallenge>[];
    for (final word in pool) {
      if (challenges.length >= _totalRounds) break;
      final c = _buildChallenge(word, allWords);
      if (c != null) challenges.add(c);
    }

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

  _DefChallenge? _buildChallenge(GermanWord word, List<GermanWord> pool) {
    final defs = word.apiEnrichment?.definitions ?? [];
    if (defs.isEmpty) return null;

    // Pick a definition that's reasonably short for display and — crucially —
    // does not contain the headword (many dictionary glosses start with it,
    // which would give the answer away). Redact any residual occurrence.
    final wl = word.word.toLowerCase();
    String def = defs.firstWhere(
      (d) => d.length <= 120 && !d.toLowerCase().contains(wl),
      orElse: () => defs.firstWhere(
        (d) => d.length <= 120,
        orElse: () => defs.first,
      ),
    );
    def = def.replaceAll(
      RegExp(RegExp.escape(word.word), caseSensitive: false),
      '___',
    );

    final correctOption = _displayOption(word);

    final distractors = _pickDistractors(word, correctOption, pool);
    if (distractors.length < _optionCount - 1) return null;

    final options = [correctOption, ...distractors.take(_optionCount - 1)];
    options.shuffle(_rng);
    final correctIndex = options.indexOf(correctOption);
    if (correctIndex < 0) return null;

    return _DefChallenge(
      word: word,
      definition: def,
      options: options,
      correctIndex: correctIndex,
    );
  }

  String _displayOption(GermanWord w) {
    if (_isDE && w.wordType == GermanWordType.substantiv &&
        w.article != null && w.article!.isNotEmpty) {
      return '${w.article} ${w.word}';
    }
    return w.word;
  }

  List<String> _pickDistractors(
      GermanWord target, String correctOption, List<GermanWord> pool) {
    final distractors = <String>{};

    // Same CEFR level and word type first (most plausible distractors)
    final sameLevel = pool
        .where((w) =>
            w.id != target.id &&
            w.cefrLevel == target.cefrLevel &&
            w.wordType == target.wordType)
        .toList()
      ..shuffle(_rng);
    for (final w in sameLevel) {
      final opt = _displayOption(w);
      if (opt != correctOption) distractors.add(opt);
      if (distractors.length >= _optionCount - 1) break;
    }

    // Same word type, same grade
    if (distractors.length < _optionCount - 1) {
      final same = pool
          .where((w) =>
              w.id != target.id &&
              w.wordType == target.wordType &&
              w.gradeLevel == target.gradeLevel)
          .toList()
        ..shuffle(_rng);
      for (final w in same) {
        final opt = _displayOption(w);
        if (opt != correctOption && !distractors.contains(opt)) {
          distractors.add(opt);
        }
        if (distractors.length >= _optionCount - 1) break;
      }
    }

    // Any word with a definition as final fallback
    if (distractors.length < _optionCount - 1) {
      final any = pool
          .where((w) => w.id != target.id)
          .toList()
        ..shuffle(_rng);
      for (final w in any) {
        final opt = _displayOption(w);
        if (opt != correctOption && !distractors.contains(opt)) {
          distractors.add(opt);
        }
        if (distractors.length >= _optionCount - 1) break;
      }
    }

    return distractors.toList();
  }

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
        skillType: LanguageSkillType.vocabulary,
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
        skillType: LanguageSkillType.vocabulary,
        baseWord: challenge.word.word,
        wasCorrect: false,
      );
    }

    final token = ++_advanceToken;
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted || token != _advanceToken) return;
      _advance();
    });
  }

  // Tap anywhere during the feedback window to advance immediately; invalidates
  // the pending auto-advance timer so it won't fire again on the next round.
  void _handleAdvanceTap() {
    if (_feedbackState == _FeedbackState.none) return;
    _advanceToken++;
    _advance();
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
      gameType: 'definition_quiz',
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
          _s.noDefinitionData,
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
          // After answering, a tap anywhere in the body advances immediately
          // (auto-advance stays a fallback). Translucent so taps on empty space
          // register; option taps are consumed by their own GestureDetector.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _handleAdvanceTap,
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Text(
                    _s.definitionQuizPrompt,
                    style: SpaceTheme.headlineStyle
                        .copyWith(color: Colors.white, fontSize: 17),
                    textAlign: TextAlign.center,
                  ),
                  if (challenge.word.cefrLevel != null) ...[
                    const SizedBox(height: 6),
                    CefrChip(challenge.word.cefrLevel!),
                  ],
                  const SizedBox(height: 16),
                  _buildDefinitionCard(challenge),
                  const SizedBox(height: 20),
                  _buildOptions(challenge),
                  if (_feedbackState == _FeedbackState.incorrect) ...[
                    const SizedBox(height: 10),
                    _buildCorrectHint(challenge),
                  ],
                  if (_feedbackState == _FeedbackState.correct) ...[
                    const SizedBox(height: 10),
                    EtymologyBanner(word: challenge.word),
                  ],
                ],
              ),
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
                  _s.definitionQuizTitle,
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

  Widget _buildDefinitionCard(_DefChallenge challenge) {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final shake = _feedbackState == _FeedbackState.incorrect
            ? sin(_shakeController.value * pi * 5) * 6
            : 0.0;
        return Transform.translate(offset: Offset(shake, 0), child: child);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _feedbackState == _FeedbackState.correct
                ? SpaceTheme.alienGreen
                : _feedbackState == _FeedbackState.incorrect
                    ? Colors.redAccent
                    : SpaceTheme.cosmicPink.withValues(alpha: 0.5),
            width: _feedbackState != _FeedbackState.none ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: SpaceTheme.cosmicPink.withValues(alpha: 0.15),
              blurRadius: 12,
            ),
          ],
        ),
        child: Text(
          challenge.definition,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 16,
            color: Colors.white,
            height: 1.5,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildOptions(_DefChallenge challenge) {
    return Column(
      children: List.generate(challenge.options.length, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildOption(challenge, i),
        );
      }),
    );
  }

  Widget _buildOption(_DefChallenge challenge, int index) {
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
        // After answering, options are inert: announce their resolved state
        // (selected = this is the correct option) and mark them disabled.
        enabled: hasAnswered ? false : null,
        selected: hasAnswered ? isCorrect : null,
        child: GestureDetector(
          onTap: () => _handleTap(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Container(
              width: double.infinity,
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
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _buildCorrectHint(_DefChallenge challenge) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.alienGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: SpaceTheme.alienGreen.withValues(alpha: 0.4)),
      ),
      child: Text(
        _s.correctAnswerReveal(challenge.options[challenge.correctIndex]),
        style: SpaceTheme.bodyStyle
            .copyWith(color: SpaceTheme.alienGreen, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

}
