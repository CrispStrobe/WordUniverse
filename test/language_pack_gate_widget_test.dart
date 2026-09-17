import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:WortUniversum/core/services/language_pack_service.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';
import 'package:WortUniversum/shared/widgets/language_pack_dialog.dart';
import 'package:WortUniversum/generated/l10n.dart';
import 'selected_language_service_test.dart' show SelectionVocabulary;

class PausableVocabulary extends SelectionVocabulary {
  Completer<void>? attempt;
  int starts = 0;
  @override Future<void> setLearningLanguage(String code, {bool allowDownload = false,
    void Function(double, String)? onProgress}) async {
    starts++;
    attempt = Completer<void>();
    onProgress?.call(.25, 'Downloading 1 / 4 MB');
    await attempt!.future;
    loaded = code;
  }
}
class PausablePacks extends LanguagePackService {
  PausablePacks(this.vocab) : super(vocab);
  final PausableVocabulary vocab;
  @override void pause(String code) {
    vocab.attempt!.completeError(DbDownloadPausedException());
  }
}
Widget host(LanguagePackService service, Widget child) =>
  ChangeNotifierProvider<LanguagePackService>.value(value: service, child: MaterialApp(
    locale: const Locale('en'), localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales, home: child));

void main() {
  testWidgets('skip preserves German, reoffers and never constructs a game', (tester) async {
    final vocab = SelectionVocabulary();
    final service = LanguagePackService(vocab);
    var constructed = 0;
    await tester.pumpWidget(host(service, Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LanguagePackGate(builder: (_) {
          constructed++;
          return const Scaffold(body: Text('GAME'));
        }))), child: const Text('Play'))))));
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePackDialog), findsOneWidget);
    expect(constructed, 0);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(vocab.saved, 'de');
    expect(constructed, 0);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePackDialog), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('GAME'), findsOneWidget);
    expect(constructed, 1);
  });

  testWidgets('shared dialog shows progress, pause and resume without failure', (tester) async {
    final vocab = PausableVocabulary();
    final service = PausablePacks(vocab);
    await tester.pumpWidget(host(service, const LanguagePackDialog(languageCode: 'de')));
    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Downloading 1 / 4 MB'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    expect(service.stateFor('de').error, isNull);
    await tester.tap(find.text('Resume'));
    await tester.pump();
    await tester.pump();
    expect(vocab.starts, 2);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
  });
}
