// test/audit/challenge_harness.dart
//
// Builds what the games would actually ask a learner, without running a
// widget: one generator per game, each returning plain [Item]s.
//
// Two files use it. challenge_dump_test.dart prints the items for a human or
// an agent to read; challenge_contract_test.dart asserts the invariants that
// hold for every item of every game. See docs/content-audit.md.

import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:archive/archive.dart';

import 'package:flutter/widgets.dart' show Locale;

import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:WortUniversum/generated/l10n.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/vocabulary_quality.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/cognitive_profile_service.dart';
import 'package:WortUniversum/core/services/dictionary_database_service.dart';
import 'package:WortUniversum/core/services/progress_service.dart';
import 'package:WortUniversum/core/models/skill_category.dart' as skills;
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/services/definition_quiz_service.dart';
import 'package:WortUniversum/features/games/services/adaptive_word_selection.dart';
import 'package:WortUniversum/features/games/services/antonym_flash_service.dart';
import 'package:WortUniversum/features/games/services/cloze_service.dart';
import 'package:WortUniversum/features/games/services/conjugation_drill_challenges.dart';
import 'package:WortUniversum/features/games/services/conjugation_drill_service.dart';
import 'package:WortUniversum/features/games/services/false_friend_service.dart';
import 'package:WortUniversum/features/games/services/hypernym_flash_service.dart';
import 'package:WortUniversum/features/games/services/sentence_completion_service.dart';
import 'package:WortUniversum/features/games/services/spelling_spotter_challenges.dart';
import 'package:WortUniversum/features/games/services/sri_review_service.dart';
import 'package:WortUniversum/features/games/services/syllable_count_service.dart';
import 'package:WortUniversum/features/games/services/word_class_flash_service.dart';
import 'package:WortUniversum/features/games/services/synonym_flash_service.dart';
import 'package:WortUniversum/features/games/services/grossschreib_service.dart';
import 'package:WortUniversum/features/games/services/grossstadt_service.dart';
import 'package:WortUniversum/features/games/services/verbtrenner_service.dart';
import 'package:WortUniversum/features/games/services/wortbaumeister_service.dart';
import 'package:WortUniversum/features/games/services/translation_flash_service.dart';
import 'package:WortUniversum/features/games/services/homophone_drill_service.dart';
import 'package:WortUniversum/features/games/services/phrasal_verb_service.dart';
import 'package:WortUniversum/features/games/services/wortfalle_service.dart';
import 'package:WortUniversum/features/home/services/word_of_the_day_service.dart';

/// One generated item, in the shape a reviewer needs: what is asked, what the
/// learner picks from, and which pick is marked correct.
class Item {
  Item({
    required this.game,
    required this.prompt,
    this.options = const [],
    this.answer,
    this.notes = const {},
  });

  final String game;
  final String prompt;
  final List<String> options;
  final String? answer;
  final Map<String, Object?> notes;

  /// [title] is the game's own name as the menu shows it, so a reviewer —
  /// or a model — knows what the learner is looking at. Word Find hands out
  /// a letter grid; without that, "Find 'Pilz' in the grid" reads as a
  /// question with no grid attached.
  Map<String, Object?> toJson({String? title}) => {
        'game': game,
        if (title != null) 'title': title,
        'prompt': prompt,
        if (options.isNotEmpty) 'options': options,
        if (answer != null) 'answer': answer,
        if (notes.isNotEmpty) 'notes': notes,
      };

  String toText() {
    final buffer = StringBuffer()..writeln('  $prompt');
    if (options.isNotEmpty) {
      for (final option in options) {
        buffer.writeln('    ${option == answer ? '✓' : ' '} $option');
      }
    } else if (answer != null) {
      buffer.writeln('    ✓ $answer');
    }
    if (notes.isNotEmpty) {
      buffer.writeln(
          '    · ${notes.entries.map((e) => '${e.key}: ${e.value}').join('  ')}');
    }
    return buffer.toString();
  }
}

Item _clozeItem(String game, ClozeChallenge challenge) => Item(
      game: game,
      prompt: '${challenge.before}___${challenge.after}',
      options: challenge.options,
      answer: challenge.options[challenge.correctIndex],
      notes: {'word': challenge.word.word},
    );

/// Games whose challenge construction is callable without a widget.
typedef Generator = Future<List<Item>> Function(AuditContext context);

/// Which pack a generator makes sense for. The menu filters games by learning
/// language, so dumping a German-only game against the English pack would
/// review content no learner is offered.
const Map<String, List<String>> generatorLanguages = {
  'antonym_flash': ['en', 'de'],
  'sri_review': ['en', 'de'],
  'grossschreib': ['de'],
  'grossstadt': ['de'],
  'wortbaumeister': ['de'],
  'verbtrenner': ['de'],
  'word_find': ['en', 'de'],
  'word_snake': ['en', 'de'],
  'word_memory': ['en', 'de'],
  'word_builder': ['en', 'de'],
  'word_sort': ['en', 'de'],
  'word_type_whirl': ['en', 'de'],
  'conjugation_drill': ['de'],
  'spelling_spotter': ['en', 'de'],
  'cloze_flash': ['en', 'de'],
  'expression_flash': ['de'],
  'proverb_cloze': ['de'],
  'sentence_completion': ['en', 'de'],
  'word_class_flash': ['en', 'de'],
  'hypernym_flash': ['en', 'de'],
  'syllable_count': ['en', 'de'],
  'translation_flash': ['de'],
  'reverse_translation_flash': ['de'],
  'definition_quiz': ['en', 'de'],
  'synonym_flash': ['en', 'de'],
  'homophone_drill': ['en'],
  'wortfalle': ['de'],
  'false_friends': ['en'],
  'phrasal_verb_power': ['en'],
  'phrasal_verb_match': ['en'],
  'word_of_the_day': ['en', 'de'],
};

class AuditContext {
  AuditContext(this.vocabulary, this.sri, this.settings, this.grade, this.count,
      this.rng, this.language)
      : strings = lookupS(Locale(language));
  final VocabularyService vocabulary;
  final SriService sri;
  final GameProvider settings;
  final int grade;
  final int count;
  final Random rng;
  final String language;

  /// The app's own strings for this pack's language.
  final S strings;

  bool get isGerman => language == 'de';

  /// The pool a game opens with, on the same terms the screen asks for it.
  Future<List<GermanWord>> pool(
    WordFeature feature, {
    int? limitFactor,
    bool Function(GermanWord word)? where,
  }) =>
      vocabulary.takeWordsWithFeature(
        feature,
        settingsProvider: settings,
        gradeLevel: grade,
        limit: count * (limitFactor ?? 8),
        where: where,
        random: rng,
      );
}

/// The six games that practise a word rather than ask a question about it:
/// the reviewable output is which words they pick, and on what grounds.
/// The five classes Word Sort and Word Type Whirl put bins on screen for.
const _binnedClasses = {
  GermanWordType.substantiv,
  GermanWordType.verb,
  GermanWordType.adjektiv,
  GermanWordType.adverb,
  GermanWordType.pronomen,
};

bool _hasABin(GermanWord word) =>
    !word.word.contains(' ') && _binnedClasses.contains(word.wordType);

/// What the games call a word class on screen.
///
/// They never show the enum: Word Sort and Word Type Whirl label their bins
/// with the interface language's plural ("Nouns", "Nomen"), Word Class Flash
/// with its singular. A dump that answers "substantiv" to an English prompt
/// reads as a bug that is not there — a model reviewing the items flagged it
/// four times in one pass, once as "option labels are not capitalized".
String _classLabel(S strings, GermanWordType type, {bool plural = true}) =>
    switch ((type, plural)) {
      (GermanWordType.substantiv, true) => strings.wordSortCategoryNoun,
      (GermanWordType.verb, true) => strings.wordSortCategoryVerb,
      (GermanWordType.adjektiv, true) => strings.wordSortCategoryAdjective,
      (GermanWordType.adverb, true) => strings.wordSortCategoryAdverb,
      (GermanWordType.pronomen, true) => strings.wordSortCategoryPronoun,
      (GermanWordType.substantiv, false) => strings.wordTypeNoun,
      (GermanWordType.verb, false) => strings.wordTypeVerb,
      (GermanWordType.adjektiv, false) => strings.wordTypeAdjective,
      (GermanWordType.adverb, false) => strings.wordTypeAdverb,
      (GermanWordType.pronomen, false) => strings.wordTypePronoun,
      _ => type.name,
    };

Generator _wordPractice(
  String game,
  String ask, {
  skills.LanguageSkillType? skill,
  bool Function(GermanWord word)? playable,
}) =>
    (c) async {
      final words = await c.vocabulary.hydrate(selectAdaptiveWords(
        vocabulary: c.vocabulary,
        sri: c.sri,
        settings: c.settings,
        grade: skills.GradeLevel.values[(c.grade - 1).clamp(0, 5)],
        count: c.count,
        isPlayable: playable ?? (w) => !w.word.contains(' '),
        skillFilter: skill,
        rng: c.rng,
      ));
      return words
          .map((w) => Item(
                game: game,
                // The bare word, as these screens show it: only Word Type
                // Whirl puts the article in front of a German noun, and a
                // dump that says «Trace "der Pilz"» while the snake spells
                // "Pilz" is reviewing a game nobody plays.
                prompt: ask.replaceAll(
                    '%s', game == 'word_type_whirl' ? w.displayName : w.word),
                answer: game == 'word_sort' || game == 'word_type_whirl'
                    ? _classLabel(c.strings, w.wordType)
                    : w.word,
                notes: {
                  'grade': w.gradeLevel,
                  if (w.displayDefinitions.isNotEmpty)
                    'gloss': w.displayDefinitions.first,
                },
              ))
          .toList();
    };

const _reviewSkills = [
  LanguageSkillType.spelling,
  LanguageSkillType.articleSelection,
  LanguageSkillType.vocabulary,
];

final Map<String, Generator> generators = {
  'sri_review': (c) async {
    // The review game asks about words the learner has already struggled
    // with; with an empty SRI history there is nothing due, so the dump shows
    // what it would ask for the words it can reach.
    final strings = lookupS(Locale(c.language));
    final pool = await c.pool(WordFeature.definitions,
        where: (w) => !w.isProperNoun && w.isHeadword);
    final validWords = c.vocabulary
        .getAllWords(c.settings)
        .map((w) => w.word.toLowerCase())
        .toSet();
    final items = <Item>[];
    for (final word in pool) {
      if (items.length >= c.count) break;
      // Cycle the skill types so the dump shows all three review formats;
      // each falls back to the definition quiz when it cannot build.
      final skill = _reviewSkills[items.length % _reviewSkills.length];
      final challenge = buildReviewChallenge(
        word,
        SriLanguageData(
          itemId: word.word,
          skillType: skill,
          nextReviewDate: DateTime.utc(2020),
        ),
        pool,
        validWords,
        strings: strings,
        isGerman: c.isGerman,
        rng: c.rng,
      );
      if (challenge == null) continue;
      items.add(Item(
        game: 'sri_review',
        prompt: challenge.prompt,
        options: challenge.options,
        answer: challenge.options[challenge.correctIndex],
        notes: {'type': challenge.type.name},
      ));
    }
    return items;
  },
  'grossschreib': (c) async {
    final pool = await c.pool(WordFeature.examples,
        limitFactor: 40,
        where: (w) => w.gradeLevel <= c.grade + 3 && w.word.isNotEmpty);
    final items = <Item>[];
    for (final word in pool) {
      if (items.length >= c.count) break;
      final isNoun = word.wordType == GermanWordType.substantiv;
      final challenge = challengeFromWord(
        word,
        correctCase: isNoun ? WordCase.capitalized : WordCase.lowercase,
        rule: isNoun
            ? CapitalizationRule.noun
            : CapitalizationRule.verbOrAdjective,
        explanation: isNoun
            ? 'Nomen werden immer großgeschrieben'
            : 'Verben und Adjektive werden kleingeschrieben',
        forceMiddlePosition: true,
      );
      if (challenge == null) continue;
      items.add(Item(
        game: 'grossschreib',
        prompt: '${challenge.beforeWord}[${challenge.targetWord}]'
            '${challenge.afterWord}',
        answer:
            challenge.correctCase == WordCase.capitalized ? 'GROSS' : 'klein',
        notes: {'word': challenge.targetWord, 'rule': challenge.explanation},
      ));
    }
    return items;
  },
  'grossstadt': (c) async {
    Future<List<GermanWord>> ofType(GermanWordType type, int count) async {
      final words = c.vocabulary
          .getAllWords(c.settings)
          .where((w) =>
              w.wordType == type &&
              !w.word.contains(' ') &&
              w.word.length >= 3 &&
              w.has(WordFeature.usableDefinition) &&
              !namesSomething(w) &&
              w.isHeadword &&
              w.gradeLevel <= c.grade + 2)
          .toList()
        ..shuffle(c.rng);
      return c.vocabulary.hydrate(words.take(count));
    }

    return buildCapitalizationItems(
      verbs: await ofType(GermanWordType.verb, 15),
      adjectives: await ofType(GermanWordType.adjektiv, 12),
      nouns: await ofType(GermanWordType.substantiv, 12),
      rng: c.rng,
    )
        .take(c.count)
        .map((item) => Item(
              game: 'grossstadt',
              // The question the screen asks, spelled out. Without it the
              // bracketed word looks like a prompt with a missing question:
              // "DAS [besprechen] → GROSS" reads as nonsense rather than as
              // the nominalisation it is.
              prompt: 'Groß oder klein? '
                  '${item.prefix}[${item.target}]${item.suffix}',
              answer: item.shouldBeCapitalized ? 'GROSS' : 'klein',
              options: const ['GROSS', 'klein'],
              notes: {'rule': item.explanation},
            ))
        .toList();
  },
  'wortbaumeister': (c) async {
    final catalogue = c.vocabulary.getAllWords(c.settings);
    final nouns = catalogue
        .where((w) => w.wordType == GermanWordType.substantiv)
        .toList();
    final nounMap = {for (final w in nouns) w.word.toLowerCase(): w};
    final candidates = await c.vocabulary.hydrate(
        nouns.where((w) => w.word.length >= minCompoundLength).take(300));
    return buildCompoundChallenges(candidates, nounMap)
        .take(c.count)
        .map((ch) => Item(
              game: 'wortbaumeister',
              prompt: 'Build the compound: ${ch.part1} + ${ch.part2}',
              answer: ch.fullWord,
              notes: {'context': ch.context},
            ))
        .toList();
  },
  'verbtrenner': (c) async => buildVerbPairs(
        verbs: await c.pool(WordFeature.inflections,
            limitFactor: 20,
            where: (w) =>
                w.wordType == GermanWordType.verb &&
                w.gradeLevel <= c.grade + 3),
        maxPairs: c.count,
        rng: c.rng,
      )
          .map((pair) => Item(
                game: 'verbtrenner',
                // The screen shows the sentence under the two halves, and
                // the answer is about that sentence: without it «an … ziehen»
                // reads as a question about the infinitive and any reader
                // will say GETRENNT. Saying so in the prompt matters as much
                // as showing the sentence — a model that had the sentence
                // still called "vorschreiben" GETRENNT three times in one
                // pass, because it was answering "is this verb separable?"
                // and not "is it written apart here?".
                prompt: 'Steht das Verb in diesem Satz getrennt oder '
                    'zusammen?\n'
                    '${pair.part1.isEmpty ? pair.part2 : '${pair.part1} … '
                        '${pair.part2}'}\n${pair.context}',
                answer: pair.shouldBeSeparated ? 'GETRENNT' : 'ZUSAMMEN',
                options: const ['GETRENNT', 'ZUSAMMEN'],
                notes: {'form': pair.formText},
              ))
          .toList(),
  'word_find': _wordPractice('word_find', 'Find "%s" in the grid'),
  'word_snake': _wordPractice('word_snake', 'Trace "%s"',
      skill: skills.LanguageSkillType.spelling),
  'word_builder': _wordPractice('word_builder', 'Build "%s" from its letters',
      skill: skills.LanguageSkillType.spelling),
  // Memory deals two cards per word. From year 3 the partner card carries the
  // definition, so the pair a player has to see through is word ↔ gloss; below
  // that the two cards both say the word in different fonts. A dump that
  // answers «undo» to «Match the pair for "undo"» reviews neither.
  'word_memory': (c) async {
    final words = await c.vocabulary.hydrate(selectAdaptiveWords(
      vocabulary: c.vocabulary,
      sri: c.sri,
      settings: c.settings,
      grade: skills.GradeLevel.values[(c.grade - 1).clamp(0, 5)],
      count: c.count,
      isPlayable: (w) =>
          w.word.length >= 3 && w.word.length <= 8 && !w.word.contains(' '),
      rng: c.rng,
    ));
    final withDefinitions =
        skills.GradeLevel.values[(c.grade - 1).clamp(0, 5)].index >= 2;
    return words.map((w) {
      final gloss = withDefinitions ? w.displayDefinitions.firstOrNull : null;
      final partner = gloss == null || gloss.isEmpty
          ? w.word
          : (gloss.length > 55 ? '${gloss.substring(0, 52)}…' : gloss);
      return Item(
        game: 'word_memory',
        prompt: 'Match the pair for "${w.word}"',
        answer: partner,
        notes: {
          'grade': w.gradeLevel,
          'partner': partner == w.word ? 'same word, other font' : 'definition',
        },
      );
    }).toList();
  },
  // Both games bin into the same five classes, and skip a word whose class
  // is not one of them. The dump did not, so it asked which bin "Dariusz"
  // and "siebzig" belong in and answered "andere" and "numerale" — bins no
  // player is ever shown.
  'word_sort': _wordPractice('word_sort', 'Sort "%s" into its word class',
      skill: skills.LanguageSkillType.wordType, playable: _hasABin),
  'word_type_whirl': _wordPractice(
      'word_type_whirl', 'Catch "%s" in the right bin',
      skill: skills.LanguageSkillType.wordType, playable: _hasABin),
  'conjugation_drill': (c) async => buildConjugationChallenges(
        verbs: (await c.pool(WordFeature.inflections,
                where: (w) => !w.isProperNoun && !w.word.contains(' ')))
            .where(isConjugatableVerb)
            .toList(),
        maxChallenges: c.count,
        rng: c.rng,
      )
          .map((ch) => Item(
                game: 'conjugation_drill',
                prompt: '${ch.verb.word}: ${ch.pronoun} ___',
                options: ch.options,
                answer: ch.options[ch.correctIndex],
              ))
          .toList(),
  'spelling_spotter': (c) async => buildSpellingChallenges(
        pool: (await c.pool(WordFeature.learnerErrors,
                limitFactor: 20, where: (w) => !w.isProperNoun))
            .where((w) => hasSpellingErrors(w, isGerman: c.isGerman))
            .toList(),
        isGerman: c.isGerman,
        gradeLevel: c.grade,
        rounds: c.count,
        rng: c.rng,
      )
          .map((ch) => Item(
                game: 'spelling_spotter',
                prompt: 'Which spelling is correct?',
                options: ch.options,
                answer: ch.options[ch.correctIndex],
                // The screen reveals the example only once the learner has
                // answered, so it is not part of the question — it would
                // contain the correct spelling.
                notes: {
                  if (ch.contextSentence != null)
                    'shown after answering': ch.contextSentence,
                },
              ))
          .toList(),
  'cloze_flash': (c) async => buildClozeChallenges(
        pool: await c.pool(WordFeature.examples,
            where: (w) => !w.isProperNoun && !w.word.contains(' ')),
        texts: (w) => [
          for (final example in w.apiEnrichment?.examples ?? const [])
            if (example.text case final text?) text,
        ],
        maxChallenges: c.count,
        rng: c.rng,
      ).map((ch) => _clozeItem('cloze_flash', ch)).toList(),
  'expression_flash': (c) async => buildClozeChallenges(
        pool: await c.pool(WordFeature.expressions,
            where: (w) => !w.isProperNoun && !w.word.contains(' ')),
        texts: (w) => [
          for (final entry in w.apiEnrichment?.expressions ?? const [])
            if (entry.expression case final text?) text,
        ],
        maxChallenges: c.count,
        minLength: 8,
        maxLength: 80,
        minVisibleWords: 2,
        rng: c.rng,
      ).map((ch) => _clozeItem('expression_flash', ch)).toList(),
  'proverb_cloze': (c) async => buildClozeChallenges(
        pool: await c.pool(WordFeature.proverbs,
            where: (w) => !w.isProperNoun && !w.word.contains(' ')),
        texts: (w) => [
          for (final entry in w.apiEnrichment?.proverbs ?? const [])
            if (entry.proverb case final text?) text,
        ],
        maxChallenges: c.count,
        minLength: 8,
        maxLength: 120,
        minVisibleWords: 2,
        rng: c.rng,
      ).map((ch) => _clozeItem('proverb_cloze', ch)).toList(),
  'sentence_completion': (c) async => buildSentenceChallenges(
        pool: (await c.pool(WordFeature.gradeExamples,
                limitFactor: 10,
                where: (w) =>
                    !w.isProperNoun &&
                    w.isHeadword &&
                    !w.word.contains('_') &&
                    !w.word.contains(' ')))
            .where((w) => hasGradeExamples(w, c.grade))
            .toList(),
        gradeIndex: c.grade,
        maxChallenges: c.count,
        rng: c.rng,
      )
          .map((ch) => Item(
                game: 'sentence_completion',
                prompt: '${ch.before}___${ch.after}',
                options: ch.options,
                answer: ch.options[ch.correctIndex],
              ))
          .toList(),
  'word_class_flash': (c) async {
    const askable = {
      GermanWordType.substantiv,
      GermanWordType.verb,
      GermanWordType.adjektiv,
    };
    final pool = selectWordClassCandidates(
      catalogue: c.vocabulary.getAllWords(c.settings),
      askableTypes: askable,
      gradeLevel: c.grade,
      rng: c.rng,
    );
    final words = await c.vocabulary.hydrate(pool.take(c.count));
    return buildWordClassChallenges(words: words, maxChallenges: c.count)
        .map((ch) => Item(
              game: 'word_class_flash',
              prompt: ch.word.displayName,
              options: askable
                  .map((t) => _classLabel(c.strings, t, plural: false))
                  .toList(),
              answer: _classLabel(c.strings, ch.correctType, plural: false),
            ))
        .toList();
  },
  'hypernym_flash': (c) async {
    final pool = await c.pool(WordFeature.hypernyms,
        where: (w) =>
            !w.isProperNoun &&
            w.isHeadword &&
            !w.word.contains('_') &&
            !w.word.contains(' '));
    return buildHypernymChallenges(
      pool: pool,
      candidates: await c.vocabulary.hydrateBySpelling(pool.expand((w) =>
          (w.apiEnrichment?.hypernyms ?? const [])
              .map((h) => h.word ?? '')
              .where((h) => h.isNotEmpty))),
      isGerman: c.isGerman,
      maxChallenges: c.count,
      rng: c.rng,
    )
        .map((ch) => Item(
              game: 'hypernym_flash',
              prompt: ch.word.word,
              options: ch.options,
              answer: ch.options[ch.correctIndex],
            ))
        .toList();
  },
  'syllable_count': (c) async => buildSyllableChallenges(
        pool: await c.pool(WordFeature.hyphenation,
            where: (w) =>
                !w.isProperNoun &&
                w.isHeadword &&
                !w.word.contains('_') &&
                !w.word.contains(' ')),
        maxChallenges: c.count,
      )
          .map((ch) => Item(
                game: 'syllable_count',
                // The card shows the bare word: an article the count does not
                // include made "die Tür" read as a two-syllable prompt keyed 1.
                prompt: ch.word.word,
                options: const ['1', '2', '3', '4+'],
                answer: const ['1', '2', '3', '4+'][ch.correctBucket],
                notes: {'hyphenation': ch.word.hyphenation.join('|')},
              ))
          .toList(),
  'translation_flash': (c) async => buildTranslationChallenges(
        pool: await c.pool(WordFeature.translations,
            where: (w) => !w.isProperNoun && w.isHeadword),
        maxChallenges: c.count,
        rng: c.rng,
      )
          .map((ch) => Item(
                game: 'translation_flash',
                prompt: ch.word.displayName,
                options: ch.options,
                answer: ch.options[ch.correctIndex],
              ))
          .toList(),
  'reverse_translation_flash': (c) async => buildTranslationChallenges(
        pool: await c.pool(WordFeature.translations,
            where: (w) => !w.isProperNoun && w.isHeadword),
        maxChallenges: c.count,
        reversed: true,
        rng: c.rng,
      )
          .map((ch) => Item(
                game: 'reverse_translation_flash',
                prompt: ch.translation,
                options: ch.options,
                answer: ch.options[ch.correctIndex],
              ))
          .toList(),
  'antonym_flash': (c) async {
    final pool = await c.pool(WordFeature.antonyms,
        where: (w) =>
            !w.isProperNoun &&
            w.isHeadword &&
            !w.word.contains('_') &&
            !w.word.contains(' '));
    return buildAntonymChallenges(
      pool: pool,
      partners: await c.vocabulary.hydrateBySpelling(
          pool.expand((w) => w.apiEnrichment?.antonyms ?? const <String>[])),
      isGerman: c.isGerman,
      maxChallenges: c.count,
      rng: c.rng,
    )
        .map((ch) => Item(
              game: 'antonym_flash',
              prompt: ch.word.word,
              options: ch.options,
              answer: ch.options[ch.correctIndex],
              notes: {'grade': ch.word.gradeLevel},
            ))
        .toList();
  },
  'synonym_flash': (c) async {
    final pool = await c.pool(WordFeature.synonyms,
        where: (w) =>
            !w.isProperNoun &&
            w.isHeadword &&
            w.word.length >= 3 &&
            !w.word.contains('_') &&
            !w.word.contains(' '));
    return buildSynonymChallenges(
      pool: pool,
      catalogue: await c.vocabulary.hydrateBySpelling(
          pool.expand((w) => w.apiEnrichment?.synonyms ?? const <String>[])),
      isGerman: c.isGerman,
      maxChallenges: c.count,
      rng: c.rng,
    )
        .map((ch) => Item(
              game: 'synonym_flash',
              prompt: ch.word.word,
              options: ch.options,
              answer: ch.options[ch.correctIndex],
              notes: {'grade': ch.word.gradeLevel},
            ))
        .toList();
  },
  'definition_quiz': (c) async => buildDefinitionChallenges(
        pool: await c.pool(WordFeature.definitions,
            where: (w) => !w.isProperNoun && w.isHeadword),
        isGerman: c.isGerman,
        maxChallenges: c.count,
        rng: c.rng,
      )
          .map((ch) => Item(
                game: 'definition_quiz',
                prompt: ch.definition,
                options: ch.options,
                answer: ch.options[ch.correctIndex],
                notes: {'word': ch.word.word, 'grade': ch.word.gradeLevel},
              ))
          .toList(),
  'homophone_drill': (c) async {
    final groups = groupsForMode(HomophoneGameMode.homophones);
    final wanted = <String>{
      for (final group in groups)
        for (final word in group.words) word.toLowerCase(),
    };
    final entries = <dynamic>[];
    for (final spelling in wanted) {
      final entry = c.vocabulary.findByWrittenForm(spelling);
      if (entry != null && entry.word.toLowerCase() == spelling) {
        entries.add(entry);
      }
    }
    final words = await c.vocabulary.hydrate(entries.cast());
    return buildHomophoneChallenges(
      allWords: words,
      gradeLevel: c.grade,
      maxChallenges: c.count,
      rng: c.rng,
      groups: groups,
    )
        .map((ch) => Item(
              game: 'homophone_drill',
              prompt: ch.sentence,
              options: ch.options,
              answer: ch.options[ch.correctIndex],
              notes: {'group': ch.groupWords.join('/')},
            ))
        .toList();
  },
  'wortfalle': (c) async => buildWortfalleChallenges(
        maxChallenges: c.count,
        rng: c.rng,
      )
          .map((ch) => Item(
                game: 'wortfalle',
                prompt: ch.sentence,
                options: ch.options,
                answer: ch.options[ch.correctIndex],
                notes: {'pair': ch.words.join('/')},
              ))
          .toList(),
  'false_friends': (c) async {
    final friends = await c.vocabulary.getFalseFriends();
    return buildFalseFriendChallenges(
      friends: friends,
      maxChallenges: c.count,
      rng: c.rng,
    )
        .map((ch) => Item(
              game: 'false_friends',
              prompt: 'What does "${ch.english}" really mean?',
              options: ch.options,
              answer: ch.options[ch.correctIndex],
              notes: {'trap': '${ch.german} = ${ch.germanMeans}'},
            ))
        .toList();
  },
  'phrasal_verb_power': (c) async {
    final verbs = await c.vocabulary.getPhrasalVerbs();
    return buildPhrasalChallenges(
      verbs: verbs,
      gradeLevel: c.grade,
      maxChallenges: c.count,
      rng: c.rng,
    )
        .map((ch) => Item(
              game: 'phrasal_verb_power',
              prompt: ch.sentence,
              options: ch.options,
              answer: ch.options[ch.correctIndex],
              notes: {'phrasal': ch.phrasal, 'means': ch.meaning},
            ))
        .toList();
  },
  'phrasal_verb_match': (c) async {
    final verbs = await c.vocabulary.getPhrasalVerbs();
    return buildPhrasalMatchChallenges(
      verbs: verbs,
      gradeLevel: c.grade,
      maxChallenges: c.count,
      rng: c.rng,
    )
        .map((ch) => Item(
              game: 'phrasal_verb_match',
              prompt: 'What does "${ch.phrasal}" mean?',
              options: ch.options,
              answer: ch.options[ch.correctIndex],
            ))
        .toList();
  },
  'word_of_the_day': (c) async {
    final items = <Item>[];
    final pool = c.vocabulary.getAllWords(c.settings);
    for (var day = 0; day < c.count; day++) {
      final date = DateTime(2026, 1, 1).add(Duration(days: day));
      // The card walks candidates and shows the first with a usable gloss;
      // the dump has to do the same or it reviews a word nobody is shown.
      final candidates =
          wordOfTheDayCandidates(pool, date, targetBand: c.grade, count: 5);
      if (candidates.isEmpty) continue;
      GermanWord? word;
      for (final candidate in candidates) {
        final hydrated = await c.vocabulary.hydrateOne(candidate);
        word ??= hydrated;
        final definition = hydrated.displayDefinitions.firstOrNull;
        if (definition != null && isUsableDefinition(definition)) {
          word = hydrated;
          break;
        }
      }
      items.add(Item(
        game: 'word_of_the_day',
        prompt:
            '${date.toIso8601String().substring(0, 10)}: ${word!.displayName}',
        answer: word.displayDefinitions.firstOrNull,
        notes: {'grade': word.gradeLevel, 'cefr': word.cefrLevel ?? '—'},
      ));
    }
    return items;
  },
};

/// Games that still build their challenges inside the widget, so this harness
/// cannot reach them yet. Printed after a run so the gap stays visible.
/// Games that still build their challenges inside the widget. Empty: every
/// game in the menu can now be generated and reviewed headlessly.
const notYetReachable = <String>[];

/// What the menu calls each game, and what it tells a learner it is — the
/// localized strings the app actually shows, so a dump is read against the
/// game as offered rather than against a label this harness made up.
String? gameTitle(String game, S strings) => switch (game) {
      'word_find' => strings.wordFindTitle,
      'word_sort' => strings.wordSortTitle,
      'word_snake' => strings.wordSnakeTitle,
      'word_memory' => strings.wordMemoryTitle,
      'word_builder' => strings.wordBuilderTitle,
      'word_type_whirl' => strings.wordWhirlTitle,
      'spelling_spotter' => strings.spellingSpotterTitle,
      'sentence_completion' => strings.sentenceCompletionTitle,
      'definition_quiz' => strings.definitionQuizTitle,
      'sri_review' => strings.sriReviewTitle,
      'antonym_flash' => strings.antonymFlashTitle,
      'synonym_flash' => strings.synonymFlashTitle,
      'conjugation_drill' => strings.conjugationDrillTitle,
      'translation_flash' => strings.translationFlashTitle,
      'syllable_count' => strings.syllableCountTitle,
      'cloze_flash' => strings.clozeFlashTitle,
      'expression_flash' => strings.expressionFlashTitle,
      'homophone_drill' => strings.homophoneDrillTitle,
      'phrasal_verb_power' => strings.phrasalVerbPowerTitle,
      'phrasal_verb_match' => strings.phrasalVerbMatchTitle,
      'false_friends' => strings.falseFriendsTitle,
      'wortfalle' => strings.wortfalleTitle,
      'wortbaumeister' => strings.wortbaumeisterCardTitle,
      'grossstadt' => strings.grossstadtCardTitle,
      'grossschreib' => strings.grossschreibTitle,
      'verbtrenner' => strings.verbtrennerCardTitle,
      'hypernym_flash' => strings.hypernymFlashTitle,
      'word_class_flash' => strings.wordClassFlashTitle,
      'proverb_cloze' => strings.proverbClozeTitle,
      'reverse_translation_flash' => strings.reverseTranslationTitle,
      'word_of_the_day' => strings.wordOfTheDay,
      _ => null,
    };

/// A pack opened for auditing: the services a generator needs, plus the
/// temporary directory the database was unpacked into.
class AuditPack {
  AuditPack(
      this.vocabulary, this.sri, this.settings, this.language, this._directory);

  final VocabularyService vocabulary;
  final SriService sri;
  final GameProvider settings;
  final String language;
  final Directory _directory;

  /// The app's own strings for this pack's language.
  S get strings => lookupS(Locale(language));

  AuditContext context({
    required int grade,
    required int count,
    required Random rng,
  }) =>
      AuditContext(vocabulary, sri, settings, grade, count, rng, language);

  Future<void> dispose() async {
    await DictionaryDatabaseService().close();
    if (_directory.existsSync()) {
      await _directory.delete(recursive: true);
    }
  }
}

/// Where the German pack is, for a caller that needs to skip without it. The
/// English pack ships as an asset; the German one is a download.
String? get germanPackPath {
  // Empty counts as unset: a wrapper that always exports WU_PACK_DE would
  // otherwise make every caller look for a pack at "".
  final path = Platform.environment['WU_PACK_DE'];
  return (path == null || path.isEmpty) ? null : path;
}

/// Unpacks [language] into a temporary directory and initialises the services
/// the generators read from. The caller owns [AuditPack.dispose].
///
/// Throws [StateError] for the German pack when WU_PACK_DE is not set, since
/// every caller has to decide for itself whether that is a skip or a failure.
Future<AuditPack> openAuditPack(String language) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues({});
  final directory = await Directory.systemTemp.createTemp('wu_audit_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => directory.path,
  );

  final pack = kLanguagePacks[language]!;
  final List<int> bytes;
  if (language == 'en') {
    bytes = GZipDecoder().decodeBytes(
        await File('assets/grundwortschatz_en.db.gz').readAsBytes());
  } else {
    final path = germanPackPath;
    if (path == null) {
      await directory.delete(recursive: true);
      throw StateError(
          'set WU_PACK_DE=/path/to/decompressed/grundwortschatz.db');
    }
    bytes = await File(path).readAsBytes();
  }
  await File('${directory.path}/${pack.databaseName}').writeAsBytes(bytes);

  final vocabulary = VocabularyService();
  await vocabulary.initialize(learningLanguage: language);
  final sri = SriService();
  final settings = GameProvider(
    progressService: ProgressService(),
    sriService: sri,
    cognitiveProfileService: CognitiveProfileService(),
    prefs: await SharedPreferences.getInstance(),
  );
  return AuditPack(vocabulary, sri, settings, language, directory);
}
