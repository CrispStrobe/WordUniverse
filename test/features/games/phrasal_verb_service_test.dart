// test/features/games/phrasal_verb_service_test.dart
//
// Unit tests for the Phrasal Verb Power game logic (#46):
//   • PhrasalVerb.fromRow — JSON column parsing
//   • buildPhrasalChallenges — option building, particle blanking,
//     grade preference, whole-word matching, fallback to Wiktionary examples

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/models/phrasal_verb.dart';
import 'package:WortUniversum/features/games/services/phrasal_verb_service.dart';

PhrasalVerb _pv({
  required String phrasal,
  required String particle,
  String? baseVerb,
  List<String> distractors = const ['on', 'in', 'down'],
  Map<String, List<String>> examples = const {},
  List<String> wiktionaryExamples = const [],
  int gradeBand = 3,
}) =>
    PhrasalVerb(
      phrasal: phrasal,
      baseVerb: baseVerb ?? phrasal.split(' ').first,
      particle: particle,
      meaning: 'a meaning',
      senses: const ['sense one'],
      distractors: distractors,
      examples: examples,
      wiktionaryExamples: wiktionaryExamples,
      gradeBand: gradeBand,
      baseZipf: 5.0,
    );

void main() {
  group('PhrasalVerb.fromRow', () {
    test('parses JSON columns', () {
      final pv = PhrasalVerb.fromRow({
        'phrasal': 'give up',
        'base_verb': 'give',
        'particle': 'up',
        'meaning': 'surrender',
        'senses_json': '["surrender","quit"]',
        'distractors_json': '["in","out","off"]',
        'examples_json': '{"3":["She gave up the game."]}',
        'wiktionary_examples_json': '["Don\'t give up now."]',
        'grade_band': 3,
        'base_zipf': 5.71,
      });
      expect(pv.phrasal, 'give up');
      expect(pv.particle, 'up');
      expect(pv.senses, ['surrender', 'quit']);
      expect(pv.distractors, ['in', 'out', 'off']);
      expect(pv.examples['3'], ['She gave up the game.']);
      expect(pv.wiktionaryExamples, ["Don't give up now."]);
      expect(pv.baseZipf, closeTo(5.71, 0.001));
    });

    test('tolerates missing / null columns', () {
      final pv = PhrasalVerb.fromRow({'phrasal': 'run out', 'particle': 'out'});
      expect(pv.senses, isEmpty);
      expect(pv.examples, isEmpty);
      expect(pv.gradeBand, 3);
    });
  });

  group('buildPhrasalChallenges', () {
    test('blanks the particle and includes correct + distractor options', () {
      final challenges = buildPhrasalChallenges(
        verbs: [
          _pv(
            phrasal: 'give up',
            particle: 'up',
            distractors: const ['in', 'out', 'off'],
            examples: const {
              '3': ['She decided to give up smoking.']
            },
          ),
        ],
        gradeLevel: 3,
        rng: Random(1),
      );
      expect(challenges, hasLength(1));
      final c = challenges.single;
      expect(c.sentence, 'She decided to give ___ smoking.');
      expect(c.options, containsAll(['up', 'in', 'out', 'off']));
      expect(c.options[c.correctIndex], 'up');
    });

    test('options never contain duplicate of the correct particle', () {
      final c = buildPhrasalChallenges(
        verbs: [
          _pv(
            phrasal: 'take off',
            particle: 'off',
            distractors: const [
              'off',
              'up',
              'down'
            ], // 'off' dup must be dropped
            examples: const {
              '3': ['The plane will take off soon.']
            },
          ),
        ],
        gradeLevel: 3,
        rng: Random(2),
      ).single;
      final offCount = c.options.where((o) => o == 'off').length;
      expect(offCount, 1);
    });

    test('only blanks whole-word particle, not substrings', () {
      // particle "up" must not be blanked inside "upset"
      final challenges = buildPhrasalChallenges(
        verbs: [
          _pv(
            phrasal: 'cheer up',
            particle: 'up',
            examples: const {
              '3': ['Do not be upset; cheer up now.']
            },
          ),
        ],
        gradeLevel: 3,
        rng: Random(3),
      );
      expect(challenges.single.sentence, 'Do not be upset; cheer ___ now.');
    });

    test('falls back to Wiktionary examples when no grade example fits', () {
      final challenges = buildPhrasalChallenges(
        verbs: [
          _pv(
            phrasal: 'put off',
            particle: 'off',
            wiktionaryExamples: const ["Don't put off your homework."],
          ),
        ],
        gradeLevel: 4,
        rng: Random(4),
      );
      expect(challenges.single.sentence, "Don't put ___ your homework.");
    });

    test('skips entries with no usable sentence', () {
      final challenges = buildPhrasalChallenges(
        verbs: [_pv(phrasal: 'mess up', particle: 'up')], // no examples at all
        gradeLevel: 3,
        rng: Random(5),
      );
      expect(challenges, isEmpty);
    });

    test('respects maxChallenges', () {
      final verbs = List.generate(
        20,
        (i) => _pv(
          phrasal: 'verb$i up',
          particle: 'up',
          baseVerb: 'verb$i',
          examples: {
            '3': ['I will verb$i up today.']
          },
        ),
      );
      final challenges = buildPhrasalChallenges(
        verbs: verbs,
        gradeLevel: 3,
        maxChallenges: 5,
        rng: Random(6),
      );
      expect(challenges.length, 5);
    });
  });

  group('buildPhrasalMatchChallenges', () {
    PhrasalVerb m(String phrasal, String meaning, {String? base}) =>
        PhrasalVerb(
          phrasal: phrasal,
          baseVerb: base ?? phrasal.split(' ').first,
          particle: phrasal.split(' ').last,
          meaning: meaning,
          senses: const [],
          distractors: const [],
          examples: const {},
          wiktionaryExamples: const [],
          gradeBand: 3,
          baseZipf: 5.0,
        );

    final sample = [
      m('give up', 'stop trying', base: 'give'),
      m('take off', 'leave the ground', base: 'take'),
      m('look after', 'care for someone', base: 'look'),
      m('run out', 'use up all of something', base: 'run'),
      m('put off', 'postpone', base: 'put'),
    ];

    test('correct meaning is among options and indexed correctly', () {
      final cs = buildPhrasalMatchChallenges(
        verbs: sample,
        gradeLevel: 3,
        rng: Random(1),
      );
      expect(cs, isNotEmpty);
      for (final c in cs) {
        expect(c.options[c.correctIndex], c.correctMeaning);
        expect(c.options.length, lessThanOrEqualTo(4));
      }
    });

    test('options have no duplicate meanings', () {
      final c = buildPhrasalMatchChallenges(
        verbs: sample,
        gradeLevel: 3,
        rng: Random(2),
      ).first;
      final lowered = c.options.map((o) => o.toLowerCase()).toList();
      expect(lowered.toSet().length, lowered.length);
    });

    test('distractor meanings are real meanings of other phrasal verbs', () {
      final allMeanings = sample.map((v) => v.meaning.toLowerCase()).toSet();
      final c = buildPhrasalMatchChallenges(
        verbs: sample,
        gradeLevel: 3,
        rng: Random(3),
      ).first;
      for (final o in c.options) {
        expect(allMeanings, contains(o.toLowerCase()));
      }
    });

    test('skips entries without a meaning', () {
      final cs = buildPhrasalMatchChallenges(
        verbs: [m('mess up', ''), m('give up', 'stop trying')],
        gradeLevel: 3,
        rng: Random(4),
      );
      expect(cs.every((c) => c.phrasal != 'mess up'), isTrue);
    });

    test('returns empty when fewer than two usable verbs', () {
      expect(
        buildPhrasalMatchChallenges(
            verbs: [m('give up', 'stop trying')],
            gradeLevel: 3,
            rng: Random(5)),
        isEmpty,
      );
    });
  });
  group('what is not taught', () {
    test('a phrasal verb glossed as sex is not offered', () {
      // "lie by" really does mean "be intimate with someone" — an accurate
      // archaic sense, so there is nothing a correction could fix. All 400
      // entries were read; it is the only one that matters.
      final verbs = [
        PhrasalVerb(
          phrasal: 'lie by',
          baseVerb: 'lie',
          particle: 'by',
          meaning: 'be intimate with someone',
          senses: const [],
          distractors: const [],
          examples: const {},
          wiktionaryExamples: const [],
          gradeBand: 4,
          baseZipf: 5.0,
        ),
        PhrasalVerb(
          phrasal: 'stop by',
          baseVerb: 'stop',
          particle: 'by',
          meaning: 'visit someone for a short time',
          senses: const [],
          distractors: const [],
          examples: const {},
          wiktionaryExamples: const [],
          gradeBand: 4,
          baseZipf: 5.0,
        ),
      ];
      final matches = buildPhrasalMatchChallenges(
          verbs: verbs, gradeLevel: 4, rng: Random(1));
      expect(matches.every((c) => c.phrasal != 'lie by'), isTrue);
      expect(matches.expand((c) => c.options),
          isNot(contains('be intimate with someone')));
    });
  });
}
