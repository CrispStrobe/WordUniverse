// lib/features/games/screens/conjugation_drill_game.dart
//
// Conjugation Drill — DE-only verb conjugation practice.
// A German verb infinitive and a pronoun are shown; the player picks the
// correct present-tense (Präsens) conjugated form from 4 options.
// Data source: word.inflectionData (structured pattern) with fallback to
// word.wiktionaryInflections (flat Wiktionary tagged forms).

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
import '../services/conjugation_drill_service.dart';
import '../widgets/cefr_chip.dart';
import '../widgets/space_background.dart';
import '../../../shared/widgets/onboarding_overlay.dart';

class ConjugationDrillGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const ConjugationDrillGame({super.key, required this.gradeLevel});

  @override
  State<ConjugationDrillGame> createState() => _ConjugationDrillGameState();
}

class _ConjugationChallenge {
  final GermanWord verb;
  final String pronoun;
  final String correctForm;
  final List<String> options; // length 4, shuffled
  final int correctIndex;

  const _ConjugationChallenge({
    required this.verb,
    required this.pronoun,
    required this.correctForm,
    required this.options,
    required this.correctIndex,
  });
}

enum _Feedback { none, correct, incorrect }

class _ConjugationDrillGameState extends State<ConjugationDrillGame>
    with TickerProviderStateMixin {
  late VocabularyService _vocabService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  static const int _maxRounds = 15;
  static const int _optionCount = 4;
  static const Duration _advanceDelay = Duration(milliseconds: 1100);

  bool _isLoading = true;
  bool _onboardingScheduled = false;
  List<_ConjugationChallenge> _challenges = [];
  int _index = 0;
  int _correct = 0;
  int _total = 0;
  int? _selectedOption;
  _Feedback _feedback = _Feedback.none;
  bool _gameOver = false;

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
    if (!_onboardingScheduled) {
      _onboardingScheduled = true;
      final s = S.of(context)!;
      OnboardingOverlay.maybeShow(
        context,
        gameKey: 'conjugation_drill',
        title: s.conjugationDrillTitle,
        steps: [
          OnboardingStep(
            icon: Icons.text_fields,
            body: s.conjugationDrillOnboardingBody1,
          ),
          OnboardingStep(
            icon: Icons.school,
            body: s.conjugationDrillOnboardingBody2,
          ),
          OnboardingStep(
            icon: Icons.tips_and_updates,
            body: s.conjugationDrillOnboardingBody3,
          ),
        ],
      );
    }
  }

  Future<void> _buildChallenges() async {
    // Präsens forms live in the inflections, so only verbs the feature index
    // says carry inflections are decoded; whether the Präsens is actually
    // usable is then checked on the real data.
    final verbs = (await _vocabService.takeWordsWithFeature(
      WordFeature.inflections,
      settingsProvider: _gameProvider,
      gradeLevel: widget.gradeLevel.index + 1,
      limit: 250,
      where: (w) =>
          w.wordType == GermanWordType.verb &&
          !w.isProperNoun &&
          !w.word.contains(' '),
      random: _rng,
    ))
        .where(isConjugatableVerb)
        .toList();
    if (!mounted) return;

    if (verbs.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // Already grade-first and shuffled by the pool query.
    final pool = verbs;

    // Pre-collect all forms per pronoun for distractor selection.
    final formsByPronoun = <String, List<String>>{};
    for (final pronoun in conjugationPronouns) {
      formsByPronoun[pronoun] = verbs
          .map((v) => getPraesensForWord(v)?[pronoun])
          .whereType<String>()
          .toList()
        ..shuffle(_rng);
    }

    final challenges = <_ConjugationChallenge>[];
    for (final verb in pool) {
      if (challenges.length >= _maxRounds) break;
      final pres = getPraesensForWord(verb)!;
      // Pick a random available pronoun for this verb.
      // Skip pronouns whose Präsens form is identical to the infinitive shown
      // on the verb card (wir/sie/Sie → "wir laufen"): the answer would just
      // be the displayed word. Keep ich/du/er-sie-es where the stem changes.
      final availablePronouns = conjugationPronouns
          .where((p) =>
              pres.containsKey(p) &&
              pres[p]!.toLowerCase() != verb.word.toLowerCase())
          .toList()
        ..shuffle(_rng);
      if (availablePronouns.isEmpty) continue;
      final pronoun = availablePronouns.first;
      final correct = pres[pronoun]!;

      final distractors = pickDistractors(
        pronoun,
        correct,
        verb.word,
        formsByPronoun[pronoun] ?? [],
        count: _optionCount - 1,
      );
      if (distractors.length < 2) continue;

      final options = [correct, ...distractors];
      options.shuffle(_rng);
      final correctIndex = options.indexOf(correct);
      if (correctIndex < 0) continue;

      challenges.add(_ConjugationChallenge(
        verb: verb,
        pronoun: pronoun,
        correctForm: correct,
        options: options,
        correctIndex: correctIndex,
      ));
    }

    setState(() {
      _challenges = challenges;
      _index = 0;
      _correct = 0;
      _total = 0;
      _selectedOption = null;
      _feedback = _Feedback.none;
      _gameOver = false;
      _isLoading = false;
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
    } else {
      _gameProvider.hapticMedium();
      _audioService.playSound('error');
      _shakeCtrl.forward(from: 0).then((_) => _shakeCtrl.reverse());
    }

    _sriService.recordResponse(
      skillType: LanguageSkillType.verbConjugation,
      baseWord: challenge.verb.word,
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
      });
    });
  }

  void _showGameOver() {
    if (_gameOver) return;
    _gameOver = true;

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'conjugation_drill',
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
        title: Text(s.conjugationDrillGameOverTitle, style: SpaceTheme.headlineStyle),
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
              s.conjugationDrillGameOverLabel,
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
            child: Text(s.backToMenu),
          ),
          ElevatedButton(
            autofocus: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              _buildChallenges();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: SpaceTheme.planetOrange),
            child: Text(s.gameReplay),
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
    final s = S.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          s.conjugationDrillNoData,
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
        _buildProgressBar(),
        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                _buildVerbCard(challenge),
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
                  s.conjugationDrillTitle,
                  style: SpaceTheme.titleStyle
                      .copyWith(color: SpaceTheme.starYellow),
                ),
                Text(
                  s.gameCorrectOfTotal(_correct, _total),
                  style:
                      SpaceTheme.bodyStyle.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      valueColor:
          const AlwaysStoppedAnimation<Color>(SpaceTheme.alienGreen),
      minHeight: 4,
    );
  }

  Widget _buildVerbCard(_ConjugationChallenge challenge) {
    final s = S.of(context)!;
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
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
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
              s.conjugationDrillPrompt,
              style: SpaceTheme.bodyStyle.copyWith(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              challenge.verb.word,
              style: SpaceTheme.headlineStyle.copyWith(
                fontSize: 36,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color:
                    SpaceTheme.planetOrange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: SpaceTheme.planetOrange.withValues(alpha: 0.6)),
              ),
              child: Text(
                challenge.pronoun,
                style: const TextStyle(
                  color: SpaceTheme.planetOrange,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (challenge.verb.cefrLevel != null) ...[
              const SizedBox(height: 8),
              CefrChip(challenge.verb.cefrLevel!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptions(_ConjugationChallenge challenge) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3.0,
      physics: const NeverScrollableScrollPhysics(),
      children:
          List.generate(challenge.options.length, (i) => _buildOption(challenge, i)),
    );
  }

  Widget _buildOption(_ConjugationChallenge challenge, int index) {
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
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
                    color: text, fontSize: 17, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
