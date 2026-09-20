// test/features/games/sri_review_service_test.dart
//
// The review game asks about words the learner has already struggled with, in
// the format of the skill they struggled at. Which format it picks — and what
// it falls back to when the word cannot support that format — is the logic.

import 'dart:math';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/services/sri_service.dart';
import 'package:WortUniversum/features/games/services/sri_review_service.dart';
import 'package:WortUniversum/generated/l10n.dart';

import 'word_fixture.dart';

GermanWord _noun(
  String word, {
  String? article,
  List<String> definitions = const [],
  List<String> learnerErrors = const [],
  List<String>? mistakes,
}) =>
    testWord(
      word,
      type: GermanWordType.substantiv,
      article: article,
      commonMistakes: mistakes,
      enrichment: testEnrichment(
        definitions: definitions,
        commonLearnerErrors: learnerErrors,
      ),
    );

SriLanguageData _due(String word, LanguageSkillType skill) => SriLanguageData(
      itemId: word,
      skillType: skill,
      nextReviewDate: DateTime.utc(2020),
    );

void main() {
  late S strings;

  setUpAll(() {
    strings = lookupS(const Locale('de'));
  });

  List<GermanWord> pool() => [
        _noun('Haus', definitions: ['Ein Gebäude zum Wohnen.']),
        _noun('Baum', definitions: ['Eine große Pflanze mit Stamm.']),
        _noun('Weg', definitions: ['Eine Strecke zum Gehen.']),
        _noun('Buch', definitions: ['Viele bedruckte Seiten.']),
      ];

  ReviewChallenge? build(
    GermanWord word,
    LanguageSkillType skill, {
    bool isGerman = true,
    Set<String>? validWords,
    List<GermanWord>? words,
  }) {
    final all = [word, ...(words ?? pool())];
    return buildReviewChallenge(
      word,
      _due(word.word, skill),
      all,
      validWords ?? all.map((w) => w.word.toLowerCase()).toSet(),
      strings: strings,
      isGerman: isGerman,
      rng: Random(1),
    );
  }

  group('article challenge', () {
    test('a German noun with an article is asked for it', () {
      final word = _noun('Gepäck',
          article: 'das', definitions: ['Was man auf eine Reise mitnimmt.']);
      final challenge = build(word, LanguageSkillType.articleSelection)!;
      expect(challenge.type, ReviewChallengeType.article);
      expect(challenge.options.toSet(), {'der', 'die', 'das'});
      expect(challenge.options[challenge.correctIndex], 'das');
      expect(challenge.prompt, contains('Gepäck'));
    });

    test('falls back to the definition quiz without an article', () {
      final word = _noun('Gepäck', definitions: ['Was man mitnimmt.']);
      expect(build(word, LanguageSkillType.articleSelection)!.type,
          ReviewChallengeType.definition);
    });

    test('is never asked of the English pack', () {
      final word = _noun('luggage',
          article: 'das', definitions: ['What you take on a journey.']);
      expect(
          build(word, LanguageSkillType.articleSelection, isGerman: false)!
              .type,
          ReviewChallengeType.definition);
    });
  });

  group('spelling challenge', () {
    test('offers the word against its own recorded misspellings', () {
      final word = _noun('Fahrrad',
          definitions: ['Ein Rad zum Fahren.'], mistakes: ['Farrad']);
      final challenge = build(word, LanguageSkillType.spelling)!;
      expect(challenge.type, ReviewChallengeType.spelling);
      expect(challenge.options, contains('Farrad'));
      expect(challenge.options[challenge.correctIndex], 'Fahrrad');
    });

    test('a misspelling that is itself a real word is not offered', () {
      final word = _noun('Weg',
          definitions: ['Eine Strecke zum Gehen.'], mistakes: ['Haus']);
      // "Haus" is in the catalogue, so keying it wrong would be wrong.
      expect(build(word, LanguageSkillType.spelling)!.type,
          ReviewChallengeType.definition);
    });

    test('a multi-word entry cannot be spelled at', () {
      final word = _noun('zum Beispiel',
          definitions: ['Eine Redewendung.'], mistakes: ['zum Beispil']);
      expect(build(word, LanguageSkillType.spelling)!.type,
          ReviewChallengeType.definition);
    });

    test('the English pack reads its own learner-error field', () {
      final word = _noun('bicycle',
          definitions: ['A vehicle with two wheels.'],
          learnerErrors: ['bycicle']);
      final challenge =
          build(word, LanguageSkillType.spelling, isGerman: false)!;
      expect(challenge.type, ReviewChallengeType.spelling);
      expect(challenge.options, contains('bycicle'));
    });
  });

  group('definition challenge', () {
    test('inherits the quiz\'s rules: the headword is redacted', () {
      final word = _noun('Alter',
          article: 'das', definitions: ['Alter ist ein Lebensabschnitt.']);
      final challenge = build(word, LanguageSkillType.vocabulary)!;
      expect(challenge.type, ReviewChallengeType.definition);
      expect(challenge.prompt, isNot(contains('Alter')));
      expect(challenge.prompt, contains('___'));
      expect(challenge.options[challenge.correctIndex], 'das Alter');
    });

    test('a word with no definition cannot be reviewed at all', () {
      expect(build(_noun('Haus'), LanguageSkillType.vocabulary), isNull);
    });
  });
}
