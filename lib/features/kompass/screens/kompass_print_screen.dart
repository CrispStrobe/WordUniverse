import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../services/kompass_progress_service.dart';
import '../models/kompass_models.dart';
import '../widgets/kompass_strings.dart';
import '../widgets/kompass_ui.dart';
import 'kompass_player_screen.dart';

class KompassPrintScreen extends StatefulWidget {
  final KompassTest test;
  const KompassPrintScreen({super.key, required this.test});
  @override
  State<KompassPrintScreen> createState() => _KompassPrintScreenState();
}

class _KompassPrintScreenState extends State<KompassPrintScreen> {
  bool _solutions = false;
  bool _working = false;
  String? _pdfError;

  String get _asset =>
      _solutions ? widget.test.solutionsAsset : widget.test.printAsset;
  String get _fileName =>
      '${widget.test.id}_${_solutions ? 'solutions' : 'tasks'}.pdf';

  Future<Uint8List> _pdfBytes(String asset) async {
    final data = await DefaultAssetBundle.of(context).load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> _openPdf({required bool print}) async {
    if (_working || _asset.isEmpty) return;
    final asset = _asset;
    final fileName = _fileName;
    final s = KompassStrings.of(context);
    setState(() {
      _working = true;
      _pdfError = null;
    });
    try {
      final bytes = await _pdfBytes(asset);
      if (!mounted) return;
      if (print) {
        await Printing.layoutPdf(
            onLayout: (_) async => bytes, name: fileName, dynamicLayout: false);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _pdfError = s.choose(
          print
              ? 'Der Druckdialog konnte nicht geöffnet werden. Versuche „PDF speichern / teilen“.'
              : 'Die PDF-Datei konnte nicht gespeichert oder geteilt werden. Bitte versuche es erneut.',
          print
              ? 'The print dialog could not be opened. Try “Save / share PDF”.'
              : 'The PDF could not be saved or shared. Please try again.'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KompassStrings.of(context);
    final asset = _asset;
    return KompassPage(
        title: widget.test.title,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                      label: Text(s.choose('Aufgaben', 'Tasks')),
                      selected: !_solutions,
                      onSelected: _working
                          ? null
                          : (_) => setState(() {
                                _solutions = false;
                                _pdfError = null;
                              })),
                  ChoiceChip(
                      label: Text(s.choose(
                          'Lösungen und Kriterien', 'Solutions and rubric')),
                      selected: _solutions,
                      onSelected: _working
                          ? null
                          : (_) => setState(() {
                                _solutions = true;
                                _pdfError = null;
                              })),
                  FilledButton.icon(
                      key: const ValueKey('kompass-pdf-save'),
                      icon: const Icon(Icons.file_download_outlined),
                      label: Text(s.choose(
                          'PDF speichern / teilen', 'Save / share PDF')),
                      onPressed: _working || asset.isEmpty
                          ? null
                          : () => _openPdf(print: false)),
                  OutlinedButton.icon(
                      key: const ValueKey('kompass-pdf-print'),
                      icon: const Icon(Icons.print_outlined),
                      label: Text(s.choose('Drucken', 'Print')),
                      onPressed: _working || asset.isEmpty
                          ? null
                          : () => _openPdf(print: true)),
                  OutlinedButton.icon(
                      icon: const Icon(Icons.edit_note_rounded),
                      label: Text(s.paper),
                      onPressed: _enterAnswers),
                ],
              )),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                  s.choose(
                      'Drucke die Aufgaben einschließlich Lesetext. Übertrage danach die Antworten; offene Antworten brauchen eine Kriterienprüfung.',
                      'Print the tasks including the passage. Afterwards, enter the answers; open answers need a rubric review.'),
                  style: const TextStyle(color: kompassMuted, fontSize: 13),
                  textAlign: TextAlign.center)),
          if (_working) const LinearProgressIndicator(minHeight: 2),
          if (_pdfError != null)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: KompassNotice(text: _pdfError!)),
          Expanded(
              child: asset.isEmpty
                  ? KompassEmpty(
                      title: s.choose(
                          'Druckvorlage fehlt', 'Print file unavailable'),
                      message: s.choose(
                          'Für diese Übungsarbeit ist keine lokale Druckvorlage hinterlegt.',
                          'No local print file is available for this paper.'))
                  : PdfPreview(
                      key: ValueKey(asset),
                      build: (_) => _pdfBytes(asset),
                      pdfFileName: _fileName,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      useActions: false,
                      onError: (context, error) => KompassEmpty(
                          title: s.choose('Vorschau nicht verfügbar',
                              'Preview unavailable'),
                          message: s.choose(
                              'Die Vorschau konnte nicht angezeigt werden. Nutze oben „PDF speichern / teilen“ oder „Drucken“, um die lokale Datei zu öffnen.',
                              'The preview could not be displayed. Use “Save / share PDF” or “Print” above to open the local file.')),
                    )),
        ]));
  }

  Future<void> _enterAnswers() async {
    final s = KompassStrings.of(context);
    if (context.read<KompassProgressService>().activeSession != null) {
      final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(s.choose(
                    'Papierantworten übertragen?', 'Enter paper answers?')),
                content: Text(s.choose(
                    'Dein gespeicherter Zwischenstand wird durch diese neue Runde ersetzt. Bereits geprüfte Antworten bleiben erhalten.',
                    'This replaces your saved session draft. Previously reviewed answers are preserved.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(s.cancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(s.continueLabel))
                ],
              ));
      if (replace != true || !mounted) return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => KompassPlayerScreen(
            taskIds: widget.test.taskIds,
            mode: 'paper',
            title: widget.test.title)));
  }
}
