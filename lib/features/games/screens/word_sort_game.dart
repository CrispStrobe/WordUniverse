// lib/features/games/screens/word_sort_game.dart
import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/word_features.dart'; 

import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/game_ui.dart';
import '../widgets/space_background.dart';
import '../../../shared/widgets/onboarding_overlay.dart';
import '../models/game_outcome.dart';

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
  bool _isEmpty = false;
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

  bool _onboardingScheduled = false;

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
        label: _s.wordSortCategoryAdverb,
        icon: Icons.speed,
        color: Colors.purple
      );
    }

    if (widget.gradeLevel.index >= 3) { // Grade 4+
      _targetCategories[GermanWordType.pronomen] = (
        label: _s.wordSortCategoryPronoun,
        icon: Icons.person,
        color: Colors.teal
      );
    }

    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'word_sort_game',
        title: _s.wordSortOnboardingTitle,
        steps: [
          OnboardingStep(
            icon: Icons.touch_app,
            body: _s.wordSortOnboardingDrag,
          ),
          OnboardingStep(
            icon: Icons.school,
            body: _s.wordSortOnboardingBuildingBlocks,
          ),
          OnboardingStep(
            icon: Icons.tips_and_updates,
            body: _s.wordSortOnboardingHints,
          ),
        ],
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

    await _loadLevel();
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
        // Same question as `enrichmentStatus == 'success'`, answered from the
        // feature index so the catalogue stays undecoded.
        word.has(WordFeature.enrichmentSuccess);
  }

  Future<void> _loadLevel() async {
    _score = 0;
    _wordsCorrect = 0;
    _isEmpty = false;
    _hintUsageCount.clear();
    _recentHints.clear();

    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};

    // Build a single lookup map keyed by lowercased word instead of
    // re-scanning the full word list for every review id below.
    final Map<String, GermanWord> wordsByLower = {};
    for (final w in _vocabularyService.getAllWords(_gameProvider)) {
      wordsByLower.putIfAbsent(w.word.toLowerCase(), () => w);
    }

    int reviewWordCount = (_wordsTotal * 0.5).ceil();
    final reviewItemIds = _sriService.getItemsForReview(
      limit: reviewWordCount * 2,
      skillTypeFilter: LanguageSkillType.wordType,
      gradeLevelFilter: widget.gradeLevel.index + 1,
    );

    for (final id in reviewItemIds) {
      final wordString = _extractBaseWordFromSriId(id);
      if (wordString == null) continue;

      final word = wordsByLower[wordString.toLowerCase()];
      if (word == null) continue;

      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
        if (wordsForGame.length >= reviewWordCount) break;
      }
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

    // Smart hints read the enrichment, so decode it for the words in play.
    _wordQueue = Queue.from(await _vocabularyService.hydrate(wordsForGame));
    if (!mounted) return;

    if (_wordQueue.isEmpty) {
      if (kDebugMode) debugPrint("No words found for WordSortGame");
      setState(() {
        _isLoading = false;
        _isEmpty = true;
      });
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
    // Ignore drops while feedback for the current word is still showing —
    // otherwise a second drop would double-record/double-score the same word.
    if (_feedbackState != FeedbackState.none) return;
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
    _audioService.playSound('success');
    _gameProvider.hapticLight();
    setState(() {
      _score += 10;
      _wordsCorrect++;
      _feedbackState = FeedbackState.correct;
      _showConfetti = true;
    });

    if (_gameProvider.hintsEnabled) _showSmartHint(_currentWord!, isCorrect: true);
    _confettiController.forward(from: 0.0);

    _feedbackTimer?.cancel();
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
    _audioService.playSound('failure');
    _gameProvider.hapticHeavy();

    setState(() {
      _feedbackState = FeedbackState.incorrect;
    });

    if (_gameProvider.hintsEnabled) _showSmartHint(_currentWord!, isCorrect: false, guessedType: guessedCategory);

    _feedbackTimer?.cancel();
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
        return _s.wordSortHintCorrect;
    }
  }

  bool get _isDE => _vocabularyService.learningLanguage == 'de';

  String _getNounHint(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, bool advanced, {bool isCorrect = true}) {
    final List<String> hints = [];
    
    if (advanced && patternData != null) {
      try {
        final plural = patternData['plural'];
        if (plural != null && plural is String && plural.isNotEmpty && plural != word.word && plural != '-') {
          hints.add(_s.wordSortHintNounPluralForm(word.word, plural));
        }

        final gender = patternData['gender'];
        if (gender != null && gender is String) {
          final genderMap = {
            'Masculine': _s.wordSortGenderMasculine,
            'Feminine': _s.wordSortGenderFeminine,
            'Neuter': _s.wordSortGenderNeuter,
          };
          final genderLabel = genderMap[gender] ?? gender;
          hints.add(_s.wordSortHintNounGender(genderLabel));
        }
      } catch (e) {}
    }
    
    if (_isDE && word.article != null && word.article!.isNotEmpty) {
      hints.add(_s.wordSortHintNounWithArticle(word.article!, word.word));
    }

    if (word.displayDefinitions.isNotEmpty) {
      hints.add(_s.wordSortHintDefinition(word.displayDefinitions.first));
    }

    hints.add(_s.wordSortHintNounNaming(word.word));

    if (apiData?.synonyms.isNotEmpty ?? false) {
      hints.add(_s.wordSortHintSynonym(apiData!.synonyms.take(2).join(', ')));
    }
    if (apiData?.antonyms.isNotEmpty ?? false) {
      hints.add(_s.wordSortHintAntonym(apiData!.antonyms.first));
    }

    if (hints.isEmpty) {
      hints.add(_s.wordSortHintCorrectAs(word.word, _s.wordTypeNoun));
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
            hints.add(_s.wordSortHintVerbPersonalForms('$ich', '$du'));
          }
        }

        final participles = patternData['participles'];
        if (participles != null && participles is Map) {
          final partizipII = participles['Partizip Perfekt'];
          if (partizipII != null && partizipII is String) {
            hints.add(_s.wordSortHintVerbPerfect(partizipII));
          }
        }

        final prateritum = patternData['conjugation']?['Präteritum'];
        if (prateritum != null && prateritum is Map && prateritum['ich'] != null) {
          hints.add(_s.wordSortHintVerbPast('${prateritum['ich']}'));
        }
      } catch (e) {}
    }

    if (word.displayDefinitions.isNotEmpty) {
      hints.add(_s.wordSortHintDefinition(word.displayDefinitions.first));
    }

    hints.add(_s.wordSortHintVerbAction(word.word));

    if (apiData?.synonyms.isNotEmpty ?? false) {
      hints.add(_s.wordSortHintSynonym(apiData!.synonyms.take(2).join(', ')));
    }
    if (apiData?.antonyms.isNotEmpty ?? false) {
      hints.add(_s.wordSortHintAntonym(apiData!.antonyms.first));
    }

    if (hints.isEmpty) {
      hints.add(_s.wordSortHintCorrectAs(word.word, _s.wordTypeVerb));
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
          hints.add(_s.wordSortHintAdjComparison(word.word, comp, superl));
        } else if (comp != null && comp is String && comp.isNotEmpty) {
          hints.add(_s.wordSortHintAdjComparative(word.word, comp));
        }
      } catch (e) {}
    }

    if (word.displayDefinitions.isNotEmpty) {
      hints.add(_s.wordSortHintDefinition(word.displayDefinitions.first));
    }

    hints.add(_s.wordSortHintAdjQuality(word.word));
    hints.add(_s.wordSortHintAdjQuestion(word.word));

    if (apiData?.synonyms.isNotEmpty ?? false) {
      hints.add(_s.wordSortHintSynonym(apiData!.synonyms.take(2).join(', ')));
    }
    if (apiData?.antonyms.isNotEmpty ?? false) {
      hints.add(_s.wordSortHintAntonym(apiData!.antonyms.first));
    }

    if (hints.isEmpty) {
      hints.add(_s.wordSortHintCorrectAs(word.word, _s.wordTypeAdjective));
    }

    return _selectHintFromList(hints);
  }

  String _getAdverbHint(GermanWord word, ApiEnrichment? apiData, bool advanced) {
    final hints = [
      _s.wordSortHintAdverbAction(word.word),
      _s.wordSortHintAdverbQuestion(word.word),
    ];
    
    if (advanced && (word.displayDefinitions.isNotEmpty)) {
      hints.add(_s.wordSortHintDefinition(word.displayDefinitions.first));
    }

    return _selectHintFromList(hints);
  }

  String _getPronomenHint(GermanWord word, ApiEnrichment? apiData, bool advanced) {
    final hints = [
      _s.wordSortHintPronounReplaces(word.word),
      _s.wordSortHintPronounStands(word.word),
    ];

    if (advanced && (word.displayDefinitions.isNotEmpty)) {
      hints.add(_s.wordSortHintDefinition(word.displayDefinitions.first));
    }
    
    return _selectHintFromList(hints);
  }

  String _generateIncorrectHint(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, 
      GermanWordType? guessedType, bool advanced) {
    
    String wrongPart = guessedType != null
        ? '${_s.wordSortHintNotA(_getCategoryName(guessedType))}\n'
        : '${_s.wordSortHintWrong}\n';
    
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
        if (word.displayDefinitions.isNotEmpty) {
          return _s.wordSortExplainCategoryDefinition(_getCategoryName(word.wordType), word.displayDefinitions.first);
        }
        return _s.wordSortExplainCategory(word.word, _getCategoryName(word.wordType));
    }
  }

  String _getNounCorrectExplanation(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, GermanWordType? guessedType) {
    final List<String> reasons = [];

    if (_isDE) {
      if (word.article != null && word.article!.isNotEmpty) {
        reasons.add('${word.article} ${word.word}');
      }
      if (guessedType == GermanWordType.verb) {
        reasons.add(_s.wordSortReasonNotConjugable);
      } else if (guessedType == GermanWordType.adjektiv) {
        reasons.add(_s.wordSortReasonNotComparable);
      }
      try {
        final plural = patternData?['plural'];
        if (plural != null && plural is String && plural.isNotEmpty && plural != word.word && plural != '-') {
          reasons.add(_s.wordSortReasonPlural(plural));
        }
      } catch (e) {}
      if (reasons.isEmpty) return _s.wordSortExplainNounCapitalized(word.word);
      return _s.wordSortExplainNounReasons(reasons.join(' • '));
    } else {
      try {
        final plural = patternData?['plural'];
        if (plural != null && plural is String && plural.isNotEmpty && plural != word.word && plural != '-') {
          reasons.add(_s.wordSortReasonPlural(plural));
        }
      } catch (e) {}
      if (reasons.isEmpty) return _s.wordSortExplainNounNaming(word.word);
      return _s.wordSortExplainNounReasons(reasons.join(' • '));
    }
  }

  String _getVerbCorrectExplanation(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, GermanWordType? guessedType) {
    final List<String> reasons = [];

    if (_isDE) {
      try {
        final conj = patternData?['conjugation']?['Präsens'];
        if (conj != null && conj is Map) {
          final ich = conj['ich'];
          final du = conj['du'];
          if (ich != null && du != null) {
            reasons.add(_s.wordSortReasonVerbForms('$ich', '$du'));
          } else if (ich != null) {
            reasons.add(_s.wordSortReasonVerbFormExample('$ich'));
          }
        }
      } catch (e) {}
      if (guessedType == GermanWordType.substantiv) reasons.add(_s.wordSortReasonNoArticle);
      if (reasons.isEmpty) return _s.wordSortExplainVerbAction(word.word);
      return _s.wordSortExplainVerbReasons(reasons.join(' • '));
    } else {
      if (word.displayDefinitions.isNotEmpty) {
        return _s.wordSortExplainVerbDefinition(word.displayDefinitions.first);
      }
      return _s.wordSortExplainVerbAction(word.word);
    }
  }

  String _getAdjectiveCorrectExplanation(GermanWord word, ApiEnrichment? apiData, Map<String, dynamic>? patternData, GermanWordType? guessedType) {
    final List<String> reasons = [];

    if (_isDE) {
      try {
        final comp = patternData?['comparative'];
        if (comp != null && comp is String && comp.isNotEmpty) {
          reasons.add(_s.wordSortReasonComparable(comp));
        }
      } catch (e) {}
      if (guessedType == GermanWordType.substantiv) reasons.add(_s.wordSortReasonNoArticle);
      if (reasons.isEmpty) reasons.add(_s.wordSortReasonAdjExample(word.word));
      return _s.wordSortExplainAdjReasons(reasons.join(' • '));
    } else {
      try {
        final comp = patternData?['comparative'];
        if (comp != null && comp is String && comp.isNotEmpty) {
          reasons.add(_s.wordSortReasonComparable(comp));
        }
      } catch (e) {}
      if (reasons.isEmpty) {
        if (word.displayDefinitions.isNotEmpty) {
          return _s.wordSortExplainAdjDefinition(word.displayDefinitions.first);
        }
        return _s.wordSortExplainAdjQuality(word.word);
      }
      return _s.wordSortExplainAdjReasons(reasons.join(' • '));
    }
  }
  
  String _selectHintFromList(List<String> hints) {
    hints.sort((a, b) => (_hintUsageCount[a] ?? 0).compareTo(_hintUsageCount[b] ?? 0));
    return hints.first;
  }

  String _getCategoryName(GermanWordType type) {
    switch (type) {
      case GermanWordType.substantiv: return _s.wordTypeNoun;
      case GermanWordType.verb: return _s.wordTypeVerb;
      case GermanWordType.adjektiv: return _s.wordTypeAdjective;
      case GermanWordType.adverb: return _s.wordTypeAdverb;
      case GermanWordType.pronomen: return _s.wordTypePronoun;
      default: return type.toString().split('.').last;
    }
  }

  void _showGameOver() {
    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'word_sort_game',
      difficulty: widget.gradeLevel.index + 1,
      score: _score,
      wasSuccessful: _wordsCorrect >= (_wordsTotal * 0.7),
    ));

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
            autofocus: true,
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
              else if (_isEmpty)
                Expanded(child: _buildEmptyState())
              else
                Expanded(child: _buildGameContent(selectedFontFamily)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 72, color: Colors.white70),
            const SizedBox(height: 24),
            Text(
              _s.wordSortEmptyTitle,
              style: SpaceTheme.titleStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _s.wordSortEmptyMessage,
              style: SpaceTheme.bodyStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(backgroundColor: SpaceTheme.planetOrange),
              child: Text(_s.gameBack),
            ),
          ],
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
                        : Colors.orange).withValues(alpha: 0.5),
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
          // Semantics goes on the child of Draggable, not around it —
          // wrapping the Draggable itself can interfere with Flutter web's
          // pointer pipeline and freeze drag/tap input on some browsers.
          Draggable<GermanWordType>(
            data: _currentWord!.wordType,
            onDragStarted: () => setState(() => _isDragging = true),
            onDragEnd: (details) => setState(() => _isDragging = false),
            feedback: _buildWordCard(displayWord, selectedFontFamily, isFeedback: true),
            childWhenDragging: _buildWordCard(displayWord, selectedFontFamily, isPlaceholder: true),
            child: Semantics(
              button: true,
              label: _s.wordSortDragLabel(displayWord),
              child: _buildWordCard(displayWord, selectedFontFamily),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordCard(String word, String selectedFontFamily, {bool isFeedback = false, bool isPlaceholder = false}) {
    Color borderColor = SpaceTheme.planetOrange;
    IconData? feedbackIcon;
    if (_feedbackState == FeedbackState.correct) {
      borderColor = Colors.green;
      feedbackIcon = Icons.check_circle;
    } else if (_feedbackState == FeedbackState.incorrect) {
      borderColor = Colors.red;
      feedbackIcon = Icons.cancel;
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
              : SpaceTheme.deepSpace.withValues(alpha: isFeedback ? 0.9 : 1.0),
          borderRadius: BorderRadius.circular(16),
          // Border style changes on incorrect to add a shape signal
          // alongside the color (color-blind redundancy).
          border: Border.all(color: borderColor, width: _feedbackState == FeedbackState.incorrect ? 5 : 3),
          boxShadow: isFeedback
              ? [BoxShadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5)]
              : [BoxShadow(color: borderColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Stack(
          children: [
            Center(
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
            if (feedbackIcon != null && !isPlaceholder)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(feedbackIcon, color: borderColor, size: 24),
              ),
          ],
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
    // Semantics goes on the builder's output (the visual) rather than
    // wrapping DragTarget itself. Wrapping DragTarget directly with
    // Semantics can interfere with Flutter web's pointer pipeline.
    return DragTarget<GermanWordType>(
      builder: (context, candidateData, rejectedData) {
        final bool isHighlighted = candidateData.isNotEmpty;
        return Semantics(
          button: true,
          label: _s.wordSortDropZoneLabel(label),
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          // Width is handled by parent column/stretch; enforce a minimum
          // touch-target height (≥48dp) for accessibility.
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: isHighlighted
                ? color.withValues(alpha: 0.4)
                : SpaceTheme.deepSpace.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isHighlighted ? color : color.withValues(alpha: 0.5),
              width: 3,
            ),
            boxShadow: isHighlighted
                ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 15, spreadRadius: 2)]
                : [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))],
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
        ),
        );
      },
      onWillAcceptWithDetails: (data) => true,
      onAcceptWithDetails: (details) {
        _handleDrop(details.data, targetType);
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
