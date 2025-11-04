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

// Enum for the different types of answer results
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

  // New state variables for feedback
  AnswerResultType _answerResult = AnswerResultType.incorrect;
  String _feedbackMessage = '';
  
  // Animation controllers
  late AnimationController _floatController;
  late AnimationController _rescueController;
  late Animation<double> _floatAnimation;
  late Animation<double> _rescueAnimation;
  
  // Timer for word visibility
  Timer? _visibilityTimer;
  static const Duration _wordVisibleDuration = Duration(seconds: 3);
  
  // Input controller
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    
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
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  Future<void> _initializeGame() async {
    // Service references
    _vocabularyService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    
    if (!_vocabularyService.isInitialized) {
      await _vocabularyService.initialize();
    }
    
    _loadNextWord();
    _focusNode.requestFocus();
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
      _feedbackMessage = ''; // Clear feedback
    });

    // Request focus on the input field for the next word
    _focusNode.requestFocus(); 
    
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
        wasCorrectForSRI = true;
        scoreGained = 10;
    } 
    // 2. Check for common graphematic mistake
    else {
      String userWordPart = userInput;

      // If the word has an article, check if the user typed it.
      // If they did, strip it so we only check the word part.
      if (correctArticle != null && userInput.startsWith("$correctArticle ")) {
          userWordPart = userInput.substring(correctArticle.length + 1);
      }
      
      // Now check if this extracted word part is in the common mistakes
      if (_currentWord!.graphematicVariants
          .any((v) => v.spelling.toLowerCase() == userWordPart)) {
        
        _answerResult = AnswerResultType.commonMistake;
        _feedbackMessage = s.gameplayFeedbackCommonMistake(_currentWord!.displayName);
        wasCorrectForSRI = true; // Still "correct" for SRI, but gets partial points
        scoreGained = 5; // Partial credit
      } 
      // 3. It's just plain wrong
      else {
        _answerResult = AnswerResultType.incorrect;
        _feedbackMessage = s.gameplayFeedbackIncorrect(_currentWord!.displayName);
        wasCorrectForSRI = false;
        scoreGained = 0;
      }
    }
    
    setState(() {
      _isAnswerChecked = true;
    });
    
    // Record the attempt in the SRI service
    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentWord!.word, // Log the base word for SRI
      wasCorrect: wasCorrectForSRI, // Only perfect/common mistakes pass
      metadata: {
        'gradeLevel': _currentWord!.gradeLevel,
        'wordType': _currentWord!.wordType.toString(),
      },
    );
    
    // Handle game logic based on result
    if (wasCorrectForSRI) {
      _audioService.playSound('correct.mp3');
      _rescueController.forward().then((_) {
        setState(() {
          _wordsRescued++;
          _score += scoreGained;
          context.read<GameProvider>().addScore(scoreGained);
        });
        _rescueController.reset();
        Timer(const Duration(seconds: 1), _loadNextWord);
      });
    } else {
      _audioService.playSound('incorrect.mp3');
      setState(() {
        _wordsLost++;
      });
      // Give the user time to read the feedback
      Timer(const Duration(seconds: 2), _loadNextWord);
    }
  }

  void _showHint() {
    if (_currentWord == null) return;
    
    setState(() {
      _isWordVisible = true;
    });
    
    Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isWordVisible = false;
        });
      }
    });
    
    setState(() {
      _score = max(0, _score - 2);
      context.read<GameProvider>().addScore(-2);
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
              style: SpaceTheme.titleStyle,
            ),
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
      _userInput = '';
      _textController.clear();
      _feedbackMessage = '';
    });
    _loadNextWord();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _floatController.dispose();
    _rescueController.dispose();
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
          child: Column(
            children: [
              GameUI(
                title: s.spaceWordRescueTitle,
                level: widget.gradeLevel.index + 1,
                onBack: () => Navigator.of(context).pop(),
              ),

              // Progress bar
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
                          ),
                        ),
                        Text(
                          '${s.gameplayLost}: $_wordsLost',
                          style: SpaceTheme.bodyStyle.copyWith(
                            color: SpaceTheme.rocketRed,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_wordsRescued + _wordsLost) / _totalWords,
                      backgroundColor: SpaceTheme.deepSpace,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        SpaceTheme.planetOrange,
                      ),
                    ),
                  ],
                ),
              ),

              // Main game area
              Expanded(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 600),
                    padding: const EdgeInsets.all(24),
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
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              cardBorderColor.withOpacity(0.3),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      child: _isWordVisible || _isAnswerChecked
                                          ? Text(
                                              // Show the correct word on fail
                                              _isAnswerChecked &&
                                                      _answerResult !=
                                                          AnswerResultType
                                                              .perfect
                                                  ? _currentWord!.displayName
                                                  : _displayedWord,
                                              key: const ValueKey('visible'),
                                              style: SpaceTheme.headlineStyle
                                                  .copyWith(
                                                fontSize: 32,
                                                color: _isAnswerChecked &&
                                                        _answerResult !=
                                                            AnswerResultType
                                                                .perfect
                                                    ? SpaceTheme.rocketRed
                                                    : Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.question_mark_rounded,
                                              key: ValueKey('hidden'),
                                              color: Colors.white,
                                              size: 40,
                                            ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 48),

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
                          style: SpaceTheme.bodyStyle
                              .copyWith(fontSize: 20, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: s.gameplayWriteTheWord,
                            hintStyle: SpaceTheme.bodyStyle
                                .copyWith(color: Colors.white54),
                            filled: true,
                            fillColor: SpaceTheme.deepSpace.withOpacity(0.7),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: SpaceTheme.planetOrange,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: SpaceTheme.alienGreen,
                                width: 2,
                              ),
                            ),
                            prefixIcon: Icon(
                              Icons.edit,
                              color: Colors.white70,
                            ),
                          ),
                          textAlign: TextAlign.center,
                          autocorrect: false,
                          enableSuggestions: false,
                        ),

                        const SizedBox(height: 24),

                        // Action buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Hint button
                            if (!_isWordVisible && !_isAnswerChecked)
                              ElevatedButton.icon(
                                onPressed: _showHint,
                                icon: const Icon(Icons.lightbulb_outline),
                                label: Text(s.gameplayHint),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SpaceTheme.starYellow,
                                  foregroundColor: SpaceTheme.deepSpace,
                                ),
                              ),

                            if (!_isWordVisible && !_isAnswerChecked)
                              const SizedBox(width: 16),

                            // Check/Continue button
                            if (!_isAnswerChecked)
                              ElevatedButton.icon(
                                onPressed: _userInput.isNotEmpty
                                    ? _checkAnswer
                                    : null,
                                icon: const Icon(Icons.check),
                                label: Text(s.gameplayCheck),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SpaceTheme.alienGreen,
                                  foregroundColor: SpaceTheme.deepSpace,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        // Feedback message
                        if (_isAnswerChecked)
                          Container(
                            margin: const EdgeInsets.only(top: 24),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _answerResult == AnswerResultType.perfect
                                  ? Colors.green.withOpacity(0.2)
                                  : _answerResult ==
                                          AnswerResultType.commonMistake
                                      ? SpaceTheme.starYellow.withOpacity(0.2)
                                      : Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _answerResult ==
                                        AnswerResultType.perfect
                                    ? Colors.green
                                    : _answerResult ==
                                            AnswerResultType.commonMistake
                                        ? SpaceTheme.starYellow
                                        : Colors.red,
                              ),
                            ),
                            child: Text(
                              _feedbackMessage,
                              style: SpaceTheme.bodyStyle,
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// This class is not part of this file, but is required by game_menu_screen.dart
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