import 'package:flutter/material.dart';
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
import 'package:WortUniversum/generated/l10n.dart';

/// A pack word as the catalogue hands one over: light, with the feature bits
/// the index would have computed. Games filter on those, so a fixture without
/// them is filtered out — Großstadt generated nothing at all.
GermanWord germanNoun(String word) => GermanWord.fromJson({
      'id': word,
      'word': word,
      'lemma': word,
      'wordType': 'substantiv',
      'gradeLevel': 1,
      'article': 'das',
      'features': WordFeature.usableDefinition.mask |
          WordFeature.headword.mask |
          WordFeature.definitions.mask,
      'isHydrated': false,
    });

class GermanVocabularyFixture extends VocabularyService {
  final List<GermanWord> words;
  GermanVocabularyFixture(this.words);
  @override
  String get learningLanguage => 'de';
  @override
  bool get isInitialized => true;
  @override
  List<GermanWord> getAllWords(GameProvider settingsProvider) => [...words];
  @override
  List<GermanWord> getWordsByGrade(
          GradeLevel grade, GameProvider settingsProvider) =>
      [...words];
  @override
  List<GermanWord> getNewWords(
          {required SriService sriService,
          required GameProvider settingsProvider,
          required GradeLevel grade,
          int limit = 5}) =>
      words.take(limit).toList();
}

class GameLocalizationFixture {
  final GermanVocabularyFixture vocabulary;
  final sri = SriService();
  final progress = ProgressService();
  final cognitive = CognitiveProfileService();
  final audio = AudioService()..setSoundEnabled(false);
  late final GameProvider game;
  GameLocalizationFixture(List<GermanWord> words)
      : vocabulary = GermanVocabularyFixture(words);
  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({'hapticEnabled': false});
    game = GameProvider(
        progressService: progress,
        sriService: sri,
        cognitiveProfileService: cognitive,
        prefs: await SharedPreferences.getInstance());
  }

  Widget app(String locale, Widget child) => MultiProvider(
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
              home: child));
  void dispose() {
    vocabulary.dispose();
    sri.dispose();
    game.dispose();
    cognitive.dispose();
  }
}
