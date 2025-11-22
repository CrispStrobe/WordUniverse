// lib/features/games/screens/word_sort_game.dart
import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart'; 

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
        word.wordType != GermanWordType.andere &&
        word.apiEnrichment?.enrichmentStatus == 'success';
  }

  void _loadLevel() {
    _score = 0;
    _wordsCorrect = 0;
    _hintUsageCount.clear();
    _recentHints.clear();

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
        final word = _vocabularyService.getAllWords(_gameProvider).firstWhere(
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
      settingsProvider: _gameProvider,
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
        if (wordsForGame.length >= _wordsTotal) break;
      }
    }

    if (wordsForGame.length < _wordsTotal) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
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
      if (mounted) Navigator.of(context).pop();
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
      _currentHint = null;
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

    _showSmartHint(_currentWord!, isCorrect: true);
    _confettiController.forward(from: 0.0);

    _feedbackTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _loadNextWord();
          _showConfetti = false;
        });
      }
    });
  }

  void _handleIncorrectAnswer(GermanWordType guessedCategory) {
    _audioService.playSound('incorrect.mp3');
    
    setState(() {
      _feedbackState = FeedbackState.incorrect;
    });

    _showSmartHint(_currentWord!, isCorrect: false, guessedType: guessedCategory);

    _feedbackTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _feedbackState = FeedbackState.none;
        });
      }
    });
  }

  void _showSmartHint(GermanWord word, {required bool isCorrect, GermanWordType? guessedType}) {
    final apiData = word.apiEnrichment; 
    String hint = _generateSmartHint(word, apiData, isCorrect: isCorrect, guessedType: guessedType);
    
    _hintUsageCount[hint] = (_hintUsageCount[hint] ?? 0) + 1;
    _recentHints.add(hint);
    if (_recentHints.length > 10) _recentHints.removeAt(0);
    
    setState(() {
      _currentHint = hint;
    });
    
    _hintController.forward();
    
    Future.delayed(Duration(milliseconds: isCorrect ? 1200 : 1800), () {
      if (mounted) {
        _hintController.reverse();
      }
    });
  }

  String _generateSmartHint(GermanWord word, ApiEnrichment? apiData, {required bool isCorrect, GermanWordType? guessedType}) {
    final patternData = apiData?.inflectionsPattern; 
    final genericHintCount = _hintUsageCount.values.where((count) => count >= 2).length;
    final shouldUseAdvancedHints = genericHintCount >= 1 || _wordsCorrect >= 3;
    
    if (isCorrect) {
      return _generateCorrectHint(word, apiData, patternData, shouldUseAdvancedHints);
    } else {
      return _generateIncorrectHint(word, apiData, patternData, guessedType, shouldUseAdvancedHints);
    }
  }

  String _generateCorrectHint(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, bool advanced) {
    switch (word.wordType) {
      case GermanWordType.substantiv:
        return _getNounHint(word, apiData, patternData, advanced, isCorrect: true);
      case GermanWordType.verb:
        return _getVerbHint(word, apiData, patternData, advanced, isCorrect: true);
      case GermanWordType.adjektiv:
        return _getAdjectiveHint(word, apiData, patternData, advanced, isCorrect: true);
      case GermanWordType.adverb:
        return _getAdverbHint(word, apiData, advanced);
      case GermanWordType.pronomen:
        return _getPronomenHint(word, apiData, advanced);
      default:
        return '✓ Richtig!';
    }
  }

  String _getNounHint(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, bool advanced, {bool isCorrect = true}) {
    final List<String> hints = [];
    
    if (advanced && patternData != null) {
      try {
        final plural = patternData['plural'];
        if (plural != null && plural is String && plural.isNotEmpty && plural != word.word && plural != '-') {
          hints.add('✓ Mehrzahl: ${word.word} → $plural');
        }
        
        final gender = patternData['gender'];
        if (gender != null && gender is String) {
          final genderMap = {
            'Masculine': 'maskulin (der)',
            'Feminine': 'feminin (die)',
            'Neuter': 'neutral (das)',
          };
          final genderLabel = genderMap[gender] ?? gender;
          hints.add('✓ Genus: $genderLabel');
        }
      } catch (e) {}
    }
    
    if (word.article != null && word.article!.isNotEmpty) {
      hints.add('✓ Nomen: ${word.article} ${word.word}');
    }
    
    if (apiData?.definitions.isNotEmpty ?? false) {
      hints.add('✓ ${apiData!.definitions.first}');
    }
    
    hints.add('✓ Nomen groß: ${word.word} (Großschreibung!)');
        
    if (hints.isEmpty) {
      hints.add('✓ Richtig: ${word.word} ist ein Nomen!');
    }
    
    return _selectHintFromList(hints);
  }

  String _getVerbHint(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, bool advanced, {bool isCorrect = true}) {
    final List<String> hints = [];
    
    if (advanced && patternData != null) {
      try {
        final conjugation = patternData['conjugation']?['Präsens'];
        if (conjugation != null && conjugation is Map) {
          final ich = conjugation['ich'];
          final du = conjugation['du'];
          
          if (ich != null && du != null) {
            hints.add('✓ Personalformen: ich $ich, du $du');
          }
        }
        
        final participles = patternData['participles'];
        if (participles != null && participles is Map) {
          final partizipII = participles['Partizip Perfekt'];
          if (partizipII != null && partizipII is String) {
            hints.add('✓ Perfekt: $partizipII');
          }
        }
        
        final prateritum = patternData['conjugation']?['Präteritum'];
        if (prateritum != null && prateritum is Map && prateritum['ich'] != null) {
          hints.add('✓ Präteritum: ich ${prateritum['ich']}');
        }
      } catch (e) {}
    }
    
    if (apiData?.definitions.isNotEmpty ?? false) {
      hints.add('✓ ${apiData!.definitions.first}');
    }

    hints.add('✓ Verb: ${word.word} → beschreibt Handlung');
    
    if (hints.isEmpty) {
      hints.add('✓ Richtig: ${word.word} ist ein Verb!');
    }
    
    return _selectHintFromList(hints);
  }

  String _getAdjectiveHint(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, bool advanced, {bool isCorrect = true}) {
    final List<String> hints = [];
    
    if (advanced && patternData != null) {
      try {
        final comp = patternData['comparative'];
        final superl = patternData['superlative'];
        
        if (comp != null && superl != null && comp is String && superl is String && comp.isNotEmpty && superl.isNotEmpty) {
          hints.add('✓ Steigerung: ${word.word} → $comp → $superl');
        } else if (comp != null && comp is String && comp.isNotEmpty) {
          hints.add('✓ Komparativ: ${word.word} → $comp');
        }
      } catch (e) {}
    }
    
    if (apiData?.definitions.isNotEmpty ?? false) {
      hints.add('✓ ${apiData!.definitions.first}');
    }

    hints.add('✓ Adjektiv: ${word.word} → Eigenschaft');
    hints.add('✓ Wie-Frage: "Wie ist es?" → ${word.word}');
    
    if (hints.isEmpty) {
      hints.add('✓ Richtig: ${word.word} ist ein Adjektiv!');
    }
    
    return _selectHintFromList(hints);
  }

  String _getAdverbHint(GermanWord word, ApiEnrichment? apiData, bool advanced) {
    final hints = [
      '✓ Adverb: ${word.word} → unveränderlich!',
      '✓ Wie-Frage: "Wie?" → ${word.word}',
    ];
    
    if (advanced && (apiData?.definitions.isNotEmpty ?? false)) {
      hints.add('✓ ${apiData!.definitions.first}');
    }
    
    return _selectHintFromList(hints);
  }

  String _getPronomenHint(GermanWord word, ApiEnrichment? apiData, bool advanced) {
    final hints = [
      '✓ Pronomen: ${word.word} → ersetzt Nomen',
      '✓ ${word.word} → steht für ein Nomen',
    ];
    
    if (advanced && (apiData?.definitions.isNotEmpty ?? false)) {
      hints.add('✓ ${apiData!.definitions.first}');
    }
    
    return _selectHintFromList(hints);
  }

  String _generateIncorrectHint(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, 
      GermanWordType? guessedType, bool advanced) {
    
    String wrongPart = guessedType != null 
        ? '✗ Kein ${_getCategoryNameGerman(guessedType)}!\n'
        : '✗ Falsch!\n';
    
    String correctPart = _getDetailedCorrectExplanation(word, apiData, patternData, guessedType);
    
    return wrongPart + correctPart;
  }

  String _getDetailedCorrectExplanation(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, GermanWordType? guessedType) {
    switch (word.wordType) {
      case GermanWordType.substantiv:
        return _getNounCorrectExplanation(word, apiData, patternData, guessedType);
      case GermanWordType.verb:
        return _getVerbCorrectExplanation(word, apiData, patternData, guessedType);
      case GermanWordType.adjektiv:
        return _getAdjectiveCorrectExplanation(word, apiData, patternData, guessedType);
      default:
        if(apiData?.definitions.isNotEmpty ?? false) {
          return '✓ ${_getCategoryNameGerman(word.wordType)}: "${apiData!.definitions.first}"';
        }
        return '✓ ${word.word} → ${_getCategoryNameGerman(word.wordType)}';
    }
  }

  String _getNounCorrectExplanation(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, GermanWordType? guessedType) {
    final List<String> reasons = [];
    
    if (word.article != null && word.article!.isNotEmpty) {
      reasons.add('${word.article} ${word.word}');
    }
    
    if (guessedType == GermanWordType.verb) {
      reasons.add('nicht konjugierbar');
    } else if (guessedType == GermanWordType.adjektiv) {
      reasons.add('nicht steigerbar');
    }
    
    try {
      final plural = patternData?['plural'];
      if (plural != null && plural is String && plural.isNotEmpty && plural != word.word && plural != '-') {
        reasons.add('Plural: $plural');
      }
    } catch (e) {}
    
    if (reasons.isEmpty) {
      return '✓ ${word.word} → Nomen (Großschreibung!)';
    }
    
    return '✓ Nomen: ${reasons.join(' • ')}';
  }

  String _getVerbCorrectExplanation(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, GermanWordType? guessedType) {
    final List<String> reasons = [];
    
    try {
      final conj = patternData?['conjugation']?['Präsens'];
      if (conj != null && conj is Map) {
        final ich = conj['ich'];
        final du = conj['du'];
        if (ich != null && du != null) {
          reasons.add('ich $ich, du $du');
        } else if (ich != null) {
          reasons.add('z.B. ich $ich');
        }
      }
    } catch (e) {}
    
    if (guessedType == GermanWordType.substantiv) {
      reasons.add('kein Artikel');
    }
    
    if (reasons.isEmpty) {
      return '✓ Verb: ${word.word} → Handlung!';
    }
    
    return '✓ Verb: ${reasons.join(' • ')}';
  }

  String _getAdjectiveCorrectExplanation(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, GermanWordType? guessedType) {
    final List<String> reasons = [];
    
    try {
      final comp = patternData?['comparative'];
      if (comp != null && comp is String && comp.isNotEmpty) {
        reasons.add('steigerbar: $comp');
      }
    } catch (e) {}
    
    if (guessedType == GermanWordType.substantiv) {
      reasons.add('kein Artikel');
    }
    
    if (reasons.isEmpty) {
      reasons.add('der ${word.word}e Mann');
    }
    
    return '✓ Adjektiv: ${reasons.join(' • ')}';
  }
  
  String _selectHintFromList(List<String> hints) {
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
      default: return type.toString().split('.').last;
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
    final String selectedFontFamily = context.watch<GameProvider>().selectedFontFamily;
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
                Expanded(child: _buildGameContent(selectedFontFamily)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameContent(String selectedFontFamily) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive breakpoint
        final isWideScreen = constraints.maxWidth > 800;
        final isTablet = constraints.maxWidth > 600 && constraints.maxWidth <= 800;
        
        return Stack(
          children: [
            // Main game layout
            if (isWideScreen)
              _buildWideScreenLayout(selectedFontFamily)
            else if (isTablet)
              _buildTabletLayout(selectedFontFamily)
            else
              _buildMobileLayout(selectedFontFamily),
            
            // Non-blocking confetti
            if (_showConfetti)
              IgnorePointer(child: _buildCategoryConfetti()),
            
            // Non-blocking hint overlay
            Positioned(
              top: 8,
              right: 8,
              left: 8,
              child: Align(
                alignment: Alignment.topCenter,
                child: _buildFloatingHint(selectedFontFamily)
              )
            ),
          ],
        );
      },
    );
  }

  Widget _buildWideScreenLayout(String selectedFontFamily) {
    return Row(
      children: [
        // Left side: Draggable word (40%)
        Expanded(
          flex: 4,
          child: Center(
            child: _currentWord == null 
                ? const SizedBox.shrink() 
                : _buildDraggableWord(selectedFontFamily),
          ),
        ),
        // Right side: Drop targets (60%)
        Expanded(
          flex: 6,
          child: _buildDropTargets(),
        ),
      ],
    );
  }

  Widget _buildTabletLayout(String selectedFontFamily) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Center(
            child: _currentWord == null 
                ? const SizedBox.shrink() 
                : _buildDraggableWord(selectedFontFamily),
          ),
        ),
        Expanded(
          flex: 5,
          child: _buildDropTargets(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(String selectedFontFamily) {
    return Column(
      children: [
        // Top: Draggable word
        // Reduced flex to give more space to buttons on small screens
        Expanded(
          flex: 3,
          child: Center(
            child: _currentWord == null 
                ? const SizedBox.shrink() 
                : _buildDraggableWord(selectedFontFamily),
          ),
        ),
        // Bottom: Drop targets
        Expanded(
          flex: 7,
          child: _buildDropTargets(),
        ),
      ],
    );
  }

  Widget _buildFloatingHint(String selectedFontFamily) {
    return FadeTransition(
      opacity: _hintAnimation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.8, end: 1.0).animate(
          CurvedAnimation(parent: _hintController, curve: Curves.elasticOut),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500), 
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: _currentHint == null 
            ? const SizedBox.shrink() 
            : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _feedbackState == FeedbackState.correct
                      ? [Colors.green.shade400, Colors.green.shade600]
                      : [Colors.orange.shade400, Colors.deepOrange.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: (_feedbackState == FeedbackState.correct 
                        ? Colors.green 
                        : Colors.orange).withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    _feedbackState == FeedbackState.correct 
                        ? Icons.check_circle 
                        : Icons.lightbulb,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentHint!,
                      style: TextStyle(
                        fontFamily: selectedFontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
            ),
        ),
      ),
    );
  }


  Widget _buildDraggableWord(String selectedFontFamily) {
    // --- UPDATED: Removed article display ---
    // We strictly use .word so "Haus" shows instead of "das Haus"
    final String displayWord = _currentWord!.word;

    return Opacity(
      opacity: _isDragging ? 0.0 : 1.0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Draggable<GermanWordType>(
            data: _currentWord!.wordType,
            onDragStarted: () => setState(() => _isDragging = true),
            onDragEnd: (details) => setState(() => _isDragging = false),
            feedback: _buildWordCard(displayWord, selectedFontFamily, isFeedback: true),
            childWhenDragging: _buildWordCard(displayWord, selectedFontFamily, isPlaceholder: true),
            child: _buildWordCard(displayWord, selectedFontFamily),
          ),
        ],
      ),
    );
  }

  Widget _buildWordCard(String word, String selectedFontFamily, {bool isFeedback = false, bool isPlaceholder = false}) {
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
        constraints: const BoxConstraints(minHeight: 80, maxHeight: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isPlaceholder
              ? Colors.transparent
              : SpaceTheme.deepSpace.withOpacity(isFeedback ? 0.9 : 1.0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 3),
          boxShadow: isFeedback
              ? [BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)]
              : [BoxShadow(color: borderColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              word, 
              style: SpaceTheme.headlineStyle.copyWith(fontFamily: selectedFontFamily, fontSize: 32),
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropTargets() {
    // --- UPDATED: Flexible Column Layout ---
    // Instead of calculating height manually, we use a Column with Expanded children.
    // This ensures that whether we have 3 or 5 categories, they equally split
    // the available vertical space (the bottom 70% of the screen).
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _targetCategories.entries.map((entry) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
              child: _buildDragTarget(
                targetType: entry.key,
                label: entry.value.label,
                icon: entry.value.icon,
                color: entry.value.color,
              ),
            ),
          );
        }).toList(),
      ),
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
          // Width is handled by parent column/stretch
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
                : [BoxShadow(color: color.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Adaptive icon size based on available height
                final iconSize = (constraints.maxHeight * 0.4).clamp(20.0, 40.0);
                
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: iconSize, color: color),
                    const SizedBox(width: 12),
                    // Prevent text overflow on small screens
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label, 
                          style: SpaceTheme.titleStyle.copyWith(
                            color: color, 
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
            ),
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
    switch (type) {
      case GermanWordType.substantiv: return '🏠';
      case GermanWordType.verb: return '🏃';
      case GermanWordType.adjektiv: return '🎨';
      case GermanWordType.adverb: return '⚡';
      case GermanWordType.pronomen: return '👤';
      default: return '⭐';
    }
  }
}