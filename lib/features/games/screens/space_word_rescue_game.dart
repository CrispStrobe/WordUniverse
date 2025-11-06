// lib/features/games/screens/space_word_rescue_game.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../core/models/skill_category.dart';
import '../widgets/space_background.dart';
import '../widgets/game_ui.dart'; 
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

class _SpaceWordRescueGameState extends State<SpaceWordRescueGame>
    with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;

  // Game state
  GermanWord? _currentWord;
  String _userInput = '';
  String _displayedWord = '';
  bool _isWordVisible = true;
  bool _isAnswerChecked = false;
  int _score = 0;
  int _wordsRescued = 0;
  int _wordsLost = 0;
  static const int _totalWords = 10;
  
  // Streak system
  int _currentStreak = 0;
  int _maxStreak = 0;

  // New state variables for feedback
  AnswerResultType _answerResult = AnswerResultType.incorrect;
  String _feedbackMessage = '';
  String _educationalHint = '';
  
  // Progressive hint system
  int _hintsUsed = 0;
  String _currentHintText = '';
  
  // Animation controllers
  late AnimationController _floatController;
  late AnimationController _rescueController;
  late AnimationController _streakController;
  late Animation<double> _floatAnimation;
  late Animation<double> _rescueAnimation;
  late Animation<double> _streakAnimation;
  
  // Timer for word visibility
  Timer? _visibilityTimer;
  Duration _wordVisibleDuration = const Duration(seconds: 3);
  
  // Input controller
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    
    // Adjust difficulty based on grade level
    switch (widget.gradeLevel) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        _wordVisibleDuration = const Duration(seconds: 4);
        break;
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        _wordVisibleDuration = const Duration(seconds: 3);
        break;
      default:
        _wordVisibleDuration = const Duration(seconds: 2);
    }
    
    // Initialize animations
    _floatController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatAnimation = Tween<double>(
      begin: -10.0,
      end: 10.0,
    ).animate(CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeInOut,
    ));
    
    _rescueController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _rescueAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _rescueController,
      curve: Curves.easeOut,
    ));
    
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
    
    if (!_vocabularyService.isInitialized) {
      await _vocabularyService.initialize();
    }
    
    _loadNextWord();
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
      _isWordVisible = true;
      _feedbackMessage = '';
      _educationalHint = '';
      _hintsUsed = 0;
      _currentHintText = '';
    });
    
    final words = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: 5,
    );
    
    if (words.isEmpty) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel);
      if (allWords.isNotEmpty) {
        words.add(allWords[Random().nextInt(allWords.length)]);
      } else {
        debugPrint("CRITICAL: No words found for this grade level.");
        return;
      }
    }
    
    _currentWord = words.first;
    _displayedWord = _currentWord!.displayName;
    
    _audioService.speak(_displayedWord);
    
    _visibilityTimer?.cancel();
    _visibilityTimer = Timer(_wordVisibleDuration, () {
      if (mounted) {
        setState(() {
          _isWordVisible = false;
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
  }

  void _checkAnswer() {
    if (_currentWord == null || _userInput.isEmpty || _isAnswerChecked) return;
    
    final s = S.of(context)!;
    final userInput = _userInput.trim().toLowerCase();
    final correctDisplayName = _currentWord!.displayName.toLowerCase();
    final correctArticle = _currentWord!.article?.toLowerCase();

    bool wasCorrectForSRI = false;
    int scoreGained = 0;

    // 1. Check for perfect match
    if (userInput == correctDisplayName) {
        _answerResult = AnswerResultType.perfect;
        _feedbackMessage = s.gameplayCorrect;
        _educationalHint = _generateEducationalHint(_currentWord!, isPerfect: true);
        wasCorrectForSRI = true;
        scoreGained = 10 - (_hintsUsed * 2); // Penalty for using hints
        scoreGained = max(5, scoreGained); // Minimum 5 points
        
        // Streak bonus
        _currentStreak++;
        if (_currentStreak > _maxStreak) _maxStreak = _currentStreak;
        if (_currentStreak >= 3) {
          scoreGained += 5; // Streak bonus
          _streakController.forward(from: 0.0);
        }
    } 
    // 2. Check for common graphematic mistake
    else {
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
        scoreGained = 5 - (_hintsUsed * 1);
        scoreGained = max(2, scoreGained);
        
        // Break streak on common mistake
        _currentStreak = 0;
      } 
      // 3. It's just plain wrong
      else {
        _answerResult = AnswerResultType.incorrect;
        _feedbackMessage = s.gameplayFeedbackIncorrect(_currentWord!.displayName);
        _educationalHint = _generateEducationalHint(_currentWord!, isIncorrect: true);
        wasCorrectForSRI = false;
        scoreGained = 0;
        
        // Break streak
        _currentStreak = 0;
      }
    }
    
    setState(() {
      _isAnswerChecked = true;
    });
    
    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentWord!.word,
      wasCorrect: wasCorrectForSRI,
      metadata: {
        'gradeLevel': _currentWord!.gradeLevel,
        'wordType': _currentWord!.wordType.toString(),
      },
    );
    
    if (wasCorrectForSRI) {
      _audioService.playSound('correct.mp3');
      _rescueController.forward().then((_) {
        setState(() {
          _wordsRescued++;
          _score += scoreGained;
          context.read<GameProvider>().addScore(scoreGained);
        });
        _rescueController.reset();
        
        // CRITICAL: Shorter delay and ensure focus
        Timer(const Duration(milliseconds: 1200), () {
          _loadNextWord();
        });
      });
    } else {
      _audioService.playSound('incorrect.mp3');
      setState(() {
        _wordsLost++;
      });
      
      // CRITICAL: Ensure focus after delay
      Timer(const Duration(milliseconds: 1800), () {
        _loadNextWord();
      });
    }
  }

  String _generateEducationalHint(GermanWord word, {
    bool isPerfect = false, 
    bool isCommonMistake = false, 
    bool isIncorrect = false
  }) {
    final List<String> hints = [];
    
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
            hints.add(word.genus!);
          }
          break;
        case GermanWordType.verb:
              String? ichForm;
              String? duForm;

              // Try to get the correct conjugation from the inflection data
              if (word.inflectionData != null) {
                try {
                  // Access: data['analyses']['verb']['conjugation']['Präsens']
                  final conjugations = word.inflectionData!['analyses']?['verb']?['conjugation']?['Präsens'] as Map<String, dynamic>?;
                  
                  if (conjugations != null) {
                    ichForm = conjugations['ich'] as String?;
                    duForm = conjugations['du'] as String?;
                  }
                } catch (e) {
                  // Log error if parsing fails, but don't crash
                  debugPrint('Error parsing verb inflectionData for ${word.word}: $e');
                }
              }

              // Use the correct forms if found
              if (ichForm != null && duForm != null) {
                hints.add('ich $ichForm, du $duForm');
              } 
              // Fallback to the old (less accurate) logic if data was missing
              else if (word.word.endsWith('en')) {
                final stem = word.word.substring(0, word.word.length - 2);
                hints.add('ich ${stem}e, du ${stem}st');
              }
              break;
        case GermanWordType.adjektiv:
          hints.add('Steigerbar: ${word.word}');
          break;
        default:
          break;
      }
      
      // Add phonetic info if available
      if (word.ipaPhoneme != null && word.ipaPhoneme!.isNotEmpty) {
        hints.add('IPA: ${word.ipaPhoneme}');
      }
    } else if (isCommonMistake) {
      // Explain the common mistake
      hints.add('Häufiger Fehler! Merke dir: ${word.word}');
      
      // Show the correct grapheme
      if (word.graphematicVariants.isNotEmpty) {
        hints.add('Richtige Schreibweise: ${word.word}');
      }
    } else if (isIncorrect) {
      // Teaching moment
      hints.add('Lerne: ${word.displayName}');
      
      // Show helpful decomposition
      if (word.word.length > 6) {
        // Try to split into syllables (simple heuristic)
        hints.add('Silben helfen beim Merken!');
      }
      
      // Show word type
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
    
    // Add example sentence if available
    if (word.exampleSentences.isNotEmpty && hints.length < 2) {
      hints.add('Beispiel: ${word.exampleSentences.first}');
    }
    
    return hints.isEmpty ? '' : hints.join(' • ');
  }

  void _showProgressiveHint() {
    if (_currentWord == null || _isAnswerChecked) return;
    
    setState(() {
      _hintsUsed++;
      
      if (_hintsUsed == 1) {
        // First hint: Show word again briefly
        _isWordVisible = true;
        Timer(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _isWordVisible = false;
            });
            _focusNode.requestFocus();
          }
        });
        _currentHintText = 'Wort nochmal gezeigt!';
      } else if (_hintsUsed == 2) {
        // Second hint: Show first letter(s)
        final word = _currentWord!.word;
        final firstPart = word.length > 3 ? word.substring(0, 2) : word.substring(0, 1);
        _currentHintText = 'Beginnt mit: $firstPart...';
      } else if (_hintsUsed == 3) {
        // Third hint: Show syllables count or length
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
      _score = max(0, _score - 2);
      context.read<GameProvider>().addScore(-2);
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

  void _showGameOver() {
    context.read<GameProvider>().recordLevelWin(
      gameType: 'space_word_rescue',
      scoreGained: _score,
      difficulty: widget.gradeLevel.index + 1,
      wasSuccessful: _wordsRescued >= (_totalWords * 0.7), 
    );

    final s = S.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        title: Text(
          s.gameOver,
          style: SpaceTheme.headlineStyle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${s.gameplayRescued}: $_wordsRescued/$_totalWords',
              style: SpaceTheme.bodyStyle,
            ),
            const SizedBox(height: 8),
            Text(
              '${s.score}: $_score',
              style: SpaceTheme.titleStyle.copyWith(color: SpaceTheme.starYellow),
            ),
            if (_maxStreak > 1) ...[
              const SizedBox(height: 8),
              Text(
                'Beste Serie: $_maxStreak 🔥',
                style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.planetOrange),
              ),
            ],
            const SizedBox(height: 16),
            _buildRating(),
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
              backgroundColor: SpaceTheme.planetOrange,
            ),
            child: Text(s.playAgain),
          ),
        ],
      ),
    );
  }

  Widget _buildRating() {
    final percentage = (_wordsRescued / _totalWords) * 100;
    String rating;
    int stars;
    final s = S.of(context)!;

    if (percentage >= 90) {
      rating = s.excellent;
      stars = 3;
    } else if (percentage >= 70) {
      rating = s.good;
      stars = 2;
    } else if (percentage >= 50) {
      rating = s.good;
      stars = 1;
    } else {
      rating = s.tryAgain;
      stars = 0;
    }

    return Column(
      children: [
        Text(rating, style: SpaceTheme.headlineStyle.copyWith(fontSize: 20)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return Icon(
              index < stars ? Icons.star : Icons.star_border,
              color: SpaceTheme.starYellow,
              size: 32,
            );
          }),
        ),
      ],
    );
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

  @override
  void dispose() {
    _floatController.dispose();
    _rescueController.dispose();
    _streakController.dispose();
    _visibilityTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    
    Color cardBorderColor = SpaceTheme.planetOrange;
    Color? cardBackgroundColor = SpaceTheme.deepSpace;
    if (_isAnswerChecked) {
      if (_answerResult == AnswerResultType.perfect) {
        cardBorderColor = Colors.green;
        cardBackgroundColor = Colors.green.withOpacity(0.3);
      } else if (_answerResult == AnswerResultType.commonMistake) {
        cardBorderColor = SpaceTheme.starYellow;
        cardBackgroundColor = SpaceTheme.starYellow.withOpacity(0.2);
      } else {
        cardBorderColor = Colors.red;
        cardBackgroundColor = Colors.red.withOpacity(0.3);
      }
    }

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWideScreen = constraints.maxWidth > 800;
              
              return Column(
                children: [
                  GameUI(
                    title: s.spaceWordRescueTitle,
                    level: widget.gradeLevel.index + 1,
                    onBack: () => Navigator.of(context).pop(),
                  ),

                  // Progress bar with streak indicator
                  Container(
                    margin: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${s.gameplayRescued}: $_wordsRescued',
                              style: SpaceTheme.bodyStyle.copyWith(
                                color: SpaceTheme.alienGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // Streak indicator
                            if (_currentStreak >= 2)
                              ScaleTransition(
                                scale: _streakAnimation,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: SpaceTheme.planetOrange,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: SpaceTheme.planetOrange.withOpacity(0.5),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '🔥 $_currentStreak',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            Text(
                              '${s.gameplayLost}: $_wordsLost',
                              style: SpaceTheme.bodyStyle.copyWith(
                                color: SpaceTheme.rocketRed,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: (_wordsRescued + _wordsLost) / _totalWords,
                          backgroundColor: SpaceTheme.deepSpace,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _currentStreak >= 3 
                                ? SpaceTheme.planetOrange 
                                : SpaceTheme.alienGreen,
                          ),
                          minHeight: 8,
                        ),
                      ],
                    ),
                  ),

                  // Main game area
                  Expanded(
                    child: Center(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: isWideScreen ? 700 : 600,
                        ),
                        padding: EdgeInsets.all(isWideScreen ? 32 : 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Floating word
                            if (_currentWord != null)
                              AnimatedBuilder(
                                animation: _floatAnimation,
                                builder: (context, child) {
                                  return Transform.translate(
                                    offset: Offset(0, _floatAnimation.value),
                                    child: FadeTransition(
                                      opacity: _rescueAnimation.drive(
                                        CurveTween(curve: Curves.easeIn),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: cardBackgroundColor,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: cardBorderColor,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: cardBorderColor.withOpacity(0.4),
                                              blurRadius: 24,
                                              spreadRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 300),
                                          child: _isWordVisible || _isAnswerChecked
                                              ? Text(
                                                  _isAnswerChecked &&
                                                          _answerResult !=
                                                              AnswerResultType.perfect
                                                      ? _currentWord!.displayName
                                                      : _displayedWord,
                                                  key: const ValueKey('visible'),
                                                  style: SpaceTheme.headlineStyle
                                                      .copyWith(
                                                    fontSize: 36,
                                                    color: _isAnswerChecked &&
                                                            _answerResult !=
                                                                AnswerResultType.perfect
                                                        ? SpaceTheme.rocketRed
                                                        : Colors.white,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.question_mark_rounded,
                                                  key: ValueKey('hidden'),
                                                  color: Colors.white,
                                                  size: 48,
                                                ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),

                            const SizedBox(height: 32),

                            // Progressive hint display
                            if (_currentHintText.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: SpaceTheme.starYellow.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: SpaceTheme.starYellow,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.lightbulb,
                                      color: SpaceTheme.starYellow,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _currentHintText,
                                      style: SpaceTheme.bodyStyle.copyWith(
                                        color: SpaceTheme.starYellow,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Input field
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
                              style: SpaceTheme.bodyStyle.copyWith(
                                fontSize: 22,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: s.gameplayWriteTheWord,
                                hintStyle: SpaceTheme.bodyStyle
                                    .copyWith(color: Colors.white54),
                                filled: true,
                                fillColor: SpaceTheme.deepSpace.withOpacity(0.7),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: SpaceTheme.planetOrange,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: SpaceTheme.planetOrange,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: SpaceTheme.alienGreen,
                                    width: 3,
                                  ),
                                ),
                                prefixIcon: const Icon(
                                  Icons.edit,
                                  color: Colors.white70,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                              ),
                              textAlign: TextAlign.center,
                              autocorrect: false,
                              enableSuggestions: false,
                            ),

                            const SizedBox(height: 24),

                            // Action buttons
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                // Hint button
                                if (!_isAnswerChecked)
                                  ElevatedButton.icon(
                                    onPressed: _showProgressiveHint,
                                    icon: const Icon(Icons.lightbulb_outline),
                                    label: Text(
                                      '${s.gameplayHint} (-2)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: SpaceTheme.starYellow,
                                      foregroundColor: SpaceTheme.deepSpace,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                    ),
                                  ),

                                // Repeat word button
                                if (!_isWordVisible && !_isAnswerChecked)
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      _audioService.speak(_displayedWord);
                                    },
                                    icon: const Icon(Icons.volume_up),
                                    label: const Text(
                                      'Hören',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: SpaceTheme.cosmicPink,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                    ),
                                  ),

                                // Check button
                                if (!_isAnswerChecked)
                                  ElevatedButton.icon(
                                    onPressed: _userInput.isNotEmpty
                                        ? _checkAnswer
                                        : null,
                                    icon: const Icon(Icons.check_circle),
                                    label: Text(
                                      s.gameplayCheck,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: SpaceTheme.alienGreen,
                                      foregroundColor: SpaceTheme.deepSpace,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 14,
                                      ),
                                      disabledBackgroundColor: Colors.grey.shade700,
                                    ),
                                  ),
                              ],
                            ),

                            // Feedback message
                            if (_isAnswerChecked) ...[
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _answerResult == AnswerResultType.perfect
                                      ? Colors.green.withOpacity(0.2)
                                      : _answerResult ==
                                              AnswerResultType.commonMistake
                                          ? SpaceTheme.starYellow.withOpacity(0.2)
                                          : Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _answerResult ==
                                            AnswerResultType.perfect
                                        ? Colors.green
                                        : _answerResult ==
                                                AnswerResultType.commonMistake
                                            ? SpaceTheme.starYellow
                                            : Colors.red,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _answerResult == AnswerResultType.perfect
                                              ? Icons.check_circle
                                              : _answerResult ==
                                                      AnswerResultType.commonMistake
                                                  ? Icons.warning
                                                  : Icons.cancel,
                                          color: _answerResult ==
                                                  AnswerResultType.perfect
                                              ? Colors.green
                                              : _answerResult ==
                                                      AnswerResultType.commonMistake
                                                  ? SpaceTheme.starYellow
                                                  : Colors.red,
                                          size: 28,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _feedbackMessage,
                                            style: SpaceTheme.bodyStyle.copyWith(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_educationalHint.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      const Divider(color: Colors.white24),
                                      const SizedBox(height: 8),
                                      Text(
                                        _educationalHint,
                                        style: SpaceTheme.bodyStyle.copyWith(
                                          fontSize: 14,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.white70,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// Card widget for menu
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
              s.spaceWordRescueTitle,
              style: SpaceTheme.titleStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              s.spaceWordRescueInstructions,
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}