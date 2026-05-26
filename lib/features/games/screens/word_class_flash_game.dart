import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class WordClassFlashGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WordClassFlashGame({super.key, required this.gradeLevel});

  @override
  State<WordClassFlashGame> createState() => _WordClassFlashGameState();
}

class _WordClassChallenge {
  final GermanWord word;
  final GermanWordType correctType;
  const _WordClassChallenge({required this.word, required this.correctType});
}

enum _Feedback { none, correct, incorrect }

class _WordClassFlashGameState extends State<WordClassFlashGame>
    with TickerProviderStateMixin {
  late VocabularyService _vocabService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;
  late S _s;

  static const int _sessionSeconds = 30;
  static const int _maxRounds = 20;
  static const Duration _advanceDelay = Duration(milliseconds: 1100);

  static const _types = [
    GermanWordType.substantiv,
    GermanWordType.verb,
    GermanWordType.adjektiv,
    GermanWordType.adverb,
  ];

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<_WordClassChallenge> _challenges = [];
  int _index = 0;
  int _correct = 0;
  int _total = 0;
  GermanWordType? _selectedType;
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
      final isDE = _isDE;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'word_class_flash',
        title: isDE ? 'Wortart-Blitz' : 'Word Class Flash',
        steps: [
          OnboardingStep(
            icon: Icons.label_outline,
            body: isDE
                ? 'Ein Wort erscheint — tippe schnell auf seine Wortart.'
                : 'A word appears — tap its word class as fast as you can.',
          ),
          OnboardingStep(
            icon: Icons.timer,
            body: isDE
                ? 'Du hast 30 Sekunden. Nomen, Verb, Adjektiv oder Adverb?'
                : 'You have 30 seconds. Noun, Verb, Adjective or Adverb?',
          ),
          OnboardingStep(
            icon: Icons.tips_and_updates,
            body: isDE
                ? 'Entscheide nach Bedeutung und Form des Wortes.'
                : 'Think about the word\'s meaning and form.',
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
            _types.contains(w.wordType))
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

    final challenges = pool
        .take(_maxRounds)
        .map((w) => _WordClassChallenge(word: w, correctType: w.wordType))
        .toList();

    setState(() {
      _challenges = challenges;
      _index = 0;
      _correct = 0;
      _total = 0;
      _selectedType = null;
      _feedback = _Feedback.none;
      _gameOver = false;
      _secondsLeft = _sessionSeconds;
      _isLoading = false;
    });

    _startTimer();
  }

  void _startTimer() {
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

  void _handleTap(GermanWordType tapped) {
    if (_feedback != _Feedback.none || _gameOver) return;
    if (_index >= _challenges.length) return;

    final challenge = _challenges[_index];
    final isCorrect = tapped == challenge.correctType;

    setState(() {
      _selectedType = tapped;
      _feedback = isCorrect ? _Feedback.correct : _Feedback.incorrect;
      _total++;
    });

    if (isCorrect) {
      HapticFeedback.lightImpact();
      _audioService.playSound('success');
      _pulseCtrl.forward(from: 0);
      _correct++;
      _sriService.recordResponse(
        skillType: LanguageSkillType.wordType,
        baseWord: challenge.word.word,
        wasCorrect: true,
      );
    } else {
      HapticFeedback.mediumImpact();
      _audioService.playSound('error');
      _shakeCtrl.forward(from: 0).then((_) => _shakeCtrl.reverse());
      _sriService.recordResponse(
        skillType: LanguageSkillType.wordType,
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
        _selectedType = null;
        _feedback = _Feedback.none;
      });
    });
  }

  void _showGameOver() {
    if (_gameOver) return;
    _gameOver = true;
    _sessionTimer?.cancel();

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'word_class_flash',
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
            Text(
              _isDE
                  ? 'richtig in ${_sessionSeconds - _secondsLeft}s'
                  : 'correct in ${_sessionSeconds - _secondsLeft}s',
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

  String _typeLabel(GermanWordType t) {
    if (_isDE) {
      switch (t) {
        case GermanWordType.substantiv:
          return 'Nomen';
        case GermanWordType.verb:
          return 'Verb';
        case GermanWordType.adjektiv:
          return 'Adjektiv';
        case GermanWordType.adverb:
          return 'Adverb';
        default:
          return '';
      }
    } else {
      switch (t) {
        case GermanWordType.substantiv:
          return 'Noun';
        case GermanWordType.verb:
          return 'Verb';
        case GermanWordType.adjektiv:
          return 'Adjective';
        case GermanWordType.adverb:
          return 'Adverb';
        default:
          return '';
      }
    }
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
          _isDE
              ? 'Keine Wortart-Daten für diese Stufe verfügbar.'
              : 'No word class data available at this level.',
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
        _buildTimerBar(),
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
                  _isDE ? 'Wortart-Blitz' : 'Word Class Flash',
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  _isDE
                      ? '$_correct richtig'
                      : '$_correct correct',
                  style: SpaceTheme.bodyStyle.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
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

  Widget _buildWordCard(_WordClassChallenge challenge) {
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
              const Color(0xFF203A43).withValues(alpha: 0.6),
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
                    : const Color(0xFF2C5364).withValues(alpha: 0.6),
            width: _feedback != _Feedback.none ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              _isDE ? 'Welche Wortart?' : 'What word class?',
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
              const SizedBox(height: 8),
              Text(
                _typeLabel(challenge.correctType),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptions(_WordClassChallenge challenge) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3.2,
      physics: const NeverScrollableScrollPhysics(),
      children: _types.map((t) => _buildTypeButton(challenge, t)).toList(),
    );
  }

  Widget _buildTypeButton(_WordClassChallenge challenge, GermanWordType t) {
    final isCorrect = t == challenge.correctType;
    final isSelected = _selectedType == t;
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
      child: GestureDetector(
        onTap: hasAnswered ? null : () => _handleTap(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            _typeLabel(t),
            style: TextStyle(
                color: text, fontSize: 15, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
