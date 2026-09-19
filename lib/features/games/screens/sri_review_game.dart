// lib/features/games/screens/sri_review_game.dart
//
// SRI Review Mode — practice the player's weakest tracked words.
// Pulls up to 10 lowest-easiness-factor entries from SriService and runs
// each through a challenge that matches the original skill:
//   • articleSelection  → pick der / die / das
//   • spelling          → pick correctly-spelled form from misspellings
//   • everything else   → pick the matching word given its definition
// Falls back to definition quiz when the skill-specific format is not
// applicable (e.g. no error words stored, or no definition available).

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/word_features.dart';
import '../services/sri_review_service.dart';
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

// ─── Data model ───────────────────────────────────────────────────────────────

// ─── Widget ───────────────────────────────────────────────────────────────────

class SriReviewGame extends StatefulWidget {
  const SriReviewGame({super.key});

  @override
  State<SriReviewGame> createState() => _SriReviewGameState();
}

enum _Feedback { none, correct, incorrect }

class _SriReviewGameState extends State<SriReviewGame>
    with TickerProviderStateMixin {
  late VocabularyService _vocabService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;
  late S _s;

  static const int _targetRounds = 10;
  static const int _optionCount = 4;

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<ReviewChallenge> _challenges = [];
  int _index = 0;
  int _correct = 0;
  int? _selectedOption;
  _Feedback _feedback = _Feedback.none;

  late AnimationController _pulseCtrl;
  late AnimationController _shakeCtrl;

  final _rng = Random();

  bool get _isDE => _vocabService.learningLanguage == 'de';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
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
    _s = S.of(context)!;
    _vocabService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();

    if (!_vocabService.isInitialized) await _vocabService.initialize();
    _audioService.setTtsLanguage(_vocabService.learningLanguage);
    await _buildChallenges();
    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'sri_review',
        title: _s.sriReviewTitle,
        steps: [
          OnboardingStep(
            icon: Icons.refresh,
            body: _s.sriReviewOnboardingBody1,
          ),
          OnboardingStep(
            icon: Icons.auto_awesome,
            body: _s.sriReviewOnboardingBody2,
          ),
          OnboardingStep(
            icon: Icons.trending_up,
            body: _s.sriReviewOnboardingBody3,
          ),
        ],
      );
    }
  }

  // ─── Challenge building ──────────────────────────────────────────────────

  String _baseWordFromId(SriLanguageData d) {
    // Strip the prefix added by SriService.getItemId() to recover the word.
    const prefixes = [
      'SPELL_',
      'ARTICLE_',
      'PLURAL_',
      'WORDTYPE_',
      'SENTENCE_',
      'PUNCT_',
      'CAPITAL_',
      'CONJUG_',
      'CASE_',
    ];
    var id = d.itemId;
    for (final p in prefixes) {
      if (id.startsWith(p)) return id.substring(p.length);
    }
    return id;
  }

  /// Indexed lookup; this used to scan the whole catalogue per review item.
  GermanWord? _findWord(String baseWord) =>
      _vocabService.findByWrittenForm(baseWord);

  Future<void> _buildChallenges() async {
    // Respect spaced repetition: prefer items that are actually DUE
    // (getItemsForReview excludes mastered/not-yet-due), ranked by difficulty.
    // Only fall back to hardest-overall when nothing is due, so the game stays
    // playable but doesn't resurface the same low-EF words every session.
    final dueIds =
        _sriService.getItemsForReview(limit: _targetRounds * 4).toSet();
    var sriItems = _sriService
        .getMostDifficultItems(limit: _targetRounds * 4)
        .where((d) => dueIds.contains(d.itemId))
        .toList();
    if (sriItems.isEmpty) {
      sriItems = _sriService.getMostDifficultItems(limit: _targetRounds * 2);
    }
    if (sriItems.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // Spelling distractors only need the spellings, so this stays the light
    // catalogue.
    final validWords = _vocabService
        .getAllWords(_gameProvider)
        .map((w) => w.word.toLowerCase())
        .toSet();

    // Definition distractors need decoded definitions — a bounded pool of
    // words the feature index says have them.
    final definitionPool = await _vocabService.takeWordsWithFeature(
      WordFeature.definitions,
      settingsProvider: _gameProvider,
      limit: 120,
      where: (w) => !w.isProperNoun,
      random: _rng,
    );

    // The reviewed words themselves are shown with their definitions and
    // learner errors, so hydrate exactly those.
    final reviewed = <SriLanguageData, GermanWord>{};
    final found = <SriLanguageData, GermanWord>{};
    for (final item in sriItems) {
      final word = _findWord(_baseWordFromId(item));
      if (word != null) found[item] = word;
    }
    final hydrated = await _vocabService.hydrate(found.values);
    var cursor = 0;
    for (final item in found.keys) {
      reviewed[item] = hydrated[cursor++];
    }
    if (!mounted) return;

    final challenges = <ReviewChallenge>[];
    for (final item in sriItems) {
      if (challenges.length >= _targetRounds) break;
      final word = reviewed[item];
      if (word == null) continue;

      final challenge = buildReviewChallenge(
        word,
        item,
        definitionPool,
        validWords,
        strings: _s,
        isGerman: _isDE,
        optionCount: _optionCount,
        rng: _rng,
      );
      if (challenge != null) challenges.add(challenge);
    }

    setState(() {
      _challenges = challenges;
      _index = 0;
      _correct = 0;
      _selectedOption = null;
      _feedback = _Feedback.none;
      _isLoading = false;
    });
  }

  // ─── Gameplay ────────────────────────────────────────────────────────────

  void _handleTap(int index) {
    if (_feedback != _Feedback.none) return;
    final challenge = _challenges[_index];
    final isCorrect = index == challenge.correctIndex;

    setState(() {
      _selectedOption = index;
      _feedback = isCorrect ? _Feedback.correct : _Feedback.incorrect;
    });

    if (isCorrect) {
      _gameProvider.hapticLight();
      _audioService.playSound('success');
      _pulseCtrl.forward(from: 0);
      _correct++;
      _sriService.recordResponse(
        skillType: challenge.sriData.skillType,
        // Use the base recovered from the item's own id so we UPDATE the
        // reviewed item rather than create a new lemma-keyed duplicate (the
        // word may have been matched via its lemma, not its surface form).
        baseWord: _baseWordFromId(challenge.sriData),
        wasCorrect: true,
      );
    } else {
      _gameProvider.hapticMedium();
      _audioService.playSound('error');
      _shakeCtrl.forward(from: 0).then((_) => _shakeCtrl.reverse());
      _sriService.recordResponse(
        skillType: challenge.sriData.skillType,
        baseWord: _baseWordFromId(challenge.sriData),
        wasCorrect: false,
      );
    }

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      _advance();
    });
  }

  void _advance() {
    if (_index + 1 >= _challenges.length) {
      _showGameOver();
      return;
    }
    setState(() {
      _index++;
      _selectedOption = null;
      _feedback = _Feedback.none;
    });
  }

  void _showGameOver() {
    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'sri_review',
      difficulty: 3,
      score: _correct * 10,
      wasSuccessful: _correct >= (_challenges.length * 0.7),
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
              '$_correct / ${_challenges.length}',
              style: SpaceTheme.titleStyle
                  .copyWith(color: SpaceTheme.starYellow, fontSize: 28),
            ),
            const SizedBox(height: 4),
            Text(
              _s.correct,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_outline, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(
              _s.reviewNoWordsYet,
              style: SpaceTheme.bodyStyle.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGame() {
    final challenge = _challenges[_index];
    return Column(
      children: [
        _buildHeader(challenge),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _buildDifficultyBanner(challenge),
                const SizedBox(height: 16),
                _buildPromptCard(challenge),
                const SizedBox(height: 20),
                _buildOptions(challenge),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ReviewChallenge challenge) {
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
                  _s.sriReviewHeader,
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  '${_index + 1} / ${_challenges.length}',
                  style: SpaceTheme.bodyStyle.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          Text(
            '${_s.score}: ${_correct * 10}',
            style: SpaceTheme.bodyStyle
                .copyWith(color: SpaceTheme.starYellow, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyBanner(ReviewChallenge challenge) {
    final ef = challenge.sriData.easinessFactor;
    final label = ef < 1.5
        ? _s.difficultyVeryHard
        : ef < 2.0
            ? _s.difficultyHard
            : _s.difficultyPractice;
    final color = ef < 1.5
        ? SpaceTheme.rocketRed
        : ef < 2.0
            ? SpaceTheme.planetOrange
            : SpaceTheme.starYellow;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.repeat, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (challenge.word.cefrLevel != null) ...[
          const SizedBox(width: 8),
          CefrChip(challenge.word.cefrLevel!),
        ],
      ],
    );
  }

  Widget _buildPromptCard(ReviewChallenge challenge) {
    final typeLabel = switch (challenge.type) {
      ReviewChallengeType.article => _s.challengeTypeArticle,
      ReviewChallengeType.spelling => _s.challengeTypeSpelling,
      ReviewChallengeType.definition => _s.challengeTypeDefinition,
    };

    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(
          _feedback == _Feedback.incorrect
              ? sin(_shakeCtrl.value * pi * 5) * 6
              : 0,
          0,
        ),
        child: child,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _feedback == _Feedback.correct
                ? SpaceTheme.alienGreen
                : _feedback == _Feedback.incorrect
                    ? Colors.redAccent
                    : SpaceTheme.nebulaPurple.withValues(alpha: 0.5),
            width: _feedback != _Feedback.none ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              typeLabel,
              style: SpaceTheme.bodyStyle.copyWith(
                  color: SpaceTheme.starYellow.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              challenge.prompt,
              style: SpaceTheme.bodyStyle.copyWith(
                color: Colors.white,
                fontSize: 16,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptions(ReviewChallenge challenge) {
    return Column(
      children: List.generate(challenge.options.length, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildOption(challenge, i),
        );
      }),
    );
  }

  Widget _buildOption(ReviewChallenge challenge, int index) {
    final isCorrect = index == challenge.correctIndex;
    final isSelected = _selectedOption == index;
    final hasAnswered = _feedback != _Feedback.none;

    Color border = SpaceTheme.moonSilver.withValues(alpha: 0.4);
    Color bg = SpaceTheme.deepSpace.withValues(alpha: 0.6);
    Color text = Colors.white;
    IconData? icon;

    if (hasAnswered) {
      if (isCorrect) {
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.2);
        icon = Icons.check_circle;
        text = Colors.green.shade200;
      } else if (isSelected) {
        border = Colors.redAccent;
        bg = Colors.red.withValues(alpha: 0.15);
        icon = Icons.cancel;
        text = Colors.redAccent;
      }
    }

    Widget tile = AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, child) => Transform.scale(
        scale:
            (hasAnswered && isCorrect) ? 1.0 + (_pulseCtrl.value * 0.025) : 1.0,
        child: child,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: text, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              challenge.options[index],
              style: TextStyle(
                  color: text, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );

    if (!hasAnswered) {
      tile = GestureDetector(onTap: () => _handleTap(index), child: tile);
    }
    return tile;
  }
}
