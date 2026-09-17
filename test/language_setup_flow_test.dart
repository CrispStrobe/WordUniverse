import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/features/onboarding/screens/language_setup_screen.dart';

void main() {
  testWidgets('each selector has its own visible legend on a space background',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(
        home: LanguageSetupScreen(
      prefs: prefs,
      onLocaleChanged: (_) {},
      onComplete: () {},
    )));
    expect(find.text('What language do you want to learn?'), findsOneWidget);
    expect(
        find.text('Language for words, exercises and games.'), findsOneWidget);
    expect(find.text('What language should the app use?'), findsOneWidget);
    expect(find.text('Language for menus, buttons and instructions.'),
        findsOneWidget);
    expect(
        tester.getTopLeft(find.text('What language do you want to learn?')).dy,
        lessThan(
            tester.getTopLeft(find.byKey(const Key('learning-language'))).dy));
    expect(
        tester.getTopLeft(find.text('What language should the app use?')).dy,
        lessThan(
            tester.getTopLeft(find.byKey(const Key('interface-language'))).dy));
    final background = tester.widget<DecoratedBox>(
        find.byKey(const Key('language-setup-background')));
    expect((background.decoration as BoxDecoration).gradient, isNotNull);
    await tester.tap(find.byKey(const Key('interface-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch').last);
    await tester.pumpAndSettle();
    expect(find.text('Welche Sprache möchtest du lernen?'), findsOneWidget);
    expect(find.text('Welche Sprache soll die App verwenden?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fresh setup saves independent choices only on Continue',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Locale? locale;
    var continued = false;
    await tester.pumpWidget(MaterialApp(
        home: LanguageSetupScreen(
      prefs: prefs,
      onLocaleChanged: (value) => locale = value,
      onComplete: () => continued = true,
    )));
    expect(prefs.getBool('language_setup_complete'), isNull);
    await tester.tap(find.byKey(const Key('interface-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(locale, const Locale('en'));
    expect(prefs.getBool('language_setup_complete'), isNull);
    await tester.ensureVisible(find.byKey(const Key('save-languages')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-languages')));
    await tester.pumpAndSettle();
    expect(prefs.getString('learning_language'), 'de');
    expect(prefs.getString('language'), 'en');
    expect(prefs.getBool('language_setup_complete'), true);
    expect(continued, true);
  });
}
