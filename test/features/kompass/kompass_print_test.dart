import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:WortUniversum/features/kompass/models/kompass_models.dart';
import 'package:WortUniversum/features/kompass/screens/kompass_print_screen.dart';

class _PdfBundle extends CachingAssetBundle {
  final documents = {
    'tasks.pdf': Uint8List.fromList(utf8.encode('%PDF-1.7\nTasks')),
    'solutions.pdf': Uint8List.fromList(utf8.encode('%PDF-1.7\nSolutions')),
  };

  @override
  Future<ByteData> load(String key) async {
    final document = documents[key]!;
    // Exercise a nonzero ByteData offset as well as the selected document.
    final buffer = Uint8List.fromList([99, ...document, 99]);
    return ByteData.view(buffer.buffer, 1, document.length);
  }
}

class _PreviewFailsPrinting extends PrintingPlatform {
  Uint8List? saved, printed;
  String? savedName, printedName;

  @override
  Future<PrintingInfo> info() async =>
      const PrintingInfo(canRaster: true, canPrint: true, canShare: true);

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      Stream.error(StateError('Preview rendering unavailable'));

  @override
  Future<bool> sharePdf(Uint8List bytes, String filename, Rect bounds,
      String? subject, String? body, List<String>? emails) async {
    saved = bytes;
    savedName = filename;
    return true;
  }

  @override
  Future<bool> layoutPdf(
      Printer? printer,
      LayoutCallback onLayout,
      String name,
      dynamic format,
      bool dynamicLayout,
      bool usePrinterSettings,
      OutputType outputType,
      bool forceCustomPrintPaper,
      bool windowsModernDialog) async {
    printed = await onLayout(format);
    printedName = name;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('save and print use bundled PDFs when the preview fails',
      (tester) async {
    final originalPlatform = PrintingPlatform.instance;
    final originalErrorHandler = FlutterError.onError;
    var previewFailures = 0;
    FlutterError.onError = (details) {
      if (details.library == 'printing' &&
          details.exception is StateError &&
          details.exception
              .toString()
              .contains('Preview rendering unavailable')) {
        previewFailures++;
      } else {
        originalErrorHandler?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = originalErrorHandler);
    final platform = _PreviewFailsPrinting();
    final bundle = _PdfBundle();
    PrintingPlatform.instance = platform;
    addTearDown(() => PrintingPlatform.instance = originalPlatform);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: DefaultAssetBundle(
            bundle: bundle,
            child: KompassPrintScreen(
                test: KompassTest.fromJson({
              'id': 'test1',
              'title': 'Deutsch · Übungsarbeit 1',
              'printAsset': 'tasks.pdf',
              'solutionsAsset': 'solutions.pdf',
              'taskIds': <String>[],
            })))));
    await tester.pumpAndSettle();
    expect(previewFailures, greaterThan(0));
    expect(tester.takeException(), isNull);
    expect(find.text('Vorschau nicht verfügbar'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('kompass-pdf-save')));
    await tester.pumpAndSettle();
    expect(platform.saved, orderedEquals(bundle.documents['tasks.pdf']!));
    expect(platform.savedName, 'test1_tasks.pdf');

    await tester.tap(find.byKey(const ValueKey('kompass-pdf-print')));
    await tester.pumpAndSettle();
    expect(platform.printed, orderedEquals(bundle.documents['tasks.pdf']!));
    expect(platform.printedName, 'test1_tasks.pdf');
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Lösungen und Kriterien'));
    await tester.pumpAndSettle();
    expect(previewFailures, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('kompass-pdf-save')));
    await tester.pumpAndSettle();
    expect(platform.saved, orderedEquals(bundle.documents['solutions.pdf']!));
    expect(platform.savedName, 'test1_solutions.pdf');
    expect(tester.takeException(), isNull);
  });
}
