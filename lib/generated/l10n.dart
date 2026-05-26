import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'l10n_de.dart';
import 'l10n_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S? of(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Universe'**
  String get appTitle;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Discover the Word Universe!'**
  String get welcome;

  /// No description provided for @startAdventure.
  ///
  /// In en, this message translates to:
  /// **'Start Word Adventure'**
  String get startAdventure;

  /// No description provided for @chooseGrade.
  ///
  /// In en, this message translates to:
  /// **'Choose Your Level'**
  String get chooseGrade;

  /// No description provided for @grade3.
  ///
  /// In en, this message translates to:
  /// **'Level 1'**
  String get grade3;

  /// No description provided for @grade4.
  ///
  /// In en, this message translates to:
  /// **'Level 2'**
  String get grade4;

  /// No description provided for @grade5.
  ///
  /// In en, this message translates to:
  /// **'Level 3'**
  String get grade5;

  /// No description provided for @grade6.
  ///
  /// In en, this message translates to:
  /// **'Level 4'**
  String get grade6;

  /// No description provided for @licensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get licensesTitle;

  /// No description provided for @viewOssLicenses.
  ///
  /// In en, this message translates to:
  /// **'View open-source licenses'**
  String get viewOssLicenses;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Word Universe'**
  String get appName;

  /// No description provided for @appLegalese.
  ///
  /// In en, this message translates to:
  /// **'© 2025–2026 CrispStrobe\n\nVocabulary databases (DE + EN) licensed under CC BY-SA 4.0. Sources: Wiktionary, ConceptNet, OEWN, OpenThesaurus, OdeNet, LiTKey, Tatoeba, Project Gutenberg, and others. Full attribution in the license entries below.\n\nDatasets: huggingface.co/datasets/cstr/grundwortschatz-voc-de  ·  cstr/grundwortschatz-voc-en\n\nApp code is proprietary.'**
  String get appLegalese;

  /// No description provided for @spaceWordRescueTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Rescue'**
  String get spaceWordRescueTitle;

  /// No description provided for @spaceWordRescueInstructions.
  ///
  /// In en, this message translates to:
  /// **'Rescue words from drifting off into space! Type them in.'**
  String get spaceWordRescueInstructions;

  /// No description provided for @wordRescueTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Rescue'**
  String get wordRescueTitle;

  /// No description provided for @wordRescueCardDescription.
  ///
  /// In en, this message translates to:
  /// **'Type words before they escape!'**
  String get wordRescueCardDescription;

  /// No description provided for @wordRescueTypeWord.
  ///
  /// In en, this message translates to:
  /// **'Type the word to rescue it!'**
  String get wordRescueTypeWord;

  /// No description provided for @wordRescueTypeHere.
  ///
  /// In en, this message translates to:
  /// **'Type here...'**
  String get wordRescueTypeHere;

  /// No description provided for @wordRescueFeedbackPerfect.
  ///
  /// In en, this message translates to:
  /// **'Perfect! Word Rescued! 🚀'**
  String get wordRescueFeedbackPerfect;

  /// No description provided for @wordRescueFeedbackCommonMistake.
  ///
  /// In en, this message translates to:
  /// **'Close enough! {word} rescued!'**
  String wordRescueFeedbackCommonMistake(String word);

  /// No description provided for @wordRescueFeedbackIncorrect.
  ///
  /// In en, this message translates to:
  /// **'Too late! The correct word was: {word}'**
  String wordRescueFeedbackIncorrect(String word);

  /// No description provided for @wordRescueFeedbackLost.
  ///
  /// In en, this message translates to:
  /// **'Word escaped into space! 💫'**
  String get wordRescueFeedbackLost;

  /// No description provided for @wordRescueGameOverStats.
  ///
  /// In en, this message translates to:
  /// **'You rescued {rescued} out of {total} words ({percentage}%)'**
  String wordRescueGameOverStats(int rescued, int total, int percentage);

  /// No description provided for @wordSnakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Snake'**
  String get wordSnakeTitle;

  /// No description provided for @wordSnakeDescription.
  ///
  /// In en, this message translates to:
  /// **'Identify and trace the words: Connect letters in the correct to spell the word.'**
  String get wordSnakeDescription;

  /// No description provided for @wordSnakeInstructions.
  ///
  /// In en, this message translates to:
  /// **'Tap cells in order to form a path that spells the word'**
  String get wordSnakeInstructions;

  /// No description provided for @wordSnakeConnectLetters.
  ///
  /// In en, this message translates to:
  /// **'Connect {count} letters'**
  String wordSnakeConnectLetters(int count);

  /// No description provided for @wordSnakeReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get wordSnakeReset;

  /// No description provided for @wordSnakePuzzleProgress.
  ///
  /// In en, this message translates to:
  /// **'Puzzle {current} of {total}'**
  String wordSnakePuzzleProgress(int current, int total);

  /// No description provided for @gameplayHint.
  ///
  /// In en, this message translates to:
  /// **'Hint (-2 Points)'**
  String get gameplayHint;

  /// No description provided for @gameplayCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get gameplayCheck;

  /// No description provided for @gameplayCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct! Well done! 🚀'**
  String get gameplayCorrect;

  /// No description provided for @gameplayIncorrect.
  ///
  /// In en, this message translates to:
  /// **'That wasn\'t quite right. Try the next one!'**
  String get gameplayIncorrect;

  /// No description provided for @gameplayRescued.
  ///
  /// In en, this message translates to:
  /// **'Rescued'**
  String get gameplayRescued;

  /// No description provided for @gameplayLost.
  ///
  /// In en, this message translates to:
  /// **'Lost'**
  String get gameplayLost;

  /// No description provided for @gameplayWriteTheWord.
  ///
  /// In en, this message translates to:
  /// **'Type the word...'**
  String get gameplayWriteTheWord;

  /// No description provided for @gameplayFeedbackCommonMistake.
  ///
  /// In en, this message translates to:
  /// **'Almost right! A common mistake.\nCorrect is: {correctWord}'**
  String gameplayFeedbackCommonMistake(Object correctWord);

  /// No description provided for @gameplayFeedbackIncorrect.
  ///
  /// In en, this message translates to:
  /// **'Sorry, that\'s wrong! Correct is: {correctWord}'**
  String gameplayFeedbackIncorrect(Object correctWord);

  /// No description provided for @wordFindTitle.
  ///
  /// In en, this message translates to:
  /// **'Word-Find'**
  String get wordFindTitle;

  /// No description provided for @wordFindDescription.
  ///
  /// In en, this message translates to:
  /// **'Spot the hidden words in the letter grid! Drag to mark them.'**
  String get wordFindDescription;

  /// No description provided for @wordFindWordsToFind.
  ///
  /// In en, this message translates to:
  /// **'Words to Find:'**
  String get wordFindWordsToFind;

  /// No description provided for @wordSortTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Sort Game'**
  String get wordSortTitle;

  /// No description provided for @wordSortDescription.
  ///
  /// In en, this message translates to:
  /// **'Sort words into categories: nouns, verbs, and adjectives'**
  String get wordSortDescription;

  /// No description provided for @wordSortTitleTimeAttack.
  ///
  /// In en, this message translates to:
  /// **'Word Sort - Time Attack!'**
  String get wordSortTitleTimeAttack;

  /// No description provided for @wordSortCategoryNoun.
  ///
  /// In en, this message translates to:
  /// **'Nouns'**
  String get wordSortCategoryNoun;

  /// No description provided for @wordSortCategoryVerb.
  ///
  /// In en, this message translates to:
  /// **'Verbs'**
  String get wordSortCategoryVerb;

  /// No description provided for @wordSortCategoryAdjective.
  ///
  /// In en, this message translates to:
  /// **'Adjectives'**
  String get wordSortCategoryAdjective;

  /// No description provided for @wordSortCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct! Well done!'**
  String get wordSortCorrect;

  /// No description provided for @wordSortIncorrect.
  ///
  /// In en, this message translates to:
  /// **'Not quite right. Let\'s learn!'**
  String get wordSortIncorrect;

  /// No description provided for @wordSortTimeUp.
  ///
  /// In en, this message translates to:
  /// **'Time\'s up!'**
  String get wordSortTimeUp;

  /// No description provided for @wordSortStreakBonus.
  ///
  /// In en, this message translates to:
  /// **'🔥 {streak} in a row! Bonus points!'**
  String wordSortStreakBonus(int streak);

  /// No description provided for @wordSortHintNounArticle.
  ///
  /// In en, this message translates to:
  /// **'Correct! You say \'{article}\' - the article shows it\'s a {gender} noun.'**
  String wordSortHintNounArticle(String article, String gender);

  /// No description provided for @wordSortHintNounPlural.
  ///
  /// In en, this message translates to:
  /// **'The plural of \'{singular}\' is \'{plural}\'.'**
  String wordSortHintNounPlural(String singular, String plural);

  /// No description provided for @wordSortHintVerbConjugation.
  ///
  /// In en, this message translates to:
  /// **'Correct! Verbs change: \'{ich}\', \'{du}\' - they conjugate with the person!'**
  String wordSortHintVerbConjugation(String ich, String du);

  /// No description provided for @wordSortHintAdjectiveComparison.
  ///
  /// In en, this message translates to:
  /// **'Adjectives have degrees: {base} → {comparative} → {superlative}'**
  String wordSortHintAdjectiveComparison(
      String base, String comparative, String superlative);

  /// No description provided for @wordSortWhyNot.
  ///
  /// In en, this message translates to:
  /// **'No, it\'s not a {type}.'**
  String wordSortWhyNot(String type);

  /// No description provided for @wordSortWhyNoun.
  ///
  /// In en, this message translates to:
  /// **'It\'s a NOUN because you say \'{article}\' - articles go before nouns!'**
  String wordSortWhyNoun(String article);

  /// No description provided for @wordSortNounDeclensionExample.
  ///
  /// In en, this message translates to:
  /// **'Nouns change by case: {nominative} → {genitive}'**
  String wordSortNounDeclensionExample(String nominative, String genitive);

  /// No description provided for @wordSortWhyVerb.
  ///
  /// In en, this message translates to:
  /// **'It\'s a VERB because it conjugates: {forms}'**
  String wordSortWhyVerb(String forms);

  /// No description provided for @wordSortWhyAdjective.
  ///
  /// In en, this message translates to:
  /// **'It\'s an ADJECTIVE because it has comparison forms: {base} → {comparative} → {superlative}'**
  String wordSortWhyAdjective(
      String base, String comparative, String superlative);

  /// No description provided for @wordSortHintLookForArticle.
  ///
  /// In en, this message translates to:
  /// **'💡 Hint: Look for the article (der/die/das)!'**
  String get wordSortHintLookForArticle;

  /// No description provided for @wordSortHintArticleExample.
  ///
  /// In en, this message translates to:
  /// **'This word has the article \'{article}\''**
  String wordSortHintArticleExample(String article);

  /// No description provided for @wordSortHintLookForConjugation.
  ///
  /// In en, this message translates to:
  /// **'💡 Hint: Can you say \'ich...\' with this word?'**
  String get wordSortHintLookForConjugation;

  /// No description provided for @wordSortHintLookForComparison.
  ///
  /// In en, this message translates to:
  /// **'💡 Hint: Can this word describe something? Can it get \'more\' or \'most\'?'**
  String get wordSortHintLookForComparison;

  /// No description provided for @wordSortToggleTimeAttack.
  ///
  /// In en, this message translates to:
  /// **'Toggle Time Attack Mode'**
  String get wordSortToggleTimeAttack;

  /// No description provided for @wordSortShowHint.
  ///
  /// In en, this message translates to:
  /// **'Show Hint'**
  String get wordSortShowHint;

  /// No description provided for @wordSortTimeAttackComplete.
  ///
  /// In en, this message translates to:
  /// **'Time Attack Complete!'**
  String get wordSortTimeAttackComplete;

  /// No description provided for @score.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get score;

  /// No description provided for @correct.
  ///
  /// In en, this message translates to:
  /// **'Correct!'**
  String get correct;

  /// No description provided for @gameOver.
  ///
  /// In en, this message translates to:
  /// **'Expedition Complete!'**
  String get gameOver;

  /// No description provided for @backToMenu.
  ///
  /// In en, this message translates to:
  /// **'Back to the Word Universe'**
  String get backToMenu;

  /// No description provided for @playAgain.
  ///
  /// In en, this message translates to:
  /// **'Play Again'**
  String get playAgain;

  /// No description provided for @adaptiveDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Adaptive Difficulty'**
  String get adaptiveDifficulty;

  /// No description provided for @adaptiveDifficultyDesc.
  ///
  /// In en, this message translates to:
  /// **'Adjusts problems based on your skill'**
  String get adaptiveDifficultyDesc;

  /// No description provided for @adjustProblems.
  ///
  /// In en, this message translates to:
  /// **'Adjusts problems based on your skill'**
  String get adjustProblems;

  /// No description provided for @gameMenu.
  ///
  /// In en, this message translates to:
  /// **'Word Universe'**
  String get gameMenu;

  /// No description provided for @level.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get level;

  /// No description provided for @lives.
  ///
  /// In en, this message translates to:
  /// **'Hull Integrity'**
  String get lives;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @incorrect.
  ///
  /// In en, this message translates to:
  /// **'Error!'**
  String get incorrect;

  /// No description provided for @excellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent, Explorer!'**
  String get excellent;

  /// No description provided for @good.
  ///
  /// In en, this message translates to:
  /// **'Good job!'**
  String get good;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again!'**
  String get tryAgain;

  /// No description provided for @nextLevel.
  ///
  /// In en, this message translates to:
  /// **'Next Expedition'**
  String get nextLevel;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @sound.
  ///
  /// In en, this message translates to:
  /// **'Sound FX'**
  String get sound;

  /// No description provided for @music.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get music;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @progress.
  ///
  /// In en, this message translates to:
  /// **'Career Progress'**
  String get progress;

  /// No description provided for @achievements.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievements;

  /// No description provided for @congratulations.
  ///
  /// In en, this message translates to:
  /// **'Congratulations, Explorer!'**
  String get congratulations;

  /// No description provided for @missionsCompleted.
  ///
  /// In en, this message translates to:
  /// **'Expeditions Completed: {count}'**
  String missionsCompleted(int count);

  /// No description provided for @starsEarned.
  ///
  /// In en, this message translates to:
  /// **'Stars Earned: {count}'**
  String starsEarned(int count);

  /// No description provided for @audioSettings.
  ///
  /// In en, this message translates to:
  /// **'Audio Settings'**
  String get audioSettings;

  /// No description provided for @soundEffects.
  ///
  /// In en, this message translates to:
  /// **'Sound effects'**
  String get soundEffects;

  /// No description provided for @backgroundMusicDesc.
  ///
  /// In en, this message translates to:
  /// **'Background music'**
  String get backgroundMusicDesc;

  /// No description provided for @gameplay.
  ///
  /// In en, this message translates to:
  /// **'Gameplay'**
  String get gameplay;

  /// No description provided for @puzzleTimer.
  ///
  /// In en, this message translates to:
  /// **'Puzzle Timer'**
  String get puzzleTimer;

  /// No description provided for @puzzleTimerDesc.
  ///
  /// In en, this message translates to:
  /// **'Enable timer in puzzle games'**
  String get puzzleTimerDesc;

  /// No description provided for @showHints.
  ///
  /// In en, this message translates to:
  /// **'Show Hints'**
  String get showHints;

  /// No description provided for @showHintsDesc.
  ///
  /// In en, this message translates to:
  /// **'Display helpful hints during games'**
  String get showHintsDesc;

  /// No description provided for @hapticFeedback.
  ///
  /// In en, this message translates to:
  /// **'Haptic Feedback'**
  String get hapticFeedback;

  /// No description provided for @hapticFeedbackDesc.
  ///
  /// In en, this message translates to:
  /// **'Vibration on touch (if supported)'**
  String get hapticFeedbackDesc;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get appLanguage;

  /// No description provided for @appLanguageDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose your preferred language'**
  String get appLanguageDesc;

  /// No description provided for @learningLanguage.
  ///
  /// In en, this message translates to:
  /// **'Learning language'**
  String get learningLanguage;

  /// No description provided for @learningLanguageDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose which vocabulary database games use'**
  String get learningLanguageDesc;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get languageGerman;

  /// No description provided for @difficulty.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get difficulty;

  /// No description provided for @currentGrade.
  ///
  /// In en, this message translates to:
  /// **'Current Level'**
  String get currentGrade;

  /// No description provided for @currentLevelDesc.
  ///
  /// In en, this message translates to:
  /// **'Current Level'**
  String get currentLevelDesc;

  /// No description provided for @difficultyDescGrade3.
  ///
  /// In en, this message translates to:
  /// **'Simple words (Grades 1-2)'**
  String get difficultyDescGrade3;

  /// No description provided for @difficultyDescGrade4.
  ///
  /// In en, this message translates to:
  /// **'Common words (Grades 3-4)'**
  String get difficultyDescGrade4;

  /// No description provided for @difficultyDescGrade5.
  ///
  /// In en, this message translates to:
  /// **'Advanced words (Grades 5-6)'**
  String get difficultyDescGrade5;

  /// No description provided for @difficultyDescGrade6.
  ///
  /// In en, this message translates to:
  /// **'Expert vocabulary (Grades 6+)'**
  String get difficultyDescGrade6;

  /// No description provided for @totalScore.
  ///
  /// In en, this message translates to:
  /// **'Total Score'**
  String get totalScore;

  /// No description provided for @gamesPlayed.
  ///
  /// In en, this message translates to:
  /// **'Games Played'**
  String get gamesPlayed;

  /// No description provided for @resetProgress.
  ///
  /// In en, this message translates to:
  /// **'Reset Progress'**
  String get resetProgress;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'App Version'**
  String get appVersion;

  /// No description provided for @developer.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get developer;

  /// No description provided for @developerName.
  ///
  /// In en, this message translates to:
  /// **'Word Universe Team'**
  String get developerName;

  /// No description provided for @targetAge.
  ///
  /// In en, this message translates to:
  /// **'Target Age'**
  String get targetAge;

  /// No description provided for @targetAgeRange.
  ///
  /// In en, this message translates to:
  /// **'6-12 years (Grades 1-6)'**
  String get targetAgeRange;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'Word Universe helps primary school students learn spelling and vocabulary through engaging space-themed games.'**
  String get aboutApp;

  /// No description provided for @debugPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Debug Panel'**
  String get debugPanelTitle;

  /// No description provided for @debugForceUnlock.
  ///
  /// In en, this message translates to:
  /// **'Force Full Unlock'**
  String get debugForceUnlock;

  /// No description provided for @debugApplyAndClose.
  ///
  /// In en, this message translates to:
  /// **'Apply & Close'**
  String get debugApplyAndClose;

  /// No description provided for @parentalGateTitle.
  ///
  /// In en, this message translates to:
  /// **'Parental Gate'**
  String get parentalGateTitle;

  /// No description provided for @parentalGateChallenge.
  ///
  /// In en, this message translates to:
  /// **'To continue, please solve this problem:'**
  String get parentalGateChallenge;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @pleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get pleaseTryAgain;

  /// No description provided for @purchaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock Full Access'**
  String get purchaseTitle;

  /// No description provided for @purchaseDescription.
  ///
  /// In en, this message translates to:
  /// **'Unlock all games, all levels, and all future updates with a single purchase!'**
  String get purchaseDescription;

  /// No description provided for @purchaseButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock Now!'**
  String get purchaseButton;

  /// No description provided for @contactingStore.
  ///
  /// In en, this message translates to:
  /// **'Reaching the Word Universe...'**
  String get contactingStore;

  /// No description provided for @purchaseError.
  ///
  /// In en, this message translates to:
  /// **'An error occurred. Please check your connection and try again.'**
  String get purchaseError;

  /// No description provided for @restorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchases'**
  String get restorePurchases;

  /// No description provided for @storeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The store is currently unavailable. Please check your connection and that you are signed in to your account.'**
  String get storeUnavailable;

  /// No description provided for @languageChanged.
  ///
  /// In en, this message translates to:
  /// **'Language Changed'**
  String get languageChanged;

  /// No description provided for @languageChangedDesc.
  ///
  /// In en, this message translates to:
  /// **'The app language will change when you restart. Would you like to restart now?'**
  String get languageChangedDesc;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @restartNow.
  ///
  /// In en, this message translates to:
  /// **'Restart Now'**
  String get restartNow;

  /// No description provided for @selectGrade.
  ///
  /// In en, this message translates to:
  /// **'Select Level'**
  String get selectGrade;

  /// No description provided for @gradeN.
  ///
  /// In en, this message translates to:
  /// **'Level {gradeNumber}'**
  String gradeN(int gradeNumber);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @restartToApplyChanges.
  ///
  /// In en, this message translates to:
  /// **'Please restart the app to apply language changes'**
  String get restartToApplyChanges;

  /// No description provided for @resetProgressConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to reset all progress? This action cannot be undone.'**
  String get resetProgressConfirmation;

  /// No description provided for @progressResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Progress reset successfully!'**
  String get progressResetSuccess;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @playToUnlock.
  ///
  /// In en, this message translates to:
  /// **'Play to unlock!'**
  String get playToUnlock;

  /// No description provided for @chooseYourGrade.
  ///
  /// In en, this message translates to:
  /// **'Choose Your Level'**
  String get chooseYourGrade;

  /// No description provided for @grade3Desc.
  ///
  /// In en, this message translates to:
  /// **'Spelling basics, simple nouns and verbs.'**
  String get grade3Desc;

  /// No description provided for @grade4Desc.
  ///
  /// In en, this message translates to:
  /// **'Common words, basic grammar rules, and word types.'**
  String get grade4Desc;

  /// No description provided for @grade5Desc.
  ///
  /// In en, this message translates to:
  /// **'More complex words, cases, and tenses.'**
  String get grade5Desc;

  /// No description provided for @grade6Desc.
  ///
  /// In en, this message translates to:
  /// **'Advanced vocabulary and complex grammar.'**
  String get grade6Desc;

  /// No description provided for @settingsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Settings coming soon!'**
  String get settingsComingSoon;

  /// No description provided for @spaceExplorerProgress.
  ///
  /// In en, this message translates to:
  /// **'Space Explorer Progress'**
  String get spaceExplorerProgress;

  /// No description provided for @unlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get unlocked;

  /// No description provided for @complete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get complete;

  /// No description provided for @rankRookie.
  ///
  /// In en, this message translates to:
  /// **'Rookie'**
  String get rankRookie;

  /// No description provided for @rankExplorer.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get rankExplorer;

  /// No description provided for @rankVeteran.
  ///
  /// In en, this message translates to:
  /// **'Veteran'**
  String get rankVeteran;

  /// No description provided for @rankExpert.
  ///
  /// In en, this message translates to:
  /// **'Expert'**
  String get rankExpert;

  /// No description provided for @rankLegend.
  ///
  /// In en, this message translates to:
  /// **'Legend'**
  String get rankLegend;

  /// No description provided for @achievementFirstCenturyTitle.
  ///
  /// In en, this message translates to:
  /// **'First Century!'**
  String get achievementFirstCenturyTitle;

  /// No description provided for @achievementFirstCenturyDesc.
  ///
  /// In en, this message translates to:
  /// **'Score 100 points'**
  String get achievementFirstCenturyDesc;

  /// No description provided for @achievementScoreMasterTitle.
  ///
  /// In en, this message translates to:
  /// **'Score Master'**
  String get achievementScoreMasterTitle;

  /// No description provided for @achievementScoreMasterDesc.
  ///
  /// In en, this message translates to:
  /// **'Score 500 points'**
  String get achievementScoreMasterDesc;

  /// No description provided for @achievementThousandClubTitle.
  ///
  /// In en, this message translates to:
  /// **'Thousand Club'**
  String get achievementThousandClubTitle;

  /// No description provided for @achievementThousandClubDesc.
  ///
  /// In en, this message translates to:
  /// **'Score 1000 points'**
  String get achievementThousandClubDesc;

  /// No description provided for @achievementLevelExplorerTitle.
  ///
  /// In en, this message translates to:
  /// **'Level Explorer'**
  String get achievementLevelExplorerTitle;

  /// No description provided for @achievementLevelExplorerDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach level 5'**
  String get achievementLevelExplorerDesc;

  /// No description provided for @achievementSpaceCommanderTitle.
  ///
  /// In en, this message translates to:
  /// **'Space Commander'**
  String get achievementSpaceCommanderTitle;

  /// No description provided for @achievementSpaceCommanderDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach level 10'**
  String get achievementSpaceCommanderDesc;

  /// No description provided for @achievementAllRounderTitle.
  ///
  /// In en, this message translates to:
  /// **'All-Rounder'**
  String get achievementAllRounderTitle;

  /// No description provided for @achievementAllRounderDesc.
  ///
  /// In en, this message translates to:
  /// **'Play all game types'**
  String get achievementAllRounderDesc;

  /// No description provided for @achievementSpeedDemonTitle.
  ///
  /// In en, this message translates to:
  /// **'Speed Demon'**
  String get achievementSpeedDemonTitle;

  /// No description provided for @achievementSpeedDemonDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete a level in under 30 seconds'**
  String get achievementSpeedDemonDesc;

  /// No description provided for @achievementPerfectionistTitle.
  ///
  /// In en, this message translates to:
  /// **'Perfectionist'**
  String get achievementPerfectionistTitle;

  /// No description provided for @achievementPerfectionistDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete a level without mistakes'**
  String get achievementPerfectionistDesc;

  /// No description provided for @achievementWordRescuerTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Rescuer'**
  String get achievementWordRescuerTitle;

  /// No description provided for @achievementWordRescuerDesc.
  ///
  /// In en, this message translates to:
  /// **'Rescue 100 words'**
  String get achievementWordRescuerDesc;

  /// No description provided for @unlockedStatus.
  ///
  /// In en, this message translates to:
  /// **'UNLOCKED'**
  String get unlockedStatus;

  /// No description provided for @lockedStatus.
  ///
  /// In en, this message translates to:
  /// **'LOCKED'**
  String get lockedStatus;

  /// No description provided for @achievementUnlocked.
  ///
  /// In en, this message translates to:
  /// **'ACHIEVEMENT UNLOCKED!'**
  String get achievementUnlocked;

  /// No description provided for @continueExploring.
  ///
  /// In en, this message translates to:
  /// **'Continue Exploring'**
  String get continueExploring;

  /// No description provided for @loadingAdventure.
  ///
  /// In en, this message translates to:
  /// **'Loading Word Adventure...'**
  String get loadingAdventure;

  /// No description provided for @preparingMission.
  ///
  /// In en, this message translates to:
  /// **'Preparing your expedition...'**
  String get preparingMission;

  /// No description provided for @initializing.
  ///
  /// In en, this message translates to:
  /// **'Initializing the Word Universe...'**
  String get initializing;

  /// No description provided for @loadingAssets.
  ///
  /// In en, this message translates to:
  /// **'Loading game assets...'**
  String get loadingAssets;

  /// No description provided for @loadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Loading saved progress...'**
  String get loadingProgress;

  /// No description provided for @preparingSpaceStation.
  ///
  /// In en, this message translates to:
  /// **'Preparing the Word Universe...'**
  String get preparingSpaceStation;

  /// No description provided for @calibratingNav.
  ///
  /// In en, this message translates to:
  /// **'Calibrating navigation systems...'**
  String get calibratingNav;

  /// No description provided for @readyForLaunch.
  ///
  /// In en, this message translates to:
  /// **'Ready for launch!'**
  String get readyForLaunch;

  /// No description provided for @launch.
  ///
  /// In en, this message translates to:
  /// **'Launch'**
  String get launch;

  /// No description provided for @splashScreenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Explore • Learn • Discover'**
  String get splashScreenSubtitle;

  /// No description provided for @sriStatisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning Insights'**
  String get sriStatisticsTitle;

  /// No description provided for @sriStatisticsDesc.
  ///
  /// In en, this message translates to:
  /// **'View your progress and identify areas for improvement.'**
  String get sriStatisticsDesc;

  /// No description provided for @premiumFeature.
  ///
  /// In en, this message translates to:
  /// **'This is a premium feature. Unlock the full version to access.'**
  String get premiumFeature;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @sriMastery.
  ///
  /// In en, this message translates to:
  /// **'Overall Mastery'**
  String get sriMastery;

  /// No description provided for @sriTotal.
  ///
  /// In en, this message translates to:
  /// **'Total Tracked'**
  String get sriTotal;

  /// No description provided for @sriMastered.
  ///
  /// In en, this message translates to:
  /// **'Mastered'**
  String get sriMastered;

  /// No description provided for @sriLearning.
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get sriLearning;

  /// No description provided for @progressMatrixTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress Matrix'**
  String get progressMatrixTitle;

  /// No description provided for @progressMatrixDesc.
  ///
  /// In en, this message translates to:
  /// **'Color shows mastery (green is best). Number shows problems tracked in that area.'**
  String get progressMatrixDesc;

  /// No description provided for @imprint.
  ///
  /// In en, this message translates to:
  /// **'Imprint / Legal'**
  String get imprint;

  /// No description provided for @imprintTitle.
  ///
  /// In en, this message translates to:
  /// **'Imprint / Legal.'**
  String get imprintTitle;

  /// No description provided for @imprintDialog.
  ///
  /// In en, this message translates to:
  /// **'Imprint / Legal..'**
  String get imprintDialog;

  /// No description provided for @viewLegalNotice.
  ///
  /// In en, this message translates to:
  /// **'Info about the Service Provider...'**
  String get viewLegalNotice;

  /// No description provided for @imprintServiceProvider.
  ///
  /// In en, this message translates to:
  /// **'Service Provider'**
  String get imprintServiceProvider;

  /// No description provided for @imprintProviderAddress.
  ///
  /// In en, this message translates to:
  /// **'Christian Ströbele\nNikolausstr. 5\n70190 Stuttgart\nDeutschland/Germany'**
  String get imprintProviderAddress;

  /// No description provided for @imprintContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get imprintContact;

  /// No description provided for @imprintContactDetails.
  ///
  /// In en, this message translates to:
  /// **'Email: postmaster@crispstro.be\nPhone: 0049 176 6421 8601'**
  String get imprintContactDetails;

  /// No description provided for @imprintContentResponsible.
  ///
  /// In en, this message translates to:
  /// **'Responsible for Content'**
  String get imprintContentResponsible;

  /// No description provided for @imprintDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Disclaimer'**
  String get imprintDisclaimer;

  /// No description provided for @imprintDisclaimerText.
  ///
  /// In en, this message translates to:
  /// **'This app is provided as is, exclusively for educational and creative purposes, without any liability.'**
  String get imprintDisclaimerText;

  /// No description provided for @imprintWebsite.
  ///
  /// In en, this message translates to:
  /// **'www.crispstro.be'**
  String get imprintWebsite;

  /// Title for the task customization settings card
  ///
  /// In en, this message translates to:
  /// **'Task Customization'**
  String get taskCustomizationTitle;

  /// Label for the toggle switch to enable task customization
  ///
  /// In en, this message translates to:
  /// **'Enable Customization'**
  String get taskCustomizationEnable;

  /// Description for the enable toggle
  ///
  /// In en, this message translates to:
  /// **'Filter vocabulary for exercises'**
  String get taskCustomizationEnableDesc;

  /// Title for the word length range slider
  ///
  /// In en, this message translates to:
  /// **'Word Length'**
  String get taskWordLengthTitle;

  /// Label showing the selected min/max word length. e.g. 'Words with 3 to 8 letters'
  ///
  /// In en, this message translates to:
  /// **'Words with {min} to {max} letters'**
  String taskWordLengthRange(int min, int max);

  /// Title for the included sources section
  ///
  /// In en, this message translates to:
  /// **'Word Sources'**
  String get taskIncludedSourcesTitle;

  /// Description for the source selection. (empty = all)
  ///
  /// In en, this message translates to:
  /// **'Only show words from selected sources (empty = all)'**
  String get taskIncludedSourcesDesc;

  /// Title for the include wildcard filter section
  ///
  /// In en, this message translates to:
  /// **'Wildcard Filters (Include)'**
  String get taskWildcardIncludeTitle;

  /// Description for include wildcards
  ///
  /// In en, this message translates to:
  /// **'Only show words that match (e.g. *ing)'**
  String get taskWildcardIncludeDesc;

  /// Title for the exclude wildcard filter section
  ///
  /// In en, this message translates to:
  /// **'Wildcard Filters (Exclude)'**
  String get taskWildcardExcludeTitle;

  /// Description for exclude wildcards
  ///
  /// In en, this message translates to:
  /// **'Hide words that match (e.g. un*)'**
  String get taskWildcardExcludeDesc;

  /// Hint text for the text field to add a new wildcard
  ///
  /// In en, this message translates to:
  /// **'Add new filter...'**
  String get taskWildcardHint;

  /// A warning message shown elsewhere in the app if filters are active
  ///
  /// In en, this message translates to:
  /// **'Filters active! Vocabulary is limited.'**
  String get taskCustomizationWarning;

  /// No description provided for @taskActiveSetTitle.
  ///
  /// In en, this message translates to:
  /// **'Active Vocabulary Set'**
  String get taskActiveSetTitle;

  /// No description provided for @taskActiveSetDesc.
  ///
  /// In en, this message translates to:
  /// **'Overrides all other filters when active.'**
  String get taskActiveSetDesc;

  /// No description provided for @taskActiveSetNone.
  ///
  /// In en, this message translates to:
  /// **'None (Use filters below)'**
  String get taskActiveSetNone;

  /// No description provided for @taskManageSets.
  ///
  /// In en, this message translates to:
  /// **'Manage Custom Sets'**
  String get taskManageSets;

  /// No description provided for @taskFiltersDisabled.
  ///
  /// In en, this message translates to:
  /// **'The filters below are disabled because a custom set is active.'**
  String get taskFiltersDisabled;

  /// No description provided for @customSetCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create New Set'**
  String get customSetCreateTitle;

  /// No description provided for @customSetEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Set'**
  String get customSetEditTitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @customSetNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Set Name'**
  String get customSetNameLabel;

  /// No description provided for @customSetNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., \'Tricky Verbs\''**
  String get customSetNameHint;

  /// No description provided for @customSetDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get customSetDescriptionLabel;

  /// No description provided for @customSetDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'A short description of this set...'**
  String get customSetDescriptionHint;

  /// No description provided for @customSetTargetGrade.
  ///
  /// In en, this message translates to:
  /// **'Target Grade'**
  String get customSetTargetGrade;

  /// No description provided for @customSetAvailableWords.
  ///
  /// In en, this message translates to:
  /// **'Available Words'**
  String get customSetAvailableWords;

  /// No description provided for @customSetSelectedWords.
  ///
  /// In en, this message translates to:
  /// **'Selected Words ({count})'**
  String customSetSelectedWords(int count);

  /// No description provided for @customSetSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Filter words...'**
  String get customSetSearchHint;

  /// No description provided for @customSetAddAll.
  ///
  /// In en, this message translates to:
  /// **'Add All'**
  String get customSetAddAll;

  /// No description provided for @customSetRemoveAll.
  ///
  /// In en, this message translates to:
  /// **'Remove All'**
  String get customSetRemoveAll;

  /// No description provided for @customSetEmpty.
  ///
  /// In en, this message translates to:
  /// **'No words selected yet.'**
  String get customSetEmpty;

  /// No description provided for @customSetNoAvailable.
  ///
  /// In en, this message translates to:
  /// **'No matching words found.'**
  String get customSetNoAvailable;

  /// No description provided for @customSetDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Set'**
  String get customSetDelete;

  /// No description provided for @customSetDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Set?'**
  String get customSetDeleteConfirmTitle;

  /// No description provided for @customSetDeleteConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {setName}?'**
  String customSetDeleteConfirmContent(String setName);

  /// Description for memory game in menu
  ///
  /// In en, this message translates to:
  /// **'Find matching word pairs in different fonts'**
  String get wordMemoryDescription;

  /// Description for word builder game in menu
  ///
  /// In en, this message translates to:
  /// **'Build words from scrambled letters'**
  String get wordBuilderDescription;

  /// Description for word whirl game in menu
  ///
  /// In en, this message translates to:
  /// **'Tap the correct word types in the whirl!'**
  String get wordWhirlDescription;

  /// Title for memory matching game
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get wordMemoryTitle;

  /// Memory game completion message
  ///
  /// In en, this message translates to:
  /// **'Complete!'**
  String get wordMemoryComplete;

  /// Score label
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get wordMemoryScore;

  /// Number of moves made
  ///
  /// In en, this message translates to:
  /// **'Moves'**
  String get wordMemoryMoves;

  /// Number of pairs found
  ///
  /// In en, this message translates to:
  /// **'Pairs'**
  String get wordMemoryPairs;

  /// Title for word builder game
  ///
  /// In en, this message translates to:
  /// **'Word Builder'**
  String get wordBuilderTitle;

  /// Game over message
  ///
  /// In en, this message translates to:
  /// **'Game Over!'**
  String get wordBuilderGameOver;

  /// Words completed label
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get wordBuilderWords;

  /// Time bonus label
  ///
  /// In en, this message translates to:
  /// **'Time Bonus'**
  String get wordBuilderTimeBonus;

  /// Instruction to build the word
  ///
  /// In en, this message translates to:
  /// **'Build the word:'**
  String get wordBuilderBuildWord;

  /// Letters pool label
  ///
  /// In en, this message translates to:
  /// **'Letters:'**
  String get wordBuilderLetters;

  /// Hint button text
  ///
  /// In en, this message translates to:
  /// **'Hint (-10)'**
  String get wordBuilderHint;

  /// Skip button text
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get wordBuilderSkip;

  /// Time label
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get wordBuilderTime;

  /// Title for word type whirl game
  ///
  /// In en, this message translates to:
  /// **'Word Type Whirl'**
  String get wordWhirlTitle;

  /// Whirl game over message
  ///
  /// In en, this message translates to:
  /// **'Whirl Complete!'**
  String get wordWhirlGameOver;

  /// Accuracy percentage
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get wordWhirlAccuracy;

  /// Best streak achieved
  ///
  /// In en, this message translates to:
  /// **'Best Streak'**
  String get wordWhirlBestStreak;

  /// Correct taps label
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get wordWhirlCorrect;

  /// Incorrect taps label
  ///
  /// In en, this message translates to:
  /// **'Incorrect'**
  String get wordWhirlIncorrect;

  /// Current streak label
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get wordWhirlStreak;

  /// Round number label
  ///
  /// In en, this message translates to:
  /// **'Round'**
  String get wordWhirlRound;

  /// Instruction to tap all words of a type
  ///
  /// In en, this message translates to:
  /// **'Tap all {wordType}!'**
  String wordWhirlTapAll(String wordType);

  /// Replay button text
  ///
  /// In en, this message translates to:
  /// **'Play Again'**
  String get gameReplay;

  /// Done/Exit button text
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get gameDone;

  /// Score label used across games
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get gameScore;

  /// Difficulty picker — easy mode (grade - 1)
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get difficultyEasy;

  /// Difficulty picker — normal mode (player's grade)
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get difficultyNormal;

  /// Difficulty picker — challenge mode (grade + 1)
  ///
  /// In en, this message translates to:
  /// **'Challenge'**
  String get difficultyChallenge;

  /// Plural label for consecutive-day streak
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String streakLabel(int count);

  /// Feedback when a falling/timed item is missed
  ///
  /// In en, this message translates to:
  /// **'Too slow!'**
  String get gameTooSlow;

  /// Stat line shown in end-of-game dialog
  ///
  /// In en, this message translates to:
  /// **'Level: {level}'**
  String gameLevelLine(int level);

  /// Stat line shown in end-of-game dialog
  ///
  /// In en, this message translates to:
  /// **'Max Combo: {combo}'**
  String gameMaxComboLine(int combo);

  /// No description provided for @gameCombo.
  ///
  /// In en, this message translates to:
  /// **'Combo x{combo}'**
  String gameCombo(int combo);

  /// No description provided for @gameLvlBadge.
  ///
  /// In en, this message translates to:
  /// **'Lvl {level}'**
  String gameLvlBadge(int level);

  /// No description provided for @verbtrennerSeparableTitle.
  ///
  /// In en, this message translates to:
  /// **'Separable Verbs'**
  String get verbtrennerSeparableTitle;

  /// No description provided for @verbtrennerCompoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Noun Compounds'**
  String get verbtrennerCompoundTitle;

  /// No description provided for @verbtrennerSeparatedLabel.
  ///
  /// In en, this message translates to:
  /// **'SEPARATED'**
  String get verbtrennerSeparatedLabel;

  /// No description provided for @verbtrennerSeparatedExample.
  ///
  /// In en, this message translates to:
  /// **'(stehe auf)'**
  String get verbtrennerSeparatedExample;

  /// No description provided for @verbtrennerTogetherLabel.
  ///
  /// In en, this message translates to:
  /// **'TOGETHER'**
  String get verbtrennerTogetherLabel;

  /// No description provided for @verbtrennerTogetherExample.
  ///
  /// In en, this message translates to:
  /// **'(aufstehen)'**
  String get verbtrennerTogetherExample;

  /// No description provided for @wortbaumeisterSeparatedExample.
  ///
  /// In en, this message translates to:
  /// **'(e.g. stehe auf)'**
  String get wortbaumeisterSeparatedExample;

  /// No description provided for @wortbaumeisterTogetherExample.
  ///
  /// In en, this message translates to:
  /// **'(e.g. aufstehen)'**
  String get wortbaumeisterTogetherExample;

  /// No description provided for @grossschreibTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Galaxy'**
  String get grossschreibTitle;

  /// No description provided for @grossschreibDescription.
  ///
  /// In en, this message translates to:
  /// **'Are words in a sentence capitalised or not?'**
  String get grossschreibDescription;

  /// No description provided for @grossschreibClickHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the word!'**
  String get grossschreibClickHint;

  /// No description provided for @grossschreibCheck.
  ///
  /// In en, this message translates to:
  /// **'CHECK'**
  String get grossschreibCheck;

  /// No description provided for @grossstadtTitle.
  ///
  /// In en, this message translates to:
  /// **'Upper or lower case?'**
  String get grossstadtTitle;

  /// No description provided for @grossstadtCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Noun Sorter'**
  String get grossstadtCardTitle;

  /// No description provided for @grossstadtCardDescription.
  ///
  /// In en, this message translates to:
  /// **'Sorting words by capitalisation on the conveyor belt'**
  String get grossstadtCardDescription;

  /// No description provided for @grossstadtCapital.
  ///
  /// In en, this message translates to:
  /// **'UPPER'**
  String get grossstadtCapital;

  /// No description provided for @grossstadtLower.
  ///
  /// In en, this message translates to:
  /// **'lower'**
  String get grossstadtLower;

  /// No description provided for @spellingSpotterTitle.
  ///
  /// In en, this message translates to:
  /// **'Spelling Spotter'**
  String get spellingSpotterTitle;

  /// No description provided for @spellingSpotterDescription.
  ///
  /// In en, this message translates to:
  /// **'Spot the correctly spelled word — learn common spelling mistakes'**
  String get spellingSpotterDescription;

  /// No description provided for @sentenceCompletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Sentence Completion'**
  String get sentenceCompletionTitle;

  /// No description provided for @sentenceCompletionDescription.
  ///
  /// In en, this message translates to:
  /// **'Fill in the missing word — practise vocabulary in context'**
  String get sentenceCompletionDescription;

  /// No description provided for @definitionQuizTitle.
  ///
  /// In en, this message translates to:
  /// **'Definition Quiz'**
  String get definitionQuizTitle;

  /// No description provided for @definitionQuizDescription.
  ///
  /// In en, this message translates to:
  /// **'Match the definition to the correct word'**
  String get definitionQuizDescription;

  /// No description provided for @sriReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Weak Words'**
  String get sriReviewTitle;

  /// No description provided for @sriReviewDescription.
  ///
  /// In en, this message translates to:
  /// **'Practice your toughest words, ranked by difficulty'**
  String get sriReviewDescription;

  /// No description provided for @antonymFlashTitle.
  ///
  /// In en, this message translates to:
  /// **'Antonym Flash'**
  String get antonymFlashTitle;

  /// No description provided for @antonymFlashDescription.
  ///
  /// In en, this message translates to:
  /// **'Tap the opposite — as fast as you can!'**
  String get antonymFlashDescription;

  /// No description provided for @wortbaumeisterCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Wort-Stückler'**
  String get wortbaumeisterCardTitle;

  /// No description provided for @wortbaumeisterCardDescription.
  ///
  /// In en, this message translates to:
  /// **'Build compound nouns piece by piece'**
  String get wortbaumeisterCardDescription;

  /// No description provided for @verbtrennerCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Verb-Trenner'**
  String get verbtrennerCardTitle;

  /// No description provided for @verbtrennerCardDescription.
  ///
  /// In en, this message translates to:
  /// **'Recognise separable verbs: together or apart?'**
  String get verbtrennerCardDescription;

  /// No description provided for @achievementsBannerProgress.
  ///
  /// In en, this message translates to:
  /// **'{unlocked} of {total} achievements unlocked'**
  String achievementsBannerProgress(int unlocked, int total);

  /// No description provided for @achievementTriangleWizardTitle.
  ///
  /// In en, this message translates to:
  /// **'Word-Snake Master'**
  String get achievementTriangleWizardTitle;

  /// No description provided for @achievementTriangleWizardDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach Level 3 in Word Snake.'**
  String get achievementTriangleWizardDesc;

  /// No description provided for @achievementBubblePopperTitle.
  ///
  /// In en, this message translates to:
  /// **'Sorting Champion'**
  String get achievementBubblePopperTitle;

  /// No description provided for @achievementBubblePopperDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach Level 3 in Word Sort.'**
  String get achievementBubblePopperDesc;

  /// No description provided for @achievementPuzzleSolverTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Finder'**
  String get achievementPuzzleSolverTitle;

  /// No description provided for @achievementPuzzleSolverDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach Level 3 in Word Find.'**
  String get achievementPuzzleSolverDesc;

  /// No description provided for @achievementNumberWallsProTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Builder'**
  String get achievementNumberWallsProTitle;

  /// No description provided for @achievementNumberWallsProDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach Level 3 in Word Builder.'**
  String get achievementNumberWallsProDesc;

  /// No description provided for @achievementCodebreakerProTitle.
  ///
  /// In en, this message translates to:
  /// **'Space Rescuer'**
  String get achievementCodebreakerProTitle;

  /// No description provided for @achievementCodebreakerProDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach Level 3 in Space Word Rescue.'**
  String get achievementCodebreakerProDesc;

  /// No description provided for @achievementMasterBuilderTitle.
  ///
  /// In en, this message translates to:
  /// **'Master Builder'**
  String get achievementMasterBuilderTitle;

  /// No description provided for @achievementMasterBuilderDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach Level 3 in Wortbaumeister.'**
  String get achievementMasterBuilderDesc;

  /// No description provided for @achievementCityPlannerTitle.
  ///
  /// In en, this message translates to:
  /// **'City Planner'**
  String get achievementCityPlannerTitle;

  /// No description provided for @achievementCityPlannerDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach Level 3 in Word Sorter.'**
  String get achievementCityPlannerDesc;

  /// No description provided for @achievementConnectionExpertTitle.
  ///
  /// In en, this message translates to:
  /// **'Galaxy Expert'**
  String get achievementConnectionExpertTitle;

  /// No description provided for @achievementConnectionExpertDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach Level 3 in Word Galaxy.'**
  String get achievementConnectionExpertDesc;

  /// No description provided for @achievementArithmeticAceTitle.
  ///
  /// In en, this message translates to:
  /// **'Memory Ace'**
  String get achievementArithmeticAceTitle;

  /// No description provided for @achievementArithmeticAceDesc.
  ///
  /// In en, this message translates to:
  /// **'Reach Level 5 in Memory and Word Whirl.'**
  String get achievementArithmeticAceDesc;

  /// No description provided for @achievementVielseitigTitle.
  ///
  /// In en, this message translates to:
  /// **'Versatile'**
  String get achievementVielseitigTitle;

  /// No description provided for @achievementVielseitigDesc.
  ///
  /// In en, this message translates to:
  /// **'Play at least four different games.'**
  String get achievementVielseitigDesc;

  /// No description provided for @parentDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent Overview'**
  String get parentDashboardTitle;

  /// No description provided for @parentPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent PIN'**
  String get parentPinTitle;

  /// No description provided for @parentPinHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter the 4-digit code.\nDefault is {pin} until you change it.'**
  String parentPinHelp(String pin);

  /// No description provided for @parentPinWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong code'**
  String get parentPinWrong;

  /// No description provided for @parentPinUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get parentPinUnlock;

  /// No description provided for @parentChangePin.
  ///
  /// In en, this message translates to:
  /// **'Change parent PIN'**
  String get parentChangePin;

  /// No description provided for @parentChangePinDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get parentChangePinDialogTitle;

  /// No description provided for @parentNewPinLabel.
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get parentNewPinLabel;

  /// No description provided for @parentConfirmPinLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get parentConfirmPinLabel;

  /// No description provided for @parentPinRequireFour.
  ///
  /// In en, this message translates to:
  /// **'4 digits required'**
  String get parentPinRequireFour;

  /// No description provided for @parentPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'Does not match'**
  String get parentPinMismatch;

  /// No description provided for @parentPinUpdated.
  ///
  /// In en, this message translates to:
  /// **'PIN updated'**
  String get parentPinUpdated;

  /// No description provided for @parentSectionLanguageMastery.
  ///
  /// In en, this message translates to:
  /// **'Language mastery'**
  String get parentSectionLanguageMastery;

  /// No description provided for @parentItemsTracked.
  ///
  /// In en, this message translates to:
  /// **'Items tracked'**
  String get parentItemsTracked;

  /// No description provided for @parentItemsMastered.
  ///
  /// In en, this message translates to:
  /// **'Of these mastered'**
  String get parentItemsMastered;

  /// No description provided for @parentItemsMasteredValue.
  ///
  /// In en, this message translates to:
  /// **'{count} ({pct}%)'**
  String parentItemsMasteredValue(int count, int pct);

  /// No description provided for @parentItemsDue.
  ///
  /// In en, this message translates to:
  /// **'Due for review'**
  String get parentItemsDue;

  /// No description provided for @parentSectionStrengths.
  ///
  /// In en, this message translates to:
  /// **'Strengths & weaknesses'**
  String get parentSectionStrengths;

  /// No description provided for @parentDataBasis.
  ///
  /// In en, this message translates to:
  /// **'Data basis'**
  String get parentDataBasis;

  /// No description provided for @parentNoDataYet.
  ///
  /// In en, this message translates to:
  /// **'no data yet'**
  String get parentNoDataYet;

  /// No description provided for @parentStrongestCategory.
  ///
  /// In en, this message translates to:
  /// **'Strongest category'**
  String get parentStrongestCategory;

  /// No description provided for @parentWeakestCategory.
  ///
  /// In en, this message translates to:
  /// **'Weakest category'**
  String get parentWeakestCategory;

  /// No description provided for @parentCategoryValue.
  ///
  /// In en, this message translates to:
  /// **'{name} ({pct}%)'**
  String parentCategoryValue(String name, int pct);

  /// No description provided for @parentTotalAttempts.
  ///
  /// In en, this message translates to:
  /// **'Total attempts'**
  String get parentTotalAttempts;

  /// No description provided for @parentSectionGameProgress.
  ///
  /// In en, this message translates to:
  /// **'Game progress'**
  String get parentSectionGameProgress;

  /// No description provided for @parentGamesPlayed.
  ///
  /// In en, this message translates to:
  /// **'Games played'**
  String get parentGamesPlayed;

  /// No description provided for @parentNoneYet.
  ///
  /// In en, this message translates to:
  /// **'none yet'**
  String get parentNoneYet;

  /// No description provided for @parentLevelValue.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String parentLevelValue(int level);

  /// No description provided for @cognitiveProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning profile'**
  String get cognitiveProfileTitle;

  /// No description provided for @cognitiveProfileEmpty.
  ///
  /// In en, this message translates to:
  /// **'Play a few rounds to build up your profile.'**
  String get cognitiveProfileEmpty;

  /// No description provided for @cognitiveProfileAttempts.
  ///
  /// In en, this message translates to:
  /// **'{attempts} attempts in {areas, plural, =1{1 skill area} other{{areas} skill areas}}'**
  String cognitiveProfileAttempts(int attempts, int areas);

  /// No description provided for @categorySpelling.
  ///
  /// In en, this message translates to:
  /// **'Spelling'**
  String get categorySpelling;

  /// No description provided for @categoryGrammar.
  ///
  /// In en, this message translates to:
  /// **'Grammar'**
  String get categoryGrammar;

  /// No description provided for @categoryVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary'**
  String get categoryVocabulary;

  /// No description provided for @categoryTextComprehension.
  ///
  /// In en, this message translates to:
  /// **'Reading comprehension'**
  String get categoryTextComprehension;

  /// No description provided for @categoryExpression.
  ///
  /// In en, this message translates to:
  /// **'Expression'**
  String get categoryExpression;

  /// No description provided for @wordSortOnboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Sort'**
  String get wordSortOnboardingTitle;

  /// No description provided for @wordSortOnboardingDrag.
  ///
  /// In en, this message translates to:
  /// **'Drag the word to the matching word-type category.'**
  String get wordSortOnboardingDrag;

  /// No description provided for @wordSortOnboardingBuildingBlocks.
  ///
  /// In en, this message translates to:
  /// **'Nouns, verbs and adjectives are the building blocks. Higher grades add adverbs and pronouns.'**
  String get wordSortOnboardingBuildingBlocks;

  /// No description provided for @wordSortOnboardingHints.
  ///
  /// In en, this message translates to:
  /// **'Need help? Wait a moment — the game will show hints for the current word after a short delay.'**
  String get wordSortOnboardingHints;

  /// No description provided for @wordSortCategoryAdverb.
  ///
  /// In en, this message translates to:
  /// **'Adverbs'**
  String get wordSortCategoryAdverb;

  /// No description provided for @wordSortCategoryPronoun.
  ///
  /// In en, this message translates to:
  /// **'Pronouns'**
  String get wordSortCategoryPronoun;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return SDe();
    case 'en':
      return SEn();
  }

  throw FlutterError(
      'S.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
