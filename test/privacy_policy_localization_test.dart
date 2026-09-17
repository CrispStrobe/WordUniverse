import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/generated/l10n.dart';
import 'package:WortUniversum/shared/widgets/privacy_policy_dialog.dart';

void main() {
  testWidgets('full privacy policy follows EN-DE-EN interface switches',
      (tester) async {
    for (final locale in ['en', 'de', 'en']) {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        supportedLocales: S.supportedLocales,
        localizationsDelegates: S.localizationsDelegates,
        home: const Scaffold(body: PrivacyPolicyDialog()),
      ));
      await tester.pumpAndSettle();
      final english = locale == 'en';
      for (final title in english
          ? [
              'Privacy',
              'In brief',
              'What is stored and where',
              'Network',
              'Crash reports',
              'Use by minors',
              'Your rights',
              'Changes'
            ]
          : [
              'Datenschutz',
              'In Kürze',
              'Was wird wo gespeichert',
              'Netzwerk',
              'Crash-Berichte',
              'Nutzung durch Minderjährige',
              'Deine Rechte',
              'Änderungen'
            ]) {
        expect(find.text(title, skipOffstage: false), findsOneWidget);
      }
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      for (final clause in english
          ? [
              'no tracking',
              '50 entries',
              'Hugging Face',
              'no payment data',
              'Copy to clipboard',
              'no user account',
              'Delete all data',
              'Opt-in'
            ]
          : [
              'kein Tracking',
              '50 Einträgen',
              'Hugging Face',
              'keine Zahlungsdaten',
              'In Zwischenablage kopieren',
              'kein Nutzerkonto',
              'Alle Daten löschen',
              'Opt-in'
            ]) {
        expect(text, contains(clause));
      }
      expect(find.byTooltip(english ? 'Close' : 'Schließen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
