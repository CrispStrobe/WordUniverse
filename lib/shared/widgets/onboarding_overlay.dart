// lib/shared/widgets/onboarding_overlay.dart
//
// One-tap "how to play" overlay. Stack this on top of a game with
// [OnboardingOverlay.maybeShow(...)] inside initState. The widget
// shows once per game (keyed by gameKey, stored in SharedPreferences);
// subsequent runs no-op.
//
// Pass [steps] as a list of (icon, body) — typically 3 short cards.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/space_theme.dart';
import '../../generated/l10n.dart';

class OnboardingStep {
  final IconData icon;
  final String body;
  const OnboardingStep({required this.icon, required this.body});
}

class OnboardingOverlay extends StatefulWidget {
  final String title;
  final List<OnboardingStep> steps;
  final VoidCallback onDismiss;

  const OnboardingOverlay({
    super.key,
    required this.title,
    required this.steps,
    required this.onDismiss,
  });

  static String _key(String gameKey) => 'onboarding_seen_$gameKey';

  /// Returns true iff the user has already dismissed the overlay for
  /// this game.
  static Future<bool> hasBeenSeen(String gameKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(gameKey)) ?? false;
  }

  /// Marks the overlay as seen for this game.
  static Future<void> markSeen(String gameKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(gameKey), true);
  }

  /// Convenience: from any StatefulWidget's `initState`, schedule a
  /// post-frame callback that pushes this overlay if and only if it
  /// hasn't been seen before. Marks it seen on dismiss.
  static void maybeShow(
    BuildContext context, {
    required String gameKey,
    required String title,
    required List<OnboardingStep> steps,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await hasBeenSeen(gameKey)) return;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => OnboardingOverlay(
          title: title,
          steps: steps,
          onDismiss: () => Navigator.of(dialogContext).pop(),
        ),
      );
      await markSeen(gameKey);
    });
  }

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final isLast = _index == widget.steps.length - 1;
    final step = widget.steps[_index];

    return Dialog(
      backgroundColor: SpaceTheme.deepSpace,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title,
                style: SpaceTheme.headlineStyle.copyWith(fontSize: 22),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [SpaceTheme.nebulaPurple, SpaceTheme.spaceBlue],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(step.icon, size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  Text(step.body,
                      style: SpaceTheme.bodyStyle.copyWith(
                          fontSize: 15, color: Colors.white),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Page indicator dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < widget.steps.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? SpaceTheme.starYellow
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: widget.onDismiss,
                  child: Text(s.skip,
                      style: const TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  autofocus: true,
                  onPressed: () {
                    if (isLast) {
                      widget.onDismiss();
                    } else {
                      setState(() => _index++);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SpaceTheme.starYellow,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(isLast ? s.gotIt : s.next),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
