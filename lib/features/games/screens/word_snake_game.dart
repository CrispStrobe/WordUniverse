// ignore_for_file: unused_element, unused_field
// lib/features/games/screens/word_snake_game.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../services/word_snake_generator.dart';
import '../providers/game_provider.dart';
import '../services/adaptive_word_selection.dart';
import '../widgets/space_background.dart';
import '../models/game_outcome.dart';

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
  bool _loadFailed = false;
  int _puzzleGeneration = 0;
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
  
  // Feedback State
  FeedbackState _feedbackState = FeedbackState.none;
  Timer? _feedbackTimer;
  Timer? _hintTimer;
  bool _showConfetti = false;
  String _educationalInfo = '';
  String _feedbackMessage = '';
  
  // Instruction hint
  String _instructionHint = '';
  Timer? _instructionTimer;

  // Screen detection helpers
  bool _isSmallScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.shortestSide < 600;
  }

  bool _isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }

  bool _isLandscapeMode(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

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
    _hintTimer?.cancel();
    _instructionTimer?.cancel();
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

    await _loadLevel();
  }



  bool _isWordValidForGame(GermanWord word) {
    return word.word.length >= 4 &&
        word.word.length <= 8 &&
        !word.word.contains(" ");
  }

  Future<void> _loadLevel() async {
    _score = 0;
    _puzzlesCompleted = 0;
    await _loadNextPuzzle();
  }

  SnakeDifficulty _getAdjustedDifficulty(String word, SnakeDifficulty baseDifficulty) {
    final length = word.length;

    if (length > 7) {
        return SnakeDifficulty.hard;
    }
    if (length > 5) {
        return (baseDifficulty == SnakeDifficulty.hard) 
            ? SnakeDifficulty.hard 
            : SnakeDifficulty.medium;
    }
    
    return baseDifficulty;
  }

  Future<void> _loadNextPuzzle() async {
    if (_puzzlesCompleted >= _totalPuzzles) {
      _showGameOver();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final wordsForGame = selectAdaptiveWords(
      vocabulary: _vocabularyService,
      sri: _sriService,
      settings: _gameProvider,
      grade: widget.gradeLevel,
      count: 20,
      isPlayable: _isWordValidForGame,
      skillFilter: LanguageSkillType.spelling,
      reviewQueueLimit: 10,
    )..shuffle();
    wordsForGame.shuffle();
    // Example sentences come from the enrichment, so decode it for these words.
    final playable = await _vocabularyService.hydrate(wordsForGame);
    if (!mounted) return;
    WordSnakeGrid? puzzle;
    GermanWord? selectedWord;

    final baseDifficulty = _getDifficultyForGrade();
    
    for (final word in playable) {
      final adjustedDifficulty = _getAdjustedDifficulty(word.word, baseDifficulty);
      
      puzzle = WordSnakeGenerator().generate(word.word, adjustedDifficulty);
      
      if (puzzle != null && (puzzle.rows < 2 || puzzle.cols < 2)) {
        if (kDebugMode) debugPrint("WordSnakeGenerator created an invalid 1-D grid. Discarding.");
        puzzle = null;
      }
      
      if (puzzle != null) {
        selectedWord = word;
        break;
      }
    }

    if (puzzle == null || selectedWord == null) {
      if (kDebugMode) debugPrint("Could not generate word snake puzzle");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
          _currentPuzzle = null;
          _currentWord = null;
        });
      }
      return;
    }

    final s = S.of(context)!;
    // Advancing to a new puzzle invalidates any pending feedback timer.
    _puzzleGeneration++;
    setState(() {
      _loadFailed = false;
      _currentPuzzle = puzzle;
      _currentWord = selectedWord;
      _selectedPath.clear();
      _feedbackState = FeedbackState.none;
      _feedbackMessage = '';
      _educationalInfo = '';
      _isLoading = false;

      // Show instruction hint
      _instructionHint = s.wordSnakeConnectLetters(puzzle!.word.length);
    });
    
    // Auto-hide instruction after 3 seconds
    _instructionTimer?.cancel();
    _instructionTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _instructionHint = '';
        });
      }
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
      if (_selectedPath.isNotEmpty) {
        final lastPoint = _selectedPath.last;
        final isAdjacent = (pos.x - lastPoint.x).abs() <= 1 &&
            (pos.y - lastPoint.y).abs() <= 1 &&
            (pos.x == lastPoint.x || pos.y == lastPoint.y);

        if (isAdjacent && !_selectedPath.contains(pos)) {
          setState(() {
            _dragCurrent = pos;
            _selectedPath.add(pos);
            
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
      if (_selectedPath.isEmpty) {
        _selectedPath.add(tappedPoint);
      } else {
        final lastPoint = _selectedPath.last;
        final isAdjacent = (tappedPoint.x - lastPoint.x).abs() <= 1 &&
            (tappedPoint.y - lastPoint.y).abs() <= 1 &&
            (tappedPoint.x == lastPoint.x || tappedPoint.y == lastPoint.y);

        if (isAdjacent && !_selectedPath.contains(tappedPoint)) {
          _selectedPath.add(tappedPoint);
          
          if (_selectedPath.length == _currentPuzzle!.word.length) {
            _checkPath();
          }
        } else if (_selectedPath.contains(tappedPoint)) {
          final index = _selectedPath.indexOf(tappedPoint);
          _selectedPath.removeRange(index + 1, _selectedPath.length);
        }
      }
    });
  }

  void _checkPath() {
    if (_currentPuzzle == null || _currentWord == null) return;
    final s = S.of(context)!;

    String formedWord = '';
    for (final point in _selectedPath) {
      formedWord += _currentPuzzle!.grid[point.y][point.x];
    }

    final bool isCorrect = formedWord == _currentPuzzle!.word;

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

    _feedbackTimer?.cancel();
    _hintTimer?.cancel();

    if (isCorrect) {
      _audioService.playSound('success');
      _gameProvider.hapticLight();
      final eduInfo = _getEducationalInfo(s, _currentWord!);
      final int generation = _puzzleGeneration;

      setState(() {
        _score += 20;
        _puzzlesCompleted++;
        _feedbackState = FeedbackState.correct;
        _showConfetti = true;
        _feedbackMessage = '✓ ${_currentWord!.word.toUpperCase()}';
        _educationalInfo = eduInfo;
      });

      Timer(const Duration(milliseconds: 500), () {
        if (mounted && generation == _puzzleGeneration) {
          setState(() { _showConfetti = false; });
        }
      });

      // Show the educational toast for a moment, then advance. Guarding on the
      // captured generation stops a stale timer from wiping the next puzzle.
      _hintTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted || generation != _puzzleGeneration) return;
        setState(() {
          _feedbackMessage = '';
          _educationalInfo = '';
          _feedbackState = FeedbackState.none;
        });
        _loadNextPuzzle();
      });

    } else {
      _audioService.playSound('failure');
      _gameProvider.hapticHeavy();

      final int generation = _puzzleGeneration;

      setState(() {
        _feedbackState = FeedbackState.incorrect;
        _feedbackMessage = '✗ ${s.tryAgain}';
        _educationalInfo = '';
      });

      _hintTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && generation == _puzzleGeneration) {
          setState(() {
            _feedbackMessage = '';
            _feedbackState = FeedbackState.none;
          });
        }
      });

      _feedbackTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted && generation == _puzzleGeneration) {
          _resetPath();
        }
      });
    }
  }

  String _caseLabel(S s, String? caseSpacy) {
    switch (caseSpacy) {
      case 'Nom':
        return s.wordSnakeCaseNominative;
      case 'Acc':
        return s.wordSnakeCaseAccusative;
      case 'Dat':
        return s.wordSnakeCaseDative;
      case 'Gen':
        return s.wordSnakeCaseGenitive;
      default:
        return caseSpacy ?? '';
    }
  }

  String _getEducationalInfo(S s, GermanWord word) {
    final List<String> infoParts = [];

    if (word.isGrundwortschatzBW) {
      infoParts.add(s.wordSnakeBasicVocabulary);
    }

    switch (word.wordType) {
      case GermanWordType.substantiv:
        if (word.article != null && word.article!.isNotEmpty) {
          infoParts.add(s.wordSnakeNounWithArticle(word.article!));
        } else {
          infoParts.add(s.wordSnakeNoun);
        }

        if (word.genus != null && word.genus!.isNotEmpty) {
          infoParts.add(s.wordSnakeGenus(word.genus!));
        }

        if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
          infoParts.add(s.wordSnakePlural(word.plural!));
        }
        break;

      case GermanWordType.verb:
        infoParts.add(s.wordSnakeVerb);
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
            if (kDebugMode) debugPrint('Error parsing verb inflectionData for ${word.word}: $e');
          }
        }

        if (ichForm != null && duForm != null && erForm != null) {
          infoParts.add(s.wordSnakeVerbForms(ichForm, duForm, erForm));
        }
        else if (word.forms != null && word.forms!.isNotEmpty) {
          infoParts.add(s.wordSnakeForms(word.forms!));
        }
        break;

      case GermanWordType.adjektiv:
        if (word.degreeSpacy != null && word.degreeSpacy == 'Pos') {
          infoParts.add(s.wordSnakeAdjectivePositive);
        } else {
          infoParts.add(s.wordSnakeAdjective);
        }

        String? komparativ, superlativ;

        if (word.inflectionData != null) {
           try {
              final comparison = word.inflectionData!['analyses']?['adjektiv']?['comparison'] as Map<String, dynamic>?;
              if (comparison != null) {
                komparativ = comparison['Komparativ'] as String?;
                superlativ = comparison['Superlativ'] as String?;
              }
            } catch (e) {
               if (kDebugMode) debugPrint('Error parsing adj inflectionData for ${word.word}: $e');
            }
        }

        if (komparativ != null && superlativ != null && komparativ.isNotEmpty && superlativ.isNotEmpty) {
          infoParts.add(s.wordSnakeComparison('${word.word}, $komparativ, $superlativ'));
        }
        else if (word.forms != null && word.forms!.isNotEmpty) {
          infoParts.add(s.wordSnakeComparison(word.forms!));
        }
        break;

      case GermanWordType.pronomen:
        infoParts.add(s.wordSnakePronoun);
        if (word.caseSpacy != null && word.caseSpacy!.isNotEmpty) {
          infoParts.add(_caseLabel(s, word.caseSpacy));
        }
        if (word.pronTypeSpacy != null && word.pronTypeSpacy!.isNotEmpty) {
          infoParts.add(word.pronTypeSpacy!);
        }
        break;

      case GermanWordType.artikel:
        infoParts.add(s.wordSnakeArticle);
        if (word.caseSpacy != null && word.caseSpacy!.isNotEmpty) {
          infoParts.add(_caseLabel(s, word.caseSpacy));
        }
        if (word.genus != null && word.genus!.isNotEmpty) {
          infoParts.add(word.genus!.toLowerCase());
        }
        break;

      default:
        String? typeLabel;
        switch (word.wordType) {
          case GermanWordType.adverb:
            typeLabel = s.wordSnakeAdverb;
            break;
          case GermanWordType.praeposition:
            typeLabel = s.wordSnakePreposition;
            break;
          case GermanWordType.konjunktion:
            typeLabel = s.wordSnakeConjunction;
            break;
          case GermanWordType.partikel:
            typeLabel = s.wordSnakeParticle;
            break;
          case GermanWordType.numerale:
            typeLabel = s.wordSnakeNumeral;
            break;
          default:
            typeLabel = null;
        }
        if (typeLabel != null) {
          infoParts.add(typeLabel);
        }
    }

    if (word.exampleSentences.isNotEmpty) {
      final example = word.exampleSentences[0];
      infoParts.add(s.wordSnakeExample(example));
    }

    if (infoParts.isEmpty) return '✓ ${word.word.toUpperCase()}';
    return infoParts.join(' • ');
  }

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
    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'word_snake_game',
      difficulty: widget.gradeLevel.index + 1,
      score: _score,
      wasSuccessful: _puzzlesCompleted >= (_totalPuzzles * 0.7),
    ));

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
            autofocus: true,
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
    final String selectedFontFamily = context.watch<GameProvider>().selectedFontFamily;

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(s),
              if (_isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_loadFailed)
                Expanded(child: _buildLoadFailed(s))
              else
                Expanded(
                  child: Stack(
                    children: [
                      _buildGameContent(selectedFontFamily),
                      
                      // Feedback toast
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        top: _feedbackMessage.isNotEmpty ? 80.0 : -200.0,
                        right: 20.0,
                        left: 20.0,
                        child: _buildFeedbackToast(s),
                      ),
                      
                      // Instruction hint toast
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        bottom: _instructionHint.isNotEmpty ? 20.0 : -100.0,
                        left: 20.0,
                        right: 20.0,
                        child: _buildInstructionToast(),
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

  Widget _buildTopBar(S s) {
    final isLandscape = _isLandscapeMode(context);
    final totalScore = context.watch<GameProvider>().score;
    
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isLandscape ? 12 : 16,
        vertical: isLandscape ? 6 : 10,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 12 : 16,
        vertical: isLandscape ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(isLandscape ? 16 : 20),
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
          // Back button
          Semantics(
            label: S.of(context)!.semanticsBack,
            button: true,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white, size: isLandscape ? 20 : 24),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Title
          Expanded(
            child: Text(
              s.wordSnakeTitle,
              style: SpaceTheme.titleStyle.copyWith(
                fontSize: isLandscape ? 16 : 18,
              ),
            ),
          ),
          
          // Progress indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: SpaceTheme.starYellow.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SpaceTheme.starYellow, width: 1.5),
            ),
            child: Text(
              s.wordSnakePuzzleProgress(
                min(_puzzlesCompleted + 1, _totalPuzzles),
                _totalPuzzles,
              ),
              style: TextStyle(
                color: SpaceTheme.starYellow,
                fontWeight: FontWeight.bold,
                fontSize: isLandscape ? 12 : 14,
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Reset button
          Semantics(
            label: s.wordSnakeResetSelection,
            button: true,
            enabled: _feedbackState == FeedbackState.none,
            child: Material(
              color: SpaceTheme.cosmicPink,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _feedbackState == FeedbackState.none ? _resetPath : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: EdgeInsets.all(isLandscape ? 8 : 10),
                  child: Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: isLandscape ? 18 : 20,
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Score
          Semantics(
            label: s.wordSnakeScoreLabel(totalScore),
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: SpaceTheme.alienGreen.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.white, size: isLandscape ? 14 : 16),
                  const SizedBox(width: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$totalScore',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isLandscape ? 12 : 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadFailed(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sentiment_dissatisfied,
                color: SpaceTheme.starYellow, size: 56),
            const SizedBox(height: 16),
            Text(
              s.wordSnakeNoPuzzles,
              style: SpaceTheme.bodyStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpaceTheme.planetOrange,
                ),
                child: Text(s.backToMenu),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameContent(String selectedFontFamily) {
    if (_currentPuzzle == null) return const SizedBox.shrink();
    
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: _isLandscapeMode(context) ? 40 : 24,
          vertical: _isLandscapeMode(context) ? 20 : 24,
        ),
        child: _buildGrid(selectedFontFamily),
      ),
    );
  }

  Widget _buildGrid(String selectedFontFamily) {
    final puzzle = _currentPuzzle!;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate maximum available space
        final double availableWidth = constraints.maxWidth;
        final double availableHeight = constraints.maxHeight;
        
        // Calculate cell size based on both dimensions
        double cellSizeByWidth = (availableWidth / puzzle.cols) - 6;
        double cellSizeByHeight = (availableHeight / puzzle.rows) - 6;
        
        // Use the smaller dimension to ensure grid fits
        double cellSize = min(cellSizeByWidth, cellSizeByHeight);
        
        // Apply reasonable limits. Floor of 48dp keeps tap targets accessible.
        cellSize = cellSize.clamp(48.0, 100.0);
        
        // Calculate actual grid dimensions
        final gridWidth = (puzzle.cols * cellSize) + ((puzzle.cols - 1) * 6);
        final gridHeight = (puzzle.rows * cellSize) + ((puzzle.rows - 1) * 6);

        return Center(
          child: GestureDetector(
            key: _gridKey,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: SizedBox(
              width: gridWidth,
              height: gridHeight,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: puzzle.cols,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 1.0,
                ),
                itemCount: puzzle.rows * puzzle.cols,
                itemBuilder: (context, index) {
                  final row = index ~/ puzzle.cols;
                  final col = index % puzzle.cols;
                  return _buildCell(row, col, cellSize, selectedFontFamily);
                },
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildCell(int row, int col, double cellSize, String selectedFontFamily) {
    final puzzle = _currentPuzzle!;
    final letter = puzzle.grid[row][col];

    final point = Point(col, row);
    
    final isSelected = _selectedPath.contains(point);
    final selectionIndex = _selectedPath.indexOf(point);

    Color bgColor;
    Color textColor = Colors.white;
    String? orderText;
    
    final fontSize = cellSize * 0.45;
    final orderCircleSize = cellSize * 0.28;
    final orderFontSize = cellSize * 0.16;

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
      bgColor = SpaceTheme.nebulaPurple.withValues(alpha: 0.6);
    }

    final s = S.of(context)!;

    return Semantics(
      label: isSelected
          ? s.wordSnakeCellSelected(letter, selectionIndex + 1)
          : s.wordSnakeCell(letter),
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onCellTapped(row, col),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? SpaceTheme.starYellow
                  : SpaceTheme.deepSpace.withValues(alpha: 0.3),
              // Thicker border on correct/incorrect adds a shape signal
              // alongside the color change.
              width: _feedbackState != FeedbackState.none && isSelected
                  ? 4
                  : (isSelected ? 3 : 1),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: SpaceTheme.starYellow.withValues(alpha: 0.5),
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
                    fontFamily: selectedFontFamily,
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    shadows: const [
                      Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                ),
              ),
              // ✓/✗ icon overlay during correct/incorrect feedback
              // (shape redundancy for color-blind players).
              if (isSelected && _feedbackState != FeedbackState.none)
                Positioned(
                  bottom: 2,
                  left: 2,
                  child: Icon(
                    _feedbackState == FeedbackState.correct
                        ? Icons.check
                        : Icons.close,
                    color: Colors.white,
                    size: cellSize * 0.22,
                  ),
                ),
              if (orderText != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: orderCircleSize,
                    height: orderCircleSize,
                    decoration: const BoxDecoration(
                      color: SpaceTheme.starYellow,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        orderText,
                        style: TextStyle(
                          fontSize: orderFontSize,
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
      ),
    );
  }

  Widget _buildFeedbackToast(S s) {
    if (_feedbackMessage.isEmpty) { 
      return const SizedBox.shrink();
    }
    
    final isSuccess = _feedbackState == FeedbackState.correct;
    
    final color = isSuccess ? Colors.green : SpaceTheme.rocketRed;
    final icon = isSuccess ? Icons.check_circle : Icons.cancel;

    return Semantics(
      liveRegion: true,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
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
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (_educationalInfo.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Divider(color: Colors.white24),
              ),
              Text(
                _educationalInfo,
                style: SpaceTheme.bodyStyle.copyWith(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionToast() {
    if (_instructionHint.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SpaceTheme.cosmicPink, width: 2),
          boxShadow: [
            BoxShadow(
              color: SpaceTheme.cosmicPink.withValues(alpha: 0.3),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.info_outline,
              color: SpaceTheme.cosmicPink,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _instructionHint,
              style: SpaceTheme.bodyStyle.copyWith(
                color: SpaceTheme.cosmicPink,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
