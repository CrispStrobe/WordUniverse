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
  String get packUpdateNotice =>
      'This app needs an updated language pack. Your previous database is retained while the replacement is downloaded and checked. Extra storage is needed; nothing downloads until you confirm.';

  @override
  String get homeReview => 'Review';

  @override
  String get homeLearningProfile => 'Learning profile';

  @override
  String get statsSpelling => 'Spelling';

  @override
  String get statsArticles => 'Articles (der/die/das)';

  @override
  String get statsPlural => 'Plurals';

  @override
  String get statsWordTypes => 'Parts of speech';

  @override
  String get statsSentenceStructure => 'Sentence structure';

  @override
  String get statsPunctuation => 'Punctuation';

  @override
  String get statsCapitalization => 'Capitalization';

  @override
  String get statsVerbs => 'Verbs (tenses)';

  @override
  String get statsCases => 'Grammatical cases';

  @override
  String get statsVocabulary => 'Vocabulary';

  @override
  String get statsReading => 'Reading in context';

  @override
  String get strategyPhonetic => 'Phonetic spelling';

  @override
  String get strategyStem => 'Word stem principle';

  @override
  String get strategyRelated => 'Related words';

  @override
  String get strategyDouble => 'Double consonant';

  @override
  String get strategyLengthening => 'Vowel lengthening';

  @override
  String get strategyMemory => 'Memory word';

  @override
  String get diagnosticsPackFailures => 'Pack failures';

  @override
  String get diagnosticsNoPackFailures => 'No local failures recorded.';

  @override
  String get diagnosticsLocalOnly =>
      'Stored only on this device. Nothing is uploaded automatically.';

  @override
  String get diagnosticsPack => 'Pack';

  @override
  String get diagnosticsStage => 'Stage';

  @override
  String get diagnosticsCause => 'Cause';

  @override
  String get diagnosticsRequiredBytes => 'Required bytes';

  @override
  String get diagnosticsAvailableBytes => 'Available bytes';

  @override
  String get diagnosticsInstall => 'Installation';

  @override
  String get diagnosticsActivate => 'Activation';

  @override
  String get diagnosticsCauseSpace => 'Insufficient space';

  @override
  String get diagnosticsCauseStorage => 'Storage failure';

  @override
  String get diagnosticsCauseSchema => 'Incompatible database schema';

  @override
  String get diagnosticsCausePayload => 'Invalid pack data';

  @override
  String get diagnosticsCauseNetwork => 'Network failure';

  @override
  String get diagnosticsCauseDownload => 'Download failure';

  @override
  String get diagnosticsCauseUnknown => 'Unknown failure';

  @override
  String get loadPreparing => 'Preparing vocabulary database …';

  @override
  String get loadWebEngine => 'Initializing web database engine …';

  @override
  String get loadLocatingStorage => 'Locating database storage …';

  @override
  String get loadCheckingDatabase => 'Checking existing database …';

  @override
  String get loadPreparingStorage => 'Preparing storage …';

  @override
  String get loadLoadingCompressed => 'Loading compressed database …';

  @override
  String loadLoadedCompressed(Object size) {
    return 'Loaded $size MB compressed data';
  }

  @override
  String get loadDecompressing => 'Decompressing database …';

  @override
  String loadDecompressed(Object size) {
    return 'Decompressed to $size MB';
  }

  @override
  String get loadWritingBrowserStorage => 'Writing to browser storage …';

  @override
  String get loadWritingStorage => 'Writing database to storage …';

  @override
  String get loadSavedBrowser => 'Database saved to browser';

  @override
  String get loadSavedDisk => 'Database saved to disk';

  @override
  String get loadOpeningDatabase => 'Opening database …';

  @override
  String get loadDatabaseReady => 'Database ready!';

  @override
  String loadDatabaseReadyWords(Object count) {
    return 'Database ready with $count words!';
  }

  @override
  String get loadVerifying => 'Verifying database integrity …';

  @override
  String loadVerifiedWords(Object count) {
    return 'Database verified: $count words';
  }

  @override
  String get loadLoadingWords => 'Loading words …';

  @override
  String get loadLoadingCustomizations => 'Loading your customizations …';

  @override
  String get loadReady => 'Ready!';

  @override
  String get loadDownloading => 'Downloading database …';

  @override
  String loadDownloadBytes(Object size) {
    return 'Downloading … $size MB';
  }

  @override
  String loadDownloadTotal(Object size, Object total) {
    return 'Downloading … $size / $total MB';
  }

  @override
  String loadDownloadComplete(Object size) {
    return 'Download complete ($size MB)';
  }

  @override
  String loadRetrying(Object attempt, Object total) {
    return 'Retrying download (attempt $attempt of $total) …';
  }

  @override
  String get loadPaused => 'Download paused';

  @override
  String get loadResumeReady => 'Ready to resume';

  @override
  String get loadFailed =>
      'The language data could not be loaded. Please try again.';

  @override
  String get loadDecompressionFailed =>
      'The database could not be decompressed. Please try again.';

  @override
  String get loadLoadingProgress => 'Loading your progress …';

  @override
  String get loadLoadingLearning => 'Loading learning data …';

  @override
  String get loadLoadingProfile => 'Loading your profile …';

  @override
  String get downloadPause => 'Pause';

  @override
  String get downloadResume => 'Resume';

  @override
  String get downloadPaused => 'Paused';

  @override
  String get setupWelcome => 'Welcome to Word Universe';

  @override
  String get setupLearningQuestion => 'What language do you want to learn?';

  @override
  String get setupLearningDescription =>
      'Language for words, exercises and games.';

  @override
  String get setupLearningLabel => 'Learning language';

  @override
  String get setupInterfaceQuestion => 'What language should the app use?';

  @override
  String get setupInterfaceDescription =>
      'Language for menus, buttons and instructions.';

  @override
  String get setupInterfaceLabel => 'Interface language';

  @override
  String get setupContinue => 'Continue';

  @override
  String get setupSaveFailed =>
      'Your language choices could not be saved. Please try again.';

  @override
  String get startupFailedTitle => 'Initialization failed';

  @override
  String get startupFailed => 'The app could not be started. Please try again.';

  @override
  String get welcome => 'Discover the Word Universe!';

  @override
  String get startAdventure => 'Start Word Adventure';

  @override
  String get onboardingWelcomeTitle => 'Set up your learning';

  @override
  String get onboardingWelcomeBody =>
      'Choose what you want to practise. You can change everything later in Settings.';

  @override
  String get onboardingLearningLanguage => 'What do you want to learn?';

  @override
  String get onboardingGoal => 'What should practice focus on?';

  @override
  String get onboardingStartBand => 'Choose a starting vocabulary band';

  @override
  String get onboardingBandNote =>
      'These are broad difficulty bands, not school years, ages, or CEFR levels.';

  @override
  String get onboardingDailyTime => 'Daily practice time';

  @override
  String get onboardingContinue => 'Prepare my learning plan';

  @override
  String get goalBalanced => 'Balanced';

  @override
  String get goalVocabulary => 'Vocabulary';

  @override
  String get goalSpelling => 'Spelling';

  @override
  String get goalGrammar => 'Grammar';

  @override
  String get goalDafDaz => 'German as a foreign language';

  @override
  String get dailySessionTitle => 'Today’s learning plan';

  @override
  String dailySessionSubtitle(int minutes) {
    return 'A focused session of about $minutes minutes';
  }

  @override
  String get dailyReviewTitle => 'Review due words';

  @override
  String dailyReviewSubtitle(int count) {
    return '$count words are ready for review';
  }

  @override
  String get dailyWarmupTitle => 'Context warm-up';

  @override
  String get dailyWarmupSubtitle => 'Start with a short sentence exercise';

  @override
  String get dailyGoalTitle => 'Practise your main goal';

  @override
  String get dailyGoalSubtitle =>
      'An exercise selected from your learning goal';

  @override
  String get dailyContextTitle => 'Use words in context';

  @override
  String get dailyContextSubtitle =>
      'Finish with a sentence-completion challenge';

  @override
  String get dailyCompleteTitle => 'Plan complete';

  @override
  String dailyCompleteSummary(int attempts, int mastered) {
    return 'You answered $attempts tracked items and mastered $mastered new items during this plan.';
  }

  @override
  String get dailyPractiseMore => 'Practise more';

  @override
  String get browseAllGames => 'Browse all games';

  @override
  String get focusMode => 'Focus mode';

  @override
  String get focusModeDesc =>
      'Reduce decorative elements and keep learning actions prominent';

  @override
  String get catalogRecommended => 'Recommended';

  @override
  String get catalogFast => 'Quick practice';

  @override
  String get catalogFavorites => 'Favourites';

  @override
  String get catalogRecent => 'Recent';

  @override
  String get catalogAll => 'All games';

  @override
  String get catalogSearch => 'Search games';

  @override
  String get catalogAddFavorite => 'Add to favourites';

  @override
  String get catalogRemoveFavorite => 'Remove from favourites';

  @override
  String get catalogNoGames => 'No games match this view yet.';

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
  String get licensesTitle => 'Licenses';

  @override
  String get viewOssLicenses => 'View open-source licenses';

  @override
  String get downloadDbTitle => 'First-time setup';

  @override
  String downloadDbMessage(String size) {
    return 'The German word database (about $size) will be downloaded once and saved on your device for offline use.';
  }

  @override
  String get downloadDbConfirm => 'Download';

  @override
  String get downloadDbCancel => 'Not now';

  @override
  String get downloadDbDeclined =>
      'The German word database is needed to continue. Tap Retry to download it, or switch to English in Settings.';

  @override
  String get appName => 'Word Universe';

  @override
  String get appLegalese =>
      '© 2025–2026 CrispStrobe\n\nGerman vocabulary database licensed under GPL-3.0 (it includes data derived from childLex); English vocabulary database under CC BY-SA 4.0. Sources: Wiktionary, ConceptNet, OEWN, OpenThesaurus, OdeNet, LiTKey, Tatoeba, Project Gutenberg, childLex, and others. Full attribution in the license entries below.\n\nDatasets: huggingface.co/datasets/cstr/grundwortschatz-voc-de  ·  cstr/grundwortschatz-voc-en\n\nApp code is proprietary.';

  @override
  String get spaceWordRescueTitle => 'Word Rescue';

  @override
  String get spaceWordRescueInstructions =>
      'Rescue words from drifting off into space! Type them in.';

  @override
  String get wordRescueTitle => 'Word Rescue';

  @override
  String get wordRescueCardDescription => 'Type words before they escape!';

  @override
  String get wordRescueTypeWord => 'Type the word to rescue it!';

  @override
  String get wordRescueTypeHere => 'Type here...';

  @override
  String get wordRescueFeedbackPerfect => 'Perfect! Word Rescued! 🚀';

  @override
  String wordRescueFeedbackCommonMistake(String word) {
    return 'Close enough! $word rescued!';
  }

  @override
  String wordRescueFeedbackIncorrect(String word) {
    return 'Too late! The correct word was: $word';
  }

  @override
  String get wordRescueFeedbackLost => 'Word escaped into space! 💫';

  @override
  String wordRescueGameOverStats(int rescued, int total, int percentage) {
    return 'You rescued $rescued out of $total words ($percentage%)';
  }

  @override
  String get wordSnakeTitle => 'Word Snake';

  @override
  String get wordSnakeDescription =>
      'Identify and trace the words: Connect letters in the correct to spell the word.';

  @override
  String get wordSnakeInstructions =>
      'Tap cells in order to form a path that spells the word';

  @override
  String wordSnakeConnectLetters(int count) {
    return 'Connect $count letters';
  }

  @override
  String get wordSnakeReset => 'Reset';

  @override
  String wordSnakePuzzleProgress(int current, int total) {
    return 'Puzzle $current of $total';
  }

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
  String get wordFindDescription =>
      'Spot the hidden words in the letter grid! Drag to mark them.';

  @override
  String get wordFindWordsToFind => 'Words to Find:';

  @override
  String get wordSortTitle => 'Word Sort Game';

  @override
  String get wordSortDescription =>
      'Sort words into categories: nouns, verbs, and adjectives';

  @override
  String get wordSortTitleTimeAttack => 'Word Sort - Time Attack!';

  @override
  String get wordSortCategoryNoun => 'Nouns';

  @override
  String get wordSortCategoryVerb => 'Verbs';

  @override
  String get wordSortCategoryAdjective => 'Adjectives';

  @override
  String get wordSortCorrect => 'Correct! Well done!';

  @override
  String get wordSortIncorrect => 'Not quite right. Let\'s learn!';

  @override
  String get wordSortTimeUp => 'Time\'s up!';

  @override
  String wordSortStreakBonus(int streak) {
    return '🔥 $streak in a row! Bonus points!';
  }

  @override
  String wordSortHintNounArticle(String article, String gender) {
    return 'Correct! You say \'$article\' - the article shows it\'s a $gender noun.';
  }

  @override
  String wordSortHintNounPlural(String singular, String plural) {
    return 'The plural of \'$singular\' is \'$plural\'.';
  }

  @override
  String wordSortHintVerbConjugation(String ich, String du) {
    return 'Correct! Verbs change: \'$ich\', \'$du\' - they conjugate with the person!';
  }

  @override
  String wordSortHintAdjectiveComparison(
      String base, String comparative, String superlative) {
    return 'Adjectives have degrees: $base → $comparative → $superlative';
  }

  @override
  String wordSortWhyNot(String type) {
    return 'No, it\'s not a $type.';
  }

  @override
  String wordSortWhyNoun(String article) {
    return 'It\'s a NOUN because you say \'$article\' - articles go before nouns!';
  }

  @override
  String wordSortNounDeclensionExample(String nominative, String genitive) {
    return 'Nouns change by case: $nominative → $genitive';
  }

  @override
  String wordSortWhyVerb(String forms) {
    return 'It\'s a VERB because it conjugates: $forms';
  }

  @override
  String wordSortWhyAdjective(
      String base, String comparative, String superlative) {
    return 'It\'s an ADJECTIVE because it has comparison forms: $base → $comparative → $superlative';
  }

  @override
  String get wordSortHintLookForArticle =>
      '💡 Hint: Look for the article (der/die/das)!';

  @override
  String wordSortHintArticleExample(String article) {
    return 'This word has the article \'$article\'';
  }

  @override
  String get wordSortHintLookForConjugation =>
      '💡 Hint: Can you say \'ich...\' with this word?';

  @override
  String get wordSortHintLookForComparison =>
      '💡 Hint: Can this word describe something? Can it get \'more\' or \'most\'?';

  @override
  String get wordSortToggleTimeAttack => 'Toggle Time Attack Mode';

  @override
  String get wordSortShowHint => 'Show Hint';

  @override
  String get wordSortTimeAttackComplete => 'Time Attack Complete!';

  @override
  String get score => 'Score';

  @override
  String get correct => 'correct';

  @override
  String get gameOver => 'Game Over';

  @override
  String get backToMenu => 'Back to Menu';

  @override
  String get goBack => 'Go Back';

  @override
  String get playAgain => 'Play Again';

  @override
  String get adaptiveDifficulty => 'Adaptive Difficulty';

  @override
  String get adaptiveDifficultyDesc => 'Adjusts problems based on your skill';

  @override
  String get adjustProblems => 'Adjusts problems based on your skill';

  @override
  String get gameMenu => 'Word Universe';

  @override
  String get level => 'Level';

  @override
  String get lives => 'Hull Integrity';

  @override
  String get time => 'Time';

  @override
  String get incorrect => 'Error!';

  @override
  String get excellent => 'Excellent, Explorer!';

  @override
  String get good => 'Good job!';

  @override
  String get tryAgain => 'Try Again!';

  @override
  String get nextLevel => 'Next Expedition';

  @override
  String get settings => 'Settings';

  @override
  String get sound => 'Sound FX';

  @override
  String get music => 'Music';

  @override
  String get language => 'Language';

  @override
  String get progress => 'Learning Progress';

  @override
  String get achievements => 'Achievements';

  @override
  String get congratulations => 'Congratulations, Explorer!';

  @override
  String missionsCompleted(int count) {
    return 'Expeditions Completed: $count';
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
  String get learningLanguage => 'Learning language';

  @override
  String get learningLanguageDesc =>
      'Choose which vocabulary database games use';

  @override
  String packRequiredTitle(String language) {
    return '$language pack required';
  }

  @override
  String packRequiredMessage(String language, String size) {
    return 'Games need the $language word database (about $size). It is downloaded once and then works offline.';
  }

  @override
  String packDownloadingTitle(String language) {
    return 'Downloading $language';
  }

  @override
  String get packDownloadPreparing => 'Preparing download…';

  @override
  String get packKeepAppOpen =>
      'Please keep the app open until the download finishes.';

  @override
  String packMetaSizeLicense(String size, String license) {
    return '$size download · data licensed under $license';
  }

  @override
  String get packOfflineAfterDownload => 'Works offline once downloaded';

  @override
  String get packFailedTitle => 'Download failed';

  @override
  String get packFailedNetworkHint =>
      'Check your internet connection and try again.';

  @override
  String get packFailedDataHint =>
      'The downloaded file did not pass its integrity check. Trying again usually fixes it.';

  @override
  String packFallbackHint(String language) {
    return 'You can continue in $language and download this pack later in Settings.';
  }

  @override
  String packUseFallback(String language) {
    return 'Continue in $language';
  }

  @override
  String get packRetry => 'Retry';

  @override
  String get languagePacksTitle => 'Language packs';

  @override
  String get languagePacksDesc => 'Vocabulary databases stored on this device';

  @override
  String get packStatusInstalled => 'Downloaded';

  @override
  String get packStatusBundled => 'Included in the app';

  @override
  String get packStatusNotInstalled => 'Not downloaded';

  @override
  String get packStatusInstalling => 'Downloading…';

  @override
  String get packStatusFailed => 'Download failed';

  @override
  String get packInUse => 'In use';

  @override
  String get packDownloadAction => 'Download';

  @override
  String get packGateLoadAction => 'Load language pack';

  @override
  String packMetaSizes(String download, String installed, String license) {
    return '$download download · $installed on this device · data under $license';
  }

  @override
  String packInstallSpace(String download, String required, String license) {
    return '$download download · allow about $required free storage for installation, including temporary copies and a download reserve · data under $license';
  }

  @override
  String packNoSpaceHint(String language, String size) {
    return 'There is not enough free storage. To install $language, allow about $size of free storage, including temporary copies and a download reserve. The installed pack uses less space.';
  }

  @override
  String packResumeProgress(String done, String total) {
    return '$done of $total downloaded — it will continue from here';
  }

  @override
  String get packUseAction => 'Use';

  @override
  String get packRemoveAction => 'Remove';

  @override
  String packRemoveConfirmTitle(String language) {
    return 'Remove $language pack?';
  }

  @override
  String packRemoveConfirmMessage(String language, String size) {
    return 'The $language word database ($size) will be deleted from this device. You can download it again at any time.';
  }

  @override
  String packRemoved(String language) {
    return '$language pack removed';
  }

  @override
  String packMissingBanner(String language) {
    return 'The $language word database is not downloaded yet. Tap to download it.';
  }

  @override
  String packReadyToast(String language) {
    return '$language is ready';
  }

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
  String get difficultyDescGrade3 => 'Everyday words and spelling basics';

  @override
  String get difficultyDescGrade4 => 'Broader vocabulary and basic grammar';

  @override
  String get difficultyDescGrade5 => 'Advanced words, cases, and tenses';

  @override
  String get difficultyDescGrade6 =>
      'Challenging vocabulary and complex grammar';

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
  String get targetAge => 'Who It’s For';

  @override
  String get targetAgeRange => 'German and English learners of different ages';

  @override
  String get aboutApp =>
      'Word Universe helps learners practise vocabulary, spelling, and grammar through engaging space-themed games.';

  @override
  String get debugPanelTitle => 'Debug Panel';

  @override
  String get debugForceUnlock => 'Force Full Unlock';

  @override
  String get debugApplyAndClose => 'Apply & Close';

  @override
  String get parentalGateTitle => 'Quick Check';

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
  String get contactingStore => 'Reaching the Word Universe...';

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
  String packRemoveFailed(String language) {
    return 'Could not remove the $language pack.';
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
  String get preparingMission => 'Preparing your expedition...';

  @override
  String get initializing => 'Initializing the Word Universe...';

  @override
  String get loadingAssets => 'Loading game assets...';

  @override
  String get loadingProgress => 'Loading saved progress...';

  @override
  String get preparingSpaceStation => 'Preparing the Word Universe...';

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

  @override
  String get imprint => 'Imprint / Legal';

  @override
  String get imprintTitle => 'Imprint / Legal.';

  @override
  String get imprintDialog => 'Imprint / Legal..';

  @override
  String get viewLegalNotice => 'Info about the Service Provider...';

  @override
  String get imprintServiceProvider => 'Service Provider';

  @override
  String get imprintProviderAddress =>
      'Christian Ströbele\nNikolausstr. 5\n70190 Stuttgart\nDeutschland/Germany';

  @override
  String get imprintContact => 'Contact';

  @override
  String get imprintContactDetails =>
      'Email: postmaster@crispstro.be\nPhone: 0049 176 6421 8601';

  @override
  String get imprintContentResponsible => 'Responsible for Content';

  @override
  String get imprintDisclaimer => 'Disclaimer';

  @override
  String get imprintDisclaimerText =>
      'This app is provided as is, exclusively for educational and creative purposes, without any liability.';

  @override
  String get imprintWebsite => 'www.crispstro.be';

  @override
  String get taskCustomizationTitle => 'Task Customization';

  @override
  String get taskCustomizationEnable => 'Enable Customization';

  @override
  String get taskCustomizationEnableDesc => 'Filter vocabulary for exercises';

  @override
  String get taskWordLengthTitle => 'Word Length';

  @override
  String taskWordLengthRange(int min, int max) {
    return 'Words with $min to $max letters';
  }

  @override
  String get taskIncludedSourcesTitle => 'Word Sources';

  @override
  String get taskIncludedSourcesDesc =>
      'Only show words from selected sources (empty = all)';

  @override
  String get taskWildcardIncludeTitle => 'Wildcard Filters (Include)';

  @override
  String get taskWildcardIncludeDesc =>
      'Only show words that match (e.g. *ing)';

  @override
  String get taskWildcardExcludeTitle => 'Wildcard Filters (Exclude)';

  @override
  String get taskWildcardExcludeDesc => 'Hide words that match (e.g. un*)';

  @override
  String get taskWildcardHint => 'Add new filter...';

  @override
  String get taskCustomizationWarning =>
      'Filters active! Vocabulary is limited.';

  @override
  String get taskActiveSetTitle => 'Active Vocabulary Set';

  @override
  String get taskActiveSetDesc => 'Overrides all other filters when active.';

  @override
  String get taskActiveSetNone => 'None (Use filters below)';

  @override
  String get taskManageSets => 'Manage Custom Sets';

  @override
  String get taskFiltersDisabled =>
      'The filters below are disabled because a custom set is active.';

  @override
  String get customSetCreateTitle => 'Create New Set';

  @override
  String get customSetEditTitle => 'Edit Set';

  @override
  String get save => 'Save';

  @override
  String get customSetNameRequired => 'Enter a name for this set.';

  @override
  String get customSetSaveFailed =>
      'The set could not be saved. Please try again.';

  @override
  String get languageChangeFailed =>
      'The app language could not be changed. Please try again.';

  @override
  String learningLanguageChanged(String language) {
    return 'Learning language switched to $language';
  }

  @override
  String get learningLanguageChangeFailed =>
      'The learning language could not be changed. Please try again.';

  @override
  String get unexpectedErrorTitle => 'Something went wrong';

  @override
  String get unexpectedErrorMessage =>
      'Please try again. If the problem continues, you can copy the crash log from Diagnostics in Settings.';

  @override
  String get genericErrorTitle => 'Error';

  @override
  String get genericErrorMessage => 'Something went wrong. Please try again.';

  @override
  String get routeNotFoundTitle => 'Page not found';

  @override
  String get routeNotFoundMessage => 'The requested page could not be found.';

  @override
  String get customSetNameLabel => 'Set Name';

  @override
  String get customSetNameHint => 'e.g., \'Tricky Verbs\'';

  @override
  String get customSetDescriptionLabel => 'Description';

  @override
  String get customSetDescriptionHint => 'A short description of this set...';

  @override
  String get customSetTargetGrade => 'Target Level';

  @override
  String get customSetAvailableWords => 'Available Words';

  @override
  String customSetSelectedWords(int count) {
    return 'Selected Words ($count)';
  }

  @override
  String get customSetSearchHint => 'Filter words...';

  @override
  String get customSetAddAll => 'Add All';

  @override
  String get customSetRemoveAll => 'Remove All';

  @override
  String get customSetEmpty => 'No words selected yet.';

  @override
  String get customSetNoAvailable => 'No matching words found.';

  @override
  String get customSetDelete => 'Delete Set';

  @override
  String get customSetDeleteConfirmTitle => 'Delete Set?';

  @override
  String customSetDeleteConfirmContent(String setName) {
    return 'Are you sure you want to delete $setName?';
  }

  @override
  String get wordMemoryDescription =>
      'Find matching word pairs in different fonts';

  @override
  String get wordBuilderDescription => 'Build words from scrambled letters';

  @override
  String get wordWhirlDescription => 'Tap the correct word types in the whirl!';

  @override
  String get wordMemoryTitle => 'Memory';

  @override
  String get wordMemoryComplete => 'Complete!';

  @override
  String get wordMemoryScore => 'Score';

  @override
  String get wordMemoryMoves => 'Moves';

  @override
  String get wordMemoryPairs => 'Pairs';

  @override
  String get wordBuilderTitle => 'Word Builder';

  @override
  String get wordBuilderGameOver => 'Game Over!';

  @override
  String get wordBuilderWords => 'Words';

  @override
  String get wordBuilderTimeBonus => 'Time Bonus';

  @override
  String get wordBuilderBuildWord => 'Build the word:';

  @override
  String get wordBuilderLetters => 'Letters:';

  @override
  String get wordBuilderHint => 'Hint (-10)';

  @override
  String get wordBuilderSkip => 'Skip';

  @override
  String get wordBuilderTime => 'Time';

  @override
  String get wordWhirlTitle => 'Word Type Whirl';

  @override
  String get wordWhirlGameOver => 'Whirl Complete!';

  @override
  String get wordWhirlAccuracy => 'Accuracy';

  @override
  String get wordWhirlBestStreak => 'Best Streak';

  @override
  String get wordWhirlCorrect => 'Correct';

  @override
  String get wordWhirlIncorrect => 'Incorrect';

  @override
  String get wordWhirlStreak => 'Streak';

  @override
  String get wordWhirlRound => 'Round';

  @override
  String wordWhirlTapAll(String wordType) {
    return 'Tap all $wordType!';
  }

  @override
  String get gameReplay => 'Play Again';

  @override
  String get gameDone => 'Done';

  @override
  String get gameScore => 'Score';

  @override
  String get difficultyEasy => 'Easy';

  @override
  String get difficultyNormal => 'Normal';

  @override
  String get difficultyChallenge => 'Challenge';

  @override
  String streakLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get gameTooSlow => 'Too slow!';

  @override
  String gameLevelLine(int level) {
    return 'Level: $level';
  }

  @override
  String gameMaxComboLine(int combo) {
    return 'Max Combo: $combo';
  }

  @override
  String gameCombo(int combo) {
    return 'Combo x$combo';
  }

  @override
  String gameLvlBadge(int level) {
    return 'Lvl $level';
  }

  @override
  String get verbtrennerSeparableTitle => 'Separable Verbs';

  @override
  String get verbtrennerCompoundTitle => 'Noun Compounds';

  @override
  String get verbtrennerSeparatedLabel => 'SEPARATED';

  @override
  String get verbtrennerSeparatedExample => '(stehe auf)';

  @override
  String get verbtrennerTogetherLabel => 'TOGETHER';

  @override
  String get verbtrennerTogetherExample => '(aufstehen)';

  @override
  String get wortbaumeisterSeparatedExample => '(e.g. stehe auf)';

  @override
  String get wortbaumeisterTogetherExample => '(e.g. aufstehen)';

  @override
  String get grossschreibTitle => 'Word Galaxy';

  @override
  String get grossschreibDescription =>
      'Are words in a sentence capitalised or not?';

  @override
  String get grossschreibClickHint => 'Tap the word!';

  @override
  String get grossschreibCheck => 'CHECK';

  @override
  String get grossstadtTitle => 'Upper or lower case?';

  @override
  String get grossstadtCardTitle => 'Noun Sorter';

  @override
  String get grossstadtCardDescription =>
      'Sorting words by capitalisation on the conveyor belt';

  @override
  String get grossstadtCapital => 'UPPER';

  @override
  String get grossstadtLower => 'lower';

  @override
  String get spellingSpotterTitle => 'Spelling Spotter';

  @override
  String get spellingSpotterDescription =>
      'Spot the correctly spelled word — learn common spelling mistakes';

  @override
  String get sentenceCompletionTitle => 'Sentence Completion';

  @override
  String get sentenceCompletionDescription =>
      'Fill in the missing word — practise vocabulary in context';

  @override
  String get definitionQuizTitle => 'Definition Quiz';

  @override
  String get definitionQuizDescription =>
      'Match the definition to the correct word';

  @override
  String get sriReviewTitle => 'Weak Words';

  @override
  String get sriReviewDescription =>
      'Practice your toughest words, ranked by difficulty';

  @override
  String get antonymFlashTitle => 'Antonym Flash';

  @override
  String get antonymFlashDescription =>
      'Tap the opposite — as fast as you can!';

  @override
  String get synonymFlashTitle => 'Synonym Flash';

  @override
  String get synonymFlashDescription =>
      'Tap a word with the same meaning — as fast as you can!';

  @override
  String get translationFlashTitle => 'Translation Flash';

  @override
  String get translationFlashDescription =>
      'Tap the English translation of each German word!';

  @override
  String get syllableCountTitle => 'Syllable Count';

  @override
  String get syllableCountDescription =>
      'How many syllables does the word have? Count them!';

  @override
  String get clozeFlashTitle => 'Cloze Flash';

  @override
  String get clozeFlashDescription =>
      'Fill in the blank — pick the right word for each sentence!';

  @override
  String get expressionFlashTitle => 'Expression Flash';

  @override
  String get expressionFlashDescription =>
      'Complete the German idiom — tap the missing word!';

  @override
  String get hypernymFlashTitle => 'Category Flash';

  @override
  String get hypernymFlashDescription =>
      'Which category does the word belong to?';

  @override
  String get wordClassFlashTitle => 'Word Class Flash';

  @override
  String get wordClassFlashDescription =>
      'Noun, Verb, Adjective or Adverb — pick fast!';

  @override
  String get proverbClozeTitle => 'Proverb Cloze';

  @override
  String get proverbClozeDescription =>
      'Complete the German proverb — tap the missing word!';

  @override
  String get reverseTranslationTitle => 'Reverse Translation';

  @override
  String get reverseTranslationDescription =>
      'An English word appears — find the German word!';

  @override
  String get conjugationDrillTitle => 'Conjugation Drill';

  @override
  String get conjugationDrillDescription =>
      'Pick the right verb form for each pronoun';

  @override
  String get conjugationDrillGameOverTitle => 'Exercise complete';

  @override
  String get conjugationDrillGameOverLabel => 'correct conjugations';

  @override
  String get homophoneDrillTitle => 'Homophone Drill';

  @override
  String get homophoneDrillDescription =>
      'Pick the right spelling — hear vs here, to vs too vs two';

  @override
  String get confusableDrillTitle => 'Word Trap';

  @override
  String get confusableDrillDescription =>
      'Spot the right word — affect vs effect, lose vs loose';

  @override
  String get phrasalVerbPowerTitle => 'Phrasal Verb Power';

  @override
  String get phrasalVerbPowerDescription =>
      'Pick the word that completes the phrasal verb — give ___, take ___';

  @override
  String get phrasalVerbPowerPrompt => 'Which word completes the phrasal verb?';

  @override
  String get phrasalVerbPowerEmpty => 'No phrasal-verb data available yet.';

  @override
  String get phrasalVerbPowerOnboard1 =>
      'Phrasal verbs are a verb plus a little word like up, off or away — give up, take off, look after.';

  @override
  String get phrasalVerbPowerOnboard2 =>
      'A sentence with a missing word is shown. Tap the word that completes the phrasal verb.';

  @override
  String get phrasalVerbPowerOnboard3 =>
      'After each answer you\'ll see what the phrasal verb means.';

  @override
  String get phrasalVerbMatchTitle => 'Phrasal Verb Match';

  @override
  String get phrasalVerbMatchDescription =>
      'Match the phrasal verb to its meaning — give up, take off, look after';

  @override
  String get phrasalVerbMatchPrompt => 'What does this phrasal verb mean?';

  @override
  String get phrasalVerbMatchEmpty => 'No phrasal-verb data available yet.';

  @override
  String get phrasalVerbMatchOnboard1 =>
      'A phrasal verb is shown — sometimes with an example sentence for context.';

  @override
  String get phrasalVerbMatchOnboard2 =>
      'Tap the meaning that matches the phrasal verb. The other choices are real meanings of different phrasal verbs.';

  @override
  String get phrasalVerbMatchOnboard3 =>
      'Reading the example can help you work out the meaning.';

  @override
  String get falseFriendsTitle => 'False Friends';

  @override
  String get falseFriendsDescription =>
      'Don\'t get tricked — gift ≠ Gift, become ≠ bekommen';

  @override
  String get falseFriendsPrompt => 'What does this English word really mean?';

  @override
  String get falseFriendsEmpty => 'No false-friend data available yet.';

  @override
  String get falseFriendsOnboard1 =>
      'False friends are English words that look like a German word but mean something different — \"gift\" is not \"Gift\".';

  @override
  String get falseFriendsOnboard2 =>
      'Pick the real German meaning. One choice is the look-alike trap!';

  @override
  String get falseFriendsOnboard3 =>
      'After each answer you\'ll see the real meaning and the trap explained.';

  @override
  String falseFriendsExplain(String english, String correctMeaning,
      String german, String germanMeans) {
    return '$english = $correctMeaning — not “$german” ($germanMeans)!';
  }

  @override
  String get wortfalleTitle => 'Word Trap (DE)';

  @override
  String get wortfalleDescription =>
      'Pick the right word — das/dass, seit/seid, Lärche/Lerche';

  @override
  String get wortfallePrompt => 'Which word fits?';

  @override
  String get wortfalleOnboard1 =>
      'Some German words look or sound almost the same but mean different things — das/dass, seit/seid, Lärche/Lerche.';

  @override
  String get wortfalleOnboard2 =>
      'A sentence with a gap is shown. Pick the word that fits the meaning.';

  @override
  String get wortfalleOnboard3 =>
      'After each answer you\'ll see what each word means.';

  @override
  String get gameRoundComplete => 'Round complete!';

  @override
  String get gameBack => 'Back';

  @override
  String get gamePlayAgain => 'Play again';

  @override
  String gameCorrectOfTotal(int correct, int total) {
    return '$correct of $total correct';
  }

  @override
  String get wortbaumeisterCardTitle => 'Wort-Stückler';

  @override
  String get wortbaumeisterCardDescription =>
      'Build compound nouns piece by piece';

  @override
  String get verbtrennerCardTitle => 'Verb-Trenner';

  @override
  String get verbtrennerCardDescription =>
      'Recognise separable verbs: together or apart?';

  @override
  String achievementsBannerProgress(int unlocked, int total) {
    return '$unlocked of $total achievements unlocked';
  }

  @override
  String get achievementTriangleWizardTitle => 'Word-Snake Master';

  @override
  String get achievementTriangleWizardDesc => 'Reach Level 3 in Word Snake.';

  @override
  String get achievementBubblePopperTitle => 'Sorting Champion';

  @override
  String get achievementBubblePopperDesc => 'Reach Level 3 in Word Sort.';

  @override
  String get achievementPuzzleSolverTitle => 'Word Finder';

  @override
  String get achievementPuzzleSolverDesc => 'Reach Level 3 in Word Find.';

  @override
  String get achievementNumberWallsProTitle => 'Word Builder';

  @override
  String get achievementNumberWallsProDesc => 'Reach Level 3 in Word Builder.';

  @override
  String get achievementCodebreakerProTitle => 'Space Rescuer';

  @override
  String get achievementCodebreakerProDesc =>
      'Reach Level 3 in Space Word Rescue.';

  @override
  String get achievementMasterBuilderTitle => 'Master Builder';

  @override
  String get achievementMasterBuilderDesc => 'Reach Level 3 in Wortbaumeister.';

  @override
  String get achievementCityPlannerTitle => 'City Planner';

  @override
  String get achievementCityPlannerDesc => 'Reach Level 3 in Word Sorter.';

  @override
  String get achievementConnectionExpertTitle => 'Galaxy Expert';

  @override
  String get achievementConnectionExpertDesc => 'Reach Level 3 in Word Galaxy.';

  @override
  String get achievementArithmeticAceTitle => 'Memory Ace';

  @override
  String get achievementArithmeticAceDesc =>
      'Reach Level 5 in Memory and Word Whirl.';

  @override
  String get achievementVielseitigTitle => 'Versatile';

  @override
  String get achievementVielseitigDesc => 'Play at least four different games.';

  @override
  String get achievementAntonymAceTitle => 'Antonym Ace';

  @override
  String get achievementAntonymAceDesc =>
      'Reach game level 3 in Antonym Flash.';

  @override
  String get achievementSynonymScholarTitle => 'Synonym Scholar';

  @override
  String get achievementSynonymScholarDesc =>
      'Reach game level 3 in Synonym Flash.';

  @override
  String get achievementClozeMasterTitle => 'Cloze Master';

  @override
  String get achievementClozeMasterDesc => 'Reach game level 3 in Cloze Flash.';

  @override
  String get achievementTranslationTitanTitle => 'Translation Titan';

  @override
  String get achievementTranslationTitanDesc =>
      'Reach game level 3 in Translation Flash.';

  @override
  String get achievementReverseLinguistTitle => 'Reverse Linguist';

  @override
  String get achievementReverseLinguistDesc =>
      'Reach game level 3 in Reverse Translation.';

  @override
  String get achievementSyllableCounterTitle => 'Syllable Counter';

  @override
  String get achievementSyllableCounterDesc =>
      'Reach game level 3 in Syllable Count.';

  @override
  String get achievementExpressionExpertTitle => 'Expression Expert';

  @override
  String get achievementExpressionExpertDesc =>
      'Reach game level 3 in Expression Flash.';

  @override
  String get achievementHypernymHunterTitle => 'Hypernym Hunter';

  @override
  String get achievementHypernymHunterDesc =>
      'Reach game level 3 in Hypernym Flash.';

  @override
  String get achievementWordClassWhizTitle => 'Word Class Whiz';

  @override
  String get achievementWordClassWhizDesc =>
      'Reach game level 3 in Word Class Flash.';

  @override
  String get achievementProverbSageTitle => 'Proverb Sage';

  @override
  String get achievementProverbSageDesc =>
      'Reach game level 3 in Proverb Cloze.';

  @override
  String get achievementConjugationKingTitle => 'Conjugation King';

  @override
  String get achievementConjugationKingDesc =>
      'Reach game level 3 in Conjugation Drill.';

  @override
  String get achievementVerbSplitterTitle => 'Verb Splitter';

  @override
  String get achievementVerbSplitterDesc =>
      'Reach game level 3 in Verbtrenner.';

  @override
  String get achievementDefinitionWizardTitle => 'Definition Wizard';

  @override
  String get achievementDefinitionWizardDesc =>
      'Reach game level 3 in Definition Quiz.';

  @override
  String get achievementSentenceSmithTitle => 'Sentence Smith';

  @override
  String get achievementSentenceSmithDesc =>
      'Reach game level 3 in Sentence Completion.';

  @override
  String get achievementSpellingSleutTitle => 'Spelling Sleuth';

  @override
  String get achievementSpellingSleutDesc =>
      'Reach game level 3 in Spelling Spotter.';

  @override
  String get achievementHomophoneHeroTitle => 'Homophone Hero';

  @override
  String get achievementHomophoneHeroDesc =>
      'Reach game level 3 in Homophone Drill.';

  @override
  String get achievementConfusableProTitle => 'Confusable Pro';

  @override
  String get achievementConfusableProDesc =>
      'Reach game level 3 in Confusable Drill.';

  @override
  String get achievementReviewRegularTitle => 'Review Regular';

  @override
  String get achievementReviewRegularDesc => 'Reach game level 5 in Review.';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsSubtitle => 'View crash log (stays on device)';

  @override
  String get diagnosticsNoCrashes => 'No crashes recorded. 🎉';

  @override
  String diagnosticsReportsOnDevice(int count) {
    return 'Crash reports on this device: $count. Data stays here unless you share it.';
  }

  @override
  String get diagnosticsCopied => 'Crash log copied to clipboard';

  @override
  String get diagnosticsCopyLog => 'Copy log';

  @override
  String get diagnosticsClearLog => 'Clear log';

  @override
  String get parentDashboardTitle => 'Learning insights';

  @override
  String get parentDashboardSubtitle =>
      'Detailed progress, optionally PIN-protected';

  @override
  String get privacyTitle => 'Privacy';

  @override
  String get privacySubtitle => 'What is stored on this device';

  @override
  String get deleteAllDataTitle => 'Delete All Data';

  @override
  String get deleteAllDataSubtitle => 'Reset progress on this device';

  @override
  String get noSourcesFound => 'No sources found';

  @override
  String get noCustomSetsYet => 'No custom sets created yet.';

  @override
  String get antonymFlashPrompt => 'Opposite of …';

  @override
  String get syllableCountPrompt => 'How many syllables?';

  @override
  String get wordClassFlashPrompt => 'What word class?';

  @override
  String get noAntonymData => 'No antonym data available at this level.';

  @override
  String correctInSeconds(int n) {
    return 'correct in ${n}s';
  }

  @override
  String get parentPinTitle => 'Insights PIN';

  @override
  String parentPinHelp(String pin) {
    return 'Enter the 4-digit code.\nDefault is $pin until you change it.';
  }

  @override
  String get parentPinWrong => 'Wrong code';

  @override
  String get parentPinUnlock => 'Unlock';

  @override
  String get parentChangePin => 'Change insights PIN';

  @override
  String get parentChangePinDialogTitle => 'Change PIN';

  @override
  String get parentNewPinLabel => 'New PIN';

  @override
  String get parentConfirmPinLabel => 'Confirm';

  @override
  String get parentPinRequireFour => '4 digits required';

  @override
  String get parentPinMismatch => 'Does not match';

  @override
  String get parentPinUpdated => 'PIN updated';

  @override
  String get parentSectionLanguageMastery => 'Language mastery';

  @override
  String get parentItemsTracked => 'Items tracked';

  @override
  String get parentItemsMastered => 'Of these mastered';

  @override
  String parentItemsMasteredValue(int count, int pct) {
    return '$count ($pct%)';
  }

  @override
  String get parentItemsDue => 'Due for review';

  @override
  String get parentSectionStrengths => 'Strengths & weaknesses';

  @override
  String get parentDataBasis => 'Data basis';

  @override
  String get parentNoDataYet => 'no data yet';

  @override
  String get parentStrongestCategory => 'Strongest category';

  @override
  String get parentWeakestCategory => 'Weakest category';

  @override
  String parentCategoryValue(String name, int pct) {
    return '$name ($pct%)';
  }

  @override
  String get parentTotalAttempts => 'Total attempts';

  @override
  String get parentSectionGameProgress => 'Game progress';

  @override
  String get parentGamesPlayed => 'Games played';

  @override
  String get parentNoneYet => 'none yet';

  @override
  String parentLevelValue(int level) {
    return 'Level $level';
  }

  @override
  String get cognitiveProfileTitle => 'Learning profile';

  @override
  String get cognitiveProfileEmpty =>
      'Play a few rounds to build up your profile.';

  @override
  String cognitiveProfileAttempts(int attempts, int areas) {
    String _temp0 = intl.Intl.pluralLogic(
      areas,
      locale: localeName,
      other: '$areas skill areas',
      one: '1 skill area',
    );
    return '$attempts attempts in $_temp0';
  }

  @override
  String get categorySpelling => 'Spelling';

  @override
  String get categoryGrammar => 'Grammar';

  @override
  String get categoryVocabulary => 'Vocabulary';

  @override
  String get categoryTextComprehension => 'Reading comprehension';

  @override
  String get categoryExpression => 'Expression';

  @override
  String get wordSortOnboardingTitle => 'Word Sort';

  @override
  String get wordSortOnboardingDrag =>
      'Drag the word to the matching word-type category.';

  @override
  String get wordSortOnboardingBuildingBlocks =>
      'Nouns, verbs and adjectives are the building blocks. Higher levels add adverbs and pronouns.';

  @override
  String get wordSortOnboardingHints =>
      'Need help? Wait a moment — the game will show hints for the current word after a short delay.';

  @override
  String get wordSortCategoryAdverb => 'Adverbs';

  @override
  String get wordSortCategoryPronoun => 'Pronouns';

  @override
  String get fontFamilyTitle => 'Font';

  @override
  String get fontFamilySubtitle => 'Choose a font for learning content';

  @override
  String get skip => 'Skip';

  @override
  String get gotIt => 'Got it';

  @override
  String get next => 'Next';

  @override
  String get debugModeEnabled => 'Debug Mode Enabled!';

  @override
  String get synonymFlashPrompt => 'Synonym for …';

  @override
  String get noSynonymData => 'No synonym data available at this level.';

  @override
  String get noClozeSentences =>
      'No example sentences available at this level.';

  @override
  String clozeAnswer(String word) {
    return 'Answer: $word';
  }

  @override
  String get sriReviewHeader => 'Review';

  @override
  String get reviewNoWordsYet =>
      'No words to review yet.\nPlay a few rounds so the system can identify your weak spots!';

  @override
  String get difficultyVeryHard => 'Very hard';

  @override
  String get difficultyHard => 'Difficult';

  @override
  String get difficultyPractice => 'Practice';

  @override
  String get challengeTypeArticle => 'Choose article';

  @override
  String get challengeTypeSpelling => 'Correct spelling';

  @override
  String get challengeTypeDefinition => 'Which word matches?';

  @override
  String articleChallengePrompt(String word) {
    return 'Which article?\n\"___ $word\"';
  }

  @override
  String get wordOfTheDay => 'Word of the Day';

  @override
  String get pronounce => 'Pronounce';

  @override
  String get tapToPractise => 'Tap to practise →';

  @override
  String gradeLabel(int grade) {
    return 'Vocabulary level $grade';
  }

  @override
  String get sectionDefinitions => 'Definitions';

  @override
  String get sectionExamples => 'Examples';

  @override
  String get sectionSynonyms => 'Synonyms';

  @override
  String get sectionAntonyms => 'Antonyms';

  @override
  String get didYouKnow => 'Did you know?';

  @override
  String get practiceNow => 'Practice now';

  @override
  String get karteikasten => 'Flashcard Box';

  @override
  String karteikastenCardMoved(int box, String label) {
    return 'Card moved to Box $box – $label';
  }

  @override
  String boxLabel(int n) {
    return 'Box $n';
  }

  @override
  String get boxLabelCurrent => '(current)';

  @override
  String get moveCard => 'Move';

  @override
  String get boxEmptyMastered => 'No mastered cards in this box yet.';

  @override
  String get boxEmptyDefault => 'This box is empty.';

  @override
  String get antonymFlashOnboardingBody1 =>
      'A word appears — tap its opposite as fast as you can.';

  @override
  String get hypernymFlashOnboardingBody1 =>
      'A word appears — tap the correct category as fast as you can.';

  @override
  String get noHypernymData => 'No category data available at this level.';

  @override
  String get hypernymFlashPrompt => 'Category for …';

  @override
  String spellingForDefinition(String definition) {
    return 'Correct spelling for:\n\"$definition\"';
  }

  @override
  String get conjugationDrillOnboardingBody1 =>
      'A verb and a personal pronoun are shown — choose the correct present tense form.';

  @override
  String get conjugationDrillOnboardingBody2 =>
      'All four options are forms of the same pronoun from different verbs.';

  @override
  String get conjugationDrillOnboardingBody3 =>
      'This game focuses on German: English verbs barely change in present tense — only the third person singular differs.';

  @override
  String get spellingSpotterOnboardingBody1 =>
      'Four words are shown — one is spelled correctly, the others contain common mistakes.';

  @override
  String get spellingSpotterOnboardingBody2 =>
      'Words are sorted by difficulty based on real learner spelling errors.';

  @override
  String correctAnswerReveal(String word) {
    return 'Correct answer: $word';
  }

  @override
  String get exampleLabel => 'Example:';

  @override
  String get definitionQuizPrompt => 'Which word is being described?';

  @override
  String get noDefinitionData => 'No definitions available at this level.';

  @override
  String get definitionQuizOnboardingBody1 =>
      'A definition is shown — pick the matching word from four options.';

  @override
  String get definitionQuizOnboardingBody2 =>
      'All options come from the same CEFR level so nothing is too obvious.';

  @override
  String get definitionQuizOnboardingBody3 =>
      'From vocabulary level 5, a language note appears after a correct answer.';

  @override
  String get sentenceCompletionPrompt => 'Which word completes the sentence?';

  @override
  String get sentenceCompletionOnboardingBody1 =>
      'A sentence with a gap is shown — pick the word that fits.';

  @override
  String get sentenceCompletionOnboardingBody2 =>
      'Only nouns, verbs, and adjectives are tested — they are uniquely identifiable in context.';

  @override
  String get sentenceCompletionOnboardingBody3 =>
      'A meaning hint appears after each correct answer.';

  @override
  String get spellingSpotterPrompt => 'Which one is spelled correctly?';

  @override
  String get noSpellingData => 'No spelling data available at this level.';

  @override
  String get synonymFlashOnboardingBody1 =>
      'A word appears — tap a word with the same meaning as fast as you can.';

  @override
  String get synonymFlashOnboardingTimer =>
      'You have 30 seconds. More correct answers means a better score.';

  @override
  String get clozeFlashOnboardingBody1 =>
      'A sentence appears with a missing word — tap the correct answer.';

  @override
  String get clozeFlashOnboardingTimer =>
      'You have 30 seconds. Read the context — it helps!';

  @override
  String get sriReviewOnboardingBody1 =>
      'Practice your weakest words — selected based on your learning history.';

  @override
  String get sriReviewOnboardingBody2 =>
      'Each challenge adapts to the word: article, spelling, or definition.';

  @override
  String get sriReviewOnboardingBody3 =>
      'Every correct answer raises the easiness factor of that word.';

  @override
  String get semanticsBack => 'Go back';

  @override
  String semanticsScore(int n) {
    return 'Score: $n';
  }

  @override
  String semanticsProgress(int done, int total) {
    return 'Progress: $done of $total';
  }

  @override
  String semanticsCombo(int n) {
    return 'Combo x$n';
  }

  @override
  String get syllableCountOnboardingBody1 =>
      'A word appears — tap how many syllables it has.';

  @override
  String get syllableCountOnboardingTimer =>
      'You have 30 seconds. Say the word aloud to feel its syllables.';

  @override
  String get noSyllableData => 'No syllable data available at this level.';

  @override
  String get wordClassFlashOnboardingBody1 =>
      'A word appears — tap its word class as fast as you can.';

  @override
  String get wordClassFlashOnboardingTimer =>
      'You have 30 seconds. Noun, Verb, Adjective or Adverb?';

  @override
  String get wordClassFlashOnboardingTip =>
      'Think about the word\'s meaning and form.';

  @override
  String get noWordClassData => 'No word class data available at this level.';

  @override
  String get wordTypeNoun => 'Noun';

  @override
  String get wordTypeVerb => 'Verb';

  @override
  String get wordTypeAdjective => 'Adjective';

  @override
  String get wordTypeAdverb => 'Adverb';

  @override
  String get wordTypePronoun => 'Pronoun';

  @override
  String get wordSortHintCorrect => '✓ Correct!';

  @override
  String get wordSortHintWrong => '✗ Wrong!';

  @override
  String wordSortHintNotA(String type) {
    return '✗ Not a $type!';
  }

  @override
  String wordSortHintSynonym(String synonyms) {
    return '✓ Also: $synonyms';
  }

  @override
  String wordSortHintAntonym(String antonym) {
    return '✓ Opposite: $antonym';
  }

  @override
  String wordSortHintNounNaming(String word) {
    return '✓ Noun: $word (a naming word)';
  }

  @override
  String wordSortHintVerbAction(String word) {
    return '✓ Verb: $word → action or state';
  }

  @override
  String wordSortHintAdjQuality(String word) {
    return '✓ Adjective: $word → describes a quality';
  }

  @override
  String wordSortHintAdjQuestion(String word) {
    return '✓ Answers \"What is it like?\" → $word';
  }

  @override
  String wordSortHintAdverbAction(String word) {
    return '✓ Adverb: $word → tells how/when/where';
  }

  @override
  String wordSortHintAdverbQuestion(String word) {
    return '✓ Answers: how? when? where? → $word';
  }

  @override
  String wordSortHintPronounReplaces(String word) {
    return '✓ Pronoun: $word → replaces a noun';
  }

  @override
  String wordSortHintPronounStands(String word) {
    return '✓ $word → stands for a noun or noun phrase';
  }

  @override
  String wordSortDragLabel(String word) {
    return 'Word: $word. Drag it to the correct word class.';
  }

  @override
  String wordSortHintCorrectAs(String word, String type) {
    return '✓ Correct: $word is a $type!';
  }

  @override
  String get homophoneTitleHomophone => 'Homophone Drill';

  @override
  String get homophoneTitleTrap => 'Word Trap';

  @override
  String get homophoneOnboardHomophone1 =>
      'Homophones sound the same but are spelled differently — \"hear\" vs \"here\", \"to\" vs \"too\" vs \"two\".';

  @override
  String get homophoneOnboardHomophone2 =>
      'A sentence with a missing word is shown. Pick the spelling that fits the meaning.';

  @override
  String get homophoneOnboardHomophone3 =>
      'After each answer a meaning hint reveals what makes each spelling unique.';

  @override
  String get homophoneOnboardConfusable1 =>
      'Some words look or sound similar but mean different things — \"affect\" vs \"effect\", \"loose\" vs \"lose\".';

  @override
  String get homophoneOnboardConfusable2 =>
      'A sentence with a missing word is shown. Pick the word whose meaning fits the context.';

  @override
  String get homophoneOnboardConfusable3 =>
      'After each answer you\'ll see a clear explanation of what makes each word distinct.';

  @override
  String get homophoneEmpty => 'No homophone data available for this level.';

  @override
  String get homophonePromptHomophone => 'Which word fits?';

  @override
  String get homophonePromptConfusable => 'Which word is correct here?';

  @override
  String get homophoneMeanings => 'Meanings';

  @override
  String get homophoneSubtitleHomophone => 'correct homophones';

  @override
  String get homophoneSubtitleTrap => 'correct words';

  @override
  String wordBuilderHintsUsed(int count) {
    return '$count used';
  }

  @override
  String wordBuilderLevelLabel(int level) {
    return 'Level $level';
  }

  @override
  String wordBuilderLevelShort(int level) {
    return 'Lvl $level';
  }

  @override
  String wordBuilderWordsProgress(int done, int total) {
    return 'Words: $done of $total';
  }

  @override
  String wordBuilderLetterTile(String letter) {
    return 'Letter tile $letter';
  }

  @override
  String get wordBuilderTileHint => 'Tap or drag into the word area';

  @override
  String wordBuilderTimeRemaining(int seconds) {
    return 'Time: $seconds seconds';
  }

  @override
  String get wordSnakeResetSelection => 'Reset selection';

  @override
  String wordSnakeScoreLabel(int score) {
    return 'Points: $score';
  }

  @override
  String wordSnakeCell(String letter) {
    return 'Letter $letter';
  }

  @override
  String wordSnakeCellSelected(String letter, int position) {
    return 'Letter $letter, position $position';
  }

  @override
  String get wordSnakeNoPuzzles =>
      'No puzzle could be made right now. Please try another level or come back later.';

  @override
  String get wordSnakeBasicVocabulary => '⭐ Core vocabulary';

  @override
  String get wordSnakeNoun => 'Noun (naming word)';

  @override
  String wordSnakeNounWithArticle(String article) {
    return 'Noun ($article)';
  }

  @override
  String wordSnakeGenus(String genus) {
    return 'Gender: $genus';
  }

  @override
  String wordSnakePlural(String plural) {
    return 'Plural: $plural';
  }

  @override
  String get wordSnakeVerb => 'Verb (action word)';

  @override
  String wordSnakeVerbForms(String ich, String du, String er) {
    return 'e.g. ich $ich, du $du, er $er';
  }

  @override
  String wordSnakeForms(String forms) {
    return 'Forms: $forms';
  }

  @override
  String get wordSnakeAdjective => 'Adjective (describing word)';

  @override
  String get wordSnakeAdjectivePositive => 'Adjective (positive)';

  @override
  String wordSnakeComparison(String forms) {
    return 'Comparison: $forms';
  }

  @override
  String get wordSnakePronoun => 'Pronoun';

  @override
  String get wordSnakeArticle => 'Article';

  @override
  String get wordSnakeAdverb => 'Adverb';

  @override
  String get wordSnakePreposition => 'Preposition';

  @override
  String get wordSnakeConjunction => 'Conjunction';

  @override
  String get wordSnakeParticle => 'Particle';

  @override
  String get wordSnakeNumeral => 'Numeral';

  @override
  String get wordSnakeCaseNominative => 'Nominative';

  @override
  String get wordSnakeCaseAccusative => 'Accusative';

  @override
  String get wordSnakeCaseDative => 'Dative';

  @override
  String get wordSnakeCaseGenitive => 'Genitive';

  @override
  String wordSnakeExample(String example) {
    return 'e.g.: $example';
  }

  @override
  String get rescueHintHeardAgain => 'Listened to the word again!';

  @override
  String rescueHintStartsWith(String prefix) {
    return 'Starts with: $prefix...';
  }

  @override
  String rescueHintLetterCount(int count) {
    return '$count letters';
  }

  @override
  String rescueBestStreak(int count) {
    return 'Best streak: $count 🔥';
  }

  @override
  String rescueSemanticsScore(int score) {
    return 'Score: $score';
  }

  @override
  String rescueSemanticsStreak(int count) {
    return 'Streak: $count';
  }

  @override
  String rescueSemanticsRescued(int rescued, int total) {
    return 'Rescued: $rescued of $total';
  }

  @override
  String rescueSemanticsLevel(int level) {
    return 'Level $level';
  }

  @override
  String get rescueSemanticsInputField => 'Type the word here';

  @override
  String get rescueSemanticsShowHint => 'Show hint';

  @override
  String get rescueSemanticsReadWord => 'Read word aloud';

  @override
  String wordMemoryScoreLabel(int score) {
    return 'Points: $score';
  }

  @override
  String wordMemoryMovesLabel(int moves) {
    return 'Moves: $moves';
  }

  @override
  String wordMemoryPairsLabel(int found, int total) {
    return 'Pairs: $found of $total';
  }

  @override
  String wordMemoryTotalGemsLabel(int gems) {
    return 'Total gems: $gems';
  }

  @override
  String wordMemoryCardMatched(String text) {
    return 'Card $text, matched';
  }

  @override
  String wordMemoryCardRevealed(String text) {
    return 'Card $text, revealed';
  }

  @override
  String get wordMemoryCardHidden => 'Hidden card';

  @override
  String wordSortDropZoneLabel(String label) {
    return 'Drop zone: $label';
  }

  @override
  String get wordSortEmptyTitle => 'No words available';

  @override
  String get wordSortEmptyMessage =>
      'There are no words to sort for this level yet. Try another level or come back later.';

  @override
  String get wordSortGenderMasculine => 'masculine (der)';

  @override
  String get wordSortGenderFeminine => 'feminine (die)';

  @override
  String get wordSortGenderNeuter => 'neuter (das)';

  @override
  String wordSortHintNounPluralForm(String word, String plural) {
    return '✓ Plural: $word → $plural';
  }

  @override
  String wordSortHintNounGender(String gender) {
    return '✓ Gender: $gender';
  }

  @override
  String wordSortHintNounWithArticle(String article, String word) {
    return '✓ Noun: $article $word';
  }

  @override
  String wordSortHintDefinition(String definition) {
    return '✓ $definition';
  }

  @override
  String wordSortHintVerbPersonalForms(String ich, String du) {
    return '✓ Personal forms: ich $ich, du $du';
  }

  @override
  String wordSortHintVerbPerfect(String form) {
    return '✓ Perfect: $form';
  }

  @override
  String wordSortHintVerbPast(String form) {
    return '✓ Past: ich $form';
  }

  @override
  String wordSortHintAdjComparison(
      String word, String comparative, String superlative) {
    return '✓ Comparison: $word → $comparative → $superlative';
  }

  @override
  String wordSortHintAdjComparative(String word, String comparative) {
    return '✓ Comparative: $word → $comparative';
  }

  @override
  String wordSortExplainCategoryDefinition(String category, String definition) {
    return '✓ $category: \"$definition\"';
  }

  @override
  String wordSortExplainCategory(String word, String category) {
    return '✓ $word → $category';
  }

  @override
  String get wordSortReasonNotConjugable => 'not conjugable';

  @override
  String get wordSortReasonNotComparable => 'not comparable';

  @override
  String wordSortReasonPlural(String plural) {
    return 'plural: $plural';
  }

  @override
  String wordSortExplainNounCapitalized(String word) {
    return '✓ $word → Noun (capitalized!)';
  }

  @override
  String wordSortExplainNounNaming(String word) {
    return '✓ $word → Noun (a naming word)';
  }

  @override
  String wordSortExplainNounReasons(String reasons) {
    return '✓ Noun: $reasons';
  }

  @override
  String wordSortReasonVerbForms(String ich, String du) {
    return 'ich $ich, du $du';
  }

  @override
  String wordSortReasonVerbFormExample(String ich) {
    return 'e.g. ich $ich';
  }

  @override
  String get wordSortReasonNoArticle => 'no article';

  @override
  String wordSortExplainVerbAction(String word) {
    return '✓ Verb: $word → action!';
  }

  @override
  String wordSortExplainVerbReasons(String reasons) {
    return '✓ Verb: $reasons';
  }

  @override
  String wordSortExplainVerbDefinition(String definition) {
    return '✓ Verb: \"$definition\"';
  }

  @override
  String wordSortReasonComparable(String comparative) {
    return 'comparable: $comparative';
  }

  @override
  String wordSortReasonAdjExample(String word) {
    return 'the $word thing';
  }

  @override
  String wordSortExplainAdjReasons(String reasons) {
    return '✓ Adjective: $reasons';
  }

  @override
  String wordSortExplainAdjDefinition(String definition) {
    return '✓ Adjective: \"$definition\"';
  }

  @override
  String wordSortExplainAdjQuality(String word) {
    return '✓ Adjective: $word → describes a quality';
  }

  @override
  String wordTypeWhirlSemanticsLevel(int level) {
    return 'Level $level';
  }

  @override
  String wordTypeWhirlSemanticsRound(int round, int total) {
    return 'Round $round of $total';
  }

  @override
  String wordTypeWhirlSemanticsStreak(int streak) {
    return 'Streak: $streak';
  }

  @override
  String wordTypeWhirlSemanticsTime(int seconds) {
    return 'Time: $seconds seconds';
  }

  @override
  String wordTypeWhirlSemanticsGems(int gems) {
    return 'Gems: $gems';
  }

  @override
  String wordTypeWhirlSemanticsWord(String word) {
    return 'Word $word';
  }

  @override
  String wordTypeWhirlSemanticsTapHint(String wordType) {
    return 'Tap if it is a $wordType';
  }

  @override
  String get wordFindPluralLabel => 'Plural';

  @override
  String get wordFindVerbFormInfinitive => 'Infinitive';

  @override
  String get wordFindVerbFormFinite => 'finite';

  @override
  String get wordFindVerbFormParticiple => 'Participle';

  @override
  String get translationFlashNoData =>
      'No translation data available for this level.';

  @override
  String get translationFlashPrompt => 'In English …';

  @override
  String translationFlashCorrectCount(int count) {
    return '$count correct';
  }

  @override
  String get translationFlashOnboardingTap =>
      'A German word appears — tap the correct English translation quickly.';

  @override
  String translationFlashOnboardingTimer(int seconds) {
    return 'You have $seconds seconds. The more correct answers, the better your score.';
  }

  @override
  String get expressionFlashOnboardingTap =>
      'An idiom appears with a gap — tap the missing word.';

  @override
  String get expressionFlashOnboardingTimer =>
      'You have 30 seconds. Know your idioms!';

  @override
  String get expressionFlashEmpty => 'No idioms available for this level.';

  @override
  String expressionFlashCorrectCount(int n) {
    return '$n correct';
  }

  @override
  String get expressionFlashLabel => 'Idiom';

  @override
  String get expressionFlashBlankHint => 'Gap — find the missing word';

  @override
  String get proverbClozeOnboardingBody =>
      'A proverb appears with a gap — tap the correct word.';

  @override
  String proverbClozeOnboardingTimer(int seconds) {
    return '$seconds seconds — as many proverbs as you can!';
  }

  @override
  String get proverbClozeEmpty => 'No proverb data available for this level.';

  @override
  String proverbClozeCorrectCount(int count) {
    return '$count correct';
  }

  @override
  String get proverbClozeLabel => 'Proverb';

  @override
  String get conjugationDrillPrompt => 'What is the present-tense form?';

  @override
  String get conjugationDrillNoData =>
      'No conjugation data available for this level.';

  @override
  String grossschreibSemLevel(int level) {
    return 'Level $level';
  }

  @override
  String grossschreibSemScore(int score) {
    return 'Points: $score';
  }

  @override
  String grossschreibSemProgress(int done, int total) {
    return 'Progress: $done of $total';
  }

  @override
  String grossschreibSemCombo(int combo) {
    return 'Combo times $combo';
  }

  @override
  String grossschreibSemWord(String word) {
    return 'Word: $word. Tap to change the spelling.';
  }

  @override
  String spellingSpotterCommonMistakes(String errors) {
    return 'Common mistakes: $errors';
  }

  @override
  String get skillLabelSpelling => 'Spelling';

  @override
  String get skillLabelArticle => 'Article';

  @override
  String get skillLabelPlural => 'Plural';

  @override
  String get skillLabelWordType => 'Word type';

  @override
  String get skillLabelSentence => 'Sentence';

  @override
  String get skillLabelPunctuation => 'Punctuation';

  @override
  String get skillLabelCapitalization => 'Capitalization';

  @override
  String get skillLabelConjugation => 'Conjugation';

  @override
  String get skillLabelCase => 'Case';

  @override
  String get skillLabelVocabulary => 'Vocabulary';

  @override
  String get skillLabelReading => 'Reading';

  @override
  String get boxNameNew => 'New';

  @override
  String get boxNameFirstReview => 'First Review';

  @override
  String get boxNamePractice => 'Practice';

  @override
  String get boxNameConfident => 'Confident';

  @override
  String get boxNameMastered => 'Mastered';

  @override
  String get privacyBriefTitle => 'In brief';

  @override
  String get privacyBriefBody =>
      'This app stores your learning progress exclusively on this device and does not send it to us or third parties. There is no tracking, no advertising and no account.';

  @override
  String get privacyStorageTitle => 'What is stored and where';

  @override
  String get privacyStorageBody =>
      'Only locally on this device, in Flutter\'s standard SharedPreferences and a log file in the sandboxed app directory:\n\n• Game progress (score, current level per game, unlocked achievements)\n• Learning curve status (which words / items were answered, how often and how confidently)\n• Cognitive profile (attempts and correct answers per skill area)\n• Streak (current and longest series of consecutive days played)\n• Settings (learning level, language, sound on/off, font, custom vocabulary sets)\n• Parental PIN (4 digits, for the parent overview)\n• A rolling crash log file with at most 50 entries, only for actual crashes\n\nNone of these values identifies you. No name, email address, date of birth, device ID or IP address is stored permanently by the app.';

  @override
  String get privacyNetworkTitle => 'Network';

  @override
  String get privacyNetworkBody =>
      'The English vocabulary database is installed with the app. The German database is downloaded from Hugging Face on first use and then stored locally. The download provider receives the technical connection data usual for an internet connection.\n\nIn-app purchases and their restoration are handled through the device\'s app store. The app receives no payment data.\n\nExternal links (e.g. to the publisher\'s website in the legal notice) open in the system browser. No data is sent from within the app.';

  @override
  String get privacyCrashTitle => 'Crash reports';

  @override
  String get privacyCrashBody =>
      'If the app crashes, a short technical entry (error message, stack trace) is written to a local file. You can view it under Settings → Diagnostics. It only leaves the device if you actively copy the log using \"Copy to clipboard\" and paste it into an email, for example.';

  @override
  String get privacyMinorsTitle => 'Use by minors';

  @override
  String get privacyMinorsBody =>
      'The app can be used by learners of different ages, including minors. The app creates no user account and does not itself collect personal data. Learning progress and settings remain locally on the device.';

  @override
  String get privacyRightsTitle => 'Your rights';

  @override
  String get privacyRightsBody =>
      'You can remove all locally stored data at any time via Settings → \"Delete all data\". This deletes all the values listed above. When you uninstall the app, iOS and Android automatically remove all sandbox data.';

  @override
  String get privacyChangesTitle => 'Changes';

  @override
  String get privacyChangesBody =>
      'If we ever start collecting data (e.g. for a cloud backup), this policy will be updated, the changes will be highlighted the next time the app starts, and any new collection will only take place with your active consent (Opt-in).';
}
