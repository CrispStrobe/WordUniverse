import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:WortUniversum/generated/l10n.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/features/settings/widgets/sri_statistics_dialog.dart';

void main() {
  test('home tooltip chrome and badge labels are locale-bound, not literals', () {
    final home = File('lib/features/home/screens/home_screen.dart').readAsStringSync();
    for (final label in ['Review', 'Lernprofil', 'Erfolge']) {
      expect(home, isNot(contains("tooltip: '$label'")));
    }
    final badge = File('lib/features/games/widgets/spelling_strategy_badge.dart').readAsStringSync();
    expect(badge, contains('S.of(context)'));
    expect(badge, isNot(contains('info.label,')));
  });
  testWidgets('statistics follows an immediate EN-DE interface switch', (tester) async {
    final service = SriService();
    for (final locale in ['en', 'de', 'en']) {
      await tester.pumpWidget(ChangeNotifierProvider.value(value: service,
        child: MaterialApp(locale: Locale(locale), supportedLocales: S.supportedLocales,
          localizationsDelegates: S.localizationsDelegates,
          home: const Scaffold(body: SriStatisticsDialog()))));
      await tester.pumpAndSettle();
      expect(find.text(locale == 'en' ? 'Spelling' : 'Rechtschreibung'), findsOneWidget);
    }
  });
}
