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

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../models/game_outcome.dart';
import '../providers/game_provider.dart';
import '../services/spelling_spotter_service.dart';
import '../widgets/cefr_chip.dart';
import '../widgets/space_background.dart';
import '../../../shared/widgets/onboarding_overlay.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

enum _ChallengeType { definition, article, spelling }

class _ReviewChallenge {
  final GermanWord word;
  final SriLanguageData sriData;
  final _ChallengeType type;
  /// Prompt displayed above the options (definition, "Der/Die/Das ___?", …)
  final String prompt;
  final List<String> options;
  final int correctIndex;

  const _ReviewChallenge({
    required this.word,
    required this.sriData,
    required this.type,
    required this.prompt,
    required this.options,
    required this.correctIndex,
  });
}

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
  List<_ReviewChallenge> _challenges = [];
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
    _buildChallenges();
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
      'SPELL_', 'ARTICLE_', 'PLURAL_', 'WORDTYPE_', 'SENTENCE_',
      'PUNCT_', 'CAPITAL_', 'CONJUG_', 'CASE_',
    ];
    var id = d.itemId;
    for (final p in prefixes) {
      if (id.startsWith(p)) return id.substring(p.length);
    }
    return id;
  }

  GermanWord? _findWord(String baseWord) {
    final lower = baseWord.toLowerCase();
    return _vocabService.getAllWords(_gameProvider)
        .where((w) => w.word.toLowerCase() == lower || w.lemma.toLowerCase() == lower)
        .firstOrNull;
  }

  void _buildChallenges() {
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

    final allWords = _vocabService.getAllWords(_gameProvider);
    // Build the valid-words set for spelling distractor filtering.
    final validWords = allWords.map((w) => w.word.toLowerCase()).toSet();

    final challenges = <_ReviewChallenge>[];
    for (final item in sriItems) {
      if (challenges.length >= _targetRounds) break;
      final base = _baseWordFromId(item);
      final word = _findWord(base);
      if (word == null) continue;

      final challenge = _buildChallenge(word, item, allWords, validWords);
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

  _ReviewChallenge? _buildChallenge(
    GermanWord word,
    SriLanguageData sriData,
    List<GermanWord> allWords,
    Set<String> validWords,
  ) {
    // Try the skill-specific format first, fall back to definition quiz.
    if (sriData.skillType == LanguageSkillType.articleSelection &&
        _isDE &&
        word.wordType == GermanWordType.substantiv &&
        word.article != null &&
        ['der', 'die', 'das'].contains(word.article!.toLowerCase())) {
      return _buildArticleChallenge(word, sriData);
    }

    if (sriData.skillType == LanguageSkillType.spelling) {
      final c = _buildSpellingChallenge(word, sriData, validWords);
      if (c != null) return c;
    }

    return _buildDefinitionChallenge(word, sriData, allWords);
  }

  _ReviewChallenge? _buildArticleChallenge(
      GermanWord word, SriLanguageData sriData) {
    final correct = word.article!.toLowerCase();
    final wrong = ['der', 'die', 'das'].where((a) => a != correct).toList();
    final options = [correct, ...wrong]..shuffle(_rng);
    final prompt = _s.articleChallengePrompt(word.word);
    return _ReviewChallenge(
      word: word,
      sriData: sriData,
      type: _ChallengeType.article,
      prompt: prompt,
      options: options,
      correctIndex: options.indexOf(correct),
    );
  }

  _ReviewChallenge? _buildSpellingChallenge(
      GermanWord word, SriLanguageData sriData, Set<String> validWords) {
    final displayWord = normWord(word.word);
    if (displayWord.contains(' ')) return null;

    final rawErrors = _isDE
        ? (word.commonMistakes ?? <String>[])
        : (word.apiEnrichment?.commonLearnerErrors ?? <String>[]);
    final errors = parseErrors(rawErrors)
        .map(normWord)
        .where((e) =>
            e.toLowerCase() != displayWord.toLowerCase() &&
            e.isNotEmpty &&
            !e.contains(' ') &&
            !validWords.contains(e.toLowerCase()))
        .take(_optionCount - 1)
        .toList();

    if (errors.isEmpty) return null;

    final options = [displayWord, ...errors]..shuffle(_rng);
    final definition = word.apiEnrichment?.definitions.firstOrNull;
    final prompt = definition != null
        ? _s.spellingForDefinition(definition)
        : _s.spellingSpotterPrompt;
    return _ReviewChallenge(
      word: word,
      sriData: sriData,
      type: _ChallengeType.spelling,
      prompt: prompt,
      options: options,
      correctIndex: options.indexOf(displayWord),
    );
  }

  _ReviewChallenge? _buildDefinitionChallenge(
      GermanWord word, SriLanguageData sriData, List<GermanWord> allWords) {
    final definition = word.apiEnrichment?.definitions.firstOrNull;
    if (definition == null) return null;

    final correctOption = word.word;
    // Prefer same grade, same type as distractors.
    final distractors = <String>{};
    final pool = (allWords
          .where((w) =>
              w.id != word.id &&
              !w.isProperNoun &&
              (w.apiEnrichment?.definitions.isNotEmpty ?? false))
          .toList()
        ..shuffle(_rng));

    for (final w in pool) {
      if (distractors.length >= _optionCount - 1) break;
      final opt = w.word;
      if (opt != correctOption) distractors.add(opt);
    }

    if (distractors.isEmpty) return null;

    final options = [correctOption, ...distractors.take(_optionCount - 1)]
      ..shuffle(_rng);
    final prompt = '"$definition"';
    return _ReviewChallenge(
      word: word,
      sriData: sriData,
      type: _ChallengeType.definition,
      prompt: prompt,
      options: options,
      correctIndex: options.indexOf(correctOption),
    );
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

  Widget _buildHeader(_ReviewChallenge challenge) {
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
                  style:
                      SpaceTheme.titleStyle.copyWith(color: SpaceTheme.starYellow),
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

  Widget _buildDifficultyBanner(_ReviewChallenge challenge) {
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

  Widget _buildPromptCard(_ReviewChallenge challenge) {
    final typeLabel = switch (challenge.type) {
      _ChallengeType.article => _s.challengeTypeArticle,
      _ChallengeType.spelling => _s.challengeTypeSpelling,
      _ChallengeType.definition => _s.challengeTypeDefinition,
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

  Widget _buildOptions(_ReviewChallenge challenge) {
    return Column(
      children: List.generate(challenge.options.length, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildOption(challenge, i),
        );
      }),
    );
  }

  Widget _buildOption(_ReviewChallenge challenge, int index) {
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
        scale: (hasAnswered && isCorrect)
            ? 1.0 + (_pulseCtrl.value * 0.025)
            : 1.0,
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
