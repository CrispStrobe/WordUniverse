// ignore_for_file: unused_element, unused_field
// lib/features/games/screens/space_word_rescue_game.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'package:provider/provider.dart';

import '../../../core/services/vocabulary_service.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../core/models/skill_category.dart';
import '../services/space_word_rescue_hints.dart';
import '../widgets/space_background.dart';
import '../widgets/space_word_rescue_widgets.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../models/game_outcome.dart';

class SpaceWordRescueGame extends StatefulWidget {
  final GradeLevel gradeLevel;

  const SpaceWordRescueGame({
    Key? key,
    required this.gradeLevel,
  }) : super(key: key);

  @override
  State<SpaceWordRescueGame> createState() => _SpaceWordRescueGameState();
}

class _SpaceWordRescueGameState extends State<SpaceWordRescueGame>
    with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game state
  GermanWord? _currentWord;
  String _userInput = '';
  String _displayedWord = '';
  List<bool> _visibleLetters = [];
  bool _isAnswerChecked = false;
  int _score = 0;
  int _wordsRescued = 0;
  int _wordsLost = 0;
  static const int _totalWords = 10;
  bool _showInputHint = true;

  // Streak system
  int _currentStreak = 0;
  int _maxStreak = 0;

  // Feedback State
  AnswerResultType _answerResult = AnswerResultType.incorrect;
  String _feedbackMessage = '';
  String _educationalHint = '';

  // Progressive hint system
  int _hintsUsed = 0;
  String _currentHintText = '';

  // Animation controllers
  late AnimationController _scrollController;
  late AnimationController _fadeController;
  late AnimationController _explosionController;
  late AnimationController _rescueController;
  late AnimationController _streakController;
  late Animation<double> _scrollAnimation;
  late Animation<double> _perspectiveAnimation;
  late Animation<double> _streakAnimation;

  // Word scrolling & Fading
  double _wordPosition = 0.0;
  Timer? _fadeTimer;
  int _nextLetterToFade = 0;

  // Adjustable fade start time
  static const double _baseFadeStartTimeFactor = 0.4;
  static const double _fadeFactorPerGrade = 0.05;
  static const double _minFadeStartTimeFactor = 0.4;

  // Particles for effects
  List<WordParticle> _particles = [];
  Timer? _particleTimer;

  // Input controller
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Timing
  late Duration _scrollDuration;
  late Duration _letterFadeInterval;

  // Timers for non-blocking flow
  Timer? _hintTimer;
  static const Duration _transitionDelay = Duration(milliseconds: 500);
  static const Duration _hintDisplayDuration = Duration(seconds: 4);

  // Screen detection helpers
  bool _isSmallScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortestSide = size.shortestSide;
    return shortestSide < 600;
  }

  bool _isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }

  bool _isCompactMode(BuildContext context) {
    return _isSmallScreen(context) && _isPortrait(context);
  }

  bool _isLandscapeMode(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  @override
  void initState() {
    super.initState();

    final baseScrollSeconds = 12.0;
    final scrollDifficultyFactor = 1.0 - (widget.gradeLevel.index * 0.1);
    final adjustedScrollSeconds = (baseScrollSeconds * scrollDifficultyFactor).clamp(5.0, 10.0);
    _scrollDuration = Duration(milliseconds: (adjustedScrollSeconds * 1000).round());

    final baseFadeMs = 700.0;
    final fadeDifficultyFactor = 1.0 - (widget.gradeLevel.index * 0.12);
    final adjustedFadeMs = (baseFadeMs * fadeDifficultyFactor).clamp(300.0, 700.0);
    _letterFadeInterval = Duration(milliseconds: adjustedFadeMs.round());

    _scrollController = AnimationController(
      duration: _scrollDuration,
      vsync: this,
    );

    _scrollAnimation = Tween<double>(
      begin: 1.2,
      end: -0.5,
    ).animate(CurvedAnimation(
      parent: _scrollController,
      curve: Curves.linear,
    ));

    _perspectiveAnimation = Tween<double>(
      begin: 0.5,
      end: 1.5,
    ).animate(CurvedAnimation(
      parent: _scrollController,
      curve: Curves.easeOut,
    ));

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _explosionController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _rescueController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _scrollController.addListener(_checkWordPosition);
    _scrollController.addStatusListener(_handleScrollComplete);

    _streakController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _streakAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _streakController,
      curve: Curves.elasticOut,
    ));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  Future<void> _initializeGame() async {
    _vocabularyService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();

    if (!_vocabularyService.isInitialized) {
      await _vocabularyService.initialize();
    }

    _loadNextWord();

    Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showInputHint = false;
        });
      }
    });
  }

  void _loadNextWord() {
    if (_wordsRescued + _wordsLost >= _totalWords) {
      _showGameOver();
      return;
    }

    setState(() {
      _userInput = '';
      _textController.clear();
      _isAnswerChecked = false;
      _nextLetterToFade = 0;
      _particles.clear();
      _hintsUsed = 0;
      _currentHintText = '';
    });

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    final words = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: 5,
      settingsProvider: _gameProvider,
    );

    if (words.isEmpty) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
      if (allWords.isNotEmpty) {
        words.add(allWords[Random().nextInt(allWords.length)]);
      }
    }

    _currentWord = words.first;
    _displayedWord = _currentWord!.displayName;
    _visibleLetters = List.filled(_displayedWord.length, true);

    _audioService.speak(_displayedWord);

    _scrollController.forward(from: 0.0);

    _fadeTimer?.cancel();

    final gradePenalty = widget.gradeLevel.index * _fadeFactorPerGrade;
    final targetFadeFactor = _baseFadeStartTimeFactor - gradePenalty;
    final fadeStartTimeFactor = targetFadeFactor.clamp(_minFadeStartTimeFactor, _baseFadeStartTimeFactor);
    
    _fadeTimer = Timer(Duration(milliseconds: (_scrollDuration.inMilliseconds * fadeStartTimeFactor).round()), () {
      _startFadingLetters();
    });
  }

  void _startFadingLetters() {
    if (_nextLetterToFade >= _displayedWord.length) return;

    Timer.periodic(_letterFadeInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_nextLetterToFade >= _displayedWord.length || _isAnswerChecked) {
        timer.cancel();
        return;
      }

      setState(() {
        _visibleLetters[_nextLetterToFade] = false;
        _nextLetterToFade++;
      });

      _audioService.playSound('whoosh');
    });
  }

  void _checkWordPosition() {
    final position = _scrollAnimation.value;

    if (position < -0.3 && !_isAnswerChecked) {
      _wordLost();
    }
  }

  void _handleScrollComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_isAnswerChecked) {
      _wordLost();
    }
  }

  void _wordLost() {
    if (_isAnswerChecked) return;
    
    final s = S.of(context)!;
    
    _hintTimer?.cancel();
    
    setState(() {
      _isAnswerChecked = true;
      _wordsLost++;
      _feedbackMessage = s.wordRescueFeedbackLost;
      _answerResult = AnswerResultType.incorrect;
      _educationalHint = generateEducationalHint(context, _currentWord!, isIncorrect: true);
      _currentStreak = 0;
    });
    
    _hintTimer = Timer(_hintDisplayDuration, () {
      if (mounted) {
        setState(() {
          _feedbackMessage = '';
          _educationalHint = '';
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      }
    });
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
    
    _scrollController.stop();
    _fadeTimer?.cancel();
    
    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentWord!.displayName,
      wasCorrect: false,
      metadata: {
        'gradeLevel': widget.gradeLevel.index + 1,
      },
    );
    
    _audioService.playSound('failure');
    HapticFeedback.heavyImpact();
    _createExplosion();

    Future.delayed(_transitionDelay, () {
      if (!mounted) return;
      _focusNode.requestFocus();
      _loadNextWord();
    });
  }

  void _createExplosion() {
    _explosionController.forward(from: 0.0);
    
    final random = Random();
    final centerX = MediaQuery.of(context).size.width / 2;
    final centerY = MediaQuery.of(context).size.height * 0.2;
    
    for (int i = 0; i < 30; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final speed = 2.0 + random.nextDouble() * 4.0;
      
      _particles.add(WordParticle(
        position: Offset(centerX, centerY),
        velocity: Offset(
          cos(angle) * speed,
          sin(angle) * speed,
        ),
        color: [SpaceTheme.rocketRed, SpaceTheme.planetOrange][random.nextInt(2)],
        size: 4.0 + random.nextDouble() * 6.0,
      ));
    }
    
    _startParticleAnimation();
  }

  void _createRescueEffect() {
    _rescueController.forward(from: 0.0);
    
    final random = Random();
    final centerX = MediaQuery.of(context).size.width / 2;
    final centerY = MediaQuery.of(context).size.height * 0.7;
    
    for (int i = 0; i < 40; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final speed = 1.5 + random.nextDouble() * 3.0;
      
      _particles.add(WordParticle(
        position: Offset(centerX, centerY),
        velocity: Offset(
          cos(angle) * speed,
          sin(angle) * speed - 2.0,
        ),
        color: [SpaceTheme.alienGreen, SpaceTheme.starYellow][random.nextInt(2)],
        size: 3.0 + random.nextDouble() * 5.0,
      ));
    }
    
    _startParticleAnimation();
  }

  void _startParticleAnimation() {
    _particleTimer?.cancel();
    _particleTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_particles.isEmpty) {
        timer.cancel();
        return;
      }
      
      setState(() {
        for (var particle in _particles) {
          particle.position += particle.velocity;
          particle.velocity = Offset(
            particle.velocity.dx,
            particle.velocity.dy + 0.2,
          );
          particle.life -= 0.02;
        }
        
        _particles.removeWhere((p) => p.life <= 0);
      });
    });
  }

  void _checkAnswer() {
    if (_currentWord == null || _userInput.isEmpty || _isAnswerChecked) return;
    
    _scrollController.stop();
    _fadeTimer?.cancel();
    
    final s = S.of(context)!;
    final userInput = _userInput.trim().toLowerCase();
    final correctDisplayName = _currentWord!.displayName.toLowerCase();
    final correctArticle = _currentWord!.article?.toLowerCase();

    bool wasCorrectForSRI = false;
    int scoreGained = 0;
    
    _hintTimer?.cancel();

    if (userInput == correctDisplayName) {
        _answerResult = AnswerResultType.perfect;
        _feedbackMessage = s.gameplayCorrect;
        _educationalHint = generateEducationalHint(context, _currentWord!, isPerfect: true);
        wasCorrectForSRI = true;
        
        scoreGained = 10 - (_hintsUsed * 2);
        scoreGained = max(5, scoreGained);
        
        _currentStreak++;
        if (_currentStreak > _maxStreak) _maxStreak = _currentStreak;
        if (_currentStreak >= 3) {
          scoreGained += 5;
          _streakController.forward(from: 0.0);
        }
    } else {
      String userWordPart = userInput;

      if (correctArticle != null && userInput.startsWith("$correctArticle ")) {
        userWordPart = userInput.substring(correctArticle.length + 1);
      }
      
      if (_currentWord!.graphematicVariants
          .any((v) => v.spelling.toLowerCase() == userWordPart)) {
        _answerResult = AnswerResultType.commonMistake;
        _feedbackMessage = s.gameplayFeedbackCommonMistake(_currentWord!.displayName);
        _educationalHint = generateEducationalHint(context, _currentWord!, isCommonMistake: true);
        wasCorrectForSRI = true;

        scoreGained = 5 - (_hintsUsed * 1);
        scoreGained = max(2, scoreGained);
        
        _currentStreak = 0;
      } else {
        _answerResult = AnswerResultType.incorrect;
        _feedbackMessage = s.gameplayFeedbackIncorrect(_currentWord!.displayName);
        _educationalHint = generateEducationalHint(context, _currentWord!, isIncorrect: true);
        wasCorrectForSRI = false;
        scoreGained = 0;
        
        _currentStreak = 0;
      }
    }
    
    setState(() {
      _isAnswerChecked = true;
    });
    
    _hintTimer = Timer(_hintDisplayDuration, () {
      if (mounted) {
        setState(() {
          _feedbackMessage = '';
          _educationalHint = '';
        });
      }
    });
    
    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentWord!.displayName,
      wasCorrect: wasCorrectForSRI,
      metadata: {
        'gradeLevel': widget.gradeLevel.index + 1,
      },
    );
    
    if (wasCorrectForSRI) {
      setState(() {
        _score += scoreGained;
        _wordsRescued++;
      });
      
      _gameProvider.addScore(scoreGained);
      _audioService.playSound('success');
      HapticFeedback.lightImpact();
      _audioService.speak(_currentWord!.displayName);
      
      _createRescueEffect();
      
      Future.delayed(_transitionDelay, () {
        if (!mounted) return;
        _focusNode.requestFocus();
        _loadNextWord();
      });
    } else {
      setState(() {
        _wordsLost++;
      });
      
      _audioService.playSound('failure');
      HapticFeedback.heavyImpact();
      _createExplosion();
      
      Future.delayed(_transitionDelay, () {
        if (!mounted) return;
        _focusNode.requestFocus();
        _loadNextWord();
      });
    }
  }

  void _showProgressiveHint() {
    if (_currentWord == null || _isAnswerChecked) return;
    
    setState(() {
      _hintsUsed++;
      
      if (_hintsUsed == 1) {
        _audioService.speak(_displayedWord);
        _currentHintText = 'Wort noch einmal angehört!';
      } else if (_hintsUsed == 2) {
        final word = _currentWord!.word;
        final firstPart = word.length > 3 ? word.substring(0, 2) : word.substring(0, 1);
        _currentHintText = 'Beginnt mit: $firstPart...';
      } else if (_hintsUsed == 3) {
        _currentHintText = '${_currentWord!.word.length} Buchstaben';
      } else {
        final word = _currentWord!.word;
        final hint = word.split('').asMap().entries.map((e) {
          return e.key % 2 == 0 ? e.value : '_';
        }).join();
        _currentHintText = hint;
      }
    });
    
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _currentHintText = '';
        });
        _focusNode.requestFocus();
      }
    });
  }

  void _resetGame() {
    setState(() {
      _score = 0;
      _wordsRescued = 0;
      _wordsLost = 0;
      _currentStreak = 0;
      _maxStreak = 0;
      _userInput = '';
      _textController.clear();
      _feedbackMessage = '';
      _educationalHint = '';
      _hintsUsed = 0;
      _currentHintText = '';
    });
    _loadNextWord();
  }

  void _showGameOver() {
    final s = S.of(context)!;
    final percentage = (_wordsRescued / _totalWords * 100).round();
    
    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'space_word_rescue',
      difficulty: widget.gradeLevel.index + 1,
      score: _score,
      wasSuccessful: _wordsRescued >= (_totalWords * 0.7),
    ));
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        title: Text(s.gameOver, style: SpaceTheme.titleStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _wordsRescued >= (_totalWords * 0.7) ? Icons.star : Icons.rocket_launch,
              size: 64,
              color: _wordsRescued >= (_totalWords * 0.7)
                  ? SpaceTheme.starYellow
                  : SpaceTheme.planetOrange,
            ),
            
            if (_maxStreak > 1) ...[
              const SizedBox(height: 8),
              Text(
                'Beste Serie: $_maxStreak 🔥',
                style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.planetOrange),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '${s.score}: $_score',
              style: SpaceTheme.headlineStyle.copyWith(
                color: SpaceTheme.alienGreen,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.wordRescueGameOverStats(_wordsRescued, _totalWords, percentage),
              style: SpaceTheme.bodyStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: Text(s.backToMenu),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetGame();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.alienGreen,
            ),
            child: Text(s.playAgain),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    _explosionController.dispose();
    _rescueController.dispose();
    _streakController.dispose();
    _fadeTimer?.cancel();
    _particleTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    final String selectedFontFamily = context.watch<GameProvider>().selectedFontFamily;
    
    return Scaffold(
      resizeToAvoidBottomInset: false, 
      body: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: SpaceBackground(
          child: Stack(
            children: [
              if (_particles.isNotEmpty)
                ExcludeSemantics(
                  child: CustomPaint(
                    painter: ParticlePainter(_particles),
                    size: Size.infinite,
                  ),
                ),
              
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape = constraints.maxWidth > constraints.maxHeight;

                    return Column(
                      children: [
                        _buildTopBar(s),
                        
                        Expanded(
                          child: Stack(
                            children: [
                              if (_currentWord != null && !_isAnswerChecked)
                                AnimatedBuilder(
                                  animation: _scrollController,
                                  builder: (context, child) {
                                    final isCompact = _isCompactMode(context);
                                    final scrollValue = _scrollAnimation.value;
                                    final adjustedScrollValue = isCompact 
                                        ? scrollValue * 0.7
                                        : scrollValue;
                                    
                                    final yPos = screenHeight * adjustedScrollValue;
                                    final scale = _perspectiveAnimation.value * (isCompact ? 0.8 : 1.0);
                                    final opacity = _calculateOpacity(adjustedScrollValue);
                                    
                                    return Positioned(
                                      left: 0,
                                      right: 0,
                                      top: yPos,
                                      child: Transform(
                                        transform: Matrix4.identity()
                                          ..setEntry(3, 2, 0.001)
                                          ..rotateX(isCompact ? -0.2 : -0.3)
                                          ..scaleByDouble(scale, scale, scale, 1.0),
                                        alignment: Alignment.center,
                                        child: Opacity(
                                          opacity: opacity,
                                          child: _buildScrollingWord(
                                            isLandscape: isLandscape,
                                            selectedFontFamily: selectedFontFamily,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 100),
                                curve: Curves.easeOut,
                                left: _isCompactMode(context) ? 10 : (_isLandscapeMode(context) ? 16 : 20),
                                right: _isCompactMode(context) ? 10 : (_isLandscapeMode(context) ? 16 : 20),
                                bottom: _isCompactMode(context) 
                                    ? (keyboardHeight > 0 ? keyboardHeight + 5 : 10)
                                    : (_isLandscapeMode(context) 
                                        ? (keyboardHeight > 0 ? keyboardHeight + 8 : 12)
                                        : (keyboardHeight > 0 ? keyboardHeight + 10 : 20)),
                                child: _buildInputArea(
                                  s,
                                  isLandscape: isLandscape,
                                  selectedFontFamily: selectedFontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                ),
              ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                top: _feedbackMessage.isNotEmpty 
                    ? (MediaQuery.of(context).padding.top + (_isLandscapeMode(context) ? 60 : 100))
                    : -200.0,
                right: 20.0,
                child: _buildFeedbackToast(
                  s,
                  selectedFontFamily: selectedFontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(S s) {
    final totalScore = context.watch<GameProvider>().score;
    final isCompact = _isCompactMode(context);
    final isLandscapeLayout = _isLandscapeMode(context);
    
    if (isCompact) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SpaceTheme.alienGreen, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Semantics(
              label: 'Zurück',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            Semantics(
              label: 'Punkte: $_score',
              child: _buildCompactStat(Icons.stars, '$_score', SpaceTheme.starYellow),
            ),
            if (_currentStreak >= 2)
              Semantics(
                label: 'Serie: $_currentStreak',
                child: _buildCompactStat(Icons.local_fire_department, '$_currentStreak', SpaceTheme.planetOrange),
              ),
            Semantics(
              label: 'Gerettet: $_wordsRescued von $_totalWords',
              child: _buildCompactStat(Icons.check_circle, '$_wordsRescued/$_totalWords', SpaceTheme.alienGreen),
            ),
            Semantics(
              label: 'Stufe ${widget.gradeLevel.index + 1}',
              container: true,
              child: _buildCompactStat(Icons.military_tech, '${widget.gradeLevel.index + 1}', SpaceTheme.planetOrange),
            ),
          ],
        ),
      );
    }
    
    if (isLandscapeLayout) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SpaceTheme.alienGreen, width: 2),
          boxShadow: [
            BoxShadow(
              color: SpaceTheme.alienGreen.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          children: [
            Semantics(
              label: 'Zurück',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: s.backToMenu,
                padding: const EdgeInsets.all(8),
              ),
            ),

            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                s.wordRescueTitle,
                style: SpaceTheme.titleStyle.copyWith(fontSize: 16),
              ),
            ),
            
            const Spacer(),
            
            _buildCompactStat(Icons.stars, '$_score', SpaceTheme.starYellow),
            const SizedBox(width: 8),
            
            if (_currentStreak >= 2) ...[
              ScaleTransition(
                scale: _streakAnimation,
                child: _buildCompactStat(Icons.local_fire_department, '$_currentStreak', SpaceTheme.planetOrange),
              ),
              const SizedBox(width: 8),
            ],
            
            _buildCompactStat(Icons.check_circle, '$_wordsRescued', SpaceTheme.alienGreen),
            const SizedBox(width: 4),
            _buildCompactStat(Icons.cancel, '$_wordsLost', SpaceTheme.rocketRed),
            const SizedBox(width: 8),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: SpaceTheme.planetOrange.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.military_tech, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.gradeLevel.index + 1}',
                    style: SpaceTheme.bodyStyle.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpaceTheme.alienGreen, width: 2),
        boxShadow: [
          BoxShadow(
            color: SpaceTheme.alienGreen.withValues(alpha: 0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Semantics(
                label: 'Zurück',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: s.backToMenu,
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(s.wordRescueTitle, style: SpaceTheme.titleStyle.copyWith(fontSize: 18)),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SpaceTheme.planetOrange.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.military_tech, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${s.level}: ${widget.gradeLevel.index + 1}',
                      style: SpaceTheme.bodyStyle.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SpaceTheme.alienGreen.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.scoreboard, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${s.score}: $totalScore',
                      style: SpaceTheme.bodyStyle.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: Divider(color: SpaceTheme.alienGreen.withValues(alpha: 0.3), height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Row(
                children: [
                  Icon(Icons.stars, color: SpaceTheme.starYellow, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Punkte: $_score',
                    style: SpaceTheme.bodyStyle.copyWith(
                      color: SpaceTheme.starYellow,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              
              if (_currentStreak >= 2)
                ScaleTransition(
                  scale: _streakAnimation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: SpaceTheme.planetOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '🔥 $_currentStreak',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),

              Row(
                children: [
                  Icon(Icons.check_circle, color: SpaceTheme.alienGreen, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '$_wordsRescued',
                    style: SpaceTheme.bodyStyle.copyWith(
                      color: SpaceTheme.alienGreen,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.cancel, color: SpaceTheme.rocketRed, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '$_wordsLost',
                    style: SpaceTheme.bodyStyle.copyWith(
                      color: SpaceTheme.rocketRed,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  double _calculateOpacity(double position) {
    if (position < -0.2) {
      return 1.0 - ((position + 0.2).abs() / 0.3).clamp(0.0, 1.0);
    }
    if (position > 0.8) {
      return 1.0 - ((position - 0.8) / 0.4).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  Widget _buildScrollingWord({required bool isLandscape, required String selectedFontFamily}) {
    final isCompact = _isCompactMode(context);
    final isLandscapeLayout = _isLandscapeMode(context);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 20 : (isLandscapeLayout ? 30 : 40),
        vertical: isCompact ? 10 : (isLandscapeLayout ? 15 : 20),
      ),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: isLandscapeLayout ? 0.95 : 0.8),
        borderRadius: BorderRadius.circular(isCompact ? 12 : (isLandscapeLayout ? 16 : 20)),
        border: Border.all(
          color: SpaceTheme.starYellow,
          width: isCompact ? 2 : (isLandscapeLayout ? 3 : 3),
        ),
        boxShadow: [
          BoxShadow(
            color: SpaceTheme.starYellow.withValues(alpha: 0.6),
            blurRadius: isCompact ? 15 : (isLandscapeLayout ? 25 : 30),
            spreadRadius: isCompact ? 2 : (isLandscapeLayout ? 4 : 5),
          ),
        ],
      ),
      child: Text(
        _buildPartialWord(),
        style: SpaceTheme.headlineStyle.copyWith(
          fontFamily: selectedFontFamily,
          fontSize: isCompact ? 28 : (isLandscapeLayout ? 40 : 48),
          color: SpaceTheme.starYellow,
          fontWeight: FontWeight.bold,
          letterSpacing: isCompact ? 2 : (isLandscapeLayout ? 3 : 4),
          shadows: [
            Shadow(
              color: SpaceTheme.starYellow.withValues(alpha: 0.8),
              blurRadius: isCompact ? 10 : (isLandscapeLayout ? 20 : 20),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _buildPartialWord() {
    String result = '';
    for (int i = 0; i < _displayedWord.length; i++) {
      if (_visibleLetters[i]) {
        result += _displayedWord[i];
      } else {
        result += '_';
      }
    }
    return result;
  }

  Widget _buildInputArea(S s, {required bool isLandscape, required String selectedFontFamily}) {
    final isCompact = _isCompactMode(context);
    final isLandscapeLayout = _isLandscapeMode(context);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : (isLandscapeLayout ? 16 : 20),
        vertical: isCompact ? 8 : (isLandscapeLayout ? 10 : 20),
      ),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: isLandscapeLayout ? 0.85 : 0.95),
        borderRadius: BorderRadius.circular(isCompact ? 12 : (isLandscapeLayout ? 16 : 20)),
        border: Border.all(
          color: SpaceTheme.alienGreen,
          width: isCompact ? 1.5 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: SpaceTheme.alienGreen.withValues(alpha: 0.3),
            blurRadius: isCompact ? 10 : 20,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCompact && !isLandscapeLayout && _showInputHint) ...[
            AnimatedOpacity(
              opacity: _showInputHint ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Text(
                s.wordRescueTypeWord,
                style: SpaceTheme.bodyStyle.copyWith(
                  color: SpaceTheme.starYellow,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Tippe das Wort hier ein',
                  textField: true,
                  child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: !_isAnswerChecked,
                  onChanged: (value) {
                    setState(() {
                      _userInput = value;
                    });
                  },
                  onSubmitted: (_) => _checkAnswer(),
                  style: SpaceTheme.headlineStyle.copyWith(
                    fontFamily: selectedFontFamily,
                    fontSize: isCompact ? 18 : (isLandscapeLayout ? 20 : 24),
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: s.wordRescueTypeHere,
                    hintStyle: SpaceTheme.bodyStyle.copyWith(
                      color: Colors.white38,
                      fontSize: isCompact ? 14 : (isLandscapeLayout ? 16 : 16),
                    ),
                    filled: true,
                    fillColor: SpaceTheme.deepSpace.withValues(alpha: 0.5),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 12 : (isLandscapeLayout ? 16 : 16),
                      vertical: isCompact ? 10 : (isLandscapeLayout ? 12 : 16),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(isCompact ? 8 : (isLandscapeLayout ? 10 : 12)),
                      borderSide: BorderSide(
                        color: SpaceTheme.alienGreen,
                        width: 2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(isCompact ? 8 : (isLandscapeLayout ? 10 : 12)),
                      borderSide: BorderSide(
                        color: SpaceTheme.alienGreen,
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(isCompact ? 8 : (isLandscapeLayout ? 10 : 12)),
                      borderSide: BorderSide(
                        color: SpaceTheme.starYellow,
                        width: 3,
                      ),
                    ),
                    prefixIcon: Icon(
                      Icons.edit,
                      color: SpaceTheme.alienGreen,
                      size: isCompact ? 18 : (isLandscapeLayout ? 20 : 24),
                    ),
                    suffixIcon: _userInput.isNotEmpty && !_isAnswerChecked
                        ? IconButton(
                            icon: Icon(Icons.send, color: SpaceTheme.alienGreen, size: isCompact ? 18 : (isLandscapeLayout ? 20 : 24)),
                            onPressed: _checkAnswer,
                            padding: EdgeInsets.zero,
                          )
                        : null,
                  ),
                  textAlign: TextAlign.center,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                ),
              ),

              if (!_isAnswerChecked) ...[
                const SizedBox(width: 8),

                Semantics(
                  label: 'Tipp anzeigen',
                  button: true,
                  child: Material(
                    color: SpaceTheme.starYellow,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: _showProgressiveHint,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: EdgeInsets.all(isCompact ? 8 : (isLandscapeLayout ? 10 : 12)),
                        child: Icon(
                          Icons.lightbulb_outline,
                          color: SpaceTheme.deepSpace,
                          size: isCompact ? 18 : (isLandscapeLayout ? 20 : 22),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                Semantics(
                  label: 'Wort vorlesen',
                  button: true,
                  child: Material(
                    color: SpaceTheme.cosmicPink,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () {
                        _audioService.speak(_displayedWord);
                        _focusNode.requestFocus();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: EdgeInsets.all(isCompact ? 8 : (isLandscapeLayout ? 10 : 12)),
                        child: Icon(
                          Icons.volume_up,
                          color: Colors.white,
                          size: isCompact ? 18 : (isLandscapeLayout ? 20 : 22),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (_currentHintText.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: isCompact ? 6 : (isLandscapeLayout ? 8 : 12)),
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 8 : (isLandscapeLayout ? 10 : 12),
                vertical: isCompact ? 4 : (isLandscapeLayout ? 6 : 8),
              ),
              decoration: BoxDecoration(
                color: SpaceTheme.starYellow.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SpaceTheme.starYellow),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lightbulb,
                    color: SpaceTheme.starYellow,
                    size: isCompact ? 14 : (isLandscapeLayout ? 14 : 16),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _currentHintText,
                      style: SpaceTheme.bodyStyle.copyWith(
                        fontFamily: selectedFontFamily,
                        color: SpaceTheme.starYellow,
                        fontWeight: FontWeight.bold,
                        fontSize: isCompact ? 12 : (isLandscapeLayout ? 12 : 14),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedbackToast(S s, {required String selectedFontFamily}) {
    if (_feedbackMessage.isEmpty) { 
      return const SizedBox.shrink();
    }
    
    final isSuccess = _answerResult == AnswerResultType.perfect || 
                      _answerResult == AnswerResultType.commonMistake;
    
    final color = isSuccess 
        ? (_answerResult == AnswerResultType.perfect ? Colors.green : SpaceTheme.starYellow)
        : SpaceTheme.rocketRed;
    
    final icon = isSuccess
        ? (_answerResult == AnswerResultType.perfect ? Icons.star : Icons.thumb_up)
        : Icons.close;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              _feedbackMessage,
              style: SpaceTheme.bodyStyle.copyWith(
                fontFamily: selectedFontFamily,
                fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (_educationalHint.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Divider(color: Colors.white24),
              ),
              Text(
                _educationalHint,
                style: SpaceTheme.bodyStyle.copyWith(
                  fontFamily: selectedFontFamily,
                  fontSize: 14, 
                  fontStyle: FontStyle.italic,
                  color: Colors.white70
                ),
                textAlign: TextAlign.center,
              ),
            ]
          ],
        ),
      ),
    );
  }
}
