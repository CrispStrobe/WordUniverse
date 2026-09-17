import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/space_word_rescue_hints.dart';
import 'game_localization_fixtures.dart';

void main() {
  for (final mode in ['mistakes', 'variants', 'incorrect']) {
    testWidgets(
        'rescue $mode wrappers follow interface locale, retaining German forms',
        (tester) async {
      final word = GermanWord.fromJson({
        'id': 'Hund',
        'word': 'Hund',
        'lemma': 'Hund',
        'wordType': 'substantiv',
        'article': 'der',
        'gradeLevel': 1,
        'commonMistakes': mode == 'mistakes' ? ['Hunt', 'Huhnd'] : <String>[],
        'graphematicVariants': mode == 'variants'
            ? [
                {'spelling': 'Hunt'}
              ]
            : [],
      });
      final fixture = GameLocalizationFixture([word]);
      await fixture.initialize();
      addTearDown(fixture.dispose);
      for (final locale in ['en', 'de', 'en']) {
        await tester.pumpWidget(fixture.app(
            locale,
            Scaffold(
                body: Builder(
              builder: (context) => Text(generateEducationalHint(context, word,
                  isCommonMistake: mode != 'incorrect',
                  isIncorrect: mode == 'incorrect')),
            ))));
        await tester.pump();
        final en = locale == 'en';
        final expected = switch (mode) {
          'mistakes' => en
              ? 'Common mistake! Remember: Hund • Not: Hunt, Huhnd'
              : 'Häufiger Fehler! Merke dir: Hund • Nicht: Hunt, Huhnd',
          'variants' => en
              ? 'Common mistake! Remember: Hund • Correct spelling: Hund'
              : 'Häufiger Fehler! Merke dir: Hund • Richtige Schreibweise: Hund',
          _ => en ? 'Learn: der Hund • Nomen' : 'Lerne: der Hund • Nomen',
        };
        expect(find.text(expected), findsOneWidget);
        expect(fixture.vocabulary.learningLanguage, 'de');
        expect(tester.takeException(), isNull);
      }
    });
  }
}
