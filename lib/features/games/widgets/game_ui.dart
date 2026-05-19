import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/space_theme.dart';
import '../providers/game_provider.dart';

/// A smart, responsive, and backward-compatible UI header for all mini-games.
///
/// This widget uses a [LayoutBuilder] to automatically detect the available
/// width and switch between a full and a compact layout. It also supports
/// an optional [customTitleWidget] for older games that require it.
class GameUI extends StatelessWidget {
  final String title;
  final int level;
  final int? timeLeft;
  final VoidCallback onBack;
  final Widget? customTitleWidget; // For backward compatibility

  const GameUI({
    super.key,
    required this.title,
    required this.level,
    this.timeLeft,
    required this.onBack,
    this.customTitleWidget, // Optional parameter
  });

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder allows this widget to be self-aware and responsive.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Define a "breakpoint". If the available width is less than this,
        // we switch to the compact layout.
        const double compactLayoutBreakpoint = 650.0;
        final bool isCompact = constraints.maxWidth < compactLayoutBreakpoint;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12 : 16,
            vertical: 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Back Button
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: isCompact ? 22 : 28,
                ),
                onPressed: onBack,
              ),
              
              SizedBox(width: isCompact ? 12 : 16),
              
              // Title Area
              Expanded(
                // Use the custom widget if provided; otherwise, use the default Text title.
                child: customTitleWidget ?? Text(
                  title,
                  style: SpaceTheme.headlineStyle.copyWith(
                    fontSize: isCompact ? 20 : 28,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              
              // Game Stats
              _buildStatsRow(context, isCompact),
            ],
          ),
        );
      },
    );
  }

  /// Helper method to build the row of stats.
  Widget _buildStatsRow(BuildContext context, bool isCompact) {
    return Row(
      children: [
        // Level
        _buildStatItem(
          icon: Icons.emoji_events,
          label: isCompact ? '' : 'Level', // Hide label if compact
          value: level.toString(),
          color: SpaceTheme.starYellow,
          isCompact: isCompact,
        ),
        
        SizedBox(width: isCompact ? 8 : 12),
        
        // Score
        Consumer<GameProvider>(
          builder: (context, gameProvider, child) {
            return _buildStatItem(
              icon: Icons.star,
              label: isCompact ? '' : 'Score', // Hide label if compact
              value: gameProvider.score.toString(),
              color: SpaceTheme.alienGreen,
              isCompact: isCompact,
            );
          },
        ),
        
        // Time (if provided)
        if (timeLeft != null) ...[
          SizedBox(width: isCompact ? 8 : 12),
          _buildStatItem(
            icon: Icons.timer,
            label: isCompact ? '' : 'Time', // Hide label if compact
            value: _formatTime(timeLeft!),
            color: timeLeft! > 10 ? SpaceTheme.cosmicPink : SpaceTheme.rocketRed,
            isCompact: isCompact,
          ),
        ],
      ],
    );
  }

  /// Helper method for rendering a single stat item, adapted for size.
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isCompact,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 12,
        vertical: isCompact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: isCompact ? 18 : 20),
          // Conditionally show the label text, hiding it if the label is empty.
          if (label.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              '$label: $value',
              style: SpaceTheme.bodyStyle.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ] else ...[
            const SizedBox(width: 6),
            Text(
              value,
              style: SpaceTheme.bodyStyle.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  /// Formats the time from seconds into a M:SS string.
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}