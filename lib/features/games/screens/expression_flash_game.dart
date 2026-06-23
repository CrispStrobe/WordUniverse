// lib/features/games/screens/expression_flash_game.dart
//
// Expression Flash (#45) — timed idiom completion game, DE only.
// A German idiomatic expression is shown with the key word blanked out;
// the player taps the correct word from 4 options.
// Source: apiEnrichment.expressions (Wiktionary Redewendungen).
// DE: ~3 400 words with usable expression entries.
// Session: 30 seconds or 20 rounds, whichever comes first.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../models/game_outcome.dart';
import '../providers/game_provider.dart';
import '../widgets/cefr_chip.dart';
import '../widgets/space_background.dart';
import '../../../shared/widgets/onboarding_overlay.dart';

class ExpressionFlashGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const ExpressionFlashGame({super.key, required this.gradeLevel});

  @override
  State<ExpressionFlashGame> createState() => _ExpressionFlashGameState();
}

// ─── data ────────────────────────────────────────────────────────────────────

class _ClozeResult {
  final String before;
  final String after;
  final String matchedForm;
  const _ClozeResult(
      {required this.before, required this.after, required this.matchedForm});
}

class _ExprChallenge {
  final GermanWord word;
  final String expression; // original full expression text
  final String before;
  final String after;
  final String matchedForm;
  final List<String> options;
  final int correctIndex;
  const _ExprChallenge({
    required this.word,
    required this.expression,
    required this.before,
    required this.after,
    required this.matchedForm,
    required this.options,
    required this.correctIndex,
  });
}

enum _Feedback { none, correct, incorrect }

// ─── state ───────────────────────────────────────────────────────────────────

class _ExpressionFlashGameState extends State<ExpressionFlashGame>
    with TickerProviderStateMixin {
  late VocabularyService _vocabService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;
  late S _s;

  static const int _sessionSeconds = 30;
  static const int _maxRounds = 20;
  static const int _optionCount = 4;
  static const Duration _advanceDelay = Duration(milliseconds: 1300);

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<_ExprChallenge> _challenges = [];
  int _index = 0;
  int _correct = 0;
  int _total = 0;
  int? _selectedOption;
  _Feedback _feedback = _Feedback.none;

  int _secondsLeft = _sessionSeconds;
  Timer? _sessionTimer;
  bool _gameOver = false;

  late AnimationController _pulseCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _timerCtrl;

  final _rng = Random();

  // ─── blank extraction (same word-boundary logic as ClozeFlash) ─────────────

  static bool _isLetter(String ch) =>
      RegExp(r'[a-zA-ZäöüÄÖÜß]').hasMatch(ch);

  static _ClozeResult? _tryBlank(String expression, String target) {
    if (target.isEmpty) return null;
    final le = expression.toLowerCase();
    final lt = target.toLowerCase();
    int pos = 0;
    while (pos < le.length) {
      final idx = le.indexOf(lt, pos);
      if (idx < 0) return null;
      final end = idx + lt.length;
      final prevOk = idx == 0 || !_isLetter(le[idx - 1]);
      final nextOk = end >= le.length || !_isLetter(le[end]);
      if (prevOk && nextOk) {
        return _ClozeResult(
          before: expression.substring(0, idx),
          after: expression.substring(end),
          matchedForm: expression.substring(idx, end),
        );
      }
      pos = idx + 1;
    }
    return null;
  }

  // ─── init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _timerCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: _sessionSeconds));
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    _timerCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    _s = S.of(context)!;
    _vocabService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();

    if (!_vocabService.isInitialized) await _vocabService.initialize();
    _audioService.setTtsLanguage('de');
    _buildChallenges();

    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'expression_flash',
        title: _s.expressionFlashTitle,
        steps: [
          OnboardingStep(
            icon: Icons.format_quote,
            body: _s.expressionFlashOnboardingTap,
          ),
          if (_gameProvider.puzzleTimerEnabled)
            OnboardingStep(
              icon: Icons.timer,
              body: _s.expressionFlashOnboardingTimer,
            ),
        ],
      );
    }
  }

  void _buildChallenges() {
    final allWords = _vocabService
        .getAllWords(_gameProvider)
        .where((w) =>
            !w.isProperNoun &&
            !w.word.contains('_') &&
            !w.word.contains(' ') &&
            (w.apiEnrichment?.expressions.isNotEmpty ?? false))
        .toList();

    if (allWords.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final gradePool = allWords
        .where((w) => w.gradeLevel == widget.gradeLevel.index + 1)
        .toList();
    final pool = gradePool.length >= 10 ? gradePool : allWords;
    pool.shuffle(_rng);

    // Separate same-type pools for distractor selection
    final byType = <GermanWordType, List<String>>{};
    for (final w in allWords) {
      byType.putIfAbsent(w.wordType, () => []).add(w.word);
    }
    for (final list in byType.values) {
      list.shuffle(_rng);
    }
    final allWordStrings = allWords.map((w) => w.word).toList()..shuffle(_rng);

    final challenges = <_ExprChallenge>[];
    for (final word in pool) {
      if (challenges.length >= _maxRounds) break;
      final c = _buildChallenge(word, byType, allWordStrings);
      if (c != null) challenges.add(c);
    }

    setState(() {
      _challenges = challenges;
      _index = 0;
      _correct = 0;
      _total = 0;
      _selectedOption = null;
      _feedback = _Feedback.none;
      _gameOver = false;
      _secondsLeft = _sessionSeconds;
      _isLoading = false;
    });

    _startTimer();
  }

  _ExprChallenge? _buildChallenge(
    GermanWord word,
    Map<GermanWordType, List<String>> byType,
    List<String> allWordStrings,
  ) {
    final expressions = word.apiEnrichment?.expressions ?? [];

    // Prefer expressions where the matched (blanked) form equals the lemma —
    // those let the player pick exactly the word being practised. Fall back to
    // inflected matches, where we present the matched form itself as the answer.
    final ordered = <MapEntry<String, _ClozeResult>>[];
    final inflected = <MapEntry<String, _ClozeResult>>[];
    for (final expr in expressions) {
      final text = expr.expression;
      if (text == null || text.length < 8 || text.length > 80) continue;
      final cloze = _tryBlank(text, word.word);
      if (cloze == null) continue;
      final entry = MapEntry(text, cloze);
      if (cloze.matchedForm.toLowerCase() == word.word.toLowerCase()) {
        ordered.add(entry);
      } else {
        inflected.add(entry);
      }
    }

    for (final entry in [...ordered, ...inflected]) {
      final text = entry.key;
      final cloze = entry.value;

      // Require at least 2 other words still visible around the blank
      final visible = (cloze.before + cloze.after)
          .split(' ')
          .where((w) => w.trim().isNotEmpty)
          .length;
      if (visible < 2) continue;

      // The correct answer is the exact form that was blanked out, so it
      // matches the gap (lemma when uninflected, inflected form otherwise).
      final answer = cloze.matchedForm;
      final visibleText = (cloze.before + cloze.after).toLowerCase();

      // Distractors: prefer same word type, fall back to any word.
      // Exclude the answer and anything already visible in the expression.
      final sameType = byType[word.wordType] ?? [];
      final distractors = <String>[];
      for (final d in [...sameType, ...allWordStrings]) {
        if (distractors.length >= _optionCount - 1) break;
        final ld = d.toLowerCase();
        if (ld == answer.toLowerCase()) continue;
        if (visibleText.contains(ld)) continue;
        if (distractors.any((x) => x.toLowerCase() == ld)) continue;
        distractors.add(d);
      }
      if (distractors.length < _optionCount - 1) continue; // need a full set

      final options = [answer, ...distractors.take(_optionCount - 1)];
      options.shuffle(_rng);
      final correctIndex =
          options.indexWhere((o) => o.toLowerCase() == answer.toLowerCase());
      if (correctIndex < 0) continue;

      return _ExprChallenge(
        word: word,
        expression: text,
        before: cloze.before,
        after: cloze.after,
        matchedForm: cloze.matchedForm,
        options: options,
        correctIndex: correctIndex,
      );
    }
    return null;
  }

  // ─── timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    if (!_gameProvider.puzzleTimerEnabled) return;
    _timerCtrl.forward(from: 0);
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = _secondsLeft - 1;
      if (left <= 0) {
        t.cancel();
        setState(() => _secondsLeft = 0);
        _showGameOver();
      } else {
        setState(() => _secondsLeft = left);
      }
    });
  }

  // ─── interaction ───────────────────────────────────────────────────────────

  void _handleTap(int index) {
    if (_feedback != _Feedback.none || _gameOver) return;
    if (_index >= _challenges.length) return;

    final challenge = _challenges[_index];
    final isCorrect = index == challenge.correctIndex;

    setState(() {
      _selectedOption = index;
      _feedback = isCorrect ? _Feedback.correct : _Feedback.incorrect;
      _total++;
    });

    if (isCorrect) {
      _gameProvider.hapticLight();
      _audioService.playSound('success');
      _pulseCtrl.forward(from: 0);
      _correct++;
      _sriService.recordResponse(
        skillType: LanguageSkillType.reading,
        baseWord: challenge.word.word,
        wasCorrect: true,
      );
    } else {
      _gameProvider.hapticMedium();
      _audioService.playSound('error');
      _shakeCtrl.forward(from: 0).then((_) => _shakeCtrl.reverse());
      _sriService.recordResponse(
        skillType: LanguageSkillType.reading,
        baseWord: challenge.word.word,
        wasCorrect: false,
      );
    }

    Future.delayed(_advanceDelay, () {
      if (!mounted || _gameOver) return;
      if (_index + 1 >= _challenges.length) {
        _sessionTimer?.cancel();
        _showGameOver();
        return;
      }
      setState(() {
        _index++;
        _selectedOption = null;
        _feedback = _Feedback.none;
      });
    });
  }

  void _showGameOver() {
    if (_gameOver) return;
    _gameOver = true;
    _sessionTimer?.cancel();

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'expression_flash',
      difficulty: widget.gradeLevel.index + 1,
      score: _correct * 10,
      wasSuccessful: _total > 0 && (_correct / _total) >= 0.7,
    ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_s.gameOver, style: SpaceTheme.headlineStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_correct / $_total',
              style: SpaceTheme.titleStyle
                  .copyWith(color: SpaceTheme.starYellow, fontSize: 32),
            ),
            const SizedBox(height: 4),
            if (_gameProvider.puzzleTimerEnabled)
              Text(
                _s.correctInSeconds(_sessionSeconds - _secondsLeft),
                style: SpaceTheme.bodyStyle.copyWith(color: Colors.white70),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text(_s.backToMenu),
          ),
          ElevatedButton(
            autofocus: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              _buildChallenges();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: SpaceTheme.planetOrange),
            child: Text(_s.playAgain),
          ),
        ],
      ),
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _challenges.isEmpty
                  ? _buildEmptyState()
                  : _buildGame(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _s.expressionFlashEmpty,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildGame() {
    final challenge = _challenges[_index];
    return Column(
      children: [
        _buildHeader(),
        if (_gameProvider.puzzleTimerEnabled) _buildTimerBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                _buildExpressionCard(challenge),
                const SizedBox(height: 20),
                _buildOptions(challenge),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () {
              _sessionTimer?.cancel();
              Navigator.of(context).pop();
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s.expressionFlashTitle,
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  _s.expressionFlashCorrectCount(_correct),
                  style: SpaceTheme.bodyStyle.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          if (_gameProvider.puzzleTimerEnabled)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _secondsLeft <= 5
                      ? SpaceTheme.rocketRed
                      : SpaceTheme.starYellow,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  '$_secondsLeft',
                  style: TextStyle(
                    color: _secondsLeft <= 5
                        ? SpaceTheme.rocketRed
                        : SpaceTheme.starYellow,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimerBar() {
    return AnimatedBuilder(
      animation: _timerCtrl,
      builder: (_, __) {
        final progress = 1.0 - _timerCtrl.value;
        final color = progress > 0.4
            ? SpaceTheme.alienGreen
            : progress > 0.2
                ? SpaceTheme.planetOrange
                : SpaceTheme.rocketRed;
        return LinearProgressIndicator(
          value: progress,
          backgroundColor: SpaceTheme.moonSilver.withValues(alpha: 0.2),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 4,
        );
      },
    );
  }

  Widget _buildExpressionCard(_ExprChallenge challenge) {
    final borderColor = _feedback == _Feedback.correct
        ? SpaceTheme.alienGreen
        : _feedback == _Feedback.incorrect
            ? Colors.redAccent
            : SpaceTheme.nebulaPurple.withValues(alpha: 0.5);

    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(
          _feedback == _Feedback.incorrect
              ? sin(_shakeCtrl.value * pi * 6) * 6
              : 0,
          0,
        ),
        child: child,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              SpaceTheme.nebulaPurple.withValues(alpha: 0.6),
              SpaceTheme.deepSpace.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor,
              width: _feedback != _Feedback.none ? 2.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _s.expressionFlashLabel,
              style: SpaceTheme.bodyStyle.copyWith(
                  color: Colors.white54, fontSize: 11, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),
            _buildExpressionRichText(challenge),
            if (_feedback != _Feedback.none) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  challenge.expression,
                  style: SpaceTheme.bodyStyle.copyWith(
                    color: _feedback == _Feedback.correct
                        ? SpaceTheme.alienGreen
                        : Colors.redAccent.shade100,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            if (challenge.word.cefrLevel != null) ...[
              const SizedBox(height: 8),
              CefrChip(challenge.word.cefrLevel!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpressionRichText(_ExprChallenge challenge) {
    const blankLabel = '  _____  ';
    final blankColor = _feedback == _Feedback.correct
        ? SpaceTheme.alienGreen
        : _feedback == _Feedback.incorrect
            ? Colors.redAccent
            : const Color(0xFF2193b0);

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
        children: [
          TextSpan(text: challenge.before),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Semantics(
              label: _s.expressionFlashBlankHint,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: blankColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: blankColor, width: 1.5),
                ),
                child: Text(
                  blankLabel,
                  style: TextStyle(
                    color: blankColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
          TextSpan(text: challenge.after),
        ],
      ),
    );
  }

  Widget _buildOptions(_ExprChallenge challenge) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3.0,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(challenge.options.length, (i) {
        return _buildOption(challenge, i);
      }),
    );
  }

  Widget _buildOption(_ExprChallenge challenge, int index) {
    final isCorrect = index == challenge.correctIndex;
    final isSelected = _selectedOption == index;
    final hasAnswered = _feedback != _Feedback.none;

    Color border = SpaceTheme.moonSilver.withValues(alpha: 0.4);
    Color bg = SpaceTheme.deepSpace.withValues(alpha: 0.6);
    Color text = Colors.white;

    if (hasAnswered) {
      if (isCorrect) {
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.25);
        text = Colors.green.shade200;
      } else if (isSelected) {
        border = Colors.redAccent;
        bg = Colors.red.withValues(alpha: 0.2);
        text = Colors.redAccent;
      }
    }

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, child) => Transform.scale(
        scale:
            hasAnswered && isCorrect ? 1.0 + (_pulseCtrl.value * 0.04) : 1.0,
        child: child,
      ),
      child: Semantics(
        button: true,
        enabled: !hasAnswered,
        label: challenge.options[index],
        child: GestureDetector(
          onTap: hasAnswered ? null : () => _handleTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              challenge.options[index],
              style: TextStyle(
                  color: text, fontSize: 15, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
