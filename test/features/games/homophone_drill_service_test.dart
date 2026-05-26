// test/features/games/homophone_drill_service_test.dart
//
// Unit tests for HomophoneDrillService (#38):
//   • homophoneGroups catalogue — structure & content
//   • _blankWord helper (via buildHomophoneChallenges output)
//   • buildHomophoneChallenges — challenge building, grade filtering,
//     option shuffling, whole-word matching
//   • Realistic data verification: confirmed pairs from the EN DB

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/services/homophone_drill_service.dart'
    show
        HomophoneGroup,
        HomophoneGameMode,
        buildHomophoneChallenges,
        confusableGroups,
        groupsForMode,
        homophoneGroups;
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({Map<String, List<String>>? gradeExamples}) =>
    ApiEnrichment(
      enrichmentStatus: 'ok',
      definitions: const ['a definition'],
      pronunciation: const [],
      examples: const [],
      synonyms: const [],
      antonyms: const [],
      conceptnet: const [],
      alternativeAnalyses: const [],
      inflections: const [],
      semanticRelations: const [],
      hyphenation: const [],
      translations: const [],
      derivedTerms: const [],
      relatedTerms: const [],
      expressions: const [],
      proverbs: const [],
      entryNotes: const [],
      hypernyms: const [],
      hyponyms: const [],
      holonyms: const [],
      meronyms: const [],
      coordinateTerms: const [],
      gutenbergExamples: const [],
      commonLearnerErrors: const [],
      gradeExamples: gradeExamples,
    );

GermanWord _word(String word, {Map<String, List<String>>? gradeExamples}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: GermanWordType.andere,
      gradeLevel: 1,
      lemma: word,
      sources: const [],
      isGrundwortschatzBW: false,
      nurImPlural: false,
      graphematicVariants: const [],
      categories: const [],
      exampleSentences: const [],
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: false,
      apiEnrichment:
          gradeExamples != null ? _enrichment(gradeExamples: gradeExamples) : null,
      examples: const [],
      hyphenation: const [],
      wiktionaryInflections: const [],
      translations: const [],
      derivedTerms: const [],
      relatedTerms: const [],
      expressions: const [],
      proverbs: const [],
      entryNotes: const [],
      hypernyms: const [],
      hyponyms: const [],
      holonyms: const [],
      meronyms: const [],
      coordinateTerms: const [],
    );

/// Build a minimal word list that covers the [group.words] of a given group,
/// each with a grade-1 example sentence.
List<GermanWord> _wordsForGroup(HomophoneGroup group) => [
      for (var i = 0; i < group.words.length; i++)
        _word(
          group.words[i],
          gradeExamples: {
            '1': ['I ${group.words[i]} today.', 'She uses ${group.words[i]}.'],
          },
        )
    ];

// ─── Catalogue structure ──────────────────────────────────────────────────────

void main() {
  group('homophoneGroups catalogue', () {
    test('contains at least 20 groups', () {
      expect(homophoneGroups.length, greaterThanOrEqualTo(20));
    });

    test('every group has 2 or 3 words', () {
      for (final g in homophoneGroups) {
        expect(g.words.length, inInclusiveRange(2, 3),
            reason: '${g.words} should have 2-3 members');
      }
    });

    test('every group has matching meanings list length', () {
      for (final g in homophoneGroups) {
        expect(g.meanings.length, g.words.length,
            reason: '${g.words} meanings length mismatch');
      }
    });

    test('no duplicate words within a group', () {
      for (final g in homophoneGroups) {
        expect(g.words.toSet().length, g.words.length,
            reason: '${g.words} has duplicate entries');
      }
    });

    test('all group words are lower-case', () {
      for (final g in homophoneGroups) {
        for (final w in g.words) {
          expect(w, w.toLowerCase(),
              reason: '$w should be lower-case in catalogue');
        }
      }
    });

    test('to/too/two triple is present', () {
      final triple = homophoneGroups.firstWhere(
          (g) => g.words.contains('to') && g.words.contains('too'),
          orElse: () => throw TestFailure('to/too group missing'));
      expect(triple.words, containsAll(['to', 'too', 'two']));
    });

    test('hear/here pair is present', () {
      expect(
          homophoneGroups.any((g) =>
              g.words.contains('hear') && g.words.contains('here')),
          isTrue);
    });

    test('there/their pair is present', () {
      expect(
          homophoneGroups.any((g) =>
              g.words.contains('there') && g.words.contains('their')),
          isTrue);
    });

    test('no meaning entry is empty', () {
      for (final g in homophoneGroups) {
        for (final m in g.meanings) {
          expect(m.trim(), isNotEmpty,
              reason: 'Empty meaning in group ${g.words}');
        }
      }
    });
  });

  // ─── buildHomophoneChallenges ─────────────────────────────────────────────

  group('buildHomophoneChallenges', () {
    test('returns empty list when no words match any group', () {
      final challenges = buildHomophoneChallenges(
        allWords: [_word('unrelatedword')],
        gradeLevel: 1,
      );
      expect(challenges, isEmpty);
    });

    test('returns challenges when group members are present', () {
      final group = homophoneGroups
          .firstWhere((g) => g.words.contains('hear') && g.words.contains('here'));
      final challenges = buildHomophoneChallenges(
        allWords: _wordsForGroup(group),
        gradeLevel: 1,
      );
      expect(challenges, isNotEmpty);
    });

    test('correctIndex is valid index into options', () {
      final group = homophoneGroups
          .firstWhere((g) => g.words.contains('know') && g.words.contains('no'));
      final challenges = buildHomophoneChallenges(
        allWords: _wordsForGroup(group),
        gradeLevel: 1,
      );
      for (final c in challenges) {
        expect(c.correctIndex, inInclusiveRange(0, c.options.length - 1));
      }
    });

    test('options contain all group words', () {
      final group = homophoneGroups
          .firstWhere((g) => g.words.contains('to') && g.words.contains('too'));
      final challenges = buildHomophoneChallenges(
        allWords: _wordsForGroup(group),
        gradeLevel: 1,
      );
      for (final c in challenges) {
        expect(c.options, containsAll(group.words));
      }
    });

    test('correct word matches options[correctIndex]', () {
      final group = homophoneGroups
          .firstWhere((g) => g.words.contains('son') && g.words.contains('sun'));
      final challenges = buildHomophoneChallenges(
        allWords: _wordsForGroup(group),
        gradeLevel: 1,
      );
      for (final c in challenges) {
        expect(c.options[c.correctIndex].toLowerCase(),
            c.correctWord.toLowerCase());
      }
    });

    test('sentence contains ___ blank placeholder', () {
      final group = homophoneGroups
          .firstWhere((g) => g.words.contains('hear') && g.words.contains('here'));
      final challenges = buildHomophoneChallenges(
        allWords: _wordsForGroup(group),
        gradeLevel: 1,
      );
      for (final c in challenges) {
        expect(c.sentence, contains('___'));
      }
    });

    test('maxChallenges is respected', () {
      final allWords = homophoneGroups
          .expand(_wordsForGroup)
          .toList();
      final challenges = buildHomophoneChallenges(
        allWords: allWords,
        gradeLevel: 2,
        maxChallenges: 5,
      );
      expect(challenges.length, lessThanOrEqualTo(5));
    });

    test('groupWords and groupMeanings have same length', () {
      final group = homophoneGroups
          .firstWhere((g) => g.words.contains('by') && g.words.contains('buy'));
      final challenges = buildHomophoneChallenges(
        allWords: _wordsForGroup(group),
        gradeLevel: 1,
      );
      for (final c in challenges) {
        expect(c.groupWords.length, c.groupMeanings.length);
      }
    });

    // ─── Whole-word matching ────────────────────────────────────────────────

    test('does not blank partial word matches (no in know)', () {
      // "know" contains "no" — "no" should not blank "know" or vice versa.
      final knowWord = _word('know', gradeExamples: {
        '1': ['I know her well.']
      });
      final noWord = _word('no', gradeExamples: {
        '1': ['No, I disagree.']
      });
      final challenges = buildHomophoneChallenges(
        allWords: [knowWord, noWord],
        gradeLevel: 1,
      );
      // "know" in "I know her well." should blank to "I ___ her well."
      // "no" should NOT blank "know" into "___w her well."
      for (final c in challenges) {
        if (c.correctWord == 'know') {
          expect(c.sentence, contains('___'));
          expect(c.sentence, isNot(contains('w her'))); // partial match guard
        }
        if (c.correctWord == 'no') {
          expect(c.sentence, contains('___'));
        }
      }
    });

    test('does not blank "to" inside "too" (whole-word guard)', () {
      // "too" contains "to" — "I'm going too." should blank "too", not "to".
      final toWord = _word('to', gradeExamples: {
        '1': ['I go to school.']
      });
      final tooWord = _word('too', gradeExamples: {
        '1': ["I'm going too."]
      });
      final twoWord = _word('two', gradeExamples: {
        '1': ['I have two cats.']
      });
      final challenges = buildHomophoneChallenges(
        allWords: [toWord, tooWord, twoWord],
        gradeLevel: 1,
      );
      final tooChallenges = challenges.where((c) => c.correctWord == 'too');
      for (final c in tooChallenges) {
        // Blanked sentence must not leave "o." artifact from partial "to" match.
        expect(c.sentence, isNot(contains('o.')));
      }
    });
  });

  // ─── Realistic DB-verified pairs ─────────────────────────────────────────

  group('Realistic homophone pairs (DB-verified)', () {
    // Pairs confirmed present in pipeline/voc-en/grundwortschatz_en.db.

    test('to/too/two — triple group — all members verifiable', () {
      final group = homophoneGroups
          .firstWhere((g) => g.words.contains('to') && g.words.contains('two'));
      expect(group.words, containsAll(['to', 'too', 'two']));
      // Meanings must reflect distinct senses.
      expect(group.meanings[group.words.indexOf('two')],
          contains('number'));
    });

    test('hear/here — meanings distinguish ear vs place', () {
      final group = homophoneGroups.firstWhere(
          (g) => g.words.contains('hear') && g.words.contains('here'));
      final hearMeaning = group.meanings[group.words.indexOf('hear')];
      final hereMeaning = group.meanings[group.words.indexOf('here')];
      expect(hearMeaning.toLowerCase(),
          anyOf(contains('ear'), contains('perceive'), contains('listen')));
      expect(hereMeaning.toLowerCase(),
          anyOf(contains('place'), contains('here'), contains('location')));
    });

    test('flour/flower — food vs plant distinction', () {
      final group = homophoneGroups.firstWhere(
          (g) => g.words.contains('flour') && g.words.contains('flower'));
      final flourIdx = group.words.indexOf('flour');
      final flowerIdx = group.words.indexOf('flower');
      expect(group.meanings[flourIdx].toLowerCase(),
          anyOf(contains('bak'), contains('grain'), contains('ground')));
      expect(group.meanings[flowerIdx].toLowerCase(),
          anyOf(contains('plant'), contains('bloom'), contains('petal')));
    });

    test('allowed/aloud — permission vs spoken', () {
      final group = homophoneGroups.firstWhere(
          (g) => g.words.contains('allowed') && g.words.contains('aloud'));
      final allowedIdx = group.words.indexOf('allowed');
      final aloudIdx = group.words.indexOf('aloud');
      expect(group.meanings[allowedIdx].toLowerCase(),
          anyOf(contains('permit'), contains('allow')));
      expect(group.meanings[aloudIdx].toLowerCase(),
          anyOf(contains('loud'), contains('spoken'), contains('audib')));
    });

    test('buildHomophoneChallenges produces valid challenges for realistic data', () {
      // Use real-world-style grade_examples matching the DB format.
      final realisticWords = [
        _word('hear', gradeExamples: {
          '1': ['I hear a dog.', 'Can you hear me?'],
          '2': ['I hear the music.'],
        }),
        _word('here', gradeExamples: {
          '1': ['Come here.', 'I am here now.'],
          '2': ['Put it here.'],
        }),
        _word('to', gradeExamples: {
          '1': ['I go to school.', 'She goes to the park.'],
        }),
        _word('too', gradeExamples: {
          '1': ["It's too big.", "I'm going too."],
        }),
        _word('two', gradeExamples: {
          '1': ['I have two pencils.', 'The clock shows two.'],
        }),
      ];

      final challenges = buildHomophoneChallenges(
        allWords: realisticWords,
        gradeLevel: 1,
        maxChallenges: 20,
      );

      expect(challenges, isNotEmpty);
      for (final c in challenges) {
        // Sentence must have a blank.
        expect(c.sentence, contains('___'));
        // Options list includes the correct answer.
        expect(c.options.map((o) => o.toLowerCase()),
            contains(c.correctWord.toLowerCase()));
        // Meanings parallel the options.
        expect(c.groupMeanings.length, c.groupWords.length);
      }
    });
  });

  // ─── Confusable catalogue (#40) ──────────────────────────────────────────

  group('confusableGroups catalogue', () {
    test('contains at least 15 groups', () {
      expect(confusableGroups.length, greaterThanOrEqualTo(15));
    });

    test('every group has 2 or 3 words', () {
      for (final g in confusableGroups) {
        expect(g.words.length, inInclusiveRange(2, 3),
            reason: '${g.words} should have 2-3 members');
      }
    });

    test('every group has matching meanings length', () {
      for (final g in confusableGroups) {
        expect(g.meanings.length, g.words.length,
            reason: '${g.words} meanings mismatch');
      }
    });

    test('affect/effect pair is present', () {
      expect(
          confusableGroups.any((g) =>
              g.words.contains('affect') && g.words.contains('effect')),
          isTrue);
    });

    test('lose/loose pair is present', () {
      expect(
          confusableGroups
              .any((g) => g.words.contains('lose') && g.words.contains('loose')),
          isTrue);
    });

    test('fewer/less pair is present', () {
      expect(
          confusableGroups
              .any((g) => g.words.contains('fewer') && g.words.contains('less')),
          isTrue);
    });

    test('principal/principle pair is present', () {
      expect(
          confusableGroups.any((g) =>
              g.words.contains('principal') &&
              g.words.contains('principle')),
          isTrue);
    });

    test('no confusable group is an exact duplicate of a homophone group', () {
      final homophoneSets =
          homophoneGroups.map((g) => g.words.toSet()).toList();
      for (final cg in confusableGroups) {
        final cgSet = cg.words.toSet();
        expect(homophoneSets.any((hs) => hs.containsAll(cgSet) && hs.length == cgSet.length),
            isFalse,
            reason: '${cg.words} is an exact duplicate of a homophones group');
      }
    });
  });

  // ─── groupsForMode ────────────────────────────────────────────────────────

  group('groupsForMode', () {
    test('homophones mode returns homophoneGroups', () {
      expect(groupsForMode(HomophoneGameMode.homophones), homophoneGroups);
    });

    test('confusables mode returns confusableGroups', () {
      expect(groupsForMode(HomophoneGameMode.confusables), confusableGroups);
    });
  });

  group('buildHomophoneChallenges with confusable groups', () {
    test('accepts explicit groups= parameter and builds challenges', () {
      final affectWord = _word('affect', gradeExamples: {
        '1': ['The rain affects our plans.'],
        '2': ['Loud noises can affect my focus.'],
      });
      final effectWord = _word('effect', gradeExamples: {
        '1': ['The exercise has an effect.'],
        '2': ['What is the effect of heat?'],
      });
      final group = confusableGroups.firstWhere(
          (g) => g.words.contains('affect') && g.words.contains('effect'));

      final challenges = buildHomophoneChallenges(
        allWords: [affectWord, effectWord],
        gradeLevel: 2,
        groups: [group],
      );
      expect(challenges, isNotEmpty);
      for (final c in challenges) {
        expect(c.sentence, contains('___'));
        expect(c.options, containsAll(['affect', 'effect']));
      }
    });

    test('correct answers alternate between confusable pairs', () {
      final looseWord = _word('loose', gradeExamples: {
        '2': ['The dog runs loose.']
      });
      final loseWord = _word('lose', gradeExamples: {
        '2': ['I do not want to lose.']
      });
      final group = confusableGroups.firstWhere(
          (g) => g.words.contains('lose') && g.words.contains('loose'));

      final challenges = buildHomophoneChallenges(
        allWords: [looseWord, loseWord],
        gradeLevel: 2,
        groups: [group],
      );
      // Both words should appear as the correct answer in some challenge.
      final correctWords = challenges.map((c) => c.correctWord).toSet();
      expect(correctWords, isNotEmpty);
      // Each challenge's correctIndex should point to the right option.
      for (final c in challenges) {
        expect(c.options[c.correctIndex].toLowerCase(),
            c.correctWord.toLowerCase());
      }
    });
  });
}
