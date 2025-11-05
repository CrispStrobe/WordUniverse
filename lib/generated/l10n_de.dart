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
  String get startAdventure => 'Starte dein Wort-Abenteuer';

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
  String get spaceWordRescueTitle => 'Wort-Rettung';

  @override
  String get spaceWordRescueInstructions => 'Rette Wörter vor dem Abdriften!';

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
  String get developerName => 'Wort-Universum Team';

  @override
  String get targetAge => 'Zielalter';

  @override
  String get targetAgeRange => '6-12 Jahre (Klasse 1-6)';

  @override
  String get aboutApp =>
      'Wort-Universum hilft Grundschülern, Rechtschreibung und Wortschatz durch fesselnde Weltraum-Spiele zu lernen.';

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
}
