// lib/features/games/screens/word_memory_game.dart
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

class WordMemoryGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WordMemoryGame({super.key, required this.gradeLevel});

  @override
  State<WordMemoryGame> createState() => _WordMemoryGameState();
}

class MemoryCard {
  final String word;
  final String fontFamily;
  final int id;
  bool isFlipped;
  bool isMatched;

  MemoryCard({
    required this.word,
    required this.fontFamily,
    required this.id,
    this.isFlipped = false,
    this.isMatched = false,
  });
}

class _WordMemoryGameState extends State<WordMemoryGame> with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  List<MemoryCard> _cards = [];
  int _score = 0;
  int _moves = 0;
  int _pairsFound = 0;
  int _totalPairs = 0;

  // Selection state
  MemoryCard? _firstSelected;
  MemoryCard? _secondSelected;
  bool _isChecking = false;

  // Animation
  late AnimationController _flipController;
  late AnimationController _matchController;
  late AnimationController _shakeController;

  // Fonts to use for memory pairs
  final List<String> _availableFonts = [
    'SpaceGrotesk',
    'Grundschrift',
    'SASBienchen',
    'BernerBasisschrift',
    'Gruenewald',
    'Schulkursiv',
  ];

  @override
  void initState() {
    super.initState();
    
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _matchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void dispose() {
    _flipController.dispose();
    _matchController.dispose();
    _shakeController.dispose();
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
    // Words should be short enough to read easily in cards
    return word.word.length >= 3 &&
        word.word.length <= 8 &&
        !word.word.contains(" ");
  }

  void _loadLevel() {
    _score = 0;
    _moves = 0;
    _pairsFound = 0;

    // Determine number of pairs based on grade
    switch (widget.gradeLevel) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        _totalPairs = 4; // 8 cards
        break;
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        _totalPairs = 6; // 12 cards
        break;
      default:
        _totalPairs = 8; // 16 cards
    }

    // --- ADAPTIVE WORD SELECTION ---
    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};

    int reviewWordCount = (_totalPairs * 0.5).ceil();
    int newWordCount = _totalPairs - reviewWordCount;

    // Get review words
    final reviewItemIds = _sriService.getItemsForReview(
      limit: reviewWordCount * 2,
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

    // Get new words
    newWordCount = _totalPairs - wordsForGame.length;
    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: newWordCount * 2,
      settingsProvider: _gameProvider,
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
        if (wordsForGame.length >= _totalPairs) break;
      }
    }

    // Fill with random words if needed
    if (wordsForGame.length < _totalPairs) {
      final allWords = _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
      allWords.shuffle();

      for (final word in allWords) {
        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          wordsForGame.add(word);
          addedWordIds.add(word.id);
          if (wordsForGame.length >= _totalPairs) break;
        }
      }
    }
    // --- END ADAPTIVE SELECTION ---

    // Create card pairs with different fonts
    final List<MemoryCard> cards = [];
    final random = Random();
    
    for (int i = 0; i < wordsForGame.length && i < _totalPairs; i++) {
      final word = wordsForGame[i];
      
      // Pick two different random fonts for this word pair
      final shuffledFonts = List<String>.from(_availableFonts)..shuffle(random);
      final font1 = shuffledFonts[0];
      final font2 = shuffledFonts[1];

      cards.add(MemoryCard(
        word: word.word,
        fontFamily: font1,
        id: i * 2,
      ));
      
      cards.add(MemoryCard(
        word: word.word,
        fontFamily: font2,
        id: i * 2 + 1,
      ));
    }

    // Shuffle all cards
    cards.shuffle(random);

    setState(() {
      _cards = cards;
      _firstSelected = null;
      _secondSelected = null;
      _isChecking = false;
      _isLoading = false;
    });
  }

  void _onCardTapped(MemoryCard card) {
    if (_isChecking || card.isMatched || card.isFlipped) return;

    setState(() {
      card.isFlipped = true;
      _flipController.forward(from: 0);
    });

    _audioService.playSound('tap');

    if (_firstSelected == null) {
      _firstSelected = card;
    } else if (_secondSelected == null && card != _firstSelected) {
      _secondSelected = card;
      _moves++;
      _checkMatch();
    }
  }

  Future<void> _checkMatch() async {
    if (_firstSelected == null || _secondSelected == null) return;

    setState(() => _isChecking = true);

    await Future.delayed(const Duration(milliseconds: 600));

    final bool isMatch = _firstSelected!.word == _secondSelected!.word;

    if (isMatch) {
      // Match found!
      setState(() {
        _firstSelected!.isMatched = true;
        _secondSelected!.isMatched = true;
        _pairsFound++;
        _score += 100;
      });

      _audioService.playSound('success');
      _matchController.forward(from: 0);

      // Record successful match in SRI
      _sriService.recordResponse(
        skillType: LanguageSkillType.spelling,
        baseWord: _firstSelected!.word,
        wasCorrect: true,
        metadata: {'game': 'memory', 'moves': _moves},
      );

      // Check if game is complete
      if (_pairsFound == _totalPairs) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          _showGameOver();
        }
      }
    } else {
      // No match - shake and flip back
      _audioService.playSound('failure');
      
      await _shakeController.forward(from: 0);
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        setState(() {
          _firstSelected!.isFlipped = false;
          _secondSelected!.isFlipped = false;
        });
      }

      // Record unsuccessful attempt in SRI
      _sriService.recordResponse(
        skillType: LanguageSkillType.spelling,
        baseWord: _firstSelected!.word,
        wasCorrect: false,
        metadata: {'game': 'memory', 'moves': _moves},
      );
    }

    if (mounted) {
      setState(() {
        _firstSelected = null;
        _secondSelected = null;
        _isChecking = false;
      });
    }
  }

  void _showGameOver() {
    final s = S.of(context)!;
    
    // Calculate star rating based on moves
    int stars = 3;
    final perfectMoves = _totalPairs; // One move per pair is perfect
    if (_moves > perfectMoves * 2) {
      stars = 1;
    } else if (_moves > perfectMoves * 1.5) {
      stars = 2;
    }

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
              s.wordMemoryComplete,
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
              '${s.wordMemoryScore}: $_score',
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 18),
            ),
            Text(
              '${s.wordMemoryMoves}: $_moves',
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 18),
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

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              GameUI(
                title: s.wordMemoryTitle,
                level: widget.gradeLevel.index + 1,
                onBack: () => Navigator.of(context).pop(),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatCard(s.wordMemoryScore, _score.toString(), Icons.stars),
                            _buildStatCard(s.wordMemoryMoves, _moves.toString(), Icons.touch_app),
                            _buildStatCard(s.wordMemoryPairs, '$_pairsFound/$_totalPairs', Icons.check_circle),
                          ],
                        ),
                      ),
                      
                      // Game grid
                      Expanded(
                        child: Center(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Calculate optimal grid layout
                              final crossAxisCount = _totalPairs <= 4 ? 2 : (_totalPairs <= 6 ? 3 : 4);
                              
                              // Calculate card size to fit screen
                              final availableWidth = constraints.maxWidth - 48;
                              final availableHeight = constraints.maxHeight - 48;
                              
                              final cardWidth = (availableWidth / crossAxisCount) - 12;
                              final rows = (_cards.length / crossAxisCount).ceil();
                              final cardHeight = (availableHeight / rows) - 12;
                              
                              final cardSize = min(cardWidth, cardHeight).clamp(80.0, 150.0);
                              
                              return SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    alignment: WrapAlignment.center,
                                    children: _cards.map((card) {
                                      return _buildMemoryCard(card, cardSize);
                                    }).toList(),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
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

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpaceTheme.nebulaPurple.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, color: SpaceTheme.starYellow, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(MemoryCard card, double size) {
    final isSelected = card == _firstSelected || card == _secondSelected;
    final shouldShake = isSelected && _shakeController.isAnimating && !card.isMatched;

    return AnimatedBuilder(
      animation: Listenable.merge([_flipController, _matchController, _shakeController]),
      builder: (context, child) {
        // Shake animation
        double shakeOffset = 0;
        if (shouldShake) {
          shakeOffset = sin(_shakeController.value * pi * 4) * 8;
        }

        // Match pulse animation
        double scale = 1.0;
        if (card.isMatched && _matchController.isAnimating) {
          scale = 1.0 + (sin(_matchController.value * pi) * 0.2);
        }

        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: Transform.scale(
            scale: scale,
            child: GestureDetector(
              onTap: () => _onCardTapped(card),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: card.isFlipped || card.isMatched
                      ? (card.isMatched
                          ? SpaceTheme.alienGreen.withOpacity(0.9)
                          : SpaceTheme.planetOrange.withOpacity(0.9))
                      : SpaceTheme.deepSpace.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: card.isMatched
                        ? SpaceTheme.alienGreen
                        : (isSelected
                            ? SpaceTheme.starYellow
                            : SpaceTheme.nebulaPurple.withOpacity(0.5)),
                    width: card.isMatched || isSelected ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (card.isMatched
                              ? SpaceTheme.alienGreen
                              : (isSelected
                                  ? SpaceTheme.starYellow
                                  : SpaceTheme.nebulaPurple))
                          .withOpacity(0.3),
                      blurRadius: card.isMatched || isSelected ? 15 : 8,
                      spreadRadius: card.isMatched || isSelected ? 2 : 0,
                    ),
                  ],
                ),
                child: card.isFlipped || card.isMatched
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              card.word,
                              style: TextStyle(
                                fontFamily: card.fontFamily,
                                fontSize: size * 0.25,
                                fontWeight: FontWeight.bold,
                                color: card.isMatched
                                    ? SpaceTheme.deepSpace
                                    : Colors.white,
                                shadows: [
                                  Shadow(
                                    blurRadius: 4,
                                    color: card.isMatched
                                        ? Colors.black26
                                        : Colors.black54,
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.psychology,
                          size: size * 0.4,
                          color: SpaceTheme.cosmicPink.withOpacity(0.6),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}