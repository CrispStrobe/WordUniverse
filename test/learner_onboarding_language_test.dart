import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/services/learner_profile_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/onboarding/screens/learner_onboarding_screen.dart';
import 'package:WortUniversum/generated/l10n.dart';

class _GameSettings extends ChangeNotifier implements GameProvider {
  @override
  void setGrade(int grade) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final learning in ['en', 'de']) {
    testWidgets(
        'learner completion preserves picked $learning independently of UI',
        (tester) async {
      final interface = learning == 'en' ? 'de' : 'en';
      SharedPreferences.setMockInitialValues({
        'learning_language': learning,
        'language': interface,
        'language_setup_complete': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final vocabulary = VocabularyService(); // Not loaded: defaults to German.
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<VocabularyService>.value(value: vocabulary),
          ChangeNotifierProvider<GameProvider>(create: (_) => _GameSettings()),
          ChangeNotifierProvider(create: (_) => LearnerProfileService(prefs)),
        ],
        child: MaterialApp(
          locale: Locale(interface),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          initialRoute: '/onboarding',
          routes: {
            '/': (_) => const Scaffold(body: Text('Completed learner setup')),
            '/onboarding': (_) => const LearnerOnboardingScreen(),
          },
        ),
      ));
      await tester.pumpAndSettle();
      final continueButton = find.widgetWithText(
          FilledButton,
          interface == 'de'
              ? 'Meinen Lernplan vorbereiten'
              : 'Prepare my learning plan');
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      expect(find.text('Completed learner setup'), findsOneWidget);
      expect(prefs.getBool('learner_onboarding_complete'), true);
      expect(prefs.getString('learning_language'), learning);
      expect(prefs.getString('language'), interface);
      expect(vocabulary.isInitialized, false); // No download during onboarding.
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      vocabulary.dispose();
    });
  }
}
