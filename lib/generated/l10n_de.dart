// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'l10n.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class SDe extends S {
  SDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Wort-Universum';

  @override
  String get loadPreparing => 'Wortschatzdatenbank wird vorbereitet …';

  @override
  String get loadWebEngine => 'Web-Datenbank wird initialisiert …';

  @override
  String get loadLocatingStorage => 'Speicherort der Datenbank wird gesucht …';

  @override
  String get loadCheckingDatabase => 'Vorhandene Datenbank wird geprüft …';

  @override
  String get loadPreparingStorage => 'Speicher wird vorbereitet …';

  @override
  String get loadLoadingCompressed => 'Komprimierte Datenbank wird geladen …';

  @override
  String loadLoadedCompressed(Object size) {
    return '$size MB komprimierte Daten geladen';
  }

  @override
  String get loadDecompressing => 'Datenbank wird entpackt …';

  @override
  String loadDecompressed(Object size) {
    return 'Auf $size MB entpackt';
  }

  @override
  String get loadWritingBrowserStorage =>
      'Wird im Browserspeicher gespeichert …';

  @override
  String get loadWritingStorage => 'Datenbank wird auf dem Gerät gespeichert …';

  @override
  String get loadSavedBrowser => 'Datenbank im Browser gespeichert';

  @override
  String get loadSavedDisk => 'Datenbank auf dem Gerät gespeichert';

  @override
  String get loadOpeningDatabase => 'Datenbank wird geöffnet …';

  @override
  String get loadDatabaseReady => 'Datenbank bereit!';

  @override
  String loadDatabaseReadyWords(Object count) {
    return 'Datenbank mit $count Wörtern bereit!';
  }

  @override
  String get loadVerifying => 'Integrität der Datenbank wird geprüft …';

  @override
  String loadVerifiedWords(Object count) {
    return 'Datenbank geprüft: $count Wörter';
  }

  @override
  String get loadLoadingWords => 'Wörter werden geladen …';

  @override
  String get loadLoadingCustomizations => 'Deine Anpassungen werden geladen …';

  @override
  String get loadReady => 'Bereit!';

  @override
  String get loadDownloading => 'Datenbank wird heruntergeladen …';

  @override
  String loadDownloadBytes(Object size) {
    return 'Wird heruntergeladen … $size MB';
  }

  @override
  String loadDownloadTotal(Object size, Object total) {
    return 'Wird heruntergeladen … $size / $total MB';
  }

  @override
  String loadDownloadComplete(Object size) {
    return 'Download abgeschlossen ($size MB)';
  }

  @override
  String loadRetrying(Object attempt, Object total) {
    return 'Download wird erneut versucht (Versuch $attempt von $total) …';
  }

  @override
  String get loadPaused => 'Download pausiert';

  @override
  String get loadResumeReady => 'Bereit zum Fortsetzen';

  @override
  String get loadFailed =>
      'Die Sprachdaten konnten nicht geladen werden. Bitte versuche es erneut.';

  @override
  String get loadDecompressionFailed =>
      'Die Datenbank konnte nicht entpackt werden. Bitte versuche es erneut.';

  @override
  String get loadLoadingProgress => 'Dein Fortschritt wird geladen …';

  @override
  String get loadLoadingLearning => 'Lerndaten werden geladen …';

  @override
  String get loadLoadingProfile => 'Dein Profil wird geladen …';

  @override
  String get downloadPause => 'Pausieren';

  @override
  String get downloadResume => 'Fortsetzen';

  @override
  String get downloadPaused => 'Pausiert';

  @override
  String get setupWelcome => 'Willkommen im WortUniversum';

  @override
  String get setupLearningQuestion => 'Welche Sprache möchtest du lernen?';

  @override
  String get setupLearningDescription =>
      'Sprache für Wörter, Übungen und Spiele.';

  @override
  String get setupLearningLabel => 'Lernsprache';

  @override
  String get setupInterfaceQuestion => 'Welche Sprache soll die App verwenden?';

  @override
  String get setupInterfaceDescription =>
      'Sprache für Menüs, Schaltflächen und Anleitungen.';

  @override
  String get setupInterfaceLabel => 'Sprache der Oberfläche';

  @override
  String get setupContinue => 'Weiter';

  @override
  String get setupSaveFailed =>
      'Deine Sprachauswahl konnte nicht gespeichert werden. Bitte versuche es erneut.';

  @override
  String get startupFailedTitle => 'Initialisierung fehlgeschlagen';

  @override
  String get startupFailed =>
      'Die App konnte nicht gestartet werden. Bitte versuche es erneut.';

  @override
  String get welcome => 'Entdecke das Wort-Universum!';

  @override
  String get startAdventure => 'Starte Wort-Abenteuer';

  @override
  String get onboardingWelcomeTitle => 'Richte dein Lernen ein';

  @override
  String get onboardingWelcomeBody =>
      'Wähle aus, was du üben möchtest. Alles lässt sich später in den Einstellungen ändern.';

  @override
  String get onboardingLearningLanguage => 'Was möchtest du lernen?';

  @override
  String get onboardingGoal =>
      'Worauf soll dein Training den Schwerpunkt legen?';

  @override
  String get onboardingStartBand => 'Wähle eine Wortschatzstufe zum Einstieg';

  @override
  String get onboardingBandNote =>
      'Die Stufen sind grobe Schwierigkeitsbereiche – keine Schuljahre, Alters- oder GER-Stufen.';

  @override
  String get onboardingDailyTime => 'Tägliche Übungszeit';

  @override
  String get onboardingContinue => 'Meinen Lernplan vorbereiten';

  @override
  String get goalBalanced => 'Ausgewogen';

  @override
  String get goalVocabulary => 'Wortschatz';

  @override
  String get goalSpelling => 'Rechtschreibung';

  @override
  String get goalGrammar => 'Grammatik';

  @override
  String get goalDafDaz => 'Deutsch als Fremd- oder Zweitsprache';

  @override
  String get dailySessionTitle => 'Dein heutiger Lernplan';

  @override
  String dailySessionSubtitle(int minutes) {
    return 'Eine konzentrierte Einheit von etwa $minutes Minuten';
  }

  @override
  String get dailyReviewTitle => 'Fällige Wörter wiederholen';

  @override
  String dailyReviewSubtitle(int count) {
    return '$count Wörter sind zur Wiederholung bereit';
  }

  @override
  String get dailyWarmupTitle => 'Aufwärmen im Kontext';

  @override
  String get dailyWarmupSubtitle => 'Starte mit einer kurzen Satzübung';

  @override
  String get dailyGoalTitle => 'Deinen Schwerpunkt üben';

  @override
  String get dailyGoalSubtitle => 'Eine Übung passend zu deinem Lernziel';

  @override
  String get dailyContextTitle => 'Wörter im Kontext verwenden';

  @override
  String get dailyContextSubtitle => 'Schließe mit einer Lückentext-Aufgabe ab';

  @override
  String get dailyCompleteTitle => 'Lernplan abgeschlossen';

  @override
  String dailyCompleteSummary(int attempts, int mastered) {
    return 'Du hast $attempts erfasste Aufgaben beantwortet und dabei $mastered neue Inhalte gemeistert.';
  }

  @override
  String get dailyPractiseMore => 'Weiterüben';

  @override
  String get browseAllGames => 'Alle Spiele entdecken';

  @override
  String get focusMode => 'Fokusmodus';

  @override
  String get focusModeDesc =>
      'Weniger Dekoration, damit die Lernaktionen im Mittelpunkt stehen';

  @override
  String get catalogRecommended => 'Empfohlen';

  @override
  String get catalogFast => 'Kurzübungen';

  @override
  String get catalogFavorites => 'Favoriten';

  @override
  String get catalogRecent => 'Zuletzt gespielt';

  @override
  String get catalogAll => 'Alle Spiele';

  @override
  String get catalogSearch => 'Spiele suchen';

  @override
  String get catalogAddFavorite => 'Zu Favoriten hinzufügen';

  @override
  String get catalogRemoveFavorite => 'Aus Favoriten entfernen';

  @override
  String get catalogNoGames => 'Noch keine passenden Spiele in dieser Ansicht.';

  @override
  String get chooseGrade => 'Wähle deine Stufe';

  @override
  String get grade3 => 'Stufe 1';

  @override
  String get grade4 => 'Stufe 2';

  @override
  String get grade5 => 'Stufe 3';

  @override
  String get grade6 => 'Stufe 4';

  @override
  String get licensesTitle => 'Lizenzen';

  @override
  String get viewOssLicenses => 'Zeige die open-source Lizenzen';

  @override
  String get downloadDbTitle => 'Ersteinrichtung';

  @override
  String downloadDbMessage(String size) {
    return 'Die deutsche Wörter-Datenbank (etwa $size) wird einmalig heruntergeladen und für die Offline-Nutzung auf deinem Gerät gespeichert.';
  }

  @override
  String get downloadDbConfirm => 'Herunterladen';

  @override
  String get downloadDbCancel => 'Jetzt nicht';

  @override
  String get downloadDbDeclined =>
      'Die deutsche Wörter-Datenbank wird zum Fortfahren benötigt. Tippe auf Wiederholen, um sie herunterzuladen, oder wechsle in den Einstellungen zu Englisch.';

  @override
  String get appName => 'Wort-Universum';

  @override
  String get appLegalese =>
      '© 2025–2026 CrispStrobe\n\nDeutsche Vokabular-Datenbank lizenziert unter GPL-3.0 (enthält aus childLex abgeleitete Daten); englische Vokabular-Datenbank unter CC BY-SA 4.0. Quellen: Wiktionary, ConceptNet, OEWN, OpenThesaurus, OdeNet, LiTKey, Tatoeba, Project Gutenberg, childLex u. a. Vollständige Quellenangaben in den Lizenzeinträgen unten.\n\nDatensätze: huggingface.co/datasets/cstr/grundwortschatz-voc-de  ·  cstr/grundwortschatz-voc-en\n\nApp-Code ist proprietär.';

  @override
  String get spaceWordRescueTitle => 'Wort-Rettung';

  @override
  String get spaceWordRescueInstructions => 'Rette Wörter vor dem Abdriften!';

  @override
  String get wordRescueTitle => 'Wort-Rettung';

  @override
  String get wordRescueCardDescription => 'Tippe Wörter bevor sie entkommen!';

  @override
  String get wordRescueTypeWord => 'Tippe das Wort um es zu retten!';

  @override
  String get wordRescueTypeHere => 'Hier tippen...';

  @override
  String get wordRescueFeedbackPerfect => 'Perfekt! Wort gerettet! 🚀';

  @override
  String wordRescueFeedbackCommonMistake(String word) {
    return 'Fast! $word gerettet!';
  }

  @override
  String wordRescueFeedbackIncorrect(String word) {
    return 'Zu spät! Das richtige Wort war: $word';
  }

  @override
  String get wordRescueFeedbackLost => 'Wort ins All entkommen! 💫';

  @override
  String wordRescueGameOverStats(int rescued, int total, int percentage) {
    return 'Du hast $rescued von $total Wörtern gerettet ($percentage%)';
  }

  @override
  String get wordSnakeTitle => 'Wortschlange';

  @override
  String get wordSnakeDescription => 'Verbinde Buchstaben zum Wort';

  @override
  String get wordSnakeInstructions =>
      'Tippe Zellen in Reihenfolge an, um einen Pfad zu bilden, der das Wort buchstabiert';

  @override
  String wordSnakeConnectLetters(int count) {
    return 'Verbinde $count Buchstaben';
  }

  @override
  String get wordSnakeReset => 'Zurücksetzen';

  @override
  String wordSnakePuzzleProgress(int current, int total) {
    return 'Rätsel $current von $total';
  }

  @override
  String get gameplayHint => 'Hinweis (-2 Punkte)';

  @override
  String get gameplayCheck => 'Prüfen';

  @override
  String get gameplayCorrect => 'Richtig! Gut gemacht! 🚀';

  @override
  String get gameplayIncorrect =>
      'Das war leider nicht richtig. Versuche es beim nächsten Mal!';

  @override
  String get gameplayRescued => 'Gerettet';

  @override
  String get gameplayLost => 'Verloren';

  @override
  String get gameplayWriteTheWord => 'Schreibe das Wort...';

  @override
  String gameplayFeedbackCommonMistake(Object correctWord) {
    return 'Fast richtig! Das ist ein häufiger Fehler.\nDie korrekte Schreibweise ist: $correctWord';
  }

  @override
  String gameplayFeedbackIncorrect(Object correctWord) {
    return 'Leider falsch. Die korrekte Schreibweise ist: $correctWord';
  }

  @override
  String get wordFindTitle => 'Wortsuche';

  @override
  String get wordFindDescription =>
      'Finde die versteckten Wörter im Buchstaben-Gitter!';

  @override
  String get wordFindWordsToFind => 'Wörter finden:';

  @override
  String get wordSortTitle => 'Wortarten-Spiel';

  @override
  String get wordSortDescription =>
      'Sortiere Wörter in Kategorien: Nomen, Verben und Adjektive';

  @override
  String get wordSortTitleTimeAttack => 'Wortarten - Gegen die Zeit!';

  @override
  String get wordSortCategoryNoun => 'Nomen';

  @override
  String get wordSortCategoryVerb => 'Verb';

  @override
  String get wordSortCategoryAdjective => 'Adjektiv';

  @override
  String get wordSortCorrect => 'Richtig! Gut gemacht!';

  @override
  String get wordSortIncorrect => 'Nicht ganz. Lass uns lernen!';

  @override
  String get wordSortTimeUp => 'Zeit abgelaufen!';

  @override
  String wordSortStreakBonus(int streak) {
    return '🔥 $streak hintereinander! Bonuspunkte!';
  }

  @override
  String wordSortHintNounArticle(String article, String gender) {
    return 'Richtig! Man sagt \'$article\' - der Artikel zeigt, dass es ein $gender Nomen ist.';
  }

  @override
  String wordSortHintNounPlural(String singular, String plural) {
    return 'Die Mehrzahl von \'$singular\' ist \'$plural\'.';
  }

  @override
  String wordSortHintVerbConjugation(String ich, String du) {
    return 'Richtig! Verben verändern sich: \'$ich\', \'$du\' - sie konjugieren mit der Person!';
  }

  @override
  String wordSortHintAdjectiveComparison(
      String base, String comparative, String superlative) {
    return 'Adjektive haben Steigerungsformen: $base → $comparative → $superlative';
  }

  @override
  String wordSortWhyNot(String type) {
    return 'Nein, es ist kein $type.';
  }

  @override
  String wordSortWhyNoun(String article) {
    return 'Es ist ein NOMEN, weil man \'$article\' sagt - Artikel stehen vor Nomen!';
  }

  @override
  String wordSortNounDeclensionExample(String nominative, String genitive) {
    return 'Nomen verändern sich nach dem Fall: $nominative → $genitive';
  }

  @override
  String wordSortWhyVerb(String forms) {
    return 'Es ist ein VERB, weil es konjugiert wird: $forms';
  }

  @override
  String wordSortWhyAdjective(
      String base, String comparative, String superlative) {
    return 'Es ist ein ADJEKTIV, weil es Steigerungsformen hat: $base → $comparative → $superlative';
  }

  @override
  String get wordSortHintLookForArticle =>
      '💡 Tipp: Achte auf den Artikel (der/die/das)!';

  @override
  String wordSortHintArticleExample(String article) {
    return 'Dieses Wort hat den Artikel \'$article\'';
  }

  @override
  String get wordSortHintLookForConjugation =>
      '💡 Tipp: Kann man \'ich...\' damit sagen?';

  @override
  String get wordSortHintLookForComparison =>
      '💡 Tipp: Kann dieses Wort etwas beschreiben? Kann es \'mehr\' oder \'am meisten\' werden?';

  @override
  String get wordSortToggleTimeAttack => 'Zeit-Modus umschalten';

  @override
  String get wordSortShowHint => 'Tipp anzeigen';

  @override
  String get wordSortTimeAttackComplete =>
      'Zeit-Herausforderung abgeschlossen!';

  @override
  String get score => 'Punkte';

  @override
  String get correct => 'richtig';

  @override
  String get gameOver => 'Spiel vorbei';

  @override
  String get backToMenu => 'Zurück zum Menü';

  @override
  String get goBack => 'Zurück';

  @override
  String get playAgain => 'Nochmal spielen';

  @override
  String get adaptiveDifficulty => 'Angepasste Schwierigkeit';

  @override
  String get adaptiveDifficultyDesc => 'Passt Aufgaben an dein Können an';

  @override
  String get adjustProblems => 'Passe die Aufgaben an deine Fähigkeiten an';

  @override
  String get gameMenu => 'Wort-Universum';

  @override
  String get level => 'Level';

  @override
  String get lives => 'Hüllenintegrität';

  @override
  String get time => 'Zeit';

  @override
  String get incorrect => 'Fehler!';

  @override
  String get excellent => 'Großartig, Forscher!';

  @override
  String get good => 'Gut gemacht!';

  @override
  String get tryAgain => 'Nochmal versuchen!';

  @override
  String get nextLevel => 'Nächste Erkundung';

  @override
  String get settings => 'Einstellungen';

  @override
  String get sound => 'Soundeffekte';

  @override
  String get music => 'Musik';

  @override
  String get language => 'Sprache';

  @override
  String get progress => 'Lernfortschritt';

  @override
  String get achievements => 'Erfolge';

  @override
  String get congratulations => 'Herzlichen Glückwunsch, Forscher!';

  @override
  String missionsCompleted(int count) {
    return 'Erkundungen abgeschlossen: $count';
  }

  @override
  String starsEarned(int count) {
    return 'Sterne erhalten: $count';
  }

  @override
  String get audioSettings => 'Audio-Einstellungen';

  @override
  String get soundEffects => 'Soundeffekte';

  @override
  String get backgroundMusicDesc => 'Hintergrundmusik';

  @override
  String get gameplay => 'Spielablauf';

  @override
  String get puzzleTimer => 'Puzzle-Timer';

  @override
  String get puzzleTimerDesc => 'Timer in Puzzle-Spielen aktivieren';

  @override
  String get showHints => 'Hinweise anzeigen';

  @override
  String get showHintsDesc => 'Hilfreiche Tipps während der Spiele anzeigen';

  @override
  String get hapticFeedback => 'Haptisches Feedback';

  @override
  String get hapticFeedbackDesc =>
      'Vibration bei Berührung (falls unterstützt)';

  @override
  String get appLanguage => 'App-Sprache';

  @override
  String get appLanguageDesc => 'Wähle deine bevorzugte Sprache';

  @override
  String get learningLanguage => 'Lernsprache';

  @override
  String get learningLanguageDesc =>
      'Wähle, welche Wortschatz-Datenbank die Spiele verwenden';

  @override
  String packRequiredTitle(String language) {
    return '$language-Paket erforderlich';
  }

  @override
  String packRequiredMessage(String language, String size) {
    return 'Die Spiele brauchen die $language-Wortdatenbank (etwa $size). Sie wird einmal geladen und funktioniert danach offline.';
  }

  @override
  String packDownloadingTitle(String language) {
    return '$language wird geladen';
  }

  @override
  String get packDownloadPreparing => 'Download wird vorbereitet…';

  @override
  String get packKeepAppOpen =>
      'Bitte lass die App offen, bis der Download fertig ist.';

  @override
  String packMetaSizeLicense(String size, String license) {
    return '$size Download · Daten unter $license';
  }

  @override
  String get packOfflineAfterDownload =>
      'Funktioniert nach dem Download offline';

  @override
  String get packFailedTitle => 'Download fehlgeschlagen';

  @override
  String get packFailedNetworkHint =>
      'Prüfe deine Internetverbindung und versuche es erneut.';

  @override
  String get packFailedDataHint =>
      'Die geladene Datei hat die Integritätsprüfung nicht bestanden. Ein neuer Versuch hilft meist.';

  @override
  String packFallbackHint(String language) {
    return 'Du kannst mit $language weitermachen und dieses Paket später in den Einstellungen laden.';
  }

  @override
  String packUseFallback(String language) {
    return 'Mit $language weitermachen';
  }

  @override
  String get packRetry => 'Erneut versuchen';

  @override
  String get languagePacksTitle => 'Sprachpakete';

  @override
  String get languagePacksDesc => 'Wortschatz-Datenbanken auf diesem Gerät';

  @override
  String get packStatusInstalled => 'Geladen';

  @override
  String get packStatusBundled => 'In der App enthalten';

  @override
  String get packStatusNotInstalled => 'Nicht geladen';

  @override
  String get packStatusInstalling => 'Wird geladen…';

  @override
  String get packStatusFailed => 'Download fehlgeschlagen';

  @override
  String get packInUse => 'Aktiv';

  @override
  String get packDownloadAction => 'Laden';

  @override
  String get packGateLoadAction => 'Sprachpaket laden';

  @override
  String get packUseAction => 'Verwenden';

  @override
  String get packRemoveAction => 'Entfernen';

  @override
  String packRemoveConfirmTitle(String language) {
    return '$language-Paket entfernen?';
  }

  @override
  String packRemoveConfirmMessage(String language, String size) {
    return 'Die $language-Wortdatenbank ($size) wird von diesem Gerät gelöscht. Du kannst sie jederzeit erneut laden.';
  }

  @override
  String packRemoved(String language) {
    return '$language-Paket entfernt';
  }

  @override
  String packMissingBanner(String language) {
    return 'Die $language-Wortdatenbank ist noch nicht geladen. Zum Laden tippen.';
  }

  @override
  String packReadyToast(String language) {
    return '$language ist bereit';
  }

  @override
  String get languageEnglish => 'English';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get difficulty => 'Schwierigkeit';

  @override
  String get currentGrade => 'Aktuelle Stufe';

  @override
  String get currentLevelDesc => 'Aktuelles Level';

  @override
  String get difficultyDescGrade3 =>
      'Alltagswörter und Grundlagen der Rechtschreibung';

  @override
  String get difficultyDescGrade4 =>
      'Breiterer Wortschatz und grundlegende Grammatik';

  @override
  String get difficultyDescGrade5 =>
      'Fortgeschrittene Wörter, Fälle und Zeitformen';

  @override
  String get difficultyDescGrade6 =>
      'Anspruchsvoller Wortschatz und komplexe Grammatik';

  @override
  String get totalScore => 'Gesamtpunktzahl';

  @override
  String get gamesPlayed => 'Gespielte Spiele';

  @override
  String get resetProgress => 'Fortschritt zurücksetzen';

  @override
  String get about => 'Über';

  @override
  String get appVersion => 'App-Version';

  @override
  String get developer => 'Entwickler';

  @override
  String get developerName => 'CrispStrobe';

  @override
  String get targetAge => 'Für wen';

  @override
  String get targetAgeRange =>
      'Deutsch- und Englischlernende verschiedener Altersgruppen';

  @override
  String get aboutApp =>
      'Wort-Universum hilft beim Üben von Wortschatz, Rechtschreibung und Grammatik – mit abwechslungsreichen Spielen im Weltraum-Design.';

  @override
  String get debugPanelTitle => 'Debug-Panel';

  @override
  String get debugForceUnlock => 'Vollversion erzwingen';

  @override
  String get debugApplyAndClose => 'Anwenden & Schließen';

  @override
  String get parentalGateTitle => 'Kurze Sicherheitsabfrage';

  @override
  String get parentalGateChallenge =>
      'Um fortzufahren, bitte diese Aufgabe lösen:';

  @override
  String get confirm => 'Bestätigen';

  @override
  String get pleaseTryAgain => 'Bitte versuche es erneut.';

  @override
  String get purchaseTitle => 'Vollzugriff freischalten';

  @override
  String get purchaseDescription =>
      'Schalte alle Spiele, alle Stufen und zukünftige Updates mit einem einzigen Kauf frei!';

  @override
  String get purchaseButton => 'Jetzt freischalten!';

  @override
  String get contactingStore => 'Verbinde mit dem Wort-Universum...';

  @override
  String get purchaseError =>
      'Ein Fehler ist aufgetreten. Bitte prüfe deine Verbindung und versuche es erneut.';

  @override
  String get restorePurchases => 'Käufe wiederherstellen';

  @override
  String get storeUnavailable =>
      'Der Store ist derzeit nicht verfügbar. Bitte prüfe deine Verbindung und ob du mit deinem Konto angemeldet bist.';

  @override
  String get languageChanged => 'Sprache geändert';

  @override
  String get languageChangedDesc =>
      'Die App-Sprache wird nach einem Neustart geändert. Möchtest du jetzt neu starten?';

  @override
  String get later => 'Später';

  @override
  String get restartNow => 'Jetzt neu starten';

  @override
  String get selectGrade => 'Stufe auswählen';

  @override
  String gradeN(int gradeNumber) {
    return 'Stufe $gradeNumber';
  }

  @override
  String packRemoveFailed(String language) {
    return 'Das $language-Paket konnte nicht entfernt werden.';
  }

  @override
  String get cancel => 'Abbrechen';

  @override
  String get restartToApplyChanges =>
      'Bitte starte die App neu, um die Sprachänderungen zu übernehmen';

  @override
  String get resetProgressConfirmation =>
      'Bist du sicher, dass du den gesamten Fortschritt zurücksetzen möchtest? Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get progressResetSuccess => 'Fortschritt erfolgreich zurückgesetzt!';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get playToUnlock => 'Spielen zum Freischalten!';

  @override
  String get chooseYourGrade => 'Wähle deine Stufe';

  @override
  String get grade3Desc =>
      'Grundlagen der Rechtschreibung, einfache Nomen und Verben.';

  @override
  String get grade4Desc =>
      'Häufige Wörter, erste Grammatikregeln und Wortarten.';

  @override
  String get grade5Desc => 'Komplexere Wörter, Fälle und Zeitformen.';

  @override
  String get grade6Desc =>
      'Fortgeschrittener Wortschatz und komplexe Grammatik.';

  @override
  String get settingsComingSoon => 'Einstellungen bald verfügbar!';

  @override
  String get spaceExplorerProgress => 'Weltraumforscher-Fortschritt';

  @override
  String get unlocked => 'Freigeschaltet';

  @override
  String get complete => 'Abgeschlossen';

  @override
  String get rankRookie => 'Rekrut';

  @override
  String get rankExplorer => 'Entdecker';

  @override
  String get rankVeteran => 'Veteran';

  @override
  String get rankExpert => 'Experte';

  @override
  String get rankLegend => 'Legende';

  @override
  String get achievementFirstCenturyTitle => 'Erstes Hundert!';

  @override
  String get achievementFirstCenturyDesc => 'Erreiche 100 Punkte';

  @override
  String get achievementScoreMasterTitle => 'Punkte-Meister';

  @override
  String get achievementScoreMasterDesc => 'Erreiche 500 Punkte';

  @override
  String get achievementThousandClubTitle => 'Tausender-Club';

  @override
  String get achievementThousandClubDesc => 'Erreiche 1000 Punkte';

  @override
  String get achievementAllRounderTitle => 'Alleskönner';

  @override
  String get achievementAllRounderDesc => 'Spiele alle Spieltypen';

  @override
  String get achievementSpeedDemonTitle => 'Geschwindigkeits-Dämon';

  @override
  String get achievementSpeedDemonDesc =>
      'Schließe ein Level in unter 30 Sekunden ab';

  @override
  String get achievementPerfectionistTitle => 'Perfektionist';

  @override
  String get achievementPerfectionistDesc =>
      'Schließe ein Level ohne Fehler ab';

  @override
  String get achievementWordRescuerTitle => 'Wort-Retter';

  @override
  String get achievementWordRescuerDesc => 'Rette 100 Wörter';

  @override
  String get unlockedStatus => 'FREIGESCHALTET';

  @override
  String get lockedStatus => 'GESPERRT';

  @override
  String get achievementUnlocked => 'ERFOLG FREIGESCHALTET!';

  @override
  String get continueExploring => 'Weiter erkunden';

  @override
  String get loadingAdventure => 'Lade Wort-Abenteuer...';

  @override
  String get preparingMission => 'Bereite deine Erkundung vor...';

  @override
  String get initializing => 'Initialisiere das Wort-Universum...';

  @override
  String get loadingAssets => 'Lade Spiel-Assets...';

  @override
  String get loadingProgress => 'Lade gespeicherten Fortschritt...';

  @override
  String get preparingSpaceStation => 'Bereite das Wort-Universum vor...';

  @override
  String get calibratingNav => 'Kalibriere Navigationssysteme...';

  @override
  String get readyForLaunch => 'Bereit zum Start!';

  @override
  String get launch => 'Start';

  @override
  String get splashScreenSubtitle => 'Erkunden • Lernen • Entdecken';

  @override
  String get sriStatisticsTitle => 'Lernfortschritt';

  @override
  String get sriStatisticsDesc =>
      'Sieh dir deinen Fortschritt an und erkenne, wo du dich verbessern kannst.';

  @override
  String get premiumFeature =>
      'Dies ist eine Premium-Funktion. Schalte die Vollversion frei, um darauf zuzugreifen.';

  @override
  String get close => 'Schließen';

  @override
  String get sriMastery => 'Gesamtbeherrschung';

  @override
  String get sriTotal => 'Gesamt Erfasst';

  @override
  String get sriMastered => 'Beherrscht';

  @override
  String get sriLearning => 'Im Training';

  @override
  String get progressMatrixTitle => 'Fortschrittsmatrix';

  @override
  String get progressMatrixDesc =>
      'Die Farbe zeigt die Beherrschung (grün ist am besten). Die Zahl zeigt die Anzahl der Aufgaben in diesem Bereich.';

  @override
  String get imprint => 'Impressum';

  @override
  String get imprintTitle => 'Impressum.';

  @override
  String get imprintDialog => 'Imprint / Legal..';

  @override
  String get viewLegalNotice => 'Informationen zum Diensteanbieter';

  @override
  String get imprintServiceProvider => 'Diensteanbieter';

  @override
  String get imprintProviderAddress =>
      'Christian Ströbele\nNikolausstr. 5\n70190 Stuttgart\nDeutschland/Germany';

  @override
  String get imprintContact => 'Kontakt';

  @override
  String get imprintContactDetails =>
      'Email: postmaster@crispstro.be\nPhone: 0049 176 6421 8601';

  @override
  String get imprintContentResponsible => 'Verantwortlich für den Inhalt';

  @override
  String get imprintDisclaimer => 'Haftungsausschluss';

  @override
  String get imprintDisclaimerText =>
      'Diese App wird \'as is\' (so wie sie ist) ausschließlich zu Bildungs- und kreativen Zwecken bereitgestellt, ohne jegliche Haftung.';

  @override
  String get imprintWebsite => 'www.crispstro.be';

  @override
  String get taskCustomizationTitle => 'Aufgaben-Anpassung';

  @override
  String get taskCustomizationEnable => 'Anpassung aktivieren';

  @override
  String get taskCustomizationEnableDesc => 'Wortschatz für Übungen filtern';

  @override
  String get taskWordLengthTitle => 'Wortlänge';

  @override
  String taskWordLengthRange(int min, int max) {
    return 'Wörter mit $min bis $max Buchstaben';
  }

  @override
  String get taskIncludedSourcesTitle => 'Wortquellen';

  @override
  String get taskIncludedSourcesDesc =>
      'Nur Wörter aus den gewählten Quellen anzeigen (leer = alle)';

  @override
  String get taskWildcardIncludeTitle => 'Platzhalter-Filter (Einschließen)';

  @override
  String get taskWildcardIncludeDesc =>
      'Zeige nur Wörter, die passen (z.B. *ung)';

  @override
  String get taskWildcardExcludeTitle => 'Platzhalter-Filter (Ausschließen)';

  @override
  String get taskWildcardExcludeDesc =>
      'Verstecke Wörter, die passen (z.B. ge*)';

  @override
  String get taskWildcardHint => 'Neuen Filter hinzufügen...';

  @override
  String get taskCustomizationWarning =>
      'Filter aktiv! Der Wortschatz ist eingeschränkt.';

  @override
  String get taskActiveSetTitle => 'Aktives Wortschatz-Set';

  @override
  String get taskActiveSetDesc =>
      'Überschreibt alle anderen Filter, wenn aktiv.';

  @override
  String get taskActiveSetNone => 'Keines (Filter unten verwenden)';

  @override
  String get taskManageSets => 'Eigene Sets verwalten';

  @override
  String get taskFiltersDisabled =>
      'Die Filter unten sind deaktiviert, da ein eigenes Set aktiv ist.';

  @override
  String get customSetCreateTitle => 'Neues Set erstellen';

  @override
  String get customSetEditTitle => 'Set bearbeiten';

  @override
  String get save => 'Speichern';

  @override
  String get customSetNameRequired => 'Gib einen Namen für dieses Set ein.';

  @override
  String get customSetSaveFailed =>
      'Das Set konnte nicht gespeichert werden. Bitte versuche es erneut.';

  @override
  String get languageChangeFailed =>
      'Die App-Sprache konnte nicht geändert werden. Bitte versuche es erneut.';

  @override
  String learningLanguageChanged(String language) {
    return 'Lernsprache zu $language gewechselt';
  }

  @override
  String get learningLanguageChangeFailed =>
      'Die Lernsprache konnte nicht geändert werden. Bitte versuche es erneut.';

  @override
  String get unexpectedErrorTitle => 'Etwas ist schiefgegangen';

  @override
  String get unexpectedErrorMessage =>
      'Bitte versuche es erneut. Falls das Problem bleibt, kannst du das Absturzprotokoll unter Einstellungen › Diagnose kopieren.';

  @override
  String get genericErrorTitle => 'Fehler';

  @override
  String get genericErrorMessage =>
      'Etwas ist schiefgegangen. Bitte versuche es erneut.';

  @override
  String get routeNotFoundTitle => 'Seite nicht gefunden';

  @override
  String get routeNotFoundMessage =>
      'Die angeforderte Seite wurde nicht gefunden.';

  @override
  String get customSetNameLabel => 'Name des Sets';

  @override
  String get customSetNameHint => 'z.B. \'Schwierige Verben\'';

  @override
  String get customSetDescriptionLabel => 'Beschreibung';

  @override
  String get customSetDescriptionHint =>
      'Eine kurze Beschreibung dieses Sets...';

  @override
  String get customSetTargetGrade => 'Ziel-Stufe';

  @override
  String get customSetAvailableWords => 'Verfügbare Wörter';

  @override
  String customSetSelectedWords(int count) {
    return 'Ausgewählte Wörter ($count)';
  }

  @override
  String get customSetSearchHint => 'Wörter filtern...';

  @override
  String get customSetAddAll => 'Alle hinzufügen';

  @override
  String get customSetRemoveAll => 'Alle entfernen';

  @override
  String get customSetEmpty => 'Noch keine Wörter ausgewählt.';

  @override
  String get customSetNoAvailable => 'Keine passenden Wörter gefunden.';

  @override
  String get customSetDelete => 'Set löschen';

  @override
  String get customSetDeleteConfirmTitle => 'Set löschen?';

  @override
  String customSetDeleteConfirmContent(String setName) {
    return 'Möchtest du das Set $setName wirklich löschen?';
  }

  @override
  String get wordMemoryDescription =>
      'Finde passende Wortpaare in verschiedenen Schriften';

  @override
  String get wordBuilderDescription =>
      'Baue Wörter aus durcheinander gewürfelten Buchstaben';

  @override
  String get wordWhirlDescription => 'Tippe die richtigen Wortarten im Wirbel!';

  @override
  String get wordMemoryTitle => 'Memory';

  @override
  String get wordMemoryComplete => 'Geschafft!';

  @override
  String get wordMemoryScore => 'Punkte';

  @override
  String get wordMemoryMoves => 'Züge';

  @override
  String get wordMemoryPairs => 'Paare';

  @override
  String get wordBuilderTitle => 'Wort-Baumeister';

  @override
  String get wordBuilderGameOver => 'Spiel Beendet!';

  @override
  String get wordBuilderWords => 'Wörter';

  @override
  String get wordBuilderTimeBonus => 'Zeitbonus';

  @override
  String get wordBuilderBuildWord => 'Baue das Wort:';

  @override
  String get wordBuilderLetters => 'Buchstaben:';

  @override
  String get wordBuilderHint => 'Hinweis (-10)';

  @override
  String get wordBuilderSkip => 'Überspringen';

  @override
  String get wordBuilderTime => 'Zeit';

  @override
  String get wordWhirlTitle => 'Wortarten-Wirbel';

  @override
  String get wordWhirlGameOver => 'Wirbel Beendet!';

  @override
  String get wordWhirlAccuracy => 'Genauigkeit';

  @override
  String get wordWhirlBestStreak => 'Beste Serie';

  @override
  String get wordWhirlCorrect => 'Richtig';

  @override
  String get wordWhirlIncorrect => 'Falsch';

  @override
  String get wordWhirlStreak => 'Serie';

  @override
  String get wordWhirlRound => 'Runde';

  @override
  String wordWhirlTapAll(String wordType) {
    return 'Tippe auf alle Worte der Wortart $wordType!';
  }

  @override
  String get gameReplay => 'Nochmal';

  @override
  String get gameDone => 'Fertig';

  @override
  String get gameScore => 'Punkte';

  @override
  String get difficultyEasy => 'Leicht';

  @override
  String get difficultyNormal => 'Normal';

  @override
  String get difficultyChallenge => 'Knifflig';

  @override
  String streakLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get gameTooSlow => 'Zu langsam!';

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
  String get verbtrennerSeparableTitle => 'Trennbare Verben';

  @override
  String get verbtrennerCompoundTitle => 'Nomen-Komposita';

  @override
  String get verbtrennerSeparatedLabel => 'GETRENNT';

  @override
  String get verbtrennerSeparatedExample => '(stehe auf)';

  @override
  String get verbtrennerTogetherLabel => 'ZUSAMMEN';

  @override
  String get verbtrennerTogetherExample => '(aufstehen)';

  @override
  String get wortbaumeisterSeparatedExample => '(z.B. stehe auf)';

  @override
  String get wortbaumeisterTogetherExample => '(z.B. aufstehen)';

  @override
  String get grossschreibTitle => 'Wort-Galaxie';

  @override
  String get grossschreibDescription =>
      'Werden Worte im Satz groß oder klein geschrieben?';

  @override
  String get grossschreibClickHint => 'Klicke auf das Wort!';

  @override
  String get grossschreibCheck => 'PRÜFEN';

  @override
  String get grossstadtTitle => 'Groß oder klein?';

  @override
  String get grossstadtCardTitle => 'Wort-Sortierer';

  @override
  String get grossstadtCardDescription =>
      'Groß- und Kleinschreibung auf dem Förderband';

  @override
  String get grossstadtCapital => 'GROSS';

  @override
  String get grossstadtLower => 'klein';

  @override
  String get spellingSpotterTitle => 'Spelling Spotter';

  @override
  String get spellingSpotterDescription =>
      'Finde das korrekt geschriebene Wort — lerne häufige Rechtschreibfehler';

  @override
  String get sentenceCompletionTitle => 'Satzergänzung';

  @override
  String get sentenceCompletionDescription =>
      'Ergänze das fehlende Wort — übe Wortschatz im Kontext';

  @override
  String get definitionQuizTitle => 'Definitions-Quiz';

  @override
  String get definitionQuizDescription =>
      'Ordne die Definition dem richtigen Wort zu';

  @override
  String get sriReviewTitle => 'Schwache Wörter';

  @override
  String get sriReviewDescription => 'Übe deine schwierigsten Wörter gezielt';

  @override
  String get antonymFlashTitle => 'Gegenwort-Blitz';

  @override
  String get antonymFlashDescription =>
      'Tippe das Gegenteil — so schnell du kannst!';

  @override
  String get synonymFlashTitle => 'Synonym-Blitz';

  @override
  String get synonymFlashDescription =>
      'Tippe ein Wort mit gleicher Bedeutung — so schnell du kannst!';

  @override
  String get translationFlashTitle => 'Übersetzungs-Blitz';

  @override
  String get translationFlashDescription =>
      'Tippe die englische Übersetzung jedes deutschen Worts!';

  @override
  String get syllableCountTitle => 'Silben zählen';

  @override
  String get syllableCountDescription =>
      'Wie viele Silben hat das Wort? Zähl sie!';

  @override
  String get clozeFlashTitle => 'Lücken-Blitz';

  @override
  String get clozeFlashDescription =>
      'Füll die Lücke aus — tippe das richtige Wort!';

  @override
  String get expressionFlashTitle => 'Phrasen-Blitz';

  @override
  String get expressionFlashDescription =>
      'Ergänze die Redewendung — tippe das fehlende Wort!';

  @override
  String get hypernymFlashTitle => 'Oberbegriff-Blitz';

  @override
  String get hypernymFlashDescription => 'Welchem Oberbegriff gehört das Wort?';

  @override
  String get wordClassFlashTitle => 'Wortart-Blitz';

  @override
  String get wordClassFlashDescription =>
      'Nomen, Verb, Adjektiv oder Adverb — schnell tippen!';

  @override
  String get proverbClozeTitle => 'Sprichwort-Blitz';

  @override
  String get proverbClozeDescription =>
      'Ergänze das Sprichwort — tippe das fehlende Wort!';

  @override
  String get reverseTranslationTitle => 'Rück-Übersetzung';

  @override
  String get reverseTranslationDescription =>
      'Ein englisches Wort erscheint — finde das deutsche Wort!';

  @override
  String get conjugationDrillTitle => 'Konjugations-Drill';

  @override
  String get conjugationDrillDescription =>
      'Wähle die richtige Verbform für jedes Personalpronomen';

  @override
  String get conjugationDrillGameOverTitle => 'Übung beendet';

  @override
  String get conjugationDrillGameOverLabel => 'richtige Konjugationen';

  @override
  String get homophoneDrillTitle => 'Homophon-Training';

  @override
  String get homophoneDrillDescription =>
      'Wähle die richtige Schreibweise — hear vs. here, to vs. too vs. two';

  @override
  String get confusableDrillTitle => 'Wortfalle';

  @override
  String get confusableDrillDescription =>
      'Finde das richtige Wort — affect vs. effect, lose vs. loose';

  @override
  String get phrasalVerbPowerTitle => 'Phrasal-Verb-Power';

  @override
  String get phrasalVerbPowerDescription =>
      'Wähle das Wort, das das Phrasal Verb vervollständigt — give ___, take ___';

  @override
  String get phrasalVerbPowerPrompt =>
      'Welches Wort vervollständigt das Phrasal Verb?';

  @override
  String get phrasalVerbPowerEmpty =>
      'Noch keine Phrasal-Verb-Daten verfügbar.';

  @override
  String get phrasalVerbPowerOnboard1 =>
      'Phrasal Verbs sind ein Verb plus ein kleines Wort wie up, off oder away — give up, take off, look after.';

  @override
  String get phrasalVerbPowerOnboard2 =>
      'Es wird ein Satz mit einer Lücke gezeigt. Tippe das Wort, das das Phrasal Verb vervollständigt.';

  @override
  String get phrasalVerbPowerOnboard3 =>
      'Nach jeder Antwort siehst du, was das Phrasal Verb bedeutet.';

  @override
  String get phrasalVerbMatchTitle => 'Phrasal-Verb-Memory';

  @override
  String get phrasalVerbMatchDescription =>
      'Ordne dem Phrasal Verb seine Bedeutung zu — give up, take off, look after';

  @override
  String get phrasalVerbMatchPrompt => 'Was bedeutet dieses Phrasal Verb?';

  @override
  String get phrasalVerbMatchEmpty =>
      'Noch keine Phrasal-Verb-Daten verfügbar.';

  @override
  String get phrasalVerbMatchOnboard1 =>
      'Ein Phrasal Verb wird gezeigt — manchmal mit einem Beispielsatz als Hilfe.';

  @override
  String get phrasalVerbMatchOnboard2 =>
      'Tippe die passende Bedeutung. Die anderen Auswahlmöglichkeiten sind echte Bedeutungen anderer Phrasal Verbs.';

  @override
  String get phrasalVerbMatchOnboard3 =>
      'Der Beispielsatz kann dir helfen, die Bedeutung zu erschließen.';

  @override
  String get falseFriendsTitle => 'Falsche Freunde';

  @override
  String get falseFriendsDescription =>
      'Lass dich nicht täuschen — gift ≠ Gift, become ≠ bekommen';

  @override
  String get falseFriendsPrompt =>
      'Was bedeutet dieses englische Wort wirklich?';

  @override
  String get falseFriendsEmpty =>
      'Noch keine Daten zu falschen Freunden verfügbar.';

  @override
  String get falseFriendsOnboard1 =>
      'Falsche Freunde sind englische Wörter, die wie ein deutsches Wort aussehen, aber etwas anderes bedeuten — \"gift\" ist nicht \"Gift\".';

  @override
  String get falseFriendsOnboard2 =>
      'Wähle die richtige deutsche Bedeutung. Eine Auswahl ist die Lookalike-Falle!';

  @override
  String get falseFriendsOnboard3 =>
      'Nach jeder Antwort siehst du die echte Bedeutung und die Falle erklärt.';

  @override
  String falseFriendsExplain(String english, String correctMeaning,
      String german, String germanMeans) {
    return '$english = $correctMeaning — nicht „$german“ ($germanMeans)!';
  }

  @override
  String get wortfalleTitle => 'Wortfalle';

  @override
  String get wortfalleDescription =>
      'Wähle das richtige Wort — das/dass, seit/seid, Lärche/Lerche';

  @override
  String get wortfallePrompt => 'Welches Wort passt?';

  @override
  String get wortfalleOnboard1 =>
      'Manche deutschen Wörter sehen oder klingen fast gleich, bedeuten aber Verschiedenes — das/dass, seit/seid, Lärche/Lerche.';

  @override
  String get wortfalleOnboard2 =>
      'Es wird ein Satz mit einer Lücke gezeigt. Wähle das Wort, das zur Bedeutung passt.';

  @override
  String get wortfalleOnboard3 =>
      'Nach jeder Antwort siehst du, was die Wörter bedeuten.';

  @override
  String get gameRoundComplete => 'Runde geschafft!';

  @override
  String get gameBack => 'Zurück';

  @override
  String get gamePlayAgain => 'Nochmal spielen';

  @override
  String gameCorrectOfTotal(int correct, int total) {
    return '$correct von $total richtig';
  }

  @override
  String get wortbaumeisterCardTitle => 'Wort-Stückler';

  @override
  String get wortbaumeisterCardDescription =>
      'Zusammengesetzte Nomen Stück für Stück bauen';

  @override
  String get verbtrennerCardTitle => 'Verb-Trenner';

  @override
  String get verbtrennerCardDescription =>
      'Trennbare Verben erkennen: zusammen oder getrennt?';

  @override
  String achievementsBannerProgress(int unlocked, int total) {
    return '$unlocked von $total Erfolgen freigeschaltet';
  }

  @override
  String get achievementTriangleWizardTitle => 'Wort-Schlange-Meister';

  @override
  String get achievementTriangleWizardDesc =>
      'Schaffe Level 3 in Wort-Schlange.';

  @override
  String get achievementBubblePopperTitle => 'Sortier-Champion';

  @override
  String get achievementBubblePopperDesc =>
      'Schaffe Level 3 in Wort-Sortierung.';

  @override
  String get achievementPuzzleSolverTitle => 'Wort-Finder';

  @override
  String get achievementPuzzleSolverDesc => 'Schaffe Level 3 in Wortsuche.';

  @override
  String get achievementNumberWallsProTitle => 'Wort-Baumeister';

  @override
  String get achievementNumberWallsProDesc =>
      'Schaffe Level 3 in Wort-Stückler.';

  @override
  String get achievementCodebreakerProTitle => 'Weltraum-Retter';

  @override
  String get achievementCodebreakerProDesc =>
      'Schaffe Level 3 in Weltraum-Wort-Rettung.';

  @override
  String get achievementMasterBuilderTitle => 'Wortbaumeister';

  @override
  String get achievementMasterBuilderDesc =>
      'Schaffe Level 3 im Wortbaumeister.';

  @override
  String get achievementCityPlannerTitle => 'Stadt-Planer';

  @override
  String get achievementCityPlannerDesc => 'Schaffe Level 3 in Wort-Sortierer.';

  @override
  String get achievementConnectionExpertTitle => 'Galaxie-Experte';

  @override
  String get achievementConnectionExpertDesc =>
      'Schaffe Level 3 in Wort-Galaxie.';

  @override
  String get achievementArithmeticAceTitle => 'Gedächtnis-Ass';

  @override
  String get achievementArithmeticAceDesc =>
      'Erreiche Level 5 in Memory und Wortarten-Wirbel.';

  @override
  String get achievementVielseitigTitle => 'Vielseitig';

  @override
  String get achievementVielseitigDesc =>
      'Spiele mindestens vier verschiedene Spiele.';

  @override
  String get achievementAntonymAceTitle => 'Gegenwort-Ass';

  @override
  String get achievementAntonymAceDesc =>
      'Erreiche Spiellevel 3 in Gegenwort-Blitz.';

  @override
  String get achievementSynonymScholarTitle => 'Synonym-Forscher';

  @override
  String get achievementSynonymScholarDesc =>
      'Erreiche Spiellevel 3 in Synonym-Blitz.';

  @override
  String get achievementClozeMasterTitle => 'Lückentext-Meister';

  @override
  String get achievementClozeMasterDesc =>
      'Erreiche Spiellevel 3 in Lückentext-Blitz.';

  @override
  String get achievementTranslationTitanTitle => 'Übersetzungs-Titan';

  @override
  String get achievementTranslationTitanDesc =>
      'Erreiche Spiellevel 3 in Übersetzungs-Blitz.';

  @override
  String get achievementReverseLinguistTitle => 'Rückwärts-Linguist';

  @override
  String get achievementReverseLinguistDesc =>
      'Erreiche Spiellevel 3 in Rückwärts-Übersetzung.';

  @override
  String get achievementSyllableCounterTitle => 'Silben-Zähler';

  @override
  String get achievementSyllableCounterDesc =>
      'Erreiche Spiellevel 3 in Silben zählen.';

  @override
  String get achievementExpressionExpertTitle => 'Ausdruck-Experte';

  @override
  String get achievementExpressionExpertDesc =>
      'Erreiche Spiellevel 3 in Ausdruck-Blitz.';

  @override
  String get achievementHypernymHunterTitle => 'Oberbegriff-Jäger';

  @override
  String get achievementHypernymHunterDesc =>
      'Erreiche Spiellevel 3 in Oberbegriff-Blitz.';

  @override
  String get achievementWordClassWhizTitle => 'Wortart-Profi';

  @override
  String get achievementWordClassWhizDesc =>
      'Erreiche Spiellevel 3 in Wortart-Blitz.';

  @override
  String get achievementProverbSageTitle => 'Sprichwort-Weise';

  @override
  String get achievementProverbSageDesc =>
      'Erreiche Spiellevel 3 in Sprichwort-Lückentext.';

  @override
  String get achievementConjugationKingTitle => 'Konjugations-König';

  @override
  String get achievementConjugationKingDesc =>
      'Erreiche Spiellevel 3 im Konjugations-Training.';

  @override
  String get achievementVerbSplitterTitle => 'Verb-Trenner';

  @override
  String get achievementVerbSplitterDesc =>
      'Erreiche Spiellevel 3 in Verbtrenner.';

  @override
  String get achievementDefinitionWizardTitle => 'Definitions-Zauberer';

  @override
  String get achievementDefinitionWizardDesc =>
      'Erreiche Spiellevel 3 im Definition-Quiz.';

  @override
  String get achievementSentenceSmithTitle => 'Satz-Schmied';

  @override
  String get achievementSentenceSmithDesc =>
      'Erreiche Spiellevel 3 in Satzergänzung.';

  @override
  String get achievementSpellingSleutTitle => 'Rechtschreib-Spürnase';

  @override
  String get achievementSpellingSleutDesc =>
      'Erreiche Spiellevel 3 in Rechtschreib-Sucher.';

  @override
  String get achievementHomophoneHeroTitle => 'Homophon-Held';

  @override
  String get achievementHomophoneHeroDesc =>
      'Erreiche Spiellevel 3 im Homophon-Training.';

  @override
  String get achievementConfusableProTitle => 'Wortfallen-Profi';

  @override
  String get achievementConfusableProDesc =>
      'Erreiche Spiellevel 3 in Wortfalle.';

  @override
  String get achievementReviewRegularTitle => 'Wiederholungs-Champion';

  @override
  String get achievementReviewRegularDesc =>
      'Erreiche Spiellevel 5 in der Wiederholung.';

  @override
  String get diagnosticsTitle => 'Diagnose';

  @override
  String get diagnosticsSubtitle =>
      'Absturzprotokoll anzeigen (bleibt auf dem Gerät)';

  @override
  String get diagnosticsNoCrashes => 'Keine Abstürze aufgezeichnet. 🎉';

  @override
  String diagnosticsReportsOnDevice(int count) {
    return 'Absturzberichte auf diesem Gerät: $count. Die Daten bleiben hier, solange du sie nicht teilst.';
  }

  @override
  String get diagnosticsCopied =>
      'Absturzprotokoll in die Zwischenablage kopiert';

  @override
  String get diagnosticsCopyLog => 'Protokoll kopieren';

  @override
  String get diagnosticsClearLog => 'Protokoll löschen';

  @override
  String get parentDashboardTitle => 'Lernanalyse';

  @override
  String get parentDashboardSubtitle =>
      'Detaillierter Fortschritt, optional mit PIN geschützt';

  @override
  String get privacyTitle => 'Datenschutz';

  @override
  String get privacySubtitle => 'Was auf diesem Gerät gespeichert wird';

  @override
  String get deleteAllDataTitle => 'Alle Daten löschen';

  @override
  String get deleteAllDataSubtitle =>
      'Fortschritt auf diesem Gerät zurücksetzen';

  @override
  String get noSourcesFound => 'Keine Quellen gefunden';

  @override
  String get noCustomSetsYet => 'Noch keine eigenen Sets erstellt.';

  @override
  String get antonymFlashPrompt => 'Gegenteil von …';

  @override
  String get syllableCountPrompt => 'Wie viele Silben?';

  @override
  String get wordClassFlashPrompt => 'Welche Wortart?';

  @override
  String get noAntonymData =>
      'Keine Gegenwort-Daten für diese Stufe verfügbar.';

  @override
  String correctInSeconds(int n) {
    return 'richtig in ${n}s';
  }

  @override
  String get parentPinTitle => 'Analyse-PIN';

  @override
  String parentPinHelp(String pin) {
    return 'Gib den 4-stelligen Code ein.\nStandard ist $pin, bis du ihn änderst.';
  }

  @override
  String get parentPinWrong => 'Falscher Code';

  @override
  String get parentPinUnlock => 'Entsperren';

  @override
  String get parentChangePin => 'Analyse-PIN ändern';

  @override
  String get parentChangePinDialogTitle => 'PIN ändern';

  @override
  String get parentNewPinLabel => 'Neue PIN';

  @override
  String get parentConfirmPinLabel => 'Bestätigen';

  @override
  String get parentPinRequireFour => '4 Ziffern erforderlich';

  @override
  String get parentPinMismatch => 'Stimmt nicht überein';

  @override
  String get parentPinUpdated => 'PIN aktualisiert';

  @override
  String get parentSectionLanguageMastery => 'Sprach-Beherrschung';

  @override
  String get parentItemsTracked => 'Items verfolgt';

  @override
  String get parentItemsMastered => 'Davon gemeistert';

  @override
  String parentItemsMasteredValue(int count, int pct) {
    return '$count ($pct%)';
  }

  @override
  String get parentItemsDue => 'Fällig zur Wiederholung';

  @override
  String get parentSectionStrengths => 'Stärken & Schwächen';

  @override
  String get parentDataBasis => 'Datenbasis';

  @override
  String get parentNoDataYet => 'noch keine Daten';

  @override
  String get parentStrongestCategory => 'Stärkste Kategorie';

  @override
  String get parentWeakestCategory => 'Schwächste Kategorie';

  @override
  String parentCategoryValue(String name, int pct) {
    return '$name ($pct%)';
  }

  @override
  String get parentTotalAttempts => 'Gesamtversuche';

  @override
  String get parentSectionGameProgress => 'Spielfortschritt';

  @override
  String get parentGamesPlayed => 'Spiele gespielt';

  @override
  String get parentNoneYet => 'noch keine';

  @override
  String parentLevelValue(int level) {
    return 'Level $level';
  }

  @override
  String get cognitiveProfileTitle => 'Lernprofil';

  @override
  String get cognitiveProfileEmpty =>
      'Spiele ein paar Runden, um dein Profil aufzubauen.';

  @override
  String cognitiveProfileAttempts(int attempts, int areas) {
    String _temp0 = intl.Intl.pluralLogic(
      areas,
      locale: localeName,
      other: '$areas Skill-Bereichen',
      one: '1 Skill-Bereich',
    );
    return '$attempts Versuche in $_temp0';
  }

  @override
  String get categorySpelling => 'Rechtschreibung';

  @override
  String get categoryGrammar => 'Grammatik';

  @override
  String get categoryVocabulary => 'Wortschatz';

  @override
  String get categoryTextComprehension => 'Textverständnis';

  @override
  String get categoryExpression => 'Ausdruck';

  @override
  String get wordSortOnboardingTitle => 'Wort-Sortierung';

  @override
  String get wordSortOnboardingDrag =>
      'Ziehe das Wort in die passende Wortart-Kategorie.';

  @override
  String get wordSortOnboardingBuildingBlocks =>
      'Nomen, Verben und Adjektive sind die Grundbausteine. In höheren Stufen kommen Adverbien und Pronomen dazu.';

  @override
  String get wordSortOnboardingHints =>
      'Brauchst du Hilfe? Warte einen Moment — das Spiel zeigt dir nach kurzer Zeit Tipps zum aktuellen Wort.';

  @override
  String get wordSortCategoryAdverb => 'Adverb';

  @override
  String get wordSortCategoryPronoun => 'Pronomen';

  @override
  String get fontFamilyTitle => 'Schriftart';

  @override
  String get fontFamilySubtitle => 'Wähle eine Schriftart für Lerninhalte';

  @override
  String get skip => 'Überspringen';

  @override
  String get gotIt => 'Verstanden';

  @override
  String get next => 'Weiter';

  @override
  String get debugModeEnabled => 'Debug-Modus aktiviert!';

  @override
  String get synonymFlashPrompt => 'Gleichbedeutend mit …';

  @override
  String get noSynonymData => 'Keine Synonym-Daten für diese Stufe verfügbar.';

  @override
  String get noClozeSentences =>
      'Keine Beispielsätze für diese Stufe verfügbar.';

  @override
  String clozeAnswer(String word) {
    return 'Antwort: $word';
  }

  @override
  String get sriReviewHeader => 'Wiederholung';

  @override
  String get reviewNoWordsYet =>
      'Noch keine Wörter zum Wiederholen.\nSpiele ein paar Runden, damit das System deine schwachen Punkte erkennt!';

  @override
  String get difficultyVeryHard => 'Sehr schwierig';

  @override
  String get difficultyHard => 'Schwierig';

  @override
  String get difficultyPractice => 'Zum Üben';

  @override
  String get challengeTypeArticle => 'Artikel wählen';

  @override
  String get challengeTypeSpelling => 'Richtige Schreibweise';

  @override
  String get challengeTypeDefinition => 'Welches Wort passt?';

  @override
  String articleChallengePrompt(String word) {
    return 'Welcher Artikel passt?\n\"___ $word\"';
  }

  @override
  String get wordOfTheDay => 'Wort des Tages';

  @override
  String get pronounce => 'Aussprechen';

  @override
  String get tapToPractise => 'Tippen zum Üben →';

  @override
  String gradeLabel(int grade) {
    return 'Wortschatzstufe $grade';
  }

  @override
  String get sectionDefinitions => 'Bedeutungen';

  @override
  String get sectionExamples => 'Beispiele';

  @override
  String get sectionSynonyms => 'Synonyme';

  @override
  String get sectionAntonyms => 'Antonyme';

  @override
  String get didYouKnow => 'Wissenswertes';

  @override
  String get practiceNow => 'Jetzt üben';

  @override
  String get karteikasten => 'Karteikasten';

  @override
  String karteikastenCardMoved(int box, String label) {
    return 'Karte verschoben nach Box $box – $label';
  }

  @override
  String boxLabel(int n) {
    return 'Box $n';
  }

  @override
  String get boxLabelCurrent => '(jetzt)';

  @override
  String get moveCard => 'Verschieben';

  @override
  String get boxEmptyMastered =>
      'Noch keine gemeisterten Karten in dieser Box.';

  @override
  String get boxEmptyDefault => 'Diese Box ist leer.';

  @override
  String get antonymFlashOnboardingBody1 =>
      'Ein Wort erscheint — tippe schnell auf sein Gegenteil.';

  @override
  String get hypernymFlashOnboardingBody1 =>
      'Ein Wort erscheint — tippe schnell auf den passenden Oberbegriff.';

  @override
  String get noHypernymData =>
      'Keine Oberbegriff-Daten für diese Stufe verfügbar.';

  @override
  String get hypernymFlashPrompt => 'Oberbegriff für …';

  @override
  String spellingForDefinition(String definition) {
    return 'Richtige Schreibweise für:\n\"$definition\"';
  }

  @override
  String get conjugationDrillOnboardingBody1 =>
      'Ein Verb und ein Personalpronomen werden gezeigt — wähle die richtige Präsens-Form.';

  @override
  String get conjugationDrillOnboardingBody2 =>
      'Alle vier Optionen sind Formen desselben Pronomens aus verschiedenen Verben.';

  @override
  String get conjugationDrillOnboardingBody3 =>
      'Dieses Spiel ist auf Deutsch: Englische Verben konjugieren im Präsens kaum — nur die 3. Person Singular weicht ab.';

  @override
  String get spellingSpotterOnboardingBody1 =>
      'Vier Wörter werden gezeigt — eines ist richtig geschrieben, die anderen enthalten typische Fehler.';

  @override
  String get spellingSpotterOnboardingBody2 =>
      'Wörter sind nach Schwierigkeit sortiert — basierend auf echten Rechtschreibfehlern.';

  @override
  String correctAnswerReveal(String word) {
    return 'Richtige Antwort: $word';
  }

  @override
  String get exampleLabel => 'Beispiel:';

  @override
  String get definitionQuizPrompt => 'Welches Wort wird beschrieben?';

  @override
  String get noDefinitionData =>
      'Keine Definitionen für diese Stufe verfügbar.';

  @override
  String get definitionQuizOnboardingBody1 =>
      'Eine Definition wird gezeigt — wähle das passende Wort aus vier Optionen.';

  @override
  String get definitionQuizOnboardingBody2 =>
      'Alle Optionen kommen aus derselben CEFR-Stufe, damit nichts zu leicht wird.';

  @override
  String get definitionQuizOnboardingBody3 =>
      'Ab Wortschatzstufe 5 erscheint nach einer richtigen Antwort ein Sprach-Tipp zum Wort.';

  @override
  String get sentenceCompletionPrompt => 'Welches Wort passt in die Lücke?';

  @override
  String get sentenceCompletionOnboardingBody1 =>
      'Ein Satz mit einer Lücke wird gezeigt — wähle das passende Wort.';

  @override
  String get sentenceCompletionOnboardingBody2 =>
      'Es werden nur Nomen, Verben und Adjektive abgefragt, da diese eindeutig im Satz erkennbar sind.';

  @override
  String get sentenceCompletionOnboardingBody3 =>
      'Bei richtiger Antwort siehst du einen Hinweis auf die Wortbedeutung.';

  @override
  String get spellingSpotterPrompt => 'Welches Wort ist richtig geschrieben?';

  @override
  String get noSpellingData =>
      'Keine Rechtschreibdaten für diese Stufe verfügbar.';

  @override
  String get synonymFlashOnboardingBody1 =>
      'Ein Wort erscheint — tippe schnell auf ein Wort mit gleicher Bedeutung.';

  @override
  String get synonymFlashOnboardingTimer =>
      'Du hast 30 Sekunden. Je mehr richtige Antworten, desto besser dein Score.';

  @override
  String get clozeFlashOnboardingBody1 =>
      'Ein Satz erscheint mit einem fehlenden Wort — tippe die richtige Antwort.';

  @override
  String get clozeFlashOnboardingTimer =>
      'Du hast 30 Sekunden. Lies den Kontext — er hilft dir!';

  @override
  String get sriReviewOnboardingBody1 =>
      'Hier übst du deine schwächsten Wörter — basierend auf deiner Lernhistorie.';

  @override
  String get sriReviewOnboardingBody2 =>
      'Jede Aufgabe passt sich dem Wort an: Artikel, Schreibweise oder Definition.';

  @override
  String get sriReviewOnboardingBody3 =>
      'Mit jeder richtigen Antwort steigt der Easiness Factor des Wortes.';

  @override
  String get semanticsBack => 'Zurück';

  @override
  String semanticsScore(int n) {
    return 'Punkte: $n';
  }

  @override
  String semanticsProgress(int done, int total) {
    return 'Fortschritt: $done von $total';
  }

  @override
  String semanticsCombo(int n) {
    return 'Kombo mal $n';
  }

  @override
  String get syllableCountOnboardingBody1 =>
      'Ein Wort erscheint — tippe, wie viele Silben es hat.';

  @override
  String get syllableCountOnboardingTimer =>
      'Du hast 30 Sekunden. Sprich das Wort laut aus, um die Silben zu spüren.';

  @override
  String get noSyllableData => 'Keine Silbendaten für diese Stufe verfügbar.';

  @override
  String get wordClassFlashOnboardingBody1 =>
      'Ein Wort erscheint — tippe schnell auf seine Wortart.';

  @override
  String get wordClassFlashOnboardingTimer =>
      'Du hast 30 Sekunden. Nomen, Verb, Adjektiv oder Adverb?';

  @override
  String get wordClassFlashOnboardingTip =>
      'Entscheide nach Bedeutung und Form des Wortes.';

  @override
  String get noWordClassData =>
      'Keine Wortart-Daten für diese Stufe verfügbar.';

  @override
  String get wordTypeNoun => 'Nomen';

  @override
  String get wordTypeVerb => 'Verb';

  @override
  String get wordTypeAdjective => 'Adjektiv';

  @override
  String get wordTypeAdverb => 'Adverb';

  @override
  String get wordTypePronoun => 'Pronomen';

  @override
  String get wordSortHintCorrect => '✓ Richtig!';

  @override
  String get wordSortHintWrong => '✗ Falsch!';

  @override
  String wordSortHintNotA(String type) {
    return '✗ Kein $type!';
  }

  @override
  String wordSortHintSynonym(String synonyms) {
    return '✓ Synonym: $synonyms';
  }

  @override
  String wordSortHintAntonym(String antonym) {
    return '✓ Gegenteil: $antonym';
  }

  @override
  String wordSortHintNounNaming(String word) {
    return '✓ Nomen groß: $word (Großschreibung!)';
  }

  @override
  String wordSortHintVerbAction(String word) {
    return '✓ Verb: $word → beschreibt Handlung';
  }

  @override
  String wordSortHintAdjQuality(String word) {
    return '✓ Adjektiv: $word → Eigenschaft';
  }

  @override
  String wordSortHintAdjQuestion(String word) {
    return '✓ Wie-Frage: \"Wie ist es?\" → $word';
  }

  @override
  String wordSortHintAdverbAction(String word) {
    return '✓ Adverb: $word → unveränderlich!';
  }

  @override
  String wordSortHintAdverbQuestion(String word) {
    return '✓ Wie-Frage: \"Wie?\" → $word';
  }

  @override
  String wordSortHintPronounReplaces(String word) {
    return '✓ Pronomen: $word → ersetzt Nomen';
  }

  @override
  String wordSortHintPronounStands(String word) {
    return '✓ $word → steht für ein Nomen';
  }

  @override
  String wordSortDragLabel(String word) {
    return 'Wort: $word. Ziehe es auf die richtige Wortart.';
  }

  @override
  String wordSortHintCorrectAs(String word, String type) {
    return '✓ Richtig: $word ist ein $type!';
  }

  @override
  String get homophoneTitleHomophone => 'Klangzwillinge';

  @override
  String get homophoneTitleTrap => 'Wortfalle';

  @override
  String get homophoneOnboardHomophone1 =>
      'Klangzwillinge klingen gleich, werden aber unterschiedlich geschrieben — wie \"Lärche\" und \"Lerche\" oder \"Seite\" und \"Saite\".';

  @override
  String get homophoneOnboardHomophone2 =>
      'Es wird ein Satz mit einer Lücke gezeigt. Wähle die Schreibweise, die zur Bedeutung passt.';

  @override
  String get homophoneOnboardHomophone3 =>
      'Nach jeder Antwort verrät dir ein Bedeutungs-Tipp, was jede Schreibweise besonders macht.';

  @override
  String get homophoneOnboardConfusable1 =>
      'Manche Wörter sehen sich ähnlich oder klingen ähnlich, bedeuten aber etwas anderes — wie \"das\" und \"dass\" oder \"wider\" und \"wieder\".';

  @override
  String get homophoneOnboardConfusable2 =>
      'Es wird ein Satz mit einer Lücke gezeigt. Wähle das Wort, dessen Bedeutung in den Satz passt.';

  @override
  String get homophoneOnboardConfusable3 =>
      'Nach jeder Antwort siehst du eine klare Erklärung, was jedes Wort unterscheidet.';

  @override
  String get homophoneEmpty =>
      'Für diese Stufe gibt es noch keine passenden Wörter.';

  @override
  String get homophonePromptHomophone => 'Welches Wort passt?';

  @override
  String get homophonePromptConfusable => 'Welches Wort ist hier richtig?';

  @override
  String get homophoneMeanings => 'Bedeutungen';

  @override
  String get homophoneSubtitleHomophone => 'richtige Klangzwillinge';

  @override
  String get homophoneSubtitleTrap => 'richtige Wörter';

  @override
  String wordBuilderHintsUsed(int count) {
    return '$count verwendet';
  }

  @override
  String wordBuilderLevelLabel(int level) {
    return 'Stufe $level';
  }

  @override
  String wordBuilderLevelShort(int level) {
    return 'Stufe $level';
  }

  @override
  String wordBuilderWordsProgress(int done, int total) {
    return 'Wörter: $done von $total';
  }

  @override
  String wordBuilderLetterTile(String letter) {
    return 'Buchstabenkachel $letter';
  }

  @override
  String get wordBuilderTileHint => 'Tippe oder ziehe in den Wortbereich';

  @override
  String wordBuilderTimeRemaining(int seconds) {
    return 'Zeit: $seconds Sekunden';
  }

  @override
  String get wordSnakeResetSelection => 'Auswahl zurücksetzen';

  @override
  String wordSnakeScoreLabel(int score) {
    return 'Punkte: $score';
  }

  @override
  String wordSnakeCell(String letter) {
    return 'Buchstabe $letter';
  }

  @override
  String wordSnakeCellSelected(String letter, int position) {
    return 'Buchstabe $letter, Position $position';
  }

  @override
  String get wordSnakeNoPuzzles =>
      'Gerade konnte kein Rätsel erstellt werden. Probier eine andere Stufe oder komm später wieder.';

  @override
  String get wordSnakeBasicVocabulary => '⭐ Grundwortschatz';

  @override
  String get wordSnakeNoun => 'Nomen';

  @override
  String wordSnakeNounWithArticle(String article) {
    return 'Nomen ($article)';
  }

  @override
  String wordSnakeGenus(String genus) {
    return 'Genus: $genus';
  }

  @override
  String wordSnakePlural(String plural) {
    return 'Plural: $plural';
  }

  @override
  String get wordSnakeVerb => 'Verb (Tun-Wort)';

  @override
  String wordSnakeVerbForms(String ich, String du, String er) {
    return 'z.B. ich $ich, du $du, er $er';
  }

  @override
  String wordSnakeForms(String forms) {
    return 'Formen: $forms';
  }

  @override
  String get wordSnakeAdjective => 'Adjektiv (Wie-Wort)';

  @override
  String get wordSnakeAdjectivePositive => 'Adjektiv (Positiv)';

  @override
  String wordSnakeComparison(String forms) {
    return 'Steigerung: $forms';
  }

  @override
  String get wordSnakePronoun => 'Pronomen';

  @override
  String get wordSnakeArticle => 'Artikel';

  @override
  String get wordSnakeAdverb => 'Adverb';

  @override
  String get wordSnakePreposition => 'Präposition';

  @override
  String get wordSnakeConjunction => 'Konjunktion';

  @override
  String get wordSnakeParticle => 'Partikel';

  @override
  String get wordSnakeNumeral => 'Numerale';

  @override
  String get wordSnakeCaseNominative => 'Nominativ';

  @override
  String get wordSnakeCaseAccusative => 'Akkusativ';

  @override
  String get wordSnakeCaseDative => 'Dativ';

  @override
  String get wordSnakeCaseGenitive => 'Genitiv';

  @override
  String wordSnakeExample(String example) {
    return 'z.B.: $example';
  }

  @override
  String get rescueHintHeardAgain => 'Wort noch einmal angehört!';

  @override
  String rescueHintStartsWith(String prefix) {
    return 'Beginnt mit: $prefix...';
  }

  @override
  String rescueHintLetterCount(int count) {
    return '$count Buchstaben';
  }

  @override
  String rescueBestStreak(int count) {
    return 'Beste Serie: $count 🔥';
  }

  @override
  String rescueSemanticsScore(int score) {
    return 'Punkte: $score';
  }

  @override
  String rescueSemanticsStreak(int count) {
    return 'Serie: $count';
  }

  @override
  String rescueSemanticsRescued(int rescued, int total) {
    return 'Gerettet: $rescued von $total';
  }

  @override
  String rescueSemanticsLevel(int level) {
    return 'Stufe $level';
  }

  @override
  String get rescueSemanticsInputField => 'Tippe das Wort hier ein';

  @override
  String get rescueSemanticsShowHint => 'Tipp anzeigen';

  @override
  String get rescueSemanticsReadWord => 'Wort vorlesen';

  @override
  String wordMemoryScoreLabel(int score) {
    return 'Punkte: $score';
  }

  @override
  String wordMemoryMovesLabel(int moves) {
    return 'Züge: $moves';
  }

  @override
  String wordMemoryPairsLabel(int found, int total) {
    return 'Paare: $found von $total';
  }

  @override
  String wordMemoryTotalGemsLabel(int gems) {
    return 'Gesamtsumme Edelsteine: $gems';
  }

  @override
  String wordMemoryCardMatched(String text) {
    return 'Karte $text, gefunden';
  }

  @override
  String wordMemoryCardRevealed(String text) {
    return 'Karte $text, aufgedeckt';
  }

  @override
  String get wordMemoryCardHidden => 'Verdeckte Karte';

  @override
  String wordSortDropZoneLabel(String label) {
    return 'Ablagebereich: $label';
  }

  @override
  String get wordSortEmptyTitle => 'Keine Wörter verfügbar';

  @override
  String get wordSortEmptyMessage =>
      'Für diese Stufe gibt es noch keine Wörter zum Sortieren. Probiere eine andere Stufe oder komm später wieder.';

  @override
  String get wordSortGenderMasculine => 'maskulin (der)';

  @override
  String get wordSortGenderFeminine => 'feminin (die)';

  @override
  String get wordSortGenderNeuter => 'neutral (das)';

  @override
  String wordSortHintNounPluralForm(String word, String plural) {
    return '✓ Mehrzahl: $word → $plural';
  }

  @override
  String wordSortHintNounGender(String gender) {
    return '✓ Genus: $gender';
  }

  @override
  String wordSortHintNounWithArticle(String article, String word) {
    return '✓ Nomen: $article $word';
  }

  @override
  String wordSortHintDefinition(String definition) {
    return '✓ $definition';
  }

  @override
  String wordSortHintVerbPersonalForms(String ich, String du) {
    return '✓ Personalformen: ich $ich, du $du';
  }

  @override
  String wordSortHintVerbPerfect(String form) {
    return '✓ Perfekt: $form';
  }

  @override
  String wordSortHintVerbPast(String form) {
    return '✓ Präteritum: ich $form';
  }

  @override
  String wordSortHintAdjComparison(
      String word, String comparative, String superlative) {
    return '✓ Steigerung: $word → $comparative → $superlative';
  }

  @override
  String wordSortHintAdjComparative(String word, String comparative) {
    return '✓ Komparativ: $word → $comparative';
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
  String get wordSortReasonNotConjugable => 'nicht konjugierbar';

  @override
  String get wordSortReasonNotComparable => 'nicht steigerbar';

  @override
  String wordSortReasonPlural(String plural) {
    return 'Plural: $plural';
  }

  @override
  String wordSortExplainNounCapitalized(String word) {
    return '✓ $word → Nomen (Großschreibung!)';
  }

  @override
  String wordSortExplainNounNaming(String word) {
    return '✓ $word → Nomen (ein Namenwort)';
  }

  @override
  String wordSortExplainNounReasons(String reasons) {
    return '✓ Nomen: $reasons';
  }

  @override
  String wordSortReasonVerbForms(String ich, String du) {
    return 'ich $ich, du $du';
  }

  @override
  String wordSortReasonVerbFormExample(String ich) {
    return 'z.B. ich $ich';
  }

  @override
  String get wordSortReasonNoArticle => 'kein Artikel';

  @override
  String wordSortExplainVerbAction(String word) {
    return '✓ Verb: $word → Handlung!';
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
    return 'steigerbar: $comparative';
  }

  @override
  String wordSortReasonAdjExample(String word) {
    return 'der ${word}e Mann';
  }

  @override
  String wordSortExplainAdjReasons(String reasons) {
    return '✓ Adjektiv: $reasons';
  }

  @override
  String wordSortExplainAdjDefinition(String definition) {
    return '✓ Adjektiv: \"$definition\"';
  }

  @override
  String wordSortExplainAdjQuality(String word) {
    return '✓ Adjektiv: $word → beschreibt eine Eigenschaft';
  }

  @override
  String wordTypeWhirlSemanticsLevel(int level) {
    return 'Stufe $level';
  }

  @override
  String wordTypeWhirlSemanticsRound(int round, int total) {
    return 'Runde $round von $total';
  }

  @override
  String wordTypeWhirlSemanticsStreak(int streak) {
    return 'Serie: $streak';
  }

  @override
  String wordTypeWhirlSemanticsTime(int seconds) {
    return 'Zeit: $seconds Sekunden';
  }

  @override
  String wordTypeWhirlSemanticsGems(int gems) {
    return 'Edelsteine: $gems';
  }

  @override
  String wordTypeWhirlSemanticsWord(String word) {
    return 'Wort $word';
  }

  @override
  String wordTypeWhirlSemanticsTapHint(String wordType) {
    return 'Tippe wenn es ein $wordType ist';
  }

  @override
  String get wordFindPluralLabel => 'Plural';

  @override
  String get wordFindVerbFormInfinitive => 'Infinitiv';

  @override
  String get wordFindVerbFormFinite => 'finit';

  @override
  String get wordFindVerbFormParticiple => 'Partizip';

  @override
  String get translationFlashNoData =>
      'Keine Übersetzungsdaten für diese Stufe verfügbar.';

  @override
  String get translationFlashPrompt => 'Auf Englisch …';

  @override
  String translationFlashCorrectCount(int count) {
    return '$count richtig';
  }

  @override
  String get translationFlashOnboardingTap =>
      'Ein deutsches Wort erscheint — tippe schnell auf die richtige englische Übersetzung.';

  @override
  String translationFlashOnboardingTimer(int seconds) {
    return 'Du hast $seconds Sekunden. Je mehr richtige Antworten, desto besser dein Score.';
  }

  @override
  String get expressionFlashOnboardingTap =>
      'Eine Redewendung erscheint mit einer Lücke — tippe das fehlende Wort.';

  @override
  String get expressionFlashOnboardingTimer =>
      'Du hast 30 Sekunden. Kenne deine Redewendungen!';

  @override
  String get expressionFlashEmpty =>
      'Keine Redewendungen für diese Stufe verfügbar.';

  @override
  String expressionFlashCorrectCount(int n) {
    return '$n richtig';
  }

  @override
  String get expressionFlashLabel => 'Redewendung';

  @override
  String get expressionFlashBlankHint => 'Lücke — finde das fehlende Wort';

  @override
  String get proverbClozeOnboardingBody =>
      'Ein Sprichwort erscheint mit einer Lücke — tippe das richtige Wort.';

  @override
  String proverbClozeOnboardingTimer(int seconds) {
    return '$seconds Sekunden, so viele Sprichwörter wie möglich!';
  }

  @override
  String get proverbClozeEmpty =>
      'Keine Sprichwort-Daten für diese Stufe verfügbar.';

  @override
  String proverbClozeCorrectCount(int count) {
    return '$count richtig';
  }

  @override
  String get proverbClozeLabel => 'Sprichwort';

  @override
  String get conjugationDrillPrompt => 'Wie lautet die Präsensform?';

  @override
  String get conjugationDrillNoData =>
      'Keine Konjugationsdaten für diese Stufe verfügbar.';

  @override
  String grossschreibSemLevel(int level) {
    return 'Stufe $level';
  }

  @override
  String grossschreibSemScore(int score) {
    return 'Punkte: $score';
  }

  @override
  String grossschreibSemProgress(int done, int total) {
    return 'Fortschritt: $done von $total';
  }

  @override
  String grossschreibSemCombo(int combo) {
    return 'Kombo mal $combo';
  }

  @override
  String grossschreibSemWord(String word) {
    return 'Wort: $word. Tippe, um die Schreibweise zu ändern.';
  }

  @override
  String spellingSpotterCommonMistakes(String errors) {
    return 'Häufige Fehler: $errors';
  }

  @override
  String get skillLabelSpelling => 'Rechtschreibung';

  @override
  String get skillLabelArticle => 'Artikel';

  @override
  String get skillLabelPlural => 'Plural';

  @override
  String get skillLabelWordType => 'Wortart';

  @override
  String get skillLabelSentence => 'Satzbau';

  @override
  String get skillLabelPunctuation => 'Zeichensetzung';

  @override
  String get skillLabelCapitalization => 'Großschreibung';

  @override
  String get skillLabelConjugation => 'Konjugation';

  @override
  String get skillLabelCase => 'Fall';

  @override
  String get skillLabelVocabulary => 'Wortschatz';

  @override
  String get skillLabelReading => 'Lesen';
}
