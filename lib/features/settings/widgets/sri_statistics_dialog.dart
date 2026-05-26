// lib/features/settings/widgets/sri_statistics_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sri_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
// FIX: Import the skill category model to get GradeLevel
import '../../../core/models/skill_category.dart';

/// A dialog that displays detailed learning statistics from the SriService.
/// It provides parents with an at-a-glance overview of their child's progress.
class SriStatisticsDialog extends StatelessWidget {
  const SriStatisticsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final sriService = context.watch<SriService>();
    final s = S.of(context)!;

    // FIX: Use the correct getter names from SriService
    final total = sriService.totalTrackedItems;
    final mastered = sriService.masteredItemCount;
    final learning = sriService.learningItemCount;
    
    final masteryPercent = total > 0 ? mastered / total : 0.0;
    final detailedData = sriService.getDetailedBreakdown();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2235).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SpaceTheme.nebulaPurple, width: 2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600), // Widen for the new matrix
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${s.sriStatisticsTitle} 🧠", style: SpaceTheme.headlineStyle),
                const SizedBox(height: 8),
                Text(s.sriStatisticsDesc, style: SpaceTheme.bodyStyle.copyWith(color: Colors.white70), textAlign: TextAlign.center),
                const SizedBox(height: 24),

                _buildMasteryMeter(context, masteryPercent),
                const SizedBox(height: 24),

                _buildSummarySection(context, total, mastered, learning),
                const Divider(color: SpaceTheme.nebulaPurple, height: 32),
                
                // FIX: Use the new LanguageSkillsMatrix instead of the old heatmap
                _buildLanguageSkillsMatrix(context, detailedData),

                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: SpaceTheme.primaryButtonStyle.copyWith(
                    backgroundColor: WidgetStateProperty.all(SpaceTheme.deepSpace),
                    side: WidgetStateProperty.all(const BorderSide(color: SpaceTheme.cosmicPink)),
                  ),
                  child: Text(s.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildMasteryMeter(BuildContext context, double percent) {
    return Column(
      children: [
        Text(S.of(context)!.sriMastery, style: SpaceTheme.titleStyle),
        const SizedBox(height: 12),
        SizedBox(
          width: 250,
          child: Stack(
            alignment: Alignment.center,
            children: [
              LinearProgressIndicator(
                value: percent,
                minHeight: 20,
                backgroundColor: SpaceTheme.deepSpace,
                valueColor: const AlwaysStoppedAnimation<Color>(SpaceTheme.alienGreen),
                borderRadius: BorderRadius.circular(10),
              ),
              Text(
                '${(percent * 100).toStringAsFixed(0)}%',
                style: SpaceTheme.titleStyle.copyWith(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummarySection(BuildContext context, int total, int mastered, int learning) {
    return IntrinsicHeight(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(context, S.of(context)!.sriTotal, total.toString(), Icons.functions),
          const VerticalDivider(color: SpaceTheme.nebulaPurple, indent: 8, endIndent: 8),
          _buildStatItem(context, S.of(context)!.sriMastered, mastered.toString(), Icons.star),
          const VerticalDivider(color: SpaceTheme.nebulaPurple, indent: 8, endIndent: 8),
          _buildStatItem(context, S.of(context)!.sriLearning, learning.toString(), Icons.school),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Icon(icon, color: SpaceTheme.starYellow, size: 24),
          const SizedBox(height: 4),
          Text(value, style: SpaceTheme.headlineStyle.copyWith(fontSize: 20)),
          Text(label, style: SpaceTheme.bodyStyle.copyWith(fontSize: 12, color: Colors.white70), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // --- FIX: New widget to display Language Skills ---
  Widget _buildLanguageSkillsMatrix(BuildContext context, Map<LanguageSkillType, Map<int, CompetenceStat>> data) {
    final s = S.of(context)!;
    // Define which skills to show. You can expand this list.
    final skillsToShow = [
      LanguageSkillType.spelling,
      LanguageSkillType.articleSelection,
      LanguageSkillType.caseUsage,
      LanguageSkillType.verbConjugation,
    ];
    // Define the grade columns to show
    final gradesToShow = [1, 2, 3, 4, 5, 6];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.grid_view_sharp, color: SpaceTheme.cosmicPink, size: 20),
            const SizedBox(width: 8),
            Text(s.progressMatrixTitle, style: SpaceTheme.titleStyle.copyWith(fontSize: 18)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          s.progressMatrixDesc,
          style: SpaceTheme.bodyStyle.copyWith(fontSize: 12, color: Colors.white60)
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: SpaceTheme.deepSpace.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              // Header Row (Grades)
              Row(
                children: [
                  const Expanded(flex: 3, child: SizedBox()), // Spacer for skill labels
                  ...gradesToShow.map((grade) => Expanded(
                    flex: 1,
                    child: Center(child: Text(
                      '${s.grade3[0]}$grade', // "L" + "1" = "L1" (using "Level 1" -> "L")
                      style: SpaceTheme.bodyStyle.copyWith(fontSize: 12, fontWeight: FontWeight.bold)
                    )),
                  )).toList(),
                ],
              ),
              const SizedBox(height: 8),

              // Data Rows (Skills)
              ...skillsToShow.map((skill) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      // Skill Label (Y-axis)
                      Expanded(
                        flex: 3,
                        child: Text(
                          _getSkillLabel(skill),
                          style: SpaceTheme.bodyStyle.copyWith(fontSize: 12, color: Colors.white70),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Heatmap Cells
                      ...gradesToShow.map((grade) {
                        final stat = data[skill]?[grade] ?? CompetenceStat(
                          tracked: 0, mastered: 0, averageEasiness: 0, totalAttempts: 0, successRate: 0
                        );
                        
                        final color = stat.tracked > 0 
                            ? _getColorForEasiness(stat.averageEasiness)
                            : Colors.grey.shade800;
                        
                        return Expanded(
                          flex: 1,
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: Container(
                              margin: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: color.withValues(alpha: 0.5), width: 1)
                              ),
                              child: stat.tracked > 0
                                ? Center(
                                    child: Text(
                                      stat.tracked.toString(),
                                      style: SpaceTheme.titleStyle.copyWith(
                                        fontSize: 14,
                                        color: color == SpaceTheme.starYellow ? Colors.black.withValues(alpha: 0.7) : Colors.white,
                                        shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 2)],
                                      ),
                                    ),
                                  )
                                : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  /// Helper to get a display name for a LanguageSkillType
  String _getSkillLabel(LanguageSkillType skill) {
    switch (skill) {
      case LanguageSkillType.spelling:
        return 'Rechtschreibung';
      case LanguageSkillType.articleSelection:
        return 'Artikel (der/die/das)';
      case LanguageSkillType.pluralForm:
        return 'Mehrzahl';
      case LanguageSkillType.wordType:
        return 'Wortarten';
      case LanguageSkillType.sentenceStructure:
        return 'Satzbau';
      case LanguageSkillType.punctuation:
        return 'Zeichensetzung';
      case LanguageSkillType.capitalization:
        return 'Großschreibung';
      case LanguageSkillType.verbConjugation:
        return 'Verben (Zeitformen)';
      case LanguageSkillType.caseUsage:
        return 'Fälle (Kasus)';
      case LanguageSkillType.vocabulary:
        return 'Wortschatz';
      case LanguageSkillType.reading:
        return 'Lesen im Kontext';
    }
  }

  /// Helper to determine cell color from easiness factor
  Color _getColorForEasiness(double easiness) {
    if (easiness >= 3.5) return SpaceTheme.alienGreen; // Consistently correct
    if (easiness > 2.5) return SpaceTheme.starYellow; // More right than wrong
    if (easiness > 1.3) return SpaceTheme.planetOrange; // More wrong than right
    if (easiness > 0) return SpaceTheme.rocketRed; // Consistently wrong
    return Colors.grey.shade800; // No data
  }
}