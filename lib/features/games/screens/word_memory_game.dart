// ignore_for_file: unused_element, unused_field
// lib/features/games/screens/word_memory_game.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/space_background.dart';
import '../models/game_outcome.dart';

class WordMemoryGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WordMemoryGame({super.key, required this.gradeLevel});

  @override
  State<WordMemoryGame> createState() => _WordMemoryGameState();
}

class MemoryCard {
  final String word;
  final String displayText;
  final String fontFamily;
  final int id;
  final String? matchId;
  final bool isDefinitionCard;
  bool isFlipped;
  bool isMatched;

  MemoryCard({
    required this.word,
    String? displayText,
    required this.fontFamily,
    required this.id,
    this.matchId,
    this.isDefinitionCard = false,
    this.isFlipped = false,
    this.isMatched = false,
  }) : displayText = displayText ?? word;
}

class _WordMemoryGameState extends State<WordMemoryGame> with TickerProviderStateMixin {
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  bool _isLoading = true;
  List<MemoryCard> _cards = [];
  
  // Game Stats
  int _score = 0;
  int _moves = 0;
  int _pairsFound = 0;
  int _totalPairs = 0;

  MemoryCard? _firstSelected;
  MemoryCard? _secondSelected;
  bool _isChecking = false;

  late AnimationController _flipController;
  late AnimationController _matchController;
  late AnimationController _shakeController;

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

    await _loadLevel();
  }

  String? _extractBaseWordFromSriId(String id) {
    if (id.startsWith('SPELL_')) return id.substring('SPELL_'.length);
    if (id.startsWith('WORDTYPE_')) return id.substring('WORDTYPE_'.length);
    return null;
  }

  bool _isWordValidForGame(GermanWord word) {
    return word.word.length >= 3 && word.word.length <= 8 && !word.word.contains(" ");
  }

  Future<void> _loadLevel() async {
    _score = 0;
    _moves = 0;
    _pairsFound = 0;

    switch (widget.gradeLevel) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        _totalPairs = 4; 
        break;
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        _totalPairs = 6; 
        break;
      default:
        _totalPairs = 8; 
    }

    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};

    int reviewWordCount = (_totalPairs * 0.5).ceil();
    final reviewItemIds = _sriService.getItemsForReview(
      limit: reviewWordCount * 2,
      gradeLevelFilter: widget.gradeLevel.index + 1,
    );

    for (final id in reviewItemIds) {
      final wordString = _extractBaseWordFromSriId(id);
      if (wordString == null) continue;
      // Indexed lookup: this used to scan the whole catalogue per review item.
      final word = _vocabularyService.findByWrittenForm(wordString);
      if (word == null) continue; // Word from SRI not in vocab, skip

      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
        if (wordsForGame.length >= reviewWordCount) break;
      }
    }

    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: (_totalPairs - wordsForGame.length) * 2,
      settingsProvider: _gameProvider,
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
        if (wordsForGame.length >= _totalPairs) break;
      }
    }

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

    // Definition cards read the enrichment, so decode it for the chosen words.
    final playable = await _vocabularyService.hydrate(wordsForGame);
    if (!mounted) return;

    final List<MemoryCard> cards = [];
    final random = Random();
    final bool definitionMode = widget.gradeLevel.index >= 2;

    for (int i = 0; i < playable.length && i < _totalPairs; i++) {
      final word = playable[i];
      final shuffledFonts = List<String>.from(_availableFonts)..shuffle(random);
      final def = definitionMode ? word.displayDefinitions.firstOrNull : null;
      if (def != null && def.isNotEmpty) {
        final pairId = 'pair_$i';
        final truncDef = def.length > 55 ? '${def.substring(0, 52)}…' : def;
        cards.add(MemoryCard(word: word.word, fontFamily: shuffledFonts[0], id: i * 2, matchId: pairId));
        cards.add(MemoryCard(word: word.word, displayText: truncDef, fontFamily: 'SpaceGrotesk', id: i * 2 + 1, matchId: pairId, isDefinitionCard: true));
      } else {
        cards.add(MemoryCard(word: word.word, fontFamily: shuffledFonts[0], id: i * 2));
        cards.add(MemoryCard(word: word.word, fontFamily: shuffledFonts[1], id: i * 2 + 1));
      }
    }

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
      // Lock input synchronously so a fast double-tap cannot flip a 3rd card
      // before the async _checkMatch sets _isChecking after its first await.
      _isChecking = true;
      _checkMatch();
    }
  }

  Future<void> _checkMatch() async {
    if (_firstSelected == null || _secondSelected == null) return;

    // _isChecking is already set true synchronously in _onCardTapped; mirror it
    // into a rebuild so the UI reflects the locked state immediately.
    setState(() => _isChecking = true);
    await Future.delayed(const Duration(milliseconds: 600));

    final bool isMatch = _firstSelected!.matchId != null
        ? _firstSelected!.matchId == _secondSelected!.matchId
        : _firstSelected!.word == _secondSelected!.word;

    if (isMatch) {
      setState(() {
        _firstSelected!.isMatched = true;
        _secondSelected!.isMatched = true;
        _pairsFound++;
        _score += 100;
      });

      _audioService.playSound('success');
      _gameProvider.hapticLight();
      _matchController.forward(from: 0);

      _sriService.recordResponse(
        skillType: LanguageSkillType.spelling,
        baseWord: _firstSelected!.word,
        wasCorrect: true,
        metadata: {'game': 'memory', 'moves': _moves},
      );

      if (_pairsFound == _totalPairs) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) _showGameOver();
      }
    } else {
      _audioService.playSound('failure');
      _gameProvider.hapticHeavy();
      await _shakeController.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        setState(() {
          _firstSelected!.isFlipped = false;
          _secondSelected!.isFlipped = false;
        });
      }

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
    int stars = 3;
    final perfectMoves = _totalPairs;
    if (_moves > perfectMoves * 2) {
      stars = 1;
    } else if (_moves > perfectMoves * 1.5) {
      stars = 2;
    }

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'word_memory_game',
      difficulty: widget.gradeLevel.index + 1,
      score: _score,
      wasSuccessful: stars >= 2,
    ));

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
            Text(s.wordMemoryComplete, style: SpaceTheme.titleStyle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) => Icon(
                index < stars ? Icons.star : Icons.star_border,
                color: SpaceTheme.starYellow,
                size: 40,
              )),
            ),
            const SizedBox(height: 20),
            Text('${s.wordMemoryScore}: $_score', style: SpaceTheme.bodyStyle.copyWith(fontSize: 18)),
            Text('${s.wordMemoryMoves}: $_moves', style: SpaceTheme.bodyStyle.copyWith(fontSize: 18)),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () {
              Navigator.of(context).pop();
              _loadLevel();
            },
            child: Text(s.gameReplay, style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.alienGreen)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: SpaceTheme.planetOrange),
            child: Text(s.gameDone, style: SpaceTheme.bodyStyle.copyWith(color: Colors.white)),
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
              if (!_isLoading) _buildAllInOneHeader(context),
              if (_isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: _buildGameGrid(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- NEW: The "Everything in ONE top bar" Widget ---
  // --- FIX: Corrected 'score' getter and optimized layout ---
  Widget _buildAllInOneHeader(BuildContext context) {
    final s = S.of(context)!;
    // 1. Get the global score correctly using the getter 'score'
    final totalGems = context.watch<GameProvider>().score;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5), width: 2)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // --- LEFT SECTION: Back & Level ---
            Semantics(
              label: S.of(context)!.semanticsBack,
              button: true,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: S.of(context)!.gradeN(widget.gradeLevel.index + 1),
              container: true,
              child: _buildMiniBadge(
                Icons.emoji_events_rounded,
                '${widget.gradeLevel.index + 1}',
                SpaceTheme.starYellow,
              ),
            ),

            const Spacer(), // Pushes center content to middle

            // --- CENTER SECTION: Game Stats (Points, Moves, Pairs) ---
            // FittedBox ensures this scales down on small phones instead of overflowing
            Flexible(
              flex: 10,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Local Score (Current Game)
                      Semantics(
                        label: s.wordMemoryScoreLabel(_score),
                        child: _buildStatItem(Icons.star_rounded, '$_score', SpaceTheme.starYellow),
                      ),
                      _buildVerticalDivider(),
                      // Moves
                      Semantics(
                        label: s.wordMemoryMovesLabel(_moves),
                        child: _buildStatItem(Icons.touch_app_rounded, '$_moves', SpaceTheme.alienGreen),
                      ),
                      _buildVerticalDivider(),
                      // Pairs Found
                      Semantics(
                        label: s.wordMemoryPairsLabel(_pairsFound, _totalPairs),
                        child: _buildStatItem(Icons.check_circle_rounded, '$_pairsFound/$_totalPairs', SpaceTheme.cosmicPink),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Spacer(), // Pushes right content to end

            // --- RIGHT SECTION: Global Gems ---
            Semantics(
              label: s.wordMemoryTotalGemsLabel(totalGems),
              container: true,
              child: _buildMiniBadge(
                Icons.diamond_rounded,
                '$totalGems', // Corrected from totalScore
                Colors.cyanAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 20,
      width: 1.5,
      color: Colors.white24,
      margin: const EdgeInsets.symmetric(horizontal: 12),
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
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 16,
      width: 1,
      color: Colors.white24,
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildGameGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        
        // Determine Grid Dimensions
        int columns;
        int rows;

        if (_totalPairs <= 4) { // 8 cards
          columns = isLandscape ? 4 : 2;
          rows = isLandscape ? 2 : 4;
        } else if (_totalPairs <= 6) { // 12 cards
          columns = isLandscape ? 4 : 3;
          rows = isLandscape ? 3 : 4;
        } else { // 16 cards
          columns = 4;
          rows = 4;
        }

        const double padding = 16.0;
        const double spacing = 12.0;
        
        final availableWidth = constraints.maxWidth - (padding * 2);
        final availableHeight = constraints.maxHeight - (padding * 2);
        
        final widthPerCard = (availableWidth - (spacing * (columns - 1))) / columns;
        final heightPerCard = (availableHeight - (spacing * (rows - 1))) / rows;
        
        final cardSize = min(widthPerCard, heightPerCard);
        
        final gridWidth = (cardSize * columns) + (spacing * (columns - 1));
        final gridHeight = (cardSize * rows) + (spacing * (rows - 1));

        return Center(
          child: SizedBox(
            width: gridWidth,
            height: gridHeight,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: 1.0,
              ),
              itemCount: _cards.length,
              itemBuilder: (context, index) {
                return _buildMemoryCard(_cards[index], cardSize);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMemoryCard(MemoryCard card, double size) {
    final isSelected = card == _firstSelected || card == _secondSelected;
    final shouldShake = isSelected && _shakeController.isAnimating && !card.isMatched;
    
    return AnimatedBuilder(
      animation: Listenable.merge([_flipController, _matchController, _shakeController]),
      builder: (context, child) {
        double shakeOffset = 0;
        if (shouldShake) shakeOffset = sin(_shakeController.value * pi * 4) * 8;

        double scale = 1.0;
        if (card.isMatched && _matchController.isAnimating) {
          scale = 1.0 + (sin(_matchController.value * pi) * 0.3);
        }

        final isFlipped = card.isFlipped || card.isMatched;

        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: Transform.scale(
            scale: scale,
            child: Semantics(
              label: card.isMatched
                  ? S.of(context)!.wordMemoryCardMatched(card.displayText)
                  : (isFlipped
                      ? S.of(context)!.wordMemoryCardRevealed(card.displayText)
                      : S.of(context)!.wordMemoryCardHidden),
              button: true,
              selected: isSelected,
              child: GestureDetector(
                onTap: () => _onCardTapped(card),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    gradient: isFlipped
                        ? (card.isMatched
                            ? LinearGradient(colors: [SpaceTheme.alienGreen, SpaceTheme.alienGreen.withValues(alpha: 0.7)])
                            : LinearGradient(colors: [SpaceTheme.planetOrange, SpaceTheme.planetOrange.withValues(alpha: 0.7)]))
                        : LinearGradient(colors: [SpaceTheme.deepSpace.withValues(alpha: 0.9), SpaceTheme.nebulaPurple.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: card.isMatched
                          ? SpaceTheme.alienGreen
                          : (isSelected ? SpaceTheme.starYellow : SpaceTheme.nebulaPurple.withValues(alpha: 0.5)),
                      width: card.isMatched || isSelected ? 3 : 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (card.isMatched ? SpaceTheme.alienGreen : (isSelected ? SpaceTheme.starYellow : SpaceTheme.nebulaPurple))
                            .withValues(alpha: card.isMatched || isSelected ? 0.6 : 0.2),
                        blurRadius: card.isMatched || isSelected ? 15 : 8,
                      ),
                    ],
                  ),
                  child: isFlipped
                      ? Stack(
                          children: [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: card.isDefinitionCard
                                    ? Text(
                                        card.displayText,
                                        style: TextStyle(
                                          fontFamily: 'SpaceGrotesk',
                                          fontSize: size * 0.16,
                                          fontStyle: FontStyle.italic,
                                          color: card.isMatched ? SpaceTheme.deepSpace : Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          card.displayText,
                                          style: TextStyle(
                                            fontFamily: card.fontFamily,
                                            fontSize: size * 0.3,
                                            fontWeight: FontWeight.bold,
                                            color: card.isMatched ? SpaceTheme.deepSpace : Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                              ),
                            ),
                            // ✓ overlay on matched cards (alongside the
                            // green color) for color-blind redundancy.
                            if (card.isMatched)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Icon(
                                  Icons.check_circle,
                                  size: size * 0.22,
                                  color: SpaceTheme.deepSpace,
                                ),
                              ),
                          ],
                        )
                      : Stack(
                          children: [
                            Positioned.fill(child: ExcludeSemantics(child: CustomPaint(painter: _CardBackPainter(animation: _flipController.view)))),
                            Center(child: Icon(Icons.psychology, size: size * 0.4, color: SpaceTheme.cosmicPink.withValues(alpha: 0.8))),
                          ],
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

class _CardBackPainter extends CustomPainter {
  final Animation<double> animation;
  _CardBackPainter({required this.animation}) : super(repaint: animation);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2;
    for (int i = 0; i < 3; i++) {
      final radius = (size.width / 2) * (0.3 + i * 0.2);
      final opacity = 0.3 + (sin(animation.value * 2 * pi + i) * 0.2);
      paint.color = SpaceTheme.starYellow.withValues(alpha: opacity);
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), radius, paint);
    }
  }
  @override
  bool shouldRepaint(_CardBackPainter oldDelegate) =>
      oldDelegate.animation.value != animation.value;
}