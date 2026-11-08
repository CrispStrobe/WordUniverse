import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/sri_item_identity.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/features/games/screens/karteikasten_screen.dart';
import 'package:WortUniversum/features/games/screens/sri_review_screen.dart';
import 'package:WortUniversum/generated/l10n.dart';

void main() {
  for (final locale in ['de', 'en']) {
    for (final boxes in [true, false]) {
      testWidgets(
          '$locale ${boxes ? 'boxes' : 'review'} show words, skills, and context',
          (tester) async {
        final caseId = SriItemIdentity.itemId(
            skillType: LanguageSkillType.caseUsage,
            baseWord: 'Hund',
            wordId: 'word-de-hund',
            additionalInfo: 'dativ');
        final missingId = SriItemIdentity.itemId(
            skillType: LanguageSkillType.spelling,
            baseWord: 'unused',
            wordId: 'opaque-without-display');
        const legacyId = 'CONJUG_laufen_er/sie/es';
        final records = [
          SriLanguageData(
              itemId: caseId,
              skillType: LanguageSkillType.caseUsage,
              failureCount: 1,
              nextReviewDate: DateTime.utc(2020),
              metadata: {'baseWord': 'Hund'}),
          SriLanguageData(
              itemId: legacyId,
              skillType: LanguageSkillType.verbConjugation,
              failureCount: 1,
              nextReviewDate: DateTime.utc(2020)),
          SriLanguageData(
              itemId: missingId,
              skillType: LanguageSkillType.spelling,
              failureCount: 1,
              nextReviewDate: DateTime.utc(2020)),
        ];
        SharedPreferences.setMockInitialValues({
          'sri_language_database': jsonEncode({
            for (final record in records) record.itemId: record.toJson(),
          }),
        });
        final sri = SriService();
        await sri.loadSriData();
        addTearDown(sri.dispose);
        await tester.pumpWidget(ChangeNotifierProvider.value(
            value: sri,
            child: MaterialApp(
                locale: Locale(locale),
                supportedLocales: S.supportedLocales,
                localizationsDelegates: S.localizationsDelegates,
                home: boxes
                    ? const KarteikastenScreen()
                    : const SriReviewScreen())));
        await tester.pumpAndSettle();
        final s = lookupS(Locale(locale));
        final caseLabel =
            '[${s.skillLabelCase}] Hund · ${s.wordSnakeCaseDative}';
        expect(find.text(caseLabel), findsOneWidget);
        expect(find.text('[${s.skillLabelConjugation}] laufen · er/sie/es'),
            findsOneWidget);
        expect(
            find.text(
                '[${s.skillLabelSpelling}] ${s.reviewItemWordUnavailable}'),
            findsOneWidget);
        expect(find.textContaining('@2|'), findsNothing);
        expect(find.textContaining('word-de-hund'), findsNothing);
        expect(find.textContaining('opaque-without-display'), findsNothing);
        expect(find.textContaining('CONJUG_'), findsNothing);

        if (boxes) {
          // The display is decoded, while drag and menu actions keep the key.
          final card = find.ancestor(
              of: find.text(caseLabel), matching: find.byType(ListTile));
          final drag = find.ancestor(
              of: card, matching: find.byType(LongPressDraggable<String>));
          expect(tester.widget<LongPressDraggable<String>>(drag).data, caseId);
          await tester.tap(find.descendant(
              of: card, matching: find.byType(PopupMenuButton<int>)));
          await tester.pumpAndSettle();
          await tester
              .tap(find.widgetWithText(PopupMenuItem<int>, s.boxLabel(2)));
          await tester.pumpAndSettle();
          expect(sri.getItemData(caseId)!.metadata['manualBox'], 2);
          expect(sri.getItemData(legacyId)!.metadata['manualBox'], isNull);
          expect(sri.totalTrackedItems, 3);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
