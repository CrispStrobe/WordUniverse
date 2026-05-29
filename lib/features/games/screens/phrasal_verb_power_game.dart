// lib/features/games/screens/phrasal_verb_power_game.dart
//
// Phrasal Verb Power (#46) — EN-only.
// A sentence with a blanked particle is shown; the player picks the particle
// that completes the phrasal verb in context (e.g. "Please ___ your toys."
// → put [away]). Distractors are real particles that form different phrasal
// verbs of the same base verb — the core difficulty of phrasal verbs.
//
// Data: the `phrasal_verbs` table in the EN database (Wiktionary CC-BY-SA +
// LLM grade-leveled examples), loaded via VocabularyService.getPhrasalVerbs().

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../models/game_outcome.dart';
import '../providers/game_provider.dart';
import '../services/phrasal_verb_service.dart';
import '../widgets/space_background.dart';
import '../../../shared/widgets/onboarding_overlay.dart';
import '../../../generated/l10n.dart';

class PhrasalVerbPowerGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const PhrasalVerbPowerGame({super.key, required this.gradeLevel});

  @override
  State<PhrasalVerbPowerGame> createState() => _PhrasalVerbPowerGameState();
}

enum _Feedback { none, correct, incorrect }

class _PhrasalVerbPowerGameState extends State<PhrasalVerbPowerGame>
    with TickerProviderStateMixin {
  late VocabularyService _vocabService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  static const int _maxRounds = 15;
  static const Duration _advanceDelay = Duration(milliseconds: 1300);

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<PhrasalChallenge> _challenges = [];
  int _index = 0;
  int _correct = 0;
  int _total = 0;
  int? _selectedOption;
  _Feedback _feedback = _Feedback.none;
  bool _gameOver = false;
  bool _showMeaning = false;

  late AnimationController _pulseCtrl;
  late AnimationController _shakeCtrl;

  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    _vocabService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();

    if (!_vocabService.isInitialized) await _vocabService.initialize();
    await _buildChallenges();

    if (!mounted) return;
    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      final s = S.of(context)!;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'phrasal_verb_power',
        title: s.phrasalVerbPowerTitle,
        steps: [
          OnboardingStep(
            icon: Icons.bolt,
            body: s.phrasalVerbPowerOnboard1,
          ),
          OnboardingStep(
            icon: Icons.text_fields,
            body: s.phrasalVerbPowerOnboard2,
          ),
          OnboardingStep(
            icon: Icons.tips_and_updates,
            body: s.phrasalVerbPowerOnboard3,
          ),
        ],
      );
    }
  }

  Future<void> _buildChallenges() async {
    final verbs = await _vocabService.getPhrasalVerbs();
    final built = buildPhrasalChallenges(
      verbs: verbs,
      gradeLevel: widget.gradeLevel.index + 1,
      maxChallenges: _maxRounds,
      rng: _rng,
    );

    if (!mounted) return;
    setState(() {
      _challenges = built;
      _index = 0;
      _correct = 0;
      _total = 0;
      _selectedOption = null;
      _feedback = _Feedback.none;
      _showMeaning = false;
      _gameOver = false;
      _isLoading = false;
    });
  }

  void _handleTap(int optionIndex) {
    if (_feedback != _Feedback.none || _gameOver) return;
    if (_index >= _challenges.length) return;

    final challenge = _challenges[_index];
    final isCorrect = optionIndex == challenge.correctIndex;

    setState(() {
      _selectedOption = optionIndex;
      _feedback = isCorrect ? _Feedback.correct : _Feedback.incorrect;
      _showMeaning = true;
      _total++;
    });

    if (isCorrect) {
      _correct++;
      _gameProvider.hapticLight();
      _audioService.playSound('success');
      _pulseCtrl.forward(from: 0);
    } else {
      _gameProvider.hapticMedium();
      _audioService.playSound('error');
      _shakeCtrl.forward(from: 0).then((_) => _shakeCtrl.reverse());
    }

    _sriService.recordResponse(
      skillType: LanguageSkillType.wordType,
      baseWord: challenge.phrasal,
      wasCorrect: isCorrect,
    );

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
        _showMeaning = false;
      });
    });
  }

  void _showGameOver() {
    if (_gameOver) return;
    _gameOver = true;

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'phrasal_verb_power',
      difficulty: widget.gradeLevel.index + 1,
      score: _correct * 10,
      wasSuccessful: _total > 0 && (_correct / _total) >= 0.7,
    ));

    final s = S.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s.gameRoundComplete, style: SpaceTheme.headlineStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_correct / $_total',
              style: SpaceTheme.titleStyle
                  .copyWith(color: SpaceTheme.starYellow, fontSize: 32),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text(s.gameBack),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _buildChallenges();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: SpaceTheme.planetOrange),
            child: Text(s.gamePlayAgain),
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
          S.of(context)!.phrasalVerbPowerEmpty,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildGame() {
    final challenge = _challenges[_index];
    return Column(
      children: [
        _buildHeader(),
        _buildProgressBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                _buildSentenceCard(challenge),
                const SizedBox(height: 20),
                _buildOptions(challenge),
                if (_showMeaning) ...[
                  const SizedBox(height: 16),
                  _buildMeaning(challenge),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final s = S.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.phrasalVerbPowerTitle,
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(s.gameCorrectOfTotal(_correct, _index + 1),
                    style:
                        SpaceTheme.bodyStyle.copyWith(color: Colors.white60)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: SpaceTheme.nebulaPurple.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_index + 1} / ${_challenges.length}',
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress =
        _challenges.isEmpty ? 0.0 : (_index + 1) / _challenges.length;
    return LinearProgressIndicator(
      value: progress,
      backgroundColor: SpaceTheme.moonSilver.withValues(alpha: 0.2),
      valueColor: const AlwaysStoppedAnimation<Color>(SpaceTheme.alienGreen),
      minHeight: 4,
    );
  }

  Widget _buildSentenceCard(PhrasalChallenge challenge) {
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
              S.of(context)!.phrasalVerbPowerPrompt,
              style: SpaceTheme.bodyStyle.copyWith(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            _buildSentenceText(challenge.sentence),
          ],
        ),
      ),
    );
  }

  Widget _buildSentenceText(String sentence) {
    final parts = sentence.split('___');
    if (parts.length != 2) {
      return Text(sentence,
          style: SpaceTheme.headlineStyle
              .copyWith(fontSize: 22, color: Colors.white, height: 1.5),
          textAlign: TextAlign.center);
    }
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: SpaceTheme.headlineStyle
            .copyWith(fontSize: 22, color: Colors.white, height: 1.5),
        children: [
          TextSpan(text: parts[0]),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: SpaceTheme.planetOrange.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: SpaceTheme.planetOrange.withValues(alpha: 0.7),
                    width: 1.5),
              ),
              child: Text(
                '   ___   ',
                style: SpaceTheme.headlineStyle.copyWith(
                  fontSize: 22,
                  color: SpaceTheme.planetOrange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          TextSpan(text: parts[1]),
        ],
      ),
    );
  }

  Widget _buildOptions(PhrasalChallenge challenge) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: List.generate(
        challenge.options.length,
        (i) => _buildOption(challenge, i),
      ),
    );
  }

  Widget _buildOption(PhrasalChallenge challenge, int index) {
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
        scale: hasAnswered && isCorrect ? 1.0 + (_pulseCtrl.value * 0.04) : 1.0,
        child: child,
      ),
      child: GestureDetector(
        onTap: hasAnswered ? null : () => _handleTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 120,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            challenge.options[index],
            style: TextStyle(
                color: text, fontSize: 20, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildMeaning(PhrasalChallenge challenge) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            challenge.phrasal,
            style: SpaceTheme.titleStyle.copyWith(
                color: SpaceTheme.starYellow, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            challenge.meaning,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
