// lib/features/games/screens/word_sort_game.dart
import 'dart:async';
import 'dart:collection';
import 'dart:math';
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

    // Show smart, non-blocking hint
    _showSmartHint(_currentWord!, isCorrect: true);

    // Confetti animation (non-blocking)
    _confettiController.forward(from: 0.0);

    // Auto-advance after 1.5 seconds
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

    // Show educational hint
    _showSmartHint(_currentWord!, isCorrect: false, guessedType: guessedCategory);

    // Show error state for 2 seconds, then reset
    _feedbackTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _feedbackState = FeedbackState.none;
        });
      }
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
      if (mounted) {
        _hintController.reverse();
      }
    });
  }

  String _generateSmartHint(GermanWord word, {required bool isCorrect, GermanWordType? guessedType}) {
    final inflection = word.inflectionData;
    
    // Track hint diversity - check if we're using too many similar hints
    final genericHintCount = _hintUsageCount.values.where((count) => count >= 2).length;
    final shouldUseAdvancedHints = genericHintCount >= 1 || _wordsCorrect >= 3;
    
    if (isCorrect) {
      return _generateCorrectHint(word, inflection, shouldUseAdvancedHints);
    } else {
      return _generateIncorrectHint(word, inflection, guessedType, shouldUseAdvancedHints);
    }
  }

  String _generateCorrectHint(GermanWord word, Map<String, dynamic>? inflection, bool advanced) {
    switch (word.wordType) {
      case GermanWordType.substantiv:
        return _getNounHint(word, inflection, advanced, isCorrect: true);
      case GermanWordType.verb:
        return _getVerbHint(word, inflection, advanced, isCorrect: true);
      case GermanWordType.adjektiv:
        return _getAdjectiveHint(word, inflection, advanced, isCorrect: true);
      case GermanWordType.adverb:
        return _getAdverbHint(word, advanced);
      case GermanWordType.pronomen:
        return _getPronomenHint(word, advanced);
      default:
        return '✓ Richtig!';
    }
  }

  String _getNounHint(GermanWord word, Map<String, dynamic>? inflection, bool advanced, {bool isCorrect = true}) {
    final List<String> hints = [];
    
    if (advanced && inflection != null) {
      final nounData = inflection['analyses']?['noun'];
      
      if (nounData != null) {
        // 1. Declension patterns
        final declension = nounData['declension'];
        if (declension != null) {
          final nom = declension['Nominativ Singular']?['definite'];
          final gen = declension['Genitiv Singular']?['definite'];
          final dat = declension['Dativ Singular']?['definite'];
          
          if (nom != null && dat != null) {
            hints.add('✓ Maskulinprobe: $nom → $dat (Dativ)');
          }
          if (nom != null && gen != null) {
            hints.add('✓ Artikelprobe: $nom (Nom.) → $gen (Gen.)');
          }
        }
        
        // 2. Plural formation
        final plural = nounData['plural'];
        if (plural != null && plural != word.word && plural != '-') {
          hints.add('✓ Plural: ${word.word} → $plural');
        }
        
        // 3. Gender information
        final gender = nounData['gender'];
        if (gender != null) {
          final genderMap = {
            'Masculine': 'maskulin (der)',
            'Feminine': 'feminin (die)',
            'Neuter': 'neutral (das)',
          };
          final genderLabel = genderMap[gender] ?? gender;
          hints.add('✓ Genus: $genderLabel');
        }
      }
    }
    
    // Article-based hints
    if (word.article != null && word.article!.isNotEmpty) {
      hints.add('✓ Nomen: ${word.article} ${word.word} → Artikel zeigt\'s!');
      hints.add('✓ Sandwichprobe: ${word.article} große ${word.word} ✓');
      hints.add('✓ Artikelprobe: ${word.article} ${word.word}');
    }
    
    // Plural hints
    if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
      hints.add('✓ Mehrzahl: ${word.word} → ${word.plural}');
    } else if (word.nurImPlural) {
      hints.add('✓ Nur Plural: ${word.word}');
    }
    
    // Capitalization rule
    hints.add('✓ Nomen groß: ${word.word} (Großschreibung!)');
    
    // Genus info
    if (word.genus != null && word.genus!.isNotEmpty) {
      hints.add('✓ ${word.genus}: ${word.word}');
    }
    
    // Fallback
    if (hints.isEmpty) {
      hints.add('✓ Richtig: ${word.word} ist ein Nomen!');
    }
    
    return _selectHintFromList(hints);
  }

  String _getVerbHint(GermanWord word, Map<String, dynamic>? inflection, bool advanced, {bool isCorrect = true}) {
    final List<String> hints = [];
    
    if (advanced && inflection != null) {
      final verbData = inflection['analyses']?['verb'];
      
      if (verbData != null) {
        // 1. Present tense conjugation
        final conjugation = verbData['conjugation']?['Präsens'];
        if (conjugation != null) {
          final ich = conjugation['ich'];
          final du = conjugation['du'];
          final er = conjugation['er'] ?? conjugation['sie'] ?? conjugation['es'];
          
          if (ich != null && du != null) {
            hints.add('✓ Personalformen: $ich / $du');
          }
          if (ich != null && er != null) {
            hints.add('✓ Konjugation: $ich / $er');
          }
        }
        
        // 2. Participles
        final participles = verbData['participles'];
        if (participles != null) {
          final partizipII = participles['Partizip II'];
          if (partizipII != null) {
            hints.add('✓ Perfekt: ${word.word} → $partizipII');
          }
        }
        
        // 3. Imperative
        final imperative = verbData['imperative'];
        if (imperative != null && imperative['du'] != null) {
          hints.add('✓ Imperativ: ${imperative['du']}!');
        }
        
        // 4. Past tense
        final prateritum = verbData['conjugation']?['Präteritum'];
        if (prateritum != null && prateritum['ich'] != null) {
          hints.add('✓ Vergangenheit: ${word.word} → ${prateritum['ich']}');
        }
      }
    }
    
    // Basic verb hints
    final baseForm = word.word.toLowerCase();
    if (baseForm.endsWith('en')) {
      final stem = baseForm.substring(0, baseForm.length - 2);
      hints.add('✓ Verb: ich ${stem}e, du ${stem}st');
      hints.add('✓ Infinitiv: ${word.word} → ich ${stem}e');
    }
    
    hints.add('✓ Verb: ${word.word} → beschreibt Handlung');
    hints.add('✓ Frageprobe: "Was tut man?" → ${word.word}');
    hints.add('✓ Zeitformenprobe: ${word.word} (Präsens)');
    
    // Fallback
    if (hints.isEmpty) {
      hints.add('✓ Richtig: ${word.word} ist ein Verb!');
    }
    
    return _selectHintFromList(hints);
  }

  String _getAdjectiveHint(GermanWord word, Map<String, dynamic>? inflection, bool advanced, {bool isCorrect = true}) {
    final List<String> hints = [];
    
    if (advanced && inflection != null) {
      final adjData = inflection['analyses']?['adjective'];
      
      if (adjData != null) {
        // 1. Comparison forms
        final comp = adjData['comparative'];
        final superl = adjData['superlative'];
        
        if (comp != null && superl != null && comp != '-' && superl != '-') {
          hints.add('✓ Steigerung: ${word.word} → $comp → $superl');
        }
        if (comp != null && comp != '-') {
          hints.add('✓ Komparativ: ${word.word} → $comp');
        }
        
        // 2. Declension in different cases
        final declension = adjData['declension'];
        if (declension != null) {
          final nom = declension['Nominativ']?['maskulin']?['definite'];
          if (nom != null) {
            hints.add('✓ Deklination: der ${nom} Mann');
          }
        }
      }
    }
    
    // Basic adjective hints
    hints.add('✓ Adjektiv: ${word.word} → Eigenschaft');
    hints.add('✓ Sandwichprobe: der ${word.word}e Baum ✓');
    hints.add('✓ Steigerbar: ${word.word}, ${word.word}er');
    hints.add('✓ Wie-Frage: "Wie ist es?" → ${word.word}');
    hints.add('✓ Attributiv: das ${word.word}e Kind');
    
    // Fallback
    if (hints.isEmpty) {
      hints.add('✓ Richtig: ${word.word} ist ein Adjektiv!');
    }
    
    return _selectHintFromList(hints);
  }

  String _getAdverbHint(GermanWord word, bool advanced) {
    final hints = [
      '✓ Adverb: ${word.word} → unveränderlich!',
      '✓ Wie-Frage: "Wie?" → ${word.word}',
      '✓ Adverb: beschreibt WIE etwas passiert',
      '✓ ${word.word} → nicht flektierbar',
    ];
    
    if (advanced && word.exampleSentences.isNotEmpty) {
      hints.add('✓ Beispiel: ${word.exampleSentences.first}');
    }
    
    return _selectHintFromList(hints);
  }

  String _getPronomenHint(GermanWord word, bool advanced) {
    final hints = [
      '✓ Pronomen: ${word.word} → ersetzt Nomen',
      '✓ ${word.word} → steht für ein Nomen',
      '✓ Fürwort: ${word.word}',
    ];
    
    // Add case information if available
    if (word.caseSpacy != null && word.caseSpacy!.isNotEmpty) {
      final caseMap = {
        'Nom': 'Nominativ',
        'Acc': 'Akkusativ', 
        'Dat': 'Dativ',
        'Gen': 'Genitiv',
      };
      final caseName = caseMap[word.caseSpacy] ?? word.caseSpacy!;
      hints.add('✓ ${word.word} → $caseName');
    }
    
    // Add pronoun type
    if (word.pronTypeSpacy != null && word.pronTypeSpacy!.isNotEmpty) {
      hints.add('✓ ${word.pronTypeSpacy}: ${word.word}');
    }
    
    return _selectHintFromList(hints);
  }

  String _generateIncorrectHint(GermanWord word, Map<String, dynamic>? inflection, 
      GermanWordType? guessedType, bool advanced) {
    
    // Show what they guessed wrong
    String wrongPart = guessedType != null 
        ? '✗ Kein ${_getCategoryNameGerman(guessedType)}!\n'
        : '✗ Falsch!\n';
    
    // Show why it's the correct type with detailed explanation
    String correctPart = _getDetailedCorrectExplanation(word, inflection, guessedType);
    
    return wrongPart + correctPart;
  }

  String _getDetailedCorrectExplanation(GermanWord word, Map<String, dynamic>? inflection, GermanWordType? guessedType) {
    switch (word.wordType) {
      case GermanWordType.substantiv:
        return _getNounCorrectExplanation(word, inflection, guessedType);
      case GermanWordType.verb:
        return _getVerbCorrectExplanation(word, inflection, guessedType);
      case GermanWordType.adjektiv:
        return _getAdjectiveCorrectExplanation(word, inflection, guessedType);
      default:
        return '✓ ${word.word} → ${_getCategoryNameGerman(word.wordType)}';
    }
  }

  String _getNounCorrectExplanation(GermanWord word, Map<String, dynamic>? inflection, GermanWordType? guessedType) {
    final List<String> reasons = [];
    
    // Show article as proof
    if (word.article != null && word.article!.isNotEmpty) {
      reasons.add('${word.article} ${word.word}');
    }
    
    // Show why it's NOT what they guessed
    if (guessedType == GermanWordType.verb) {
      reasons.add('nicht konjugierbar');
    } else if (guessedType == GermanWordType.adjektiv) {
      reasons.add('nicht steigerbar');
    }
    
    // Show plural as proof
    if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
      reasons.add('Plural: ${word.plural}');
    }
    
    if (reasons.isEmpty) {
      return '✓ ${word.word} → Nomen (Großschreibung!)';
    }
    
    return '✓ Nomen: ${reasons.join(' • ')}';
  }

  String _getVerbCorrectExplanation(GermanWord word, Map<String, dynamic>? inflection, GermanWordType? guessedType) {
    final List<String> reasons = [];
    
    // Show conjugation as proof
    if (inflection != null) {
      final verbData = inflection['analyses']?['verb'];
      if (verbData != null) {
        final conj = verbData['conjugation']?['Präsens'];
        if (conj != null) {
          final ich = conj['ich'];
          final du = conj['du'];
          if (ich != null && du != null) {
            reasons.add('$ich, $du');
          } else if (ich != null) {
            reasons.add(ich);
          }
        }
      }
    }
    
    // Show why it's NOT what they guessed
    if (guessedType == GermanWordType.substantiv) {
      reasons.add('kein Artikel');
    } else if (guessedType == GermanWordType.adjektiv) {
      reasons.add('Aktion, keine Eigenschaft');
    }
    
    // Fallback to simple conjugation
    if (reasons.isEmpty && word.word.endsWith('en')) {
      final stem = word.word.substring(0, word.word.length - 2);
      reasons.add('ich ${stem}e');
    }
    
    if (reasons.isEmpty) {
      return '✓ Verb: ${word.word} → Handlung!';
    }
    
    return '✓ Verb: ${reasons.join(' • ')}';
  }

  String _getAdjectiveCorrectExplanation(GermanWord word, Map<String, dynamic>? inflection, GermanWordType? guessedType) {
    final List<String> reasons = [];
    
    // Show comparison as proof
    if (inflection != null) {
      final adjData = inflection['analyses']?['adjective'];
      if (adjData != null) {
        final comp = adjData['comparative'];
        final superl = adjData['superlative'];
        if (comp != null && comp != '-') {
          reasons.add(comp);
        }
        if (superl != null && superl != '-') {
          reasons.add(superl);
        }
      }
    }
    
    // Show why it's NOT what they guessed
    if (guessedType == GermanWordType.substantiv) {
      reasons.add('kein Artikel');
    } else if (guessedType == GermanWordType.verb) {
      reasons.add('nicht konjugierbar');
    }
    
    // Show sandwich test
    if (reasons.isEmpty) {
      reasons.add('der ${word.word}e Mann');
    }
    
    return '✓ Adjektiv: ${reasons.join(' • ')}';
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
                Expanded(child: _buildGameContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive breakpoint
        final isWideScreen = constraints.maxWidth > 800;
        final isTablet = constraints.maxWidth > 600 && constraints.maxWidth <= 800;
        
        return Stack(
          children: [
            // Main game layout
            if (isWideScreen)
              _buildWideScreenLayout()
            else if (isTablet)
              _buildTabletLayout()
            else
              _buildMobileLayout(),
            
            // Non-blocking confetti
            if (_showConfetti)
              IgnorePointer(child: _buildCategoryConfetti()),
            
            // Non-blocking hint overlay
            if (_currentHint != null)
              _buildFloatingHint(),
          ],
        );
      },
    );
  }

  Widget _buildWideScreenLayout() {
    return Row(
      children: [
        // Left side: Draggable word (40%)
        Expanded(
          flex: 4,
          child: Center(
            child: _currentWord == null 
                ? const SizedBox.shrink() 
                : _buildDraggableWord(),
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

  Widget _buildTabletLayout() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Center(
            child: _currentWord == null 
                ? const SizedBox.shrink() 
                : _buildDraggableWord(),
          ),
        ),
        Expanded(
          flex: 5,
          child: _buildDropTargets(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Top: Draggable word
        Expanded(
          flex: 4,
          child: Center(
            child: _currentWord == null 
                ? const SizedBox.shrink() 
                : _buildDraggableWord(),
          ),
        ),
        // Bottom: Drop targets
        Expanded(
          flex: 6,
          child: _buildDropTargets(),
        ),
      ],
    );
  }

  Widget _buildFloatingHint() {
    return Positioned(
      top: 8,
      right: 8,
      left: 8,
      child: FadeTransition(
        opacity: _hintAnimation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(
            CurvedAnimation(parent: _hintController, curve: Curves.elasticOut),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                    style: const TextStyle(
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
    
    // Fallback to article
    if (word.article == 'der') return Colors.blue;
    if (word.article == 'die') return Colors.pink;
    if (word.article == 'das') return Colors.green;
    
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
              : [BoxShadow(color: borderColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive target sizing
        final targetHeight = constraints.maxHeight / _targetCategories.length - 16;
        final clampedHeight = targetHeight.clamp(80.0, 120.0);
        
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: _targetCategories.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: _buildDragTarget(
                targetType: entry.key,
                label: entry.value.label,
                icon: entry.value.icon,
                color: entry.value.color,
                height: clampedHeight,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDragTarget({
    required GermanWordType targetType,
    required String label,
    required IconData icon,
    required Color color,
    required double height,
  }) {
    return DragTarget<GermanWordType>(
      builder: (context, candidateData, rejectedData) {
        final bool isHighlighted = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: height,
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  label, 
                  style: SpaceTheme.titleStyle.copyWith(
                    color: color, 
                    fontSize: 22,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
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