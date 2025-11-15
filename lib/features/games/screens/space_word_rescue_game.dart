// lib/features/games/screens/space_word_rescue_game.dart

import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'package:provider/provider.dart';

import '../../../core/services/vocabulary_service.dart';
import '../../../core/models/vocabulary_models.dart';

import '../../../core/services/sri_service.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../core/models/skill_category.dart';
import '../widgets/space_background.dart';
// import '../widgets/game_ui.dart'; // No longer used, replaced by _buildTopBar
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';

class SpaceWordRescueGame extends StatefulWidget {
  final GradeLevel gradeLevel;

  const SpaceWordRescueGame({
    Key? key,
    required this.gradeLevel,
  }) : super(key: key);

  @override
  State<SpaceWordRescueGame> createState() => _SpaceWordRescueGameState();
}

enum AnswerResultType {
  perfect,
  commonMistake,
  incorrect
}

class WordParticle {
  Offset position;
  Offset velocity;
  Color color;
  double size;
  double life;

  WordParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    this.life = 1.0,
  });
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

  // --- MERGED: Streak system from HEAD ---
  int _currentStreak = 0;
  int _maxStreak = 0;

  // Feedback State
  AnswerResultType _answerResult = AnswerResultType.incorrect;
  String _feedbackMessage = '';
  String _educationalHint = '';

  // --- MERGED: Progressive hint system from HEAD ---
  int _hintsUsed = 0;
  String _currentHintText = '';

  // Animation controllers
  late AnimationController _scrollController;
  late AnimationController _fadeController;
  late AnimationController _explosionController;
  late AnimationController _rescueController;
  late AnimationController _streakController; // From HEAD
  late Animation<double> _scrollAnimation;
  late Animation<double> _perspectiveAnimation;
  late Animation<double> _streakAnimation; // From HEAD

  // Word scrolling & Fading
  double _wordPosition = 0.0;
  Timer? _fadeTimer;
  int _nextLetterToFade = 0;

  // --- Adjustable fade start time ---

  /// The default start time for fading letters, as a fraction of the total scroll duration.
  /// 0.7 means the fading will start when the word has completed 70% of its scroll.
  /// This is the setting for the easiest level (Grade 1).
  /// (0.5 = mid-screen, 1.0 = bottom of screen).
  static const double _baseFadeStartTimeFactor = 0.4;

  /// How much earlier fading starts for each grade level above Grade 1.
  /// 0.05 means for Grade 2, fading starts 5% earlier (at 65% scroll), 
  /// for Grade 3 it's 10% earlier (at 60% scroll), and so on.
  /// This makes higher levels progressively harder.
  static const double _fadeFactorPerGrade = 0.05;

  /// The absolute earliest the fading can possibly start, as a fraction of the scroll.
  /// This acts as a "floor" or "clamp" for high grade levels.
  /// By setting this to 0.5, we guarantee that fading will
  /// NEVER start before the word has passed mid-screen (50%).
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

  // --- MODIFIED: Timers for non-blocking flow ---
  Timer? _hintTimer;
  static const Duration _transitionDelay = Duration(milliseconds: 500); // For particles
  static const Duration _hintDisplayDuration = Duration(seconds: 4); // Hint stays on screen

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

    // --- Core game animations from 2c4a04c ---
    _scrollController = AnimationController(
      duration: _scrollDuration,
      vsync: this,
    );

    _scrollAnimation = Tween<double>(
      begin: 1.2, // Start below screen
      end: -0.5, // End above screen
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

    // --- MERGED: Streak animation from HEAD ---
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

    // Timer to hide the initial input hint
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
      // Note: We don't clear feedback/hint message here to let it overlap
      _nextLetterToFade = 0;
      _particles.clear();
      // --- MERGED: Reset hint/streak state from HEAD ---
      _hintsUsed = 0;
      _currentHintText = '';
    });

    // Aggressively request focus every time a new word is loaded
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

    // --- MODIFIED: Dynamic fade start time based on grade level ---
    final gradePenalty = widget.gradeLevel.index * _fadeFactorPerGrade;
    final targetFadeFactor = _baseFadeStartTimeFactor - gradePenalty;

    // --- FIX: Correct clamp logic ---
    // The calculated value is clamped BETWEEN the min and base factors.
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

      _audioService.playSound('whoosh.mp3');
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

  String _generateEducationalHint(GermanWord word, {
    bool isPerfect = false,
    bool isCommonMistake = false,
    bool isIncorrect = false
  }) {
    final List<String> hints = [];
    late S s;
    try {
      s = S.of(context)!;
    } catch (e) {
      return ''; // Can't generate hints if context is gone
    }

    if (isPerfect) {
      // Positive reinforcement with educational content
      switch (word.wordType) {
        case GermanWordType.substantiv:
          if (word.article != null) {
            hints.add('✓ ${word.article} ${word.word}');
          }
          if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
            hints.add('Plural: ${word.plural}');
          }
          if (word.genus != null) {
            hints.add('Genus: ${word.genus}');
          }
          break;
        case GermanWordType.verb:
            hints.add('Verb (Tun-Wort)');
            String? ichForm;
            String? duForm;
            String? erForm;

            if (word.inflectionData != null) {
              try {
                final conjugations = word.inflectionData!['analyses']?['verb']?['conjugation']?['Präsens'] as Map<String, dynamic>?;
                if (conjugations != null) {
                  ichForm = conjugations['ich'] as String?;
                  duForm = conjugations['du'] as String?;
                  erForm = conjugations['er/sie/es'] as String?;
                }
              } catch (e) {
                debugPrint('Error parsing verb inflectionData for ${word.word}: $e');
              }
            }

            if (ichForm != null && duForm != null && erForm != null) {
              hints.add('z.B. ich $ichForm, du $duForm, er $erForm');
            }
            else if (word.forms != null && word.forms!.isNotEmpty) {
              hints.add('Formen: ${word.forms}');
            }
            break;
        case GermanWordType.adjektiv:
          hints.add('Adjektiv (Wie-Wort)');
          String? komparativ;
          String? superlativ;

          if (word.inflectionData != null) {
            try {
              final comparison = word.inflectionData!['analyses']?['adjektiv']?['comparison'] as Map<String, dynamic>?;
              if (comparison != null) {
                komparativ = comparison['Komparativ'] as String?;
                superlativ = comparison['Superlativ'] as String?;
              }
            } catch (e) {
                debugPrint('Error parsing adj inflectionData for ${word.word}: $e');
            }
          }
          
          if (komparativ != null && superlativ != null) {
            hints.add('Steigerung: $komparativ, $superlativ');
          }
          else if (word.forms != null && word.forms!.isNotEmpty) {
            hints.add('Steigerung: ${word.forms}');
          }
          break;
        default:
          break;
      }
    } else if (isCommonMistake) {
      hints.add('Häufiger Fehler! Merke dir: ${word.word}');
      if (word.graphematicVariants.isNotEmpty) {
        hints.add('Richtige Schreibweise: ${word.word}');
      }
    } else if (isIncorrect) {
      hints.add('Lerne: ${word.displayName}');
      final typeMap = {
        GermanWordType.substantiv: 'Nomen',
        GermanWordType.verb: 'Verb',
        GermanWordType.adjektiv: 'Adjektiv',
      };
      final type = typeMap[word.wordType];
      if (type != null) {
        hints.add(type);
      }
    }

    if (word.exampleSentences.isNotEmpty && hints.length < 2) {
      hints.add('Beispiel: ${word.exampleSentences.first}');
    }
    
    if (hints.isEmpty && isPerfect) {
      hints.add('✓ ${s.gameplayCorrect}!');
    }

    return hints.join(' • ');
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
      _educationalHint = _generateEducationalHint(_currentWord!, isIncorrect: true);
      _currentStreak = 0; // --- MERGED: Reset streak ---
    });
    
    _hintTimer = Timer(_hintDisplayDuration, () {
      if (mounted) {
        setState(() {
          _feedbackMessage = '';
          _educationalHint = '';
        });
        // CRITICAL: Request focus after word disappears
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      }
    });
    
    // CRITICAL: Request focus immediately
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
    
    _audioService.playSound('incorrect.mp3');
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
          sin(angle) * speed - 2.0, // Upward bias
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
            particle.velocity.dy + 0.2, // Gravity
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
        _educationalHint = _generateEducationalHint(_currentWord!, isPerfect: true);
        wasCorrectForSRI = true;
        
        // --- MERGED: Scoring logic from HEAD ---
        scoreGained = 10 - (_hintsUsed * 2); // Penalty for using hints
        scoreGained = max(5, scoreGained); // Minimum 5 points
        
        // Streak bonus
        _currentStreak++;
        if (_currentStreak > _maxStreak) _maxStreak = _currentStreak;
        if (_currentStreak >= 3) {
          scoreGained += 5; // Streak bonus
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
        _educationalHint = _generateEducationalHint(_currentWord!, isCommonMistake: true);
        wasCorrectForSRI = true;

        // --- MERGED: Scoring logic from HEAD ---
        scoreGained = 5 - (_hintsUsed * 1);
        scoreGained = max(2, scoreGained);
        
        // Break streak on common mistake
        _currentStreak = 0;
      } else {
        _answerResult = AnswerResultType.incorrect;
        _feedbackMessage = s.gameplayFeedbackIncorrect(_currentWord!.displayName);
        _educationalHint = _generateEducationalHint(_currentWord!, isIncorrect: true);
        wasCorrectForSRI = false;
        scoreGained = 0;
        
        // --- MERGED: Break streak from HEAD ---
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
      _audioService.playSound('correct.mp3');
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
      
      _audioService.playSound('incorrect.mp3');
      _createExplosion();
      
      Future.delayed(_transitionDelay, () {
        if (!mounted) return;
        _focusNode.requestFocus();
        _loadNextWord();
      });
    }
  }

  // --- MERGED: Method from HEAD ---
  void _showProgressiveHint() {
    if (_currentWord == null || _isAnswerChecked) return;
    
    setState(() {
      _hintsUsed++;
      
      if (_hintsUsed == 1) {
        // First hint: Repeat audio
        _audioService.speak(_displayedWord);
        _currentHintText = 'Wort noch einmal angehört!';
      } else if (_hintsUsed == 2) {
        // Second hint: Show first letter(s)
        final word = _currentWord!.word;
        final firstPart = word.length > 3 ? word.substring(0, 2) : word.substring(0, 1);
        _currentHintText = 'Beginnt mit: $firstPart...';
      } else if (_hintsUsed == 3) {
        // Third hint: Show length
        _currentHintText = '${_currentWord!.word.length} Buchstaben';
      } else {
        // Final hint: Show the word with blanks
        final word = _currentWord!.word;
        final hint = word.split('').asMap().entries.map((e) {
          return e.key % 2 == 0 ? e.value : '_';
        }).join();
        _currentHintText = hint;
      }
      
      // Penalty
      // _score = max(0, _score - 2); // Penalty is applied on answer
      // context.read<GameProvider>().addScore(-2);
    });
    
    // Clear hint after a delay
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _currentHintText = '';
        });
        _focusNode.requestFocus();
      }
    });
  }

  // --- MERGED: Method from HEAD ---
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
    
    _gameProvider.recordLevelWin(
      gameType: 'space_word_rescue',
      scoreGained: _score,
      difficulty: widget.gradeLevel.index + 1,
      wasSuccessful: _wordsRescued >= (_totalWords * 0.7),
    );
    
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
            
            // --- MERGED: Show Max Streak from HEAD ---
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
            // --- MERGED: Use _resetGame from HEAD ---
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
    _streakController.dispose(); // --- MERGED: from HEAD ---
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
                CustomPaint(
                  painter: ParticlePainter(_particles),
                  size: Size.infinite,
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
                                    final yPos = screenHeight * _scrollAnimation.value;
                                    final scale = _perspectiveAnimation.value;
                                    final opacity = _calculateOpacity(_scrollAnimation.value);
                                    
                                    return Positioned(
                                      left: 0,
                                      right: 0,
                                      top: yPos,
                                      child: Transform(
                                        transform: Matrix4.identity()
                                          ..setEntry(3, 2, 0.001) // Perspective
                                          ..rotateX(-0.3) // Tilt back
                                          ..scale(scale),
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
                                left: 20,
                                right: 20,
                                bottom: keyboardHeight > 0 ? keyboardHeight + 10 : 20,
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
                top: _feedbackMessage.isNotEmpty ? (MediaQuery.of(context).padding.top + 100) : -200.0,
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
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpaceTheme.alienGreen, width: 2),
        boxShadow: [
          BoxShadow(
            color: SpaceTheme.alienGreen.withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: s.backToMenu,
              ),
              Text(s.wordRescueTitle, style: SpaceTheme.titleStyle.copyWith(fontSize: 18)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SpaceTheme.planetOrange.withOpacity(0.8),
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
                  color: SpaceTheme.alienGreen.withOpacity(0.8),
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
            child: Divider(color: SpaceTheme.alienGreen.withOpacity(0.3), height: 1),
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
              
              // --- MERGED: Streak indicator from HEAD ---
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: SpaceTheme.starYellow,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: SpaceTheme.starYellow.withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Text(
        _buildPartialWord(),
        style: SpaceTheme.headlineStyle.copyWith(
          fontFamily: selectedFontFamily,
          fontSize: isLandscape ? 36 : 48,
          color: SpaceTheme.starYellow,
          fontWeight: FontWeight.bold,
          letterSpacing: 4,
          shadows: [
            Shadow(
              color: SpaceTheme.starYellow.withOpacity(0.8),
              blurRadius: 20,
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: SpaceTheme.alienGreen,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: SpaceTheme.alienGreen.withOpacity(0.3),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: _showInputHint ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _showInputHint ? null : 0,
              child: Text(
                s.wordRescueTypeWord,
                style: SpaceTheme.bodyStyle.copyWith(
                  color: SpaceTheme.starYellow,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          if (_showInputHint) const SizedBox(height: 12),
          TextField(
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
              fontSize: isLandscape ? 20 : 24,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: s.wordRescueTypeHere,
              hintStyle: SpaceTheme.bodyStyle.copyWith(
                color: Colors.white38,
              ),
              filled: true,
              fillColor: SpaceTheme.deepSpace.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: SpaceTheme.alienGreen,
                  width: 2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: SpaceTheme.alienGreen,
                  width: 2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: SpaceTheme.starYellow,
                  width: 3,
                ),
              ),
              prefixIcon: Icon(
                Icons.edit,
                color: SpaceTheme.alienGreen,
              ),
              suffixIcon: _userInput.isNotEmpty && !_isAnswerChecked
                  ? IconButton(
                      icon: Icon(Icons.send, color: SpaceTheme.alienGreen),
                      onPressed: _checkAnswer,
                    )
                  : null,
            ),
            textAlign: TextAlign.center,
            autocorrect: false,
            enableSuggestions: false,
          ),

          // --- MERGED: Progressive hint display from HEAD ---
          if (_currentHintText.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SpaceTheme.starYellow.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: SpaceTheme.starYellow,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lightbulb,
                    color: SpaceTheme.starYellow,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentHintText,
                    style: SpaceTheme.bodyStyle.copyWith(
                      fontFamily: selectedFontFamily,
                      color: SpaceTheme.starYellow,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          // --- MERGED: Action buttons from HEAD ---
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              // Hint button
              if (!_isAnswerChecked)
                ElevatedButton.icon(
                  onPressed: _showProgressiveHint,
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: Text(
                    '${s.gameplayHint} (-2)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SpaceTheme.starYellow,
                    foregroundColor: SpaceTheme.deepSpace,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),

              // Repeat word button
              if (!_isAnswerChecked)
                ElevatedButton.icon(
                  onPressed: () {
                    _audioService.speak(_displayedWord);
                    _focusNode.requestFocus();
                  },
                  icon: const Icon(Icons.volume_up, size: 18),
                  label: const Text(
                    'Hören',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SpaceTheme.cosmicPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
            ],
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
        width: 300, // Increased width for longer hints
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
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
            // --- Display the educational hint ---
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

// Particle painter for explosion/success effects
class ParticlePainter extends CustomPainter {
  final List<WordParticle> particles;
  
  ParticlePainter(this.particles);
  
  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final paint = Paint()
        ..color = particle.color.withOpacity(particle.life)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        particle.position,
        particle.size * particle.life,
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(ParticlePainter oldDelegate) => true;
}

// Menu card widget
class SpaceWordRescueCard extends StatelessWidget {
  final VoidCallback onTap;

  const SpaceWordRescueCard({
    Key? key,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SpaceTheme.planetOrange.withOpacity(0.8),
              SpaceTheme.cosmicPink.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: SpaceTheme.planetOrange.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.rocket_launch,
              size: 48,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              s.wordRescueTitle,
              style: SpaceTheme.titleStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              s.wordRescueCardDescription,
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}