// lib/core/models/skill_category.dart
import 'package:flutter/material.dart';

// --- ENUMS FOR VOCABULARY & GRAMMAR MODELS ---
// This is now the SINGLE source of truth for these enums.

// Represents the type of word (Part-of-Speech)
enum GermanWordType {
  substantiv,
  verb,
  adjektiv,
  adverb,
  artikel,
  pronomen,
  praeposition,
  konjunktion,
  partikel,
  numerale,
  kardinalzahlwort,
  ordinalzahlwort,
  affix,
  mehrwortausdruck,
  andere, // Fallback type
}

// Represents the difficulty of a word's spelling
enum SpellingDifficulty { 
  easy, 
  medium, 
  hard, 
  expert 
}

// Represents the specific language skill being practiced
enum LanguageSkillType {
  spelling,          // Spelling individual words
  articleSelection,  // Der/die/das selection
  pluralForm,       // Singular to plural conversion
  wordType,         // Identifying noun/verb/adjective etc.
  sentenceStructure,// Understanding sentence construction
  punctuation,      // Comma placement, etc.
  capitalization,   // German capitalization rules
  verbConjugation,  // Verb forms
  caseUsage,        // Nominativ/Akkusativ/Dativ/Genitiv
  vocabulary,       // Word meaning: synonyms, antonyms, definitions, translations, hypernyms
  reading,          // Reading in context: cloze, expressions, proverbs
}


// --- ENUMS FROM YOUR PROVIDED FILE ---

// Grade levels for German primary school (Grundschule)
enum GradeLevel {
  grade1, // Klasse 1 (Age 6-7)
  grade2, // Klasse 2 (Age 7-8)
  grade3, // Klasse 3 (Age 8-9)
  grade4, // Klasse 4 (Age 9-10)
  grade5, // Klasse 5 (Age 10-11)
  grade6, // Klasse 6 (Age 11-12)
}

// Language skill categories aligned with German curriculum
enum LanguageCategory {
  rechtschreibung, // Spelling & Orthography
  grammatik, // Grammar
  wortschatz, // Vocabulary
  textverstaendnis, // Reading Comprehension
  ausdruck, // Expression & Writing
}

// Specific German grammar topics
enum GrammarTopic {
  artikel, // Der, die, das
  mehrzahl, // Plural forms
  wortarten, // Word types (noun, verb, etc.)
  satzglieder, // Sentence parts
  zeitformen, // Verb tenses
  faelle, // Cases (Nominativ, Akkusativ, Dativ, Genitiv)
  grossschreibung, // Capitalization rules
  zeichensetzung, // Punctuation
}

// Spelling focus areas
enum SpellingTopic {
  grundwoerter, // Basic sight words
  silben, // Syllables
  doppelkonsonanten, // Double consonants
  dehnungs_h, // Silent h (Dehnungs-h)
  umlaute, // Ä, Ö, Ü
  scharfes_s, // ß usage
  ie_schreibung, // ie vs i
  endungen, // Word endings (-ung, -heit, -keit)
}

// Word categories for vocabulary learning
enum WordCategory {
  menschen, // People & family
  tiere, // Animals
  schule, // School
  zuhause, // Home
  essen, // Food
  koerper, // Body parts
  kleidung, // Clothing
  natur, // Nature
  fahrzeuge, // Vehicles
  zeit, // Time & calendar
  gefuehle, // Emotions
  aktivitaeten, // Activities
  farben, // Colors
  zahlen, // Numbers
  formen, // Shapes
}

// --- DATA CLASSES FROM YOUR PROVIDED FILE ---

// Data class for skill categories
class SkillCategory {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final LanguageCategory category;
  final GradeLevel minGrade;
  final GradeLevel? maxGrade;
  final List<String> keywords;
  final int difficultyLevel; // 1-10

  const SkillCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.category,
    required this.minGrade,
    this.maxGrade,
    required this.keywords,
    required this.difficultyLevel,
  });
}

// Predefined skill categories for German primary education
class SkillCategories {
  static const List<SkillCategory> all = [
    // RECHTSCHREIBUNG (Spelling)
    SkillCategory(
      id: 'basic_spelling',
      name: 'Grundwortschatz',
      description: 'Häufige Wörter richtig schreiben',
      icon: Icons.abc,
      color: Colors.blue,
      category: LanguageCategory.rechtschreibung,
      minGrade: GradeLevel.grade1,
      keywords: ['buchstaben', 'wörter', 'schreiben'],
      difficultyLevel: 1,
    ),
    SkillCategory(
      id: 'syllables',
      name: 'Silbentrennung',
      description: 'Wörter in Silben aufteilen',
      icon: Icons.splitscreen,
      color: Colors.teal,
      category: LanguageCategory.rechtschreibung,
      minGrade: GradeLevel.grade2,
      keywords: ['silben', 'trennung', 'wortteilung'],
      difficultyLevel: 3,
    ),
    SkillCategory(
      id: 'special_letters',
      name: 'Besondere Buchstaben',
      description: 'Umlaute, ß und besondere Schreibweisen',
      icon: Icons.text_fields,
      color: Colors.purple,
      category: LanguageCategory.rechtschreibung,
      minGrade: GradeLevel.grade2,
      keywords: ['umlaute', 'ß', 'äöü'],
      difficultyLevel: 4,
    ),

    // GRAMMATIK (Grammar)
    SkillCategory(
      id: 'articles',
      name: 'Artikel',
      description: 'Der, die oder das? Begleiter richtig verwenden',
      icon: Icons.bookmark,
      color: Colors.orange,
      category: LanguageCategory.grammatik,
      minGrade: GradeLevel.grade1,
      keywords: ['der', 'die', 'das', 'artikel'],
      difficultyLevel: 2,
    ),
    
    // --- THIS IS THE FIX for the crash ---
    SkillCategory(
      id: 'word_types', // This ID matches 'word_types' in game_provider.dart
      name: 'Wortarten',
      description: 'Nomen, Verben und Adjektive erkennen',
      icon: Icons.category,
      color: Colors.green,
      category: LanguageCategory.grammatik,
      minGrade: GradeLevel.grade2,
      keywords: ['nomen', 'verben', 'adjektive'],
      difficultyLevel: 3,
    ),
    // --- END FIX ---

    SkillCategory(
      id: 'plural',
      name: 'Mehrzahl bilden',
      description: 'Von der Einzahl zur Mehrzahl',
      icon: Icons.group,
      color: Colors.indigo,
      category: LanguageCategory.grammatik,
      minGrade: GradeLevel.grade2,
      keywords: ['mehrzahl', 'plural', 'einzahl'],
      difficultyLevel: 3,
    ),
    SkillCategory(
      id: 'sentences',
      name: 'Satzbildung',
      description: 'Vollständige Sätze bilden und verstehen',
      icon: Icons.format_align_left,
      color: Colors.red,
      category: LanguageCategory.grammatik,
      minGrade: GradeLevel.grade2,
      maxGrade: GradeLevel.grade4,
      keywords: ['sätze', 'satzglieder', 'satzbau'],
      difficultyLevel: 5,
    ),
    SkillCategory(
      id: 'verb_tenses',
      name: 'Zeitformen',
      description: 'Gegenwart, Vergangenheit und Zukunft',
      icon: Icons.access_time,
      color: Colors.amber,
      category: LanguageCategory.grammatik,
      minGrade: GradeLevel.grade3,
      keywords: ['präsens', 'perfekt', 'zeitformen'],
      difficultyLevel: 6,
    ),
    SkillCategory(
      id: 'cases',
      name: 'Die vier Fälle',
      description: 'Nominativ, Akkusativ, Dativ und Genitiv',
      icon: Icons.layers,
      color: Colors.deepPurple,
      category: LanguageCategory.grammatik,
      minGrade: GradeLevel.grade4,
      keywords: ['fälle', 'kasus', 'nominativ'],
      difficultyLevel: 8,
    ),

    // WORTSCHATZ (Vocabulary)
    SkillCategory(
      id: 'basic_vocab',
      name: 'Grundwortschatz',
      description: 'Wichtige Wörter des täglichen Lebens',
      icon: Icons.book,
      color: Colors.lightBlue,
      category: LanguageCategory.wortschatz,
      minGrade: GradeLevel.grade1,
      keywords: ['wörter', 'vokabeln', 'alltag'],
      difficultyLevel: 1,
    ),
    SkillCategory(
      id: 'theme_vocab',
      name: 'Themenwortschatz',
      description: 'Wörter zu verschiedenen Themen lernen',
      icon: Icons.collections_bookmark,
      color: Colors.cyan,
      category: LanguageCategory.wortschatz,
      minGrade: GradeLevel.grade2,
      keywords: ['themen', 'wortfelder', 'kategorien'],
      difficultyLevel: 3,
    ),
    SkillCategory(
      id: 'synonyms',
      name: 'Wortfamilien & Synonyme',
      description: 'Ähnliche und verwandte Wörter',
      icon: Icons.compare_arrows,
      color: Colors.tealAccent,
      category: LanguageCategory.wortschatz,
      minGrade: GradeLevel.grade3,
      keywords: ['synonyme', 'wortfamilien', 'ähnlich'],
      difficultyLevel: 5,
    ),

    // TEXTVERSTÄNDNIS (Reading Comprehension)
    SkillCategory(
      id: 'reading_basics',
      name: 'Erste Texte',
      description: 'Einfache Texte lesen und verstehen',
      icon: Icons.chrome_reader_mode,
      color: Colors.brown,
      category: LanguageCategory.textverstaendnis,
      minGrade: GradeLevel.grade1,
      keywords: ['lesen', 'verstehen', 'texte'],
      difficultyLevel: 2,
    ),
    SkillCategory(
      id: 'story_comprehension',
      name: 'Geschichten verstehen',
      description: 'Handlung und Figuren in Geschichten erkennen',
      icon: Icons.auto_stories,
      color: Colors.pink,
      category: LanguageCategory.textverstaendnis,
      minGrade: GradeLevel.grade3,
      keywords: ['geschichten', 'märchen', 'erzählungen'],
      difficultyLevel: 5,
    ),

    // AUSDRUCK (Expression)
    SkillCategory(
      id: 'sentence_writing',
      name: 'Sätze schreiben',
      description: 'Eigene Sätze formulieren',
      icon: Icons.edit,
      color: Colors.deepOrange,
      category: LanguageCategory.ausdruck,
      minGrade: GradeLevel.grade2,
      keywords: ['schreiben', 'formulieren', 'ausdruck'],
      difficultyLevel: 4,
    ),
    SkillCategory(
      id: 'creative_writing',
      name: 'Kreatives Schreiben',
      description: 'Eigene kleine Geschichten verfassen',
      icon: Icons.create,
      color: Colors.lime,
      category: LanguageCategory.ausdruck,
      minGrade: GradeLevel.grade3,
      keywords: ['geschichten', 'kreativ', 'fantasie'],
      difficultyLevel: 6,
    ),
  ];

  // Helper methods
  static List<SkillCategory> getByGrade(GradeLevel grade) {
    return all.where((skill) {
      final gradeIndex = GradeLevel.values.indexOf(grade);
      final minIndex = GradeLevel.values.indexOf(skill.minGrade);
      final maxIndex = skill.maxGrade != null
          ? GradeLevel.values.indexOf(skill.maxGrade!)
          : GradeLevel.values.length - 1;
      return gradeIndex >= minIndex && gradeIndex <= maxIndex;
    }).toList();
  }

  static List<SkillCategory> getByCategory(LanguageCategory category) {
    return all.where((skill) => skill.category == category).toList();
  }

  static SkillCategory? getById(String id) {
    try {
      return all.firstWhere((skill) => skill.id == id);
    } catch (_) {
      return null;
    }
  }

  static String getGradeName(GradeLevel grade) {
    switch (grade) {
      case GradeLevel.grade1:
        return '1. Klasse';
      case GradeLevel.grade2:
        return '2. Klasse';
      case GradeLevel.grade3:
        return '3. Klasse';
      case GradeLevel.grade4:
        return '4. Klasse';
      case GradeLevel.grade5:
        return '5. Klasse';
      case GradeLevel.grade6:
        return '6. Klasse';
    }
  }

  static String getCategoryName(LanguageCategory category) {
    switch (category) {
      case LanguageCategory.rechtschreibung:
        return 'Rechtschreibung';
      case LanguageCategory.grammatik:
        return 'Grammatik';
      case LanguageCategory.wortschatz:
        return 'Wortschatz';
      case LanguageCategory.textverstaendnis:
        return 'Textverständnis';
      case LanguageCategory.ausdruck:
        return 'Ausdruck';
    }
  }
}