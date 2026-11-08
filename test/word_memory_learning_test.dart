import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/screens/word_memory_game.dart';

import 'features/games/word_fixture.dart';
import 'game_localization_fixtures.dart';

void main() {
  Future<GameLocalizationFixture> openGame(
    WidgetTester tester,
    GradeLevel grade, {
    List<GermanWord>? words,
  }) async {
    final fixture = GameLocalizationFixture(words ??
        [
          testWord('Hund',
              grade: grade.index + 1,
              article: 'der',
              enrichment:
                  testEnrichment(definitions: ['Ein Haustier, das bellt.'])),
          testWord('Katze',
              grade: grade.index + 1,
              article: 'die',
              enrichment:
                  testEnrichment(definitions: ['Ein Haustier, das miaut.'])),
        ]);
    await fixture.initialize();
    addTearDown(fixture.dispose);
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(fixture.app('en', WordMemoryGame(gradeLevel: grade)));
    await tester.pump();
    return fixture;
  }

  Future<void> choosePair(WidgetTester tester, int first, int second) async {
    await tester.tap(find.byKey(ValueKey('memory-card-$first')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('memory-card-$second')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    // The mismatch delay starts after the shake animation completes.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'memory guesses are not spelling failures; copied pairs are practice',
      (tester) async {
    final fixture = await openGame(tester, GradeLevel.grade1);
    await choosePair(tester, 0, 2);
    expect(fixture.sri.totalTrackedItems, 0,
        reason: 'two unseen different cards are not a language error');

    await choosePair(tester, 0, 1);
    final card = fixture.sri.getItemData(fixture.sri.getItemId(
      skillType: LanguageSkillType.spelling,
      baseWord: 'Hund',
      wordId: 'test_Hund',
    ))!;
    expect(card.successCount, 1);
    expect(card.failureCount, 0);
    expect(card.assistedSuccessCount, 1);
    expect(card.repetitions, 0);
    expect(card.metadata['responseFormat'], 'wordShapeMatch');

    // A thin catalogue makes two pairs, and those two must finish the round.
    await choosePair(tester, 2, 3);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fixture.sri.totalMasteredItems, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('definition pairs record vocabulary instead of spelling',
      (tester) async {
    final fixture = await openGame(tester, GradeLevel.grade3);
    await choosePair(tester, 0, 1);
    expect(fixture.sri.getItemData('SPELL_hund'), isNull);
    final card = fixture.sri.getItemData(fixture.sri.getItemId(
      skillType: LanguageSkillType.vocabulary,
      baseWord: 'Hund',
      wordId: 'test_Hund',
    ))!;
    expect(card.successCount, 1);
    expect(card.metadata['gradeLevel'], 3);
    expect(card.metadata['responseFormat'], 'definitionMatch');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving during the reveal does not mutate a disposed screen',
      (tester) async {
    final fixture = await openGame(tester, GradeLevel.grade1);
    await tester.tap(find.byKey(const ValueKey('memory-card-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('memory-card-1')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.sri.totalTrackedItems, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('matching Arm and arm records the two actual lexical identities',
      (tester) async {
    final fixture = await openGame(tester, GradeLevel.grade1, words: [
      testWord('Arm', grade: 1),
      testWord('arm', grade: 1, type: GermanWordType.adjektiv),
    ]);
    await choosePair(tester, 0, 1);
    await choosePair(tester, 2, 3);
    expect(fixture.sri.totalTrackedItems, 2);
    for (final word in ['Arm', 'arm']) {
      final card = fixture.sri.getItemData(fixture.sri.getItemId(
        skillType: LanguageSkillType.spelling,
        baseWord: word,
        wordId: 'test_$word',
      ))!;
      expect(card.successCount, 1);
      expect(card.assistedSuccessCount, 1);
      expect(card.metadata['wordId'], 'test_$word');
      expect(card.metadata['baseWord'], word);
    }
    expect(fixture.sri.getItemData('SPELL_arm'), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'two senses with identical word faces do not make ambiguous pairs',
      (tester) async {
    final fixture = await openGame(tester, GradeLevel.grade1, words: [
      GermanWord.fromJson({
        ...testWord('sein', grade: 1, type: GermanWordType.verb).toJson(),
        'id': 'verb_sein',
      }),
      GermanWord.fromJson({
        ...testWord('sein', grade: 1, type: GermanWordType.pronomen).toJson(),
        'id': 'possessive_sein',
      }),
    ]);
    expect(find.byKey(const ValueKey('memory-card-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('memory-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('memory-card-2')), findsNothing);
    await choosePair(tester, 0, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fixture.sri.totalTrackedItems, 1);
    final card = fixture.sri.getItemData(fixture.sri.getItemId(
      skillType: LanguageSkillType.spelling,
      baseWord: 'sein',
      wordId: 'verb_sein',
    ))!;
    expect(card.metadata['wordId'], 'verb_sein');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
