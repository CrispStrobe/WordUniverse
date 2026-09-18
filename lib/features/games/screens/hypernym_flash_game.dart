// lib/features/games/screens/hypernym_flash_game.dart

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/word_features.dart';
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

class HypernymFlashGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const HypernymFlashGame({super.key, required this.gradeLevel});

  @override
  State<HypernymFlashGame> createState() => _HypernymFlashGameState();
}

class _HypernymChallenge {
  final GermanWord word;
  final String correctHypernym;
  final List<String> options;
  final int correctIndex;
  const _HypernymChallenge({
    required this.word,
    required this.correctHypernym,
    required this.options,
    required this.correctIndex,
  });
}

enum _Feedback { none, correct, incorrect }

class _HypernymFlashGameState extends State<HypernymFlashGame>
    with TickerProviderStateMixin {
  late VocabularyService _vocabService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;
  late S _s;

  static const int _sessionSeconds = 30;
  static const int _maxRounds = 20;
  static const int _optionCount = 4;
  static const Duration _advanceDelay = Duration(milliseconds: 1100);

  static const Set<String> _abstractENVerbs = {
    'be', 'have', 'do', 'exist', 'become', 'get', 'make', 'take', 'go',
    'come', 'give', 'use', 'find', 'think', 'see', 'know', 'want', 'seem',
    'put', 'move', 'change', 'live', 'try', 'apply', 'act', 'work', 'play',
    'bring', 'keep', 'turn', 'show', 'leave', 'feel', 'follow', 'need',
    'run', 'call', 'look', 'set', 'hold', 'start', 'stop', 'stay', 'begin',
    'appear', 'happen',
  };

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<_HypernymChallenge> _challenges = [];
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

  bool get _isDE => _vocabService.learningLanguage == 'de';

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
    _audioService.setTtsLanguage(_vocabService.learningLanguage);
    _buildChallenges();
    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'hypernym_flash',
        title: _s.hypernymFlashTitle,
        steps: [
          OnboardingStep(
            icon: Icons.category,
            body: _s.hypernymFlashOnboardingBody1,
          ),
          if (_gameProvider.puzzleTimerEnabled)
            OnboardingStep(
              icon: Icons.timer,
              body: _s.synonymFlashOnboardingTimer,
            ),
        ],
      );
    }
  }

  bool _isClean(String w, bool isDE) {
    if (w.length < 3) return false;
    final tokens = w.split(' ');
    if (tokens.length > 2) return false;
    if (!isDE && _abstractENVerbs.contains(w.toLowerCase())) return false;
    return true;
  }

  String? _pickHypernym(GermanWord word) {
    final isDE = _isDE;
    final hypernyms = word.apiEnrichment?.hypernyms ?? [];
    for (final h in hypernyms) {
      final w = (h.word ?? '').trim();
      if (_isClean(w, isDE)) return w;
    }
    return null;
  }

  Future<void> _buildChallenges() async {
    // Only words the feature index says carry hypernyms are read back with
    // their enrichment; choosing *which* hypernym still needs the real data.
    final candidates = await _vocabService.takeWordsWithFeature(
      WordFeature.hypernyms,
      settingsProvider: _gameProvider,
      gradeLevel: widget.gradeLevel.index + 1,
      limit: 200,
      where: (w) =>
          !w.isProperNoun && !w.word.contains('_') && !w.word.contains(' '),
      random: _rng,
    );
    if (!mounted) return;

    // Compute the chosen hypernym once per word and reuse it everywhere
    // (filter, distractor pool, and challenge build) instead of recomputing.
    final picked = <GermanWord, String>{};
    for (final w in candidates) {
      final h = _pickHypernym(w);
      if (h != null) picked[w] = h;
    }
    final allWords = picked.keys.toList();

    if (allWords.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // Already grade-first and shuffled by the pool query.
    final pool = allWords;

    final hypernymPool = picked.values.toList();
    hypernymPool.shuffle(_rng);

    final challenges = <_HypernymChallenge>[];
    for (final word in pool) {
      if (challenges.length >= _maxRounds) break;
      final c = _buildChallenge(word, picked[word]!, hypernymPool);
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

  _HypernymChallenge? _buildChallenge(
      GermanWord word, String correct, List<String> hypernymPool) {
    // Exclude EVERY hypernym of this word from the distractor pool, not just
    // the chosen `correct` — a word often has several valid hypernyms, and any
    // of them appearing as a "wrong" option would actually be correct.
    final ownHypernyms = (word.apiEnrichment?.hypernyms ?? [])
        .map((h) => (h.word ?? '').trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();

    final distractors = <String>[];
    for (final h in hypernymPool) {
      if (distractors.length >= _optionCount - 1) break;
      final hl = h.toLowerCase();
      if (!ownHypernyms.contains(hl) &&
          !distractors.any((d) => d.toLowerCase() == hl)) {
        distractors.add(h);
      }
    }
    if (distractors.isEmpty) return null;

    final options = [correct, ...distractors.take(_optionCount - 1)];
    options.shuffle(_rng);
    final correctIndex =
        options.indexWhere((o) => o.toLowerCase() == correct.toLowerCase());
    if (correctIndex < 0) return null;

    return _HypernymChallenge(
      word: word,
      correctHypernym: correct,
      options: options,
      correctIndex: correctIndex,
    );
  }

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
        skillType: LanguageSkillType.vocabulary,
        baseWord: challenge.word.word,
        wasCorrect: true,
      );
    } else {
      _gameProvider.hapticMedium();
      _audioService.playSound('error');
      _shakeCtrl.forward(from: 0).then((_) => _shakeCtrl.reverse());
      _sriService.recordResponse(
        skillType: LanguageSkillType.vocabulary,
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
      gameType: 'hypernym_flash',
      difficulty: widget.gradeLevel.index + 1,
      score: _correct * 10,
      wasSuccessful: _total > 0 && (_correct / _total) >= 0.7,
    ));

    if (!mounted) return;
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

  // ─── UI ──────────────────────────────────────────────────────────────────

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
          _s.noHypernymData,
          style: SpaceTheme.bodyStyle,
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
                _buildWordCard(challenge),
                const SizedBox(height: 24),
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
                  _s.hypernymFlashTitle,
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  '$_correct ${_s.correct}',
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

  Widget _buildWordCard(_HypernymChallenge challenge) {
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF7F00FF).withValues(alpha: 0.5),
              SpaceTheme.deepSpace.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _feedback == _Feedback.correct
                ? SpaceTheme.alienGreen
                : _feedback == _Feedback.incorrect
                    ? Colors.redAccent
                    : const Color(0xFF7F00FF).withValues(alpha: 0.5),
            width: _feedback != _Feedback.none ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              _s.hypernymFlashPrompt,
              style: SpaceTheme.bodyStyle.copyWith(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              challenge.word.word,
              style: SpaceTheme.headlineStyle.copyWith(
                fontSize: 34,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (challenge.word.cefrLevel != null) ...[
              const SizedBox(height: 8),
              CefrChip(challenge.word.cefrLevel!),
            ],
            if (_feedback != _Feedback.none) ...[
              const SizedBox(height: 10),
              Text(
                challenge.correctHypernym,
                style: SpaceTheme.bodyStyle.copyWith(
                  color: Colors.white70,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptions(_HypernymChallenge challenge) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3.2,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(challenge.options.length, (i) {
        return _buildOption(challenge, i);
      }),
    );
  }

  Widget _buildOption(_HypernymChallenge challenge, int index) {
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
        scale: hasAnswered && isCorrect
            ? 1.0 + (_pulseCtrl.value * 0.04)
            : 1.0,
        child: child,
      ),
      child: Semantics(
        button: true,
        label: challenge.options[index],
        child: GestureDetector(
          onTap: hasAnswered ? null : () => _handleTap(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
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
      ),
    );
  }
}
