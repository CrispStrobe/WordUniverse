// lib/features/games/screens/word_find_game.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:collection';

import '../../../core/models/skill_category.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../services/word_search_generator.dart';
import '../models/word_find_models.dart';
import '../providers/game_provider.dart';
import '../widgets/game_ui.dart';
import '../widgets/space_background.dart';

class WordFindGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WordFindGame({super.key, required this.gradeLevel});

  @override
  State<WordFindGame> createState() => _WordFindGameState();
}

class _WordFindGameState extends State<WordFindGame> {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  int _gridSize = 10;
  List<List<String>> _grid = [];
  List<PlacedWord> _placedWords = [];
  List<GermanWord> _wordsToFind = [];
  int _score = 0;

  // State for found words
  final Set<String> _foundWords = {};
  final Set<GridPosition> _foundCells = {};

  // State for user interaction
  final GlobalKey _gridKey = GlobalKey();
  GridPosition? _dragStart;
  GridPosition? _dragCurrent;
  final Set<GridPosition> _selectedCells = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
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

  void _loadLevel() {
    // Clear old game state
    _grid.clear();
    _placedWords.clear();
    _wordsToFind.clear();
    _foundWords.clear();
    _foundCells.clear();
    _score = 0;

    // Determine grid size and word count based on grade
    // (You can make this more complex)
    int wordCount;
    switch (widget.gradeLevel) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        _gridSize = 8;
        wordCount = 4;
        break;
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        _gridSize = 10;
        wordCount = 6;
        break;
      default:
        _gridSize = 12;
        wordCount = 8;
    }

    // Get words for the game
    final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel);
    allWords.removeWhere((word) =>
        word.wordType == GermanWordType.andere ||
        word.word.contains(" ") || // No multi-word phrases
        word.word.length > _gridSize || // Word must fit in grid
        word.word.length < 3 // Words should be at least 3 letters
        );
    allWords.shuffle();
    _wordsToFind = allWords.take(wordCount).toList();

    // Generate the grid
    final wordStrings = _wordsToFind.map((w) => w.word.replaceAll(' ', '')).toList();
    final result = WordSearchGenerator.generate(_gridSize, wordStrings);

    // Update state
    setState(() {
      _grid = result.grid;
      _placedWords = result.placedWords;
      _isLoading = false;
    });
  }

  // --- Drag Handling Logic ---

  GridPosition? _getGridPositionFromOffset(Offset localPos) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final cellSize = box.size.width / _gridSize;
    if (cellSize <= 0) return null;

    final col = (localPos.dx / cellSize).floor();
    final row = (localPos.dy / cellSize).floor();

    if (row >= 0 && row < _gridSize && col >= 0 && col < _gridSize) {
      return GridPosition(row, col);
    }
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    final pos = _getGridPositionFromOffset(details.localPosition);
    if (pos != null) {
      setState(() {
        _dragStart = pos;
        _dragCurrent = pos;
        _updateSelectedCells();
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStart == null) return;
    final pos = _getGridPositionFromOffset(details.localPosition);
    if (pos != null && pos != _dragCurrent) {
      setState(() {
        // Constrain to horizontal, vertical, or diagonal
        final dx = (pos.col - _dragStart!.col).abs();
        final dy = (pos.row - _dragStart!.row).abs();

        if (dx == dy) {
          // Diagonal
          _dragCurrent = pos;
        } else if (dx > dy) {
          // Horizontal
          _dragCurrent = GridPosition(_dragStart!.row, pos.col);
        } else {
          // Vertical
          _dragCurrent = GridPosition(pos.row, _dragStart!.col);
        }
        _updateSelectedCells();
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_dragStart == null || _dragCurrent == null) return;

    _checkSelectedWord();

    setState(() {
      _dragStart = null;
      _dragCurrent = null;
      _selectedCells.clear();
    });
  }

  void _updateSelectedCells() {
    _selectedCells.clear();
    if (_dragStart == null || _dragCurrent == null) return;

    final int r1 = _dragStart!.row;
    final int c1 = _dragStart!.col;
    final int r2 = _dragCurrent!.row;
    final int c2 = _dragCurrent!.col;

    // Horizontal
    if (r1 == r2) {
      for (int c = min(c1, c2); c <= max(c1, c2); c++) {
        _selectedCells.add(GridPosition(r1, c));
      }
    }
    // Vertical
    else if (c1 == c2) {
      for (int r = min(r1, r2); r <= max(r1, r2); r++) {
        _selectedCells.add(GridPosition(r, c1));
      }
    }
    // Diagonal
    else if ((r1 - r2).abs() == (c1 - c2).abs()) {
      final int rStep = (r2 > r1) ? 1 : -1;
      final int cStep = (c2 > c1) ? 1 : -1;
      for (int i = 0; i <= (r1 - r2).abs(); i++) {
        _selectedCells.add(GridPosition(r1 + i * rStep, c1 + i * cStep));
      }
    }
  }

  void _checkSelectedWord() {
    String selectedWord = "";
    List<GridPosition> orderedCells = List.from(_selectedCells);

    // This sorting works for horizontal, vertical, and diagonal
    orderedCells.sort((a, b) {
      if (a.row != b.row) return a.row.compareTo(b.row);
      return a.col.compareTo(b.col);
    });

    for (var pos in orderedCells) {
      selectedWord += _grid[pos.row][pos.col];
    }

    String reversedWord = selectedWord.split('').reversed.join('');

    for (var placedWord in _placedWords) {
      if (!_foundWords.contains(placedWord.word) &&
          (placedWord.word == selectedWord || placedWord.word == reversedWord)) {
        
        // --- SUCCESS! ---
        _audioService.playSound('correct.mp3');
        _gameProvider.addScore(10);
        setState(() {
          _score += 10;
          _foundWords.add(placedWord.word);
          _foundCells.addAll(_selectedCells);
        });

        // Find the original GermanWord to record in SRI
        final originalWord = _wordsToFind.firstWhere(
            (w) => w.word.toUpperCase() == placedWord.word);

        _sriService.recordResponse(
          skillType: LanguageSkillType.spelling,
          baseWord: originalWord.word,
          wasCorrect: true,
          metadata: {
            'gradeLevel': originalWord.gradeLevel,
            'wordType': originalWord.wordType.toString(),
          },
        );

        // Check for game over
        if (_foundWords.length == _placedWords.length) {
          _showGameOver();
        }
        return;
      }
    }

    // --- FAILED ---
    _audioService.playSound('incorrect.mp3');
  }

  void _showGameOver() {
    final s = S.of(context)!;
    _gameProvider.recordLevelWin(
      gameType: 'word_find_game',
      scoreGained: _score,
      difficulty: widget.gradeLevel.index + 1,
      wasSuccessful: true,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        title: Text(s.gameOver, style: SpaceTheme.headlineStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.congratulations, style: SpaceTheme.bodyStyle),
            const SizedBox(height: 16),
            Text('${s.score}: $_score', style: SpaceTheme.titleStyle),
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
              _loadLevel();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              GameUI(
                title: "Galaxy Word-Find", // This game needs a title
                level: widget.gradeLevel.index + 1,
                onBack: () => Navigator.of(context).pop(),
              ),
              if (_isLoading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- The Grid ---
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: GestureDetector(
                            key: _gridKey,
                            onPanStart: _onPanStart,
                            onPanUpdate: _onPanUpdate,
                            onPanEnd: _onPanEnd,
                            child: AspectRatio(
                              aspectRatio: 1.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: SpaceTheme.deepSpace.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _gridSize,
                                  ),
                                  itemCount: _gridSize * _gridSize,
                                  itemBuilder: (context, index) {
                                    final row = index ~/ _gridSize;
                                    final col = index % _gridSize;
                                    return _buildCell(row, col);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // --- Words to Find ---
                      Expanded(
                        flex: 2,
                        child: _buildWordsToFindList(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCell(int row, int col) {
    final pos = GridPosition(row, col);
    final isSelected = _selectedCells.contains(pos);
    final isFound = _foundCells.contains(pos);

    Color bgColor;
    Color textColor = Colors.white;

    if (isFound) {
      bgColor = SpaceTheme.alienGreen.withOpacity(0.7);
      textColor = SpaceTheme.deepSpace;
    } else if (isSelected) {
      bgColor = SpaceTheme.planetOrange.withOpacity(0.8);
    } else {
      bgColor = SpaceTheme.nebulaPurple.withOpacity(0.5);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: SpaceTheme.deepSpace.withOpacity(0.3)),
      ),
      child: Center(
        child: Text(
          _grid[row][col],
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
            shadows: const [
              Shadow(blurRadius: 4, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordsToFindList() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16, right: 16, bottom: 16),
      decoration: SpaceTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Wörter finden:", // TODO: Add to l10n
            style: SpaceTheme.titleStyle.copyWith(color: SpaceTheme.starYellow),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _wordsToFind.length,
              itemBuilder: (context, index) {
                final word = _wordsToFind[index];
                final wordUpper = word.word.toUpperCase();
                final isFound = _foundWords.contains(wordUpper);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    word.word, // Show the base word
                    style: SpaceTheme.bodyStyle.copyWith(
                      fontSize: 16,
                      color: isFound ? SpaceTheme.alienGreen : Colors.white70,
                      decoration: isFound
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: SpaceTheme.rocketRed,
                      decorationThickness: 2.0,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}