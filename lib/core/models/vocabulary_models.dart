// lib/core/models/vocabulary_models.dart

import 'skill_category.dart'; // SINGLE Source of Truth for Enums

// --- HELPER FOR ROBUST PARSING ---
// Even though we fixed the DB, these prevent crashes if bad data slips in.
num? _parseNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

int _parseInt(dynamic value, int defaultValue) {
  return _parseNum(value)?.toInt() ?? defaultValue;
}

double _parseDouble(dynamic value, double defaultValue) {
  return _parseNum(value)?.toDouble() ?? defaultValue;
}
// ---------------------------------

// -----------------------------------------------------------------------------
// PART 1: API ENRICHMENT MODELS (V24)
// -----------------------------------------------------------------------------

class ApiExpression {
  final String? expression;
  final String? senseIndex;

  ApiExpression({this.expression, this.senseIndex});

  factory ApiExpression.fromJson(Map<String, dynamic> json) {
    return ApiExpression(
      expression: json['expression'],
      senseIndex: json['sense_index'],
    );
  }
}

class ApiProverb {
  final String? proverb;
  final String? senseIndex;

  ApiProverb({this.proverb, this.senseIndex});

  factory ApiProverb.fromJson(Map<String, dynamic> json) {
    return ApiProverb(
      proverb: json['proverb'],
      senseIndex: json['sense_index'],
    );
  }
}

class ApiSemanticTerm {
  final String? word;
  final String? senseIndex;

  ApiSemanticTerm({this.word, this.senseIndex});

  factory ApiSemanticTerm.fromJson(Map<String, dynamic> json) {
    return ApiSemanticTerm(
      word: json['hypernym_word'] ??
          json['hyponym_word'] ??
          json['holonym_word'] ??
          json['meronym_word'] ??
          json['coordinate_word'] ??
          json['word'],
      senseIndex: json['sense_index'],
    );
  }
}

class ApiEnrichment {
  final String enrichmentStatus;
  final String? primaryPos;
  final String? primaryLemma;
  final List<String> definitions;
  final List<ApiPronunciation> pronunciation;
  final List<ApiExample> examples;
  final List<String> synonyms;
  final List<String> antonyms;
  final List<ApiConceptNetRelation> conceptnet;
  final List<ApiAlternativeAnalysis> alternativeAnalyses;
  final String? apiInfo;
  final List<Map<String, dynamic>> inflections;
  final Map<String, dynamic>? inflectionsPattern;
  final List<String> hyphenation;
  final List<ApiTranslation> translations;
  final List<String> derivedTerms;
  final List<String> relatedTerms;
  final List<ApiSemanticRelation> semanticRelations;
  final List<ApiExpression> expressions;
  final List<ApiProverb> proverbs;
  final List<String> entryNotes;
  final List<ApiSemanticTerm> hypernyms;
  final List<ApiSemanticTerm> hyponyms;
  final List<ApiSemanticTerm> holonyms;
  final List<ApiSemanticTerm> meronyms;
  final List<ApiSemanticTerm> coordinateTerms;

  // Grade-differentiated example sentences: {"1": ["sent1","sent2"], ..., "6": [...]}
  // Populated by add_llm_examples*.py. Null if grade fill hasn't run yet.
  final Map<String, List<String>>? gradeExamples;

  // Raw Gutenberg-sourced sentences (before grade assignment).
  final List<String> gutenbergExamples;

  // Common spelling errors for this word (EN: from Norvig/Wikipedia; DE: from LiTKey/DysList).
  // Each entry is a misspelled form string.
  final List<String> commonLearnerErrors;

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
    required this.inflections,
    this.inflectionsPattern,
    required this.semanticRelations,
    required this.hyphenation,
    required this.translations,
    required this.derivedTerms,
    required this.relatedTerms,
    required this.expressions,
    required this.proverbs,
    required this.entryNotes,
    required this.hypernyms,
    required this.hyponyms,
    required this.holonyms,
    required this.meronyms,
    required this.coordinateTerms,
    this.gradeExamples,
    required this.gutenbergExamples,
    required this.commonLearnerErrors,
  });

  factory ApiEnrichment.fromJson(Map<String, dynamic> json) {
    List<ApiSemanticTerm> parseTerms(String key) {
      return (json[key] as List<dynamic>?)
              ?.map((t) => ApiSemanticTerm.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [];
    }

    List<String> parseTermList(String key, String wordKey) {
      return (json[key] as List<dynamic>?)
              ?.map((t) {
                if (t is Map<String, dynamic>) return t[wordKey] as String?;
                if (t is String) return t;
                return null;
              })
              .where((t) => t != null)
              .cast<String>()
              .toList() ??
          [];
    }

    return ApiEnrichment(
      enrichmentStatus: json['enrichment_status'] ?? 'unknown',
      primaryPos: json['primary_pos'],
      primaryLemma: json['primary_lemma'],
      definitions: List<String>.from(json['definitions'] ?? []),
      pronunciation: (json['pronunciation'] as List<dynamic>?)
              ?.map((p) => ApiPronunciation.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      examples: (json['examples'] as List<dynamic>?)
              ?.map((e) => ApiExample.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
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
      inflections: List<Map<String, dynamic>>.from(json['inflections'] ?? []),
      inflectionsPattern: json['inflections_pattern'] as Map<String, dynamic>?,
      semanticRelations: (json['semantic_relations'] as List<dynamic>?)
              ?.map((r) =>
                  ApiSemanticRelation.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      hyphenation: List<String>.from(json['hyphenation'] ?? []),
      translations: (json['wiktionary_translations'] as List<dynamic>?)
              ?.map((t) => ApiTranslation.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      derivedTerms: parseTermList('wiktionary_derived_terms', 'derived_word'),
      relatedTerms: parseTermList('wiktionary_related_terms', 'related_word'),
      expressions: (json['expressions'] as List<dynamic>?)
              ?.map((e) => ApiExpression.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      proverbs: (json['proverbs'] as List<dynamic>?)
              ?.map((p) => ApiProverb.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      entryNotes: List<String>.from(json['entry_notes'] ?? []),
      hypernyms: parseTerms('hypernyms'),
      hyponyms: parseTerms('hyponyms'),
      holonyms: parseTerms('holonyms'),
      meronyms: parseTerms('meronyms'),
      coordinateTerms: parseTerms('coordinate_terms'),
      gradeExamples: _parseGradeExamples(json['grade_examples']),
      gutenbergExamples:
          List<String>.from(json['gutenberg_examples'] ?? []),
      commonLearnerErrors: _parseCommonLearnerErrors(json['commonLearnerErrors']),
    );
  }

  static List<String> _parseCommonLearnerErrors(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .map((e) {
            if (e is String) return e;
            if (e is Map) return e['error'] as String?;
            return null;
          })
          .where((e) => e != null && e.isNotEmpty)
          .cast<String>()
          .toList();
    }
    return [];
  }

  static Map<String, List<String>>? _parseGradeExamples(dynamic raw) {
    if (raw == null || raw is! Map) return null;
    final result = <String, List<String>>{};
    for (final entry in raw.entries) {
      final grade = entry.key.toString();
      final sents = entry.value;
      if (sents is List) {
        result[grade] = sents.map((s) => s.toString()).toList();
      }
    }
    return result.isEmpty ? null : result;
  }
}

class ApiExample {
  final String? text;
  final String? ref;
  final String? author;
  final String? title;
  final int? year;

  ApiExample({this.text, this.ref, this.author, this.title, this.year});

  factory ApiExample.fromJson(Map<String, dynamic> json) {
    return ApiExample(
      text: json['text'],
      ref: json['ref'],
      author: json['author'],
      title: json['title'],
      year: _parseNum(json['year'])?.toInt(),
    );
  }
}

class ApiPronunciation {
  final String? ipa;
  final String? audio;
  final String? mp3Url;
  final String? oggUrl;

  ApiPronunciation({this.ipa, this.audio, this.mp3Url, this.oggUrl});

  factory ApiPronunciation.fromJson(Map<String, dynamic> json) {
    return ApiPronunciation(
      ipa: json['ipa'],
      audio: json['audio'],
      mp3Url: json['mp3_url'],
      oggUrl: json['ogg_url'],
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
      weight: _parseDouble(json['weight'], 0.0),
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

class ApiSemanticRelation {
  final String? definition;
  final List<String> synonyms;
  final List<String> antonyms;

  ApiSemanticRelation(
      {this.definition, required this.synonyms, required this.antonyms});

  factory ApiSemanticRelation.fromJson(Map<String, dynamic> json) {
    return ApiSemanticRelation(
      definition: json['definition'],
      synonyms: List<String>.from(json['synonyms'] ?? []),
      antonyms: List<String>.from(json['antonyms'] ?? []),
    );
  }
}

class ApiTranslation {
  final String? lang;
  final String? langCode;
  final String? word;
  final String? senseText;
  final String? roman;
  final String? tags;

  ApiTranslation(
      {this.lang,
      this.langCode,
      this.word,
      this.senseText,
      this.roman,
      this.tags});

  factory ApiTranslation.fromJson(Map<String, dynamic> json) {
    return ApiTranslation(
      lang: json['lang'],
      langCode: json['lang_code'],
      word: json['word'],
      senseText: json['sense_text'],
      roman: json['roman'],
      tags: json['tags'],
    );
  }

  Map<String, dynamic> toJson() => {
        'lang': lang,
        'lang_code': langCode,
        'word': word,
        'sense_text': senseText,
        'roman': roman,
        'tags': tags,
      };
}

// -----------------------------------------------------------------------------
// PART 2: CORE VOCABULARY MODELS
// -----------------------------------------------------------------------------

class GraphematicVariant {
  final String spelling;
  final double probability;

  GraphematicVariant({required this.spelling, required this.probability});

  factory GraphematicVariant.fromJson(Map<String, dynamic> json) {
    return GraphematicVariant(
      spelling: json['spelling'],
      probability: _parseDouble(json['probability'], 0.0),
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

  // Consolidated V24 Fields
  final List<ApiExample> examples;
  final List<String> hyphenation;
  final List<Map<String, dynamic>> wiktionaryInflections;
  final List<ApiTranslation> translations;
  final List<String> derivedTerms;
  final List<String> relatedTerms;
  final List<ApiExpression> expressions;
  final List<ApiProverb> proverbs;
  final List<String> entryNotes;
  final List<ApiSemanticTerm> hypernyms;
  final List<ApiSemanticTerm> hyponyms;
  final List<ApiSemanticTerm> holonyms;
  final List<ApiSemanticTerm> meronyms;
  final List<ApiSemanticTerm> coordinateTerms;

  final Map<String, dynamic>? frequencyData;
  final double? averageRank;
  final Map<String, dynamic>? artikelDetailsNRW;
  final Map<String, dynamic>? morphematischesPrinzip;

  // Computed difficulty estimate (1=easiest … 6=hardest).
  // Derived from curriculum membership, CEFR level, and word frequency.
  final int? gradeLevelEstimate;

  // CEFR level (A1, A2, B1, B2, C1, C2) from CEFR-J profile.
  final String? cefrLevel;

  // True when the DB row was typed 'proper_noun' (Eigenname / Vorname).
  // Mapped to GermanWordType.substantiv for most game logic, but games can
  // filter proper nouns out where they'd produce odd challenges.
  final bool isProperNoun;

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
    this.gradeLevelEstimate,
    this.cefrLevel,
    required this.examples,
    required this.hyphenation,
    required this.wiktionaryInflections,
    required this.translations,
    required this.derivedTerms,
    required this.relatedTerms,
    required this.expressions,
    required this.proverbs,
    required this.entryNotes,
    required this.hypernyms,
    required this.hyponyms,
    required this.holonyms,
    required this.meronyms,
    required this.coordinateTerms,
    this.isProperNoun = false,
  });

  factory GermanWord.fromJson(Map<String, dynamic> json) {
    final apiData = json['apiEnrichment'] != null
        ? ApiEnrichment.fromJson(json['apiEnrichment'] as Map<String, dynamic>)
        : null;

    final variantsList = (json['graphematicVariants'] as List<dynamic>?) ?? [];
    final variants = variantsList
        .map((v) => GraphematicVariant.fromJson(v as Map<String, dynamic>))
        .toList();

    // Audio Path Logic
    String? resolvedAudioPath;
    if (apiData?.pronunciation.isNotEmpty ?? false) {
      ApiPronunciation? mp3Pron = apiData!.pronunciation.firstWhere(
          (p) => p.mp3Url != null,
          orElse: () => ApiPronunciation());
      if (mp3Pron.mp3Url != null) {
        resolvedAudioPath = mp3Pron.mp3Url;
      } else {
        ApiPronunciation? oggPron = apiData.pronunciation.firstWhere(
            (p) => p.audio != null,
            orElse: () => ApiPronunciation());
        if (oggPron.audio != null) {
          resolvedAudioPath = oggPron.audio;
        }
      }
    }
    resolvedAudioPath ??= json['audioPath'];

    // Example Sentences Logic
    // Priority: Tatoeba (child-friendly, CC-BY 2.0) > Wiktionary > legacy strings
    final List<String> tatoebaExamples =
        List<String>.from(json['tatoeba_examples'] ?? []);
    final List<ApiExample> v24Examples = apiData?.examples ?? [];
    final List<String> oldExampleStrings =
        List<String>.from(json['exampleSentences'] ?? []);

    final List<String> exampleStrings = tatoebaExamples.isNotEmpty
        ? tatoebaExamples
        : v24Examples.isNotEmpty
            ? v24Examples
                .map((e) => e.text ?? '')
                .where((t) => t.isNotEmpty)
                .toList()
            : oldExampleStrings;

    // Parsing Helpers for Enums
    GermanWordType parseWordType(String? typeStr) {
      if (typeStr == null) return GermanWordType.andere;
      final normalized = typeStr.toLowerCase();
      const aliases = {
        'noun': GermanWordType.substantiv,
        'proper_noun': GermanWordType.substantiv,
        'propernoun': GermanWordType.substantiv,
        'verb': GermanWordType.verb,
        'adjective': GermanWordType.adjektiv,
        'adj': GermanWordType.adjektiv,
        'adverb': GermanWordType.adverb,
        'adv': GermanWordType.adverb,
        'article': GermanWordType.artikel,
        'determiner': GermanWordType.artikel,
        'det': GermanWordType.artikel,
        'pronoun': GermanWordType.pronomen,
        'pron': GermanWordType.pronomen,
        'preposition': GermanWordType.praeposition,
        'adposition': GermanWordType.praeposition,
        'adp': GermanWordType.praeposition,
        'conjunction': GermanWordType.konjunktion,
        'conj': GermanWordType.konjunktion,
        'particle': GermanWordType.partikel,
        'part': GermanWordType.partikel,
        'numeral': GermanWordType.numerale,
        'num': GermanWordType.numerale,
        'cardinal': GermanWordType.kardinalzahlwort,
        'ordinal': GermanWordType.ordinalzahlwort,
        'phrase': GermanWordType.mehrwortausdruck,
        'multiword': GermanWordType.mehrwortausdruck,
        'other': GermanWordType.andere,
      };
      final alias = aliases[normalized];
      if (alias != null) return alias;
      try {
        return GermanWordType.values.firstWhere(
          (e) => e.toString().split('.').last.toLowerCase() == normalized,
        );
      } catch (e) {
        return GermanWordType.andere;
      }
    }

    WordCategory parseCategory(String? catStr) {
      // FIX: 'sonstiges' was invalid. Falling back to 'schule'.
      if (catStr == null) return WordCategory.schule;
      try {
        return WordCategory.values.firstWhere(
          (e) =>
              e.toString().split('.').last.toLowerCase() ==
              catStr.toLowerCase(),
        );
      } catch (e) {
        return WordCategory.schule;
      }
    }

    // SAFELY Parse Indices
    int diffIndex = _parseInt(json['spellingDifficulty'], 0);
    SpellingDifficulty diff = SpellingDifficulty
        .values[diffIndex.clamp(0, SpellingDifficulty.values.length - 1)];

    final rawWordType = (json['wordType'] as String? ?? '').toLowerCase();
    final isProperNoun =
        rawWordType == 'proper_noun' || rawWordType == 'propernoun';

    return GermanWord(
      id: json['id']?.toString() ?? '',
      word: json['word'] ?? '',
      article: json['article'],
      wordType: parseWordType(json['wordType']),
      isProperNoun: isProperNoun,
      gradeLevel: _parseInt(json['gradeLevel'], 1), // SAFE PARSE
      lemma: apiData?.primaryLemma ?? json['lemma'] ?? json['word'],
      forms: json['forms'],
      url: json['url'],
      sources: List<String>.from(json['sources'] ?? []),
      isGrundwortschatzBW: json['isGrundwortschatzBW'] ?? false,
      genus: json['genus'],
      nurImPlural: json['nurImPlural'] ?? false,
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
              ?.map((c) => parseCategory(c.toString()))
              .toList() ??
          [],
      exampleSentences: exampleStrings,
      spellingDifficulty: diff,
      commonMistakes: json['commonMistakes'] != null
          ? List<String>.from(json['commonMistakes'])
          : null,
      audioPath: resolvedAudioPath,
      apiEnrichment: apiData,

      examples: v24Examples,
      hyphenation:
          apiData?.hyphenation ?? List<String>.from(json['hyphenation'] ?? []),
      wiktionaryInflections: apiData?.inflections ?? [],
      translations: apiData?.translations ?? [],
      derivedTerms: apiData?.derivedTerms ?? [],
      relatedTerms: apiData?.relatedTerms ?? [],
      expressions: apiData?.expressions ?? [],
      proverbs: apiData?.proverbs ?? [],
      entryNotes: apiData?.entryNotes ?? [],
      hypernyms: apiData?.hypernyms ?? [],
      hyponyms: apiData?.hyponyms ?? [],
      holonyms: apiData?.holonyms ?? [],
      meronyms: apiData?.meronyms ?? [],
      coordinateTerms: apiData?.coordinateTerms ?? [],

      frequencyData: json['frequencyData'] as Map<String, dynamic>?,
      averageRank: _parseDouble(json['averageRank'], 0.0), // SAFE PARSE
      artikelDetailsNRW: json['artikelDetailsNRW'] as Map<String, dynamic>?,
      morphematischesPrinzip:
          json['morphematisches Prinzip'] as Map<String, dynamic>?,
      gradeLevelEstimate: json['gradeLevelEstimate'] != null
          ? _parseInt(json['gradeLevelEstimate'], 0)
          : null,
      cefrLevel: json['cefr_level'] as String?,
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
        'exampleSentences': exampleSentences, // FIXED: Use class field
        'spellingDifficulty': spellingDifficulty.index,
        'commonMistakes': commonMistakes,
        'audioPath': audioPath,
        'frequencyData': frequencyData,
        'averageRank': averageRank,
        'artikelDetailsNRW': artikelDetailsNRW,
        'morphematisches Prinzip': morphematischesPrinzip,
        'hyphenation': hyphenation,
        if (gradeLevelEstimate != null) 'gradeLevelEstimate': gradeLevelEstimate,
        if (cefrLevel != null) 'cefr_level': cefrLevel,
      };
}

// -----------------------------------------------------------------------------
// PART 3: STRUCTURES FOR SETS & GRAMMAR
// -----------------------------------------------------------------------------

class VocabularySet {
  final String id;
  final String name;
  final String description;
  final List<String> wordIds;
  final GradeLevel targetGrade;
  final DateTime createdAt;
  final bool isCustom;

  VocabularySet({
    required this.id,
    required this.name,
    required this.description,
    required this.wordIds,
    required this.targetGrade,
    required this.createdAt,
    this.isCustom = false,
  });

  factory VocabularySet.fromJson(Map<String, dynamic> json) {
    GradeLevel parseGrade(dynamic val) {
      if (val == null) return GradeLevel.grade1;
      final str = val.toString();
      try {
        return GradeLevel.values
            .firstWhere((e) => e.toString().split('.').last == str);
      } catch (_) {
        return GradeLevel.grade1;
      }
    }

    return VocabularySet(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      wordIds: List<String>.from(json['wordIds']),
      targetGrade: parseGrade(json['targetGrade']),
      createdAt: DateTime.parse(json['createdAt']),
      isCustom: json['isCustom'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'wordIds': wordIds,
        'targetGrade': targetGrade.toString().split('.').last,
        'createdAt': createdAt.toIso8601String(),
        'isCustom': isCustom,
      };
}
