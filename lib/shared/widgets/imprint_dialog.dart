import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';

class ImprintDialog extends StatelessWidget {
  const ImprintDialog({super.key});

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // Could not launch
      debugPrint("Could not launch $urlString");
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    
    return SimpleDialog(
      backgroundColor: SpaceTheme.deepSpace,
      title: Text(
        s.imprint,
        style: SpaceTheme.headlineStyle.copyWith(color: SpaceTheme.starYellow),
      ),
      contentPadding: const EdgeInsets.all(24.0),
      children: [
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.4, // Constrain width
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSectionTitle(s.imprintServiceProvider),
                _buildSectionText(s.imprintProviderAddress),
                
                const SizedBox(height: 16),
                _buildSectionTitle(s.imprintContact),
                _buildSectionText(s.imprintContactDetails),

                const SizedBox(height: 16),
                _buildSectionTitle(s.imprintContentResponsible),
                _buildSectionText(s.imprintProviderAddress), // Assumes same address

                const SizedBox(height: 16),
                _buildSectionTitle(s.imprintDisclaimer),
                _buildSectionText(s.imprintDisclaimerText),

                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () => _launchURL('https://www.crispstro.be'), // URL remains hard-coded
                    child: Text(
                      s.imprintWebsite, // Text is localized
                      style: SpaceTheme.bodyStyle.copyWith(
                        color: SpaceTheme.alienGreen,
                        decoration: TextDecoration.underline,
                        decorationColor: SpaceTheme.alienGreen,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: SpaceTheme.primaryButtonStyle,
                    child: Text(s.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: SpaceTheme.titleStyle.copyWith(color: Colors.white, fontSize: 18),
    );
  }

  Widget _buildSectionText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Text(
        text,
        style: SpaceTheme.bodyStyle.copyWith(color: Colors.white70, fontSize: 14),
      ),
    );
  }
}

