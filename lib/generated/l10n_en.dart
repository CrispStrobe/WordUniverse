// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SEn extends S {
  SEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Word Universe';

  @override
  String get welcome => 'Discover the Word Universe!';

  @override
  String get startAdventure => 'Start Your Word Adventure';

  @override
  String get chooseGrade => 'Choose Your Level';

  @override
  String get grade3 => 'Level 1';

  @override
  String get grade4 => 'Level 2';

  @override
  String get grade5 => 'Level 3';

  @override
  String get grade6 => 'Level 4';

  @override
  String get spaceWordRescueTitle => 'Word Rescue';

  @override
  String get spaceWordRescueInstructions => 'Rescue words from drifting off!';

  @override
  String get gameplayHint => 'Hint (-2 Points)';

  @override
  String get gameplayCheck => 'Check';

  @override
  String get gameplayCorrect => 'Correct! Well done! 🚀';

  @override
  String get gameplayIncorrect => 'That wasn\'t quite right. Try the next one!';

  @override
  String get gameplayRescued => 'Rescued';

  @override
  String get gameplayLost => 'Lost';

  @override
  String get gameplayWriteTheWord => 'Type the word...';

  @override
  String gameplayFeedbackCommonMistake(Object correctWord) {
    return 'Almost right! A common mistake.\nCorrect is: $correctWord';
  }

  @override
  String gameplayFeedbackIncorrect(Object correctWord) {
    return 'Sorry, that\'s wrong! Correct is: $correctWord';
  }

  @override
  String get wordFindTitle => 'Word-Find';

  @override
  String get wordFindDescription => 'Find the hidden words in the letter grid!';

  @override
  String get wordFindWordsToFind => 'Words to Find:';

  @override
  String get wordSortTitle => 'Word Type Station';

  @override
  String get wordSortDescription =>
      'Sort the words into the correct categories!';

  @override
  String get wordSortCategoryNoun => 'Nouns';

  @override
  String get wordSortCategoryVerb => 'Verbs';

  @override
  String get wordSortCategoryAdjective => 'Adjectives';

  @override
  String get wordSortCategoryAdverb => 'Adverbs';

  @override
  String get wordSortInstructions => 'Drag the word to the correct station!';

  @override
  String get adaptiveDifficulty => 'Adaptive Difficulty';

  @override
  String get adaptiveDifficultyDesc => 'Adjusts problems based on your skill';

  @override
  String get adjustProblems => 'Adjusts problems based on your skill';

  @override
  String get gameMenu => 'Mission Control';

  @override
  String get level => 'Level';

  @override
  String get score => 'Score';

  @override
  String get lives => 'Hull Integrity';

  @override
  String get time => 'Time';

  @override
  String get correct => 'Correct!';

  @override
  String get incorrect => 'Error!';

  @override
  String get excellent => 'Excellent work, Commander!';

  @override
  String get good => 'Good job!';

  @override
  String get tryAgain => 'Try Again!';

  @override
  String get gameOver => 'Mission Complete!';

  @override
  String get nextLevel => 'Next Mission';

  @override
  String get playAgain => 'Play Again';

  @override
  String get backToMenu => 'Back to Mission Control';

  @override
  String get settings => 'Settings';

  @override
  String get sound => 'Sound FX';

  @override
  String get music => 'Music';

  @override
  String get language => 'Language';

  @override
  String get progress => 'Career Progress';

  @override
  String get achievements => 'Achievements';

  @override
  String get congratulations => 'Congratulations, Commander!';

  @override
  String missionsCompleted(int count) {
    return 'Missions Completed: $count';
  }

  @override
  String starsEarned(int count) {
    return 'Stars Earned: $count';
  }

  @override
  String get audioSettings => 'Audio Settings';

  @override
  String get soundEffects => 'Sound effects';

  @override
  String get backgroundMusicDesc => 'Background music';

  @override
  String get gameplay => 'Gameplay';

  @override
  String get puzzleTimer => 'Puzzle Timer';

  @override
  String get puzzleTimerDesc => 'Enable timer in puzzle games';

  @override
  String get showHints => 'Show Hints';

  @override
  String get showHintsDesc => 'Display helpful hints during games';

  @override
  String get hapticFeedback => 'Haptic Feedback';

  @override
  String get hapticFeedbackDesc => 'Vibration on touch (if supported)';

  @override
  String get appLanguage => 'App Language';

  @override
  String get appLanguageDesc => 'Choose your preferred language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get difficulty => 'Difficulty';

  @override
  String get currentGrade => 'Current Level';

  @override
  String get currentLevelDesc => 'Current Level';

  @override
  String get difficultyDescGrade3 => 'Simple words (Grades 1-2)';

  @override
  String get difficultyDescGrade4 => 'Common words (Grades 3-4)';

  @override
  String get difficultyDescGrade5 => 'Advanced words (Grades 5-6)';

  @override
  String get difficultyDescGrade6 => 'Expert vocabulary (Grades 6+)';

  @override
  String get totalScore => 'Total Score';

  @override
  String get gamesPlayed => 'Games Played';

  @override
  String get resetProgress => 'Reset Progress';

  @override
  String get about => 'About';

  @override
  String get appVersion => 'App Version';

  @override
  String get developer => 'Developer';

  @override
  String get developerName => 'Word Universe Team';

  @override
  String get targetAge => 'Target Age';

  @override
  String get targetAgeRange => '6-12 years (Grades 1-6)';

  @override
  String get aboutApp =>
      'Word Universe helps primary school students learn spelling and vocabulary through engaging space-themed games.';

  @override
  String get debugPanelTitle => 'Debug Panel';

  @override
  String get debugForceUnlock => 'Force Full Unlock';

  @override
  String get debugApplyAndClose => 'Apply & Close';

  @override
  String get parentalGateTitle => 'Parental Gate';

  @override
  String get parentalGateChallenge => 'To continue, please solve this problem:';

  @override
  String get confirm => 'Confirm';

  @override
  String get pleaseTryAgain => 'Please try again.';

  @override
  String get purchaseTitle => 'Unlock Full Access';

  @override
  String get purchaseDescription =>
      'Unlock all games, all levels, and all future updates with a single purchase!';

  @override
  String get purchaseButton => 'Unlock Now!';

  @override
  String get contactingStore => 'Contacting Mission Control...';

  @override
  String get purchaseError =>
      'An error occurred. Please check your connection and try again.';

  @override
  String get restorePurchases => 'Restore Purchases';

  @override
  String get storeUnavailable =>
      'The store is currently unavailable. Please check your connection and that you are signed in to your account.';

  @override
  String get languageChanged => 'Language Changed';

  @override
  String get languageChangedDesc =>
      'The app language will change when you restart. Would you like to restart now?';

  @override
  String get later => 'Later';

  @override
  String get restartNow => 'Restart Now';

  @override
  String get selectGrade => 'Select Level';

  @override
  String gradeN(int gradeNumber) {
    return 'Level $gradeNumber';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get restartToApplyChanges =>
      'Please restart the app to apply language changes';

  @override
  String get resetProgressConfirmation =>
      'Are you sure you want to reset all progress? This action cannot be undone.';

  @override
  String get progressResetSuccess => 'Progress reset successfully!';

  @override
  String get reset => 'Reset';

  @override
  String get playToUnlock => 'Play to unlock!';

  @override
  String get chooseYourGrade => 'Choose Your Level';

  @override
  String get grade3Desc => 'Spelling basics, simple nouns and verbs.';

  @override
  String get grade4Desc => 'Common words, basic grammar rules, and word types.';

  @override
  String get grade5Desc => 'More complex words, cases, and tenses.';

  @override
  String get grade6Desc => 'Advanced vocabulary and complex grammar.';

  @override
  String get settingsComingSoon => 'Settings coming soon!';

  @override
  String get spaceExplorerProgress => 'Space Explorer Progress';

  @override
  String get unlocked => 'Unlocked';

  @override
  String get complete => 'Complete';

  @override
  String get rankRookie => 'Rookie';

  @override
  String get rankExplorer => 'Explorer';

  @override
  String get rankVeteran => 'Veteran';

  @override
  String get rankExpert => 'Expert';

  @override
  String get rankLegend => 'Legend';

  @override
  String get achievementFirstCenturyTitle => 'First Century!';

  @override
  String get achievementFirstCenturyDesc => 'Score 100 points';

  @override
  String get achievementScoreMasterTitle => 'Score Master';

  @override
  String get achievementScoreMasterDesc => 'Score 500 points';

  @override
  String get achievementThousandClubTitle => 'Thousand Club';

  @override
  String get achievementThousandClubDesc => 'Score 1000 points';

  @override
  String get achievementLevelExplorerTitle => 'Level Explorer';

  @override
  String get achievementLevelExplorerDesc => 'Reach level 5';

  @override
  String get achievementSpaceCommanderTitle => 'Space Commander';

  @override
  String get achievementSpaceCommanderDesc => 'Reach level 10';

  @override
  String get achievementAllRounderTitle => 'All-Rounder';

  @override
  String get achievementAllRounderDesc => 'Play all game types';

  @override
  String get achievementSpeedDemonTitle => 'Speed Demon';

  @override
  String get achievementSpeedDemonDesc =>
      'Complete a level in under 30 seconds';

  @override
  String get achievementPerfectionistTitle => 'Perfectionist';

  @override
  String get achievementPerfectionistDesc =>
      'Complete a level without mistakes';

  @override
  String get achievementWordRescuerTitle => 'Word Rescuer';

  @override
  String get achievementWordRescuerDesc => 'Rescue 100 words';

  @override
  String get unlockedStatus => 'UNLOCKED';

  @override
  String get lockedStatus => 'LOCKED';

  @override
  String get achievementUnlocked => 'ACHIEVEMENT UNLOCKED!';

  @override
  String get continueExploring => 'Continue Exploring';

  @override
  String get loadingAdventure => 'Loading Word Adventure...';

  @override
  String get preparingMission => 'Preparing your language mission...';

  @override
  String get initializing => 'Initializing Word Universe...';

  @override
  String get loadingAssets => 'Loading game assets...';

  @override
  String get loadingProgress => 'Loading saved progress...';

  @override
  String get preparingSpaceStation => 'Preparing space station...';

  @override
  String get calibratingNav => 'Calibrating navigation systems...';

  @override
  String get readyForLaunch => 'Ready for launch!';

  @override
  String get launch => 'Launch';

  @override
  String get splashScreenSubtitle => 'Explore • Learn • Discover';

  @override
  String get sriStatisticsTitle => 'Learning Insights';

  @override
  String get sriStatisticsDesc =>
      'View your progress and identify areas for improvement.';

  @override
  String get premiumFeature =>
      'This is a premium feature. Unlock the full version to access.';

  @override
  String get close => 'Close';

  @override
  String get sriMastery => 'Overall Mastery';

  @override
  String get sriTotal => 'Total Tracked';

  @override
  String get sriMastered => 'Mastered';

  @override
  String get sriLearning => 'Learning';

  @override
  String get progressMatrixTitle => 'Progress Matrix';

  @override
  String get progressMatrixDesc =>
      'Color shows mastery (green is best). Number shows problems tracked in that area.';
}
