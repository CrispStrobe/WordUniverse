class AppFonts {
  // These 'family' names MUST match your pubspec.yaml
  static const String standard = 'SpaceGrotesk';
  static const String grundschrift = 'Grundschrift';
  static const String sasBienchen = 'SASBienchen';
  static const String berner = 'BernerBasisschrift';
  static const String didactGothic = 'DidactGothic';
  static const String euroScript = 'EuroScript';
  static const String gruenewald = 'Gruenewald';
  static const String letsTrace = 'LetsTrace';
  static const String schulfibelNord = 'SchulfibelNord';
  static const String schulkursiv = 'Schulkursiv';
  static const String simplePrint = 'SimplePrint';


  // This map is used by the settings screen dropdown
  static final Map<String, String> selectableFonts = {
    // Key: The family name from pubspec.yaml
    // Value: The display name for the user
    standard: 'Standard (Space Grotesk)',
    grundschrift: 'Grundschrift',
    sasBienchen: 'SAS Bienchen',
    berner: 'Berner Basisschrift',
    didactGothic: 'Didact Gothic',
    euroScript: 'EuroScript',
    gruenewald: 'Gruenewald',
    letsTrace: 'LetsTrace',
    schulfibelNord: 'Schulfibel Nord',
    schulkursiv: 'Schulkursiv',
    simplePrint: 'Simple Print',
  };
}