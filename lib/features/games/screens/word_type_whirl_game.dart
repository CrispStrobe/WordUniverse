// lib/features/games/screens/word_type_whirl_game.dart
import 'dart:async';
import 'dart:math';
import 'dart:collection'; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart' as vocab_service;

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/space_background.dart';

class WordTypeWhirlGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WordTypeWhirlGame({super.key, required this.gradeLevel});

  @override
  State<WordTypeWhirlGame> createState() => _WordTypeWhirlGameState();
}

class WhirlingWord {
  final GermanWord word;
  final double angle;
  final int trackIndex; // <--- NEW: 0, 1, or 2
  final double speed;   // All words in the same track share this speed
  bool isTapped;
  bool isCorrect;
  bool shouldRemove;

  WhirlingWord({
    required this.word,
    required this.angle,
    required this.trackIndex, // <--- Update Constructor
    required this.speed,
    this.isTapped = false,
    this.isCorrect = false,
    this.shouldRemove = false,
  });
  
  // Helper to calculate radius based on track index
  double get radius {
    switch (trackIndex) {
      case 0: return 0.30; // Inner
      case 1: return 0.58; // Middle
      case 2: return 0.85; // Outer
      default: return 0.6;
    }
  }
}

class RoundStats {
  final GermanWordType targetType;
  int correctTaps;
  int incorrectTaps;
  int missedWords;

  RoundStats({
    required this.targetType,
    this.correctTaps = 0,
    this.incorrectTaps = 0,
    this.missedWords = 0,
  });
}

class HintMessage {
  final String text;
  final bool isError;
  final String id;

  HintMessage({required this.text, required this.isError})
      : id = UniqueKey().toString();
}

class _WordTypeWhirlGameState extends State<WordTypeWhirlGame>
    with TickerProviderStateMixin {
  
  late vocab_service.VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  bool _isLoading = true;
  List<WhirlingWord> _whirlingWords = [];
  GermanWordType? _currentTargetType;
  int _score = 0;
  int _streak = 0;
  int _maxStreak = 0;
  int _round = 1;
  int _totalRounds = 8;
  double _baseSpeed = 1.0;
  bool _isEndingRound = false;

  // Instruction Banner State
  bool _showFullInstructions = false;
  Timer? _instructionTimer;

  // Hints
  Timer? _autoHintTimer;
  bool _showAutoHints = false;
  static const _autoHintDelay = 7;
  int _secondsSinceLastCorrectTap = 0;

  // Round management
  Timer? _roundTimer;
  int _roundTimeRemaining = 15;
  List<RoundStats> _roundHistory = [];

  late AnimationController _whirlController;
  late AnimationController _pulseController;
  Timer? _spawnTimer;
  final Stopwatch _whirlStopwatch = Stopwatch();

  Size _whirlAreaSize = Size.zero;

  final Queue<HintMessage> _hintQueue = Queue<HintMessage>();
  HintMessage? _currentHintMessage;
  Timer? _hintDisplayTimer;
  final GlobalKey<AnimatedListState> _hintListKey = GlobalKey<AnimatedListState>();
  final List<HintMessage> _visibleHints = [];

  late Map<GermanWordType, ({String label, IconData icon, Color color})> _wordTypes;
  List<GermanWord> _wordPool = [];
  int _wordPoolIndex = 0;

  @override
  void initState() {
    super.initState();

    _whirlController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _whirlStopwatch.start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = S.of(context)!;

    _wordTypes = {
      GermanWordType.substantiv: (
        label: s.wordSortCategoryNoun,
        icon: Icons.home,
        color: SpaceTheme.planetOrange
      ),
      GermanWordType.verb: (
        label: s.wordSortCategoryVerb,
        icon: Icons.directions_run,
        color: SpaceTheme.alienGreen
      ),
      GermanWordType.adjektiv: (
        label: s.wordSortCategoryAdjective,
        icon: Icons.palette,
        color: SpaceTheme.cosmicPink
      ),
    };

    if (widget.gradeLevel.index >= 2) {
      _wordTypes[GermanWordType.adverb] =
          (label: 'Adverb', icon: Icons.speed, color: Colors.purple);
    }

    if (widget.gradeLevel.index >= 3) {
      _wordTypes[GermanWordType.pronomen] =
          (label: 'Pronomen', icon: Icons.person, color: Colors.teal);
    }
  }

  @override
  void dispose() {
    _whirlController.dispose();
    _pulseController.dispose();
    _roundTimer?.cancel();
    _spawnTimer?.cancel();
    _autoHintTimer?.cancel();
    _hintDisplayTimer?.cancel();
    _instructionTimer?.cancel();
    _whirlStopwatch.stop();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    setState(() => _isLoading = true);

    _vocabularyService = context.read<vocab_service.VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();

    if (!_vocabularyService.isInitialized) {
      await _vocabularyService.initialize();
    }

    _loadWordPool();
    _loadLevel();
  }

  String? _extractBaseWordFromSriId(String id) {
    if (id.startsWith('SPELL_')) return id.substring('SPELL_'.length);
    if (id.startsWith('WORDTYPE_')) return id.substring('WORDTYPE_'.length);
    if (id.startsWith('ARTICLE_')) return id.substring('ARTICLE_'.length);
    return null;
  }

  bool _isWordValidForGame(GermanWord word, {bool requireApiData = false}) {
    final bool hasValidType = _wordTypes.containsKey(word.wordType);
    final bool isCleanWord = !word.word.contains(" ") &&
        word.word.length >= 3 &&
        word.word.length <= 10;

    if (requireApiData) {
      return hasValidType &&
          isCleanWord &&
          word.apiEnrichment?.enrichmentStatus == 'success';
    }
    return hasValidType && isCleanWord;
  }

  void _loadWordPool() {
    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};
    
    final reviewItemIds = _sriService.getItemsForReview(
      limit: 50,
      skillTypeFilter: LanguageSkillType.wordType,
      gradeLevelFilter: widget.gradeLevel.index + 1,
    );

    for (final id in reviewItemIds) {
      String? wordString = _extractBaseWordFromSriId(id);
      if (wordString == null) continue;
      if (wordString.startsWith('der ') || wordString.startsWith('die ') || wordString.startsWith('das ')) {
        wordString = wordString.split(' ')[1];
      }
      try {
        final word = _vocabularyService
            .getAllWords(_gameProvider)
            .firstWhere((w) => w.word.toLowerCase() == wordString!.toLowerCase());

        if (!addedWordIds.contains(word.id) && _isWordValidForGame(word)) {
           wordsForGame.add(word);
           addedWordIds.add(word.id);
        }
      } catch (e) {}
    }

    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: 100,
      settingsProvider: _gameProvider,
    );

    for (final word in newWords) {
      if (!addedWordIds.contains(word.id) && _isWordValidForGame(word)) {
         wordsForGame.add(word);
         addedWordIds.add(word.id);
      }
    }

    if (wordsForGame.length < 60) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
      allWords.shuffle();
      for(final w in allWords) {
         if(_isWordValidForGame(w) && !addedWordIds.contains(w.id)) {
            wordsForGame.add(w);
            addedWordIds.add(w.id);
            if(wordsForGame.length >= 100) break;
         }
      }
    }
    
    // Ensure minimum distribution
    final allWordsFromService = _vocabularyService.getFullVocabularyList();
    allWordsFromService.shuffle();

    for (final type in _wordTypes.keys) {
      final currentCount = wordsForGame.where((w) => w.wordType == type).length;
      final needed = 15 - currentCount; 

      if (needed > 0) {
        final moreWords = allWordsFromService
            .where((w) => w.wordType == type && _isWordValidForGame(w) && !addedWordIds.contains(w.id))
            .take(needed)
            .toList();
        
        if (moreWords.isNotEmpty) {
          wordsForGame.addAll(moreWords);
          addedWordIds.addAll(moreWords.map((w) => w.id));
        }
      }
    }

    wordsForGame.shuffle();
    _wordPool = wordsForGame;
    _wordPoolIndex = 0;
  }

  void _loadLevel() {
    setState(() {
      _score = 0;
      _streak = 0;
      _maxStreak = 0;
      _round = 1;
      _baseSpeed = 1.0;
      _roundHistory.clear();
      _isLoading = false;
      _hintQueue.clear();
      _visibleHints.clear();
      _currentHintMessage = null;
    });

    _startRound();
  }

  void _startRound() {
    _isEndingRound = false;
    if (_round > _totalRounds) {
      _showGameOver();
      return;
    }

    final validTypes = _wordTypes.keys
        .where((type) => _wordPool.where((w) => w.wordType == type).length >= 5)
        .toList();

    if (validTypes.isEmpty) {
       return;
    }

    validTypes.shuffle();
    _currentTargetType = validTypes.first;

    // Show instructions temporarily
    setState(() {
       _showFullInstructions = true;
    });
    _instructionTimer?.cancel();
    // Reduced duration slightly so it clears faster
    _instructionTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showFullInstructions = false);
      }
    });

    switch (widget.gradeLevel) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        _roundTimeRemaining = 20;
        break;
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        _roundTimeRemaining = 15;
        break;
      default:
        _roundTimeRemaining = 12;
    }

    _baseSpeed = 1.0 + (_round - 1) * 0.08;

    _showAutoHints = false;
    _secondsSinceLastCorrectTap = 0;
    _hintQueue.clear();
    _hintDisplayTimer?.cancel();
    _currentHintMessage = null;

    for (int i = _visibleHints.length - 1; i >= 0; i--) {
      _hintListKey.currentState?.removeItem(
        0,
        (context, animation) => const SizedBox.shrink(),
      );
    }
    _visibleHints.clear();

    setState(() {
      _whirlingWords.clear();
      _roundHistory.add(RoundStats(targetType: _currentTargetType!));
    });

    _startRoundTimer();
    _startWordSpawning(); 

    _audioService.playSound('tap');
  }

  void _startRoundTimer() {
    _roundTimer?.cancel();
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_roundTimeRemaining > 0) {
        setState(() {
          _roundTimeRemaining--;
          if (!_showAutoHints) {
            _secondsSinceLastCorrectTap++;
            if (_secondsSinceLastCorrectTap >= _autoHintDelay) {
              _showAutoHints = true;
            }
          }
        });
      } else {
        _endRound();
      }
    });
  }

  void _checkRoundCompletion() {
    final hasTargetWords = _whirlingWords
        .any((w) => !w.isTapped && w.word.wordType == _currentTargetType);

    if (!hasTargetWords && _whirlingWords.isNotEmpty) {
      _endRound();
    }
  }

  void _startWordSpawning() {
    _spawnTimer?.cancel();
    final spawnInterval = (1500 ~/ _baseSpeed).clamp(600, 2000);

    _spawnTimer = Timer.periodic(Duration(milliseconds: spawnInterval), (timer) {
      if (_roundTimeRemaining > 0 && _whirlingWords.length < 12) {
        _spawnWord();
      }
    });

    final random = Random();
    _spawnWord(forceTarget: true);
    _spawnWord(forceTarget: true);
    
    for (int i = 0; i < 4; i++) {
      Future.delayed(Duration(milliseconds: i * 250 + random.nextInt(100)), () {
        if (mounted) _spawnWord();
      });
    }
  }

  void _spawnWord({bool forceTarget = false}) {
    // 1. Shuffle pool if needed
    if (_wordPoolIndex >= _wordPool.length) {
      _wordPool.shuffle();
      _wordPoolIndex = 0;
    }

    // 2. Safety check for screen size
    final maxRadius = min(_whirlAreaSize.width, _whirlAreaSize.height) / 2.0;
    if (maxRadius <= 50) return;

    final random = Random();
    final Set<String> onScreenWords =
        Set<String>.from(_whirlingWords.map((w) => w.word.word.trim().toLowerCase()));

    // 3. Determine if we need a target word
    bool shouldSpawnTarget;
    if (forceTarget) {
      shouldSpawnTarget = true;
    } else {
      final unTappedTargetCount = _whirlingWords
          .where((w) => !w.isTapped && w.word.wordType == _currentTargetType)
          .length;
      // Keep at least 2 targets on screen, otherwise 40% chance
      shouldSpawnTarget = unTappedTargetCount < 2 ? true : random.nextDouble() < 0.4;
    }

    // 4. Select the Word
    GermanWord? selectedWord;
    int searchStartIndex = _wordPoolIndex;
    int maxAttempts = _wordPool.length;

    // Helper to find word
    GermanWord? findWord(bool mustBeTarget, bool mustNotBeTarget) {
      for (int i = 0; i < maxAttempts; i++) {
        int currentIndex = (searchStartIndex + i) % _wordPool.length;
        final candidate = _wordPool[currentIndex];
        final clean = candidate.word.trim().toLowerCase();
        
        if (onScreenWords.contains(clean)) continue;
        
        if (mustBeTarget && candidate.wordType != _currentTargetType) continue;
        if (mustNotBeTarget && candidate.wordType == _currentTargetType) continue;

        _wordPoolIndex = currentIndex + 1;
        return candidate;
      }
      return null;
    }

    if (shouldSpawnTarget) {
      selectedWord = findWord(true, false);
    }
    // If no target found (or not looking for one), try non-target
    if (selectedWord == null && !forceTarget) {
      selectedWord = findWord(false, true);
    }
    // Fallback: any unique word
    selectedWord ??= findWord(false, false);

    if (selectedWord == null) return;

    // 5. FIND A TRACK AND SLOT
    // We have 3 tracks. We shuffle them to spawn randomly.
    // Track 0 (Inner), Track 1 (Middle), Track 2 (Outer)
    List<int> tracks = [0, 1, 2]..shuffle();
    
    int? chosenTrack;
    double? chosenAngle;
    
    // Define fixed speeds per track to ensure words NEVER catch up to each other
    // Inner is slowest angularly (but visually fine), Outer is fastest angularly
    // You can tweak these multipliers.
    final List<double> trackSpeeds = [0.8, 0.6, 0.4]; 

    for (int track in tracks) {
      // Calculate how much angle a card takes up in this track
      // Circumference = 2 * pi * r
      // r in pixels = trackRadius * maxRadius
      // Card width approx 120px.
      // Angle needed = (CardWidth / Circumference) * 2pi * Buffer
      double trackR = 0.0;
      if (track == 0) trackR = 0.30;
      else if (track == 1) trackR = 0.58;
      else trackR = 0.85;

      final pixelRadius = trackR * maxRadius;
      // Arc length formula: s = r * theta  => theta = s / r
      // We add a buffer (1.3x card width)
      final double requiredAngle = (120.0 / pixelRadius) * 1.3; 

      // Try 10 random angles in this track
      for (int i = 0; i < 10; i++) {
        double testAngle = random.nextDouble() * 2 * pi;
        bool fits = true;

        for (var existing in _whirlingWords) {
          if (existing.trackIndex == track) {
            double diff = (testAngle - existing.angle).abs();
            if (diff > pi) diff = 2 * pi - diff;
            
            if (diff < requiredAngle) {
              fits = false;
              break;
            }
          }
        }

        if (fits) {
          chosenTrack = track;
          chosenAngle = testAngle;
          break;
        }
      }
      if (chosenTrack != null) break;
    }

    if (chosenTrack == null || chosenAngle == null) return; // Screen is full

    setState(() {
      _whirlingWords.add(WhirlingWord(
        word: selectedWord!,
        angle: chosenAngle!,
        trackIndex: chosenTrack!,
        // IMPORTANT: All words in this track move at same speed relative to base speed
        speed: trackSpeeds[chosenTrack] * _baseSpeed, 
      ));
    });
  }

  void _onWordTapped(WhirlingWord whirlingWord) {
    if (whirlingWord.isTapped || _isEndingRound) return;

    final isCorrect = whirlingWord.word.wordType == _currentTargetType;

    setState(() {
      whirlingWord.isTapped = true;
      whirlingWord.isCorrect = isCorrect;
    });

    if (isCorrect) {
      _onCorrectTap(whirlingWord);
    } else {
      _onIncorrectTap(whirlingWord);
    }

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          whirlingWord.shouldRemove = true;
          _whirlingWords.remove(whirlingWord);
        });
      }
    });
  }

  void _showHint(String message, bool isError) {
    final newHint = HintMessage(text: message, isError: isError);
    _hintQueue.add(newHint);
    if (_currentHintMessage == null) {
      _processHintQueue();
    }
  }

  void _processHintQueue() {
    if (_currentHintMessage != null || _hintQueue.isEmpty) return;

    _hintDisplayTimer?.cancel();
    _currentHintMessage = _hintQueue.removeFirst();

    _visibleHints.insert(0, _currentHintMessage!);
    _hintListKey.currentState
        ?.insertItem(0, duration: const Duration(milliseconds: 400));

    _hintDisplayTimer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      if (_visibleHints.isNotEmpty) {
        final removedHint = _visibleHints.removeAt(0);
        _hintListKey.currentState?.removeItem(
            0,
            (context, animation) =>
                _buildHintToast(removedHint, animation, isRemoving: true),
            duration: const Duration(milliseconds: 300));
      }
      _currentHintMessage = null;
      _processHintQueue();
    });
  }

  String _generateSimpleHint(GermanWord word, bool isCorrect) {
    final displayWord = _getDisplayWord(word);
    if (isCorrect) return "✓ Richtig! $displayWord";
    return "✗ Falsch! $displayWord ist kein ${_wordTypes[_currentTargetType]?.label}";
  }

  void _onCorrectTap(WhirlingWord whirlingWord) {
    _audioService.playSound('success');
    _pulseController.forward(from: 0);
    _secondsSinceLastCorrectTap = 0;
    _showAutoHints = false;

    _showHint(_generateSimpleHint(whirlingWord.word, true), false);

    setState(() {
      _streak++;
      if (_streak > _maxStreak) _maxStreak = _streak;
      final multiplier = min(1 + (_streak ~/ 3) * 0.5, 3.0);
      _score += (10 * multiplier).round();
      _roundHistory.last.correctTaps++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.wordType,
      baseWord: whirlingWord.word.word,
      wasCorrect: true,
      metadata: {'game': 'word_type_whirl', 'wordType': whirlingWord.word.wordType.toString()},
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _checkRoundCompletion();
    });
  }

  void _onIncorrectTap(WhirlingWord whirlingWord) {
    _audioService.playSound('failure');
    _showHint(_generateSimpleHint(whirlingWord.word, false), true);

    setState(() {
      _streak = 0;
      _score = max(0, _score - 5);
      _roundHistory.last.incorrectTaps++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.wordType,
      baseWord: whirlingWord.word.word,
      wasCorrect: false,
      metadata: {'game': 'word_type_whirl', 'wordType': whirlingWord.word.wordType.toString()},
    );
  }

  void _endRound() {
    if (_isEndingRound) return;
    _isEndingRound = true;
    _roundTimer?.cancel();
    _spawnTimer?.cancel();

    _showAutoHints = false;
    _secondsSinceLastCorrectTap = 0;

    final missedCount = _whirlingWords
        .where((w) => !w.isTapped && w.word.wordType == _currentTargetType)
        .length;

    if (mounted) {
      _roundHistory.last.missedWords = missedCount;
    }

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() => _round++);
        _startRound();
      }
    });
  }

  void _showGameOver() {
    _roundTimer?.cancel();
    _spawnTimer?.cancel();

    final totalMissed =
        _roundHistory.fold<int>(0, (sum, r) => sum + r.missedWords);
    final wasSuccessful = _score > 0 && totalMissed <= _totalRounds;

    _gameProvider.recordLevelWin(
      gameType: 'word_type_whirl_game',
      scoreGained: _score,
      difficulty: widget.gradeLevel.index + 1,
      wasSuccessful: wasSuccessful,
    );

    if (!mounted) return;
    final s = S.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              wasSuccessful ? Icons.emoji_events : Icons.timer_off,
              color: SpaceTheme.starYellow,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(s.gameOver, style: SpaceTheme.headlineStyle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${s.gameScore}: $_score',
                style: SpaceTheme.bodyStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 8),
            Text('Streak: $_maxStreak',
                style: SpaceTheme.bodyStyle.copyWith(fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: Text(s.backToMenu,
                style: const TextStyle(color: SpaceTheme.starYellow)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedFontFamily = context.watch<GameProvider>().selectedFontFamily;

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Stack(
            children: [
              // MAIN LAYOUT
              Column(
                children: [
                  _buildTopBar(),
                  if (_isLoading)
                    const Expanded(child: Center(child: CircularProgressIndicator()))
                  else
                    Expanded(
                      child: _buildWhirlArea(selectedFontFamily),
                    ),
                ],
              ),

              // A. Persistent Target Indicator (Left aligned)
              // Only show when NOT showing full instructions
              if (_currentTargetType != null && !_isLoading && !_isEndingRound && !_showFullInstructions)
                 _buildPersistentTargetIndicator(),
              
              // B. Large Temporary Instructions (Bottom floating)
              if (_showFullInstructions && _currentTargetType != null)
                 _buildFullInstructionsOverlay(),

              // C. Hints (Bottom)
              _buildHintOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final totalGems = context.watch<GameProvider>().score;
    final timeColor = _roundTimeRemaining < 5 ? SpaceTheme.rocketRed : SpaceTheme.alienGreen;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5), width: 2)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () {
               _roundTimer?.cancel();
               _spawnTimer?.cancel();
               Navigator.of(context).pop();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          
          _buildMiniBadge(Icons.emoji_events_rounded, '${widget.gradeLevel.index + 1}', SpaceTheme.starYellow),
          
          const Spacer(),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatCompact(Icons.star_rounded, '$_score', SpaceTheme.starYellow),
                _buildVerticalDivider(),
                _buildStatCompact(Icons.replay_rounded, '$_round/$_totalRounds', SpaceTheme.cosmicPink),
                _buildVerticalDivider(),
                _buildStatCompact(Icons.local_fire_department_rounded, '$_streak', Colors.orange),
                _buildVerticalDivider(),
                _buildStatCompact(Icons.timer_rounded, '${_roundTimeRemaining}s', timeColor),
              ],
            ),
          ),

          const Spacer(),

          _buildMiniBadge(Icons.diamond_rounded, '$totalGems', Colors.cyanAccent),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildStatCompact(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 16,
      width: 1,
      color: Colors.white24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  // --- UPDATED: Persistent Indicator (Left aligned, below header) ---
  Widget _buildPersistentTargetIndicator() {
    final typeInfo = _wordTypes[_currentTargetType!]!;
    
    return Positioned(
      top: 70, // Sits below the top bar
      left: 16, // Aligned to left
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: typeInfo.color, width: 2),
          boxShadow: [BoxShadow(color: typeInfo.color.withValues(alpha: 0.3), blurRadius: 10)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(typeInfo.icon, color: typeInfo.color, size: 20),
            const SizedBox(width: 8),
            Text(
              typeInfo.label,
              style: TextStyle(color: typeInfo.color, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  // --- UPDATED: Instructions Overlay (Bottom Floating, Non-Blocking) ---
  Widget _buildFullInstructionsOverlay() {
    final s = S.of(context)!;
    final typeInfo = _wordTypes[_currentTargetType!]!;

    return Positioned(
      bottom: 100, // Floats above hints
      left: 20,
      right: 20,
      child: IgnorePointer( // Allows gameplay clicks through the instruction
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 500),
          opacity: _showFullInstructions ? 1.0 : 0.0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                // Clean semi-transparent dark background
                color: SpaceTheme.deepSpace.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: typeInfo.color, width: 2),
                boxShadow: [BoxShadow(color: typeInfo.color.withValues(alpha: 0.3), blurRadius: 20)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(typeInfo.icon, size: 32, color: typeInfo.color),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      s.wordWhirlTapAll(typeInfo.label),
                      textAlign: TextAlign.center,
                      style: SpaceTheme.headlineStyle.copyWith(fontSize: 20, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHintOverlay() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        child: AnimatedList(
          key: _hintListKey,
          initialItemCount: _visibleHints.length,
          itemBuilder: (context, index, animation) {
            return _buildHintToast(_visibleHints[index], animation);
          },
          shrinkWrap: true,
          reverse: true,
        ),
      ),
    );
  }

  Widget _buildHintToast(HintMessage hint, Animation<double> animation,
      {bool isRemoving = false}) {
    final color = hint.isError ? SpaceTheme.rocketRed : SpaceTheme.alienGreen;
    final icon = hint.isError ? Icons.cancel_outlined : Icons.check_circle_outline;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.5), end: const Offset(0, 0))
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: isRemoving ? Curves.easeOut : Curves.easeIn),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: SpaceTheme.deepSpace.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color, width: 2),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: Text(hint.text, style: const TextStyle(fontSize: 14, color: Colors.white))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWhirlArea(String selectedFontFamily) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.biggest != _whirlAreaSize) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _whirlAreaSize = constraints.biggest);
          });
        }

        final centerX = _whirlAreaSize.width / 2;
        final centerY = _whirlAreaSize.height / 2;
        final maxRadius = min(_whirlAreaSize.width, _whirlAreaSize.height) / 2.0;
        if (maxRadius <= 0) return const SizedBox.shrink();

        return AnimatedBuilder(
          animation: _whirlController,
          builder: (context, child) {
            final double elapsedSeconds = _whirlStopwatch.elapsedMilliseconds / 1000.0;
            final double baseRadsPerSec = pi / 4;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // ... (Center Icon code remains the same) ...
                Positioned(
                  left: centerX - 30,
                  top: centerY - 30,
                  child: Opacity(
                    opacity: 0.3,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [SpaceTheme.cosmicPink, Colors.transparent]),
                      ),
                      child: const Icon(Icons.tornado, color: SpaceTheme.cosmicPink, size: 32),
                    ),
                  ),
                ),

                ..._whirlingWords.map((whirlingWord) {
                  // Calculate current angle
                  // Note: words in same track have same speed, so relative distance never changes!
                  final currentAngle = whirlingWord.angle + (elapsedSeconds * baseRadsPerSec * whirlingWord.speed);
                  
                  // Use the track-defined radius
                  final x = centerX + cos(currentAngle) * (whirlingWord.radius * maxRadius);
                  final y = centerY + sin(currentAngle) * (whirlingWord.radius * maxRadius);
                  
                  final cardWidth = (maxRadius * 0.4).clamp(90.0, 130.0);
                  // Reduce height slightly to ensure vertical clearance between tracks
                  final cardHeight = (cardWidth * 0.4).clamp(40.0, 55.0);

                  return Positioned(
                    key: ValueKey<String>(whirlingWord.word.id),
                    left: x - (cardWidth / 2),
                    top: y - (cardHeight / 2),
                    child: _buildWhirlingWordWidget(whirlingWord, selectedFontFamily, currentAngle, cardWidth, cardHeight),
                  );
                }).toList(),
              ],
            );
          },
        );
      },
    );
  }

  String _getDisplayWord(GermanWord word) {
    if (word.wordType == GermanWordType.substantiv) {
      final text = word.displayName;
      if (text.startsWith('der ') || 
          text.startsWith('die ') || 
          text.startsWith('das ')) {
        return text.split(' ')[1];
      }
    }
    return word.displayName;
  }

  Widget _buildWhirlingWordWidget(
    WhirlingWord whirlingWord,
    String selectedFontFamily,
    double currentAngle,
    double cardWidth,
    double cardHeight,
  ) {
    final typeInfo = _wordTypes[whirlingWord.word.wordType];
    final isTarget = whirlingWord.word.wordType == _currentTargetType;
    final shouldHighlight = isTarget && _showAutoHints && !whirlingWord.isTapped;

    Color backgroundColor = SpaceTheme.deepSpace.withValues(alpha: 0.7);
    Color borderColor = Colors.white.withValues(alpha: 0.3);
    Color textColor = Colors.white;

    if (whirlingWord.isTapped) {
      if (whirlingWord.isCorrect) {
        backgroundColor = SpaceTheme.alienGreen.withValues(alpha: 0.9);
        borderColor = SpaceTheme.alienGreen;
        textColor = SpaceTheme.deepSpace;
      } else {
        backgroundColor = SpaceTheme.rocketRed.withValues(alpha: 0.9);
        borderColor = SpaceTheme.rocketRed;
      }
    } else if (shouldHighlight) {
      backgroundColor = SpaceTheme.deepSpace.withValues(alpha: 0.9);
      borderColor = typeInfo?.color ?? SpaceTheme.starYellow;
    }

    return GestureDetector(
      onTap: () => _onWordTapped(whirlingWord),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: shouldHighlight ? 4 : 2),
          boxShadow: [if (shouldHighlight) BoxShadow(color: borderColor.withValues(alpha: 0.7), blurRadius: 12)],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                _getDisplayWord(whirlingWord.word),
                style: TextStyle(
                  fontFamily: selectedFontFamily,
                  fontSize: 16,
                  fontWeight: shouldHighlight ? FontWeight.w900 : FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}