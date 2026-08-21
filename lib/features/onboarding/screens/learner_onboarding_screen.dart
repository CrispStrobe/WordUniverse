import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/learner_profile_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../features/games/providers/game_provider.dart';
import '../../../generated/l10n.dart';
import '../../../features/games/widgets/space_background.dart';

class LearnerOnboardingScreen extends StatefulWidget {
  const LearnerOnboardingScreen({super.key});

  @override
  State<LearnerOnboardingScreen> createState() =>
      _LearnerOnboardingScreenState();
}

class _LearnerOnboardingScreenState extends State<LearnerOnboardingScreen> {
  String _learningLanguage = 'de';
  LearnerGoal _goal = LearnerGoal.balanced;
  int _band = 1;
  int _minutes = 10;
  bool _saving = false;

  Future<void> _continue() async {
    if (_saving) return;
    setState(() => _saving = true);
    await context
        .read<VocabularyService>()
        .rememberLearningLanguage(_learningLanguage);
    context.read<GameProvider>().setGrade(_band);
    await context.read<LearnerProfileService>().completeOnboarding(
          goal: _goal,
          sessionMinutes: _minutes,
        );
    if (mounted) Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SpaceTheme.deepSpace.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: SpaceTheme.starYellow.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.onboardingWelcomeTitle,
                          style:
                              SpaceTheme.headlineStyle.copyWith(fontSize: 28)),
                      const SizedBox(height: 6),
                      Text(s.onboardingWelcomeBody,
                          style: SpaceTheme.bodyStyle),
                      const SizedBox(height: 22),
                      _section(
                          s.onboardingLearningLanguage,
                          SegmentedButton<String>(
                            segments: [
                              ButtonSegment(
                                  value: 'de', label: Text(s.languageGerman)),
                              ButtonSegment(
                                  value: 'en', label: Text(s.languageEnglish)),
                            ],
                            selected: {_learningLanguage},
                            onSelectionChanged: (v) =>
                                setState(() => _learningLanguage = v.first),
                          )),
                      _section(
                          s.onboardingGoal,
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _goalChip(LearnerGoal.balanced, s.goalBalanced),
                            _goalChip(LearnerGoal.vocabulary, s.goalVocabulary),
                            _goalChip(LearnerGoal.spelling, s.goalSpelling),
                            _goalChip(LearnerGoal.grammar, s.goalGrammar),
                            _goalChip(LearnerGoal.dafDaz, s.goalDafDaz),
                          ])),
                      _section(
                          s.onboardingStartBand,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: List.generate(4, (i) {
                                    final value = i + 1;
                                    return ChoiceChip(
                                      label: Text(s.gradeN(value)),
                                      selected: _band == value,
                                      onSelected: (_) =>
                                          setState(() => _band = value),
                                    );
                                  })),
                              const SizedBox(height: 8),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Text(
                                  _bandDescription(s),
                                  key: ValueKey(_band),
                                  style: SpaceTheme.bodyStyle
                                      .copyWith(color: Colors.white70),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s.onboardingBandNote,
                                style: SpaceTheme.bodyStyle.copyWith(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )),
                      _section(
                          s.onboardingDailyTime,
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 5, label: Text('5 min')),
                              ButtonSegment(value: 10, label: Text('10 min')),
                              ButtonSegment(value: 15, label: Text('15 min')),
                            ],
                            selected: {_minutes},
                            onSelectionChanged: (v) =>
                                setState(() => _minutes = v.first),
                          )),
                      const SizedBox(height: 22),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _continue,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.arrow_forward),
                          label: Text(s.onboardingContinue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: SpaceTheme.titleStyle.copyWith(fontSize: 16)),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _goalChip(LearnerGoal value, String label) => ChoiceChip(
        label: Text(label),
        selected: _goal == value,
        onSelected: (_) => setState(() => _goal = value),
      );

  String _bandDescription(S s) => switch (_band) {
        1 => s.grade3Desc,
        2 => s.grade4Desc,
        3 => s.grade5Desc,
        _ => s.grade6Desc,
      };
}
