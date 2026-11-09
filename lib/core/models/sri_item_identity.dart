import 'skill_category.dart';

/// The durable identity of a word/skill exercise.
///
/// Prefixes already written by older versions remain readable. Callers should
/// use the stored item's id when recording a review, rather than rebuilding it
/// from the displayed word and accidentally dropping a pronoun or case suffix.
class SriItemIdentity {
  const SriItemIdentity({
    required this.baseWord,
    this.skillType,
    this.additionalInfo,
    this.wordId,
  });

  final String baseWord;
  final LanguageSkillType? skillType;
  final String? additionalInfo;
  final String? wordId;

  static const prefixes = <LanguageSkillType, String>{
    LanguageSkillType.spelling: 'SPELL_',
    LanguageSkillType.articleSelection: 'ARTICLE_',
    LanguageSkillType.pluralForm: 'PLURAL_',
    LanguageSkillType.wordType: 'WORDTYPE_',
    LanguageSkillType.sentenceStructure: 'SENTENCE_',
    LanguageSkillType.punctuation: 'PUNCT_',
    LanguageSkillType.capitalization: 'CAPITAL_',
    LanguageSkillType.verbConjugation: 'CONJUG_',
    LanguageSkillType.caseUsage: 'CASE_',
    LanguageSkillType.vocabulary: 'VOCAB_',
    LanguageSkillType.reading: 'READ_',
  };

  static const _legacyPrefixes = <String, LanguageSkillType>{
    'TYPE_': LanguageSkillType.wordType,
    'GRAM_': LanguageSkillType.sentenceStructure,
    'MEAN_': LanguageSkillType.vocabulary,
  };

  static String itemId({
    required LanguageSkillType skillType,
    required String baseWord,
    String? additionalInfo,
    String? wordId,
  }) {
    final prefix = prefixes[skillType]!;
    if (wordId != null && wordId.trim().isNotEmpty) {
      // A catalogue id identifies a lexical sense; spelling alone cannot
      // distinguish Arm/arm or the verb/possessive senses of "sein". Encoding
      // each component also keeps underscores, pipes and pronoun contexts
      // unambiguous. The visible word stays in metadata, not in the key.
      return '$prefix@2|${Uri.encodeComponent(wordId.trim())}|'
          '${Uri.encodeComponent(additionalInfo ?? '')}';
    }
    if (skillType == LanguageSkillType.sentenceStructure ||
        skillType == LanguageSkillType.punctuation) {
      // Keep the historic case-sensitive contextual ids compatible.
      return '$prefix${additionalInfo ?? baseWord}';
    }
    final word = baseWord.trim().toLowerCase();
    final hasSuffix = skillType == LanguageSkillType.verbConjugation ||
        skillType == LanguageSkillType.caseUsage;
    final suffix = hasSuffix && additionalInfo?.isNotEmpty == true
        ? '_$additionalInfo'
        : '';
    return '$prefix$word$suffix';
  }

  factory SriItemIdentity.fromId(
    String itemId, {
    LanguageSkillType? skillType,
    Map<String, dynamic> metadata = const {},
  }) {
    var written = itemId;
    LanguageSkillType? encodedSkill;
    final known = <String, LanguageSkillType>{
      for (final entry in prefixes.entries) entry.value: entry.key,
      ..._legacyPrefixes,
    };
    for (final entry in known.entries) {
      if (itemId.startsWith(entry.key)) {
        written = itemId.substring(entry.key.length);
        encodedSkill = entry.value;
        break;
      }
    }

    final skill = skillType ?? encodedSkill;
    String? detail;
    String? lexicalId;
    if (written.startsWith('@2|')) {
      final components = written.split('|');
      if (components.length == 3) {
        try {
          lexicalId = Uri.decodeComponent(components[1]);
          detail = Uri.decodeComponent(components[2]);
          if (lexicalId.isEmpty) lexicalId = null;
          if (lexicalId != null) written = '';
          if (detail.isEmpty) detail = null;
        } on FormatException {
          // An unknown/malformed future key remains readable as legacy data.
          lexicalId = null;
          detail = null;
        }
      }
    }
    if (lexicalId == null &&
        (skill == LanguageSkillType.verbConjugation ||
            skill == LanguageSkillType.caseUsage)) {
      final split = written.indexOf('_');
      if (split >= 0) {
        detail = written.substring(split + 1);
        written = written.substring(0, split);
      }
    }

    final savedWord = metadata['baseWord'];
    final savedDetail = metadata['additionalInfo'];
    final savedId = metadata['wordId'];
    return SriItemIdentity(
      baseWord: savedWord is String && savedWord.trim().isNotEmpty
          ? savedWord.trim()
          : written,
      skillType: skill,
      additionalInfo: lexicalId != null
          ? detail
          : savedDetail is String
              ? savedDetail
              : detail,
      wordId: lexicalId ??
          (savedId is String && savedId.trim().isNotEmpty ? savedId : null),
    );
  }

  String? get canonicalId => skillType == null
      ? null
      : itemId(
          skillType: skillType!,
          baseWord: baseWord,
          additionalInfo: additionalInfo,
          wordId: wordId,
        );
}

/// Compatible helper for older game callers that only have a queue id.
String? baseWordFromSriId(String id) {
  final word = SriItemIdentity.fromId(id).baseWord;
  return word.isEmpty ? null : word;
}
