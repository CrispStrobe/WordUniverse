import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/screens/word_type_whirl_game.dart';
import 'game_localization_fixtures.dart';

void main() {
  for (final correct in [true, false]) {
    testWidgets(
        'whirl $correct feedback uses interface locale with German learning',
        (tester) async {
      // Only nouns meet the target-pool threshold; the verb is always wrong.
      final nouns = ['Haus', 'Boot'];
      final fixture = GameLocalizationFixture([
        ...nouns.map(germanNoun),
        GermanWord.fromJson({
          'id': 'laufen',
          'word': 'laufen',
          'wordType': 'verb',
          'gradeLevel': 1
        }),
      ]);
      await fixture.initialize();
      addTearDown(fixture.dispose);
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const screen = WordTypeWhirlGame(gradeLevel: GradeLevel.grade1);
      try {
        await tester.pumpWidget(fixture.app('en', screen));
        await tester.pump();
        final state = tester.state(find.byType(WordTypeWhirlGame));
        for (final locale in ['en', 'de', 'en']) {
          await tester.pumpWidget(fixture.app(locale, screen));
          await tester.pump();
          expect(tester.state(find.byType(WordTypeWhirlGame)), same(state));
          Finder? card;
          String? word;
          for (var attempt = 0; attempt < 20; attempt++) {
            await tester.pump(const Duration(milliseconds: 400));
            for (final candidate in correct ? nouns : ['laufen']) {
              final finder = find.byKey(ValueKey<String>(candidate));
              if (finder.evaluate().isNotEmpty &&
                  find
                      .descendant(
                          of: finder, matching: find.byIcon(Icons.check))
                      .evaluate()
                      .isEmpty &&
                  find
                      .descendant(
                          of: finder, matching: find.byIcon(Icons.close))
                      .evaluate()
                      .isEmpty) {
                card = finder;
                word = candidate.toUpperCase();
                break;
              }
            }
            if (card != null) break;
          }
          expect(card, isNotNull);
          // Invoke the rendered card's tap callback, avoiding orbital hit-test races.
          tester
              .widget<GestureDetector>(find.descendant(
                  of: card!, matching: find.byType(GestureDetector)))
              .onTap!();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 450));
          final en = locale == 'en';
          final expected = correct
              ? '${en ? '✓ Correct!' : '✓ Richtig!'} $word'
              : en
                  ? '✗ Wrong! $word does not belong to: Nouns'
                  : '✗ Falsch! $word gehört nicht zu: Nomen';
          expect(find.text(expected), findsOneWidget);
          expect(fixture.vocabulary.learningLanguage, 'de');
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 3));
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      }
    });
  }
}
