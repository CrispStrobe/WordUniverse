// lib/features/games/screens/false_friends_game.dart
//
// False Friends (#48) — EN-only.
// An English false-friend word is shown; the player picks its real German
// meaning. The German look-alike word is offered as the trap. Data: the
// `false_friends` table (built by add_false_friends_en.py).

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
import '../services/false_friend_service.dart';
import '../widgets/space_background.dart';
import '../../../shared/widgets/onboarding_overlay.dart';
import '../../../generated/l10n.dart';

class FalseFriendsGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const FalseFriendsGame({super.key, required this.gradeLevel});

  @override
  State<FalseFriendsGame> createState() => _FalseFriendsGameState();
}

enum _Feedback { none, correct, incorrect }

class _FalseFriendsGameState extends State<FalseFriendsGame>
    with TickerProviderStateMixin {
  late VocabularyService _vocabService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  static const int _maxRounds = 15;
  static const Duration _advanceDelay = Duration(milliseconds: 1600);

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<FalseFriendChallenge> _challenges = [];
  int _index = 0;
  int _correct = 0;
  int _total = 0;
  int? _selectedOption;
  _Feedback _feedback = _Feedback.none;
  bool _gameOver = false;
  bool _showExplain = false;

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
        gameKey: 'false_friends',
        title: s.falseFriendsTitle,
        steps: [
          OnboardingStep(icon: Icons.warning_amber, body: s.falseFriendsOnboard1),
          OnboardingStep(icon: Icons.checklist, body: s.falseFriendsOnboard2),
          OnboardingStep(icon: Icons.tips_and_updates, body: s.falseFriendsOnboard3),
        ],
      );
    }
  }

  Future<void> _buildChallenges() async {
    final friends = await _vocabService.getFalseFriends();
    final built = buildFalseFriendChallenges(
      friends: friends,
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
      _showExplain = false;
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
      _showExplain = true;
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
      skillType: LanguageSkillType.vocabulary,
      baseWord: challenge.english,
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
        _showExplain = false;
      });
    });
  }

  void _showGameOver() {
    if (_gameOver) return;
    _gameOver = true;

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'false_friends',
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
            Text('$_correct / $_total',
                style: SpaceTheme.titleStyle
                    .copyWith(color: SpaceTheme.starYellow, fontSize: 32)),
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
            autofocus: true,
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

  Widget _buildEmptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(S.of(context)!.falseFriendsEmpty,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        ),
      );

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
                _buildPrompt(challenge),
                const SizedBox(height: 20),
                ...List.generate(challenge.options.length,
                    (i) => _buildOption(challenge, i)),
                if (_showExplain) ...[
                  const SizedBox(height: 16),
                  _buildExplain(challenge),
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
                Text(s.falseFriendsTitle,
                    style: SpaceTheme.titleStyle
                        .copyWith(color: SpaceTheme.starYellow)),
                Text(s.gameCorrectOfTotal(_correct, _total),
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
            child: Text('${_index + 1} / ${_challenges.length}',
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w600)),
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

  Widget _buildPrompt(FalseFriendChallenge challenge) {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(
            _feedback == _Feedback.incorrect
                ? sin(_shakeCtrl.value * pi * 6) * 6
                : 0,
            0),
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
            Text(S.of(context)!.falseFriendsPrompt,
                style: SpaceTheme.bodyStyle
                    .copyWith(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 12),
            Text(challenge.english,
                textAlign: TextAlign.center,
                style: SpaceTheme.headlineStyle.copyWith(
                  fontSize: 30,
                  color: SpaceTheme.starYellow,
                  fontWeight: FontWeight.w800,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(FalseFriendChallenge challenge, int index) {
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: hasAnswered ? null : () => _handleTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Text(challenge.options[index],
              style: TextStyle(
                  color: text, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _buildExplain(FalseFriendChallenge challenge) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        // e.g. "gift = Geschenk — nicht „Gift" (poison)!"
        S.of(context)!.falseFriendsExplain(
            challenge.english, challenge.correctMeaning,
            challenge.german, challenge.germanMeans),
        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
      ),
    );
  }
}
