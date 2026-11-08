import 'package:flutter/widgets.dart';

/// Interface language is independent of the German learning material.
class KompassStrings {
  final bool german;
  const KompassStrings(this.german);
  factory KompassStrings.of(BuildContext context) =>
      KompassStrings(Localizations.localeOf(context).languageCode == 'de');
  String choose(String de, String en) => german ? de : en;
  String get title => 'Kompass 4 · Deutsch';
  String get back => choose('Zurück', 'Back');
  String get next => choose('Weiter', 'Next');
  String get close => choose('Schließen', 'Close');
  String get cancel => choose('Abbrechen', 'Cancel');
  String get continueLabel => choose('Fortsetzen', 'Continue');
  String get text => choose('Lesetext', 'Reading text');
  String get answer => choose('Deine Antwort', 'Your answer');
  String get check => choose('Antwort prüfen', 'Check answer');
  String get finish => choose('Runde abschließen', 'Finish session');
  String get skip => choose('Überspringen', 'Skip');
  String get notTaught => choose('Noch nicht gelernt', 'Not taught yet');
  String get pending => choose('Rückmeldung offen', 'Awaiting review');
  String get review => choose('Mit Kriterien prüfen', 'Review with rubric');
  String get practice => choose('Mit Unterstützung üben', 'Supported practice');
  String get independent =>
      choose('Selbstständig bearbeiten', 'Work independently');
  String get startCheck => choose('Start-Check', 'Starting check');
  String get paper => choose('Vom Papier übertragen', 'Enter paper answers');
  String get report => choose('Mein Lernbild', 'My learning picture');
  String get save => choose('Speichern', 'Save');
  String get retry => choose('Erneut versuchen', 'Try again');
  String get minutes => choose('Minuten', 'minutes');
  String get points => choose('Punkte', 'points');
  String get saved =>
      choose('Auf diesem Gerät gespeichert', 'Saved on this device');
  String get storageWarning => choose(
      'Das Speichern auf diesem Gerät hat nicht geklappt. Lass diese Seite geöffnet und versuche es erneut.',
      'Saving on this device failed. Keep this page open and try again.');
  String domain(String domain) => switch (domain) {
        'reading' => choose('Lesen', 'Reading'),
        'spelling' => choose('Rechtschreibung', 'Spelling'),
        'language' => choose('Sprache untersuchen', 'Language'),
        _ => choose('Aufträge verstehen', 'Understanding instructions'),
      };
  String game(String domain) => switch (domain) {
        'reading' => 'Lesedetektiv',
        'spelling' => 'Wörter prüfen',
        'language' => 'Satzwerkstatt',
        _ => 'Auftragspilot',
      };
  String gameGoal(String domain) => switch (domain) {
        'reading' => choose('Genau lesen und Belege finden.',
            'Read closely and find evidence.'),
        'spelling' => choose('Wörter prüfen und Schreibweisen begründen.',
            'Check spelling and explain your strategy.'),
        'language' => choose('Wörter und Sätze untersuchen.',
            'Explore how words and sentences work.'),
        _ => choose('Erkennen, was eine Aufgabe verlangt.',
            'Understand what a task asks you to do.'),
      };
  String state(String state) => switch (state) {
        'secure' => choose('Mehrfach selbstständig gezeigt',
            'Shown independently several times'),
        'developing' => choose('Auf dem Weg', 'Developing'),
        'supported' => choose('Mit Hilfe gezeigt', 'Shown with support'),
        'learning' => choose('Daran arbeite ich', 'Working on this'),
        _ => choose('Noch nicht beobachtet', 'Not yet observed'),
      };
  String mode(String mode) => switch (mode) {
        'independent' => independent,
        'startCheck' => startCheck,
        'paper' => paper,
        _ => practice,
      };
}

String kompassPoints(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();
