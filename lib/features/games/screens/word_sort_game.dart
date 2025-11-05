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

enum FeedbackState { none, correct, incorrect }

class _WordSortGameState extends State<WordSortGame> with TickerProviderStateMixin {
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;
  late S _s;

  bool _isLoading = true;
  Queue<GermanWord> _wordQueue = Queue<GermanWord>();
  GermanWord? _currentWord;
  int _score = 0;
  int _wordsCorrect = 0;
  int _wordsTotal = 10;
  bool _isDragging = false;

  FeedbackState _feedbackState = FeedbackState.none;
  Timer? _feedbackTimer;
  
  // Non-blocking hint system
  String? _currentHint;
  late AnimationController _hintController;
  late Animation<double> _hintAnimation;
  
  // Hint rotation tracking
  final Map<String, int> _hintUsageCount = {};
  final List<String> _recentHints = [];
  
  // Confetti
  late AnimationController _confettiController;
  bool _showConfetti = false;

  late Map<GermanWordType, ({String label, IconData icon, Color color})> _targetCategories;

  @override
  void initState() {
    super.initState();
    
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _hintAnimation = CurvedAnimation(
      parent: _hintController,
      curve: Curves.easeInOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _s = S.of(context)!;
    
    // Basic categories for all grades
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
    };
    
    // Add advanced categories for grades > 3
    if (widget.gradeLevel.index >= 2) { // Grade 3+
      _targetCategories[GermanWordType.adverb] = (
        label: 'Adverb',
        icon: Icons.speed,
        color: Colors.purple
      );
    }
    
    if (widget.gradeLevel.index >= 3) { // Grade 4+
      _targetCategories[GermanWordType.pronomen] = (
        label: 'Pronomen',
        icon: Icons.person,
        color: Colors.teal
      );
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _confettiController.dispose();
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
    return _targetCategories.containsKey(word.wordType) &&
        !word.word.contains(" ") &&
        word.wordType != GermanWordType.andere;
  }

  void _loadLevel() {
    _score = 0;
    _wordsCorrect = 0;

    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};

    int reviewWordCount = (_wordsTotal * 0.5).ceil();
    final reviewItemIds = _sriService.getItemsForReview(
      limit: reviewWordCount * 2,
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
      } catch (e) {}
    }

    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: (_wordsTotal - wordsForGame.length) * 2,
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
        if (wordsForGame.length >= _wordsTotal) break;
      }
    }

    if (wordsForGame.length < _wordsTotal) {
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

    _wordQueue = Queue.from(wordsForGame);

    if (_wordQueue.isEmpty) {
      debugPrint("No words found for WordSortGame");
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
      _handleCorrectAnswer();
    } else {
      _handleIncorrectAnswer(targetCategory);
    }
  }

  void _handleCorrectAnswer() {
    _audioService.playSound('correct.mp3');
    _gameProvider.addScore(10);
    
    setState(() {
      _score += 10;
      _wordsCorrect++;
      _feedbackState = FeedbackState.correct;
      _showConfetti = true;
    });

    // Show smart, non-blocking hint
    _showSmartHint(_currentWord!, isCorrect: true);

    // Confetti animation (non-blocking)
    _confettiController.forward(from: 0.0);

    // Auto-advance after 1.5 seconds
    _feedbackTimer = Timer(const Duration(milliseconds: 1500), () {
      setState(() {
        _loadNextWord();
        _showConfetti = false;
      });
    });
  }

  void _handleIncorrectAnswer(GermanWordType guessedCategory) {
    _audioService.playSound('incorrect.mp3');
    
    setState(() {
      _feedbackState = FeedbackState.incorrect;
    });

    // Show educational hint
    _showSmartHint(_currentWord!, isCorrect: false, guessedType: guessedCategory);

    // Show error state for 2 seconds, then reset
    _feedbackTimer = Timer(const Duration(milliseconds: 2000), () {
      setState(() {
        _feedbackState = FeedbackState.none;
      });
    });
  }

  void _showSmartHint(GermanWord word, {required bool isCorrect, GermanWordType? guessedType}) {
    String hint = _generateSmartHint(word, isCorrect: isCorrect, guessedType: guessedType);
    
    // Track hint usage
    _hintUsageCount[hint] = (_hintUsageCount[hint] ?? 0) + 1;
    _recentHints.add(hint);
    if (_recentHints.length > 10) _recentHints.removeAt(0);
    
    setState(() {
      _currentHint = hint;
    });
    
    // Fade in
    _hintController.forward();
    
    // Fade out after delay
    Future.delayed(Duration(milliseconds: isCorrect ? 1200 : 1800), () {
      _hintController.reverse();
    });
  }

  String _generateSmartHint(GermanWord word, {required bool isCorrect, GermanWordType? guessedType}) {
    final inflection = word.inflectionData;
    
    // Check if we've shown generic hints too many times
    final genericHintCount = _hintUsageCount.values.where((count) => count >= 3).length;
    final shouldUseAdvancedHints = genericHintCount >= 2;
    
    if (isCorrect) {
      return _generateCorrectHint(word, inflection, shouldUseAdvancedHints);
    } else {
      return _generateIncorrectHint(word, inflection, guessedType, shouldUseAdvancedHints);
    }
  }

  String _generateCorrectHint(GermanWord word, Map<String, dynamic>? inflection, bool advanced) {
    // For correct answers after seeing hints 3+ times, just show icon
    if (advanced && _hintUsageCount.values.any((c) => c >= 3)) {
      if (word.exampleSentences.isNotEmpty) {
        return '✓ Beispiel: ${word.exampleSentences.first}';
      }
      return '✓';
    }
    
    switch (word.wordType) {
      case GermanWordType.substantiv:
        return _getNounHint(word, inflection, advanced);
      case GermanWordType.verb:
        return _getVerbHint(word, inflection, advanced);
      case GermanWordType.adjektiv:
        return _getAdjectiveHint(word, inflection, advanced);
      case GermanWordType.adverb:
        return advanced 
            ? 'Adverbien sind unveränderlich: ${word.word}'
            : 'Adverb: ${word.word} → beschreibt WIE etwas gemacht wird';
      case GermanWordType.pronomen:
        return advanced
            ? 'Pronomen ersetzen Nomen: ${word.word}'
            : 'Pronomen: ${word.word} → steht für ein Nomen';
      default:
        return '✓';
    }
  }

  String _getNounHint(GermanWord word, Map<String, dynamic>? inflection, bool advanced) {
    if (advanced && inflection != null) {
      final nounData = inflection['analyses']?['noun'];
      if (nounData != null) {
        final declension = nounData['declension'];
        if (declension != null) {
          // Grammar probe: Maskulinprobe
          final nom = declension['Nominativ Singular']?['definite'];
          final dat = declension['Dativ Singular']?['definite'];
          if (nom != null && dat != null) {
            return 'Maskulinprobe: $nom → $dat (Dativ)';
          }
        }
        
        // Show plural formation
        final plural = nounData['plural'];
        if (plural != null && plural != word.word) {
          return 'Mehrzahlbildung: ${word.word} → $plural';
        }
      }
    }
    
    // Rotate through basic hints
    final hints = [
      'Nomen: ${word.article ?? 'das'} ${word.word} → Artikel zeigt es!',
      'Sandwichprobe: ${word.article ?? 'der'} große ${word.word} ✓',
      'Lexikalische Artikelprobe: ${word.article ?? 'das'} ${word.word}',
    ];
    
    return _selectHintFromList(hints);
  }

  String _getVerbHint(GermanWord word, Map<String, dynamic>? inflection, bool advanced) {
    if (advanced && inflection != null) {
      final verbData = inflection['analyses']?['verb'];
      if (verbData != null) {
        final conjugation = verbData['conjugation']?['Präsens'];
        if (conjugation != null) {
          final ich = conjugation['ich'];
          final du = conjugation['du'];
          if (ich != null && du != null) {
            // Grammar probe: Personalformenprobe
            return 'Personalformenprobe: $ich, $du';
          }
        }
        
        // Grammar probe: Zeitformenprobe
        final participles = verbData['participles'];
        if (participles != null && participles['Partizip II'] != null) {
          return 'Zeitformenprobe: ${word.word} → ${participles['Partizip II']}';
        }
      }
    }
    
    final hints = [
      'Verb: ich ${word.word.endsWith('en') ? word.word.substring(0, word.word.length - 2) + 'e' : word.word}',
      'Verben beschreiben Aktionen: ${word.word}',
      'Frageprobe: "Was macht man?" → ${word.word}',
    ];
    
    return _selectHintFromList(hints);
  }

  String _getAdjectiveHint(GermanWord word, Map<String, dynamic>? inflection, bool advanced) {
    if (advanced && inflection != null) {
      final adjData = inflection['analyses']?['adjective'];
      if (adjData != null) {
        final comp = adjData['comparative'];
        final superl = adjData['superlative'];
        if (comp != null && superl != null) {
          // Grammar probe: Steigerungsprobe
          return 'Steigerungsprobe: ${word.word} → $comp → $superl';
        }
      }
    }
    
    final hints = [
      'Adjektiv: ${word.word} beschreibt eine Eigenschaft',
      'Sandwichprobe: der ${word.word}e Baum ✓',
      'Adjektive sind steigerbar: ${word.word}',
    ];
    
    return _selectHintFromList(hints);
  }

  String _generateIncorrectHint(GermanWord word, Map<String, dynamic>? inflection, 
      GermanWordType? guessedType, bool advanced) {
    
    String wrongPart = guessedType != null 
        ? '✗ Kein ${_getCategoryNameGerman(guessedType)}\n'
        : '✗ Falsch\n';
    
    String correctPart = '';
    
    switch (word.wordType) {
      case GermanWordType.substantiv:
        if (word.article != null) {
          correctPart = '✓ ${word.article} ${word.word} → Nomen (Artikel!)';
        }
        break;
      case GermanWordType.verb:
        if (inflection != null) {
          final verbData = inflection['analyses']?['verb'];
          if (verbData != null) {
            final conj = verbData['conjugation']?['Präsens'];
            if (conj != null && conj['ich'] != null) {
              correctPart = '✓ ${conj['ich']} → Verb (konjugiert!)';
            }
          }
        }
        if (correctPart.isEmpty) {
          correctPart = '✓ ${word.word} → Verb (Aktion!)';
        }
        break;
      case GermanWordType.adjektiv:
        correctPart = '✓ ${word.word} → Adjektiv (Eigenschaft!)';
        break;
      default:
        correctPart = '✓ ${_getCategoryNameGerman(word.wordType)}';
    }
    
    return wrongPart + correctPart;
  }

  String _selectHintFromList(List<String> hints) {
    // Find least-used hint
    hints.sort((a, b) => (_hintUsageCount[a] ?? 0).compareTo(_hintUsageCount[b] ?? 0));
    return hints.first;
  }

  String _getCategoryNameGerman(GermanWordType type) {
    switch (type) {
      case GermanWordType.substantiv: return 'Nomen';
      case GermanWordType.verb: return 'Verb';
      case GermanWordType.adjektiv: return 'Adjektiv';
      case GermanWordType.adverb: return 'Adverb';
      case GermanWordType.pronomen: return 'Pronomen';
      default: return type.toString();
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
            Text('${_s.score}: $_score',
              style: SpaceTheme.titleStyle.copyWith(color: SpaceTheme.starYellow)),
            const SizedBox(height: 16),
            Text('$_wordsCorrect / $_wordsTotal ${_s.correct}',
              style: SpaceTheme.bodyStyle),
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
            style: ElevatedButton.styleFrom(backgroundColor: SpaceTheme.planetOrange),
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
    return Expanded(
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Center(
                  child: _currentWord == null ? const SizedBox.shrink() : _buildDraggableWord(),
                ),
              ),
              Expanded(
                flex: 3,
                child: _buildDropTargets(),
              ),
            ],
          ),
          // Non-blocking confetti
          if (_showConfetti)
            IgnorePointer(child: _buildCategoryConfetti()),
          // Non-blocking hint overlay (top-right corner)
          if (_currentHint != null)
            _buildFloatingHint(),
        ],
      ),
    );
  }

  Widget _buildFloatingHint() {
    return Positioned(
      top: 16,
      right: 16,
      left: 16,
      child: FadeTransition(
        opacity: _hintAnimation,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _feedbackState == FeedbackState.correct
                ? Colors.green.withOpacity(0.9)
                : Colors.orange.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            _currentHint!,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableWord() {
    final showArticle = _feedbackState != FeedbackState.none &&
        _currentWord!.wordType == GermanWordType.substantiv &&
        _currentWord!.article != null;

    return Opacity(
      opacity: _isDragging ? 0.0 : 1.0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showArticle)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                _currentWord!.article!,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _getGenderColor(_currentWord!),
                ),
              ),
            ),
          Draggable<GermanWordType>(
            data: _currentWord!.wordType,
            onDragStarted: () => setState(() => _isDragging = true),
            onDragEnd: (details) => setState(() => _isDragging = false),
            feedback: _buildWordCard(_currentWord!.word, isFeedback: true),
            childWhenDragging: _buildWordCard(_currentWord!.word, isPlaceholder: true),
            child: _buildWordCard(_currentWord!.word),
          ),
        ],
      ),
    );
  }

  Color _getGenderColor(GermanWord word) {
    final gender = word.inflectionData?['analyses']?['noun']?['gender'];
    if (gender == 'Masculine') return Colors.blue;
    if (gender == 'Feminine') return Colors.pink;
    if (gender == 'Neuter') return Colors.green;
    return Colors.grey;
  }

  Widget _buildWordCard(String word, {bool isFeedback = false, bool isPlaceholder = false}) {
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
        constraints: const BoxConstraints(minHeight: 100, maxHeight: 140),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isPlaceholder
              ? Colors.transparent
              : SpaceTheme.deepSpace.withOpacity(isFeedback ? 0.9 : 1.0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 3),
          boxShadow: isFeedback
              ? [BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)]
              : null,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              word,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 32),
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropTargets() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: _targetCategories.entries.map((entry) {
        return Padding(
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
          height: 100,
          width: 300,
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
                ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 15, spreadRadius: 2)]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(width: 16),
              Text(label, style: SpaceTheme.titleStyle.copyWith(color: color, fontSize: 22)),
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

  Widget _buildCategoryConfetti() {
    final emoji = _getCategoryEmoji(_currentWord?.wordType);
    
    return AnimatedBuilder(
      animation: _confettiController,
      builder: (context, child) {
        return Stack(
          children: List.generate(15, (index) {
            final random = (index * 137) % 100 / 100.0;
            final startX = random * MediaQuery.of(context).size.width;
            final progress = _confettiController.value;

            return Positioned(
              left: startX,
              top: progress * MediaQuery.of(context).size.height - 50,
              child: Opacity(
                opacity: 1.0 - progress,
                child: Transform.rotate(
                  angle: progress * 8 * 3.14159,
                  child: Text(emoji, style: const TextStyle(fontSize: 32)),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  String _getCategoryEmoji(GermanWordType? type) {
    if (type == null) return '⭐';
    final typeStr = type.toString();
    if (typeStr.contains('substantiv')) return '🏠';
    if (typeStr.contains('verb')) return '🏃';
    if (typeStr.contains('adjektiv')) return '🎨';
    if (typeStr.contains('adverb')) return '⚡';
    if (typeStr.contains('pronomen')) return '👤';
    return '⭐';
  }
}