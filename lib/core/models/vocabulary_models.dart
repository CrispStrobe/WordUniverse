// lib/core/models/vocabulary_models.dart

import 'skill_category.dart';

// --- API ENRICHMENT MODELS (NEW) ---
class ApiEnrichment {
  final String enrichmentStatus;
  final String? primaryPos;
  final String? primaryLemma;
  final List<String> definitions;
  final List<ApiPronunciation> pronunciation;
  final List<String> examples;
  final List<String> synonyms;
  final List<String> antonyms;
  final List<ApiConceptNetRelation> conceptnet;
  final List<ApiAlternativeAnalysis> alternativeAnalyses;
  final String? apiInfo;
  final List<Map<String, dynamic>>? inflections; // Raw Wiktionary table
  final Map<String, dynamic>? inflectionsPattern; // Pattern.de table
  final List<String> hyphenation;

  final List<ApiTranslation>? translations;
  final List<String>? derivedTerms;
  final List<String>? relatedTerms;
  
  final List<ApiSemanticRelation> semanticRelations; 
  
  ApiEnrichment({
    required this.enrichmentStatus,
    this.primaryPos,
    this.primaryLemma,
    required this.definitions,
    required this.pronunciation,
    required this.examples,
    required this.synonyms,
    required this.antonyms,
    required this.conceptnet,
    required this.alternativeAnalyses,
    this.apiInfo,
    this.inflections,
    this.inflectionsPattern,
    required this.semanticRelations,
    required this.hyphenation,
    required this.translations,
    required this.derivedTerms,
    required this.relatedTerms,
  });

  factory ApiEnrichment.fromJson(Map<String, dynamic> json) {
    return ApiEnrichment(
      enrichmentStatus: json['enrichment_status'] ?? 'unknown',
      primaryPos: json['primary_pos'],
      primaryLemma: json['primary_lemma'],
      definitions: List<String>.from(json['definitions'] ?? []),
      pronunciation: (json['pronunciation'] as List<dynamic>?)
              ?.map((p) => ApiPronunciation.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      examples: List<String>.from(json['examples'] ?? []),
      synonyms: List<String>.from(json['synonyms'] ?? []),
      antonyms: List<String>.from(json['antonyms'] ?? []),
      conceptnet: (json['conceptnet'] as List<dynamic>?)
              ?.map((c) =>
                  ApiConceptNetRelation.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      alternativeAnalyses: (json['alternative_analyses'] as List<dynamic>?)
              ?.map((a) =>
                  ApiAlternativeAnalysis.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      apiInfo: json['api_info'],
      inflections:
          List<Map<String, dynamic>>.from(json['inflections'] ?? []),
      inflectionsPattern: json['inflections_pattern'] as Map<String, dynamic>?,
      
      // --- NEW: Parsing for semantic_relations ---
      semanticRelations: (json['semantic_relations'] as List<dynamic>?)
              ?.map((r) =>
                  ApiSemanticRelation.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      hyphenation: List<String>.from(json['hyphenation'] ?? []),
      translations: (json['wiktionary_translations'] as List<dynamic>?)
              ?.map((t) =>
                  ApiTranslation.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      derivedTerms: List<String>.from(json['wiktionary_derived_terms'] ?? []),
      relatedTerms: List<String>.from(json['wiktionary_related_terms'] ?? []),
    );
  }
}

class ApiPronunciation {
  final String? ipa;
  final String? audio;

  ApiPronunciation({this.ipa, this.audio});

  factory ApiPronunciation.fromJson(Map<String, dynamic> json) {
    return ApiPronunciation(
      ipa: json['ipa'],
      audio: json['audio'],
    );
  }
}

class ApiConceptNetRelation {
  final String? relation;
  final String? target;
  final double? weight;

  ApiConceptNetRelation({this.relation, this.target, this.weight});

  factory ApiConceptNetRelation.fromJson(Map<String, dynamic> json) {
    return ApiConceptNetRelation(
      relation: json['relation'],
      target: json['target'],
      weight: (json['weight'] as num?)?.toDouble(),
    );
  }
}

class ApiAlternativeAnalysis {
  final String? pos;
  final String? lemma;
  final String? definition;

  ApiAlternativeAnalysis({this.pos, this.lemma, this.definition});

  factory ApiAlternativeAnalysis.fromJson(Map<String, dynamic> json) {
    return ApiAlternativeAnalysis(
      pos: json['pos'],
      lemma: json['lemma'],
      definition: json['definition'],
    );
  }
}

// --- NEW: Class for semantic_relations ---
class ApiSemanticRelation {
  final String? definition;
  final List<String> synonyms;
  final List<String> antonyms;

  ApiSemanticRelation({this.definition, required this.synonyms, required this.antonyms});

  factory ApiSemanticRelation.fromJson(Map<String, dynamic> json) {
    return ApiSemanticRelation(
      definition: json['definition'],
      synonyms: List<String>.from(json['synonyms'] ?? []),
      antonyms: List<String>.from(json['antonyms'] ?? []),
    );
  }
}
// --- END NEW ---


// --- CORE VOCABULARY MODELS ---

class GraphematicVariant {
  final String spelling;
  final double probability;

  GraphematicVariant({required this.spelling, required this.probability});

  factory GraphematicVariant.fromJson(Map<String, dynamic> json) {
    return GraphematicVariant(
      spelling: json['spelling'],
      probability: (json['probability'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'spelling': spelling,
        'probability': probability,
      };
}

class GermanWord {
  final String id;
  final String word;
  final String? article;
  final GermanWordType wordType;
  final int gradeLevel;
  final String lemma;
  final String? forms;
  final String? url;
  final List<String> sources;
  final bool isGrundwortschatzBW;
  final String? genus;
  final bool nurImPlural;
  final Map<String, dynamic>? inflectionData;
  final String? ipaPhoneme;
  final String? sampaPhoneme;
  final List<GraphematicVariant> graphematicVariants;
  final String? caseSpacy;
  final String? numberSpacy;
  final String? degreeSpacy;
  final String? pronTypeSpacy;
  final String? verbFormSpacy;
  final String? plural;
  final List<WordCategory> categories;
  final List<String> exampleSentences;
  final SpellingDifficulty spellingDifficulty;
  final List<String>? commonMistakes;
  final String? audioPath;

  final ApiEnrichment? apiEnrichment;
  
  final Map<String, dynamic>? frequencyData;
  final double? averageRank;
  final Map<String, dynamic>? artikelDetailsNRW;
  final Map<String, dynamic>? morphematischesPrinzip;
  final List<String>? hyphenation;
  final List<Map<String, dynamic>>? wiktionaryInflections;

  // --- FIX: ADDED MISSING CLASS FIELDS ---
  final List<ApiTranslation>? translations;
  final List<String>? derivedTerms;
  final List<String>? relatedTerms;
  // --- END FIX ---

  GermanWord({
    required this.id,
    required this.word,
    this.article,
    required this.wordType,
    required this.gradeLevel,
    required this.lemma,
    this.forms,
    this.url,
    required this.sources,
    required this.isGrundwortschatzBW,
    this.genus,
    required this.nurImPlural,
    this.inflectionData,
    this.ipaPhoneme,
    this.sampaPhoneme,
    required this.graphematicVariants,
    this.caseSpacy,
    this.numberSpacy,
    this.degreeSpacy,
    this.pronTypeSpacy,
    this.verbFormSpacy,
    this.plural,
    required this.categories,
    required this.exampleSentences,
    required this.spellingDifficulty,
    this.commonMistakes,
    this.audioPath,
    this.apiEnrichment,
    this.frequencyData,
    this.averageRank,
    this.artikelDetailsNRW,
    this.morphematischesPrinzip,
    this.hyphenation,
    this.wiktionaryInflections,
    this.translations, // This was correctly in the constructor
    this.derivedTerms, // This was correctly in the constructor
    this.relatedTerms, // This was correctly in the constructor
  });

  factory GermanWord.fromJson(Map<String, dynamic> json) {
    final apiData = json['apiEnrichment'] != null
        ? ApiEnrichment.fromJson(json['apiEnrichment'] as Map<String, dynamic>)
        : null;

    final variantsList = (json['graphematicVariants'] as List<dynamic>?) ?? [];
    final variants = variantsList
        .map((v) => GraphematicVariant.fromJson(v as Map<String, dynamic>))
        .toList();

    return GermanWord(
      id: json['id'],
      word: json['word'],
      article: json['article'],
      wordType: GermanWordType.values.firstWhere(
        (e) => e.toString().split('.').last == json['wordType'],
        orElse: () => GermanWordType.andere,
      ),
      gradeLevel: json['gradeLevel'] ?? 1,
      lemma: apiData?.primaryLemma ?? json['lemma'] ?? json['word'],
      forms: json['forms'],
      url: json['url'],
      sources: List<String>.from(json['sources'] ?? []),
      isGrundwortschatzBW: json['isGrundwortschatzBW'] ?? false,
      genus: json['genus'],
      nurImPlural: json['nurImPlural'] ?? false,

      // This line now acts as a fallback if wiktionaryInflections is missing
      inflectionData: apiData?.inflectionsPattern ??
          json['inflectionData'] as Map<String, dynamic>?,
      
      ipaPhoneme: apiData?.pronunciation
              .firstWhere((p) => p.ipa != null,
                  orElse: () => ApiPronunciation())
              .ipa ??
          json['ipaPhoneme'],
      sampaPhoneme: json['sampaPhoneme'],
      graphematicVariants: variants,
      caseSpacy: json['caseSpacy'],
      numberSpacy: json['numberSpacy'],
      degreeSpacy: json['degreeSpacy'],
      pronTypeSpacy: json['pronTypeSpacy'],
      verbFormSpacy: json['verbFormSpacy'],
      plural: json['plural'],
      categories: (json['categories'] as List<dynamic>?)
              ?.map((c) => WordCategory.values.firstWhere(
                    (e) => e.toString().split('.').last == c,
                    orElse: () => WordCategory.schule,
                  ))
              .toList() ??
          [],
      exampleSentences: (apiData?.examples.isNotEmpty ?? false)
          ? apiData!.examples
          : List<String>.from(json['exampleSentences'] ?? []),
      spellingDifficulty:
          SpellingDifficulty.values[json['spellingDifficulty'] ?? 0],
      commonMistakes: json['commonMistakes'] != null
          ? List<String>.from(json['commonMistakes'])
          : null,
      audioPath: apiData?.pronunciation
              .firstWhere((p) => p.audio != null,
                  orElse: () => ApiPronunciation())
              .audio ??
          json['audioPath'],
      apiEnrichment: apiData,
      hyphenation: apiData?.hyphenation,

      // This is the new, primary source for inflection data
      wiktionaryInflections: apiData?.inflections,
      translations: apiData?.translations,
      derivedTerms: apiData?.derivedTerms,
      relatedTerms: apiData?.relatedTerms,
      
      frequencyData: json['frequencyData'] as Map<String, dynamic>?,
      averageRank: (json['averageRank'] as num?)?.toDouble(),
      artikelDetailsNRW: json['artikelDetailsNRW'] as Map<String, dynamic>?,
      // Note: The key in the JSON has a space.
      morphematischesPrinzip: json['morphematisches Prinzip'] as Map<String, dynamic>?, 
      
    );
  }

  String get displayName {
    if (wordType == GermanWordType.substantiv &&
        article != null &&
        article!.isNotEmpty) {
      return '$article $word';
    }
    return word;
  }

  // --- MODIFIED: Added new fields to toJson ---
  Map<String, dynamic> toJson() => {
        'id': id,
        'word': word,
        'article': article,
        'wordType': wordType.toString().split('.').last,
        'gradeLevel': gradeLevel,
        'lemma': lemma,
        'forms': forms,
        'url': url,
        'sources': sources,
        'isGrundwortschatzBW': isGrundwortschatzBW,
        'genus': genus,
        'nurImPlural': nurImPlural,
        'inflectionData': inflectionData,
        'ipaPhoneme': ipaPhoneme,
        'sampaPhoneme': sampaPhoneme,
        'graphematicVariants':
            graphematicVariants.map((v) => v.toJson()).toList(),
        'caseSpacy': caseSpacy,
        'numberSpacy': numberSpacy,
        'degreeSpacy': degreeSpacy,
        'pronTypeSpacy': pronTypeSpacy,
        'verbFormSpacy': verbFormSpacy,
        'plural': plural,
        'categories':
            categories.map((c) => c.toString().split('.').last).toList(),
        'exampleSentences': exampleSentences,
        'spellingDifficulty': spellingDifficulty.index,
        'commonMistakes': commonMistakes,
        'audioPath': audioPath,
        
        'frequencyData': frequencyData,
        'averageRank': averageRank,
        'artikelDetailsNRW': artikelDetailsNRW,
        'morphematisches Prinzip': morphematischesPrinzip,
        'hyphenation': hyphenation,
        'wiktionaryInflections': wiktionaryInflections,

        'translations': translations?.map((t) => t.toJson()).toList(), 
        'derivedTerms': derivedTerms,
        'relatedTerms': relatedTerms,

        // apiEnrichment is intentionally not saved back,
        // as it's loaded from the enriched asset.
      };
  // --- END MODIFIED ---
}

class GrammarExercise {
  final String id;
  final GrammarTopic topic;
  final GradeLevel gradeLevel;
  final String instruction;
  final String sentence;
  final List<String> options;
  final String correctAnswer;
  final String explanation;

  GrammarExercise(
      {required this.id,
      required this.topic,
      required this.gradeLevel,
      required this.instruction,
      required this.sentence,
      required this.options,
      required this.correctAnswer,
      required this.explanation});

  factory GrammarExercise.fromJson(Map<String, dynamic> json) {
    return GrammarExercise(
      id: json['id'],
      topic: GrammarTopic.values.firstWhere(
        (e) => e.toString().split('.').last == json['topic'],
        orElse: () => GrammarTopic.satzglieder,
      ),
      gradeLevel: GradeLevel.values[json['gradeLevel'] ?? 0],
      instruction: json['instruction'],
      sentence: json['sentence'],
      options: List<String>.from(json['options']),
      correctAnswer: json['correctAnswer'],
      explanation: json['explanation'],
    );
  }
}

class VocabularySet {
  final String id;
  final String name;
  final String description;
  final List<String> wordIds;
  final GradeLevel targetGrade;
  final DateTime createdAt;
  final bool isCustom;

  VocabularySet(
      {required this.id,
      required this.name,
      required this.description,
      required this.wordIds,
      required this.targetGrade,
      required this.createdAt,
      this.isCustom = false});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'wordIds': wordIds,
        'targetGrade': targetGrade.index,
        'createdAt': createdAt.toIso8601String(),
        'isCustom': isCustom,
      };

  factory VocabularySet.fromJson(Map<String, dynamic> json) {
    return VocabularySet(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      wordIds: List<String>.from(json['wordIds']),
      targetGrade: GradeLevel.values[json['targetGrade'] ?? 0],
      createdAt: DateTime.parse(json['createdAt']),
      isCustom: json['isCustom'] ?? false,
    );
  }
}

class ApiTranslation {
  final String? lang;
  final String? langCode;
  final String? word;
  final String? tags;

  ApiTranslation({this.lang, this.langCode, this.word, this.tags});

  factory ApiTranslation.fromJson(Map<String, dynamic> json) {
    return ApiTranslation(
      lang: json['lang'],
      langCode: json['lang_code'],
      word: json['word'],
      tags: json['tags'],
    );
  }

  Map<String, dynamic> toJson() => {
    'lang': lang,
    'lang_code': langCode,
    'word': word,
    'tags': tags,
  };
  
}