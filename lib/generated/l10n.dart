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

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your learning'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Choose what you want to practise. You can change everything later in Settings.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingLearningLanguage.
  ///
  /// In en, this message translates to:
  /// **'What do you want to learn?'**
  String get onboardingLearningLanguage;

  /// No description provided for @onboardingGoal.
  ///
  /// In en, this message translates to:
  /// **'What should practice focus on?'**
  String get onboardingGoal;

  /// No description provided for @onboardingStartBand.
  ///
  /// In en, this message translates to:
  /// **'Choose a starting vocabulary band'**
  String get onboardingStartBand;

  /// No description provided for @onboardingDailyTime.
  ///
  /// In en, this message translates to:
  /// **'Daily practice time'**
  String get onboardingDailyTime;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Prepare my learning plan'**
  String get onboardingContinue;

  /// No description provided for @goalBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get goalBalanced;

  /// No description provided for @goalVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary'**
  String get goalVocabulary;

  /// No description provided for @goalSpelling.
  ///
  /// In en, this message translates to:
  /// **'Spelling'**
  String get goalSpelling;

  /// No description provided for @goalGrammar.
  ///
  /// In en, this message translates to:
  /// **'Grammar'**
  String get goalGrammar;

  /// No description provided for @goalDafDaz.
  ///
  /// In en, this message translates to:
  /// **'German as a foreign language'**
  String get goalDafDaz;

  /// No description provided for @dailySessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Today’s learning plan'**
  String get dailySessionTitle;

  /// No description provided for @dailySessionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A focused session of about {minutes} minutes'**
  String dailySessionSubtitle(int minutes);

  /// No description provided for @dailyReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review due words'**
  String get dailyReviewTitle;

  /// No description provided for @dailyReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} words are ready for review'**
  String dailyReviewSubtitle(int count);

  /// No description provided for @dailyWarmupTitle.
  ///
  /// In en, this message translates to:
  /// **'Context warm-up'**
  String get dailyWarmupTitle;

  /// No description provided for @dailyWarmupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start with a short sentence exercise'**
  String get dailyWarmupSubtitle;

  /// No description provided for @dailyGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Practise your main goal'**
  String get dailyGoalTitle;

  /// No description provided for @dailyGoalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An exercise selected from your learning goal'**
  String get dailyGoalSubtitle;

  /// No description provided for @dailyContextTitle.
  ///
  /// In en, this message translates to:
  /// **'Use words in context'**
  String get dailyContextTitle;

  /// No description provided for @dailyContextSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Finish with a sentence-completion challenge'**
  String get dailyContextSubtitle;

  /// No description provided for @dailyCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan complete'**
  String get dailyCompleteTitle;

  /// No description provided for @dailyCompleteSummary.
  ///
  /// In en, this message translates to:
  /// **'You answered {attempts} tracked items and mastered {mastered} new items during this plan.'**
  String dailyCompleteSummary(int attempts, int mastered);

  /// No description provided for @dailyPractiseMore.
  ///
  /// In en, this message translates to:
  /// **'Practise more'**
  String get dailyPractiseMore;

  /// No description provided for @browseAllGames.
  ///
  /// In en, this message translates to:
  /// **'Browse all games'**
  String get browseAllGames;

  /// No description provided for @focusMode.
  ///
  /// In en, this message translates to:
  /// **'Focus mode'**
  String get focusMode;

  /// No description provided for @focusModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Reduce decorative elements and keep learning actions prominent'**
  String get focusModeDesc;

  /// No description provided for @catalogRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get catalogRecommended;

  /// No description provided for @catalogFast.
  ///
  /// In en, this message translates to:
  /// **'Quick practice'**
  String get catalogFast;

  /// No description provided for @catalogFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get catalogFavorites;

  /// No description provided for @catalogRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get catalogRecent;

  /// No description provided for @catalogAll.
  ///
  /// In en, this message translates to:
  /// **'All games'**
  String get catalogAll;

  /// No description provided for @catalogSearch.
  ///
  /// In en, this message translates to:
  /// **'Search games'**
  String get catalogSearch;

  /// No description provided for @catalogAddFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get catalogAddFavorite;

  /// No description provided for @catalogRemoveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get catalogRemoveFavorite;

  /// No description provided for @catalogNoGames.
  ///
  /// In en, this message translates to:
  /// **'No games match this view yet.'**
  String get catalogNoGames;

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

  /// No description provided for @downloadDbTitle.
  ///
  /// In en, this message translates to:
  /// **'First-time setup'**
  String get downloadDbTitle;

  /// No description provided for @downloadDbMessage.
  ///
  /// In en, this message translates to:
  /// **'The German word database (about {size}) will be downloaded once and saved on your device for offline use.'**
  String downloadDbMessage(String size);

  /// No description provided for @downloadDbConfirm.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadDbConfirm;

  /// No description provided for @downloadDbCancel.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get downloadDbCancel;

  /// No description provided for @downloadDbDeclined.
  ///
  /// In en, this message translates to:
  /// **'The German word database is needed to continue. Tap Retry to download it, or switch to English in Settings.'**
  String get downloadDbDeclined;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Word Universe'**
  String get appName;

  /// No description provided for @appLegalese.
  ///
  /// In en, this message translates to:
  /// **'© 2025–2026 CrispStrobe\n\nGerman vocabulary database licensed under GPL-3.0 (it includes data derived from childLex); English vocabulary database under CC BY-SA 4.0. Sources: Wiktionary, ConceptNet, OEWN, OpenThesaurus, OdeNet, LiTKey, Tatoeba, Project Gutenberg, childLex, and others. Full attribution in the license entries below.\n\nDatasets: huggingface.co/datasets/cstr/grundwortschatz-voc-de  ·  cstr/grundwortschatz-voc-en\n\nApp code is proprietary.'**
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
  /// **'correct'**
  String get correct;

  /// No description provided for @gameOver.
  ///
  /// In en, this message translates to:
  /// **'Game Over'**
  String get gameOver;

  /// No description provided for @backToMenu.
  ///
  /// In en, this message translates to:
  /// **'Back to Menu'**
  String get backToMenu;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

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
  /// **'Everyday words and spelling basics'**
  String get difficultyDescGrade3;

  /// No description provided for @difficultyDescGrade4.
  ///
  /// In en, this message translates to:
  /// **'Broader vocabulary and basic grammar'**
  String get difficultyDescGrade4;

  /// No description provided for @difficultyDescGrade5.
  ///
  /// In en, this message translates to:
  /// **'Advanced words, cases, and tenses'**
  String get difficultyDescGrade5;

  /// No description provided for @difficultyDescGrade6.
  ///
  /// In en, this message translates to:
  /// **'Challenging vocabulary and complex grammar'**
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
  /// **'Who It’s For'**
  String get targetAge;

  /// No description provided for @targetAgeRange.
  ///
  /// In en, this message translates to:
  /// **'German and English learners of different ages'**
  String get targetAgeRange;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'Word Universe helps learners practise vocabulary, spelling, and grammar through engaging space-themed games.'**
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
  /// **'Quick Check'**
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
  /// **'Target Level'**
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

  /// No description provided for @synonymFlashTitle.
  ///
  /// In en, this message translates to:
  /// **'Synonym Flash'**
  String get synonymFlashTitle;

  /// No description provided for @synonymFlashDescription.
  ///
  /// In en, this message translates to:
  /// **'Tap a word with the same meaning — as fast as you can!'**
  String get synonymFlashDescription;

  /// No description provided for @translationFlashTitle.
  ///
  /// In en, this message translates to:
  /// **'Translation Flash'**
  String get translationFlashTitle;

  /// No description provided for @translationFlashDescription.
  ///
  /// In en, this message translates to:
  /// **'Tap the English translation of each German word!'**
  String get translationFlashDescription;

  /// No description provided for @syllableCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Syllable Count'**
  String get syllableCountTitle;

  /// No description provided for @syllableCountDescription.
  ///
  /// In en, this message translates to:
  /// **'How many syllables does the word have? Count them!'**
  String get syllableCountDescription;

  /// No description provided for @clozeFlashTitle.
  ///
  /// In en, this message translates to:
  /// **'Cloze Flash'**
  String get clozeFlashTitle;

  /// No description provided for @clozeFlashDescription.
  ///
  /// In en, this message translates to:
  /// **'Fill in the blank — pick the right word for each sentence!'**
  String get clozeFlashDescription;

  /// No description provided for @expressionFlashTitle.
  ///
  /// In en, this message translates to:
  /// **'Expression Flash'**
  String get expressionFlashTitle;

  /// No description provided for @expressionFlashDescription.
  ///
  /// In en, this message translates to:
  /// **'Complete the German idiom — tap the missing word!'**
  String get expressionFlashDescription;

  /// No description provided for @hypernymFlashTitle.
  ///
  /// In en, this message translates to:
  /// **'Category Flash'**
  String get hypernymFlashTitle;

  /// No description provided for @hypernymFlashDescription.
  ///
  /// In en, this message translates to:
  /// **'Which category does the word belong to?'**
  String get hypernymFlashDescription;

  /// No description provided for @wordClassFlashTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Class Flash'**
  String get wordClassFlashTitle;

  /// No description provided for @wordClassFlashDescription.
  ///
  /// In en, this message translates to:
  /// **'Noun, Verb, Adjective or Adverb — pick fast!'**
  String get wordClassFlashDescription;

  /// No description provided for @proverbClozeTitle.
  ///
  /// In en, this message translates to:
  /// **'Proverb Cloze'**
  String get proverbClozeTitle;

  /// No description provided for @proverbClozeDescription.
  ///
  /// In en, this message translates to:
  /// **'Complete the German proverb — tap the missing word!'**
  String get proverbClozeDescription;

  /// No description provided for @reverseTranslationTitle.
  ///
  /// In en, this message translates to:
  /// **'Reverse Translation'**
  String get reverseTranslationTitle;

  /// No description provided for @reverseTranslationDescription.
  ///
  /// In en, this message translates to:
  /// **'An English word appears — find the German word!'**
  String get reverseTranslationDescription;

  /// No description provided for @conjugationDrillTitle.
  ///
  /// In en, this message translates to:
  /// **'Conjugation Drill'**
  String get conjugationDrillTitle;

  /// No description provided for @conjugationDrillDescription.
  ///
  /// In en, this message translates to:
  /// **'Pick the right verb form for each pronoun'**
  String get conjugationDrillDescription;

  /// No description provided for @conjugationDrillGameOverTitle.
  ///
  /// In en, this message translates to:
  /// **'Exercise complete'**
  String get conjugationDrillGameOverTitle;

  /// No description provided for @conjugationDrillGameOverLabel.
  ///
  /// In en, this message translates to:
  /// **'correct conjugations'**
  String get conjugationDrillGameOverLabel;

  /// No description provided for @homophoneDrillTitle.
  ///
  /// In en, this message translates to:
  /// **'Homophone Drill'**
  String get homophoneDrillTitle;

  /// No description provided for @homophoneDrillDescription.
  ///
  /// In en, this message translates to:
  /// **'Pick the right spelling — hear vs here, to vs too vs two'**
  String get homophoneDrillDescription;

  /// No description provided for @confusableDrillTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Trap'**
  String get confusableDrillTitle;

  /// No description provided for @confusableDrillDescription.
  ///
  /// In en, this message translates to:
  /// **'Spot the right word — affect vs effect, lose vs loose'**
  String get confusableDrillDescription;

  /// No description provided for @phrasalVerbPowerTitle.
  ///
  /// In en, this message translates to:
  /// **'Phrasal Verb Power'**
  String get phrasalVerbPowerTitle;

  /// No description provided for @phrasalVerbPowerDescription.
  ///
  /// In en, this message translates to:
  /// **'Pick the word that completes the phrasal verb — give ___, take ___'**
  String get phrasalVerbPowerDescription;

  /// No description provided for @phrasalVerbPowerPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which word completes the phrasal verb?'**
  String get phrasalVerbPowerPrompt;

  /// No description provided for @phrasalVerbPowerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No phrasal-verb data available yet.'**
  String get phrasalVerbPowerEmpty;

  /// No description provided for @phrasalVerbPowerOnboard1.
  ///
  /// In en, this message translates to:
  /// **'Phrasal verbs are a verb plus a little word like up, off or away — give up, take off, look after.'**
  String get phrasalVerbPowerOnboard1;

  /// No description provided for @phrasalVerbPowerOnboard2.
  ///
  /// In en, this message translates to:
  /// **'A sentence with a missing word is shown. Tap the word that completes the phrasal verb.'**
  String get phrasalVerbPowerOnboard2;

  /// No description provided for @phrasalVerbPowerOnboard3.
  ///
  /// In en, this message translates to:
  /// **'After each answer you\'ll see what the phrasal verb means.'**
  String get phrasalVerbPowerOnboard3;

  /// No description provided for @phrasalVerbMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Phrasal Verb Match'**
  String get phrasalVerbMatchTitle;

  /// No description provided for @phrasalVerbMatchDescription.
  ///
  /// In en, this message translates to:
  /// **'Match the phrasal verb to its meaning — give up, take off, look after'**
  String get phrasalVerbMatchDescription;

  /// No description provided for @phrasalVerbMatchPrompt.
  ///
  /// In en, this message translates to:
  /// **'What does this phrasal verb mean?'**
  String get phrasalVerbMatchPrompt;

  /// No description provided for @phrasalVerbMatchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No phrasal-verb data available yet.'**
  String get phrasalVerbMatchEmpty;

  /// No description provided for @phrasalVerbMatchOnboard1.
  ///
  /// In en, this message translates to:
  /// **'A phrasal verb is shown — sometimes with an example sentence for context.'**
  String get phrasalVerbMatchOnboard1;

  /// No description provided for @phrasalVerbMatchOnboard2.
  ///
  /// In en, this message translates to:
  /// **'Tap the meaning that matches the phrasal verb. The other choices are real meanings of different phrasal verbs.'**
  String get phrasalVerbMatchOnboard2;

  /// No description provided for @phrasalVerbMatchOnboard3.
  ///
  /// In en, this message translates to:
  /// **'Reading the example can help you work out the meaning.'**
  String get phrasalVerbMatchOnboard3;

  /// No description provided for @falseFriendsTitle.
  ///
  /// In en, this message translates to:
  /// **'False Friends'**
  String get falseFriendsTitle;

  /// No description provided for @falseFriendsDescription.
  ///
  /// In en, this message translates to:
  /// **'Don\'t get tricked — gift ≠ Gift, become ≠ bekommen'**
  String get falseFriendsDescription;

  /// No description provided for @falseFriendsPrompt.
  ///
  /// In en, this message translates to:
  /// **'What does this English word really mean?'**
  String get falseFriendsPrompt;

  /// No description provided for @falseFriendsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No false-friend data available yet.'**
  String get falseFriendsEmpty;

  /// No description provided for @falseFriendsOnboard1.
  ///
  /// In en, this message translates to:
  /// **'False friends are English words that look like a German word but mean something different — \"gift\" is not \"Gift\".'**
  String get falseFriendsOnboard1;

  /// No description provided for @falseFriendsOnboard2.
  ///
  /// In en, this message translates to:
  /// **'Pick the real German meaning. One choice is the look-alike trap!'**
  String get falseFriendsOnboard2;

  /// No description provided for @falseFriendsOnboard3.
  ///
  /// In en, this message translates to:
  /// **'After each answer you\'ll see the real meaning and the trap explained.'**
  String get falseFriendsOnboard3;

  /// No description provided for @falseFriendsExplain.
  ///
  /// In en, this message translates to:
  /// **'{english} = {correctMeaning} — not “{german}” ({germanMeans})!'**
  String falseFriendsExplain(
      String english, String correctMeaning, String german, String germanMeans);

  /// No description provided for @wortfalleTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Trap (DE)'**
  String get wortfalleTitle;

  /// No description provided for @wortfalleDescription.
  ///
  /// In en, this message translates to:
  /// **'Pick the right word — das/dass, seit/seid, Lärche/Lerche'**
  String get wortfalleDescription;

  /// No description provided for @wortfallePrompt.
  ///
  /// In en, this message translates to:
  /// **'Which word fits?'**
  String get wortfallePrompt;

  /// No description provided for @wortfalleOnboard1.
  ///
  /// In en, this message translates to:
  /// **'Some German words look or sound almost the same but mean different things — das/dass, seit/seid, Lärche/Lerche.'**
  String get wortfalleOnboard1;

  /// No description provided for @wortfalleOnboard2.
  ///
  /// In en, this message translates to:
  /// **'A sentence with a gap is shown. Pick the word that fits the meaning.'**
  String get wortfalleOnboard2;

  /// No description provided for @wortfalleOnboard3.
  ///
  /// In en, this message translates to:
  /// **'After each answer you\'ll see what each word means.'**
  String get wortfalleOnboard3;

  /// No description provided for @gameRoundComplete.
  ///
  /// In en, this message translates to:
  /// **'Round complete!'**
  String get gameRoundComplete;

  /// No description provided for @gameBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get gameBack;

  /// No description provided for @gamePlayAgain.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get gamePlayAgain;

  /// No description provided for @gameCorrectOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{correct} of {total} correct'**
  String gameCorrectOfTotal(int correct, int total);

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

  /// No description provided for @achievementAntonymAceTitle.
  ///
  /// In en, this message translates to:
  /// **'Antonym Ace'**
  String get achievementAntonymAceTitle;

  /// No description provided for @achievementAntonymAceDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Antonym Flash 3 times.'**
  String get achievementAntonymAceDesc;

  /// No description provided for @achievementSynonymScholarTitle.
  ///
  /// In en, this message translates to:
  /// **'Synonym Scholar'**
  String get achievementSynonymScholarTitle;

  /// No description provided for @achievementSynonymScholarDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Synonym Flash 3 times.'**
  String get achievementSynonymScholarDesc;

  /// No description provided for @achievementClozeMasterTitle.
  ///
  /// In en, this message translates to:
  /// **'Cloze Master'**
  String get achievementClozeMasterTitle;

  /// No description provided for @achievementClozeMasterDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Cloze Flash 3 times.'**
  String get achievementClozeMasterDesc;

  /// No description provided for @achievementTranslationTitanTitle.
  ///
  /// In en, this message translates to:
  /// **'Translation Titan'**
  String get achievementTranslationTitanTitle;

  /// No description provided for @achievementTranslationTitanDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Translation Flash 3 times.'**
  String get achievementTranslationTitanDesc;

  /// No description provided for @achievementReverseLinguistTitle.
  ///
  /// In en, this message translates to:
  /// **'Reverse Linguist'**
  String get achievementReverseLinguistTitle;

  /// No description provided for @achievementReverseLinguistDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Reverse Translation 3 times.'**
  String get achievementReverseLinguistDesc;

  /// No description provided for @achievementSyllableCounterTitle.
  ///
  /// In en, this message translates to:
  /// **'Syllable Counter'**
  String get achievementSyllableCounterTitle;

  /// No description provided for @achievementSyllableCounterDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Syllable Count 3 times.'**
  String get achievementSyllableCounterDesc;

  /// No description provided for @achievementExpressionExpertTitle.
  ///
  /// In en, this message translates to:
  /// **'Expression Expert'**
  String get achievementExpressionExpertTitle;

  /// No description provided for @achievementExpressionExpertDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Expression Flash 3 times.'**
  String get achievementExpressionExpertDesc;

  /// No description provided for @achievementHypernymHunterTitle.
  ///
  /// In en, this message translates to:
  /// **'Hypernym Hunter'**
  String get achievementHypernymHunterTitle;

  /// No description provided for @achievementHypernymHunterDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Hypernym Flash 3 times.'**
  String get achievementHypernymHunterDesc;

  /// No description provided for @achievementWordClassWhizTitle.
  ///
  /// In en, this message translates to:
  /// **'Word Class Whiz'**
  String get achievementWordClassWhizTitle;

  /// No description provided for @achievementWordClassWhizDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Word Class Flash 3 times.'**
  String get achievementWordClassWhizDesc;

  /// No description provided for @achievementProverbSageTitle.
  ///
  /// In en, this message translates to:
  /// **'Proverb Sage'**
  String get achievementProverbSageTitle;

  /// No description provided for @achievementProverbSageDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Proverb Cloze 3 times.'**
  String get achievementProverbSageDesc;

  /// No description provided for @achievementConjugationKingTitle.
  ///
  /// In en, this message translates to:
  /// **'Conjugation King'**
  String get achievementConjugationKingTitle;

  /// No description provided for @achievementConjugationKingDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Conjugation Drill 3 times.'**
  String get achievementConjugationKingDesc;

  /// No description provided for @achievementVerbSplitterTitle.
  ///
  /// In en, this message translates to:
  /// **'Verb Splitter'**
  String get achievementVerbSplitterTitle;

  /// No description provided for @achievementVerbSplitterDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Verbtrenner 3 times.'**
  String get achievementVerbSplitterDesc;

  /// No description provided for @achievementDefinitionWizardTitle.
  ///
  /// In en, this message translates to:
  /// **'Definition Wizard'**
  String get achievementDefinitionWizardTitle;

  /// No description provided for @achievementDefinitionWizardDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Definition Quiz 3 times.'**
  String get achievementDefinitionWizardDesc;

  /// No description provided for @achievementSentenceSmithTitle.
  ///
  /// In en, this message translates to:
  /// **'Sentence Smith'**
  String get achievementSentenceSmithTitle;

  /// No description provided for @achievementSentenceSmithDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Sentence Completion 3 times.'**
  String get achievementSentenceSmithDesc;

  /// No description provided for @achievementSpellingSleutTitle.
  ///
  /// In en, this message translates to:
  /// **'Spelling Sleuth'**
  String get achievementSpellingSleutTitle;

  /// No description provided for @achievementSpellingSleutDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Spelling Spotter 3 times.'**
  String get achievementSpellingSleutDesc;

  /// No description provided for @achievementHomophoneHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Homophone Hero'**
  String get achievementHomophoneHeroTitle;

  /// No description provided for @achievementHomophoneHeroDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Homophone Drill 3 times.'**
  String get achievementHomophoneHeroDesc;

  /// No description provided for @achievementConfusableProTitle.
  ///
  /// In en, this message translates to:
  /// **'Confusable Pro'**
  String get achievementConfusableProTitle;

  /// No description provided for @achievementConfusableProDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete Confusable Drill 3 times.'**
  String get achievementConfusableProDesc;

  /// No description provided for @achievementReviewRegularTitle.
  ///
  /// In en, this message translates to:
  /// **'Review Regular'**
  String get achievementReviewRegularTitle;

  /// No description provided for @achievementReviewRegularDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete SRI Review 5 times.'**
  String get achievementReviewRegularDesc;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View crash log (stays on device)'**
  String get diagnosticsSubtitle;

  /// No description provided for @parentDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning insights'**
  String get parentDashboardTitle;

  /// No description provided for @parentDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed progress, optionally PIN-protected'**
  String get parentDashboardSubtitle;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyTitle;

  /// No description provided for @privacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'What is stored on this device'**
  String get privacySubtitle;

  /// No description provided for @deleteAllDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete All Data'**
  String get deleteAllDataTitle;

  /// No description provided for @deleteAllDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reset progress on this device'**
  String get deleteAllDataSubtitle;

  /// No description provided for @noSourcesFound.
  ///
  /// In en, this message translates to:
  /// **'No sources found'**
  String get noSourcesFound;

  /// No description provided for @noCustomSetsYet.
  ///
  /// In en, this message translates to:
  /// **'No custom sets created yet.'**
  String get noCustomSetsYet;

  /// No description provided for @antonymFlashPrompt.
  ///
  /// In en, this message translates to:
  /// **'Opposite of …'**
  String get antonymFlashPrompt;

  /// No description provided for @syllableCountPrompt.
  ///
  /// In en, this message translates to:
  /// **'How many syllables?'**
  String get syllableCountPrompt;

  /// No description provided for @wordClassFlashPrompt.
  ///
  /// In en, this message translates to:
  /// **'What word class?'**
  String get wordClassFlashPrompt;

  /// No description provided for @noAntonymData.
  ///
  /// In en, this message translates to:
  /// **'No antonym data available at this level.'**
  String get noAntonymData;

  /// No description provided for @correctInSeconds.
  ///
  /// In en, this message translates to:
  /// **'correct in {n}s'**
  String correctInSeconds(int n);

  /// No description provided for @parentPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Insights PIN'**
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
  /// **'Change insights PIN'**
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
  /// **'Nouns, verbs and adjectives are the building blocks. Higher levels add adverbs and pronouns.'**
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

  /// No description provided for @fontFamilyTitle.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get fontFamilyTitle;

  /// No description provided for @fontFamilySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a font for learning content'**
  String get fontFamilySubtitle;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @debugModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Debug Mode Enabled!'**
  String get debugModeEnabled;

  /// No description provided for @synonymFlashPrompt.
  ///
  /// In en, this message translates to:
  /// **'Synonym for …'**
  String get synonymFlashPrompt;

  /// No description provided for @noSynonymData.
  ///
  /// In en, this message translates to:
  /// **'No synonym data available at this level.'**
  String get noSynonymData;

  /// No description provided for @noClozeSentences.
  ///
  /// In en, this message translates to:
  /// **'No example sentences available at this level.'**
  String get noClozeSentences;

  /// No description provided for @clozeAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer: {word}'**
  String clozeAnswer(String word);

  /// No description provided for @sriReviewHeader.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get sriReviewHeader;

  /// No description provided for @reviewNoWordsYet.
  ///
  /// In en, this message translates to:
  /// **'No words to review yet.\nPlay a few rounds so the system can identify your weak spots!'**
  String get reviewNoWordsYet;

  /// No description provided for @difficultyVeryHard.
  ///
  /// In en, this message translates to:
  /// **'Very hard'**
  String get difficultyVeryHard;

  /// No description provided for @difficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Difficult'**
  String get difficultyHard;

  /// No description provided for @difficultyPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get difficultyPractice;

  /// No description provided for @challengeTypeArticle.
  ///
  /// In en, this message translates to:
  /// **'Choose article'**
  String get challengeTypeArticle;

  /// No description provided for @challengeTypeSpelling.
  ///
  /// In en, this message translates to:
  /// **'Correct spelling'**
  String get challengeTypeSpelling;

  /// No description provided for @challengeTypeDefinition.
  ///
  /// In en, this message translates to:
  /// **'Which word matches?'**
  String get challengeTypeDefinition;

  /// No description provided for @articleChallengePrompt.
  ///
  /// In en, this message translates to:
  /// **'Which article?\n\"___ {word}\"'**
  String articleChallengePrompt(String word);

  /// No description provided for @wordOfTheDay.
  ///
  /// In en, this message translates to:
  /// **'Word of the Day'**
  String get wordOfTheDay;

  /// No description provided for @pronounce.
  ///
  /// In en, this message translates to:
  /// **'Pronounce'**
  String get pronounce;

  /// No description provided for @tapToPractise.
  ///
  /// In en, this message translates to:
  /// **'Tap to practise →'**
  String get tapToPractise;

  /// No description provided for @gradeLabel.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary level {grade}'**
  String gradeLabel(int grade);

  /// No description provided for @sectionDefinitions.
  ///
  /// In en, this message translates to:
  /// **'Definitions'**
  String get sectionDefinitions;

  /// No description provided for @sectionExamples.
  ///
  /// In en, this message translates to:
  /// **'Examples'**
  String get sectionExamples;

  /// No description provided for @sectionSynonyms.
  ///
  /// In en, this message translates to:
  /// **'Synonyms'**
  String get sectionSynonyms;

  /// No description provided for @sectionAntonyms.
  ///
  /// In en, this message translates to:
  /// **'Antonyms'**
  String get sectionAntonyms;

  /// No description provided for @didYouKnow.
  ///
  /// In en, this message translates to:
  /// **'Did you know?'**
  String get didYouKnow;

  /// No description provided for @practiceNow.
  ///
  /// In en, this message translates to:
  /// **'Practice now'**
  String get practiceNow;

  /// No description provided for @karteikasten.
  ///
  /// In en, this message translates to:
  /// **'Flashcard Box'**
  String get karteikasten;

  /// No description provided for @karteikastenCardMoved.
  ///
  /// In en, this message translates to:
  /// **'Card moved to Box {box} – {label}'**
  String karteikastenCardMoved(int box, String label);

  /// No description provided for @boxLabel.
  ///
  /// In en, this message translates to:
  /// **'Box {n}'**
  String boxLabel(int n);

  /// No description provided for @boxLabelCurrent.
  ///
  /// In en, this message translates to:
  /// **'(current)'**
  String get boxLabelCurrent;

  /// No description provided for @moveCard.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveCard;

  /// No description provided for @boxEmptyMastered.
  ///
  /// In en, this message translates to:
  /// **'No mastered cards in this box yet.'**
  String get boxEmptyMastered;

  /// No description provided for @boxEmptyDefault.
  ///
  /// In en, this message translates to:
  /// **'This box is empty.'**
  String get boxEmptyDefault;

  /// No description provided for @antonymFlashOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'A word appears — tap its opposite as fast as you can.'**
  String get antonymFlashOnboardingBody1;

  /// No description provided for @hypernymFlashOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'A word appears — tap the correct category as fast as you can.'**
  String get hypernymFlashOnboardingBody1;

  /// No description provided for @noHypernymData.
  ///
  /// In en, this message translates to:
  /// **'No category data available at this level.'**
  String get noHypernymData;

  /// No description provided for @hypernymFlashPrompt.
  ///
  /// In en, this message translates to:
  /// **'Category for …'**
  String get hypernymFlashPrompt;

  /// No description provided for @spellingForDefinition.
  ///
  /// In en, this message translates to:
  /// **'Correct spelling for:\n\"{definition}\"'**
  String spellingForDefinition(String definition);

  /// No description provided for @conjugationDrillOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'A verb and a personal pronoun are shown — choose the correct present tense form.'**
  String get conjugationDrillOnboardingBody1;

  /// No description provided for @conjugationDrillOnboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'All four options are forms of the same pronoun from different verbs.'**
  String get conjugationDrillOnboardingBody2;

  /// No description provided for @conjugationDrillOnboardingBody3.
  ///
  /// In en, this message translates to:
  /// **'This game focuses on German: English verbs barely change in present tense — only the third person singular differs.'**
  String get conjugationDrillOnboardingBody3;

  /// No description provided for @spellingSpotterOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'Four words are shown — one is spelled correctly, the others contain common mistakes.'**
  String get spellingSpotterOnboardingBody1;

  /// No description provided for @spellingSpotterOnboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'Words are sorted by difficulty based on real learner spelling errors.'**
  String get spellingSpotterOnboardingBody2;

  /// No description provided for @correctAnswerReveal.
  ///
  /// In en, this message translates to:
  /// **'Correct answer: {word}'**
  String correctAnswerReveal(String word);

  /// No description provided for @exampleLabel.
  ///
  /// In en, this message translates to:
  /// **'Example:'**
  String get exampleLabel;

  /// No description provided for @definitionQuizPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which word is being described?'**
  String get definitionQuizPrompt;

  /// No description provided for @noDefinitionData.
  ///
  /// In en, this message translates to:
  /// **'No definitions available at this level.'**
  String get noDefinitionData;

  /// No description provided for @definitionQuizOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'A definition is shown — pick the matching word from four options.'**
  String get definitionQuizOnboardingBody1;

  /// No description provided for @definitionQuizOnboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'All options come from the same CEFR level so nothing is too obvious.'**
  String get definitionQuizOnboardingBody2;

  /// No description provided for @definitionQuizOnboardingBody3.
  ///
  /// In en, this message translates to:
  /// **'From vocabulary level 5, a language note appears after a correct answer.'**
  String get definitionQuizOnboardingBody3;

  /// No description provided for @sentenceCompletionPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which word completes the sentence?'**
  String get sentenceCompletionPrompt;

  /// No description provided for @sentenceCompletionOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'A sentence with a gap is shown — pick the word that fits.'**
  String get sentenceCompletionOnboardingBody1;

  /// No description provided for @sentenceCompletionOnboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'Only nouns, verbs, and adjectives are tested — they are uniquely identifiable in context.'**
  String get sentenceCompletionOnboardingBody2;

  /// No description provided for @sentenceCompletionOnboardingBody3.
  ///
  /// In en, this message translates to:
  /// **'A meaning hint appears after each correct answer.'**
  String get sentenceCompletionOnboardingBody3;

  /// No description provided for @spellingSpotterPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which one is spelled correctly?'**
  String get spellingSpotterPrompt;

  /// No description provided for @noSpellingData.
  ///
  /// In en, this message translates to:
  /// **'No spelling data available at this level.'**
  String get noSpellingData;

  /// No description provided for @synonymFlashOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'A word appears — tap a word with the same meaning as fast as you can.'**
  String get synonymFlashOnboardingBody1;

  /// No description provided for @synonymFlashOnboardingTimer.
  ///
  /// In en, this message translates to:
  /// **'You have 30 seconds. More correct answers means a better score.'**
  String get synonymFlashOnboardingTimer;

  /// No description provided for @clozeFlashOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'A sentence appears with a missing word — tap the correct answer.'**
  String get clozeFlashOnboardingBody1;

  /// No description provided for @clozeFlashOnboardingTimer.
  ///
  /// In en, this message translates to:
  /// **'You have 30 seconds. Read the context — it helps!'**
  String get clozeFlashOnboardingTimer;

  /// No description provided for @sriReviewOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'Practice your weakest words — selected based on your learning history.'**
  String get sriReviewOnboardingBody1;

  /// No description provided for @sriReviewOnboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'Each challenge adapts to the word: article, spelling, or definition.'**
  String get sriReviewOnboardingBody2;

  /// No description provided for @sriReviewOnboardingBody3.
  ///
  /// In en, this message translates to:
  /// **'Every correct answer raises the easiness factor of that word.'**
  String get sriReviewOnboardingBody3;

  /// No description provided for @achievementGrade2Title.
  ///
  /// In en, this message translates to:
  /// **'Level 2 Explorer'**
  String get achievementGrade2Title;

  /// No description provided for @achievementGrade2Desc.
  ///
  /// In en, this message translates to:
  /// **'Reached vocabulary level 2.'**
  String get achievementGrade2Desc;

  /// No description provided for @achievementGrade3Title.
  ///
  /// In en, this message translates to:
  /// **'Level 3 Explorer'**
  String get achievementGrade3Title;

  /// No description provided for @achievementGrade3Desc.
  ///
  /// In en, this message translates to:
  /// **'Reached vocabulary level 3.'**
  String get achievementGrade3Desc;

  /// No description provided for @achievementGrade4Title.
  ///
  /// In en, this message translates to:
  /// **'Level 4 Explorer'**
  String get achievementGrade4Title;

  /// No description provided for @achievementGrade4Desc.
  ///
  /// In en, this message translates to:
  /// **'Reached vocabulary level 4.'**
  String get achievementGrade4Desc;

  /// No description provided for @achievementGrade5Title.
  ///
  /// In en, this message translates to:
  /// **'Level 5 Explorer'**
  String get achievementGrade5Title;

  /// No description provided for @achievementGrade5Desc.
  ///
  /// In en, this message translates to:
  /// **'Reached vocabulary level 5.'**
  String get achievementGrade5Desc;

  /// No description provided for @achievementGrade6Title.
  ///
  /// In en, this message translates to:
  /// **'Level 6 Explorer'**
  String get achievementGrade6Title;

  /// No description provided for @achievementGrade6Desc.
  ///
  /// In en, this message translates to:
  /// **'Reached vocabulary level 6.'**
  String get achievementGrade6Desc;

  /// No description provided for @semanticsBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get semanticsBack;

  /// No description provided for @semanticsScore.
  ///
  /// In en, this message translates to:
  /// **'Score: {n}'**
  String semanticsScore(int n);

  /// No description provided for @semanticsProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress: {done} of {total}'**
  String semanticsProgress(int done, int total);

  /// No description provided for @semanticsCombo.
  ///
  /// In en, this message translates to:
  /// **'Combo x{n}'**
  String semanticsCombo(int n);

  /// No description provided for @syllableCountOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'A word appears — tap how many syllables it has.'**
  String get syllableCountOnboardingBody1;

  /// No description provided for @syllableCountOnboardingTimer.
  ///
  /// In en, this message translates to:
  /// **'You have 30 seconds. Say the word aloud to feel its syllables.'**
  String get syllableCountOnboardingTimer;

  /// No description provided for @noSyllableData.
  ///
  /// In en, this message translates to:
  /// **'No syllable data available at this level.'**
  String get noSyllableData;

  /// No description provided for @wordClassFlashOnboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'A word appears — tap its word class as fast as you can.'**
  String get wordClassFlashOnboardingBody1;

  /// No description provided for @wordClassFlashOnboardingTimer.
  ///
  /// In en, this message translates to:
  /// **'You have 30 seconds. Noun, Verb, Adjective or Adverb?'**
  String get wordClassFlashOnboardingTimer;

  /// No description provided for @wordClassFlashOnboardingTip.
  ///
  /// In en, this message translates to:
  /// **'Think about the word\'s meaning and form.'**
  String get wordClassFlashOnboardingTip;

  /// No description provided for @noWordClassData.
  ///
  /// In en, this message translates to:
  /// **'No word class data available at this level.'**
  String get noWordClassData;

  /// No description provided for @wordTypeNoun.
  ///
  /// In en, this message translates to:
  /// **'Noun'**
  String get wordTypeNoun;

  /// No description provided for @wordTypeVerb.
  ///
  /// In en, this message translates to:
  /// **'Verb'**
  String get wordTypeVerb;

  /// No description provided for @wordTypeAdjective.
  ///
  /// In en, this message translates to:
  /// **'Adjective'**
  String get wordTypeAdjective;

  /// No description provided for @wordTypeAdverb.
  ///
  /// In en, this message translates to:
  /// **'Adverb'**
  String get wordTypeAdverb;

  /// No description provided for @wordTypePronoun.
  ///
  /// In en, this message translates to:
  /// **'Pronoun'**
  String get wordTypePronoun;

  /// No description provided for @wordSortHintCorrect.
  ///
  /// In en, this message translates to:
  /// **'✓ Correct!'**
  String get wordSortHintCorrect;

  /// No description provided for @wordSortHintWrong.
  ///
  /// In en, this message translates to:
  /// **'✗ Wrong!'**
  String get wordSortHintWrong;

  /// No description provided for @wordSortHintNotA.
  ///
  /// In en, this message translates to:
  /// **'✗ Not a {type}!'**
  String wordSortHintNotA(String type);

  /// No description provided for @wordSortHintSynonym.
  ///
  /// In en, this message translates to:
  /// **'✓ Also: {synonyms}'**
  String wordSortHintSynonym(String synonyms);

  /// No description provided for @wordSortHintAntonym.
  ///
  /// In en, this message translates to:
  /// **'✓ Opposite: {antonym}'**
  String wordSortHintAntonym(String antonym);

  /// No description provided for @wordSortHintNounNaming.
  ///
  /// In en, this message translates to:
  /// **'✓ Noun: {word} (a naming word)'**
  String wordSortHintNounNaming(String word);

  /// No description provided for @wordSortHintVerbAction.
  ///
  /// In en, this message translates to:
  /// **'✓ Verb: {word} → action or state'**
  String wordSortHintVerbAction(String word);

  /// No description provided for @wordSortHintAdjQuality.
  ///
  /// In en, this message translates to:
  /// **'✓ Adjective: {word} → describes a quality'**
  String wordSortHintAdjQuality(String word);

  /// No description provided for @wordSortHintAdjQuestion.
  ///
  /// In en, this message translates to:
  /// **'✓ Answers \"What is it like?\" → {word}'**
  String wordSortHintAdjQuestion(String word);

  /// No description provided for @wordSortHintAdverbAction.
  ///
  /// In en, this message translates to:
  /// **'✓ Adverb: {word} → tells how/when/where'**
  String wordSortHintAdverbAction(String word);

  /// No description provided for @wordSortHintAdverbQuestion.
  ///
  /// In en, this message translates to:
  /// **'✓ Answers: how? when? where? → {word}'**
  String wordSortHintAdverbQuestion(String word);

  /// No description provided for @wordSortHintPronounReplaces.
  ///
  /// In en, this message translates to:
  /// **'✓ Pronoun: {word} → replaces a noun'**
  String wordSortHintPronounReplaces(String word);

  /// No description provided for @wordSortHintPronounStands.
  ///
  /// In en, this message translates to:
  /// **'✓ {word} → stands for a noun or noun phrase'**
  String wordSortHintPronounStands(String word);

  /// No description provided for @wordSortDragLabel.
  ///
  /// In en, this message translates to:
  /// **'Word: {word}. Drag it to the correct word class.'**
  String wordSortDragLabel(String word);

  /// No description provided for @wordSortHintCorrectAs.
  ///
  /// In en, this message translates to:
  /// **'✓ Correct: {word} is a {type}!'**
  String wordSortHintCorrectAs(String word, String type);

  /// No description provided for @homophoneTitleHomophone.
  ///
  /// In en, this message translates to:
  /// **'Homophone Drill'**
  String get homophoneTitleHomophone;

  /// No description provided for @homophoneTitleTrap.
  ///
  /// In en, this message translates to:
  /// **'Word Trap'**
  String get homophoneTitleTrap;

  /// No description provided for @homophoneOnboardHomophone1.
  ///
  /// In en, this message translates to:
  /// **'Homophones sound the same but are spelled differently — \"hear\" vs \"here\", \"to\" vs \"too\" vs \"two\".'**
  String get homophoneOnboardHomophone1;

  /// No description provided for @homophoneOnboardHomophone2.
  ///
  /// In en, this message translates to:
  /// **'A sentence with a missing word is shown. Pick the spelling that fits the meaning.'**
  String get homophoneOnboardHomophone2;

  /// No description provided for @homophoneOnboardHomophone3.
  ///
  /// In en, this message translates to:
  /// **'After each answer a meaning hint reveals what makes each spelling unique.'**
  String get homophoneOnboardHomophone3;

  /// No description provided for @homophoneOnboardConfusable1.
  ///
  /// In en, this message translates to:
  /// **'Some words look or sound similar but mean different things — \"affect\" vs \"effect\", \"loose\" vs \"lose\".'**
  String get homophoneOnboardConfusable1;

  /// No description provided for @homophoneOnboardConfusable2.
  ///
  /// In en, this message translates to:
  /// **'A sentence with a missing word is shown. Pick the word whose meaning fits the context.'**
  String get homophoneOnboardConfusable2;

  /// No description provided for @homophoneOnboardConfusable3.
  ///
  /// In en, this message translates to:
  /// **'After each answer you\'ll see a clear explanation of what makes each word distinct.'**
  String get homophoneOnboardConfusable3;

  /// No description provided for @homophoneEmpty.
  ///
  /// In en, this message translates to:
  /// **'No homophone data available for this level.'**
  String get homophoneEmpty;

  /// No description provided for @homophonePromptHomophone.
  ///
  /// In en, this message translates to:
  /// **'Which word fits?'**
  String get homophonePromptHomophone;

  /// No description provided for @homophonePromptConfusable.
  ///
  /// In en, this message translates to:
  /// **'Which word is correct here?'**
  String get homophonePromptConfusable;

  /// No description provided for @homophoneMeanings.
  ///
  /// In en, this message translates to:
  /// **'Meanings'**
  String get homophoneMeanings;

  /// No description provided for @homophoneSubtitleHomophone.
  ///
  /// In en, this message translates to:
  /// **'correct homophones'**
  String get homophoneSubtitleHomophone;

  /// No description provided for @homophoneSubtitleTrap.
  ///
  /// In en, this message translates to:
  /// **'correct words'**
  String get homophoneSubtitleTrap;

  /// No description provided for @wordBuilderHintsUsed.
  ///
  /// In en, this message translates to:
  /// **'{count} used'**
  String wordBuilderHintsUsed(int count);

  /// No description provided for @wordBuilderLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String wordBuilderLevelLabel(int level);

  /// No description provided for @wordBuilderLevelShort.
  ///
  /// In en, this message translates to:
  /// **'Lvl {level}'**
  String wordBuilderLevelShort(int level);

  /// No description provided for @wordBuilderWordsProgress.
  ///
  /// In en, this message translates to:
  /// **'Words: {done} of {total}'**
  String wordBuilderWordsProgress(int done, int total);

  /// No description provided for @wordBuilderLetterTile.
  ///
  /// In en, this message translates to:
  /// **'Letter tile {letter}'**
  String wordBuilderLetterTile(String letter);

  /// No description provided for @wordBuilderTileHint.
  ///
  /// In en, this message translates to:
  /// **'Tap or drag into the word area'**
  String get wordBuilderTileHint;

  /// No description provided for @wordBuilderTimeRemaining.
  ///
  /// In en, this message translates to:
  /// **'Time: {seconds} seconds'**
  String wordBuilderTimeRemaining(int seconds);

  /// No description provided for @wordSnakeResetSelection.
  ///
  /// In en, this message translates to:
  /// **'Reset selection'**
  String get wordSnakeResetSelection;

  /// No description provided for @wordSnakeScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Points: {score}'**
  String wordSnakeScoreLabel(int score);

  /// No description provided for @wordSnakeCell.
  ///
  /// In en, this message translates to:
  /// **'Letter {letter}'**
  String wordSnakeCell(String letter);

  /// No description provided for @wordSnakeCellSelected.
  ///
  /// In en, this message translates to:
  /// **'Letter {letter}, position {position}'**
  String wordSnakeCellSelected(String letter, int position);

  /// No description provided for @wordSnakeNoPuzzles.
  ///
  /// In en, this message translates to:
  /// **'No puzzle could be made right now. Please try another level or come back later.'**
  String get wordSnakeNoPuzzles;

  /// No description provided for @wordSnakeBasicVocabulary.
  ///
  /// In en, this message translates to:
  /// **'⭐ Core vocabulary'**
  String get wordSnakeBasicVocabulary;

  /// No description provided for @wordSnakeNoun.
  ///
  /// In en, this message translates to:
  /// **'Noun (naming word)'**
  String get wordSnakeNoun;

  /// No description provided for @wordSnakeNounWithArticle.
  ///
  /// In en, this message translates to:
  /// **'Noun ({article})'**
  String wordSnakeNounWithArticle(String article);

  /// No description provided for @wordSnakeGenus.
  ///
  /// In en, this message translates to:
  /// **'Gender: {genus}'**
  String wordSnakeGenus(String genus);

  /// No description provided for @wordSnakePlural.
  ///
  /// In en, this message translates to:
  /// **'Plural: {plural}'**
  String wordSnakePlural(String plural);

  /// No description provided for @wordSnakeVerb.
  ///
  /// In en, this message translates to:
  /// **'Verb (action word)'**
  String get wordSnakeVerb;

  /// No description provided for @wordSnakeVerbForms.
  ///
  /// In en, this message translates to:
  /// **'e.g. ich {ich}, du {du}, er {er}'**
  String wordSnakeVerbForms(String ich, String du, String er);

  /// No description provided for @wordSnakeForms.
  ///
  /// In en, this message translates to:
  /// **'Forms: {forms}'**
  String wordSnakeForms(String forms);

  /// No description provided for @wordSnakeAdjective.
  ///
  /// In en, this message translates to:
  /// **'Adjective (describing word)'**
  String get wordSnakeAdjective;

  /// No description provided for @wordSnakeAdjectivePositive.
  ///
  /// In en, this message translates to:
  /// **'Adjective (positive)'**
  String get wordSnakeAdjectivePositive;

  /// No description provided for @wordSnakeComparison.
  ///
  /// In en, this message translates to:
  /// **'Comparison: {forms}'**
  String wordSnakeComparison(String forms);

  /// No description provided for @wordSnakePronoun.
  ///
  /// In en, this message translates to:
  /// **'Pronoun'**
  String get wordSnakePronoun;

  /// No description provided for @wordSnakeArticle.
  ///
  /// In en, this message translates to:
  /// **'Article'**
  String get wordSnakeArticle;

  /// No description provided for @wordSnakeAdverb.
  ///
  /// In en, this message translates to:
  /// **'Adverb'**
  String get wordSnakeAdverb;

  /// No description provided for @wordSnakePreposition.
  ///
  /// In en, this message translates to:
  /// **'Preposition'**
  String get wordSnakePreposition;

  /// No description provided for @wordSnakeConjunction.
  ///
  /// In en, this message translates to:
  /// **'Conjunction'**
  String get wordSnakeConjunction;

  /// No description provided for @wordSnakeParticle.
  ///
  /// In en, this message translates to:
  /// **'Particle'**
  String get wordSnakeParticle;

  /// No description provided for @wordSnakeNumeral.
  ///
  /// In en, this message translates to:
  /// **'Numeral'**
  String get wordSnakeNumeral;

  /// No description provided for @wordSnakeCaseNominative.
  ///
  /// In en, this message translates to:
  /// **'Nominative'**
  String get wordSnakeCaseNominative;

  /// No description provided for @wordSnakeCaseAccusative.
  ///
  /// In en, this message translates to:
  /// **'Accusative'**
  String get wordSnakeCaseAccusative;

  /// No description provided for @wordSnakeCaseDative.
  ///
  /// In en, this message translates to:
  /// **'Dative'**
  String get wordSnakeCaseDative;

  /// No description provided for @wordSnakeCaseGenitive.
  ///
  /// In en, this message translates to:
  /// **'Genitive'**
  String get wordSnakeCaseGenitive;

  /// No description provided for @wordSnakeExample.
  ///
  /// In en, this message translates to:
  /// **'e.g.: {example}'**
  String wordSnakeExample(String example);

  /// No description provided for @rescueHintHeardAgain.
  ///
  /// In en, this message translates to:
  /// **'Listened to the word again!'**
  String get rescueHintHeardAgain;

  /// No description provided for @rescueHintStartsWith.
  ///
  /// In en, this message translates to:
  /// **'Starts with: {prefix}...'**
  String rescueHintStartsWith(String prefix);

  /// No description provided for @rescueHintLetterCount.
  ///
  /// In en, this message translates to:
  /// **'{count} letters'**
  String rescueHintLetterCount(int count);

  /// No description provided for @rescueBestStreak.
  ///
  /// In en, this message translates to:
  /// **'Best streak: {count} 🔥'**
  String rescueBestStreak(int count);

  /// No description provided for @rescueSemanticsScore.
  ///
  /// In en, this message translates to:
  /// **'Score: {score}'**
  String rescueSemanticsScore(int score);

  /// No description provided for @rescueSemanticsStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak: {count}'**
  String rescueSemanticsStreak(int count);

  /// No description provided for @rescueSemanticsRescued.
  ///
  /// In en, this message translates to:
  /// **'Rescued: {rescued} of {total}'**
  String rescueSemanticsRescued(int rescued, int total);

  /// No description provided for @rescueSemanticsLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String rescueSemanticsLevel(int level);

  /// No description provided for @rescueSemanticsInputField.
  ///
  /// In en, this message translates to:
  /// **'Type the word here'**
  String get rescueSemanticsInputField;

  /// No description provided for @rescueSemanticsShowHint.
  ///
  /// In en, this message translates to:
  /// **'Show hint'**
  String get rescueSemanticsShowHint;

  /// No description provided for @rescueSemanticsReadWord.
  ///
  /// In en, this message translates to:
  /// **'Read word aloud'**
  String get rescueSemanticsReadWord;

  /// No description provided for @wordMemoryScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Points: {score}'**
  String wordMemoryScoreLabel(int score);

  /// No description provided for @wordMemoryMovesLabel.
  ///
  /// In en, this message translates to:
  /// **'Moves: {moves}'**
  String wordMemoryMovesLabel(int moves);

  /// No description provided for @wordMemoryPairsLabel.
  ///
  /// In en, this message translates to:
  /// **'Pairs: {found} of {total}'**
  String wordMemoryPairsLabel(int found, int total);

  /// No description provided for @wordMemoryTotalGemsLabel.
  ///
  /// In en, this message translates to:
  /// **'Total gems: {gems}'**
  String wordMemoryTotalGemsLabel(int gems);

  /// No description provided for @wordMemoryCardMatched.
  ///
  /// In en, this message translates to:
  /// **'Card {text}, matched'**
  String wordMemoryCardMatched(String text);

  /// No description provided for @wordMemoryCardRevealed.
  ///
  /// In en, this message translates to:
  /// **'Card {text}, revealed'**
  String wordMemoryCardRevealed(String text);

  /// No description provided for @wordMemoryCardHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden card'**
  String get wordMemoryCardHidden;

  /// No description provided for @wordSortDropZoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Drop zone: {label}'**
  String wordSortDropZoneLabel(String label);

  /// No description provided for @wordSortEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No words available'**
  String get wordSortEmptyTitle;

  /// No description provided for @wordSortEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'There are no words to sort for this level yet. Try another level or come back later.'**
  String get wordSortEmptyMessage;

  /// No description provided for @wordSortGenderMasculine.
  ///
  /// In en, this message translates to:
  /// **'masculine (der)'**
  String get wordSortGenderMasculine;

  /// No description provided for @wordSortGenderFeminine.
  ///
  /// In en, this message translates to:
  /// **'feminine (die)'**
  String get wordSortGenderFeminine;

  /// No description provided for @wordSortGenderNeuter.
  ///
  /// In en, this message translates to:
  /// **'neuter (das)'**
  String get wordSortGenderNeuter;

  /// No description provided for @wordSortHintNounPluralForm.
  ///
  /// In en, this message translates to:
  /// **'✓ Plural: {word} → {plural}'**
  String wordSortHintNounPluralForm(String word, String plural);

  /// No description provided for @wordSortHintNounGender.
  ///
  /// In en, this message translates to:
  /// **'✓ Gender: {gender}'**
  String wordSortHintNounGender(String gender);

  /// No description provided for @wordSortHintNounWithArticle.
  ///
  /// In en, this message translates to:
  /// **'✓ Noun: {article} {word}'**
  String wordSortHintNounWithArticle(String article, String word);

  /// No description provided for @wordSortHintDefinition.
  ///
  /// In en, this message translates to:
  /// **'✓ {definition}'**
  String wordSortHintDefinition(String definition);

  /// No description provided for @wordSortHintVerbPersonalForms.
  ///
  /// In en, this message translates to:
  /// **'✓ Personal forms: ich {ich}, du {du}'**
  String wordSortHintVerbPersonalForms(String ich, String du);

  /// No description provided for @wordSortHintVerbPerfect.
  ///
  /// In en, this message translates to:
  /// **'✓ Perfect: {form}'**
  String wordSortHintVerbPerfect(String form);

  /// No description provided for @wordSortHintVerbPast.
  ///
  /// In en, this message translates to:
  /// **'✓ Past: ich {form}'**
  String wordSortHintVerbPast(String form);

  /// No description provided for @wordSortHintAdjComparison.
  ///
  /// In en, this message translates to:
  /// **'✓ Comparison: {word} → {comparative} → {superlative}'**
  String wordSortHintAdjComparison(
      String word, String comparative, String superlative);

  /// No description provided for @wordSortHintAdjComparative.
  ///
  /// In en, this message translates to:
  /// **'✓ Comparative: {word} → {comparative}'**
  String wordSortHintAdjComparative(String word, String comparative);

  /// No description provided for @wordSortExplainCategoryDefinition.
  ///
  /// In en, this message translates to:
  /// **'✓ {category}: \"{definition}\"'**
  String wordSortExplainCategoryDefinition(String category, String definition);

  /// No description provided for @wordSortExplainCategory.
  ///
  /// In en, this message translates to:
  /// **'✓ {word} → {category}'**
  String wordSortExplainCategory(String word, String category);

  /// No description provided for @wordSortReasonNotConjugable.
  ///
  /// In en, this message translates to:
  /// **'not conjugable'**
  String get wordSortReasonNotConjugable;

  /// No description provided for @wordSortReasonNotComparable.
  ///
  /// In en, this message translates to:
  /// **'not comparable'**
  String get wordSortReasonNotComparable;

  /// No description provided for @wordSortReasonPlural.
  ///
  /// In en, this message translates to:
  /// **'plural: {plural}'**
  String wordSortReasonPlural(String plural);

  /// No description provided for @wordSortExplainNounCapitalized.
  ///
  /// In en, this message translates to:
  /// **'✓ {word} → Noun (capitalized!)'**
  String wordSortExplainNounCapitalized(String word);

  /// No description provided for @wordSortExplainNounNaming.
  ///
  /// In en, this message translates to:
  /// **'✓ {word} → Noun (a naming word)'**
  String wordSortExplainNounNaming(String word);

  /// No description provided for @wordSortExplainNounReasons.
  ///
  /// In en, this message translates to:
  /// **'✓ Noun: {reasons}'**
  String wordSortExplainNounReasons(String reasons);

  /// No description provided for @wordSortReasonVerbForms.
  ///
  /// In en, this message translates to:
  /// **'ich {ich}, du {du}'**
  String wordSortReasonVerbForms(String ich, String du);

  /// No description provided for @wordSortReasonVerbFormExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. ich {ich}'**
  String wordSortReasonVerbFormExample(String ich);

  /// No description provided for @wordSortReasonNoArticle.
  ///
  /// In en, this message translates to:
  /// **'no article'**
  String get wordSortReasonNoArticle;

  /// No description provided for @wordSortExplainVerbAction.
  ///
  /// In en, this message translates to:
  /// **'✓ Verb: {word} → action!'**
  String wordSortExplainVerbAction(String word);

  /// No description provided for @wordSortExplainVerbReasons.
  ///
  /// In en, this message translates to:
  /// **'✓ Verb: {reasons}'**
  String wordSortExplainVerbReasons(String reasons);

  /// No description provided for @wordSortExplainVerbDefinition.
  ///
  /// In en, this message translates to:
  /// **'✓ Verb: \"{definition}\"'**
  String wordSortExplainVerbDefinition(String definition);

  /// No description provided for @wordSortReasonComparable.
  ///
  /// In en, this message translates to:
  /// **'comparable: {comparative}'**
  String wordSortReasonComparable(String comparative);

  /// No description provided for @wordSortReasonAdjExample.
  ///
  /// In en, this message translates to:
  /// **'the {word} thing'**
  String wordSortReasonAdjExample(String word);

  /// No description provided for @wordSortExplainAdjReasons.
  ///
  /// In en, this message translates to:
  /// **'✓ Adjective: {reasons}'**
  String wordSortExplainAdjReasons(String reasons);

  /// No description provided for @wordSortExplainAdjDefinition.
  ///
  /// In en, this message translates to:
  /// **'✓ Adjective: \"{definition}\"'**
  String wordSortExplainAdjDefinition(String definition);

  /// No description provided for @wordSortExplainAdjQuality.
  ///
  /// In en, this message translates to:
  /// **'✓ Adjective: {word} → describes a quality'**
  String wordSortExplainAdjQuality(String word);

  /// No description provided for @wordTypeWhirlSemanticsLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String wordTypeWhirlSemanticsLevel(int level);

  /// No description provided for @wordTypeWhirlSemanticsRound.
  ///
  /// In en, this message translates to:
  /// **'Round {round} of {total}'**
  String wordTypeWhirlSemanticsRound(int round, int total);

  /// No description provided for @wordTypeWhirlSemanticsStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak: {streak}'**
  String wordTypeWhirlSemanticsStreak(int streak);

  /// No description provided for @wordTypeWhirlSemanticsTime.
  ///
  /// In en, this message translates to:
  /// **'Time: {seconds} seconds'**
  String wordTypeWhirlSemanticsTime(int seconds);

  /// No description provided for @wordTypeWhirlSemanticsGems.
  ///
  /// In en, this message translates to:
  /// **'Gems: {gems}'**
  String wordTypeWhirlSemanticsGems(int gems);

  /// No description provided for @wordTypeWhirlSemanticsWord.
  ///
  /// In en, this message translates to:
  /// **'Word {word}'**
  String wordTypeWhirlSemanticsWord(String word);

  /// No description provided for @wordTypeWhirlSemanticsTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap if it is a {wordType}'**
  String wordTypeWhirlSemanticsTapHint(String wordType);

  /// No description provided for @wordFindPluralLabel.
  ///
  /// In en, this message translates to:
  /// **'Plural'**
  String get wordFindPluralLabel;

  /// No description provided for @wordFindVerbFormInfinitive.
  ///
  /// In en, this message translates to:
  /// **'Infinitive'**
  String get wordFindVerbFormInfinitive;

  /// No description provided for @wordFindVerbFormFinite.
  ///
  /// In en, this message translates to:
  /// **'finite'**
  String get wordFindVerbFormFinite;

  /// No description provided for @wordFindVerbFormParticiple.
  ///
  /// In en, this message translates to:
  /// **'Participle'**
  String get wordFindVerbFormParticiple;

  /// No description provided for @translationFlashNoData.
  ///
  /// In en, this message translates to:
  /// **'No translation data available for this level.'**
  String get translationFlashNoData;

  /// No description provided for @translationFlashPrompt.
  ///
  /// In en, this message translates to:
  /// **'In English …'**
  String get translationFlashPrompt;

  /// No description provided for @translationFlashCorrectCount.
  ///
  /// In en, this message translates to:
  /// **'{count} correct'**
  String translationFlashCorrectCount(int count);

  /// No description provided for @translationFlashOnboardingTap.
  ///
  /// In en, this message translates to:
  /// **'A German word appears — tap the correct English translation quickly.'**
  String get translationFlashOnboardingTap;

  /// No description provided for @translationFlashOnboardingTimer.
  ///
  /// In en, this message translates to:
  /// **'You have {seconds} seconds. The more correct answers, the better your score.'**
  String translationFlashOnboardingTimer(int seconds);

  /// No description provided for @expressionFlashOnboardingTap.
  ///
  /// In en, this message translates to:
  /// **'An idiom appears with a gap — tap the missing word.'**
  String get expressionFlashOnboardingTap;

  /// No description provided for @expressionFlashOnboardingTimer.
  ///
  /// In en, this message translates to:
  /// **'You have 30 seconds. Know your idioms!'**
  String get expressionFlashOnboardingTimer;

  /// No description provided for @expressionFlashEmpty.
  ///
  /// In en, this message translates to:
  /// **'No idioms available for this level.'**
  String get expressionFlashEmpty;

  /// No description provided for @expressionFlashCorrectCount.
  ///
  /// In en, this message translates to:
  /// **'{n} correct'**
  String expressionFlashCorrectCount(int n);

  /// No description provided for @expressionFlashLabel.
  ///
  /// In en, this message translates to:
  /// **'Idiom'**
  String get expressionFlashLabel;

  /// No description provided for @expressionFlashBlankHint.
  ///
  /// In en, this message translates to:
  /// **'Gap — find the missing word'**
  String get expressionFlashBlankHint;

  /// No description provided for @proverbClozeOnboardingBody.
  ///
  /// In en, this message translates to:
  /// **'A proverb appears with a gap — tap the correct word.'**
  String get proverbClozeOnboardingBody;

  /// No description provided for @proverbClozeOnboardingTimer.
  ///
  /// In en, this message translates to:
  /// **'{seconds} seconds — as many proverbs as you can!'**
  String proverbClozeOnboardingTimer(int seconds);

  /// No description provided for @proverbClozeEmpty.
  ///
  /// In en, this message translates to:
  /// **'No proverb data available for this level.'**
  String get proverbClozeEmpty;

  /// No description provided for @proverbClozeCorrectCount.
  ///
  /// In en, this message translates to:
  /// **'{count} correct'**
  String proverbClozeCorrectCount(int count);

  /// No description provided for @proverbClozeLabel.
  ///
  /// In en, this message translates to:
  /// **'Proverb'**
  String get proverbClozeLabel;

  /// No description provided for @conjugationDrillPrompt.
  ///
  /// In en, this message translates to:
  /// **'What is the present-tense form?'**
  String get conjugationDrillPrompt;

  /// No description provided for @conjugationDrillNoData.
  ///
  /// In en, this message translates to:
  /// **'No conjugation data available for this level.'**
  String get conjugationDrillNoData;

  /// No description provided for @grossschreibSemLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String grossschreibSemLevel(int level);

  /// No description provided for @grossschreibSemScore.
  ///
  /// In en, this message translates to:
  /// **'Points: {score}'**
  String grossschreibSemScore(int score);

  /// No description provided for @grossschreibSemProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress: {done} of {total}'**
  String grossschreibSemProgress(int done, int total);

  /// No description provided for @grossschreibSemCombo.
  ///
  /// In en, this message translates to:
  /// **'Combo times {combo}'**
  String grossschreibSemCombo(int combo);

  /// No description provided for @grossschreibSemWord.
  ///
  /// In en, this message translates to:
  /// **'Word: {word}. Tap to change the spelling.'**
  String grossschreibSemWord(String word);

  /// No description provided for @spellingSpotterCommonMistakes.
  ///
  /// In en, this message translates to:
  /// **'Common mistakes: {errors}'**
  String spellingSpotterCommonMistakes(String errors);

  /// No description provided for @skillLabelSpelling.
  ///
  /// In en, this message translates to:
  /// **'Spelling'**
  String get skillLabelSpelling;

  /// No description provided for @skillLabelArticle.
  ///
  /// In en, this message translates to:
  /// **'Article'**
  String get skillLabelArticle;

  /// No description provided for @skillLabelPlural.
  ///
  /// In en, this message translates to:
  /// **'Plural'**
  String get skillLabelPlural;

  /// No description provided for @skillLabelWordType.
  ///
  /// In en, this message translates to:
  /// **'Word type'**
  String get skillLabelWordType;

  /// No description provided for @skillLabelSentence.
  ///
  /// In en, this message translates to:
  /// **'Sentence'**
  String get skillLabelSentence;

  /// No description provided for @skillLabelPunctuation.
  ///
  /// In en, this message translates to:
  /// **'Punctuation'**
  String get skillLabelPunctuation;

  /// No description provided for @skillLabelCapitalization.
  ///
  /// In en, this message translates to:
  /// **'Capitalization'**
  String get skillLabelCapitalization;

  /// No description provided for @skillLabelConjugation.
  ///
  /// In en, this message translates to:
  /// **'Conjugation'**
  String get skillLabelConjugation;

  /// No description provided for @skillLabelCase.
  ///
  /// In en, this message translates to:
  /// **'Case'**
  String get skillLabelCase;

  /// No description provided for @skillLabelVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary'**
  String get skillLabelVocabulary;

  /// No description provided for @skillLabelReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get skillLabelReading;
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
