// test/features/games/wortfalle_service_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/services/wortfalle_service.dart';

void main() {
  group('wortfalleCatalogue integrity', () {
    test('every pair is well-formed and examples are consistent', () {
      expect(wortfalleCatalogue.length, greaterThan(10));
      for (final p in wortfalleCatalogue) {
        expect(p.words.length, p.meanings.length,
            reason: 'words/meanings length mismatch for ${p.words}');
        expect(p.words.length, greaterThanOrEqualTo(2));
        expect(p.examples, isNotEmpty);
        for (final ex in p.examples) {
          expect(ex.sentence, contains('___'),
              reason: '${p.words}: example has no blank');
          expect(p.words, contains(ex.answer),
              reason: '${p.words}: answer "${ex.answer}" not in the pair');
        }
      }
    });
  });

  group('buildWortfalleChallenges', () {
    test('blank present, options are the pair, correct index right', () {
      final cs = buildWortfalleChallenges(rng: Random(1));
      expect(cs, isNotEmpty);
      for (final c in cs) {
        expect(c.sentence, contains('___'));
        expect(c.options.toSet(), c.words.toSet());
        // the option at correctIndex must be the example's intended answer,
        // i.e. it is one of the pair words
        expect(c.words, contains(c.options[c.correctIndex]));
      }
    });

    test('respects maxChallenges', () {
      expect(buildWortfalleChallenges(maxChallenges: 5, rng: Random(2)).length, 5);
    });

    test('das/dass pair produces a "dass" answer somewhere', () {
      final pair = ConfusionPair(
        words: const ['das', 'dass'],
        meanings: const ['a', 'b'],
        examples: const [(sentence: 'Ich denke, ___ es geht.', answer: 'dass')],
      );
      final c = buildWortfalleChallenges(rng: Random(3), catalogue: [pair]).single;
      expect(c.options[c.correctIndex], 'dass');
    });
  });
}
