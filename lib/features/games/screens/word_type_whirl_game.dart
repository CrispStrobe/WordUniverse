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
  double _baseSpeed = 0.5;
  
  // Round management
  Timer? _roundTimer;
  int _roundTimeRemaining = 15;
  List<RoundStats> _roundHistory = [];

  // Animation
  late AnimationController _whirlController;
  late AnimationController _pulseController;
  Timer? _spawnTimer;
  
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
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

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
    });

    _startRound();
  }

  void _startRound() {
    if (_round > _totalRounds) {
      _showGameOver();
      return;
    }

    // Pick random target word type
    final types = _wordTypes.keys.toList()..shuffle();
    _currentTargetType = types.first;

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

    // Increase speed every 2 rounds
    _baseSpeed = 1.0 + (_round - 1) * 0.15;

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
        setState(() => _roundTimeRemaining--);
      } else {
        _endRound();
      }
    });
  }

  void _startWordSpawning() {
    _spawnTimer?.cancel();
    
    // Spawn interval decreases with difficulty
    final spawnInterval = (1000 ~/ _baseSpeed).clamp(400, 1200);
    
    _spawnTimer = Timer.periodic(Duration(milliseconds: spawnInterval), (timer) {
      if (_roundTimeRemaining > 0 && _whirlingWords.length < 12) {
        _spawnWord();
      }
    });

    // Spawn initial words
    for (int i = 0; i < 4; i++) {
      Future.delayed(Duration(milliseconds: i * 300), () {
        if (mounted) _spawnWord();
      });
    }
  }

  void _spawnWord() {
    if (_wordPoolIndex >= _wordPool.length) {
      _wordPool.shuffle();
      _wordPoolIndex = 0;
    }

    final word = _wordPool[_wordPoolIndex++];
    final random = Random();
    
    final whirlingWord = WhirlingWord(
      word: word,
      angle: random.nextDouble() * 2 * pi,
      radius: 80.0 + random.nextDouble() * 100,
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

    setState(() {
      _streak++;
      if (_streak > _maxStreak) _maxStreak = _streak;
      
      // Score with streak multiplier
      final multiplier = min(1 + (_streak ~/ 3) * 0.5, 3.0);
      _score += (10 * multiplier).round();
      
      _roundHistory.last.correctTaps++;
    });

    // Record success in SRI
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
    _roundTimer?.cancel();
    _spawnTimer?.cancel();

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
            child: Row(
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
                  final currentAngle = whirlingWord.angle + 
                    (_whirlController.value * 2 * pi * whirlingWord.speed);
                  
                  final x = centerX + cos(currentAngle) * whirlingWord.radius;
                  final y = centerY + sin(currentAngle) * whirlingWord.radius;
                  
                  return Positioned(
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
    } else if (isTarget) {
      backgroundColor = SpaceTheme.deepSpace.withOpacity(0.9);
      borderColor = typeInfo?.color ?? SpaceTheme.starYellow;
    } else {
      backgroundColor = SpaceTheme.deepSpace.withOpacity(0.7);
      borderColor = Colors.white.withOpacity(0.3);
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
            width: isTarget ? 3 : 2,
          ),
          boxShadow: [
            if (isTarget)
              BoxShadow(
                color: borderColor.withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                whirlingWord.word.word,
                style: TextStyle(
                  fontFamily: selectedFontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  shadows: const [
                    Shadow(blurRadius: 2, color: Colors.black54),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}