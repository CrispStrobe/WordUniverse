// lib/features/games/screens/word_builder_game.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';

import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/space_background.dart';

class WordBuilderGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WordBuilderGame({super.key, required this.gradeLevel});

  @override
  State<WordBuilderGame> createState() => _WordBuilderGameState();
}

class LetterTile {
  final String letter;
  final int originalIndex;
  bool isPlaced;
  int? placedPosition;

  LetterTile({
    required this.letter,
    required this.originalIndex,
    this.isPlaced = false,
    this.placedPosition,
  });
}

enum FeedbackState { none, correct, incorrect, hint }

class _WordBuilderGameState extends State<WordBuilderGame> with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  GermanWord? _currentWord;
  List<LetterTile> _tiles = [];
  List<LetterTile?> _buildArea = [];
  int _score = 0;
  int _wordsCompleted = 0;
  int _totalWords = 8;
  int _hintsUsed = 0;
  
  FeedbackState _feedbackState = FeedbackState.none;
  Timer? _feedbackTimer;
  bool _showHint = false;

  // Educational info flow
  String _educationalInfoText = "";
  bool _showEducationalInfo = false;
  Timer? _educationalInfoTimer;

  // Control for "Baue das Wort:" instruction
  bool _showBuildInstruction = true;
  Timer? _instructionTimer;

  // Time tracking
  Timer? _gameTimer;
  int _secondsRemaining = 60;
  int _timeBonus = 0;

  // Animation controllers
  late AnimationController _successController;
  late AnimationController _shakeController;
  late AnimationController _hintController;

  @override
  void initState() {
    super.initState();
    
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _gameTimer?.cancel();
    _educationalInfoTimer?.cancel();
    _instructionTimer?.cancel();
    _successController.dispose();
    _shakeController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    setState(() => _isLoading = true);

    _vocabularyService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();

    if (!_vocabularyService.isInitialized) {
      await _vocabularyService.initialize();
    }

    _loadLevel();
  }

  String? _extractBaseWordFromSriId(String id) {
    if (id.startsWith('SPELL_')) return id.substring('SPELL_'.length);
    if (id.startsWith('WORDTYPE_')) return id.substring('WORDTYPE_'.length);
    return null;
  }

  bool _isWordValidForGame(GermanWord word) {
    final length = word.word.length;
    
    switch (widget.gradeLevel) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        return length >= 3 && length <= 5 && !word.word.contains(" ");
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        return length >= 4 && length <= 7 && !word.word.contains(" ");
      default:
        return length >= 5 && length <= 10 && !word.word.contains(" ");
    }
  }

  void _loadLevel() {
    _score = 0;
    _wordsCompleted = 0;
    _hintsUsed = 0;
    
    switch (widget.gradeLevel) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        _secondsRemaining = 90;
        break;
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        _secondsRemaining = 75;
        break;
      default:
        _secondsRemaining = 60;
    }

    _loadNextWord();
    _startTimer();
    
    _instructionTimer?.cancel();
    _instructionTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showBuildInstruction = false;
        });
      }
    });
    
    setState(() => _isLoading = false);
  }

  void _startTimer() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _gameTimer?.cancel();
        if (mounted) {
          _showGameOver();
        }
      }
    });
  }

  void _loadNextWord() {
    if (_wordsCompleted >= _totalWords) {
      _gameTimer?.cancel();
      if (mounted) {
        _showGameOver();
      }
      return;
    }

    final List<GermanWord> candidateWords = [];
    final Set<String> addedWordIds = {};

    final reviewItemIds = _sriService.getItemsForReview(
      limit: 20,
      skillTypeFilter: LanguageSkillType.spelling,
      gradeLevelFilter: widget.gradeLevel.index + 1,
    );

    for (final id in reviewItemIds) {
      final wordString = _extractBaseWordFromSriId(id);
      if (wordString == null) continue;

      try {
        final word = _vocabularyService.getAllWords(_gameProvider).firstWhere(
            (w) => w.word.toLowerCase() == wordString.toLowerCase());

        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          candidateWords.add(word);
          addedWordIds.add(word.id);
        }
      } catch (e) {
        // Word from SRI not in vocab, skip
      }
    }

    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: 20,
      settingsProvider: _gameProvider,
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        candidateWords.add(word);
        addedWordIds.add(word.id);
      }
    }

    if (candidateWords.length < 10) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
      allWords.shuffle();

      for (final word in allWords) {
        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          candidateWords.add(word);
          addedWordIds.add(word.id);
          if (candidateWords.length >= 20) break;
        }
      }
    }

    if (candidateWords.isEmpty) {
      debugPrint("No words found for WordBuilderGame");
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    candidateWords.shuffle();
    final selectedWord = candidateWords.first;

    final letters = selectedWord.word.toUpperCase().split('');
    final List<LetterTile> tiles = [];
    
    for (int i = 0; i < letters.length; i++) {
      tiles.add(LetterTile(
        letter: letters[i],
        originalIndex: i,
      ));
    }

    final random = Random();
    for (int attempt = 0; attempt < 10; attempt++) {
      tiles.shuffle(random);
      
      bool isDifferent = false;
      for (int i = 0; i < tiles.length; i++) {
        if (tiles[i].originalIndex != i) {
          isDifferent = true;
          break;
        }
      }
      if (isDifferent) break;
    }

    setState(() {
      _currentWord = selectedWord;
      _tiles = tiles;
      _buildArea = List.filled(letters.length, null);
      _feedbackState = FeedbackState.none;
      _showHint = false;
      _hintController.reset();
    });
  }

  void _onTileDraggedToBuildArea(LetterTile draggedTile, int targetPosition) {
    if (_feedbackState == FeedbackState.correct) return;

    final int? sourcePosition = draggedTile.placedPosition;
    final LetterTile? tileInTargetSlot = _buildArea[targetPosition];

    setState(() {
      if (sourcePosition != null) {
        _buildArea[sourcePosition] = null;
      }

      _buildArea[targetPosition] = draggedTile;
      draggedTile.isPlaced = true;
      draggedTile.placedPosition = targetPosition;

      if (tileInTargetSlot != null) {
        if (sourcePosition != null) {
          _buildArea[sourcePosition] = tileInTargetSlot;
          tileInTargetSlot.placedPosition = sourcePosition;
        } else {
          tileInTargetSlot.isPlaced = false;
          tileInTargetSlot.placedPosition = null;
        }
      }
    });

    _audioService.playSound('tap');
    _checkWord();
  }

  void _onTileReturnedToPool(LetterTile tile) {
    setState(() {
      if (tile.placedPosition != null) {
        _buildArea[tile.placedPosition!] = null;
      }
      tile.isPlaced = false;
      tile.placedPosition = null;
      _feedbackState = FeedbackState.none;
    });

    _audioService.playSound('tap');
  }

  void _checkWord() {
    if (_buildArea.any((tile) => tile == null)) {
      return;
    }

    final constructedWord = _buildArea.map((tile) => tile!.letter).join('');
    final targetWord = _currentWord!.word.toUpperCase();

    if (constructedWord == targetWord) {
      _onCorrectWord();
    } else {
      _onIncorrectWord();
    }
  }

  void _onCorrectWord() {
    _audioService.playSound('success');
    
    setState(() {
      _feedbackState = FeedbackState.correct;
      _wordsCompleted++;
      
      int baseScore = 100;
      _timeBonus = (_secondsRemaining > 45) ? 50 : ((_secondsRemaining > 30) ? 25 : 0);
      int hintPenalty = _hintsUsed * 10;
      
      _score += baseScore + _timeBonus - hintPenalty;
      _hintsUsed = 0;
    });

    _successController.forward(from: 0);

    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentWord!.word,
      wasCorrect: true,
      metadata: {
        'game': 'word_builder',
        'time_remaining': _secondsRemaining,
        'hints_used': _hintsUsed,
      },
    );

    final eduInfo = _getEducationalInfo(_currentWord!);
    if (eduInfo.isNotEmpty) {
      setState(() {
        _educationalInfoText = '${_currentWord!.word}$eduInfo';
        _showEducationalInfo = true;
      });

      _educationalInfoTimer?.cancel();
      _educationalInfoTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) {
          setState(() {
            _showEducationalInfo = false;
          });
        }
      });
    }

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _loadNextWord();
      }
    });
  }

  void _onIncorrectWord() {
    _audioService.playSound('failure');
    
    setState(() {
      _feedbackState = FeedbackState.incorrect;
    });

    _shakeController.forward(from: 0);

    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentWord!.word,
      wasCorrect: false,
      metadata: {'game': 'word_builder'},
    );

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _feedbackState = FeedbackState.none;
        });
      }
    });
  }

  void _useHint() {
    if (_showHint || _feedbackState == FeedbackState.correct) return;

    setState(() {
      _showHint = true;
      _hintsUsed++;
      _feedbackState = FeedbackState.hint;
    });

    _hintController.forward(from: 0);
    _audioService.playSound('tap');
  }

  void _skipWord() {
    _audioService.playSound('tap');
    
    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentWord!.word,
      wasCorrect: false,
      metadata: {'game': 'word_builder', 'skipped': true},
    );

    _loadNextWord();
  }

  String _getEducationalInfo(GermanWord word) {
    final parts = <String>[];
    
    if (word.wordType != GermanWordType.andere) {
        final s = S.of(context)!;
        switch (word.wordType) {
        case GermanWordType.substantiv:
            parts.add(s.wordSortCategoryNoun);
            break;
        case GermanWordType.verb:
            parts.add(s.wordSortCategoryVerb);
            break;
        case GermanWordType.adjektiv:
            parts.add(s.wordSortCategoryAdjective);
            break;
        default:
            break;
        }
    }
    
    if (word.article != null && word.article!.isNotEmpty) {
        parts.add(word.article!);
    }
    
    return parts.isEmpty ? '' : ' (${parts.join(', ')})';
  }

  void _showGameOver() {
    final s = S.of(context)!;
    
    final percentage = (_wordsCompleted / _totalWords * 100).round();
    int stars = 1;
    if (percentage >= 90) stars = 3;
    else if (percentage >= 70) stars = 2;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.emoji_events, color: SpaceTheme.starYellow, size: 32),
            const SizedBox(width: 12),
            Text(
              s.wordBuilderGameOver,
              style: SpaceTheme.titleStyle,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return Icon(
                  index < stars ? Icons.star : Icons.star_border,
                  color: SpaceTheme.starYellow,
                  size: 40,
                );
              }),
            ),
            const SizedBox(height: 20),
            Text(
              '${s.gameScore}: $_score',
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 18),
            ),
            Text(
              '${s.wordBuilderWords}: $_wordsCompleted/$_totalWords',
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 18),
            ),
            if (_timeBonus > 0)
              Text(
                '${s.wordBuilderTimeBonus}: +$_timeBonus',
                style: SpaceTheme.bodyStyle.copyWith(
                  fontSize: 16,
                  color: SpaceTheme.alienGreen,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _loadLevel();
            },
            child: Text(
              s.gameReplay,
              style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.alienGreen),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.planetOrange,
            ),
            child: Text(
              s.gameDone,
              style: SpaceTheme.bodyStyle.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final selectedFontFamily = context.watch<GameProvider>().selectedFontFamily;

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Unified compact top bar
              _buildUnifiedTopBar(s),
              
              if (_isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      children: [
                        // Educational info (floating)
                        if (_showEducationalInfo)
                          _buildWordInfo(selectedFontFamily),
                        
                        // Build instruction (floating, disappears after 3s)
                        if (_showBuildInstruction)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: AnimatedOpacity(
                              opacity: 1.0,
                              duration: const Duration(milliseconds: 300),
                              child: Text(
                                s.wordBuilderBuildWord,
                                style: SpaceTheme.bodyStyle.copyWith(
                                  fontSize: 14,
                                  color: SpaceTheme.starYellow,
                                ),
                              ),
                            ),
                          ),
                        
                        // Main game area
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Build area with hint
                              _buildConstructionArea(selectedFontFamily),
                              
                              const SizedBox(height: 16),
                              
                              // Letter tiles pool
                              _buildLetterPool(selectedFontFamily),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // NEW: Unified compact top bar with icon buttons
  Widget _buildUnifiedTopBar(S s) {
    final timeColor = _secondsRemaining < 10 
        ? SpaceTheme.rocketRed 
        : (_secondsRemaining < 30 ? SpaceTheme.planetOrange : SpaceTheme.alienGreen);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(
            color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            onPressed: () {
              _gameTimer?.cancel();
              Navigator.of(context).pop();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          
          const SizedBox(width: 8),
          
          // Hint button (icon only)
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: (_feedbackState == FeedbackState.correct || _showHint)
                      ? Colors.grey
                      : SpaceTheme.starYellow,
                  size: 24,
                ),
                if (_hintsUsed > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: SpaceTheme.rocketRed,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$_hintsUsed',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: (_feedbackState == FeedbackState.correct || _showHint)
                ? null
                : _useHint,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: '${s.wordBuilderHint} (-10)',
          ),
          
          const SizedBox(width: 4),
          
          // Skip button (icon only)
          IconButton(
            icon: Icon(
              Icons.skip_next,
              color: _feedbackState == FeedbackState.correct
                  ? Colors.grey
                  : SpaceTheme.rocketRed,
              size: 24,
            ),
            onPressed: _feedbackState == FeedbackState.correct ? null : _skipWord,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: s.wordBuilderSkip,
          ),
          
          const SizedBox(width: 12),
          
          // Level
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: SpaceTheme.nebulaPurple.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5)),
            ),
            child: Text(
              'Lvl ${widget.gradeLevel.index + 1}',
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: SpaceTheme.nebulaPurple,
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Score
          _buildCompactStat(Icons.stars, _score.toString(), SpaceTheme.starYellow),
          
          const SizedBox(width: 8),
          
          // Words
          _buildCompactStat(Icons.spellcheck, '$_wordsCompleted/$_totalWords', SpaceTheme.cosmicPink),
          
          const Spacer(),
          
          // Time
          _buildCompactStat(Icons.timer, '${_secondsRemaining}s', timeColor),
        ],
      ),
    );
  }

  Widget _buildCompactStat(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            value,
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordInfo(String selectedFontFamily) {
    return AnimatedOpacity(
      opacity: _showEducationalInfo ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SpaceTheme.alienGreen.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SpaceTheme.alienGreen),
        ),
        child: Text(
          _educationalInfoText,
          style: SpaceTheme.bodyStyle.copyWith(
            fontFamily: selectedFontFamily,
            fontSize: 14,
            color: SpaceTheme.alienGreen,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildConstructionArea(String selectedFontFamily) {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final shakeOffset = sin(_shakeController.value * pi * 4) * 10;
        
        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SpaceTheme.deepSpace.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _feedbackState == FeedbackState.correct
                    ? SpaceTheme.alienGreen
                    : (_feedbackState == FeedbackState.incorrect
                        ? SpaceTheme.rocketRed
                        : SpaceTheme.nebulaPurple),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hint text (faded word)
                if (_showHint)
                  AnimatedBuilder(
                    animation: _hintController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: 0.3 + (_hintController.value * 0.2),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _currentWord!.word.toUpperCase(),
                            style: TextStyle(
                              fontFamily: selectedFontFamily,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: SpaceTheme.starYellow,
                              letterSpacing: 6,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                
                // Build slots
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: List.generate(_buildArea.length, (index) {
                    return _buildDropSlot(index, selectedFontFamily);
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptySlot(int position, {bool isHighlighted = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 50,
      height: 60,
      decoration: BoxDecoration(
        color: isHighlighted
                ? SpaceTheme.nebulaPurple.withValues(alpha: 0.5)
                : SpaceTheme.deepSpace.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHighlighted
              ? SpaceTheme.starYellow
              : SpaceTheme.nebulaPurple.withValues(alpha: 0.5),
          width: isHighlighted ? 2 : 1.5,
        ),
      ),
      child: Center(
        child: Text(
          '${position + 1}',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Widget _buildDropSlot(int position, String selectedFontFamily) {
    final tile = _buildArea[position];
    
    return DragTarget<LetterTile>(
      onWillAcceptWithDetails: (details) => _feedbackState != FeedbackState.correct && details.data != tile,
      onAcceptWithDetails: (details) => _onTileDraggedToBuildArea(details.data, position),
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;
        
        if (tile != null) {
          return Draggable<LetterTile>(
            data: tile,
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.8,
                child: _buildTileWidget(tile, selectedFontFamily, isDragging: true),
              ),
            ),
            childWhenDragging: _buildEmptySlot(position, isHighlighted: true),
            onDragStarted: () {
              if (_feedbackState == FeedbackState.incorrect) {
                setState(() {
                  _feedbackState = FeedbackState.none;
                });
              }
            },
            child: GestureDetector(
              onTap: () {
                if (_feedbackState != FeedbackState.correct) {
                  _onTileReturnedToPool(tile);
                }
              },
              child: _buildTileWidget(tile, selectedFontFamily),
            ),
          );
        } else {
          return _buildEmptySlot(position, isHighlighted: isHighlighted);
        }
      },
    );
  }

  Widget _buildLetterPool(String selectedFontFamily) {
    return DragTarget<LetterTile>(
      onWillAcceptWithDetails: (details) => details.data.isPlaced,
      onAcceptWithDetails: (details) => _onTileReturnedToPool(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SpaceTheme.deepSpace.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: isHighlighted 
              ? Border.all(color: SpaceTheme.starYellow, width: 2)
              : Border.all(color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _tiles.where((tile) => !tile.isPlaced).map((tile) {
              return _buildDraggableTile(tile, selectedFontFamily);
            }).toList(),
          ),
        );
      }
    );
  }

  Widget _buildDraggableTile(LetterTile tile, String selectedFontFamily) {
    return Draggable<LetterTile>(
      data: tile,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.8,
          child: _buildTileWidget(tile, selectedFontFamily, isDragging: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildTileWidget(tile, selectedFontFamily),
      ),
      onDragStarted: () {
        if (_feedbackState == FeedbackState.incorrect) {
          setState(() {
            _feedbackState = FeedbackState.none;
          });
        }
      },
      child: _buildTileWidget(tile, selectedFontFamily),
    );
  }

  Widget _buildTileWidget(LetterTile tile, String selectedFontFamily, {bool isDragging = false}) {
    return AnimatedBuilder(
      animation: _successController,
      builder: (context, child) {
        final scale = tile.isPlaced && _feedbackState == FeedbackState.correct
            ? 1.0 + (sin(_successController.value * pi) * 0.2)
            : 1.0;
        
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 50,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  SpaceTheme.cosmicPink,
                  SpaceTheme.cosmicPink.withValues(alpha: 0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: SpaceTheme.cosmicPink.withValues(alpha: 0.4),
                  blurRadius: isDragging ? 16 : 6,
                  spreadRadius: isDragging ? 2 : 0,
                ),
              ],
            ),
            child: Center(
              child: Text(
                tile.letter,
                style: TextStyle(
                  fontFamily: selectedFontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: const [
                    Shadow(blurRadius: 3, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}