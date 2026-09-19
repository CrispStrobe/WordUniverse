// lib/features/games/screens/grossstadt_game.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../services/grossstadt_service.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/space_background.dart';
import '../models/game_outcome.dart';

/// Großstadt Game - Teaching German capitalization rules
/// Refactored: Plain "Groß vs Klein" logic, All-Caps display, Contextual highlighting.
class GrossstadtGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const GrossstadtGame({super.key, required this.gradeLevel});

  @override
  State<GrossstadtGame> createState() => _GrossstadtGameState();
}

/// Represents a single item flowing on the conveyor belt

enum FeedbackState { none, correct, incorrect }

class _GrossstadtGameState extends State<GrossstadtGame>
    with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  final List<CapitalizationItem> _itemQueue = [];
  CapitalizationItem? _currentItem;
  int _score = 0;
  int _itemsCompleted = 0;
  int _totalItems = 20;
  int _combo = 0;
  int _correctCount = 0;
  int _maxCombo = 0;
  int _level = 1;

  // Conveyor belt animation
  late AnimationController _conveyorController;
  late Animation<double> _conveyorAnimation;
  double _conveyorSpeed = 4.0; // seconds per item

  // Feedback
  FeedbackState _feedbackState = FeedbackState.none;
  String _feedbackMessage = '';

  // Animation Controllers
  late AnimationController _successController;
  late AnimationController _errorController;

  void _log(String message) {
    if (kDebugMode) debugPrint('[GROSSSTADT] $message');
  }

  @override
  void initState() {
    super.initState();

    _conveyorController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_conveyorSpeed * 1000).toInt()),
    );

    _conveyorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _conveyorController, curve: Curves.linear),
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
    _conveyorController.dispose();
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

    await _loadLevel();
  }

  Future<void> _loadLevel() async {
    _score = 0;
    _itemsCompleted = 0;
    _combo = 0;
    _correctCount = 0;
    _maxCombo = 0;
    _level = 1;
    _conveyorSpeed = 4.0;

    await _generateItemQueue();
    if (!mounted) return;
    _showNextItem();

    setState(() => _isLoading = false);
  }

  /// Generate capitalization items from vocabulary words
  Future<void> _generateItemQueue() async {
    _log('========================================');
    _log('Starting item generation');
    _log('========================================');

    _itemQueue.clear();

    // Get appropriate words for the grade level
    final verbs = await _getWordsForGame(GermanWordType.verb, 15);
    final adjectives = await _getWordsForGame(GermanWordType.adjektiv, 12);
    final nouns = await _getWordsForGame(GermanWordType.substantiv, 12);
    if (!mounted) return;

    if (kDebugMode) {
      _log(
          'Available: ${verbs.length} verbs, ${adjectives.length} adjectives, ${nouns.length} nouns');
      _log('');
    }

    _itemQueue.addAll(buildCapitalizationItems(
      verbs: verbs,
      adjectives: adjectives,
      nouns: nouns,
    ));

    _itemQueue.shuffle();
    if (_itemQueue.length > _totalItems) {
      _itemQueue.removeRange(_totalItems, _itemQueue.length);
    }

    if (kDebugMode) {
      _log('');
      _log('========================================');
      _log('Total items generated: ${_itemQueue.length}');
      _log('========================================');
    }
  }

  /// Check if a verb is in infinitive form (base form)

  /// Get clean adjective base form by stripping common endings

  /// The chosen words, with their enrichment: conjugated forms come from the
  /// Wiktionary inflections, and only these few words need them.
  Future<List<GermanWord>> _getWordsForGame(
      GermanWordType type, int count) async {
    final allWords = _vocabularyService
        .getAllWords(_gameProvider)
        .where((w) =>
            w.wordType == type &&
            !w.word.contains(' ') && // Single words only
            w.word.length >= 3 &&
            w.gradeLevel <= widget.gradeLevel.index + 2)
        .toList();

    // Additional filtering based on word type
    List<GermanWord> filtered;
    if (type == GermanWordType.verb) {
      // For verbs: Only keep infinitives (lemma ends in -en, -ern, -eln)
      filtered = allWords.where((w) => isInfinitive(w.lemma)).toList();
      if (kDebugMode) {
        _log(
            'Filtered verbs: ${filtered.length} infinitives out of ${allWords.length} total');
      }
    } else if (type == GermanWordType.adjektiv) {
      // For adjectives: Prefer words with clean lemmas
      filtered = allWords;
    } else {
      // For nouns: exclude proper nouns using the model's flag (German nouns are
      // all capitalized, so a case/length heuristic over/under-filters). This
      // mirrors the other games.
      filtered = allWords.where((w) => !w.isProperNoun).toList();
    }

    filtered.shuffle();
    return _vocabularyService.hydrate(filtered.take(count));
  }

  // --- MORPHOLOGY HELPERS ---

  /// Helper to get present tense conjugated form from API data

  /// Nominalised neuter form for "etwas/nichts ___" (Großschreibung), but only
  /// for simple consonant-final base adjectives where adding "-es" is correct
  /// (gut→Gutes, klein→Kleines, rot→Rotes). Returns null for -e/-el/-er/-en
  /// adjectives whose nominalisation needs elision/stem rules we don't model
  /// reliably (dunkel→Dunkles, teuer→Teures) — we skip rather than present a
  /// malformed word as the correct answer.

  // --- VARIANT GENERATORS ---

  // --- GAMEPLAY LOGIC ---

  void _showNextItem() {
    if (_itemsCompleted >= _totalItems || _itemQueue.isEmpty) {
      _showGameOver();
      return;
    }

    setState(() {
      _currentItem = _itemQueue.removeAt(0);
      _feedbackState = FeedbackState.none;
      _feedbackMessage = '';
    });

    _conveyorController.reset();
    _conveyorController.forward().then((_) {
      if (_feedbackState == FeedbackState.none && mounted) {
        _handleMiss();
      }
    });
  }

  void _handleChoice(bool chooseCapitalized) {
    if (_currentItem == null || _feedbackState != FeedbackState.none) return;

    _conveyorController.stop();
    final isCorrect = chooseCapitalized == _currentItem!.shouldBeCapitalized;

    setState(() {
      _feedbackState =
          isCorrect ? FeedbackState.correct : FeedbackState.incorrect;
      _feedbackMessage = _currentItem!.explanation;
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

    final basePoints = 100 + (_currentItem!.difficulty * 20);
    final comboMultiplier = 1.0 + (_combo / 10);
    final points = (basePoints * comboMultiplier).round();

    setState(() {
      _score += points;
      _itemsCompleted++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentItem!.lemma,
      wasCorrect: true,
      metadata: {
        'rule': _currentItem!.rule,
        'responseTimeMs':
            ((1.0 - _conveyorAnimation.value) * _conveyorSpeed * 1000).round(),
        'combo': _combo,
      },
    );

    if (_itemsCompleted % 5 == 0) {
      _levelUp();
    }

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _showNextItem();
    });
  }

  void _handleIncorrectAnswer() {
    _errorController.forward().then((_) => _errorController.reset());
    _audioService.playSound('failure');
    _gameProvider.hapticHeavy();

    setState(() {
      _combo = 0;
      _score = max(0, _score - 50);
      _itemsCompleted++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentItem!.lemma,
      wasCorrect: false,
      metadata: {
        'rule': _currentItem!.rule,
      },
    );

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) _showNextItem();
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
      if (mounted) _showNextItem();
    });
  }

  void _levelUp() {
    setState(() {
      _level++;
      _conveyorSpeed = max(1.5, _conveyorSpeed * 0.85);
      _conveyorController.duration =
          Duration(milliseconds: (_conveyorSpeed * 1000).toInt());
    });
    _audioService.playSound('levelup');
  }

  void _showGameOver() {
    final s = S.of(context);
    if (s == null) return;

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'grossstadt_game',
      difficulty: widget.gradeLevel.index + 1,
      score: _score,
      wasSuccessful:
          _itemsCompleted > 0 && _correctCount * 2 >= _itemsCompleted,
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
            Text(s.gameMaxComboLine(_maxCombo), style: SpaceTheme.bodyStyle),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
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

  // --- UI BUILDING --- (rest of the code stays the same)

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
              Expanded(
                child: _buildGameArea(s, selectedFontFamily),
              ),
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
                _conveyorController.stop();
                Navigator.of(context).pop();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            label: s.semanticsLevel(_level),
            container: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SpaceTheme.nebulaPurple.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5)),
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
            label: s.semanticsScore(_score),
            child: _buildCompactStat(
                Icons.stars, '$_score', SpaceTheme.starYellow),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: s.semanticsProgress(_itemsCompleted, _totalItems),
            child: _buildCompactStat(Icons.check_circle_outline,
                '$_itemsCompleted/$_totalItems', SpaceTheme.cosmicPink),
          ),
          const Spacer(),
          if (_combo > 1)
            Semantics(
              label: s.semanticsCombo(_combo),
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
              s.grossstadtTitle,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: AnimatedBuilder(
            animation: _conveyorAnimation,
            builder: (context, child) {
              return _buildConveyorBelt(selectedFontFamily);
            },
          ),
        ),
        _buildSortingArea(s),
      ],
    );
  }

  Widget _buildConveyorBelt(String selectedFontFamily) {
    if (_currentItem == null) {
      return const SizedBox.shrink();
    }

    final position = _conveyorAnimation.value;

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 100,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  SpaceTheme.nebulaPurple.withValues(alpha: 0.1),
                  SpaceTheme.nebulaPurple,
                  SpaceTheme.nebulaPurple.withValues(alpha: 0.1),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: MediaQuery.of(context).size.width * position - 150,
          top: 50,
          child: _buildMovingItem(selectedFontFamily),
        ),
      ],
    );
  }

  Widget _buildMovingItem(String selectedFontFamily) {
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
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getItemColor(),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _getItemColor().withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        fontFamily: selectedFontFamily,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      children: [
                        TextSpan(text: _currentItem!.prefix.toUpperCase()),
                        TextSpan(
                          text: _currentItem!.target.toUpperCase(),
                          style: TextStyle(
                            color: SpaceTheme.starYellow,
                            decoration: TextDecoration.underline,
                            decorationColor: SpaceTheme.starYellow,
                          ),
                        ),
                        TextSpan(text: _currentItem!.suffix.toUpperCase()),
                      ],
                    ),
                  ),
                  if (_feedbackMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _feedbackState == FeedbackState.correct
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _feedbackMessage,
                              style: TextStyle(
                                fontFamily: selectedFontFamily,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
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

  Color _getItemColor() {
    switch (_feedbackState) {
      case FeedbackState.correct:
        return Colors.green.shade700;
      case FeedbackState.incorrect:
        return SpaceTheme.rocketRed;
      case FeedbackState.none:
        return SpaceTheme.cosmicPink;
    }
  }

  Widget _buildSortingArea(S s) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: _buildSortButton(
              icon: Icons.text_fields,
              label: s.grossstadtCapital,
              color: SpaceTheme.starYellow,
              onTap: () => _handleChoice(true),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildSortButton(
              icon: Icons.text_format,
              label: s.grossstadtLower,
              color: SpaceTheme.nebulaPurple,
              onTap: () => _handleChoice(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: label,
      button: true,
      enabled: _feedbackState == FeedbackState.none,
      child: GestureDetector(
        onTap: _feedbackState == FeedbackState.none ? onTap : null,
        child: AnimatedOpacity(
          opacity: _feedbackState == FeedbackState.none ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 2),
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
                Icon(icon, size: 48, color: Colors.white),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
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
