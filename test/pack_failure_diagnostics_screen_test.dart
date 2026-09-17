import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/load_status.dart';
import 'package:WortUniversum/core/services/pack_failure_logger.dart';
import 'package:WortUniversum/core/services/db_platform/db_download_exception.dart';
import 'package:WortUniversum/generated/l10n.dart';
import 'package:WortUniversum/features/settings/screens/diagnostics_screen.dart';

Widget host(Locale locale, {required int crashCount, required int failureCount}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('de')],
    home: DiagnosticsScreen(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackFailureLogger.instance.resetForTests();
  });

  Future<void> pumpWith(Locale locale, WidgetTester tester) async {
    await tester.pumpWidget(host(locale, crashCount: 0, failureCount: 0));
    await tester.pumpAndSettle();
  }

  testWidgets('en labels the failures section and the empty state',
      (tester) async {
    await pumpWith(const Locale('en'), tester);
    expect(find.text('Pack failures'), findsOneWidget);
    expect(find.text('No local failures recorded.'), findsOneWidget);
  });

  testWidgets('de labels the failures section and the empty state',
      (tester) async {
    await pumpWith(const Locale('de'), tester);
    expect(find.text('Paket-Fehler'), findsOneWidget);
    expect(find.text('Keine lokalen Fehler aufgezeichnet.'), findsOneWidget);
  });

  testWidgets('a recorded space failure is rendered with size details',
      (tester) async {
    await PackFailureLogger.instance.record(
      pack: 'de', operation: PackOperation.install,
      stage: LoadStage.writingStorage,
      error: DbInsufficientSpaceException(requiredBytes: 200, availableBytes: 100),
    );
    await pumpWith(const Locale('en'), tester);
    expect(find.text('Pack failures'), findsOneWidget);
    final details = find.byType(ExpansionTile);
    expect(details, findsOneWidget);
  });
}
