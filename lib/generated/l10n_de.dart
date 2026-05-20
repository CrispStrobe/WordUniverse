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
  String get welcome => 'Entdecke das Wort-Universum!';

  @override
  String get startAdventure => 'Starte Wort-Abenteuer';

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
  String get appName => 'Wort-Universum';

  @override
  String get appLegalese => '© 2025 CrispStrobe';

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
  String get correct => 'Richtig!';

  @override
  String get gameOver => 'Mission abgeschlossen!';

  @override
  String get backToMenu => 'Zurück zur Missionskontrolle';

  @override
  String get playAgain => 'Nochmal spielen';

  @override
  String get adaptiveDifficulty => 'Angepasste Schwierigkeit';

  @override
  String get adaptiveDifficultyDesc => 'Passt Aufgaben an dein Können an';

  @override
  String get adjustProblems => 'Passe die Aufgaben an deine Fähigkeiten an';

  @override
  String get gameMenu => 'Missionskontrolle';

  @override
  String get level => 'Level';

  @override
  String get lives => 'Hüllenintegrität';

  @override
  String get time => 'Zeit';

  @override
  String get incorrect => 'Fehler!';

  @override
  String get excellent => 'Hervorragende Arbeit, Kommandant!';

  @override
  String get good => 'Gut gemacht!';

  @override
  String get tryAgain => 'Nochmal versuchen!';

  @override
  String get nextLevel => 'Nächste Mission';

  @override
  String get settings => 'Einstellungen';

  @override
  String get sound => 'Soundeffekte';

  @override
  String get music => 'Musik';

  @override
  String get language => 'Sprache';

  @override
  String get progress => 'Karrierefortschritt';

  @override
  String get achievements => 'Erfolge';

  @override
  String get congratulations => 'Herzlichen Glückwunsch, Kommandant!';

  @override
  String missionsCompleted(int count) {
    return 'Missionen abgeschlossen: $count';
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
  String get difficultyDescGrade3 => 'Einfache Wörter (Klasse 1-2)';

  @override
  String get difficultyDescGrade4 => 'Häufige Wörter (Klasse 3-4)';

  @override
  String get difficultyDescGrade5 => 'Fortgeschrittene Wörter (Klasse 5-6)';

  @override
  String get difficultyDescGrade6 => 'Experten-Wortschatz (Klasse 6+)';

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
  String get targetAge => 'Zielalter';

  @override
  String get targetAgeRange => '6-12 Jahre (Klasse 1-6)';

  @override
  String get aboutApp =>
      'Wort-Universum hilft Schülern, Rechtschreibung und Wortschatz durch fesselnde Spiele zu lernen.';

  @override
  String get debugPanelTitle => 'Debug-Panel';

  @override
  String get debugForceUnlock => 'Vollversion erzwingen';

  @override
  String get debugApplyAndClose => 'Anwenden & Schließen';

  @override
  String get parentalGateTitle => 'Kindersicherung';

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
  String get contactingStore => 'Verbinde mit Missionskontrolle...';

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
  String get achievementLevelExplorerTitle => 'Level-Entdecker';

  @override
  String get achievementLevelExplorerDesc => 'Erreiche Level 5';

  @override
  String get achievementSpaceCommanderTitle => 'Weltraum-Kommandant';

  @override
  String get achievementSpaceCommanderDesc => 'Erreiche Level 10';

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
  String get preparingMission => 'Bereite deine Sprach-Mission vor...';

  @override
  String get initializing => 'Initialisiere Wort-Universum...';

  @override
  String get loadingAssets => 'Lade Spiel-Assets...';

  @override
  String get loadingProgress => 'Lade gespeicherten Fortschritt...';

  @override
  String get preparingSpaceStation => 'Bereite Raumstation vor...';

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
  String get customSetNameLabel => 'Name des Sets';

  @override
  String get customSetNameHint => 'z.B. \'Schwierige Verben\'';

  @override
  String get customSetDescriptionLabel => 'Beschreibung';

  @override
  String get customSetDescriptionHint =>
      'Eine kurze Beschreibung dieses Sets...';

  @override
  String get customSetTargetGrade => 'Ziel-Klassenstufe';

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
  String get grossschreibTitle => 'Großschreibungs-Galaxie';

  @override
  String get grossschreibClickHint => 'Klicke auf das Wort!';

  @override
  String get grossschreibCheck => 'PRÜFEN';

  @override
  String get grossstadtTitle => 'Groß oder klein?';

  @override
  String get grossstadtCapital => 'GROSS';

  @override
  String get grossstadtLower => 'klein';

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
  String get parentDashboardTitle => 'Eltern-Übersicht';

  @override
  String get parentPinTitle => 'Eltern-PIN';

  @override
  String parentPinHelp(String pin) {
    return 'Gib den 4-stelligen Code ein.\nStandard ist $pin, bis du ihn änderst.';
  }

  @override
  String get parentPinWrong => 'Falscher Code';

  @override
  String get parentPinUnlock => 'Entsperren';

  @override
  String get parentChangePin => 'Eltern-PIN ändern';

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
      'Nomen, Verben und Adjektive sind die Grundbausteine. Höhere Klassen bringen Adverbien und Pronomen dazu.';

  @override
  String get wordSortOnboardingHints =>
      'Brauchst du Hilfe? Warte einen Moment — das Spiel zeigt dir nach kurzer Zeit Tipps zum aktuellen Wort.';

  @override
  String get wordSortCategoryAdverb => 'Adverb';

  @override
  String get wordSortCategoryPronoun => 'Pronomen';
}
