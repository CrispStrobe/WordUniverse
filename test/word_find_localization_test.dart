import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/features/games/screens/word_find_game.dart';
import 'game_localization_fixtures.dart';

void main() {
  for (final found in [false, true]) {
    testWidgets(
        'word find ${found ? 'found' : 'pending'} semantics follow interface locale',
        (tester) async {
      final fixture =
          GameLocalizationFixture([germanNoun('Haus'), germanNoun('Boot')]);
      await fixture.initialize();
      addTearDown(fixture.dispose);
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const screen = WordFindGame(gradeLevel: GradeLevel.grade1);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(fixture.app('en', screen));
      await tester.pump();
      final state = tester.state(find.byType(WordFindGame));
      if (found) {
        // Solve the rendered grid rather than relying on random placement.
        final cells = find.descendant(
            of: find.byType(GridView), matching: find.byType(Text));
        final letters =
            tester.widgetList<Text>(cells).map((t) => t.data!).toList();
        expect(letters.length, 64);
        List<int>? path;
        for (var start = 0; start < 64; start++) {
          for (final direction in [
            const Offset(1, 0),
            const Offset(0, 1),
            const Offset(-1, 0),
            const Offset(0, -1)
          ]) {
            final indices = <int>[];
            for (var i = 0; i < 4; i++) {
              final r = start ~/ 8 + direction.dy.toInt() * i;
              final c = start % 8 + direction.dx.toInt() * i;
              if (r < 0 || r >= 8 || c < 0 || c >= 8) break;
              indices.add(r * 8 + c);
            }
            if (indices.map((i) => letters[i]).join() == 'HAUS') path = indices;
          }
        }
        expect(path, isNotNull);
        final start = tester.getCenter(cells.at(path!.first));
        final end = tester.getCenter(cells.at(path.last));
        final gesture = await tester.startGesture(start);
        await gesture.moveTo(start + (end - start) / 6);
        await gesture.moveTo(end);
        await gesture.up();
        await tester.pump();
      }
      for (final locale in ['en', 'de', 'en']) {
        await tester.pumpWidget(fixture.app(locale, screen));
        await tester.pump();
        expect(tester.state(find.byType(WordFindGame)), same(state));
        final en = locale == 'en';
        final status = found
            ? (en ? 'found' : 'gefunden')
            : (en ? 'still to find' : 'noch zu finden');
        expect(find.bySemanticsLabel(RegExp('^Haus, $status')), findsOneWidget);
        expect(
            find.bySemanticsLabel(
                RegExp('^Boot, ${en ? 'still to find' : 'noch zu finden'}')),
            findsOneWidget);
        final grid = tester.widget<Semantics>(find
            .ancestor(
                of: find.byType(GridView), matching: find.byType(Semantics))
            .first);
        expect(grid.properties.label, en ? 'Word grid' : 'Wortgitter');
        expect(
            grid.properties.hint,
            en
                ? 'Drag across letters to select words'
                : 'Ziehe über Buchstaben, um Wörter zu markieren');
        expect(fixture.vocabulary.learningLanguage, 'de');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }
}
