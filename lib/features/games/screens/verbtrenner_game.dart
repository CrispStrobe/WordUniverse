// ignore_for_file: unused_element, unused_field
// lib/features/games/screens/trennbare_verben_game.dart
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

/// Trennbare Verben Game - Teaching German separable prefix verb rules
/// Players decide if verb parts should be ZUSAMMEN (together) or GETRENNT (separated)
class VerbtrennerGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const VerbtrennerGame({super.key, required this.gradeLevel});

  @override
  State<VerbtrennerGame> createState() => _VerbtrennerGameState();
}

/// Represents a single word pair challenge
class VerbPair {
  final String part1; // e.g., "stehe" or empty for infinitives
  final String part2; // e.g., "auf" or "aufstehen"
  final bool shouldBeSeparated; // true = GETRENNT, false = ZUSAMMEN
  final String context; // Example sentence
  final String explanation; // Rule explanation
  final int difficulty; // 1-3
  final String wordId; // For SRI tracking
  final String formText; // Original form from Wiktionary

  VerbPair({
    required this.part1,
    required this.part2,
    required this.shouldBeSeparated,
    required this.context,
    required this.explanation,
    required this.difficulty,
    required this.wordId,
    required this.formText,
  });
}

enum FeedbackState { none, correct, incorrect }

class _VerbtrennerGameState extends State<VerbtrennerGame>
    with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  final List<VerbPair> _pairQueue = [];
  VerbPair? _currentPair;
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
  double _fallingSpeed = 5.0; // seconds per item

  // Feedback
  FeedbackState _feedbackState = FeedbackState.none;
  Timer? _feedbackTimer;
  String _feedbackMessage = '';

  // Effects
  late AnimationController _successController;
  late AnimationController _errorController;

  // Separable prefixes (comprehensive list)
  static const _separablePrefixes = [
    'ab', 'an', 'auf', 'aus', 'bei', 'ein', 'empor', 'fest',
    'fort', 'her', 'hin', 'los', 'mit', 'nach', 'nieder',
    'vor', 'weg', 'weiter', 'zu', 'zurecht', 'zurück', 'zusammen'
  ];

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
    _feedbackTimer?.cancel();
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

    _generatePairQueue();
    _showNextPair();

    setState(() => _isLoading = false);
  }

  /// Generate verb pairs from vocabulary data
  void _generatePairQueue() {
    _pairQueue.clear();

    // Get all verbs at appropriate grade level
    final verbs = _vocabularyService
        .getAllWords(_gameProvider)
        .where((w) =>
            w.wordType == GermanWordType.verb &&
            w.gradeLevel <= widget.gradeLevel.index + 3) // Slightly above grade
        .toList();

    if (kDebugMode) debugPrint('[TRENNBARE VERBEN] Found ${verbs.length} verbs to check');

    // Process each verb to find separable ones
    for (final verb in verbs) {
      if (_isVerbSeparable(verb)) {
        final pairs = _generatePairsFromVerb(verb);
        _pairQueue.addAll(pairs);
      }
    }

    // Shuffle and limit
    _pairQueue.shuffle();
    if (_pairQueue.length > _totalItems) {
      _pairQueue.removeRange(_totalItems, _pairQueue.length);
    }

    if (kDebugMode) debugPrint('[TRENNBARE VERBEN] Generated ${_pairQueue.length} verb pairs');
  }

  /// Check if a verb is separable based on Wiktionary inflections
  bool _isVerbSeparable(GermanWord word) {
    final inflections = word.apiEnrichment?.inflections ?? [];

    for (final form in inflections) {
      final formText = form['form_text'] as String?;
      if (formText == null) continue;

      // Check for separated forms (e.g., "stehe auf")
      if (formText.contains(' ')) {
        final parts = formText.split(' ');
        if (parts.length == 2 && _isSeparablePrefix(parts[1])) {
          return true;
        }
      }
    }

    return false;
  }

  bool _isSeparablePrefix(String prefix) {
    return _separablePrefixes.contains(prefix.toLowerCase());
  }

  /// Generate all rule-based pairs from a separable verb.
  /// Only generates a VerbPair when a real example sentence is available.
  List<VerbPair> _generatePairsFromVerb(GermanWord word) {
  final pairs = <VerbPair>[];
  final inflections = word.apiEnrichment?.inflections ?? [];
  final apiExamples = word.apiEnrichment?.examples ?? [];
  final tataoebaExamples = word.exampleSentences;

  final String infinitive = word.word;
  String prefix = '';

  for (final form in inflections) {
    final formText = form['form_text'] as String?;
    if (formText != null && formText.contains(' ')) {
      final parts = formText.split(' ');
      if (parts.length == 2 && _isSeparablePrefix(parts[1])) {
        prefix = parts[1];
        break;
      }
    }
  }

  if (prefix.isEmpty) return pairs;

  for (final form in inflections) {
    final formText = form['form_text'] as String?;
    final tags = form['tags'] as String?;
    if (formText == null || tags == null) continue;

    // RULE 1: Present/Past tense (conjugated) → GETRENNT
    if ((tags.contains('present') || tags.contains('past')) &&
        !tags.contains('participle') &&
        !tags.contains('infinitive') &&
        formText.contains(' ')) {
      final parts = formText.split(' ');
      if (parts.length == 2) {
        final context = _findRealExample(
          apiExamples: apiExamples,
          tataoebaExamples: tataoebaExamples,
          formText: formText,
        );
        if (context == null) continue;
        pairs.add(VerbPair(
          part1: parts[0],
          part2: parts[1],
          shouldBeSeparated: true,
          context: context,
          explanation: 'Konjugierte Form im Hauptsatz → getrennt',
          difficulty: 2,
          wordId: word.id,
          formText: formText,
        ));
      }
    }

    // RULE 2: Extended infinitive with "zu"
    if (tags.contains('extended') && tags.contains('infinitive')) {
      final context = _findRealExample(
        apiExamples: apiExamples,
        tataoebaExamples: tataoebaExamples,
        formText: formText,
      );
      if (context == null) continue;
      final hasSpaces = formText.contains(' ');
      final String part1, part2;
      if (hasSpaces) {
        final lastSpace = formText.lastIndexOf(' ');
        part1 = formText.substring(0, lastSpace);
        part2 = formText.substring(lastSpace + 1);
      } else {
        part1 = prefix;
        part2 = formText.substring(prefix.length);
      }
      pairs.add(VerbPair(
        part1: part1,
        part2: part2,
        shouldBeSeparated: hasSpaces,
        context: context,
        explanation: hasSpaces
            ? 'Infinitiv mit Hilfsverb (zu haben/sein) → getrennt'
            : 'zu-Infinitiv (ein Wort) → zusammen',
        difficulty: 3,
        wordId: word.id,
        formText: formText,
      ));
    }

    // RULE 3: Plain infinitive → ZUSAMMEN
    if (tags.contains('infinitive') &&
        !tags.contains('extended') &&
        formText == infinitive) {
      final context = _findRealExample(
        apiExamples: apiExamples,
        tataoebaExamples: tataoebaExamples,
        formText: formText,
      );
      if (context == null) continue;
      pairs.add(VerbPair(
        part1: prefix,
        part2: formText.substring(prefix.length),
        shouldBeSeparated: false,
        context: context,
        explanation: 'Infinitiv nach Modalverb → zusammen',
        difficulty: 1,
        wordId: word.id,
        formText: formText,
      ));
    }

    // RULE 4: Past participle → ZUSAMMEN
    if (tags.contains('participle') && tags.contains('perfect')) {
      final context = _findRealExample(
        apiExamples: apiExamples,
        tataoebaExamples: tataoebaExamples,
        formText: formText,
      );
      if (context == null) continue;
      pairs.add(VerbPair(
        part1: prefix,
        part2: formText.substring(prefix.length),
        shouldBeSeparated: false,
        context: context,
        explanation: 'Partizip Perfekt → zusammen',
        difficulty: 2,
        wordId: word.id,
        formText: formText,
      ));
    }
  }

  return pairs;
}

  /// Returns a real example sentence containing [formText], or any real sentence
  /// from the word's examples if no exact match exists. Returns null only when
  /// the word has no example sentences at all.
  String? _findRealExample({
    required List<ApiExample> apiExamples,
    required List<String> tataoebaExamples,
    required String formText,
  }) {
    // Prefer exact-match examples (sentence contains the specific inflected form)
    for (final ex in apiExamples) {
      final text = ex.text;
      if (text != null && text.isNotEmpty && text.contains(formText)) return text;
    }
    for (final text in tataoebaExamples) {
      if (text.isNotEmpty && text.contains(formText)) return text;
    }
    // Fall back to any real sentence — still better than a fabricated template
    for (final ex in apiExamples) {
      final text = ex.text;
      if (text != null && text.isNotEmpty) return text;
    }
    for (final text in tataoebaExamples) {
      if (text.isNotEmpty) return text;
    }
    return null;
  }


  void _showNextPair() {
    if (_itemsCompleted >= _totalItems || _pairQueue.isEmpty) {
      _showGameOver();
      return;
    }

    setState(() {
      _currentPair = _pairQueue.removeAt(0);
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

  void _handleChoice(bool chooseSeparated) {
    if (_currentPair == null || _feedbackState != FeedbackState.none) return;

    _fallingController.stop();
    final isCorrect = chooseSeparated == _currentPair!.shouldBeSeparated;

    setState(() {
      _feedbackState = isCorrect ? FeedbackState.correct : FeedbackState.incorrect;
      _feedbackMessage = _currentPair!.explanation;
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

    final basePoints = 100 + (_currentPair!.difficulty * 25);
    final comboMultiplier = 1.0 + (_combo / 10);
    final points = (basePoints * comboMultiplier).round();

    setState(() {
      _score += points;
      _itemsCompleted++;
    });

    // FIX: Use spelling
    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentPair!.formText,
      wasCorrect: true,
      metadata: {
        'wordId': _currentPair!.wordId,
        'responseTimeMs': ((1.0 - _fallingAnimation.value) * _fallingSpeed * 1000).round(),
        'combo': _combo
      },
    );

    if (_itemsCompleted % 5 == 0) {
      _levelUp();
    }

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _showNextPair();
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

    // FIX: Use spelling
    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentPair!.formText,
      wasCorrect: false,
      metadata: {
        'wordId': _currentPair!.wordId,
      },
    );

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) _showNextPair();
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
      if (mounted) _showNextPair();
    });
  }

  void _levelUp() {
    setState(() {
      _level++;
      _fallingSpeed = max(2.0, _fallingSpeed * 0.88);
      _fallingController.duration = Duration(milliseconds: (_fallingSpeed * 1000).toInt());
    });

    _audioService.playSound('levelup');
  }

  void _showGameOver() {
    final s = S.of(context);
    if (s == null) return;

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'verbtrenner_game',
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
        content: Text('${s.gameScore}: $_score', style: SpaceTheme.bodyStyle),
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
            // FIX: Use gameDone
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
          // Back button
          Semantics(
            label: 'Zurück',
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
          // Level
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
          // Score
          Semantics(
            label: 'Punkte: $_score',
            child: _buildCompactStat(Icons.stars, '$_score', SpaceTheme.starYellow),
          ),
          const SizedBox(width: 8),
          // Progress
          Semantics(
            label: 'Fortschritt: $_itemsCompleted von $_totalItems',
            child: _buildCompactStat(Icons.check_circle_outline, '$_itemsCompleted/$_totalItems', SpaceTheme.cosmicPink),
          ),
          const Spacer(),
          // Combo (Replacing Timer slot)
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
              s.verbtrennerSeparableTitle,
              // FIX: headerStyle -> headlineStyle
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 18),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: AnimatedBuilder(
            animation: _fallingAnimation,
            builder: (context, child) => _buildFallingVerb(selectedFontFamily),
          ),
        ),
        _buildChoiceButtons(s),
      ],
    );
  }

  Widget _buildFallingVerb(String selectedFontFamily) {
    if (_currentPair == null) return const SizedBox.shrink();

    final screenHeight = MediaQuery.of(context).size.height - 400;
    final position = screenHeight * _fallingAnimation.value;

    return Stack(
        children: [
        // Visual guide line
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

        // Falling verb parts - ALWAYS show as two parts
        Positioned(
            left: 0,
            right: 0,
            top: position,
            child: _buildDoubleParts(selectedFontFamily),
        ),
        ],
    );
    }

  Widget _buildVerbParts(String selectedFontFamily) {
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
            // ALWAYS show as double parts
            child: _buildDoubleParts(selectedFontFamily),
            ),
        );
        },
    );
    }

  Widget _buildSinglePart(String selectedFontFamily) {
    // For infinitives and participles (shown as single unit)
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _getPartColor(),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 3),
          boxShadow: [
            BoxShadow(
              color: _getPartColor().withValues(alpha: 0.5),
              blurRadius: 25,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currentPair!.part2,
              style: TextStyle(
                fontFamily: selectedFontFamily,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _currentPair!.context,
              style: TextStyle(
                fontFamily: selectedFontFamily,
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
            if (_feedbackMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDoubleParts(String selectedFontFamily) {
    // ALWAYS show two parts with context and feedback below
    return Center(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
                // Part 1
                Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: _getPartColor(),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                    boxShadow: [
                    BoxShadow(
                        color: _getPartColor().withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                    ),
                    ],
                ),
                child: Text(
                    _currentPair!.part1,
                    style: TextStyle(
                    fontFamily: selectedFontFamily,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    ),
                ),
                ),

                // Gap indicator
                Container(
                width: 80,
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                ),
                ),

                // Part 2
                Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: _getPartColor(),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                    boxShadow: [
                    BoxShadow(
                        color: _getPartColor().withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                    ),
                    ],
                ),
                child: Text(
                    _currentPair!.part2,
                    style: TextStyle(
                    fontFamily: selectedFontFamily,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    ),
                ),
                ),
            ],
            ),
            
            // Context and feedback below the parts
            const SizedBox(height: 24),
            Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
                children: [
                Text(
                    _currentPair!.context,
                    style: TextStyle(
                    fontFamily: selectedFontFamily,
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.9),
                    ),
                    textAlign: TextAlign.center,
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
                ],
                ],
            ),
            ),
        ],
        ),
    );
    }

  Color _getPartColor() {
    switch (_feedbackState) {
      case FeedbackState.correct:
        return Colors.green.shade700;
      case FeedbackState.incorrect:
        return SpaceTheme.rocketRed;
      case FeedbackState.none:
        return SpaceTheme.cosmicPink;
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
              subtitle: s.verbtrennerSeparatedExample,
              color: SpaceTheme.nebulaPurple,
              onTap: () => _handleChoice(true),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildChoiceButton(
              icon: Icons.link,
              label: s.verbtrennerTogetherLabel,
              subtitle: s.verbtrennerTogetherExample,
              color: SpaceTheme.starYellow,
              onTap: () => _handleChoice(false),
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
            height: 140,
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
                Icon(icon, size: 42, color: Colors.white),
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
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
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