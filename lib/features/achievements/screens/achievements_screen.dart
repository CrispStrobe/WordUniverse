// lib/features/achievements/screens/achievements_screen.dart
//
// Shows the player which achievements they've unlocked from
// GameProvider._achievements. Read-only — unlocks happen in
// GameProvider._checkAchievements() on score/progress events.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../../games/providers/game_provider.dart';

class _AchievementInfo {
  final String title;
  final String description;
  final String icon;
  const _AchievementInfo(this.title, this.description, this.icon);
}

// Ordered IDs (drives both display order and total-count math).
const List<String> _kAchievementIds = [
  // Score-based
  'first_century',
  'score_master',
  'thousand_club',
  // Level-based
  'level_explorer',
  'space_commander',
  // Per-game (3 sessions)
  'triangle_wizard',
  'bubble_popper',
  'puzzle_solver',
  'number_walls_pro',
  'codebreaker_pro',
  'master_builder',
  'city_planner',
  'connection_expert',
  'antonym_ace',
  'synonym_scholar',
  'cloze_master',
  'translation_titan',
  'reverse_linguist',
  'syllable_counter',
  'expression_expert',
  'hypernym_hunter',
  'word_class_whiz',
  'proverb_sage',
  'conjugation_king',
  'verb_splitter',
  'definition_wizard',
  'sentence_smith',
  'spelling_sleuth',
  'homophone_hero',
  'confusable_pro',
  'review_regular',
  // Cross-game milestones
  'arithmetic_ace',
  'all_rounder',
];

// Icon-only catalog (icons aren't localized).
const Map<String, String> _kAchievementIcons = {
  'first_century': '💯',
  'score_master': '⭐',
  'thousand_club': '🚀',
  'level_explorer': '🌟',
  'space_commander': '👨‍🚀',
  'triangle_wizard': '🐍',
  'bubble_popper': '🏆',
  'puzzle_solver': '🔍',
  'number_walls_pro': '🧱',
  'codebreaker_pro': '🪐',
  'master_builder': '🏗️',
  'city_planner': '🏙️',
  'connection_expert': '🌌',
  'antonym_ace': '⚡',
  'synonym_scholar': '📚',
  'cloze_master': '✏️',
  'translation_titan': '🌍',
  'reverse_linguist': '🔄',
  'syllable_counter': '🎵',
  'expression_expert': '💬',
  'hypernym_hunter': '🌳',
  'word_class_whiz': '🏷️',
  'proverb_sage': '📜',
  'conjugation_king': '👑',
  'verb_splitter': '✂️',
  'definition_wizard': '🔮',
  'sentence_smith': '⚒️',
  'spelling_sleuth': '🔎',
  'homophone_hero': '👂',
  'confusable_pro': '🎯',
  'review_regular': '🔁',
  'arithmetic_ace': '🎯',
  'all_rounder': '🎮',
};

_AchievementInfo _infoFor(S s, String id) {
  switch (id) {
    case 'first_century':
      return _AchievementInfo(
          s.achievementFirstCenturyTitle, s.achievementFirstCenturyDesc, '💯');
    case 'score_master':
      return _AchievementInfo(
          s.achievementScoreMasterTitle, s.achievementScoreMasterDesc, '⭐');
    case 'thousand_club':
      return _AchievementInfo(
          s.achievementThousandClubTitle, s.achievementThousandClubDesc, '🚀');
    case 'level_explorer':
      return _AchievementInfo(s.achievementLevelExplorerTitle,
          s.achievementLevelExplorerDesc, '🌟');
    case 'space_commander':
      return _AchievementInfo(s.achievementSpaceCommanderTitle,
          s.achievementSpaceCommanderDesc, '👨‍🚀');
    case 'triangle_wizard':
      return _AchievementInfo(s.achievementTriangleWizardTitle,
          s.achievementTriangleWizardDesc, '🐍');
    case 'bubble_popper':
      return _AchievementInfo(s.achievementBubblePopperTitle,
          s.achievementBubblePopperDesc, '🏆');
    case 'puzzle_solver':
      return _AchievementInfo(s.achievementPuzzleSolverTitle,
          s.achievementPuzzleSolverDesc, '🔍');
    case 'number_walls_pro':
      return _AchievementInfo(s.achievementNumberWallsProTitle,
          s.achievementNumberWallsProDesc, '🧱');
    case 'codebreaker_pro':
      return _AchievementInfo(s.achievementCodebreakerProTitle,
          s.achievementCodebreakerProDesc, '🪐');
    case 'master_builder':
      return _AchievementInfo(s.achievementMasterBuilderTitle,
          s.achievementMasterBuilderDesc, '🏗️');
    case 'city_planner':
      return _AchievementInfo(s.achievementCityPlannerTitle,
          s.achievementCityPlannerDesc, '🏙️');
    case 'connection_expert':
      return _AchievementInfo(s.achievementConnectionExpertTitle,
          s.achievementConnectionExpertDesc, '🌌');
    case 'arithmetic_ace':
      return _AchievementInfo(s.achievementArithmeticAceTitle,
          s.achievementArithmeticAceDesc, '🎯');
    case 'all_rounder':
      return _AchievementInfo(
          s.achievementVielseitigTitle, s.achievementVielseitigDesc, '🎮');
    case 'antonym_ace':
      return _AchievementInfo(s.achievementAntonymAceTitle, s.achievementAntonymAceDesc, '⚡');
    case 'synonym_scholar':
      return _AchievementInfo(s.achievementSynonymScholarTitle, s.achievementSynonymScholarDesc, '📚');
    case 'cloze_master':
      return _AchievementInfo(s.achievementClozeMasterTitle, s.achievementClozeMasterDesc, '✏️');
    case 'translation_titan':
      return _AchievementInfo(s.achievementTranslationTitanTitle, s.achievementTranslationTitanDesc, '🌍');
    case 'reverse_linguist':
      return _AchievementInfo(s.achievementReverseLinguistTitle, s.achievementReverseLinguistDesc, '🔄');
    case 'syllable_counter':
      return _AchievementInfo(s.achievementSyllableCounterTitle, s.achievementSyllableCounterDesc, '🎵');
    case 'expression_expert':
      return _AchievementInfo(s.achievementExpressionExpertTitle, s.achievementExpressionExpertDesc, '💬');
    case 'hypernym_hunter':
      return _AchievementInfo(s.achievementHypernymHunterTitle, s.achievementHypernymHunterDesc, '🌳');
    case 'word_class_whiz':
      return _AchievementInfo(s.achievementWordClassWhizTitle, s.achievementWordClassWhizDesc, '🏷️');
    case 'proverb_sage':
      return _AchievementInfo(s.achievementProverbSageTitle, s.achievementProverbSageDesc, '📜');
    case 'conjugation_king':
      return _AchievementInfo(s.achievementConjugationKingTitle, s.achievementConjugationKingDesc, '👑');
    case 'verb_splitter':
      return _AchievementInfo(s.achievementVerbSplitterTitle, s.achievementVerbSplitterDesc, '✂️');
    case 'definition_wizard':
      return _AchievementInfo(s.achievementDefinitionWizardTitle, s.achievementDefinitionWizardDesc, '🔮');
    case 'sentence_smith':
      return _AchievementInfo(s.achievementSentenceSmithTitle, s.achievementSentenceSmithDesc, '⚒️');
    case 'spelling_sleuth':
      return _AchievementInfo(s.achievementSpellingSleutTitle, s.achievementSpellingSleutDesc, '🔎');
    case 'homophone_hero':
      return _AchievementInfo(s.achievementHomophoneHeroTitle, s.achievementHomophoneHeroDesc, '👂');
    case 'confusable_pro':
      return _AchievementInfo(s.achievementConfusableProTitle, s.achievementConfusableProDesc, '🎯');
    case 'review_regular':
      return _AchievementInfo(s.achievementReviewRegularTitle, s.achievementReviewRegularDesc, '🔁');
    default:
      return _AchievementInfo(id, '', _kAchievementIcons[id] ?? '🏅');
  }
}

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final gp = context.watch<GameProvider>();
    final unlockedById = {
      for (final a in gp.achievements) a.id: a,
    };
    final allIds = _kAchievementIds;
    final unlockedCount =
        allIds.where(unlockedById.containsKey).length;
    final totalCount = allIds.length;

    return Scaffold(
      backgroundColor: SpaceTheme.deepSpace,
      appBar: AppBar(
        title: Text(s.achievements),
        backgroundColor: SpaceTheme.deepSpace,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _ProgressBanner(
                unlocked: unlockedCount, total: totalCount),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: allIds.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final id = allIds[i];
                final info = _infoFor(s, id);
                final unlocked = unlockedById[id];
                return _AchievementTile(
                  info: info,
                  unlockedAt: unlocked?.unlockedAt,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  final int unlocked;
  final int total;
  const _ProgressBanner({required this.unlocked, required this.total});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final ratio = total > 0 ? unlocked / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SpaceTheme.nebulaPurple, SpaceTheme.spaceBlue],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.achievementsBannerProgress(unlocked, total),
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(SpaceTheme.starYellow),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final _AchievementInfo info;
  final DateTime? unlockedAt;
  const _AchievementTile({required this.info, required this.unlockedAt});

  @override
  Widget build(BuildContext context) {
    final isUnlocked = unlockedAt != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUnlocked
            ? SpaceTheme.nebulaPurple.withValues(alpha: 0.35)
            : SpaceTheme.deepSpace,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnlocked
              ? SpaceTheme.starYellow.withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Opacity(
            opacity: isUnlocked ? 1.0 : 0.35,
            child: Text(info.icon, style: const TextStyle(fontSize: 32)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  style: SpaceTheme.titleStyle.copyWith(
                    fontSize: 15,
                    color: isUnlocked ? Colors.white : Colors.white54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.description,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    color: isUnlocked ? Colors.white70 : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
          if (isUnlocked)
            const Icon(Icons.check_circle,
                color: SpaceTheme.alienGreen, size: 24)
          else
            const Icon(Icons.lock_outline,
                color: Colors.white24, size: 22),
        ],
      ),
    );
  }
}
