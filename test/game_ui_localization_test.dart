import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/widgets/game_ui.dart';
import 'package:WortUniversum/generated/l10n.dart';

void main() {
  for (final width in [600.0, 1000.0]) {
    testWidgets('game header localizes visible and semantic stats at $width',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final game = GameProvider(
        progressService: ProgressService(),
        sriService: SriService(),
        cognitiveProfileService: CognitiveProfileService(),
        prefs: await SharedPreferences.getInstance(),
      );
      addTearDown(game.dispose);
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        for (final locale in ['en', 'de', 'en']) {
          await tester.pumpWidget(ChangeNotifierProvider.value(
            value: game,
            child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: S.supportedLocales,
              localizationsDelegates: S.localizationsDelegates,
              home: Scaffold(
                  body: GameUI(
                      title: 'Spiel', level: 3, timeLeft: 65, onBack: () {})),
            ),
          ));
          await tester.pump();
          final en = locale == 'en';
          for (final label in [
            en ? 'Level 3' : 'Stufe 3',
            en ? 'Score: 0' : 'Punkte: 0',
            en ? 'Time remaining: 1:05' : 'Verbleibende Zeit: 1:05'
          ]) {
            expect(find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')),
                findsOneWidget);
          }
          if (width >= 650) {
            for (final text in [
              en ? 'Level: 3' : 'Stufe: 3',
              en ? 'Score: 0' : 'Punkte: 0',
              en ? 'Time: 1:05' : 'Zeit: 1:05'
            ]) {
              expect(find.text(text), findsOneWidget);
            }
          }
          final time = tester.widget<Semantics>(find.byWidgetPredicate((w) =>
              w is Semantics &&
              w.properties.label ==
                  (en ? 'Time remaining: 1:05' : 'Verbleibende Zeit: 1:05')));
          expect(time.properties.liveRegion, isNot(true));
          expect(tester.takeException(), isNull);
        }
      } finally {
        semantics.dispose();
      }
    });
  }
}
