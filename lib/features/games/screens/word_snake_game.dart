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
  
  FeedbackState _feedbackState = FeedbackState.none;
  Timer? _feedbackTimer;
  bool _showConfetti = false;
  String _educationalInfo = '';

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
        final word = _vocabularyService.allWords.firstWhere(
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
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
      }
    }

    // Fill with random words if needed
    if (wordsForGame.isEmpty) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel);
      allWords.shuffle();

      for (final word in allWords) {
        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          wordsForGame.add(word);
          addedWordIds.add(word.id);
          if (wordsForGame.length >= 20) break;
        }
      }
    }

    // Try to generate a puzzle with one of the words
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
      // Fallback: couldn't generate puzzle
      debugPrint("Could not generate word snake puzzle");
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _currentPuzzle = puzzle;
      _currentWord = selectedWord;
      _selectedPath.clear();
      _feedbackState = FeedbackState.none;
      _educationalInfo = '';
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

    if (isCorrect) {
      _audioService.playSound('correct.mp3');
      _gameProvider.addScore(20);
      
      // Generate educational info
      final eduInfo = _getEducationalInfo(_currentWord!);
      
      setState(() {
        _score += 20;
        _puzzlesCompleted++;
        _feedbackState = FeedbackState.correct;
        _showConfetti = true;
        _educationalInfo = eduInfo;
      });

      // Show success feedback, then load next puzzle
      _feedbackTimer = Timer(const Duration(milliseconds: 2500), () {
        setState(() {
          _showConfetti = false;
        });
        _loadNextPuzzle();
      });
    } else {
      _audioService.playSound('incorrect.mp3');
      
      setState(() {
        _feedbackState = FeedbackState.incorrect;
      });

      // Show error feedback, then reset
      _feedbackTimer = Timer(const Duration(milliseconds: 1000), () {
        setState(() {
          _selectedPath.clear();
          _feedbackState = FeedbackState.none;
        });
      });
    }
  }

  /// Generates educational info for the word
  String _getEducationalInfo(GermanWord word) {
    final List<String> infoParts = [];
    /*
    // Add CEFR level from sources (A1, A2, B1, etc.)
    if (word.sources.isNotEmpty) {
      final levels = word.sources.where((s) => s.startsWith('A') || s.startsWith('B'));
      if (levels.isNotEmpty) {
        infoParts.add('Niveau: ${levels.first}');
      }
    }*/
    
    // Add Grundwortschatz badge
    if (word.isGrundwortschatzBW) {
      infoParts.add('⭐ ');
    }
    
    switch (word.wordType) {
      case GermanWordType.substantiv:
        if (word.article != null && word.article!.isNotEmpty) {
          infoParts.add(word.article!);
        }
        
        // Add number (Singular/Plural)
        if (word.numberSpacy != null && word.numberSpacy!.isNotEmpty) {
          final numberMap = {
            'Sing': 'Singular',
            'Plur': 'Plural',
          };
          infoParts.add(numberMap[word.numberSpacy] ?? word.numberSpacy!);
        }
        
        if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
          infoParts.add('Plural: ${word.plural}');
        }
        
        if (word.genus != null && word.genus!.isNotEmpty) {
          infoParts.add(word.genus!.toLowerCase());
        }
        break;
        
      case GermanWordType.verb:
        // Try to show conjugation from inflectionData
        if (word.inflectionData != null && word.inflectionData!.isNotEmpty) {
          final conjugation = _getRandomVerbConjugation(word.inflectionData!);
          if (conjugation != null) {
            infoParts.add(conjugation);
          }
        }
        
        // Show verb form info
        if (word.verbFormSpacy != null && word.verbFormSpacy!.isNotEmpty) {
          final verbFormMap = {
            'Inf': 'Infinitiv',
            'Fin': 'finit',
            'Part': 'Partizip',
          };
          final verbForm = verbFormMap[word.verbFormSpacy] ?? word.verbFormSpacy!;
          if (infoParts.isEmpty || !infoParts.any((p) => p.contains(':'))) {
            infoParts.add(verbForm);
          }
        }
        
        // Show forms if available (conjugations)
        if (infoParts.length <= 2 && word.forms != null && word.forms!.isNotEmpty) {
          final formsList = word.forms!.split(',').take(2);
          for (final form in formsList) {
            final trimmed = form.trim();
            if (trimmed.isNotEmpty) {
              infoParts.add(trimmed);
            }
          }
        }
        
        if (infoParts.isEmpty || (infoParts.length == 1 && infoParts[0].startsWith('Niveau'))) {
          infoParts.add('Verb');
        }
        break;
        
      case GermanWordType.adjektiv:
        // Try to show comparative and superlative from inflectionData
        if (word.inflectionData != null) {
          final comparative = word.inflectionData!['comparative'];
          final superlative = word.inflectionData!['superlative'];
          
          if (comparative != null && comparative.toString().isNotEmpty && comparative != '-') {
            infoParts.add(comparative.toString());
          }
          if (superlative != null && superlative.toString().isNotEmpty && superlative != '-') {
            infoParts.add(superlative.toString());
          }
        }
        
        // Show degree info if available
        if (word.degreeSpacy != null && word.degreeSpacy!.isNotEmpty && infoParts.length <= 2) {
          final degreeMap = {
            'Pos': 'Positiv',
            'Cmp': 'Komparativ',
            'Sup': 'Superlativ',
          };
          final degreeLabel = degreeMap[word.degreeSpacy] ?? word.degreeSpacy!;
          if (!infoParts.any((p) => p.contains('er') || p.contains('sten'))) {
            infoParts.add(degreeLabel);
          }
        }
        
        // Show forms if available (comparative/superlative)
        if (infoParts.length <= 2 && word.forms != null && word.forms!.isNotEmpty) {
          final formsList = word.forms!.split(',').take(2);
          for (final form in formsList) {
            final trimmed = form.trim();
            if (trimmed.isNotEmpty) {
              infoParts.add(trimmed);
            }
          }
        }
        
        if (infoParts.isEmpty || (infoParts.length == 1 && infoParts[0].startsWith('Niveau'))) {
          infoParts.add('Adjektiv');
        }
        break;
        
      case GermanWordType.pronomen:
        // Show case if available
        if (word.caseSpacy != null && word.caseSpacy!.isNotEmpty) {
          final caseMap = {
            'Nom': 'Nominativ',
            'Acc': 'Akkusativ',
            'Dat': 'Dativ',
            'Gen': 'Genitiv',
          };
          infoParts.add(caseMap[word.caseSpacy] ?? word.caseSpacy!);
        }
        
        // Show number
        if (word.numberSpacy != null && word.numberSpacy!.isNotEmpty) {
          final numberMap = {
            'Sing': 'Singular',
            'Plur': 'Plural',
          };
          infoParts.add(numberMap[word.numberSpacy] ?? word.numberSpacy!);
        }
        
        // Show pronoun type
        if (word.pronTypeSpacy != null && word.pronTypeSpacy!.isNotEmpty) {
          infoParts.add(word.pronTypeSpacy!);
        }
        
        if (infoParts.isEmpty || (infoParts.length == 1 && infoParts[0].startsWith('Niveau'))) {
          infoParts.add('Pronomen');
        }
        break;
        
      case GermanWordType.artikel:
        // Show case and gender info
        if (word.caseSpacy != null && word.caseSpacy!.isNotEmpty) {
          final caseMap = {
            'Nom': 'Nominativ',
            'Acc': 'Akkusativ',
            'Dat': 'Dativ',
            'Gen': 'Genitiv',
          };
          infoParts.add(caseMap[word.caseSpacy] ?? word.caseSpacy!);
        }
        
        if (word.genus != null && word.genus!.isNotEmpty) {
          infoParts.add(word.genus!.toLowerCase());
        }
        
        if (word.numberSpacy != null && word.numberSpacy!.isNotEmpty) {
          final numberMap = {
            'Sing': 'Singular',
            'Plur': 'Plural',
          };
          infoParts.add(numberMap[word.numberSpacy] ?? word.numberSpacy!);
        }
        
        if (infoParts.isEmpty || (infoParts.length == 1 && infoParts[0].startsWith('Niveau'))) {
          infoParts.add('Artikel');
        }
        break;
        
      case GermanWordType.adverb:
        infoParts.add('Adverb');
        break;
        
      case GermanWordType.praeposition:
        infoParts.add('Präposition');
        break;
        
      case GermanWordType.konjunktion:
        infoParts.add('Konjunktion');
        break;
        
      default:
        final typeMap = {
          GermanWordType.partikel: 'Partikel',
          GermanWordType.numerale: 'Numerale',
        };
        final typeLabel = typeMap[word.wordType];
        if (typeLabel != null) {
          infoParts.add(typeLabel);
        }
    }
    
    // Add one example sentence if available (keep it short)
    if (word.exampleSentences.isNotEmpty && infoParts.length < 4) {
      final example = word.exampleSentences[0];
      if (example.length <= 50) {
        infoParts.add('z.B.: $example');
      }
    }
    
    /* 
    // Add common mistakes if available
    if (word.commonMistakes != null && word.commonMistakes!.isNotEmpty && infoParts.length < 5) {
      final mistakes = word.commonMistakes!.take(2).join(', ');
      infoParts.add('⚠️ nicht: $mistakes');
    } */
    
    if (infoParts.isEmpty) return '';
    return infoParts.join(' • ');
  }

  /// Gets a random verb conjugation from inflectionData
  String? _getRandomVerbConjugation(Map<String, dynamic> inflectionData) {
    final random = Random();
    
    final options = [
      ('Präsens', ['ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr']),
      ('Präteritum', ['ich', 'du', 'er', 'sie', 'es']),
      ('Perfekt', ['ich', 'du', 'er']),
    ];
    
    options.shuffle(random);
    
    for (final (tense, persons) in options) {
      final tenseKeys = [
        tense,
        tense.toLowerCase(),
        tense.replaceAll('ä', 'a').replaceAll('ü', 'u'),
        'present',
        'past',
        'perfect',
      ];
      
      for (final tenseKey in tenseKeys) {
        if (inflectionData.containsKey(tenseKey)) {
          final tenseData = inflectionData[tenseKey];
          if (tenseData is Map) {
            final shuffledPersons = List<String>.from(persons)..shuffle(random);
            
            for (final person in shuffledPersons) {
              if (tenseData.containsKey(person)) {
                final form = tenseData[person];
                if (form != null && form.toString().isNotEmpty && form != '-') {
                  return '$person: $form';
                }
              }
            }
          }
        }
      }
    }
    
    return null;
  }

  void _resetPath() {
    setState(() {
      _selectedPath.clear();
      _feedbackState = FeedbackState.none;
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
                _buildGameContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameContent() {
    if (_currentPuzzle == null) return const SizedBox.shrink();
    final s = S.of(context)!;

    return Expanded(
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Progress indicator
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  s.wordSnakePuzzleProgress(_puzzlesCompleted + 1, _totalPuzzles),
                  style: SpaceTheme.titleStyle.copyWith(
                    color: SpaceTheme.starYellow,
                  ),
                ),
              ),
              
              // The grid
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildGrid(),
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
            ],
          ),
          
          // Success overlay with educational info
          if (_feedbackState == FeedbackState.correct)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SpaceTheme.starYellow, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '✓ ${_currentWord!.word.toUpperCase()}',
                      style: SpaceTheme.headlineStyle.copyWith(fontSize: 32),
                    ),
                    if (_educationalInfo.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _educationalInfo,
                        style: SpaceTheme.bodyStyle.copyWith(
                          fontSize: 16,
                          color: SpaceTheme.starYellow,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_showConfetti) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '🎉',
                        style: TextStyle(fontSize: 60),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Failure overlay
          if (_feedbackState == FeedbackState.incorrect)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '✗ ${s.tryAgain}',
                  style: SpaceTheme.headlineStyle.copyWith(fontSize: 32),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final puzzle = _currentPuzzle!;
    final cellSize = 80.0;

    return GestureDetector(
      key: _gridKey,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: SizedBox(
        width: puzzle.cols * cellSize,
        height: puzzle.rows * cellSize,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: puzzle.cols,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: puzzle.rows * puzzle.cols,
          itemBuilder: (context, index) {
            final row = index ~/ puzzle.cols;
            final col = index % puzzle.cols;
            return _buildCell(row, col);
          },
        ),
      ),
    );
  }

  Widget _buildCell(int row, int col) {
    final puzzle = _currentPuzzle!;
    final letter = puzzle.grid[row][col];
    final point = Point(col, row);
    
    final isSelected = _selectedPath.contains(point);
    final selectionIndex = _selectedPath.indexOf(point);

    Color bgColor;
    Color textColor = Colors.white;
    String? orderText;

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
                  fontSize: 32,
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
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: SpaceTheme.starYellow,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      orderText,
                      style: TextStyle(
                        fontSize: 12,
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
}