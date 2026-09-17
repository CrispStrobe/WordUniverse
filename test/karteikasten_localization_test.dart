import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/screens/karteikasten_screen.dart';
import 'package:WortUniversum/generated/l10n.dart';

class _GermanVocabulary extends VocabularyService {
  @override
  String get learningLanguage => 'de';
}

void main() {
  testWidgets('box names use interface locale while learning German',
      (tester) async {
    final vocabulary = _GermanVocabulary();
    final sri = SriService();
    addTearDown(vocabulary.dispose);
    addTearDown(sri.dispose);
    for (final locale in ['en', 'de', 'en']) {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<VocabularyService>.value(value: vocabulary),
          ChangeNotifierProvider<SriService>.value(value: sri),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: S.supportedLocales,
          localizationsDelegates: S.localizationsDelegates,
          home: const KarteikastenScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      for (final label in locale == 'en'
          ? ['New', 'First Review', 'Practice', 'Confident', 'Mastered']
          : ['Neu', 'Erste Festigung', 'Übung', 'Sicher', 'Gemeistert']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(vocabulary.learningLanguage, 'de');
      expect(tester.takeException(), isNull);
    }
  });
}
