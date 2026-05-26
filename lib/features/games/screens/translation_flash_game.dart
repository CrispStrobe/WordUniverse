// lib/features/games/screens/translation_flash_game.dart
//
// Translation Flash — DE-only timed warm-up game.
// A German word is shown; the player taps its English translation from 4
// options within the session timer. Uses Wiktionary EN translations stored in
// apiEnrichment.translations (lang_code == 'en').
// Session ends after 30 seconds or 20 rounds, whichever comes first.

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

// ─── Internal data model ──────────────────────────────────────────────────────

class _TranslChallenge {
  final GermanWord deWord;
  final String enTranslation;
  final List<String> options;
  final int correctIndex;
  const _TranslChallenge({
    required this.deWord,
    required this.enTranslation,
    required this.options,
    required this.correctIndex,
  });
}

enum _Feedback { none, correct, incorrect }

// ─── Game screen ──────────────────────────────────────────────────────────────

class TranslationFlashGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const TranslationFlashGame({super.key, required this.gradeLevel});

  @override
  State<TranslationFlashGame> createState() => _TranslationFlashGameState();
}

class _TranslationFlashGameState extends State<TranslationFlashGame>
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

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<_TranslChallenge> _challenges = [];
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
        gameKey: 'translation_flash',
        title: 'Übersetzungs-Blitz',
        steps: [
          const OnboardingStep(
            icon: Icons.translate,
            body: 'Ein deutsches Wort erscheint — tippe schnell auf die richtige englische Übersetzung.',
          ),
          const OnboardingStep(
            icon: Icons.timer,
            body: 'Du hast 30 Sekunden. Je mehr richtige Antworten, desto besser dein Score.',
          ),
          const OnboardingStep(
            icon: Icons.tips_and_updates,
            body: 'Übersetzungen stammen aus Wiktionary.',
          ),
        ],
      );
    }
  }

  // ─── Challenge building ────────────────────────────────────────────────────

  // A translation is "clean" if it contains only ASCII letters, hyphens,
  // apostrophes, and spaces — no dots (abbreviations), no diacritics, no digits,
  // no all-caps abbreviations. Maximum 2 words (single-word preferred, but a
  // 2-word standard phrase beats a rare single-word regional variant).
  static bool _isCleanTranslation(String w) {
    if (w.isEmpty) return false;
    if (w.contains('.')) return false;
    if (w == w.toUpperCase() && w.length > 1) return false;
    if (!RegExp(r"^[a-zA-Z\-' ]+$").hasMatch(w)) return false;
    return w.split(' ').length <= 2;
  }

  /// Returns the first Wiktionary EN translation that passes [_isCleanTranslation].
  /// Positional priority respects Wiktionary's sense ordering; single-word is
  /// not forced over multi-word so standard phrases (e.g. "traffic light") beat
  /// obscure single-word regional synonyms (e.g. "robot").
  static String? _primaryEnTranslation(GermanWord word) {
    final translations = word.apiEnrichment?.translations ?? [];
    for (final t in translations) {
      if (t.langCode == 'en' && t.word != null) {
        final w = t.word!.trim();
        if (_isCleanTranslation(w)) return w;
      }
    }
    return null;
  }

  void _buildChallenges() {
    final allWords = _vocabService
        .getAllWords(_gameProvider)
        .where((w) =>
            !w.isProperNoun &&
            !w.word.contains('_') &&
            !w.word.contains(' ') &&
            _primaryEnTranslation(w) != null)
        .toList();

    if (allWords.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // Prefer grade-appropriate pool.
    final gradePool = allWords
        .where((w) => w.gradeLevel == widget.gradeLevel.index + 1)
        .toList();
    final pool = gradePool.length >= 10 ? gradePool : allWords;
    pool.shuffle(_rng);

    // Build the EN translation distractor pool from the full word set.
    final enPool = allWords
        .map((w) => _primaryEnTranslation(w))
        .whereType<String>()
        .toList()
      ..shuffle(_rng);

    final challenges = <_TranslChallenge>[];
    for (final word in pool) {
      if (challenges.length >= _maxRounds) break;
      final c = _buildChallenge(word, enPool);
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

  _TranslChallenge? _buildChallenge(GermanWord word, List<String> enPool) {
    final correct = _primaryEnTranslation(word);
    if (correct == null) return null;

    // All EN translations for this word (to exclude from distractors).
    final allEntryEn = (word.apiEnrichment?.translations ?? [])
        .where((t) => t.langCode == 'en' && t.word != null)
        .map((t) => t.word!.toLowerCase())
        .toSet();

    final distractors = <String>[];
    for (final t in enPool) {
      if (distractors.length >= _optionCount - 1) break;
      if (!allEntryEn.contains(t.toLowerCase()) &&
          t.toLowerCase() != correct.toLowerCase()) {
        distractors.add(t);
      }
    }
    if (distractors.isEmpty) return null;

    final options = [correct, ...distractors.take(_optionCount - 1)];
    options.shuffle(_rng);
    final correctIndex = options.indexWhere(
        (o) => o.toLowerCase() == correct.toLowerCase());
    if (correctIndex < 0) return null;

    return _TranslChallenge(
      deWord: word,
      enTranslation: correct,
      options: options,
      correctIndex: correctIndex,
    );
  }

  // ─── Timer ─────────────────────────────────────────────────────────────────

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

  // ─── Input handling ────────────────────────────────────────────────────────

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
      HapticFeedback.lightImpact();
      _audioService.playSound('success');
      _pulseCtrl.forward(from: 0);
      _correct++;
      _sriService.recordResponse(
        skillType: LanguageSkillType.wordType,
        baseWord: challenge.deWord.word,
        wasCorrect: true,
      );
    } else {
      HapticFeedback.mediumImpact();
      _audioService.playSound('error');
      _shakeCtrl.forward(from: 0).then((_) => _shakeCtrl.reverse());
      _sriService.recordResponse(
        skillType: LanguageSkillType.wordType,
        baseWord: challenge.deWord.word,
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
      gameType: 'translation_flash',
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
              'richtig in ${_sessionSeconds - _secondsLeft}s',
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Keine Übersetzungsdaten für diese Stufe verfügbar.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
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
                  'Übersetzungs-Blitz',
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  '$_correct richtig',
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

  Widget _buildWordCard(_TranslChallenge challenge) {
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
              const Color(0xFF1A237E).withValues(alpha: 0.6),
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
                    : const Color(0xFF3F51B5).withValues(alpha: 0.6),
            width: _feedback != _Feedback.none ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            const Text(
              'Auf Englisch …',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text(
              challenge.deWord.word,
              style: SpaceTheme.headlineStyle.copyWith(
                fontSize: 34,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (challenge.deWord.cefrLevel != null) ...[
              const SizedBox(height: 8),
              CefrChip(challenge.deWord.cefrLevel!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptions(_TranslChallenge challenge) {
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

  Widget _buildOption(_TranslChallenge challenge, int index) {
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
      child: GestureDetector(
        onTap: hasAnswered ? null : () => _handleTap(index),
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
    );
  }
}
