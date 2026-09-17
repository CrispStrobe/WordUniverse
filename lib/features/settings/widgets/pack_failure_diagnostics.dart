import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/load_status.dart';
import '../../../core/services/pack_failure_logger.dart';
import '../../../generated/l10n.dart';
import '../../../shared/utils/load_status_localization.dart';

/// Handled pack failures stay separate from CrashLogger's uncaught errors.
class PackFailureDiagnostics extends StatefulWidget {
  const PackFailureDiagnostics({super.key});
  @override
  State<PackFailureDiagnostics> createState() => _PackFailureDiagnosticsState();
}

class _PackFailureDiagnosticsState extends State<PackFailureDiagnostics> {
  late Future<List<PackFailureEntry>> _entries = PackFailureLogger.instance.readAll();
  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    return FutureBuilder<List<PackFailureEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <PackFailureEntry>[];
        return Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(s.diagnosticsPackFailures),
            subtitle: Text(s.diagnosticsLocalOnly),
            trailing: entries.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: s.diagnosticsCopyLog, icon: const Icon(Icons.copy), onPressed: () async {
                await Clipboard.setData(ClipboardData(text: entries.map((e) => jsonEncode(e.toJson())).join('\n')));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context)!.diagnosticsCopied)));
              }),
              IconButton(tooltip: s.diagnosticsClearLog, icon: const Icon(Icons.delete_outline), onPressed: () async {
                await PackFailureLogger.instance.clear();
                if (mounted) setState(() { _entries = PackFailureLogger.instance.readAll(); });
              }),
            ]),
          ),
          if (entries.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(s.diagnosticsNoPackFailures)),
          for (final e in entries.reversed) ExpansionTile(
            title: Text('${s.diagnosticsPack}: ${e.pack} · ${e.operation == PackOperation.install ? s.diagnosticsInstall : s.diagnosticsActivate}'),
            subtitle: Text('${_cause(e.cause, s)} · ${e.timestamp.toIso8601String()}'),
            children: [Padding(padding: const EdgeInsets.all(12), child: SelectableText([
              '${s.diagnosticsStage}: ${LoadStatus(e.stage).localized(s)}',
              '${s.diagnosticsCause}: ${_cause(e.cause, s)}',
              if (e.requiredBytes != null) '${s.diagnosticsRequiredBytes}: ${e.requiredBytes}',
              if (e.availableBytes != null) '${s.diagnosticsAvailableBytes}: ${e.availableBytes}',
            ].join('\n')))],
          ),
        ]);
      },
    );
  }

  String _cause(PackFailureCause cause, S s) => switch (cause) {
    PackFailureCause.insufficientSpace => s.diagnosticsCauseSpace,
    PackFailureCause.storage => s.diagnosticsCauseStorage,
    PackFailureCause.schema => s.diagnosticsCauseSchema,
    PackFailureCause.payload => s.diagnosticsCausePayload,
    PackFailureCause.network => s.diagnosticsCauseNetwork,
    PackFailureCause.download => s.diagnosticsCauseDownload,
    PackFailureCause.unknown => s.diagnosticsCauseUnknown,
  };
}
