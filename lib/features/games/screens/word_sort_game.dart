// lib/features/games/screens/word_sort_game.dart
import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/game_ui.dart';
import '../widgets/space_background.dart';

class WordSortGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WordSortGame({super.key, required this.gradeLevel});

  @override
  State<WordSortGame> createState() => _WordSortGameState();
}

// Enum to manage feedback state
enum FeedbackState { none, correct, incorrect }

class _WordSortGameState extends State<WordSortGame> {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;
  late S _s;

  // Game State
  bool _isLoading = true;
  Queue<GermanWord> _wordQueue = Queue<GermanWord>();
  GermanWord? _currentWord;
  int _score = 0;
  int _wordsCorrect = 0;
  int _wordsTotal = 10; // Words per round
  bool _isDragging = false;
  bool _showConfetti = false;

  // Feedback State
  FeedbackState _feedbackState = FeedbackState.none;
  Timer? _feedbackTimer;

  // Map of WordTypes we care about to their UI data
  late Map<GermanWordType, ({String label, IconData icon, Color color})>
      _targetCategories;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize localized data here, as context is available
    _s = S.of(context)!;
    
    // --- FIX: Removed Adverb ---
    _targetCategories = {
      GermanWordType.substantiv: (
        label: _s.wordSortCategoryNoun,
        icon: Icons.home,
        color: SpaceTheme.planetOrange
      ),
      GermanWordType.verb: (
        label: _s.wordSortCategoryVerb,
        icon: Icons.directions_run,
        color: SpaceTheme.alienGreen
      ),
      GermanWordType.adjektiv: (
        label: _s.wordSortCategoryAdjective,
        icon: Icons.palette,
        color: SpaceTheme.cosmicPink
      ),
      // GermanWordType.adverb was here
    };
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    setState(() => _isLoading = true);

    // Get services
    _vocabularyService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();

    if (!_vocabularyService.isInitialized) {
      await _vocabularyService.initialize();
    }

    _loadLevel();
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
    // Check if it's one of the 3 target categories, not "andere", and not a phrase
    return _targetCategories.containsKey(word.wordType) &&
        !word.word.contains(" ") &&
        word.wordType != GermanWordType.andere;
  }

  void _loadLevel() {
    _score = 0;
    _wordsCorrect = 0;

    // --- NEW ADAPTIVE WORD SELECTION ---
    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};

    int reviewWordCount = (_wordsTotal * 0.5).ceil(); // 50% review
    int newWordCount = _wordsTotal - reviewWordCount;

    // 1. Get REVIEW words (words the user struggles with)
    // We prioritize words they get wrong in *this* game (WordType)
    final reviewItemIds = _sriService.getItemsForReview(
      limit: reviewWordCount * 2, // Get extra in case of filtering
      skillTypeFilter: LanguageSkillType.wordType,
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
          if (wordsForGame.length >= reviewWordCount) break;
        }
      } catch (e) {
        // Word from SRI not in vocab, skip
      }
    }

    // 2. Get NEW words (words the user has not seen)
    newWordCount = _wordsTotal - wordsForGame.length; // Recalculate how many we need
    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: newWordCount * 2, // Get extra
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
        if (wordsForGame.length >= _wordsTotal) break;
      }
    }

    // 3. Fill the rest with RANDOM words (if needed)
    if (wordsForGame.length < _wordsTotal) {
      int randomWordsNeeded = _wordsTotal - wordsForGame.length;
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel);
      allWords.shuffle();

      for (final word in allWords) {
        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          wordsForGame.add(word);
          addedWordIds.add(word.id);
          if (wordsForGame.length >= _wordsTotal) break;
        }
      }
    }
    // --- END ADAPTIVE SELECTION ---

    _wordQueue = Queue.from(wordsForGame);

    if (_wordQueue.isEmpty) {
      // Handle error case where no words are found
      debugPrint("No words found for WordSortGame at this grade level.");
      setState(() => _isLoading = false);
      Navigator.of(context).pop();
      return;
    }

    _loadNextWord();
    setState(() => _isLoading = false);
  }

  void _loadNextWord() {
    if (_wordQueue.isEmpty) {
      _showGameOver();
      return;
    }
    setState(() {
      _currentWord = _wordQueue.removeFirst();
      _feedbackState = FeedbackState.none;
    });
  }

  void _handleDrop(GermanWordType droppedType, GermanWordType targetCategory) {
    if (_currentWord == null) return;
    final bool isCorrect = (droppedType == targetCategory);

    // Record the attempt in the SRI service
    _sriService.recordResponse(
      skillType: LanguageSkillType.wordType,
      baseWord: _currentWord!.word,
      wasCorrect: isCorrect,
      metadata: {
        'gradeLevel': _currentWord!.gradeLevel,
        'wordType': _currentWord!.wordType.toString(),
      },
    );

    if (isCorrect) {
      _audioService.playSound('correct.mp3');
      _gameProvider.addScore(10);
      setState(() {
        _score += 10;
        _wordsCorrect++;
        _feedbackState = FeedbackState.correct;
        _showConfetti = true;
      });

      // Show "Correct!" feedback, then move to next word
      _feedbackTimer = Timer(const Duration(milliseconds: 1000), () {
        setState(() {
          _loadNextWord();
          _showConfetti = false;
        });
      });
    } else {
      _audioService.playSound('incorrect.mp3');
      setState(() {
        _feedbackState = FeedbackState.incorrect;
      });
      // Show "Incorrect!" feedback, then reset
      _feedbackTimer = Timer(const Duration(milliseconds: 1000), () {
        setState(() {
          _feedbackState = FeedbackState.none;
        });
      });
    }
  }

  void _showGameOver() {
    _gameProvider.recordLevelWin(
      gameType: 'word_sort_game',
      scoreGained: _score,
      difficulty: widget.gradeLevel.index + 1,
      wasSuccessful: _wordsCorrect >= (_wordsTotal * 0.7),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        title: Text(_s.gameOver, style: SpaceTheme.headlineStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_s.score}: $_score',
              style: SpaceTheme.titleStyle
                  .copyWith(color: SpaceTheme.starYellow),
            ),
            const SizedBox(height: 16),
            Text(
              '$_wordsCorrect / $_wordsTotal ${_s.correct}',
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
            child: Text(_s.backToMenu),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _loadLevel();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.planetOrange,
            ),
            child: Text(_s.playAgain),
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
                title: _s.wordSortTitle,
                level: widget.gradeLevel.index + 1,
                onBack: () => Navigator.of(context).pop(),
              ),
              if (_isLoading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else
                _buildGameContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameContent() {
    return Expanded(
      child: Stack(
        children: [
          Row(
            children: [
              // 1. Draggable Word Area
              Expanded(
                flex: 2, // 2/5ths of the space
                child: Center(
                  child: _currentWord == null
                      ? const SizedBox.shrink()
                      : _buildDraggableWord(),
                ),
              ),
              // 2. Drop Target Area
              Expanded(
                flex: 3, // 3/5ths of the space
                child: _buildDropTargets(),
              ),
            ],
          ),
          // 3. Confetti Overlay (for success)
          if (_showConfetti)
            const Center(
              child: IgnorePointer(
                child: Text(
                  '🎉',
                  style: TextStyle(fontSize: 200),
                ), // Simple placeholder
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDraggableWord() {
    // Animate opacity to hide the word while it's being dragged
    return Opacity(
      opacity: _isDragging || _showConfetti ? 0.0 : 1.0,
      child: Draggable<GermanWordType>(
        data: _currentWord!.wordType,
        onDragStarted: () => setState(() => _isDragging = true),
        onDragEnd: (details) => setState(() => _isDragging = false),
        // This is what the user sees while dragging
        feedback: _buildWordCard(_currentWord!.word, isFeedback: true),
        // This is the widget left behind (which we hide)
        childWhenDragging:
            _buildWordCard(_currentWord!.word, isPlaceholder: true),
        // This is the widget at the start position
        child: _buildWordCard(_currentWord!.word),
      ),
    );
  }

  Widget _buildWordCard(String word,
      {bool isFeedback = false, bool isPlaceholder = false}) {
    Color borderColor = SpaceTheme.planetOrange;
    if (_feedbackState == FeedbackState.correct) {
      borderColor = Colors.green;
    } else if (_feedbackState == FeedbackState.incorrect) {
      borderColor = Colors.red;
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 250,
        height: 100,
        decoration: BoxDecoration(
          color: isPlaceholder
              ? Colors.transparent
              : SpaceTheme.deepSpace.withOpacity(isFeedback ? 0.9 : 1.0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 3),
          boxShadow: isFeedback
              ? [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ]
              : null,
        ),
        child: Center(
          child: Text(
            word,
            style: SpaceTheme.headlineStyle.copyWith(fontSize: 32),
          ),
        ),
      ),
    );
  }

  // --- FIX: Changed this from a GridView to a Column ---
  Widget _buildDropTargets() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: _targetCategories.entries.map((entry) {
        return Padding(
          // Add padding for spacing
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: _buildDragTarget(
            targetType: entry.key,
            label: entry.value.label,
            icon: entry.value.icon,
            color: entry.value.color,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDragTarget({
    required GermanWordType targetType,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return DragTarget<GermanWordType>(
      builder: (context, candidateData, rejectedData) {
        final bool isHighlighted = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 100, // Give the targets a fixed height
          width: 300, // Give the targets a fixed width
          decoration: BoxDecoration(
            color: isHighlighted
                ? color.withOpacity(0.4)
                : SpaceTheme.deepSpace.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isHighlighted ? color : color.withOpacity(0.5),
              width: 3,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 15,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Row( // Use a Row for icon + label
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(width: 16),
              Text(
                label,
                style: SpaceTheme.titleStyle.copyWith(color: color, fontSize: 22),
              ),
            ],
          ),
        );
      },
      onWillAccept: (data) => true,
      onAccept: (droppedType) {
        _handleDrop(droppedType, targetType);
      },
    );
  }
}