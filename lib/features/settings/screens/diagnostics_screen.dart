// lib/features/settings/screens/diagnostics_screen.dart
//
// User-facing view of the on-device crash log. Lets the user:
//   - inspect what crashes have happened (read-only),
//   - copy the entire log to the clipboard (for pasting into an email /
//     GitHub issue / Slack message — i.e. opt-in sharing under their full
//     control),
//   - clear the log.
//
// Crash data never leaves the device automatically. Surface this from
// Settings so it's discoverable for users who want to help debug.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/crash_logger.dart';
import '../../../core/theme/space_theme.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late Future<List<CrashEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = CrashLogger.instance.readAll();
  }

  void _refresh() {
    setState(() {
      _entriesFuture = CrashLogger.instance.readAll();
    });
  }

  Future<void> _copyToClipboard(List<CrashEntry> entries) async {
    final text = entries.map((e) => jsonEncode(e.toJson())).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Crash log copied to clipboard')),
    );
  }

  Future<void> _clear() async {
    await CrashLogger.instance.clear();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceTheme.deepSpace,
      appBar: AppBar(
        title: const Text('Diagnostics'),
        backgroundColor: SpaceTheme.deepSpace,
      ),
      body: FutureBuilder<List<CrashEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const [];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entries.isEmpty
                            ? 'No crashes recorded. 🎉'
                            : '${entries.length} crash report'
                                '${entries.length == 1 ? '' : 's'} on device. '
                                'Data stays here unless you share it.',
                        style: SpaceTheme.bodyStyle,
                      ),
                    ),
                    if (entries.isNotEmpty) ...[
                      IconButton(
                        tooltip: 'Copy log',
                        onPressed: () => _copyToClipboard(entries),
                        icon: const Icon(Icons.copy),
                      ),
                      IconButton(
                        tooltip: 'Clear log',
                        onPressed: _clear,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 0),
              Expanded(
                child: ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final e = entries[entries.length - 1 - i]; // newest first
                    return ExpansionTile(
                      title: Text(
                        e.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SpaceTheme.bodyStyle,
                      ),
                      subtitle: Text(
                        '${e.source} · ${e.timestamp.toIso8601String()}',
                        style: SpaceTheme.bodyStyle.copyWith(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                      children: [
                        if (e.stackTrace != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              e.stackTrace!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        if (e.context != null && e.context!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: SelectableText(
                              e.context!.entries
                                  .map((kv) => '${kv.key}: ${kv.value}')
                                  .join('\n'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
