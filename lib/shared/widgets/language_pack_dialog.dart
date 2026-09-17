// lib/shared/widgets/language_pack_dialog.dart
//
// The one place the user is asked about a language pack, and the one gate that
// stands between "pack missing" and "game starts".
//
// [ensureLanguagePackReady] is called before any game launches. When the
// active pack is loaded it returns immediately; otherwise it shows
// [LanguagePackDialog], which discloses the download size and license (Apple
// App Store Review Guidelines §2.4.2/§4.2.3), reports progress, and on
// repeated failure offers the bundled fallback pack so the app stays usable.
// Nothing downloads without an explicit tap.

export 'language_pack_gate.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/language_pack.dart';
import '../../core/services/language_pack_service.dart';
import '../../core/theme/space_theme.dart';
import '../../generated/l10n.dart';
import '../utils/load_status_localization.dart';

/// Makes sure the active learning language is playable, prompting for the
/// download if needed. Returns true when it is safe to start a game.
///
/// Call this before pushing any game screen: a missing pack otherwise means an
/// empty vocabulary, and an empty vocabulary means a crash inside the game.
Future<bool> ensureLanguagePackReady(BuildContext context) async {
  final service = context.read<LanguagePackService>();
  final saved = await service.savedLanguageStatus();
  if (!context.mounted) return false;
  if (service.isActivePackReady) return true;

  final accepted = await showLanguagePackDialog(
        context,
        languageCode: saved.code,
        // Already downloaded but not loaded (e.g. after a failed switch):
        // nothing to consent to, just load it.
        skipConsent: saved.installed,
      ) ??
      false;
  return accepted && context.mounted && service.isActivePackReady;
}

/// Shows the pack installer for [languageCode]. Resolves to true when that
/// pack (or the fallback the user accepted) is ready.
Future<bool?> showLanguagePackDialog(
  BuildContext context, {
  required String languageCode,
  bool skipConsent = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LanguagePackDialog(
      languageCode: languageCode,
      skipConsent: skipConsent,
    ),
  );
}

enum _Phase { confirm, installing, paused, failed }

class LanguagePackDialog extends StatefulWidget {
  const LanguagePackDialog({
    super.key,
    required this.languageCode,
    this.skipConsent = false,
  });

  final String languageCode;

  /// Skip the consent step — the pack is already on the device (or bundled),
  /// so there is no download to disclose.
  final bool skipConsent;

  @override
  State<LanguagePackDialog> createState() => _LanguagePackDialogState();
}

class _LanguagePackDialogState extends State<LanguagePackDialog> {
  late _Phase _phase;

  bool _errorIsNetwork = false;
  bool _errorIsSpace = false;

  LanguagePack get _pack =>
      languagePackFor(widget.languageCode) ??
      kLanguagePacks[kFallbackLanguageCode]!;

  @override
  void initState() {
    super.initState();
    final state = context.read<LanguagePackService>().stateFor(widget.languageCode);
    _phase = state.status == LanguagePackStatus.paused ? _Phase.paused : _Phase.confirm;
    if (widget.skipConsent || !_pack.requiresDownload) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.installing;
    });

    final service = context.read<LanguagePackService>();
    final ok = await service.install(widget.languageCode);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    final state = service.stateFor(widget.languageCode);
    setState(() {
      _phase = state.status == LanguagePackStatus.paused ? _Phase.paused : _Phase.failed;
      _errorIsNetwork = state.errorIsNetwork;
      _errorIsSpace = state.errorIsSpace;
    });
  }

  Future<void> _useFallback() async {
    final service = context.read<LanguagePackService>();
    final ok = await service.activateFallback();
    if (!mounted) return;
    Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final fallback = kLanguagePacks[kFallbackLanguageCode]!;
    final showFallback = _pack.code != fallback.code;

    return AlertDialog(
      backgroundColor: SpaceTheme.deepSpace,
      title: Row(
        children: [
          Icon(
            switch (_phase) {
              _Phase.confirm => Icons.cloud_download_outlined,
              _Phase.installing => Icons.downloading,
              _Phase.paused => Icons.pause_circle_outline,
              _Phase.failed => Icons.error_outline,
            },
            color: _phase == _Phase.failed
                ? SpaceTheme.planetOrange
                : SpaceTheme.starYellow,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              switch (_phase) {
                _Phase.confirm => s.packRequiredTitle(_pack.nativeName),
                _Phase.installing => s.packDownloadingTitle(_pack.nativeName),
                _Phase.paused => s.loadPaused,
                _Phase.failed => s.packFailedTitle,
              },
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 18),
            ),
          ),
        ],
      ),
      content: switch (_phase) {
        _Phase.confirm => _buildConfirm(s),
        _Phase.installing => _buildProgress(s),
        _Phase.paused => _buildProgress(s),
        _Phase.failed => _buildError(s, showFallback, fallback),
      },
      actions: switch (_phase) {
        _Phase.confirm => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.downloadDbCancel, style: SpaceTheme.bodyStyle),
            ),
            TextButton(
              autofocus: true,
              onPressed: _start,
              child: Text(
                s.downloadDbConfirm,
                style: SpaceTheme.buttonStyle
                    .copyWith(color: SpaceTheme.starYellow),
              ),
            ),
          ],
        _Phase.installing => [
          TextButton(onPressed: () => context.read<LanguagePackService>().pause(widget.languageCode),
            child: Text(s.downloadPause)),
        ],
        _Phase.paused => [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.close)),
          TextButton(onPressed: _start,
            child: Text(s.downloadResume)),
        ],
        _Phase.failed => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.close, style: SpaceTheme.bodyStyle),
            ),
            if (showFallback)
              TextButton(
                onPressed: _useFallback,
                child: Text(
                  s.packUseFallback(fallback.nativeName),
                  style: SpaceTheme.bodyStyle
                      .copyWith(color: SpaceTheme.moonSilver),
                ),
              ),
            TextButton(
              autofocus: true,
              onPressed: _start,
              child: Text(
                s.packRetry,
                style: SpaceTheme.buttonStyle
                    .copyWith(color: SpaceTheme.starYellow),
              ),
            ),
          ],
      },
    );
  }

  Widget _buildConfirm(S s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.packRequiredMessage(_pack.nativeName, _pack.downloadSizeLabel),
          style: SpaceTheme.bodyStyle,
        ),
        Consumer<LanguagePackService>(builder: (context, service, _) {
          final cached = service.stateFor(_pack.code).cachedBytes;
          if (cached == null || cached <= 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _MetaLine(
              icon: Icons.download_done_outlined,
              text: s.packResumeProgress(
                  _megabytes(cached), _pack.downloadSizeLabel),
            ),
          );
        }),
        const SizedBox(height: 12),
        _MetaLine(
          icon: Icons.sd_storage_outlined,
          // The database is stored decompressed, so the download figure alone
          // understates what has to fit on the device by roughly six times.
          text: _pack.installedSizeLabel == null
              ? s.packMetaSizeLicense(
                  _pack.downloadSizeLabel, _pack.licenseLabel)
              : s.packMetaSizes(
                  _pack.downloadSizeLabel,
                  _pack.installedSizeLabel!,
                  _pack.licenseLabel,
                ),
        ),
        const SizedBox(height: 4),
        _MetaLine(
          icon: Icons.wifi_off_outlined,
          text: s.packOfflineAfterDownload,
        ),
      ],
    );
  }

  Widget _buildProgress(S s) {
    return Consumer<LanguagePackService>(
      builder: (context, service, _) {
        final state = service.stateFor(widget.languageCode);
        final percent = (state.progress * 100).round();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                // 0 progress reads better as indeterminate than as a stuck bar.
                value: state.progress > 0 ? state.progress : null,
                minHeight: 8,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  SpaceTheme.starYellow,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              state.message.localized(s),
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '$percent%',
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 12,
                color: SpaceTheme.moonSilver,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.packKeepAppOpen,
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 11,
                color: SpaceTheme.moonSilver,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildError(S s, bool showFallback, LanguagePack fallback) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.loadFailed,
          style: SpaceTheme.bodyStyle.copyWith(
            color: SpaceTheme.starYellow.withValues(alpha: 0.85),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _errorIsSpace
              ? s.packNoSpaceHint(_pack.nativeName,
                  _pack.installedSizeLabel ?? _pack.downloadSizeLabel)
              : _errorIsNetwork
                  ? s.packFailedNetworkHint
                  : s.packFailedDataHint,
          style: SpaceTheme.bodyStyle.copyWith(fontSize: 12),
        ),
        if (showFallback) ...[
          const SizedBox(height: 8),
          Text(
            s.packFallbackHint(fallback.nativeName),
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 12,
              color: SpaceTheme.moonSilver,
            ),
          ),
        ],
      ],
    );
  }
}

String _megabytes(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: SpaceTheme.moonSilver),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 12,
              color: SpaceTheme.moonSilver,
            ),
          ),
        ),
      ],
    );
  }
}
