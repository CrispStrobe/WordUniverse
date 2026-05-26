// lib/features/games/screens/syllable_count_game.dart
//
// Syllable Count (#43) — timed warm-up game.
// A word is shown; the player taps how many syllables it has (1 / 2 / 3 / 4+).
// Syllable count is derived from the hyphenation field in ApiEnrichment.
// DE: ~9 400 words with valid hyphenation. EN: ~2 900.
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

class SyllableCountGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const SyllableCountGame({super.key, required this.gradeLevel});

  @override
  State<SyllableCountGame> createState() => _SyllableCountGameState();
}

class _SyllableChallenge {
  final GermanWord word;
  final int syllableCount;
  final int correctBucket; // 0→1, 1→2, 2→3, 3→4+
  const _SyllableChallenge({
    required this.word,
    required this.syllableCount,
    required this.correctBucket,
  });
}

enum _Feedback { none, correct, incorrect }

class _SyllableCountGameState extends State<SyllableCountGame>
    with TickerProviderStateMixin {
  late VocabularyService _vocabService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;
  late S _s;

  static const int _sessionSeconds = 30;
  static const int _maxRounds = 20;
  static const List<String> _bucketLabels = ['1', '2', '3', '4+'];

  static const Duration _advanceDelay = Duration(milliseconds: 900);

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<_SyllableChallenge> _challenges = [];
  int _index = 0;
  int _correct = 0;
  int _total = 0;
  int? _selectedBucket;
  _Feedback _feedback = _Feedback.none;

  int _secondsLeft = _sessionSeconds;
  Timer? _sessionTimer;
  bool _gameOver = false;

  late AnimationController _pulseCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _timerCtrl;

  final _rng = Random();

  bool get _isDE => _vocabService.learningLanguage == 'de';

  // ─── syllable extraction ───────────────────────────────────────────────────

  // Parses a raw hyphenation string (e.g. "Schmet-ter-ling") into a syllable
  // count. Returns null when the string is malformed (consonant-only segments,
  // concatenated forms that can't be safely split, etc.).
  static int? _countSyllables(String rawHyph) {
    if (rawHyph.isEmpty) return null;

    // Some DB entries concatenate two hyphenation forms without a separator,
    // detectable by an uppercase letter that is not at the start and not after
    // a hyphen (e.g. "Bei-spielBei-spie-le"). Truncate to the first form.
    String truncated = rawHyph;
    for (int i = 1; i < rawHyph.length; i++) {
      final ch = rawHyph[i];
      if (ch == ch.toUpperCase() && ch != ch.toLowerCase() && rawHyph[i - 1] != '-') {
        truncated = rawHyph.substring(0, i);
        break;
      }
    }

    final segments = truncated.split('-');
    // Every segment must contain at least one vowel; otherwise the split is
    // character-level noise (e.g. "Fe-b-ru-ar" for Februar).
    const vowels = 'aeiouyäöüAEIOUYÄÖÜ';
    for (final seg in segments) {
      if (!seg.split('').any(vowels.contains)) return null;
    }
    return segments.length;
  }

  static int _toBucket(int n) => n <= 3 ? n - 1 : 3; // 1→0, 2→1, 3→2, 4+→3

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
    _audioService.setTtsLanguage(_vocabService.learningLanguage);
    _buildChallenges();

    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      final isDE = _isDE;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'syllable_count',
        title: isDE ? 'Silben zählen' : 'Syllable Count',
        steps: [
          OnboardingStep(
            icon: Icons.volume_up,
            body: isDE
                ? 'Ein Wort erscheint — tippe, wie viele Silben es hat.'
                : 'A word appears — tap how many syllables it has.',
          ),
          OnboardingStep(
            icon: Icons.timer,
            body: isDE
                ? 'Du hast 30 Sekunden. Sprich das Wort laut aus, um die Silben zu spüren.'
                : 'You have 30 seconds. Say the word aloud to feel its syllables.',
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
            (w.apiEnrichment?.hyphenation.isNotEmpty ?? false))
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

    final challenges = <_SyllableChallenge>[];
    for (final word in pool) {
      if (challenges.length >= _maxRounds) break;
      final c = _buildChallenge(word);
      if (c != null) challenges.add(c);
    }

    setState(() {
      _challenges = challenges;
      _index = 0;
      _correct = 0;
      _total = 0;
      _selectedBucket = null;
      _feedback = _Feedback.none;
      _gameOver = false;
      _secondsLeft = _sessionSeconds;
      _isLoading = false;
    });

    _startTimer();
  }

  _SyllableChallenge? _buildChallenge(GermanWord word) {
    final hyphenations = word.apiEnrichment!.hyphenation;
    // Try each hyphenation entry; use the first that parses cleanly.
    for (final raw in hyphenations) {
      final count = _countSyllables(raw);
      if (count != null && count >= 1) {
        return _SyllableChallenge(
          word: word,
          syllableCount: count,
          correctBucket: _toBucket(count),
        );
      }
    }
    return null;
  }

  // ─── timer ─────────────────────────────────────────────────────────────────

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

  // ─── interaction ───────────────────────────────────────────────────────────

  void _handleTap(int bucket) {
    if (_feedback != _Feedback.none || _gameOver) return;
    if (_index >= _challenges.length) return;

    final challenge = _challenges[_index];
    final isCorrect = bucket == challenge.correctBucket;

    setState(() {
      _selectedBucket = bucket;
      _feedback = isCorrect ? _Feedback.correct : _Feedback.incorrect;
      _total++;
    });

    if (isCorrect) {
      _gameProvider.hapticLight();
      _audioService.playSound('success');
      _pulseCtrl.forward(from: 0);
      _correct++;
      _sriService.recordResponse(
        skillType: LanguageSkillType.spelling,
        baseWord: challenge.word.word,
        wasCorrect: true,
      );
    } else {
      _gameProvider.hapticMedium();
      _audioService.playSound('error');
      _shakeCtrl.forward(from: 0).then((_) => _shakeCtrl.reverse());
      _sriService.recordResponse(
        skillType: LanguageSkillType.spelling,
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
        _selectedBucket = null;
        _feedback = _Feedback.none;
      });
    });
  }

  void _showGameOver() {
    if (_gameOver) return;
    _gameOver = true;
    _sessionTimer?.cancel();

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'syllable_count',
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
          _isDE
              ? 'Keine Silbendaten für diese Stufe verfügbar.'
              : 'No syllable data available at this level.',
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
                const SizedBox(height: 28),
                _buildBuckets(challenge),
                if (_feedback != _Feedback.none) ...[
                  const SizedBox(height: 16),
                  _buildHint(challenge),
                ],
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
                  _isDE ? 'Silben zählen' : 'Syllable Count',
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  '$_correct ${_isDE ? 'richtig' : 'correct'}',
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

  Widget _buildWordCard(_SyllableChallenge challenge) {
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
              SpaceTheme.nebulaPurple.withValues(alpha: 0.6),
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
                    : SpaceTheme.nebulaPurple.withValues(alpha: 0.5),
            width: _feedback != _Feedback.none ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              _isDE ? 'Wie viele Silben?' : 'How many syllables?',
              style: SpaceTheme.bodyStyle.copyWith(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              challenge.word.word,
              style: SpaceTheme.headlineStyle.copyWith(
                fontSize: 36,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (challenge.word.cefrLevel != null) ...[
              const SizedBox(height: 8),
              CefrChip(challenge.word.cefrLevel!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBuckets(_SyllableChallenge challenge) {
    return Row(
      children: List.generate(4, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
            child: _buildBucket(challenge, i),
          ),
        );
      }),
    );
  }

  Widget _buildBucket(_SyllableChallenge challenge, int bucket) {
    final isCorrect = bucket == challenge.correctBucket;
    final isSelected = _selectedBucket == bucket;
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
        scale: hasAnswered && isCorrect ? 1.0 + (_pulseCtrl.value * 0.06) : 1.0,
        child: child,
      ),
      child: GestureDetector(
        onTap: hasAnswered ? null : () => _handleTap(bucket),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 72,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            _bucketLabels[bucket],
            style: TextStyle(
              color: text,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHint(_SyllableChallenge challenge) {
    // Show the hyphenated form so the user learns the correct split.
    final hyph = challenge.word.apiEnrichment!.hyphenation.first;
    final syllableWord = hyph.contains('-') ? hyph : challenge.word.word;
    return Text(
      syllableWord,
      style: SpaceTheme.bodyStyle.copyWith(
        color: _feedback == _Feedback.correct
            ? SpaceTheme.alienGreen
            : Colors.redAccent.shade100,
        fontSize: 16,
        letterSpacing: 1.2,
      ),
      textAlign: TextAlign.center,
    );
  }
}
