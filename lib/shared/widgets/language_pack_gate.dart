import 'package:flutter/material.dart';
import '../../core/theme/space_theme.dart';
import '../../generated/l10n.dart';
import 'language_pack_dialog.dart';

/// The builder is never invoked until the selected vocabulary is loaded, so a
/// game widget cannot be constructed against an empty database.
class LanguagePackGate extends StatefulWidget {
  const LanguagePackGate({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  State<LanguagePackGate> createState() => _LanguagePackGateState();
}

class _LanguagePackGateState extends State<LanguagePackGate> {
  Widget? _game;
  bool _checking = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!mounted || _checking) return;
    _checking = true;
    final ready = await ensureLanguagePackReady(context);
    if (!mounted) return;
    _checking = false;
    if (ready) {
      setState(() => _game = widget.builder(context));
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    if (game != null) return game;
    // Reached when the pack is still missing and there is nothing to pop back
    // to (a deep link, or the gate as the first route): offer the download
    // again rather than showing an empty screen.
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: SpaceTheme.spaceGradient),
        child: Center(
          child: TextButton.icon(
            onPressed: _check,
            icon: const Icon(Icons.cloud_download_outlined,
                color: SpaceTheme.starYellow),
            label: Text(
              S.of(context)!.packGateLoadAction,
              style: SpaceTheme.buttonStyle
                  .copyWith(color: SpaceTheme.starYellow),
            ),
          ),
        ),
      ),
    );
  }
}
