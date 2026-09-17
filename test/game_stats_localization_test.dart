import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/features/games/screens/grossstadt_game.dart';
import 'package:WortUniversum/features/games/screens/wortbaumeister_game.dart';
import 'package:WortUniversum/generated/l10n.dart';
import 'game_localization_fixtures.dart';

void main() {
  for (final grossstadt in [true, false]) {
    testWidgets(
        '${grossstadt ? 'Grossstadt' : 'Wortbaumeister'} stats follow interface locale with German learning',
        (tester) async {
      final fixture = GameLocalizationFixture([
        for (final w in [
          'Haus',
          'Boot',
          'Baum',
          'Hausboot',
          'Boothaus',
          'Baumhaus'
        ])
          germanNoun(w),
      ]);
      await fixture.initialize();
      addTearDown(fixture.dispose);
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final screen = grossstadt
          ? const GrossstadtGame(gradeLevel: GradeLevel.grade1)
          : const WortbaumeisterGame(gradeLevel: GradeLevel.grade1);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(fixture.app('en', screen));
        await tester.pump();
        // Noun-only fixtures make every capitalization/together choice correct.
        for (var i = 0; i < 2; i++) {
          final s = S.of(tester.element(find.byWidget(screen)))!;
          await tester.tap(find.text(
              grossstadt ? s.grossstadtCapital : s.verbtrennerTogetherLabel));
          await tester.pump();
          await tester.pump(Duration(milliseconds: grossstadt ? 1200 : 2000));
        }
        for (final locale in ['en', 'de', 'en']) {
          await tester.pumpWidget(fixture.app(locale, screen));
          await tester.pump();
          final en = locale == 'en';
          for (final pattern in [
            en ? '^Level 1' : '^Stufe 1',
            en ? r'^Score: [1-9]\d*' : r'^Punkte: [1-9]\d*',
            en ? '^Progress: 2 of ' : '^Fortschritt: 2 von ',
            en ? '^Combo x2' : '^Kombo mal 2'
          ]) {
            expect(find.bySemanticsLabel(RegExp(pattern)), findsOneWidget);
          }
          expect(fixture.vocabulary.learningLanguage, 'de');
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
        semantics.dispose();
      }
    });
  }
}
