import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/features/onboarding/screens/language_setup_screen.dart';

class FailingPreferences extends Fake implements SharedPreferences {
  FailingPreferences(this.throws);
  final bool throws;

  @override
  String? getString(String key) => key == 'language' ? 'de' : null;

  @override
  Future<bool> setString(String key, String value) async {
    if (throws) throw StateError('Raw English storage failure');
    return false;
  }
}

void main() {
  for (final throws in [false, true]) {
    testWidgets(
        'save failure is localized and follows selection (throws=$throws)',
        (tester) async {
      var completed = false;
      await tester.pumpWidget(MaterialApp(
        // Deliberately no locale delegate or parent rebuild: the selection owns
        // this screen's immediate language, including a previously shown error.
        home: LanguageSetupScreen(
          prefs: FailingPreferences(throws),
          onLocaleChanged: (_) {},
          onComplete: () => completed = true,
        ),
      ));
      await tester.ensureVisible(find.byKey(const Key('save-languages')));
      await tester.tap(find.byKey(const Key('save-languages')));
      await tester.pumpAndSettle();
      const germanError =
          'Deine Sprachauswahl konnte nicht gespeichert werden. Bitte versuche es erneut.';
      expect(find.text(germanError), findsOneWidget);
      expect(find.textContaining('Bad state'), findsNothing);
      expect(find.textContaining('Raw English'), findsNothing);
      expect(completed, isFalse);
      expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('save-languages')))
              .onPressed,
          isNotNull);

      await tester.ensureVisible(find.byKey(const Key('interface-language')));
      await tester.tap(find.byKey(const Key('interface-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Your language choices could not be saved. Please try again.'),
          findsOneWidget);
      expect(find.text(germanError), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
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
