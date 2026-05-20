// lib/features/games/screens/word_find_game.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
// import 'dart:collection';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';

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
import '../models/game_outcome.dart';

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

    // --- NEW ADAPTIVE WORD SELECTION ---
    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};

    int reviewWordCount = (wordCount * 0.5).ceil(); // 50% review
    int newWordCount = wordCount - reviewWordCount;

    // 1. Get REVIEW words (words the user struggles with)
    // We get *all* review items, sorted by worst performance
    final reviewItemIds = _sriService.getItemsForReview(
      limit: reviewWordCount * 2, // Get extra in case of filtering
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
          if (wordsForGame.length >= reviewWordCount) break;
        }
      } catch (e) {
        // Word from SRI not in vocab, skip
      }
    }

    // 2. Get NEW words (words the user has not seen)
    newWordCount = wordCount - wordsForGame.length; // Recalculate how many we need
    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: newWordCount * 2, // Get extra
      settingsProvider: _gameProvider,
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
        if (wordsForGame.length >= wordCount) break;
      }
    }

    // 3. Fill the rest with RANDOM words (if needed)
    if (wordsForGame.length < wordCount) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
      allWords.shuffle();

      for (final word in allWords) {
        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          wordsForGame.add(word);
          addedWordIds.add(word.id);
          if (wordsForGame.length >= wordCount) break;
        }
      }
    }
    // --- END ADAPTIVE SELECTION ---

    _wordsToFind = wordsForGame;

    // Generate the grid
    final wordStrings =
        _wordsToFind.map((w) => w.word.replaceAll(' ', '')).toList();
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

  /// Extracts the base word (e.g., "haus") from an SRI ID (e.g., "SPELL_haus").
  String? _extractBaseWordFromSriId(String id) {
    if (id.startsWith('SPELL_')) {
      return id.substring('SPELL_'.length);
    }
    if (id.startsWith('WORDTYPE_')) {
      return id.substring('WORDTYPE_'.length);
    }
    // Add other prefixes if you track more word skills
    return null;
  }

  /// Checks if a word is valid for this specific game.
  bool _isWordValidForGame(GermanWord word) {
    return !word.word.contains(" ") &&
        word.word.length <= _gridSize &&
        word.word.length >= 3;
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
        _audioService.playSound('success');
        HapticFeedback.lightImpact();
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
    _audioService.playSound('failure');
    HapticFeedback.heavyImpact();
  }

  /// Generates compact educational info for a found word
  String _getEducationalInfo(GermanWord word) {
    final List<String> infoParts = [];
    
    switch (word.wordType) {
      case GermanWordType.substantiv:
        // Always show article if available
        if (word.article != null && word.article!.isNotEmpty) {
          infoParts.add(word.article!);
        }
        
        // Always show plural if available
        if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
          infoParts.add('Plural: ${word.plural}');
        } /* else if (word.nurImPlural) {
          infoParts.add('nur Plural');
        } */
        
        // Show genus as fallback or additional info
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
        
        // If no conjugation, show verb form info
        if (infoParts.isEmpty && word.verbFormSpacy != null) {
          final verbFormMap = {
            'Inf': 'Infinitiv',
            'Fin': 'finit',
            'Part': 'Partizip',
          };
          infoParts.add(verbFormMap[word.verbFormSpacy] ?? word.verbFormSpacy!);
        }
        
        // If still nothing, at least show it's a verb
        if (infoParts.isEmpty) {
          infoParts.add('Verb');
        }
        break;
        
      case GermanWordType.adjektiv:
        // Try to show comparative and superlative
        bool hasSteigerung = false;
        
        if (word.inflectionData != null) {
          final comparative = word.inflectionData!['comparative'];
          final superlative = word.inflectionData!['superlative'];
          
          if (comparative != null && comparative.toString().isNotEmpty && comparative != '-') {
            infoParts.add(comparative.toString());
            hasSteigerung = true;
          }
          if (superlative != null && superlative.toString().isNotEmpty && superlative != '-') {
            infoParts.add(superlative.toString());
            hasSteigerung = true;
          }
        }
        
        // Show degree info if available
        if (word.degreeSpacy != null && word.degreeSpacy!.isNotEmpty) {
          final degreeMap = {
            'Pos': 'Positiv',
            'Cmp': 'Komparativ',
            'Sup': 'Superlativ',
          };
          final degreeLabel = degreeMap[word.degreeSpacy] ?? word.degreeSpacy!;
          if (!hasSteigerung) {
            infoParts.add(degreeLabel);
          }
        }
        
        // Fallback
        if (infoParts.isEmpty) {
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
        
        // Show pronoun type
        if (word.pronTypeSpacy != null && word.pronTypeSpacy!.isNotEmpty) {
          infoParts.add(word.pronTypeSpacy!);
        }
        
        if (infoParts.isEmpty) {
          infoParts.add('Pronomen');
        }
        break;
        
      case GermanWordType.artikel:
        // Show case and gender info
        if (word.caseSpacy != null && word.caseSpacy!.isNotEmpty) {
          infoParts.add(word.caseSpacy!);
        }
        if (word.genus != null && word.genus!.isNotEmpty) {
          infoParts.add(word.genus!.toLowerCase());
        }
        if (infoParts.isEmpty) {
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
        // For other types, show the type name
        final typeMap = {
          GermanWordType.partikel: 'Partikel',
          GermanWordType.numerale: 'Numerale',
        };
        final typeLabel = typeMap[word.wordType];
        if (typeLabel != null) {
          infoParts.add(typeLabel);
        }
    }
    
    // Return empty string if no info available
    if (infoParts.isEmpty) return '';
    
    // Join with bullets for compact display
    return ' • ${infoParts.join(' • ')}';
  }

  /// Gets a random verb conjugation from inflectionData
  String? _getRandomVerbConjugation(Map<String, dynamic> inflectionData) {
    final random = Random();
    
    // Define tense-person combinations to try
    final options = [
      ('Präsens', ['ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr']),
      ('Präteritum', ['ich', 'du', 'er', 'sie', 'es']),
      ('Perfekt', ['ich', 'du', 'er']),
    ];
    
    // Shuffle and try to find a valid conjugation
    options.shuffle(random);
    
    for (final (tense, persons) in options) {
      // Try different field names for the tense
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
            // Shuffle persons
            final shuffledPersons = List<String>.from(persons)..shuffle(random);
            
            for (final person in shuffledPersons) {
              // Try different formats
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

  void _showGameOver() {
    final s = S.of(context)!;
    _gameProvider.reportOutcome(GameOutcome.win(
      gameType: 'word_find_game',
      difficulty: widget.gradeLevel.index + 1,
      score: _score,
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
    final s = S.of(context)!;

    final String selectedFontFamily = context.watch<GameProvider>().selectedFontFamily;

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              GameUI(
                title: s.wordFindTitle,
                level: widget.gradeLevel.index + 1,
                onBack: () => Navigator.of(context).pop(),
              ),
              if (_isLoading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const double breakpoint = 600.0;

                      // Calculate grid size to fit in available space
                      Widget gridWidget;
                      if (constraints.maxWidth < breakpoint) {
                        // Portrait/narrow: grid should fit width and leave space for word list
                        final availableHeight = constraints.maxHeight * 0.5; // 50% for grid
                        final availableWidth = constraints.maxWidth - 32; // padding
                        final gridSize = min(availableHeight, availableWidth);
                        
                        gridWidget = Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: SizedBox(
                              width: gridSize,
                              height: gridSize,
                              child: _buildGridWidget(selectedFontFamily),
                            ),
                          ),
                        );
                      } else {
                        // Landscape/wide: grid should fit in 60% of width
                        final availableHeight = constraints.maxHeight - 32;
                        final availableWidth = (constraints.maxWidth * 0.6) - 32;
                        final gridSize = min(availableHeight, availableWidth);
                        
                        gridWidget = Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: SizedBox(
                              width: gridSize,
                              height: gridSize,
                              child: _buildGridWidget(selectedFontFamily),
                            ),
                          ),
                        );
                      }

                      final wordListWidget = _buildWordsToFindList(selectedFontFamily);

                      if (constraints.maxWidth < breakpoint) {
                        // Small screen: Column layout
                        return Column(
                          children: [
                            gridWidget,
                            Expanded(child: wordListWidget),
                          ],
                        );
                      } else {
                        // Wide screen: Row layout
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: gridWidget),
                            Expanded(flex: 2, child: wordListWidget),
                          ],
                        );
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Extract grid building into separate method
  Widget _buildGridWidget(String selectedFontFamily) {
    return Semantics(
      label: 'Wortgitter',
      hint: 'Ziehe über Buchstaben, um Wörter zu markieren',
      child: GestureDetector(
        key: _gridKey,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Container(
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _gridSize,
          ),
          itemCount: _gridSize * _gridSize,
          itemBuilder: (context, index) {
            final row = index ~/ _gridSize;
            final col = index % _gridSize;
            return _buildCell(row, col, selectedFontFamily);
          },
        ),
        ),
      ),
    );
  }

  Widget _buildCell(int row, int col, String selectedFontFamily) {
    final pos = GridPosition(row, col);
    final isSelected = _selectedCells.contains(pos);
    final isFound = _foundCells.contains(pos);

    Color bgColor;
    Color textColor = Colors.white;

    if (isFound) {
      bgColor = SpaceTheme.alienGreen.withValues(alpha: 0.7);
      textColor = SpaceTheme.deepSpace;
    } else if (isSelected) {
      bgColor = SpaceTheme.planetOrange.withValues(alpha: 0.8);
    } else {
      bgColor = SpaceTheme.nebulaPurple.withValues(alpha: 0.5);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: bgColor,
        // Thicker border on found cells adds a shape signal alongside
        // the alienGreen color.
        border: Border.all(
          color: isFound
              ? SpaceTheme.deepSpace
              : SpaceTheme.deepSpace.withValues(alpha: 0.3),
          width: isFound ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Center(
            // Wrap the Text to scale it down if it doesn't fit
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _grid[row][col],
                style: TextStyle(
                  fontFamily: selectedFontFamily,
                  fontSize: 18, // This is a *maximum* size
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  shadows: const [
                    Shadow(blurRadius: 4, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordsToFindList(String selectedFontFamily) {
    final s = S.of(context)!;
    
    // Only show words that were actually placed in the grid
    final wordsInGrid = _wordsToFind.where((word) {
      final wordUpper = word.word.toUpperCase().replaceAll(' ', '');
      return _placedWords.any((placed) => placed.word == wordUpper);
    }).toList();
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16, right: 16, bottom: 16),
      decoration: SpaceTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.wordFindWordsToFind,
            style: SpaceTheme.titleStyle.copyWith(color: SpaceTheme.starYellow),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: wordsInGrid.length,
              itemBuilder: (context, index) {
                final word = wordsInGrid[index];
                final wordUpper = word.word.toUpperCase().replaceAll(' ', '');
                final isFound = _foundWords.contains(wordUpper);
                
                // Get educational info when word is found
                final eduInfo = isFound ? _getEducationalInfo(word) : '';
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Semantics(
                    label: isFound
                        ? '${word.word}, gefunden'
                        : '${word.word}, noch zu finden',
                    child: RichText(
                    text: TextSpan(
                      children: [
                        // The main word
                        TextSpan(
                          text: word.word,
                          style: SpaceTheme.bodyStyle.copyWith(
                            fontFamily: selectedFontFamily,
                            fontSize: 16,
                            color: isFound ? SpaceTheme.alienGreen : Colors.white70,
                            decoration: isFound
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            decorationColor: SpaceTheme.rocketRed,
                            decorationThickness: 2.0,
                          ),
                        ),
                        // Educational info (only when found)
                        if (eduInfo.isNotEmpty)
                          TextSpan(
                            text: eduInfo,
                            style: SpaceTheme.bodyStyle.copyWith(
                              fontFamily: selectedFontFamily,
                              fontSize: 13,
                              color: SpaceTheme.starYellow.withValues(alpha: 0.9),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
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