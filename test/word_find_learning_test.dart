import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/features/games/screens/word_find_game.dart';

import 'features/games/word_fixture.dart';
import 'game_localization_fixtures.dart';

void main() {
  testWidgets(
      'one uppercase grid target keeps one lexical identity and finishes',
      (tester) async {
    final fixture = GameLocalizationFixture([
      testWord('Arm', grade: 1),
      testWord('arm', grade: 1, type: GermanWordType.adjektiv),
    ]);
    await fixture.initialize();
    addTearDown(fixture.dispose);
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
        fixture.app('en', const WordFindGame(gradeLevel: GradeLevel.grade1)));
    await tester.pump();
    expect(
        find.bySemanticsLabel(RegExp('^Arm, still to find')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^arm, still to find')), findsNothing);

    // Solve what was rendered, so the test covers random grid placement and
    // the actual gesture/answer recording path rather than private state.
    final cells =
        find.descendant(of: find.byType(GridView), matching: find.byType(Text));
    final letters =
        tester.widgetList<Text>(cells).map((text) => text.data!).toList();
    expect(letters, hasLength(64));
    List<int>? path;
    for (var start = 0; start < 64; start++) {
      for (final direction in [
        const Offset(1, 0),
        const Offset(0, 1),
        const Offset(-1, 0),
        const Offset(0, -1),
      ]) {
        final indices = <int>[];
        for (var offset = 0; offset < 3; offset++) {
          final row = start ~/ 8 + direction.dy.toInt() * offset;
          final column = start % 8 + direction.dx.toInt() * offset;
          if (row < 0 || row >= 8 || column < 0 || column >= 8) break;
          indices.add(row * 8 + column);
        }
        if (indices.map((index) => letters[index]).join() == 'ARM') {
          path = indices;
        }
      }
    }
    expect(path, isNotNull);
    final start = tester.getCenter(cells.at(path!.first));
    final end = tester.getCenter(cells.at(path.last));
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + (end - start) / 6);
    await gesture.moveTo(end);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'two indistinguishable ARM placements must not trap the round');
    expect(fixture.sri.totalTrackedItems, 1);
    final card = fixture.sri.getItemData(fixture.sri.getItemId(
      skillType: LanguageSkillType.vocabulary,
      baseWord: 'Arm',
      wordId: 'test_Arm',
    ))!;
    expect(card.successCount, 1);
    expect(card.assistedSuccessCount, 1);
    expect(card.metadata['wordId'], 'test_Arm');
    expect(
        fixture.sri.getItemData(fixture.sri.getItemId(
          skillType: LanguageSkillType.vocabulary,
          baseWord: 'arm',
          wordId: 'test_arm',
        )),
        isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
