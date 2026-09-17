// Red/green widget tests for the localized loader/download progress pipeline.
//
// A German interface must never show an English loader/download/status string
// — including the exact user-reported leak ('Writing to browser storage...').
// Services now emit typed LoadStatus values; widgets translate at build time,
// so the same pipeline also proves an interface-language change is picked up
// by in-flight progress without restarting the flow.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:WortUniversum/core/models/load_status.dart';
import 'package:WortUniversum/core/services/language_pack_service.dart';
import 'package:WortUniversum/shared/utils/load_status_localization.dart';
import 'package:WortUniversum/shared/widgets/language_pack_dialog.dart';
import 'package:WortUniversum/generated/l10n.dart';

import 'selected_language_service_test.dart' show SelectionVocabulary;

/// Emits the exact status the web DB loader reports while writing IndexedDB
/// and then hangs, so the install UI stays in that phase for assertions.
class StorageVocabulary extends SelectionVocabulary {
  @override
  Future<void> setLearningLanguage(String code,
      {bool allowDownload = false, LoadProgress? onProgress}) async {
    onProgress?.call(.8, const LoadStatus(LoadStage.writingBrowserStorage));
    await Completer<void>().future; // never settles: keeps the phase visible
  }
}

Widget host(Locale locale, LanguagePackService service) =>
    ChangeNotifierProvider<LanguagePackService>.value(
      value: service,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: const LanguagePackDialog(languageCode: 'de', skipConsent: true),
      ),
    );

void main() {
  testWidgets(
      'German installer translates the browser storage phase (user report)',
      (tester) async {
    final service = LanguagePackService(StorageVocabulary());
    await tester.pumpWidget(host(const Locale('de'), service));
    await tester.pump();
    await tester.pump();
    expect(find.text('Writing to browser storage...'), findsNothing);
    expect(find.text('Writing to browser storage …'), findsNothing);
    expect(find.text('Wird im Browserspeicher gespeichert …'), findsOneWidget);
  });

  testWidgets('sizes and counts localize, including German grouping',
      (tester) async {
    final service = LanguagePackService(StorageVocabulary());
    await tester.pumpWidget(host(const Locale('de'), service));
    final s = S.of(tester.element(find.byType(LanguagePackDialog).first))!;
    // MB with a decimal comma plus the thousands-grouped word count.
    expect(
      const LoadStatus(LoadStage.loadedCompressed, bytes: 26649600)
          .localized(s),
      '25,4 MB komprimierte Daten geladen',
    );
    expect(
      const LoadStatus(LoadStage.databaseReadyWords, count: 24500).localized(s),
      'Datenbank mit 24.500 Wörtern bereit!',
    );
  });

  testWidgets(
      'dynamic progress re-renders in the current interface language without restarting the flow',
      (tester) async {
    final service = LanguagePackService(StorageVocabulary());
    await tester.pumpWidget(host(const Locale('de'), service));
    await tester.pump();
    await tester.pump();
    expect(find.text('Wird im Browserspeicher gespeichert …'), findsOneWidget);

    // The interface switches to English while the install is still running:
    // the same in-flight status is re-rendered in the new locale.
    await tester.pumpWidget(host(const Locale('en'), service));
    await tester.pump();
    expect(find.text('Writing to browser storage …'), findsOneWidget);
    expect(find.text('Wird im Browserspeicher gespeichert …'), findsNothing);
  });
}
