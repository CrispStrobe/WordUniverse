import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/settings/widgets/manage_sets_dialog.dart';
import 'package:WortUniversum/generated/l10n.dart';

class _Vocabulary extends VocabularyService {
  List<VocabularySet> sets = [];
  @override
  String get learningLanguage => 'de';
  @override
  List<VocabularySet> getCustomSets() => sets;
}

void main() {
  for (final populated in [false, true]) {
    testWidgets('custom sets localize empty labels (populated: $populated)',
        (tester) async {
      final vocabulary = _Vocabulary();
      addTearDown(vocabulary.dispose);
      if (populated) {
        vocabulary.sets = [
          VocabularySet(
              id: '1',
              name: 'Meine Wörter',
              description: '',
              wordIds: [],
              targetGrade: GradeLevel.grade1,
              createdAt: DateTime(2026),
              isCustom: true),
          VocabularySet(
              id: '2',
              name: 'Tiere',
              description: 'Eigene Beschreibung',
              wordIds: [],
              targetGrade: GradeLevel.grade1,
              createdAt: DateTime(2026),
              isCustom: true),
        ];
      }
      for (final locale in ['de', 'en', 'de']) {
        await tester.pumpWidget(ChangeNotifierProvider<VocabularyService>.value(
          value: vocabulary,
          child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: S.supportedLocales,
              localizationsDelegates: S.localizationsDelegates,
              home: const Scaffold(body: ManageSetsDialog())),
        ));
        await tester.pumpAndSettle();
        expect(
            find.text(populated
                ? (locale == 'en' ? 'No description' : 'Keine Beschreibung')
                : (locale == 'en'
                    ? 'No custom sets created yet.'
                    : 'Noch keine eigenen Sets erstellt.')),
            findsOneWidget);
        if (populated) {
          expect(find.text('Meine Wörter'), findsOneWidget);
          expect(find.text('Eigene Beschreibung'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    });
  }
}
