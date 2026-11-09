import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/audio_service.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/screens/sentence_completion_game.dart';
import 'package:WortUniversum/generated/l10n.dart';

import 'word_fixture.dart';

class _SentenceVocabulary extends VocabularyService {
  final List<GermanWord> words;
  _SentenceVocabulary(this.words);

  @override
  bool get isInitialized => true;
  @override
  String get learningLanguage => 'de';
  @override
  Future<List<GermanWord>> takeWordsWithFeature(WordFeature feature,
          {required GameProvider settingsProvider,
          int? gradeLevel,
          int limit = 60,
          bool Function(GermanWord)? where,
          Random? random}) async =>
      words.where((w) => where?.call(w) ?? true).take(limit).toList();
}

List<GermanWord> _words() {
  GermanWord adjective(
          String word, String form, String meaning, String source) =>
      testWord(word,
          type: GermanWordType.adjektiv,
          grade: 4,
          enrichment: testEnrichment(definitions: [
            meaning
          ], gradeExamples: {
            '4': [source]
          }, inflections: [
            {
              'form_text': form,
              'tags': 'masculine, nominative, singular, positive, strong'
            }
          ]));
  return [
    adjective('sonnig', 'sonniger', 'Von der Sonne beschienen.',
        'Ein sonniger Tag am Meer ist immer schön.'),
    adjective('wichtig', 'wichtiger', 'Von großer Bedeutung.',
        'Das Ergebnis ist wichtig.'),
    adjective(
        'still', 'stiller', 'Ohne Lärm oder Bewegung.', 'Das Kind ist still.'),
    adjective('dreckig', 'dreckiger', 'Mit Schmutz bedeckt.',
        'Das Hemd ist dreckig.'),
  ];
}

void main() {
  for (final locale in ['de', 'en']) {
    testWidgets(
        '$locale: clue precedes scoring and SRI records lexical vocabulary',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'hapticEnabled': false,
        'onboarding_seen_sentence_completion': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final words = _words();
      final vocabulary = _SentenceVocabulary(words);
      final sri = SriService();
      final cognitive = CognitiveProfileService();
      final game = GameProvider(
          progressService: ProgressService(),
          sriService: sri,
          cognitiveProfileService: cognitive,
          prefs: prefs);
      final audio = AudioService()..setSoundEnabled(false);
      addTearDown(() {
        vocabulary.dispose();
        sri.dispose();
        cognitive.dispose();
        game.dispose();
      });
      tester.view.physicalSize = const Size(900, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<VocabularyService>.value(value: vocabulary),
            ChangeNotifierProvider<SriService>.value(value: sri),
            ChangeNotifierProvider<GameProvider>.value(value: game),
            Provider<AudioService>.value(value: audio),
          ],
          child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: S.supportedLocales,
              localizationsDelegates: S.localizationsDelegates,
              home: const SentenceCompletionGame(
                  gradeLevel: GradeLevel.grade4))));
      await tester.pumpAndSettle();
      final strings = lookupS(Locale(locale));
      expect(find.text(strings.sentenceCompletionPrompt), findsOneWidget);
      expect(
          find.text(strings
              .sentenceCompletionMeaningCue('Von der Sonne beschienen.')),
          findsOneWidget);
      expect(sri.totalAttempts, 0);
      expect(find.text('sonniger'), findsOneWidget);
      expect(find.text('sonnig'), findsNothing);

      // Exercise correct and incorrect responses through the actual screen.
      final correct = locale == 'de';
      final option = find.text(correct ? 'sonniger' : 'wichtiger');
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pump(const Duration(milliseconds: 600));
      final id = sri.getItemId(
          skillType: LanguageSkillType.vocabulary,
          baseWord: 'sonnig',
          wordId: words.first.id);
      final record = sri.getItemData(id)!;
      expect(record.skillType, LanguageSkillType.vocabulary);
      expect(record.identity.wordId, words.first.id);
      expect(record.successCount, correct ? 1 : 0);
      expect(record.failureCount, correct ? 0 : 1);
      expect(sri.totalTrackedItems, 1);
      expect(
          find.text('Ein sonniger Tag am Meer ist immer schön.',
              findRichText: true),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
