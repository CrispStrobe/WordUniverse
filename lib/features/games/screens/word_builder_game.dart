// lib/features/games/screens/word_builder_game.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/models/skill_category.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/game_ui.dart';
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
    
    // Grade-appropriate word lengths
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
    
    // Set time based on grade
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

    // --- ADAPTIVE WORD SELECTION ---
    final List<GermanWord> candidateWords = [];
    final Set<String> addedWordIds = {};

    // Get review words (50%)
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

    // Get new words
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

    // Fill with random words if needed
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
    // --- END ADAPTIVE SELECTION ---

    if (candidateWords.isEmpty) {
      debugPrint("No words found for WordBuilderGame");
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    candidateWords.shuffle();
    final selectedWord = candidateWords.first;

    // Create scrambled letter tiles
    final letters = selectedWord.word.toUpperCase().split('');
    final List<LetterTile> tiles = [];
    
    for (int i = 0; i < letters.length; i++) {
      tiles.add(LetterTile(
        letter: letters[i],
        originalIndex: i,
      ));
    }

    // Scramble the tiles (ensure it's actually scrambled)
    final random = Random();
    for (int attempt = 0; attempt < 10; attempt++) {
      tiles.shuffle(random);
      
      // Check if scrambled (not in original order)
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
    });
  }

  void _onTileDraggedToBuildArea(LetterTile tile, int position) {
    if (tile.isPlaced) return;

    setState(() {
      // Remove from previous position if any
      for (int i = 0; i < _buildArea.length; i++) {
        if (_buildArea[i] == tile) {
          _buildArea[i] = null;
        }
      }

      // Place in new position
      _buildArea[position] = tile;
      tile.isPlaced = true;
      tile.placedPosition = position;
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
    // Check if all positions are filled
    if (_buildArea.any((tile) => tile == null)) {
      return;
    }

    // Build the constructed word
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
      
      // Calculate score with time bonus
      int baseScore = 100;
      _timeBonus = (_secondsRemaining > 45) ? 50 : ((_secondsRemaining > 30) ? 25 : 0);
      int hintPenalty = _hintsUsed * 10;
      
      _score += baseScore + _timeBonus - hintPenalty;
      _hintsUsed = 0;
    });

    _successController.forward(from: 0);

    // Record success in SRI
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

    // Load next word after delay
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

    // Record failure in SRI
    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentWord!.word,
      wasCorrect: false,
      metadata: {'game': 'word_builder'},
    );

    // Reset after delay
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
    
    // Record as incorrect in SRI
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
    
    if (word.article != null) {
        parts.add(word.article!);
    }
    
    return parts.isEmpty ? '' : ' (${parts.join(', ')})';
    }

  void _showGameOver() {
    final s = S.of(context)!;
    
    // Calculate performance
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
              GameUI(
                title: s.wordBuilderTitle,
                level: widget.gradeLevel.index + 1,
                onBack: () {
                  _gameTimer?.cancel();
                  Navigator.of(context).pop();
                },
              ),
              if (_isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 600;
                      
                      return Column(
                        children: [
                          // Stats bar
                          _buildStatsBar(s),
                          
                          // Main game area
                          Expanded(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: isWide ? 800 : constraints.maxWidth,
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Educational info
                                        if (_currentWord != null)
                                          _buildWordInfo(selectedFontFamily),
                                        
                                        const SizedBox(height: 24),
                                        
                                        // Build area with hint
                                        _buildConstructionArea(s, selectedFontFamily),
                                        
                                        const SizedBox(height: 32),
                                        
                                        // Letter tiles pool
                                        _buildLetterPool(s, selectedFontFamily),
                                        
                                        const SizedBox(height: 24),
                                        
                                        // Action buttons
                                        _buildActionButtons(s),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

  Widget _buildStatsBar(S s) {
    final timeColor = _secondsRemaining < 10 
        ? SpaceTheme.rocketRed 
        : (_secondsRemaining < 30 ? SpaceTheme.planetOrange : SpaceTheme.alienGreen);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(s.gameScore, _score.toString(), Icons.stars, SpaceTheme.starYellow),
          _buildStatItem(s.wordBuilderWords, '$_wordsCompleted/$_totalWords', Icons.spellcheck, SpaceTheme.cosmicPink),
          _buildStatItem(s.wordBuilderTime, '${_secondsRemaining}s', Icons.timer, timeColor),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: SpaceTheme.bodyStyle.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: SpaceTheme.bodyStyle.copyWith(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWordInfo(String selectedFontFamily) {
    final eduInfo = _getEducationalInfo(_currentWord!);
    
    return AnimatedOpacity(
      opacity: _feedbackState == FeedbackState.correct ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SpaceTheme.alienGreen.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SpaceTheme.alienGreen),
        ),
        child: Text(
          '${_currentWord!.word}$eduInfo',
          style: SpaceTheme.bodyStyle.copyWith(
            fontFamily: selectedFontFamily,
            fontSize: 16,
            color: SpaceTheme.alienGreen,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildConstructionArea(S s, String selectedFontFamily) {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final shakeOffset = sin(_shakeController.value * pi * 4) * 10;
        
        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: SpaceTheme.cardDecoration.copyWith(
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
              children: [
                Text(
                  s.wordBuilderBuildWord,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Hint text (faded word)
                if (_showHint)
                  AnimatedBuilder(
                    animation: _hintController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: 0.3 + (_hintController.value * 0.2),
                        child: Text(
                          _currentWord!.word.toUpperCase(),
                          style: TextStyle(
                            fontFamily: selectedFontFamily,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: SpaceTheme.starYellow,
                            letterSpacing: 8,
                          ),
                        ),
                      );
                    },
                  ),
                
                const SizedBox(height: 8),
                
                // Build slots
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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

  Widget _buildDropSlot(int position, String selectedFontFamily) {
    final tile = _buildArea[position];
    
    return DragTarget<LetterTile>(
      onWillAccept: (data) => _feedbackState != FeedbackState.correct,
      onAccept: (data) => _onTileDraggedToBuildArea(data, position),
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;
        
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 60,
          height: 70,
          decoration: BoxDecoration(
            color: tile != null
                ? SpaceTheme.planetOrange.withOpacity(0.8)
                : (isHighlighted
                    ? SpaceTheme.nebulaPurple.withOpacity(0.5)
                    : SpaceTheme.deepSpace.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted
                  ? SpaceTheme.starYellow
                  : SpaceTheme.nebulaPurple.withOpacity(0.5),
              width: isHighlighted ? 3 : 2,
            ),
          ),
          child: tile != null
              ? GestureDetector(
                  onTap: () => _onTileReturnedToPool(tile),
                  child: Center(
                    child: Text(
                      tile.letter,
                      style: TextStyle(
                        fontFamily: selectedFontFamily,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    '${position + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildLetterPool(S s, String selectedFontFamily) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SpaceTheme.cardDecoration,
      child: Column(
        children: [
          Text(
            s.wordBuilderLetters,
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: _tiles.where((tile) => !tile.isPlaced).map((tile) {
              return _buildDraggableTile(tile, selectedFontFamily);
            }).toList(),
          ),
        ],
      ),
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
            width: 60,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  SpaceTheme.cosmicPink,
                  SpaceTheme.cosmicPink.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: SpaceTheme.cosmicPink.withOpacity(0.4),
                  blurRadius: isDragging ? 20 : 8,
                  spreadRadius: isDragging ? 2 : 0,
                ),
              ],
            ),
            child: Center(
              child: Text(
                tile.letter,
                style: TextStyle(
                  fontFamily: selectedFontFamily,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: const [
                    Shadow(blurRadius: 4, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(S s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: (_feedbackState == FeedbackState.correct || _showHint) ? null : _useHint,
          icon: const Icon(Icons.lightbulb_outline),
          label: Text(s.wordBuilderHint),
          style: ElevatedButton.styleFrom(
            backgroundColor: SpaceTheme.starYellow,
            foregroundColor: SpaceTheme.deepSpace,
            disabledBackgroundColor: Colors.grey,
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _feedbackState == FeedbackState.correct ? null : _skipWord,
          icon: const Icon(Icons.skip_next),
          label: Text(s.wordBuilderSkip),
          style: ElevatedButton.styleFrom(
            backgroundColor: SpaceTheme.rocketRed,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey,
          ),
        ),
      ],
    );
  }
}