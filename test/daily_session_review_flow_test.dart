import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/audio_service.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/language_pack_service.dart';
import 'package:WortUniversum/core/services/learner_profile_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/models/game_outcome.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/screens/sentence_completion_game.dart';
import 'package:WortUniversum/features/games/screens/sri_review_game.dart';
import 'package:WortUniversum/features/home/screens/daily_session_screen.dart';
import 'package:WortUniversum/generated/l10n.dart';

// Only installation is replaced. The real catalogue lookup, ambiguity guard,
// feature filtering and review builder run over these small hydrated entries.
class _ReadyVocabulary extends VocabularyService {
  @override
  bool get isInitialized => true;
  @override
  String get learningLanguage => 'de';
  @override
  Future<String> savedLearningLanguage() async => 'de';
  @override
  Future<bool> isPackInstalled(String language) async => language == 'de';
}

GermanWord _word(String text, String definition, String sentence,
        {String type = 'noun', String? article}) =>
    GermanWord.fromJson({
      'id': 'custom_$text',
      'word': text,
      'lemma': text,
      'wordType': type,
      'article': article,
      'gradeLevel': 1,
      'features': WordFeature.headword.mask |
          WordFeature.definitions.mask |
          WordFeature.usableDefinition.mask |
          WordFeature.gradeExamples.mask,
      'apiEnrichment': {
        'primary_lemma': text,
        'definitions': [definition],
        'grade_examples': {
          '1': [sentence],
        },
      },
    });

class _DailyFixture {
  final vocabulary = _ReadyVocabulary();
  final sri = SriService(clock: () => DateTime.utc(2026, 11, 8));
  final cognitive = CognitiveProfileService();
  final audio = AudioService()..setSoundEnabled(false);
  late final GameProvider game;
  late final LearnerProfileService profile;
  late final LanguagePackService packs;

  Future<void> initialize(List<SriLanguageData> records) async {
    SharedPreferences.setMockInitialValues({
      'learner_onboarding_complete': true,
      'onboarding_seen_sri_review': true,
      'onboarding_seen_sentence_completion': true,
      'hapticEnabled': false,
      'grade': 1,
      'learning_language': 'de',
      'sri_language_database': jsonEncode({
        for (final record in records) record.itemId: record.toJson(),
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    profile = LearnerProfileService(prefs);
    game = GameProvider(
      progressService: ProgressService(),
      sriService: sri,
      cognitiveProfileService: cognitive,
      prefs: prefs,
    );
    packs = LanguagePackService(vocabulary);
    for (final word in [
      _word('Hund', 'Ein Haustier, das bellt.', 'Der Hund schläft im Korb.',
          article: 'der'),
      _word('Katze', 'Ein Haustier, das miaut.', 'Die Katze sitzt am Fenster.',
          article: 'die'),
      _word('Haus', 'Ein Gebäude zum Wohnen.', 'Das Haus steht am Wald.',
          article: 'das'),
      _word('Baum', 'Eine große Pflanze mit einem Stamm.',
          'Der Baum steht im Garten.',
          article: 'der'),
      _word('Arm', 'Ein Körperteil zwischen Hand und Schulter.',
          'Mein Arm ist heute wieder gesund.',
          article: 'der'),
      _word(
          'arm', 'Jemand hat nur wenig Geld zum Leben.', 'Die Familie ist arm.',
          type: 'adjective'),
    ]) {
      await vocabulary.addCustomWord(word);
    }
    await sri.loadSriData();
  }

  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider<VocabularyService>.value(value: vocabulary),
          ChangeNotifierProvider<SriService>.value(value: sri),
          ChangeNotifierProvider<GameProvider>.value(value: game),
          ChangeNotifierProvider<LearnerProfileService>.value(value: profile),
          ChangeNotifierProvider<LanguagePackService>.value(value: packs),
          Provider<AudioService>.value(value: audio),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: S.supportedLocales,
          localizationsDelegates: S.localizationsDelegates,
          home: DailySessionScreen(),
        ),
      );

  void dispose() {
    packs.dispose();
    profile.dispose();
    game.dispose();
    cognitive.dispose();
    sri.dispose();
    vocabulary.dispose();
  }
}

void main() {
  Future<void> openDaily(WidgetTester tester, _DailyFixture fixture) async {
    addTearDown(fixture.dispose);
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(fixture.host());
    await tester.pumpAndSettle();
    expect(fixture.profile.dailyCompletedSteps, isEmpty);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
  }

  testWidgets('unsupported and ambiguous reviews fall back and finish step one',
      (tester) async {
    final fixture = _DailyFixture();
    final records = [
      SriLanguageData(
        itemId: 'READ_hund',
        skillType: LanguageSkillType.reading,
        nextReviewDate: DateTime.utc(2020),
        metadata: {'baseWord': 'Hund', 'wordId': 'custom_Hund'},
      ),
      SriLanguageData(
        itemId: 'SPELL_arm',
        skillType: LanguageSkillType.spelling,
        nextReviewDate: DateTime.utc(2020),
      ),
    ];
    await fixture.initialize(records);
    String snapshot() => jsonEncode({
          for (final record in records)
            record.itemId: fixture.sri.getItemData(record.itemId)!.toJson(),
        });
    final before = snapshot();
    expect(fixture.sri.getAvailableReviewCount(), 2);
    await openDaily(tester, fixture);

    expect(find.byType(SentenceCompletionGame), findsOneWidget);
    expect(find.byType(SriReviewGame), findsNothing);
    expect(find.text(lookupS(const Locale('en')).sentenceCompletionPrompt),
        findsOneWidget);
    expect(snapshot(), before);
    expect(fixture.sri.getAvailableReviewCount(), 2,
        reason: 'preparing a fallback must not consume unsupported cards');

    fixture.game.reportOutcome(GameOutcome.win(
      gameType: 'sentence_completion',
      difficulty: 1,
      score: 10,
    ));
    Navigator.of(tester.element(find.byType(SentenceCompletionGame))).pop();
    await tester.pumpAndSettle();
    expect(fixture.profile.dailyCompletedSteps, {1});
    expect(find.text('1/3'), findsOneWidget);
    expect(snapshot(), before);
    expect(fixture.sri.getAvailableReviewCount(), 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a supported article review answers and completes the daily step',
      (tester) async {
    final fixture = _DailyFixture();
    final itemId = fixture.sri.getItemId(
      skillType: LanguageSkillType.articleSelection,
      baseWord: 'Hund',
      wordId: 'custom_Hund',
    );
    await fixture.initialize([
      SriLanguageData(
        itemId: itemId,
        skillType: LanguageSkillType.articleSelection,
        nextReviewDate: DateTime.utc(2020),
        metadata: {'baseWord': 'Hund', 'wordId': 'custom_Hund'},
      ),
    ]);
    await openDaily(tester, fixture);
    expect(find.byType(SriReviewGame), findsOneWidget);
    expect(find.byType(SentenceCompletionGame), findsNothing);
    expect(fixture.game.totalGamesPlayed, 0);

    await tester.tap(find.text('der'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(fixture.sri.getItemData(itemId)!.successCount, 1);
    expect(fixture.game.totalGamesPlayed, 1);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text(lookupS(const Locale('en')).backToMenu));
    await tester.pumpAndSettle();
    expect(fixture.profile.dailyCompletedSteps, {1});
    expect(find.text('1/3'), findsOneWidget);
    expect(fixture.sri.getItemData(itemId)!.skillType,
        LanguageSkillType.articleSelection);
    expect(fixture.sri.getAvailableReviewCount(), 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
