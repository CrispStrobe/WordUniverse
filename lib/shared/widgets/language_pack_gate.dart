import 'package:flutter/material.dart';
import 'language_pack_dialog.dart';

/// The builder is never invoked until the selected vocabulary is loaded.
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
  Widget build(BuildContext context) => _game ?? Scaffold(body: Center(
    child: TextButton(onPressed: _check,
      child: Text(Localizations.localeOf(context).languageCode == 'de'
        ? 'Sprachpaket laden' : 'Load language pack'))));
}
