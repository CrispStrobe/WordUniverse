// lib/features/games/screens/word_snake_game.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../services/word_snake_generator.dart';
import '../providers/game_provider.dart';
import '../widgets/game_ui.dart';
import '../widgets/space_background.dart';

class WordSnakeGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WordSnakeGame({super.key, required this.gradeLevel});

  @override
  State<WordSnakeGame> createState() => _WordSnakeGameState();
}

enum FeedbackState { none, correct, incorrect }

class _WordSnakeGameState extends State<WordSnakeGame> {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  WordSnakeGrid? _currentPuzzle;
  GermanWord? _currentWord;
  int _score = 0;
  int _puzzlesCompleted = 0;
  int _totalPuzzles = 5;

  // User interaction
  final List<Point> _selectedPath = [];
  final GlobalKey _gridKey = GlobalKey();
  Point? _dragStart;
  Point? _dragCurrent;
  
  // --- MODIFIED: Feedback State ---
  FeedbackState _feedbackState = FeedbackState.none;
  Timer? _feedbackTimer; // This timer is for failure reset
  Timer? _hintTimer; // This timer is for the hint toast
  bool _showConfetti = false;
  String _educationalInfo = ''; // This is the success hint
  String _feedbackMessage = ''; // This is the failure/success message

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _hintTimer?.cancel(); // --- FIX: Cancel the new hint timer ---
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
    if (id.startsWith('SPELL_')) {
      return id.substring('SPELL_'.length);
    }
    if (id.startsWith('WORDTYPE_')) {
      return id.substring('WORDTYPE_'.length);
    }
    return null;
  }

  bool _isWordValidForGame(GermanWord word) {
    // Words should be 4-8 letters for good snake puzzles
    return word.word.length >= 4 &&
        word.word.length <= 8 &&
        !word.word.contains(" ");
  }

  void _loadLevel() {
    _score = 0;
    _puzzlesCompleted = 0;
    _loadNextPuzzle();
  }

  void _loadNextPuzzle() {
    // --- Check for game over *before* loading the next puzzle ---
    if (_puzzlesCompleted >= _totalPuzzles) {
      _showGameOver();
      return;
    }

    setState(() => _isLoading = true);

    // --- ADAPTIVE WORD SELECTION ---
    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};

    // Get review words (50%)
    final reviewItemIds = _sriService.getItemsForReview(
      limit: 10,
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
          wordsForGame.add(word);
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
      limit: 10,
      settingsProvider: _gameProvider,
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
      }
    }

    // Fill with random words if needed
    if (wordsForGame.isEmpty) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
      allWords.shuffle();

      for (final word in allWords) {
        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          wordsForGame.add(word);
          addedWordIds.add(word.id);
          if (wordsForGame.length >= 20) break;
        }
      }
    }
    // --- END ADAPTIVE SELECTION ---

    wordsForGame.shuffle();
    WordSnakeGrid? puzzle;
    GermanWord? selectedWord;

    final difficulty = _getDifficultyForGrade();
    for (final word in wordsForGame) {
      puzzle = WordSnakeGenerator().generate(word.word, difficulty);
      if (puzzle != null) {
        selectedWord = word;
        break;
      }
    }

    if (puzzle == null || selectedWord == null) {
      debugPrint("Could not generate word snake puzzle");
      // --- FIX: Check mounted before popping ---
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    setState(() {
      _currentPuzzle = puzzle;
      _currentWord = selectedWord;
      _selectedPath.clear();
      // --- REMOVED: Feedback is cleared by hint timer or _resetPath ---
      // _feedbackState = FeedbackState.none;
      // _educationalInfo = ''; 
      _isLoading = false;
    });
  }

  SnakeDifficulty _getDifficultyForGrade() {
    switch (widget.gradeLevel) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        return SnakeDifficulty.easy;
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        return SnakeDifficulty.medium;
      default:
        return SnakeDifficulty.hard;
    }
  }

  // --- DRAG AND TAP HANDLING ---

  Point? _getGridPositionFromOffset(Offset localPos) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final puzzle = _currentPuzzle;
    if (puzzle == null) return null;

    final cellWidth = box.size.width / puzzle.cols;
    final cellHeight = box.size.height / puzzle.rows;
    
    if (cellWidth <= 0 || cellHeight <= 0) return null;

    final col = (localPos.dx / cellWidth).floor();
    final row = (localPos.dy / cellHeight).floor();

    if (row >= 0 && row < puzzle.rows && col >= 0 && col < puzzle.cols) {
      return Point(col, row);
    }
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    if (_currentPuzzle == null || _feedbackState != FeedbackState.none) return;

    final pos = _getGridPositionFromOffset(details.localPosition);
    if (pos != null) {
      setState(() {
        _dragStart = pos;
        _dragCurrent = pos;
        _selectedPath.clear();
        _selectedPath.add(pos);
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStart == null || _currentPuzzle == null) return;
    
    final pos = _getGridPositionFromOffset(details.localPosition);
    if (pos != null && pos != _dragCurrent) {
      // Check if this is adjacent to the last point
      if (_selectedPath.isNotEmpty) {
        final lastPoint = _selectedPath.last;
        final isAdjacent = (pos.x - lastPoint.x).abs() <= 1 &&
            (pos.y - lastPoint.y).abs() <= 1 &&
            (pos.x == lastPoint.x || pos.y == lastPoint.y);

        if (isAdjacent && !_selectedPath.contains(pos)) {
          setState(() {
            _dragCurrent = pos;
            _selectedPath.add(pos);
            
            // Check if completed
            if (_selectedPath.length == _currentPuzzle!.word.length) {
              _checkPath();
            }
          });
        }
      }
    }
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
  }

  void _onCellTapped(int row, int col) {
    if (_currentPuzzle == null || _feedbackState != FeedbackState.none) return;

    final tappedPoint = Point(col, row);

    setState(() {
      // If this is the first cell or adjacent to the last cell
      if (_selectedPath.isEmpty) {
        _selectedPath.add(tappedPoint);
      } else {
        final lastPoint = _selectedPath.last;
        final isAdjacent = (tappedPoint.x - lastPoint.x).abs() <= 1 &&
            (tappedPoint.y - lastPoint.y).abs() <= 1 &&
            (tappedPoint.x == lastPoint.x || tappedPoint.y == lastPoint.y);

        if (isAdjacent && !_selectedPath.contains(tappedPoint)) {
          _selectedPath.add(tappedPoint);
          
          // Check if we've completed the path
          if (_selectedPath.length == _currentPuzzle!.word.length) {
            _checkPath();
          }
        } else if (_selectedPath.contains(tappedPoint)) {
          // If clicking on an already selected cell, remove from that point
          final index = _selectedPath.indexOf(tappedPoint);
          _selectedPath.removeRange(index + 1, _selectedPath.length);
        }
      }
    });
  }

  void _checkPath() {
    if (_currentPuzzle == null || _currentWord == null) return;
    final s = S.of(context)!;

    // Build the word from the selected path
    String formedWord = '';
    for (final point in _selectedPath) {
      formedWord += _currentPuzzle!.grid[point.y][point.x];
    }

    final bool isCorrect = formedWord == _currentPuzzle!.word;

    // Record in SRI
    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentWord!.word,
      wasCorrect: isCorrect,
      metadata: {
        'gradeLevel': _currentWord!.gradeLevel,
        'wordType': _currentWord!.wordType.toString(),
        'gameType': 'word_snake',
      },
    );

    // --- FIX: Cancel any old timers ---
    _feedbackTimer?.cancel();
    _hintTimer?.cancel();

    if (isCorrect) {
      _audioService.playSound('correct.mp3');
      _gameProvider.addScore(20);
      
      // Generate educational info
      final eduInfo = _getEducationalInfo(_currentWord!);
      
      setState(() {
        _score += 20;
        // --- FIX: Increment counter *after* success ---
        _puzzlesCompleted++;
        _feedbackState = FeedbackState.correct;
        _showConfetti = true; // This can be used for particle effects
        _feedbackMessage = '✓ ${_currentWord!.word.toUpperCase()}';
        _educationalInfo = eduInfo;
      });

      // --- FIX: Non-blocking flow ---
      // 1. Show hint toast for 4 seconds
      _hintTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _feedbackMessage = '';
            _educationalInfo = '';
            _feedbackState = FeedbackState.none;
          });
        }
      });
      
      // 2. After a short particle delay, load the next puzzle
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() { _showConfetti = false; });
          _loadNextPuzzle(); // This will handle the game over check
        }
      });

    } else {
      _audioService.playSound('incorrect.mp3');
      
      setState(() {
        _feedbackState = FeedbackState.incorrect;
        _feedbackMessage = '✗ ${s.tryAgain}';
        _educationalInfo = '';
      });

      // --- FIX: Non-blocking flow ---
      // 1. Show failure toast for 2 seconds
      _hintTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _feedbackMessage = '';
            _feedbackState = FeedbackState.none;
          });
        }
      });

      // 2. After 1 second, reset the path
      _feedbackTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _resetPath();
        }
      });
    }
  }

  /// --- MODIFIED: More instructive hints using inflectionData ---
  String _getEducationalInfo(GermanWord word) {
    final List<String> infoParts = [];
    
    // Add Grundwortschatz badge
    if (word.isGrundwortschatzBW) {
      infoParts.add('⭐ Grundwortschatz');
    }
    
    switch (word.wordType) {
      case GermanWordType.substantiv:
        String nounInfo = 'Nomen';
        if (word.article != null && word.article!.isNotEmpty) {
          nounInfo += ' (${word.article})';
        }
        infoParts.add(nounInfo);
        
        if (word.genus != null && word.genus!.isNotEmpty) {
          infoParts.add('Genus: ${word.genus}');
        }

        if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
          infoParts.add('Plural: ${word.plural}');
        }
        break;
        
      case GermanWordType.verb:
        infoParts.add('Verb (Tun-Wort)');
        String? ichForm, duForm, erForm;

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
          infoParts.add('z.B. ich $ichForm, du $duForm, er $erForm');
        } 
        else if (word.forms != null && word.forms!.isNotEmpty) {
          infoParts.add('Formen: ${word.forms}');
        }
        break;
        
      case GermanWordType.adjektiv:
        String adjInfo = 'Adjektiv (Wie-Wort)';
        if (word.degreeSpacy != null && word.degreeSpacy == 'Pos') {
          adjInfo = 'Adjektiv (Positiv)';
        }
        infoParts.add(adjInfo);
        
        String? komparativ, superlativ;
        
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

        if (komparativ != null && superlativ != null && komparativ.isNotEmpty && superlativ.isNotEmpty) {
          infoParts.add('Steigerung: ${word.word}, $komparativ, $superlativ');
        } 
        else if (word.forms != null && word.forms!.isNotEmpty) {
          infoParts.add('Steigerung: ${word.forms}');
        }
        break;
        
      case GermanWordType.pronomen:
        infoParts.add('Pronomen');
        if (word.caseSpacy != null && word.caseSpacy!.isNotEmpty) {
          final caseMap = {'Nom': 'Nominativ', 'Acc': 'Akkusativ', 'Dat': 'Dativ', 'Gen': 'Genitiv'};
          infoParts.add(caseMap[word.caseSpacy] ?? word.caseSpacy!);
        }
        if (word.pronTypeSpacy != null && word.pronTypeSpacy!.isNotEmpty) {
          infoParts.add(word.pronTypeSpacy!);
        }
        break;
        
      case GermanWordType.artikel:
        infoParts.add('Artikel');
        if (word.caseSpacy != null && word.caseSpacy!.isNotEmpty) {
          final caseMap = {'Nom': 'Nominativ', 'Acc': 'Akkusativ', 'Dat': 'Dativ', 'Gen': 'Genitiv'};
          infoParts.add(caseMap[word.caseSpacy] ?? word.caseSpacy!);
        }
        if (word.genus != null && word.genus!.isNotEmpty) {
          infoParts.add(word.genus!.toLowerCase());
        }
        break;
        
      default:
        final typeMap = {
          GermanWordType.adverb: 'Adverb',
          GermanWordType.praeposition: 'Präposition',
          GermanWordType.konjunktion: 'Konjunktion',
          GermanWordType.partikel: 'Partikel',
          GermanWordType.numerale: 'Numerale',
        };
        final typeLabel = typeMap[word.wordType];
        if (typeLabel != null) {
          infoParts.add(typeLabel);
        }
    }
    
    // Add one example sentence if available
    if (word.exampleSentences.isNotEmpty) {
      final example = word.exampleSentences[0];
      infoParts.add('z.B.: $example');
    }
    
    if (infoParts.isEmpty) return '✓ ${word.word.toUpperCase()}';
    return infoParts.join(' • ');
  }

  // --- REMOVED: _getRandomVerbConjugation (logic moved into _getEducationalInfo) ---

  void _resetPath() {
    setState(() {
      _selectedPath.clear();
      _feedbackState = FeedbackState.none;
      _feedbackMessage = '';
      _educationalInfo = '';
    });
  }

  void _showGameOver() {
    final s = S.of(context)!;
    _gameProvider.recordLevelWin(
      gameType: 'word_snake_game',
      scoreGained: _score,
      difficulty: widget.gradeLevel.index + 1,
      wasSuccessful: _puzzlesCompleted >= (_totalPuzzles * 0.7),
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
            Text(
              '${s.score}: $_score',
              style: SpaceTheme.titleStyle.copyWith(color: SpaceTheme.starYellow),
            ),
            const SizedBox(height: 16),
            Text(
              '$_puzzlesCompleted / $_totalPuzzles ${s.correct}',
              style: SpaceTheme.bodyStyle,
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
    final s = S.of(context)!;

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              GameUI(
                title: s.wordSnakeTitle,
                level: widget.gradeLevel.index + 1,
                onBack: () => Navigator.of(context).pop(),
              ),
              if (_isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                // --- MODIFIED: Wrap game content in a Stack for the toast ---
                Expanded(
                  child: Stack(
                    children: [
                      _buildGameContent(s),
                      
                      // --- NEW: Non-blocking feedback toast ---
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        top: _feedbackMessage.isNotEmpty ? 20.0 : -150.0,
                        right: 20.0,
                        left: 20.0,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: _buildFeedbackToast(s),
                        ),
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

  Widget _buildGameContent(S s) { // --- MODIFIED: Pass S ---
    if (_currentPuzzle == null) return const SizedBox.shrink();
    
    return Column( 
      // --- FIX: Remove MainAxisAlignment.center ---
      // mainAxisAlignment: MainAxisAlignment.center, 
      children: [
        // Progress indicator
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            // --- FIX: Clamp the displayed puzzle number to never exceed the total ---
            s.wordSnakePuzzleProgress(min(_puzzlesCompleted + 1, _totalPuzzles), _totalPuzzles),
            style: SpaceTheme.titleStyle.copyWith(
              color: SpaceTheme.starYellow,
            ),
          ),
        ),
        
        // --- FIX: Wrap the grid in Expanded ---
        // This gives the grid all the remaining space between the 
        // progress text (top) and the button (bottom).
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _buildGrid(),
            ),
          ),
        ),

        // Hint and reset button
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                s.wordSnakeConnectLetters(_currentPuzzle!.word.length),
                style: SpaceTheme.bodyStyle,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _feedbackState == FeedbackState.none ? _resetPath : null,
                icon: const Icon(Icons.refresh),
                label: Text(s.wordSnakeReset),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpaceTheme.cosmicPink,
                ),
              ),
            ],
          ),
        ),
        
        // --- REMOVED: All the old feedback overlays ---
      ],
    );
  }

  Widget _buildGrid() {
    final puzzle = _currentPuzzle!;
    
    // --- Responsive Cell Size ---
    // Use LayoutBuilder to get the available space
    return LayoutBuilder(
      builder: (context, constraints) {
        // Find the largest possible square cell size
        final double maxWidth = constraints.maxWidth;
        final double maxHeight = constraints.maxHeight; // Not always available, but good to check
        
        // Calculate cell size based on width
        double cellSize = (maxWidth / puzzle.cols) - 4; // 4 for spacing
        
        // If height is constrained, check against that too
        if (maxHeight.isFinite && maxHeight > 0) {
          final double cellHeight = (maxHeight / puzzle.rows) - 4;
          cellSize = min(cellSize, cellHeight);
        }
        
        // Set a max cell size
        cellSize = min(cellSize, 80.0);

        return GestureDetector(
          key: _gridKey,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: SizedBox(
            width: puzzle.cols * (cellSize + 4),
            height: puzzle.rows * (cellSize + 4),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: puzzle.cols,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.0, // Ensure cells are square
              ),
              itemCount: puzzle.rows * puzzle.cols,
              itemBuilder: (context, index) {
                final row = index ~/ puzzle.cols;
                final col = index % puzzle.cols;
                // --- Pass cell size to _buildCell ---
                return _buildCell(row, col, cellSize);
              },
            ),
          ),
        );
      }
    );
  }

  Widget _buildCell(int row, int col, double cellSize) {
    final puzzle = _currentPuzzle!;
    final letter = puzzle.grid[row][col];
    final point = Point(col, row);
    
    final isSelected = _selectedPath.contains(point);
    final selectionIndex = _selectedPath.indexOf(point);

    Color bgColor;
    Color textColor = Colors.white;
    String? orderText;
    
    // --- Dynamic font size ---
    final fontSize = cellSize * 0.4; // 40% of cell size
    final orderCircleSize = cellSize * 0.25; // 25% of cell size
    final orderFontSize = cellSize * 0.15; // 15% of cell size

    if (_feedbackState == FeedbackState.correct && isSelected) {
      bgColor = SpaceTheme.alienGreen;
      textColor = SpaceTheme.deepSpace;
      orderText = '${selectionIndex + 1}';
    } else if (_feedbackState == FeedbackState.incorrect && isSelected) {
      bgColor = SpaceTheme.rocketRed;
      orderText = '${selectionIndex + 1}';
    } else if (isSelected) {
      bgColor = SpaceTheme.planetOrange;
      orderText = '${selectionIndex + 1}';
    } else {
      bgColor = SpaceTheme.nebulaPurple.withOpacity(0.6);
    }

    return GestureDetector(
      onTap: () => _onCellTapped(row, col),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? SpaceTheme.starYellow
                : SpaceTheme.deepSpace.withOpacity(0.3),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: SpaceTheme.starYellow.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: fontSize, // Dynamic font size
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  shadows: const [
                    Shadow(blurRadius: 4, color: Colors.black54),
                  ],
                ),
              ),
            ),
            if (orderText != null)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: orderCircleSize, // Dynamic size
                  height: orderCircleSize, // Dynamic size
                  decoration: BoxDecoration(
                    color: SpaceTheme.starYellow,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      orderText,
                      style: TextStyle(
                        fontSize: orderFontSize, // Dynamic font size
                        fontWeight: FontWeight.bold,
                        color: SpaceTheme.deepSpace,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  /// --- NEW: Feedback Toast Widget ---
  Widget _buildFeedbackToast(S s) {
    if (_feedbackMessage.isEmpty) { 
      return const SizedBox.shrink();
    }
    
    final isSuccess = _feedbackState == FeedbackState.correct;
    
    final color = isSuccess ? Colors.green : SpaceTheme.rocketRed;
    final icon = isSuccess ? Icons.check_circle : Icons.cancel;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
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
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (_educationalInfo.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Divider(color: Colors.white24),
              ),
              Text(
                _educationalInfo,
                style: SpaceTheme.bodyStyle.copyWith(
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