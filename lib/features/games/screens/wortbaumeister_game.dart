// lib/features/games/screens/wortbaumeister_game.dart
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

/// Wortbaumeister Game - Teaching German Zusammen-/Getrenntschreibung
/// Fixed to match vocabulary_models.dart strictly.
class WortbaumeisterGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WortbaumeisterGame({super.key, required this.gradeLevel});

  @override
  State<WortbaumeisterGame> createState() => _WortbaumeisterGameState();
}

enum GameMode { trennbareVerben, nomenKomposita }

class WordChallenge {
  final String part1;
  final String part2;
  final bool shouldBeTogether;
  final String context;
  final String explanation;
  final int difficulty;
  final String wordId; // Base Lemma
  final GameMode mode;
  final String fullWord; // Specific Form

  WordChallenge({
    required this.part1,
    required this.part2,
    required this.shouldBeTogether,
    required this.context,
    required this.explanation,
    required this.difficulty,
    required this.wordId,
    required this.mode,
    required this.fullWord,
  });
}

enum FeedbackState { none, correct, incorrect }

class _WortbaumeisterGameState extends State<WortbaumeisterGame>
    with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  final List<WordChallenge> _challengeQueue = [];
  WordChallenge? _currentChallenge;
  int _score = 0;
  int _itemsCompleted = 0;
  final int _totalItems = 20;
  int _combo = 0;
  int _correctCount = 0;
  int _maxCombo = 0;
  int _level = 1;
  // Wort-Stückler is scoped to compound nouns. Separable verbs are
  // handled by Verb-Trenner, which has a binary-choice mechanic better
  // suited to that grammar topic.
  GameMode _currentMode = GameMode.nomenKomposita;

  // Animation
  late AnimationController _fallingController;
  late Animation<double> _fallingAnimation;
  double _fallingSpeed = 5.0;

  // Feedback
  FeedbackState _feedbackState = FeedbackState.none;
  String _feedbackMessage = '';
  bool _showContext = false;

  // Effects
  late AnimationController _successController;
  late AnimationController _errorController;


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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void dispose() {
    _fallingController.dispose();
    _successController.dispose();
    _errorController.dispose();
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
    _fallingSpeed = 5.0;

    _generateChallengeQueue();

    setState(() => _isLoading = false);
    _showNextChallenge();
  }

  // --- GENERATION LOGIC ---

  void _generateChallengeQueue() {
    _challengeQueue.clear();
    if (kDebugMode) debugPrint('[WORTBAUMEISTER] 🏗️ Generating new queue from Database examples...');

    final allWords = _vocabularyService.getAllWords(_gameProvider);

    final nouns = allWords
        .where((w) => w.wordType == GermanWordType.substantiv)
        .toList();

    final Map<String, GermanWord> nounMap = {
      for (var w in nouns) w.word.toLowerCase(): w
    };

    final nounChallenges = _generateNounChallenges(nouns, nounMap)..shuffle();

    if (kDebugMode) debugPrint('[WORTBAUMEISTER] 📊 Generated Pool: ${nounChallenges.length} Nouns');

    for (final c in nounChallenges) {
      if (_challengeQueue.length >= _totalItems) break;
      _challengeQueue.add(c);
    }
  }

  List<WordChallenge> _generateNounChallenges(List<GermanWord> nouns, Map<String, GermanWord> nounMap) {
    final challenges = <WordChallenge>[];

    for (final noun in nouns) {
      if (challenges.length > 20) break;
      if (noun.word.length < 8) continue;

      final split = _findValidCompoundSplit(noun.word, nounMap);

      if (split != null) {
        String context = 'Das Wort "${noun.word}" wird so geschrieben.';
        if (noun.examples.isNotEmpty) {
           final ex = noun.examples.firstWhere(
             (e) => e.text != null && e.text!.length < 100,
             // --- FIX 3: Use ApiExample class, not Example ---
             orElse: () => ApiExample(text: null)
           );
           if (ex.text != null) context = ex.text!;
        }

        challenges.add(WordChallenge(
          part1: split.part1,
          part2: split.part2,
          shouldBeTogether: true,
          context: context,
          explanation: 'Nomen-Komposita schreibt man immer zusammen.',
          difficulty: 1,
          wordId: noun.word,
          mode: GameMode.nomenKomposita,
          fullWord: noun.word,
        ));
      }
    }
    return challenges;
  }

  CompoundSplit? _findValidCompoundSplit(String word, Map<String, GermanWord> nounMap) {
    // Collect every split where both halves are real DB nouns (≥4 chars each),
    // then pick the most BALANCED one (largest min-part-length). Returning the
    // first match favoured a tiny coincidental modifier and produced wrong
    // decompositions; balanced splits track real compound boundaries better.
    CompoundSplit? best;
    int bestScore = -1;
    for (int i = 4; i < word.length - 3; i++) {
      final String p1 = word.substring(0, i);
      final String p2 = word.substring(i);
      final String p1Lower = p1.toLowerCase();
      final String p2Lower = p2.toLowerCase();

      bool valid = _isValidNoun(p1Lower, nounMap) && _isValidNoun(p2Lower, nounMap);
      // Allow a single Fugen-s on the modifier (Geburts+tag).
      if (!valid && p1Lower.endsWith('s')) {
        valid = _isValidNoun(p1Lower.substring(0, p1Lower.length - 1), nounMap) &&
            _isValidNoun(p2Lower, nounMap);
      }
      if (valid) {
        final score = p1.length < p2.length ? p1.length : p2.length;
        if (score > bestScore) {
          bestScore = score;
          best = CompoundSplit(part1: p1, part2: p2, difficulty: 1);
        }
      }
    }
    return best;
  }

  bool _isValidNoun(String key, Map<String, GermanWord> map) {
    final w = map[key];
    return w != null && w.wordType == GermanWordType.substantiv;
  }

  // --- GAMEPLAY & UI ---

  void _showNextChallenge() {
    if (_itemsCompleted >= _totalItems || _challengeQueue.isEmpty) {
      _showGameOver();
      return;
    }

    setState(() {
      _currentChallenge = _challengeQueue.removeAt(0);
      _currentMode = _currentChallenge!.mode;
      _feedbackState = FeedbackState.none;
      _feedbackMessage = '';
      _showContext = false;
    });

    _fallingController.reset();
    _fallingController.forward().then((_) {
      if (_feedbackState == FeedbackState.none && mounted) {
        _handleMiss();
      }
    });
  }

  void _handleChoice(bool chooseTogether) {
    if (_currentChallenge == null || _feedbackState != FeedbackState.none) return;

    _fallingController.stop();
    final isCorrect = chooseTogether == _currentChallenge!.shouldBeTogether;

    setState(() {
      _feedbackState = isCorrect ? FeedbackState.correct : FeedbackState.incorrect;
      _feedbackMessage = _currentChallenge!.explanation;
      _showContext = true;
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

    final basePoints = 100 + (_currentChallenge!.difficulty * 25);
    final comboMultiplier = 1.0 + (_combo / 10);
    final points = (basePoints * comboMultiplier).round();

    setState(() {
      _score += points;
      _itemsCompleted++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentChallenge!.wordId,
      wasCorrect: true,
      metadata: {
        'game': 'wortbaumeister',
        'wordId': _currentChallenge!.wordId,
        'combo': _combo
      },
    );

    if (_itemsCompleted % 5 == 0) {
      _levelUp();
    }

    Future.delayed(const Duration(milliseconds: 2000), () {
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
      baseWord: _currentChallenge!.wordId,
      wasCorrect: false,
      metadata: {
        'game': 'wortbaumeister',
        'wordId': _currentChallenge!.wordId,
      },
    );

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _showNextChallenge();
    });
  }

  void _handleMiss() {
    final s = S.of(context);
    setState(() {
      _feedbackState = FeedbackState.incorrect;
      _feedbackMessage = s?.gameTooSlow ?? 'Zu langsam!';
      _showContext = true;
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
      _fallingSpeed = max(2.5, _fallingSpeed * 0.9);
      _fallingController.duration = Duration(milliseconds: (_fallingSpeed * 1000).toInt());
    });
    _audioService.playSound('levelup');
  }

  void _showGameOver() {
    final s = S.of(context);
    if (s == null) return;

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'wortbaumeister_game',
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
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.gameDone, style: SpaceTheme.buttonStyle),
          ),
        ],
      ),
    );
  }

  // --- UI BUILDING ---

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
              _buildUnifiedTopBar(s),
              Expanded(child: _buildGameArea(s, selectedFontFamily)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedTopBar(S s) {
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
          const SizedBox(width: 12),
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
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: SpaceTheme.nebulaPurple,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Punkte: $_score',
            child: _buildCompactStat(Icons.stars, '$_score', SpaceTheme.starYellow),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Fortschritt: $_itemsCompleted von $_totalItems',
            child: _buildCompactStat(Icons.check_circle_outline, '$_itemsCompleted/$_totalItems', SpaceTheme.cosmicPink),
          ),
          const Spacer(),
          if (_combo > 1)
            Semantics(
              label: 'Kombo mal $_combo',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SpaceTheme.planetOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SpaceTheme.planetOrange),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    s.gameCombo(_combo),
                    style: SpaceTheme.bodyStyle.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: SpaceTheme.planetOrange,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameArea(S s, String selectedFontFamily) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _currentMode == GameMode.trennbareVerben ? s.verbtrennerSeparableTitle : s.verbtrennerCompoundTitle,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 18),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: AnimatedBuilder(
            animation: _fallingAnimation,
            builder: (context, child) => _buildFallingWord(selectedFontFamily),
          ),
        ),
        _buildChoiceButtons(s),
      ],
    );
  }

  Widget _buildFallingWord(String selectedFontFamily) {
    if (_currentChallenge == null) return const SizedBox.shrink();

    final screenHeight = MediaQuery.of(context).size.height - 400;
    final position = screenHeight * _fallingAnimation.value;

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: screenHeight * 0.75,
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

        Positioned(
          left: 0,
          right: 0,
          top: position,
          child: _buildWordDisplay(selectedFontFamily),
        ),
      ],
    );
  }

  Widget _buildWordDisplay(String selectedFontFamily) {
    final scale = _feedbackState == FeedbackState.correct
        ? 1.0 + (sin(_successController.value * pi) * 0.1)
        : 1.0;

    return AnimatedBuilder(
      animation: _errorController,
      builder: (context, child) {
        final shake = _feedbackState == FeedbackState.incorrect
            ? sin(_errorController.value * pi * 4) * 10
            : 0.0;

        return Transform.translate(
          offset: Offset(shake, 0),
          child: Transform.scale(
            scale: scale,
            child: _buildBlockDisplay(selectedFontFamily),
          ),
        );
      },
    );
  }

  Widget _buildBlockDisplay(String selectedFontFamily) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBlock(_currentChallenge!.part1.toUpperCase(), selectedFontFamily),

              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              _buildBlock(_currentChallenge!.part2.toUpperCase(), selectedFontFamily),
            ],
          ),
          if (_showContext) ...[
            const SizedBox(height: 16),
            Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SpaceTheme.nebulaPurple.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    _currentChallenge!.context,
                    style: TextStyle(
                      fontFamily: selectedFontFamily,
                      fontSize: 16,
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_feedbackMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _feedbackState == FeedbackState.correct
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 18,
                              color: _feedbackState == FeedbackState.correct
                                  ? SpaceTheme.alienGreen
                                  : SpaceTheme.rocketRed,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _feedbackMessage,
                                style: TextStyle(
                                  color: _feedbackState == FeedbackState.correct
                                      ? SpaceTheme.alienGreen
                                      : SpaceTheme.rocketRed,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildBlock(String text, String fontFamily) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _getWordColor(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: _getWordColor().withValues(alpha: 0.4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Color _getWordColor() {
    switch (_feedbackState) {
      case FeedbackState.correct:
        return Colors.green.shade700;
      case FeedbackState.incorrect:
        return SpaceTheme.rocketRed;
      case FeedbackState.none:
        return _currentMode == GameMode.trennbareVerben
            ? SpaceTheme.cosmicPink
            : SpaceTheme.nebulaPurple;
    }
  }

  Widget _buildChoiceButtons(S s) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: _buildChoiceButton(
              icon: Icons.link_off,
              label: s.verbtrennerSeparatedLabel,
              subtitle: s.wortbaumeisterSeparatedExample,
              color: SpaceTheme.nebulaPurple,
              onTap: () => _handleChoice(false),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildChoiceButton(
              icon: Icons.link,
              label: s.verbtrennerTogetherLabel,
              subtitle: s.wortbaumeisterTogetherExample,
              color: SpaceTheme.starYellow,
              onTap: () => _handleChoice(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: '$label, $subtitle',
      button: true,
      enabled: _feedbackState == FeedbackState.none,
      child: GestureDetector(
        onTap: _feedbackState == FeedbackState.none ? onTap : null,
        child: AnimatedOpacity(
          opacity: _feedbackState == FeedbackState.none ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 36, color: Colors.white),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper class for compound splits
class CompoundSplit {
  final String part1;
  final String part2;
  final int difficulty;

  CompoundSplit({
    required this.part1,
    required this.part2,
    required this.difficulty,
  });
}