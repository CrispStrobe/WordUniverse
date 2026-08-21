import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/services/learner_profile_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../../games/providers/game_provider.dart';
import '../../games/screens/cloze_flash_game.dart';
import '../../games/screens/definition_quiz_game.dart';
import '../../games/screens/sentence_completion_game.dart';
import '../../games/screens/spelling_spotter_game.dart';
import '../../games/screens/sri_review_game.dart';
import '../../games/screens/word_sort_game.dart';
import '../../games/widgets/space_background.dart';

class DailySessionScreen extends StatefulWidget {
  const DailySessionScreen({super.key});

  @override
  State<DailySessionScreen> createState() => _DailySessionScreenState();
}

class _DailySessionScreenState extends State<DailySessionScreen> {
  late final int _attemptsAtStart;
  late final int _masteredAtStart;

  @override
  void initState() {
    super.initState();
    final sri = context.read<SriService>();
    _attemptsAtStart = sri.totalAttempts;
    _masteredAtStart = sri.totalMasteredItems;
  }

  GradeLevel get _band {
    final band = context.read<GameProvider>().grade.clamp(1, 4);
    return gradeLevelFromBand(band);
  }

  Future<void> _play(int step, Widget screen) async {
    final game = context.read<GameProvider>();
    final before = game.totalGamesPlayed;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted || game.totalGamesPlayed == before) return;
    await context.read<LearnerProfileService>().completeDailyStep(step);
  }

  Widget _goalGame(LearnerGoal goal) {
    switch (goal) {
      case LearnerGoal.spelling:
        return SpellingSpotterGame(gradeLevel: _band);
      case LearnerGoal.grammar:
        return WordSortGame(gradeLevel: _band);
      case LearnerGoal.dafDaz:
        return SentenceCompletionGame(gradeLevel: _band);
      case LearnerGoal.vocabulary:
      case LearnerGoal.balanced:
        return DefinitionQuizGame(gradeLevel: _band);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final profile = context.watch<LearnerProfileService>();
    final sri = context.watch<SriService>();
    final completed = profile.dailyCompletedSteps;
    final allDone = completed.length >= 3;
    final compact = MediaQuery.sizeOf(context).height < 500;

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.dailySessionTitle,
                              style: SpaceTheme.headlineStyle
                                  .copyWith(fontSize: compact ? 24 : 28)),
                          Text(s.dailySessionSubtitle(profile.sessionMinutes),
                              style: SpaceTheme.bodyStyle),
                        ]),
                  ),
                  Text('${completed.length}/3',
                      style: SpaceTheme.titleStyle
                          .copyWith(color: SpaceTheme.starYellow)),
                ]),
                SizedBox(height: compact ? 8 : 18),
                if (allDone)
                  Expanded(
                    child: _Summary(
                      attempts: sri.totalAttempts - _attemptsAtStart,
                      mastered: sri.totalMasteredItems - _masteredAtStart,
                      onAgain: profile.resetDailySession,
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      children: [
                        _StepCard(
                          index: 1,
                          title: sri.getAvailableReviewCount() > 0
                              ? s.dailyReviewTitle
                              : s.dailyWarmupTitle,
                          subtitle: sri.getAvailableReviewCount() > 0
                              ? s.dailyReviewSubtitle(
                                  sri.getAvailableReviewCount())
                              : s.dailyWarmupSubtitle,
                          icon: Icons.refresh,
                          done: completed.contains(1),
                          compact: compact,
                          onTap: () => _play(
                              1,
                              sri.getAvailableReviewCount() > 0
                                  ? const SriReviewGame()
                                  : SentenceCompletionGame(gradeLevel: _band)),
                        ),
                        _StepCard(
                          index: 2,
                          title: s.dailyGoalTitle,
                          subtitle: s.dailyGoalSubtitle,
                          icon: Icons.track_changes,
                          done: completed.contains(2),
                          compact: compact,
                          onTap: () => _play(2, _goalGame(profile.goal)),
                        ),
                        _StepCard(
                          index: 3,
                          title: s.dailyContextTitle,
                          subtitle: s.dailyContextSubtitle,
                          icon: Icons.auto_stories,
                          done: completed.contains(3),
                          compact: compact,
                          onTap: () =>
                              _play(3, ClozeFlashGame(gradeLevel: _band)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.done,
    required this.compact,
    required this.onTap,
  });
  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool done;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.symmetric(vertical: compact ? 3 : 4),
        color: SpaceTheme.deepSpace.withValues(alpha: 0.88),
        child: ListTile(
          dense: compact,
          visualDensity:
              compact ? VisualDensity.compact : VisualDensity.standard,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 18,
            vertical: compact ? 0 : 10,
          ),
          leading: CircleAvatar(
            backgroundColor:
                done ? SpaceTheme.alienGreen : SpaceTheme.starYellow,
            child: done
                ? const Icon(Icons.check, color: Colors.white)
                : Text('$index', style: const TextStyle(color: Colors.black)),
          ),
          title: Text(
            title,
            style:
                SpaceTheme.titleStyle.copyWith(fontSize: compact ? 18 : null),
          ),
          subtitle: Text(
            subtitle,
            style: SpaceTheme.bodyStyle.copyWith(fontSize: compact ? 13 : null),
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(done ? Icons.replay : icon, color: Colors.white70),
          onTap: onTap,
        ),
      );
}

class _Summary extends StatelessWidget {
  const _Summary(
      {required this.attempts, required this.mastered, required this.onAgain});
  final int attempts;
  final int mastered;
  final Future<void> Function() onAgain;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.9),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.verified,
                  size: 64, color: SpaceTheme.alienGreen),
              const SizedBox(height: 12),
              Text(s.dailyCompleteTitle, style: SpaceTheme.headlineStyle),
              const SizedBox(height: 8),
              Text(
                  s.dailyCompleteSummary(
                      attempts.clamp(0, 999), mastered.clamp(0, 999)),
                  textAlign: TextAlign.center,
                  style: SpaceTheme.bodyStyle),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onAgain,
                icon: const Icon(Icons.replay),
                label: Text(s.dailyPractiseMore),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
