// Local-only privacy policy, presented in the interface language.
import 'package:flutter/material.dart';

import '../../core/theme/space_theme.dart';
import '../../generated/l10n.dart';

class PrivacyPolicyDialog extends StatelessWidget {
  const PrivacyPolicyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    return Dialog(
      backgroundColor: SpaceTheme.deepSpace,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      color: SpaceTheme.starYellow, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.privacyTitle,
                        style: SpaceTheme.headlineStyle.copyWith(fontSize: 22)),
                  ),
                  IconButton(
                    tooltip: s.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _PolicySection(
                          title: s.privacyBriefTitle, body: s.privacyBriefBody),
                      _PolicySection(
                          title: s.privacyStorageTitle,
                          body: s.privacyStorageBody),
                      _PolicySection(
                          title: s.privacyNetworkTitle,
                          body: s.privacyNetworkBody),
                      _PolicySection(
                          title: s.privacyCrashTitle, body: s.privacyCrashBody),
                      _PolicySection(
                          title: s.privacyMinorsTitle,
                          body: s.privacyMinorsBody),
                      _PolicySection(
                          title: s.privacyRightsTitle,
                          body: s.privacyRightsBody),
                      _PolicySection(
                          title: s.privacyChangesTitle,
                          body: s.privacyChangesBody),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;
  const _PolicySection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: SpaceTheme.titleStyle
                  .copyWith(fontSize: 16, color: SpaceTheme.starYellow)),
          const SizedBox(height: 6),
          Text(body,
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}
