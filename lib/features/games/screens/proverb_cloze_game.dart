// lib/features/games/screens/proverb_cloze_game.dart
//
// Proverb Cloze (#48) — timed proverb completion game, DE only.
// A German proverb is shown with the key word blanked out;
// the player taps the correct word from 4 options.
// Source: apiEnrichment.proverbs (Wiktionary Sprichwörter).
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
import '../widgets/space_background.dart';
import '../../../shared/widgets/onboarding_overlay.dart';

class ProverbClozeGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const ProverbClozeGame({super.key, required this.gradeLevel});

  @override
  State<ProverbClozeGame> createState() => _ProverbClozeGameState();
}

// ─── data ────────────────────────────────────────────────────────────────────

class _ClozeResult {
  final String before;
  final String after;
  final String matchedForm;
  const _ClozeResult(
      {required this.before, required this.after, required this.matchedForm});
}

class _ProverbChallenge {
  final GermanWord word;
  final String proverb;
  final String before;
  final String after;
  final String matchedForm;
  final List<String> options;
  final int correctIndex;
  const _ProverbChallenge({
    required this.word,
    required this.proverb,
    required this.before,
    required this.after,
    required this.matchedForm,
    required this.options,
    required this.correctIndex,
  });
}

enum _Feedback { none, correct, incorrect }

// ─── state ───────────────────────────────────────────────────────────────────

class _ProverbClozeGameState extends State<ProverbClozeGame>
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

  // Parchment / proverb-scroll palette.
  static const Color _goldAccent = Color(0xFFDAA520);
  static const Color _scrollGold = Color(0xFFc6a700);
  static const Color _scrollPlum = Color(0xFF5f0f40);

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<_ProverbChallenge> _challenges = [];
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

  static _ClozeResult? _tryBlank(String sentence, String target) {
    if (target.isEmpty) return null;
    final ls = sentence.toLowerCase();
    final lt = target.toLowerCase();
    int pos = 0;
    while (pos < ls.length) {
      final idx = ls.indexOf(lt, pos);
      if (idx < 0) return null;
      final end = idx + lt.length;
      final prevOk = idx == 0 || !_isLetter(ls[idx - 1]);
      final nextOk = end >= ls.length || !_isLetter(ls[end]);
      if (prevOk && nextOk) {
        return _ClozeResult(
          before: sentence.substring(0, idx),
          after: sentence.substring(end),
          matchedForm: sentence.substring(idx, end),
        );
      }
      pos = idx + 1;
    }
    return null;
  }

  static int _visibleWordCount(_ClozeResult cloze) =>
      (cloze.before + cloze.after)
          .trim()
          .split(RegExp(r'\s+'))
          .where((w) => w.trim().isNotEmpty)
          .length;

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
        gameKey: 'proverb_cloze',
        title: _s.proverbClozeTitle,
        steps: [
          OnboardingStep(
            icon: Icons.auto_stories,
            body: _s.proverbClozeOnboardingBody,
          ),
          if (_gameProvider.puzzleTimerEnabled)
            OnboardingStep(
              icon: Icons.timer,
              body: _s.proverbClozeOnboardingTimer(_sessionSeconds),
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
            (w.apiEnrichment?.proverbs.isNotEmpty ?? false))
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

    final byType = <GermanWordType, List<String>>{};
    for (final w in allWords) {
      byType.putIfAbsent(w.wordType, () => []).add(w.word);
    }
    for (final list in byType.values) {
      list.shuffle(_rng);
    }
    final allWordStrings = allWords.map((w) => w.word).toList()..shuffle(_rng);

    final challenges = <_ProverbChallenge>[];
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

  _ProverbChallenge? _buildChallenge(
    GermanWord word,
    Map<GermanWordType, List<String>> byType,
    List<String> allWordStrings,
  ) {
    final proverbs = word.apiEnrichment?.proverbs ?? [];

    // Collect all usable (text, cloze) candidates.
    final candidates = <(String, _ClozeResult)>[];
    for (final p in proverbs) {
      final text = p.proverb;
      if (text == null || text.length < 8 || text.length > 120) continue;

      final cloze = _tryBlank(text, word.word);
      if (cloze == null) continue;
      if (_visibleWordCount(cloze) < 2) continue;

      candidates.add((text, cloze));
    }
    if (candidates.isEmpty) return null;

    // C4: the blank is filled by the matched form in the sentence, which can be
    // inflected or archaic, while the options would otherwise be bare lemmas.
    // Prefer proverbs where the matched form equals the lemma so the correct
    // option reads naturally; otherwise we still surface the matched form (not
    // the lemma) as the correct option so it actually fits the gap.
    candidates.sort((a, b) {
      final aExact =
          a.$2.matchedForm.toLowerCase() == word.word.toLowerCase() ? 0 : 1;
      final bExact =
          b.$2.matchedForm.toLowerCase() == word.word.toLowerCase() ? 0 : 1;
      return aExact.compareTo(bExact);
    });

    final (text, cloze) = candidates.first;
    // Use the form that actually appears in the proverb as the correct answer.
    final correctForm = cloze.matchedForm;

    final sameType = byType[word.wordType] ?? [];
    final distractors = <String>[];
    for (final d in [...sameType, ...allWordStrings]) {
      if (distractors.length >= _optionCount - 1) break;
      if (d.toLowerCase() != correctForm.toLowerCase() &&
          d.toLowerCase() != word.word.toLowerCase() &&
          !distractors.any((x) => x.toLowerCase() == d.toLowerCase())) {
        distractors.add(d);
      }
    }
    if (distractors.isEmpty) return null;

    final options = [correctForm, ...distractors.take(_optionCount - 1)];
    options.shuffle(_rng);
    final correctIndex =
        options.indexWhere((o) => o.toLowerCase() == correctForm.toLowerCase());
    if (correctIndex < 0) return null;

    return _ProverbChallenge(
      word: word,
      proverb: text,
      before: cloze.before,
      after: cloze.after,
      matchedForm: cloze.matchedForm,
      options: options,
      correctIndex: correctIndex,
    );
  }

  // ─── timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    if (!_gameProvider.puzzleTimerEnabled) return;
    _timerCtrl.forward(from: 0);
    _runCountdown();
  }

  // Pause the countdown (ticker + progress bar) during the feedback delay so the
  // player isn't penalised for the answer-reveal pause; also keeps it from
  // running once the game is over.
  void _pauseTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _timerCtrl.stop();
  }

  void _resumeTimer() {
    if (!_gameProvider.puzzleTimerEnabled || _gameOver) return;
    if (_secondsLeft <= 0) return;
    // Resume the progress bar from where it left off.
    _timerCtrl.forward(
        from: 1.0 - (_secondsLeft / _sessionSeconds).clamp(0.0, 1.0));
    _runCountdown();
  }

  void _runCountdown() {
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

    // Freeze the session timer during the answer-reveal delay.
    _pauseTimer();

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
        _showGameOver();
        return;
      }
      setState(() {
        _index++;
        _selectedOption = null;
        _feedback = _Feedback.none;
      });
      // Resume the timer once the next proverb is shown.
      _resumeTimer();
    });
  }

  void _showGameOver() {
    if (_gameOver) return;
    _gameOver = true;
    _pauseTimer();

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'proverb_cloze',
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
          _s.proverbClozeEmpty,
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
                _buildProverbCard(challenge),
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
                  _s.proverbClozeTitle,
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  _s.proverbClozeCorrectCount(_correct),
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

  Widget _buildProverbCard(_ProverbChallenge challenge) {
    final borderColor = _feedback == _Feedback.correct
        ? SpaceTheme.alienGreen
        : _feedback == _Feedback.incorrect
            ? Colors.redAccent
            : _goldAccent.withValues(alpha: 0.5);

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
              _scrollGold.withValues(alpha: 0.15),
              _scrollPlum.withValues(alpha: 0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: borderColor,
              width: _feedback != _Feedback.none ? 2.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _s.proverbClozeLabel,
              style: SpaceTheme.bodyStyle.copyWith(
                  color: Colors.white54, fontSize: 11, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),
            _buildProverbRichText(challenge),
            if (_feedback != _Feedback.none) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  challenge.proverb,
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
          ],
        ),
      ),
    );
  }

  Widget _buildProverbRichText(_ProverbChallenge challenge) {
    const blankLabel = '  _____  ';
    final blankColor = _feedback == _Feedback.correct
        ? SpaceTheme.alienGreen
        : _feedback == _Feedback.incorrect
            ? Colors.redAccent
            : _goldAccent;

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
          TextSpan(text: challenge.after),
        ],
      ),
    );
  }

  Widget _buildOptions(_ProverbChallenge challenge) {
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

  Widget _buildOption(_ProverbChallenge challenge, int index) {
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
        selected: isSelected,
        label: challenge.options[index],
        child: GestureDetector(
          onTap: hasAnswered ? null : () => _handleTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
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
