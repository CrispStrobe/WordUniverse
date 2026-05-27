// lib/features/games/screens/grossschreibungs_galaxie_game.dart
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
import '../providers/game_provider.dart';
import '../widgets/space_background.dart';
import '../models/game_outcome.dart';

/// Großschreibungs-Galaxie - Teaching German capitalization rules
/// Full sentences fall with target word in ALL CAPS
/// Player clicks word to cycle: ALL CAPS → Capitalized → lowercase → ALL CAPS
class GrossschreibungsGalaxieGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const GrossschreibungsGalaxieGame({super.key, required this.gradeLevel});

  @override
  State<GrossschreibungsGalaxieGame> createState() => _GrossschreibungsGalaxieGameState();
}

enum WordCase { allCaps, capitalized, lowercase }
enum CapitalizationRule { noun, verbOrAdjective, sentenceStart }

class SentenceChallenge {
  final String beforeWord; // Text before the target word
  final String targetWord; // The word to test (original correct form)
  final String afterWord; // Text after the target word
  final WordCase correctCase; // What the player should select
  final CapitalizationRule rule;
  final String explanation;
  final String wordId;
  final bool isAtSentenceStart;

  SentenceChallenge({
    required this.beforeWord,
    required this.targetWord,
    required this.afterWord,
    required this.correctCase,
    required this.rule,
    required this.explanation,
    required this.wordId,
    required this.isAtSentenceStart,
  });

  String get fullSentence => '$beforeWord$targetWord$afterWord';
}

enum FeedbackState { none, correct, incorrect }

class _GrossschreibungsGalaxieGameState extends State<GrossschreibungsGalaxieGame>
    with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  final List<SentenceChallenge> _challengeQueue = [];
  SentenceChallenge? _currentChallenge;
  WordCase _currentWordCase = WordCase.allCaps; // Player's current selection
  int _score = 0;
  int _itemsCompleted = 0;
  int _totalItems = 25;
  int _combo = 0;
  int _correctCount = 0;
  int _maxCombo = 0;
  int _level = 1;

  // Animation
  late AnimationController _fallingController;
  late Animation<double> _fallingAnimation;
  double _fallingSpeed = 8.0; // seconds per sentence (slower)

  // Feedback
  FeedbackState _feedbackState = FeedbackState.none;
  String _feedbackMessage = '';

  // Effects
  late AnimationController _successController;
  late AnimationController _errorController;
  
  // Title fade
  late AnimationController _titleFadeController;
  late Animation<double> _titleFadeAnimation;
  bool _showTitle = true;

  void _log(String message) {
    if (kDebugMode) debugPrint('[GROSSSCHREIBUNG] $message');
  }

  @override
  void initState() {
    super.initState();

    _fallingController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _fallingSpeed.toInt()),
    );

    _fallingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fallingController, curve: Curves.linear),
    );

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _errorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _titleFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _titleFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _titleFadeController, curve: Curves.easeOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void dispose() {
    _fallingController.dispose();
    _successController.dispose();
    _errorController.dispose();
    _titleFadeController.dispose();
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

  void _loadLevel() {
    _score = 0;
    _itemsCompleted = 0;
    _combo = 0;
    _correctCount = 0;
    _maxCombo = 0;
    _level = 1;
    _fallingSpeed = 8.0;

    _generateChallengeQueue();
    _showNextChallenge();

    setState(() => _isLoading = false);

    // Fade out title after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _titleFadeController.forward().then((_) {
          if (mounted) setState(() => _showTitle = false);
        });
      }
    });
  }

  /// Generate capitalization challenges ONLY from words with real example sentences
  void _generateChallengeQueue() {
    _log('========================================');
    _log('Starting challenge generation');
    _log('========================================');
    
    _challengeQueue.clear();
    final challenges = <SentenceChallenge>[];

    // Get all words with examples
    final allWords = _vocabularyService.getAllWords(_gameProvider)
        .where((w) => 
            w.gradeLevel <= widget.gradeLevel.index + 3 && 
            w.word.isNotEmpty &&
            w.examples.isNotEmpty) // ONLY words with examples!
        .toList();

    _log('Total words with examples: ${allWords.length}');

    // Separate by type
    final nouns = allWords.where((w) => w.wordType == GermanWordType.substantiv).toList();
    final verbs = allWords.where((w) => w.wordType == GermanWordType.verb).toList();
    final adjectives = allWords.where((w) => w.wordType == GermanWordType.adjektiv).toList();

    _log('Available nouns with examples: ${nouns.length}');
    _log('Available verbs with examples: ${verbs.length}');
    _log('Available adjectives with examples: ${adjectives.length}');

    // Shuffle
    nouns.shuffle();
    verbs.shuffle();
    adjectives.shuffle();

    _log('');
    _log('--- GENERATING NOUN CHALLENGES (capitalized in middle) ---');
    // RULE 1: Nouns are always capitalized (in middle of sentence)
    int nounAttempts = 0;
    int nounSuccesses = 0;
    for (final noun in nouns) {
      if (nounSuccesses >= 10) break;
      nounAttempts++;
      
      final challenge = _createChallengeFromWord(
        noun,
        correctCase: WordCase.capitalized,
        rule: CapitalizationRule.noun,
        explanation: 'Nomen werden immer großgeschrieben',
        forceMiddlePosition: true,
        attemptNumber: nounAttempts,
      );
      
      if (challenge != null) {
        challenges.add(challenge);
        nounSuccesses++;
        _log('✓ Noun challenge $nounSuccesses created successfully');
      }
    }
    _log('Noun challenges: $nounSuccesses/$nounAttempts successful');

    _log('');
    _log('--- GENERATING VERB CHALLENGES (lowercase in middle) ---');
    // RULE 2: Verbs are lowercase (in middle of sentence)
    int verbAttempts = 0;
    int verbSuccesses = 0;
    for (final verb in verbs) {
      if (verbSuccesses >= 6) break;
      verbAttempts++;
      
      final challenge = _createChallengeFromWord(
        verb,
        correctCase: WordCase.lowercase,
        rule: CapitalizationRule.verbOrAdjective,
        explanation: 'Verben werden kleingeschrieben',
        forceMiddlePosition: true,
        attemptNumber: verbAttempts,
      );
      
      if (challenge != null) {
        challenges.add(challenge);
        verbSuccesses++;
        _log('✓ Verb challenge $verbSuccesses created successfully');
      }
    }
    _log('Verb challenges: $verbSuccesses/$verbAttempts successful');

    _log('');
    _log('--- GENERATING ADJECTIVE CHALLENGES (lowercase in middle) ---');
    // RULE 3: Adjectives are lowercase (in middle of sentence)
    int adjAttempts = 0;
    int adjSuccesses = 0;
    for (final adj in adjectives) {
      if (adjSuccesses >= 6) break;
      adjAttempts++;
      
      final challenge = _createChallengeFromWord(
        adj,
        correctCase: WordCase.lowercase,
        rule: CapitalizationRule.verbOrAdjective,
        explanation: 'Adjektive werden kleingeschrieben',
        forceMiddlePosition: true,
        attemptNumber: adjAttempts,
      );
      
      if (challenge != null) {
        challenges.add(challenge);
        adjSuccesses++;
        _log('✓ Adjective challenge $adjSuccesses created successfully');
      }
    }
    _log('Adjective challenges: $adjSuccesses/$adjAttempts successful');

    _log('');
    _log('--- GENERATING SENTENCE START CHALLENGES (capitalized at start) ---');
    // RULE 4: Sentence start - verbs and adjectives capitalized at start
    int startAttempts = 0;
    int startSuccesses = 0;
    for (final word in [...verbs, ...adjectives]) {
      if (startSuccesses >= 3) break;
      startAttempts++;
      
      final challenge = _createChallengeFromWord(
        word,
        correctCase: WordCase.capitalized,
        rule: CapitalizationRule.sentenceStart,
        explanation: 'Am Satzanfang wird großgeschrieben',
        forceSentenceStart: true,
        attemptNumber: startAttempts,
      );
      
      if (challenge != null) {
        challenges.add(challenge);
        startSuccesses++;
        _log('✓ Sentence start challenge $startSuccesses created successfully');
      }
    }
    _log('Sentence start challenges: $startSuccesses/$startAttempts successful');

    _log('');
    _log('========================================');
    _log('Total challenges created: ${challenges.length}');
    
    // Shuffle and limit
    challenges.shuffle();
    _challengeQueue.addAll(challenges.take(_totalItems));

    _log('Final queue size: ${_challengeQueue.length}');
    _log('========================================');
  }

  /// Create a challenge from a word using ONLY real examples
  SentenceChallenge? _createChallengeFromWord(
    GermanWord word, {
    required WordCase correctCase,
    required CapitalizationRule rule,
    required String explanation,
    bool forceMiddlePosition = false,
    bool forceSentenceStart = false,
    required int attemptNumber,
  }) {
    final wordTypeStr = word.wordType.toString().split('.').last;
    _log('  Attempt #$attemptNumber: "${word.word}" ($wordTypeStr)');
    
    if (word.examples.isEmpty) {
      _log('    ✗ No examples available');
      return null;
    }

    _log('    → Found ${word.examples.length} example(s)');

    // Try each example
    for (int i = 0; i < word.examples.length; i++) {
      final example = word.examples[i];
      
      if (example.text == null || example.text!.isEmpty) {
        _log('    → Example ${i + 1}: empty text, skipping');
        continue;
      }

      final sentence = example.text!;
      _log('    → Example ${i + 1}: "$sentence"');

      // Check sentence length
      if (sentence.length > 120) {
        _log('      ✗ Too long (${sentence.length} chars)');
        continue;
      }

      // Find the word in the sentence at a word boundary, and extend the
      // match through any inflectional ending (so a lemma like
      // "amerikanisch" picks up "amerikanische" / "amerikanischen" as a
      // single token, and "Peter" doesn't get sliced into "Pete"+"r").
      final candidates = <String>{
        word.word,
        if (word.lemma.isNotEmpty) word.lemma,
      }..removeWhere((c) => c.isEmpty);

      int wordIndex = -1;
      int wordEnd = -1;
      String foundWord = word.word;
      for (final candidate in candidates) {
        final escaped = RegExp.escape(candidate);
        // \b on the front; on the tail, eat any German letters that
        // follow without a boundary (the inflection).
        final pattern = RegExp(
          r'\b' + escaped + r'[A-Za-zÄÖÜäöüß]*',
          caseSensitive: false,
        );
        final m = pattern.firstMatch(sentence);
        if (m != null) {
          wordIndex = m.start;
          wordEnd = m.end;
          foundWord = candidate;
          break;
        }
      }

      if (wordIndex == -1) {
        _log('      ✗ Word not found in sentence');
        continue;
      }

      _log('      → Word "$foundWord" found at [$wordIndex,$wordEnd]');

      // Determine if word is at sentence start
      final isAtStart = wordIndex < 3; // First few characters = sentence start
      _log('      → Is at sentence start: $isAtStart');

      // Check position requirements
      if (forceMiddlePosition && isAtStart) {
        _log('      ✗ Need middle position but word is at start');
        continue;
      }

      if (forceSentenceStart && !isAtStart) {
        _log('      ✗ Need sentence start but word is in middle');
        continue;
      }

      // Extract the full inflected form actually present in the sentence.
      final actualWordInSentence = sentence.substring(wordIndex, wordEnd);

      // Extract surrounding parts.
      final before = sentence.substring(0, wordIndex);
      final after = wordEnd < sentence.length ? sentence.substring(wordEnd) : '';

      final challenge = SentenceChallenge(
        beforeWord: before,
        targetWord: actualWordInSentence,
        afterWord: after,
        correctCase: correctCase,
        rule: rule,
        explanation: explanation,
        wordId: word.id,
        isAtSentenceStart: isAtStart,
      );

      _log('      ✓ CREATED: "$before[$actualWordInSentence]$after"');
      return challenge;
    }

    _log('    ✗ No suitable example found after checking all ${word.examples.length} examples');
    return null;
  }

  void _showNextChallenge() {
    if (_itemsCompleted >= _totalItems || _challengeQueue.isEmpty) {
      _showGameOver();
      return;
    }

    setState(() {
      _currentChallenge = _challengeQueue.removeAt(0);
      _currentWordCase = WordCase.allCaps; // Always start with ALL CAPS
      _feedbackState = FeedbackState.none;
      _feedbackMessage = '';
    });

    _fallingController.reset();
    _fallingController.forward().then((_) {
      if (_feedbackState == FeedbackState.none && mounted) {
        _handleMiss();
      }
    });
  }

  /// Player clicks the word to cycle through cases
  void _cycleWordCase() {
    if (_feedbackState != FeedbackState.none) return;
    
    _audioService.playSound('tap');
    
    setState(() {
      switch (_currentWordCase) {
        case WordCase.allCaps:
          _currentWordCase = WordCase.capitalized;
          break;
        case WordCase.capitalized:
          _currentWordCase = WordCase.lowercase;
          break;
        case WordCase.lowercase:
          _currentWordCase = WordCase.allCaps;
          break;
      }
    });
  }

  /// Player submits their choice
  void _submitChoice() {
    if (_currentChallenge == null || _feedbackState != FeedbackState.none) return;

    _fallingController.stop();
    final isCorrect = _currentWordCase == _currentChallenge!.correctCase;

    setState(() {
      _feedbackState = isCorrect ? FeedbackState.correct : FeedbackState.incorrect;
      _feedbackMessage = _currentChallenge!.explanation;
    });

    if (isCorrect) {
      _handleCorrectAnswer();
    } else {
      _handleIncorrectAnswer();
    }
  }

  void _handleCorrectAnswer() {
    _successController.forward().then((_) => _successController.reset());
    _audioService.playSound('success');
    _gameProvider.hapticLight();

    _combo++;
    _correctCount++;
    if (_combo > _maxCombo) _maxCombo = _combo;

    final basePoints = 100;
    final comboMultiplier = 1.0 + (_combo / 10);
    final points = (basePoints * comboMultiplier).round();

    setState(() {
      _score += points;
      _itemsCompleted++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentChallenge!.targetWord,
      wasCorrect: true,
      metadata: {
        'game': 'grossschreibung',
        'wordId': _currentChallenge!.wordId,
        'combo': _combo,
      },
    );

    if (_itemsCompleted % 5 == 0) {
      _levelUp();
    }

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _showNextChallenge();
    });
  }

  void _handleIncorrectAnswer() {
    _errorController.forward().then((_) => _errorController.reset());
    _audioService.playSound('failure');
    _gameProvider.hapticHeavy();

    setState(() {
      _combo = 0;
      _score = max(0, _score - 25);
      _itemsCompleted++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentChallenge!.targetWord,
      wasCorrect: false,
      metadata: {
        'game': 'grossschreibung',
        'wordId': _currentChallenge!.wordId,
      },
    );

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) _showNextChallenge();
    });
  }

  void _handleMiss() {
    final s = S.of(context);
    setState(() {
      _feedbackState = FeedbackState.incorrect;
      _feedbackMessage = s?.gameTooSlow ?? 'Zu langsam!';
      _combo = 0;
      _itemsCompleted++;
    });

    _audioService.playSound('failure');
    _gameProvider.hapticHeavy();

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _showNextChallenge();
    });
  }

  void _levelUp() {
    setState(() {
      _level++;
      _fallingSpeed = max(3.0, _fallingSpeed * 0.92);
      _fallingController.duration = Duration(milliseconds: (_fallingSpeed * 1000).toInt());
    });

    _audioService.playSound('levelup');
  }

  void _showGameOver() {
    final s = S.of(context);
    if (s == null) return;

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'grossschreib_game',
      difficulty: widget.gradeLevel.index + 1,
      score: _score,
      wasSuccessful: _itemsCompleted > 0 && _correctCount * 2 >= _itemsCompleted,
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
            Text('${s.gameScore}: $_score', style: SpaceTheme.bodyStyle),
            Text(s.gameLevelLine(_level), style: SpaceTheme.bodyStyle),
            Text(s.gameMaxComboLine(_maxCombo), style: SpaceTheme.bodyStyle),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _loadLevel();
            },
            child: Text(s.gameReplay, style: SpaceTheme.buttonStyle),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).pop();
            },
            child: Text(s.gameDone, style: SpaceTheme.buttonStyle),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final selectedFontFamily = context.watch<GameProvider>().selectedFontFamily;

    if (_isLoading || s == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(s),
              if (_showTitle) _buildTitleSection(s),
              Expanded(child: _buildGameArea(selectedFontFamily)),
              _buildSubmitButton(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleSection(S s) {
    return FadeTransition(
      opacity: _titleFadeAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            s.grossschreibTitle,
            style: SpaceTheme.headlineStyle.copyWith(fontSize: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(S s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(
            color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Semantics(
            label: S.of(context)!.semanticsBack,
            button: true,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              onPressed: () {
                _fallingController.stop();
                Navigator.of(context).pop();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Stufe $_level',
            container: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SpaceTheme.nebulaPurple.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  s.gameLvlBadge(_level),
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: SpaceTheme.nebulaPurple,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            label: 'Punkte: $_score',
            child: _buildCompactStat(Icons.stars, '$_score', SpaceTheme.starYellow),
          ),
          const SizedBox(width: 6),
          Semantics(
            label: 'Fortschritt: $_itemsCompleted von $_totalItems',
            child: _buildCompactStat(Icons.check_circle_outline, '$_itemsCompleted/$_totalItems', SpaceTheme.cosmicPink),
          ),
          if (_combo > 1) ...[
            const SizedBox(width: 6),
            Semantics(
              label: 'Kombo mal $_combo',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: SpaceTheme.planetOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SpaceTheme.planetOrange),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'x$_combo',
                    style: SpaceTheme.bodyStyle.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: SpaceTheme.planetOrange,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          Flexible(
            child: Text(
              s.grossschreibClickHint,
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 11,
                color: Colors.white70,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameArea(String selectedFontFamily) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _fallingAnimation,
          builder: (context, child) => _buildFallingSentence(
            selectedFontFamily,
            constraints.maxHeight,
          ),
        );
      },
    );
  }

  Widget _buildFallingSentence(String selectedFontFamily, double availableHeight) {
    if (_currentChallenge == null) return const SizedBox.shrink();

    // Calculate position (more space for falling)
    final position = availableHeight * _fallingAnimation.value;

    return Stack(
      children: [
        // Guide line at 75%
        Positioned(
          left: 0,
          right: 0,
          top: availableHeight * 0.75,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  SpaceTheme.nebulaPurple.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Falling sentence
        Positioned(
          left: 16,
          right: 16,
          top: position,
          child: _buildSentenceDisplay(selectedFontFamily),
        ),
      ],
    );
  }

  Widget _buildSentenceDisplay(String selectedFontFamily) {
    final scale = _feedbackState == FeedbackState.correct
        ? 1.0 + (sin(_successController.value * pi) * 0.08)
        : 1.0;

    return AnimatedBuilder(
      animation: _errorController,
      builder: (context, child) {
        final shake = _feedbackState == FeedbackState.incorrect
            ? sin(_errorController.value * pi * 4) * 8
            : 0.0;

        return Transform.translate(
          offset: Offset(shake, 0),
          child: Transform.scale(
            scale: scale,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sentence with tappable word
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _getBorderColor(),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _getBorderColor().withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    // Inline rendering: a single RichText so the line
                    // wraps on real word boundaries. The target word is a
                    // WidgetSpan, so trailing punctuation (commas etc.)
                    // and inflectional context stay glued, and we don't
                    // split mid-word across lines.
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontFamily: selectedFontFamily,
                          fontSize: 20,
                          color: Colors.white.withValues(alpha: 0.9),
                          height: 1.6,
                        ),
                        children: [
                          if (_currentChallenge!.beforeWord.isNotEmpty)
                            TextSpan(text: _currentChallenge!.beforeWord),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Semantics(
                              label:
                                  'Wort: ${_getDisplayWord()}. Tippe, um die Schreibweise zu ändern.',
                              button: true,
                              child: GestureDetector(
                                onTap: _cycleWordCase,
                                behavior: HitTestBehavior.translucent,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _getWordBackgroundColor(),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        width: 2,
                                      ),
                                    ),
                                    child: Text(
                                      _getDisplayWord(),
                                      style: TextStyle(
                                        fontFamily: selectedFontFamily,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_currentChallenge!.afterWord.isNotEmpty)
                            TextSpan(text: _currentChallenge!.afterWord),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Feedback message
                  if (_feedbackState != FeedbackState.none) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: _feedbackState == FeedbackState.correct
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.red.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _feedbackState == FeedbackState.correct
                                ? Colors.green
                                : Colors.red,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _feedbackState == FeedbackState.correct
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _feedbackMessage,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getDisplayWord() {
    final word = _currentChallenge!.targetWord;
    
    switch (_currentWordCase) {
      case WordCase.allCaps:
        return word.toUpperCase();
      case WordCase.capitalized:
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      case WordCase.lowercase:
        return word.toLowerCase();
    }
  }

  Color _getBorderColor() {
    switch (_feedbackState) {
      case FeedbackState.correct:
        return Colors.green;
      case FeedbackState.incorrect:
        return SpaceTheme.rocketRed;
      case FeedbackState.none:
        return SpaceTheme.cosmicPink;
    }
  }

  Color _getWordBackgroundColor() {
    switch (_feedbackState) {
      case FeedbackState.correct:
        return Colors.green.shade700;
      case FeedbackState.incorrect:
        return SpaceTheme.rocketRed;
      case FeedbackState.none:
        return SpaceTheme.cosmicPink.withValues(alpha: 0.7);
    }
  }

  Widget _buildSubmitButton(S s) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.bottomRight,
        child: Semantics(
          label: s.grossschreibCheck,
          button: true,
          enabled: _feedbackState == FeedbackState.none,
          child: GestureDetector(
            onTap: _feedbackState == FeedbackState.none ? _submitChoice : null,
            child: AnimatedOpacity(
              opacity: _feedbackState == FeedbackState.none ? 1.0 : 0.5,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      SpaceTheme.alienGreen,
                      SpaceTheme.alienGreen.withValues(alpha: 0.7)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: SpaceTheme.alienGreen.withValues(alpha: 0.4),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 28, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      s.grossschreibCheck,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
