// lib/features/games/screens/word_type_whirl_game.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/models/skill_category.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/game_ui.dart';
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
  final double radius;
  final double speed;
  bool isTapped;
  bool isCorrect;
  bool shouldRemove;
  
  WhirlingWord({
    required this.word,
    required this.angle,
    required this.radius,
    required this.speed,
    this.isTapped = false,
    this.isCorrect = false,
    this.shouldRemove = false,
  });
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

class _WordTypeWhirlGameState extends State<WordTypeWhirlGame> with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
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

  Timer? _hintTimer;
  bool _showHints = false;
  static const _hintDelay = 7; // Show hints after 7 seconds of no correct taps
  int _secondsSinceLastCorrectTap = 0;
  
  // Round management
  Timer? _roundTimer;
  int _roundTimeRemaining = 15;
  List<RoundStats> _roundHistory = [];

  // Animation
  late AnimationController _whirlController;
  late AnimationController _pulseController;
  Timer? _spawnTimer;
  final Stopwatch _whirlStopwatch = Stopwatch();
  
  // Available word types based on grade
  late Map<GermanWordType, ({String label, IconData icon, Color color})> _wordTypes;
  
  // Word pool for current session
  List<GermanWord> _wordPool = [];
  int _wordPoolIndex = 0;

  @override
  void initState() {
    super.initState();
    
    _whirlController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // larger numbers make it easier
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
    
    // Basic word types for all grades
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
    
    // Add advanced types for higher grades
    if (widget.gradeLevel.index >= 2) { // Grade 3+
      _wordTypes[GermanWordType.adverb] = (
        label: 'Adverb',
        icon: Icons.speed,
        color: Colors.purple
      );
    }
    
    if (widget.gradeLevel.index >= 3) { // Grade 4+
      _wordTypes[GermanWordType.pronomen] = (
        label: 'Pronomen',
        icon: Icons.person,
        color: Colors.teal
      );
    }
  }

  @override
  void dispose() {
    _whirlController.dispose();
    _pulseController.dispose();
    _roundTimer?.cancel();
    _spawnTimer?.cancel();
    _hintTimer?.cancel();
    _whirlStopwatch.stop();
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

    _loadWordPool();
    _loadLevel();
  }

  String? _extractBaseWordFromSriId(String id) {
    if (id.startsWith('SPELL_')) return id.substring('SPELL_'.length);
    if (id.startsWith('WORDTYPE_')) return id.substring('WORDTYPE_'.length);
    return null;
  }

  bool _isWordValidForGame(GermanWord word) {
    return _wordTypes.containsKey(word.wordType) &&
        !word.word.contains(" ") &&
        word.word.length >= 3 &&
        word.word.length <= 10;
  }

  void _loadWordPool() {
    // --- ADAPTIVE WORD SELECTION ---
    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};

    // Get review words (50%)
    final reviewItemIds = _sriService.getItemsForReview(
      limit: 50,
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
        }
      } catch (e) {
        // Word from SRI not in vocab, skip
      }
    }

    // Get new words
    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: 50,
      settingsProvider: _gameProvider,
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
      }
    }

    // Fill with random words if needed
    if (wordsForGame.length < 60) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
      allWords.shuffle();

      for (final word in allWords) {
        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          wordsForGame.add(word);
          addedWordIds.add(word.id);
          if (wordsForGame.length >= 100) break;
        }
      }
    }
    // --- END ADAPTIVE SELECTION ---

    // CRITICAL FIX: Ensure we have words of all types
    final wordsByType = <GermanWordType, List<GermanWord>>{};
    for (final type in _wordTypes.keys) {
      wordsByType[type] = wordsForGame.where((w) => w.wordType == type).toList();
    }

    // If any type has too few words, add more
    for (final type in _wordTypes.keys) {
      if ((wordsByType[type]?.length ?? 0) < 10) {
        final allWords = _vocabularyService.getAllWords(_gameProvider);
        final moreWords = allWords.where((w) => 
          w.wordType == type && 
          _isWordValidForGame(w) && 
          !addedWordIds.contains(w.id)
        ).take(15).toList();
        
        wordsForGame.addAll(moreWords);
        addedWordIds.addAll(moreWords.map((w) => w.id));
      }
    }

    wordsForGame.shuffle();
    _wordPool = wordsForGame;
    _wordPoolIndex = 0;
    
    debugPrint('[WHIRL] Word pool loaded: ${_wordPool.length} total words');
    for (final type in _wordTypes.keys) {
      final count = _wordPool.where((w) => w.wordType == type).length;
      debugPrint('[WHIRL] ${type.toString().split('.').last}: $count words');
    }
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
    });

    _startRound();
  }

  void _startRound() {
    _isEndingRound = false;
    if (_round > _totalRounds) {
      _showGameOver();
      return;
    }

    // Pick random target word type
    final types = _wordTypes.keys.toList()..shuffle();
    
    GermanWordType? selectedType;
    for (final type in types) {
      if (_hasEnoughWordsOfType(type)) {
        selectedType = type;
        break;
      }
    }
    
    _currentTargetType = selectedType ?? types.first;

    // Set round time based on grade
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

    // CRITICAL FIX: Reset hint system BEFORE setState
    _showHints = false;
    _secondsSinceLastCorrectTap = 0;

    setState(() {
      _whirlingWords.clear();
      _roundHistory.add(RoundStats(targetType: _currentTargetType!));
    });

    _startRoundTimer();
    _startWordSpawning();
    
    _audioService.playSound('tap');
    
    debugPrint('[WHIRL] Round $_round started - Target: $_currentTargetType - Hints: $_showHints');
  }

  void _startRoundTimer() {
    _roundTimer?.cancel();
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_roundTimeRemaining > 0) {
        setState(() {
          _roundTimeRemaining--;
          
          // Track time since last correct tap for hints
          if (!_showHints) {
            _secondsSinceLastCorrectTap++;
            if (_secondsSinceLastCorrectTap >= _hintDelay) {
              _showHints = true;
            }
          }
        });
        
        // CRITICAL FIX: Check if all target words are tapped
        _checkRoundCompletion();
      } else {
        _endRound();
      }
    });
  }

  // Add this new method after _startRoundTimer
  void _checkRoundCompletion() {
    // Check if any target words remain
    final hasTargetWords = _whirlingWords.any((w) => 
      !w.isTapped && w.word.wordType == _currentTargetType
    );
    
    if (!hasTargetWords && _whirlingWords.isNotEmpty) {
      // All target words tapped! Auto-complete round
      debugPrint('[WHIRL] All target words tapped! Auto-completing round.');
      _endRound();
    }
  }

  void _startWordSpawning() {
    _spawnTimer?.cancel();
    
    // Spawn interval decreases with difficulty
    final spawnInterval = (1500 ~/ _baseSpeed).clamp(600, 2000);
    
    _spawnTimer = Timer.periodic(Duration(milliseconds: spawnInterval), (timer) {
      if (_roundTimeRemaining > 0 && _whirlingWords.length < 12) {
        _spawnWord();
      }
    });

    // --- FIX: Simplify initial spawn ---
    // Just call _spawnWord(), which already has all the
    // correct logic for radius, uniqueness, and target-rate.
    final random = Random();
    for (int i = 0; i < 6; i++) {
      Future.delayed(Duration(milliseconds: i * 250 + random.nextInt(100)), () {
        if (mounted) _spawnWord();
      });
    }
  }

  bool _hasEnoughWordsOfType(GermanWordType type) {
    final count = _wordPool.where((w) => w.wordType == type).length;
    return count >= 5; // Need at least 5 words of each type
  }

  // lib/features/games/screens/word_type_whirl_game.dart

  // ... (keep all code above this method)

  void _spawnWord() {
    if (_wordPoolIndex >= _wordPool.length) {
      _wordPool.shuffle();
      _wordPoolIndex = 0;
    }

    final random = Random();
    
    // --- Make check case/whitespace-insensitive ---
    final Set<String> onScreenWords = _whirlingWords.map((w) => w.word.word.trim().toLowerCase()).toSet();
    
    // Ensure 40% of words are the target type
    final shouldSpawnTarget = random.nextDouble() < 0.4;
    
    GermanWord? selectedWord;
    int searchStartIndex = _wordPoolIndex;
    int maxAttempts = _wordPool.length; // Max search iteration

    if (shouldSpawnTarget) {
      // --- Try to find a word of the target type NOT on screen ---
      for (int i = 0; i < maxAttempts; i++) {
        int currentIndex = (searchStartIndex + i) % _wordPool.length;
        final candidateWord = _wordPool[currentIndex];
        final cleanWord = candidateWord.word.trim().toLowerCase();

        if (candidateWord.wordType == _currentTargetType && 
            !onScreenWords.contains(cleanWord)) {
          selectedWord = candidateWord;
          _wordPoolIndex = currentIndex + 1; // Set index for next spawn
          break;
        }
      }
    }
    
    // If still no target word found, or we want a non-target word
    if (selectedWord == null) {
      // --- Try to find a non-target word NOT on screen ---
      for (int i = 0; i < maxAttempts; i++) {
        int currentIndex = (searchStartIndex + i) % _wordPool.length;
        final candidateWord = _wordPool[currentIndex];
        final cleanWord = candidateWord.word.trim().toLowerCase();

        if (candidateWord.wordType != _currentTargetType && 
            !onScreenWords.contains(cleanWord)) {
          selectedWord = candidateWord;
          _wordPoolIndex = currentIndex + 1;
          break;
        }
      }
    }
    
    // Fallback: If STILL no word, find the *first available* word of *any* type
    if (selectedWord == null) {
       // --- Fallback to ANY word NOT on screen ---
      for (int i = 0; i < maxAttempts; i++) {
        int currentIndex = (searchStartIndex + i) % _wordPool.length;
        final candidateWord = _wordPool[currentIndex];
        final cleanWord = candidateWord.word.trim().toLowerCase();

        if (!onScreenWords.contains(cleanWord)) {
          selectedWord = candidateWord;
          _wordPoolIndex = currentIndex + 1;
          break;
        }
      }
    }

    // If no unique word could be found at all
    if (selectedWord == null) {
      debugPrint("[WHIRL] Could not find a unique word to spawn. Skipping.");
      return;
    }
    
    // --- FIX for overlap: Create two distinct bands ---
    final double radius;
    final bool isInnerBand; // Need to know which band we're in
    if (random.nextBool()) {
      // Inner band
      radius = 110.0 + random.nextDouble() * 30.0; // Range: 110-140
      isInnerBand = true;
    } else {
      // Outer band
      radius = 190.0 + random.nextDouble() * 30.0; // Range: 190-220
      isInnerBand = false;
    }
    
    // --- NEW FIX: Check for angular collision in the *same band* ---
    double newAngle;
    int attempt = 0;
    bool collision;

    // A 100px-wide card at radius 110 (inner) subtends an angle of
    // 2 * asin( (100/2) / 110 ) approx 0.92 radians.
    // We'll use 1.0 rad (~57 deg) as a safe minimum separation.
    const minAngleSeparation = 1.0; 

    do {
      collision = false;
      newAngle = random.nextDouble() * 2 * pi;
      
      // Check against all existing words
      for (final existingWord in _whirlingWords) {
        // Are they in the same band? (use 150 as midpoint)
        final bool existingIsInner = existingWord.radius < 150; 
        
        if (isInnerBand == existingIsInner) {
          // Yes. Check their angle separation.
          double angleDiff = (newAngle - existingWord.angle).abs();
          if (angleDiff > pi) {
            angleDiff = 2 * pi - angleDiff; // Get shortest arc
          }
          
          if (angleDiff < minAngleSeparation) {
            collision = true;
            break; // Collision found, break inner loop to try new angle
          }
        }
      }
      attempt++;
    } while (collision && attempt < 40); // Try 40 times to find a free spot

    if (collision) {
      // Still colliding after 40 attempts, band is likely full.
      // Don't spawn the word.
      debugPrint("[WHIRL] Could not find a non-colliding spot. Skipping.");
      return;
    }
    
    final whirlingWord = WhirlingWord(
      word: selectedWord,
      angle: newAngle, // Use the collision-checked angle
      radius: radius, 
      speed: (0.5 + random.nextDouble() * 0.5) * _baseSpeed,
    );

    setState(() {
      _whirlingWords.add(whirlingWord);
    });
  }


  void _onWordTapped(WhirlingWord whirlingWord) {
    if (whirlingWord.isTapped) return;

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

    // Remove word after animation
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          whirlingWord.shouldRemove = true;
          _whirlingWords.remove(whirlingWord);
        });
      }
    });
  }

  void _onCorrectTap(WhirlingWord whirlingWord) {
    _audioService.playSound('success');
    _pulseController.forward(from: 0);

    // CRITICAL FIX: Reset hint system IMMEDIATELY
    _secondsSinceLastCorrectTap = 0;
    _showHints = false;

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
      metadata: {
        'game': 'word_type_whirl',
        'round': _round,
        'streak': _streak,
      },
    );
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _checkRoundCompletion();
    });
  }

  void _onIncorrectTap(WhirlingWord whirlingWord) {
    _audioService.playSound('failure');

    setState(() {
      _streak = 0;
      _score = max(0, _score - 5);
      _roundHistory.last.incorrectTaps++;
    });

    // Record failure in SRI
    _sriService.recordResponse(
      skillType: LanguageSkillType.wordType,
      baseWord: whirlingWord.word.word,
      wasCorrect: false,
      metadata: {
        'game': 'word_type_whirl',
        'round': _round,
      },
    );
  }

  void _endRound() {
    if (_isEndingRound) return; 
    _isEndingRound = true;
    _roundTimer?.cancel();
    _spawnTimer?.cancel();

    // CRITICAL FIX: Force reset hints before next round
    _showHints = false;
    _secondsSinceLastCorrectTap = 0;

    // Count missed target words
    final missedCount = _whirlingWords.where((w) => 
      !w.isTapped && w.word.wordType == _currentTargetType
    ).length;
    
    _roundHistory.last.missedWords = missedCount;

    // Brief pause before next round
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _round++;
        });
        _startRound();
      }
    });
  }

  void _showGameOver() {
    _roundTimer?.cancel();
    _spawnTimer?.cancel();
    
    final s = S.of(context)!;
    
    // Calculate performance
    final totalCorrect = _roundHistory.fold<int>(0, (sum, stats) => sum + stats.correctTaps);
    final totalIncorrect = _roundHistory.fold<int>(0, (sum, stats) => sum + stats.incorrectTaps);
    final totalMissed = _roundHistory.fold<int>(0, (sum, stats) => sum + stats.missedWords);
    final total = totalCorrect + totalIncorrect + totalMissed;
    final accuracy = total > 0 ? (totalCorrect / total * 100).round() : 0;
    
    int stars = 1;
    if (accuracy >= 85) stars = 3;
    else if (accuracy >= 70) stars = 2;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.emoji_events, color: SpaceTheme.starYellow, size: 32),
            const SizedBox(width: 12),
            Text(
              s.wordWhirlGameOver,
              style: SpaceTheme.titleStyle,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return Icon(
                  index < stars ? Icons.star : Icons.star_border,
                  color: SpaceTheme.starYellow,
                  size: 40,
                );
              }),
            ),
            const SizedBox(height: 20),
            Text(
              '${s.gameScore}: $_score',
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 18),
            ),
            Text(
              '${s.wordWhirlAccuracy}: $accuracy%',
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 16),
            ),
            Text(
              '${s.wordWhirlBestStreak}: $_maxStreak',
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 16,
                color: SpaceTheme.starYellow,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${s.wordWhirlCorrect}: $totalCorrect',
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 14,
                color: SpaceTheme.alienGreen,
              ),
            ),
            Text(
              '${s.wordWhirlIncorrect}: $totalIncorrect',
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 14,
                color: SpaceTheme.rocketRed,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _loadLevel();
            },
            child: Text(
              s.gameReplay,
              style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.alienGreen),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.planetOrange,
            ),
            child: Text(
              s.gameDone,
              style: SpaceTheme.bodyStyle.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final selectedFontFamily = context.watch<GameProvider>().selectedFontFamily;

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              GameUI(
                title: s.wordWhirlTitle,
                level: widget.gradeLevel.index + 1,
                onBack: () {
                  _roundTimer?.cancel();
                  _spawnTimer?.cancel();
                  Navigator.of(context).pop();
                },
              ),
              if (_isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      // Stats bar
                      _buildStatsBar(s),
                      
                      // Target instruction
                      _buildTargetBanner(s, selectedFontFamily),
                      
                      // Whirl area
                      Expanded(
                        child: _buildWhirlArea(selectedFontFamily),
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

  Widget _buildStatsBar(S s) {
    final timeColor = _roundTimeRemaining < 5 
        ? SpaceTheme.rocketRed 
        : (_roundTimeRemaining < 10 ? SpaceTheme.planetOrange : SpaceTheme.alienGreen);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(s.gameScore, _score.toString(), Icons.stars, SpaceTheme.starYellow),
          _buildStatItem(s.wordWhirlRound, '$_round/$_totalRounds', Icons.replay, SpaceTheme.cosmicPink),
          _buildStatItem(s.wordWhirlStreak, _streak.toString(), Icons.local_fire_department, 
            _streak > 5 ? SpaceTheme.starYellow : Colors.orange),
          _buildStatItem(s.wordBuilderTime, '${_roundTimeRemaining}s', Icons.timer, timeColor),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildTargetBanner(S s, String selectedFontFamily) {
    if (_currentTargetType == null) return const SizedBox.shrink();
    
    final typeInfo = _wordTypes[_currentTargetType!]!;
    
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.1);
        
        return Transform.scale(
          scale: scale,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  typeInfo.color.withOpacity(0.3),
                  typeInfo.color.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: typeInfo.color, width: 3),
              boxShadow: [
                BoxShadow(
                  color: typeInfo.color.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(typeInfo.icon, color: typeInfo.color, size: 32),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        s.wordWhirlTapAll(typeInfo.label),
                        style: SpaceTheme.titleStyle.copyWith(
                          fontFamily: selectedFontFamily,
                          fontSize: 20,
                          color: typeInfo.color,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                // CRITICAL FIX: Show hint indicator
                if (_showHints)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lightbulb, color: SpaceTheme.starYellow, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Hinweise aktiv!',
                          style: SpaceTheme.bodyStyle.copyWith(
                            fontSize: 12,
                            color: SpaceTheme.starYellow,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWhirlArea(String selectedFontFamily) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight / 2;
        
        return AnimatedBuilder(
          animation: _whirlController,
          builder: (context, child) {
            
            // --- FIX for jumpy animation ---
            // Use total elapsed time for a continuous, non-jumping rotation
            final double elapsedSeconds = _whirlStopwatch.elapsedMilliseconds / 1000.0;
            // Base speed: one full rotation (2*pi) every 8 seconds
            final double baseRadsPerSec = pi / 4; 

            return Stack(
              children: [
                // Center vortex decoration
                Positioned(
                  left: centerX - 30,
                  top: centerY - 30,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          SpaceTheme.cosmicPink.withOpacity(0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.tornado,
                        color: SpaceTheme.cosmicPink.withOpacity(0.5),
                        size: 32,
                      ),
                    ),
                  ),
                ),
                
                // Whirling words
                ..._whirlingWords.map((whirlingWord) {
                  
                  // --- FIX for jumpy animation ---
                  // The angle is now based on the elapsed time and the word's speed
                  final currentAngle = whirlingWord.angle + 
                    (elapsedSeconds * baseRadsPerSec * whirlingWord.speed);
                  
                  final x = centerX + cos(currentAngle) * whirlingWord.radius;
                  final y = centerY + sin(currentAngle) * whirlingWord.radius;
                  
                  return Positioned(
                    // --- THIS IS THE FIX ---
                    // Give each word a unique key based on its text.
                    // This stops Flutter from reusing the wrong widget state.
                    key: ValueKey<String>(whirlingWord.word.word),
                    // --- END OF FIX ---
                    
                    left: x - 50,
                    top: y - 25,
                    child: _buildWhirlingWordWidget(
                      whirlingWord,
                      selectedFontFamily,
                      currentAngle,
                    ),
                  );
                }).toList(),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWhirlingWordWidget(
    WhirlingWord whirlingWord,
    String selectedFontFamily,
    double currentAngle,
  ) {
    final typeInfo = _wordTypes[whirlingWord.word.wordType];
    final isTarget = whirlingWord.word.wordType == _currentTargetType;
    
    // Apply hint highlighting
    // This variable is key: it's only true if it's a target, hints are on, and it's not tapped
    final shouldHighlight = isTarget && _showHints && !whirlingWord.isTapped;
    
    Color backgroundColor;
    Color borderColor;
    Color textColor = Colors.white;
    
    if (whirlingWord.isTapped) {
      if (whirlingWord.isCorrect) {
        backgroundColor = SpaceTheme.alienGreen.withOpacity(0.9);
        borderColor = SpaceTheme.alienGreen;
        textColor = SpaceTheme.deepSpace;
      } else {
        backgroundColor = SpaceTheme.rocketRed.withOpacity(0.9);
        borderColor = SpaceTheme.rocketRed;
      }
    } else if (shouldHighlight) {
      // --- FIX #1 ---
      // ONLY apply hint styling if shouldHighlight is true
      backgroundColor = SpaceTheme.deepSpace.withOpacity(0.9);
      borderColor = typeInfo?.color ?? SpaceTheme.starYellow;
      textColor = Colors.white;
    } else {
      // --- FIX #2 ---
      // This is the new default state for all un-tapped cards
      // (either non-target, or target with hints OFF)
      backgroundColor = SpaceTheme.deepSpace.withOpacity(0.7);
      borderColor = Colors.white.withOpacity(0.3); // Neutral border
      textColor = Colors.white;
    }

    return GestureDetector(
      onTap: () => _onWordTapped(whirlingWord),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100,
        height: 50,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            // --- FIX #3 ---
            // Width is 5 if highlighted, otherwise a standard 2
            width: shouldHighlight ? 5 : 2, 
          ),
          boxShadow: [
            // --- FIX #4 ---
            // ONLY show the glow effect if shouldHighlight is true
            if (shouldHighlight)
              BoxShadow(
                color: borderColor.withOpacity(0.9), 
                blurRadius: 20,
                spreadRadius: 5,
              ),
          ],
        ),
        child: Stack(
          children: [
            // This pulsing indicator is already correct
            if (shouldHighlight)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: RadialGradient(
                      colors: [
                        typeInfo!.color.withOpacity(0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    whirlingWord.word.word,
                    style: TextStyle(
                      fontFamily: selectedFontFamily,
                      fontSize: 16,
                      // These style changes are also correct as they depend on shouldHighlight
                      fontWeight: shouldHighlight ? FontWeight.w900 : FontWeight.bold,
                      color: textColor,
                      shadows: [
                        Shadow(
                          blurRadius: shouldHighlight ? 4 : 2,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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