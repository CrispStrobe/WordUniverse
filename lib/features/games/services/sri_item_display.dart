import '../../../core/models/skill_category.dart';
import '../../../core/services/sri_service.dart';
import '../../../generated/l10n.dart';

/// Display text is separate from the durable item id used by review actions.
/// The identity decoder supports both legacy spellings and lexical v2 keys.
String sriItemDisplayLabel(S s, SriLanguageData item) {
  final identity = item.identity;
  final skill = switch (item.skillType) {
    LanguageSkillType.spelling => s.skillLabelSpelling,
    LanguageSkillType.articleSelection => s.skillLabelArticle,
    LanguageSkillType.pluralForm => s.skillLabelPlural,
    LanguageSkillType.wordType => s.skillLabelWordType,
    LanguageSkillType.sentenceStructure => s.skillLabelSentence,
    LanguageSkillType.punctuation => s.skillLabelPunctuation,
    LanguageSkillType.capitalization => s.skillLabelCapitalization,
    LanguageSkillType.verbConjugation => s.skillLabelConjugation,
    LanguageSkillType.caseUsage => s.skillLabelCase,
    LanguageSkillType.vocabulary => s.skillLabelVocabulary,
    LanguageSkillType.reading => s.skillLabelReading,
  };
  var detail = identity.additionalInfo?.trim() ?? '';
  if (item.skillType == LanguageSkillType.caseUsage) {
    detail = switch (detail.toLowerCase()) {
      'nom' || 'nominativ' || 'nominative' => s.wordSnakeCaseNominative,
      'akk' ||
      'acc' ||
      'akkusativ' ||
      'accusative' =>
        s.wordSnakeCaseAccusative,
      'dat' || 'dativ' || 'dative' => s.wordSnakeCaseDative,
      'gen' || 'genitiv' || 'genitive' => s.wordSnakeCaseGenitive,
      _ => detail,
    };
  }
  final word =
      identity.baseWord.isNotEmpty && !identity.baseWord.startsWith('@2|')
          ? identity.baseWord
          : s.reviewItemWordUnavailable;
  return [
    '[$skill]',
    word,
    if (detail.isNotEmpty && detail != identity.baseWord) '· $detail',
  ].join(' ');
}
