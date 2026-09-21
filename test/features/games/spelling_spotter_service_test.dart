// test/features/games/spelling_spotter_service_test.dart
//
// Unit tests for SpellingSpotter pure-function helpers.
// Each group targets one of the three functions; the final group
// walks through realistic DE examples to confirm the combined
// pipeline produces sound challenges.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/services/spelling_spotter_service.dart';

void main() {
  // ─── normWord ─────────────────────────────────────────────────────────────

  group('normWord', () {
    test('removes single LiTKey underscore', () {
      expect(normWord('vorbei_bringen'), 'vorbeibringen');
    });

    test('removes multiple underscores (morpheme chain)', () {
      expect(normWord('zu_rück_bringen'), 'zurückbringen');
    });

    test('leaves plain words unchanged', () {
      expect(normWord('laufen'), 'laufen');
    });

    test('leaves empty string unchanged', () {
      expect(normWord(''), '');
    });

    test('leaves spaces unchanged (multi-word phrase, filtered elsewhere)', () {
      expect(normWord('auf dem Weg'), 'auf dem Weg');
    });

    test('real DE example: auf_stehen → aufstehen', () {
      expect(normWord('auf_stehen'), 'aufstehen');
    });
  });

  // ─── parseErrors ──────────────────────────────────────────────────────────

  group('parseErrors', () {
    test('single clean entry is returned as-is', () {
      expect(parseErrors(['hapy']), ['hapy']);
    });

    test('comma-separated entry "ihn, in" splits into two tokens', () {
      expect(parseErrors(['ihn, in']), ['ihn', 'in']);
    });

    test('comma with no space also splits', () {
      expect(parseErrors(['ihn,in']), ['ihn', 'in']);
    });

    test('multiple entries, some comma-joined, flatten correctly', () {
      expect(
        parseErrors(['hapy', 'happpy, happi', 'hapyy']),
        ['hapy', 'happpy', 'happi', 'hapyy'],
      );
    });

    test('empty string after trim is dropped', () {
      expect(parseErrors(['hapy', ',', '']), ['hapy']);
    });

    test('trailing comma produces no ghost entry', () {
      expect(parseErrors(['ihn,']), ['ihn']);
    });

    test('empty input list → empty output', () {
      expect(parseErrors([]), isEmpty);
    });

    test('whitespace-only entry is dropped', () {
      expect(parseErrors(['   ', 'hapy']), ['hapy']);
    });
  });

  // ─── isDistractorPlausible ────────────────────────────────────────────────

  group('isDistractorPlausible', () {
    const validWords = {'in', 'ihn', 'ihm', 'ihnen', 'die', 'der', 'das'};

    test('valid vocabulary word "in" rejected for target "ihn"', () {
      expect(
        isDistractorPlausible('in', 'ihn', validWords: validWords),
        isFalse,
      );
    });

    test('valid vocab word "ihm" rejected for target "ihn"', () {
      expect(
        isDistractorPlausible('ihm', 'ihn', validWords: validWords),
        isFalse,
      );
    });

    test('genuine misspelling "ihn" with extra h accepted', () {
      // "ihhn" is not a real word
      expect(
        isDistractorPlausible('ihhn', 'ihn', validWords: validWords),
        isTrue,
      );
    });

    test('candidate equal to target is rejected', () {
      expect(
        isDistractorPlausible('ihn', 'ihn', validWords: validWords),
        isFalse,
      );
    });

    test('candidate with underscore rejected (raw LiTKey form)', () {
      expect(
        isDistractorPlausible('vorbei_bringen', 'vorbeibringen',
            validWords: {}),
        isFalse,
      );
    });

    test('candidate with comma rejected (unparsed multi-entry)', () {
      expect(
        isDistractorPlausible('ihn, in', 'ihn', validWords: {}),
        isFalse,
      );
    });

    test('candidate with space rejected (multi-word phrase)', () {
      expect(
        isDistractorPlausible('vor bei', 'vorbei', validWords: {}),
        isFalse,
      );
    });

    test('candidate more than 4 chars longer than target is rejected', () {
      // "ruksak" vs "vorbeibringen" — length diff = 8, well above threshold
      expect(
        isDistractorPlausible('ruksak', 'vorbeibringen', validWords: {}),
        isFalse,
      );
    });

    test('candidate 4 chars shorter than target is accepted (boundary)', () {
      // "vorb" (4) vs "vorbei" (6) — diff = 2, within threshold
      expect(
        isDistractorPlausible('vorb', 'vorbei', validWords: {}),
        isTrue,
      );
    });

    test('empty candidate is rejected', () {
      expect(
        isDistractorPlausible('', 'ihn', validWords: {}),
        isFalse,
      );
    });

    test('case-insensitive validWords check: "Ihn" matches entry "ihn"', () {
      expect(
        isDistractorPlausible('Ihn', 'ihn', validWords: {'ihn'}),
        isFalse,
      );
    });
  });

  // ─── Realistic pipeline scenarios ─────────────────────────────────────────

  group('realistic DE challenge scenarios', () {
    // Simulates what _buildChallenge does for "ihn" with commonMistakes ["in"].

    test('"ihn": error "in" (a real word) must not become a distractor', () {
      const target = 'ihn';
      final validWords = {'ihn', 'in', 'ihm', 'ihnen'};
      final errors = parseErrors(['in']); // from commonMistakes

      // Apply the validWords filter that now applies to primary errors:
      final filteredErrors = errors
          .map(normWord)
          .where((e) =>
              e.toLowerCase() != target.toLowerCase() &&
              e.isNotEmpty &&
              !e.contains(' ') &&
              !validWords.contains(e.toLowerCase()))
          .toList();

      expect(filteredErrors, isEmpty,
          reason: '"in" is a valid vocab word and must be excluded');
    });

    test('"vorbeibringen": underscore form normalises correctly', () {
      const raw = 'vorbei_bringen';
      expect(normWord(raw), 'vorbeibringen');
    });

    test(
        '"ruksak" is too short to be a plausible distractor for "vorbeibringen"',
        () {
      expect(
        isDistractorPlausible('ruksak', 'vorbeibringen', validWords: {}),
        isFalse,
      );
    });

    test('genuine misspelling "vorbeibrngen" (missing i) is plausible', () {
      expect(
        isDistractorPlausible('vorbeibrngen', 'vorbeibringen', validWords: {}),
        isTrue,
      );
    });

    test('a typo corpus entry that does not look like the word is dropped', () {
      // The English errors come from a corpus of what people actually typed,
      // and "base" arrives with "pare" and "pase" among its misspellings.
      // Both were offered as wrong spellings and "pare" is a word, so the
      // question had two right answers. A shared first letter is what
      // separates them from the real slips.
      for (final noise in ['pare', 'pase']) {
        expect(isDistractorPlausible(noise, 'base', validWords: {}), isFalse,
            reason: '$noise does not start like "base"');
      }
      for (final slip in ['basse', 'bates', 'bas']) {
        expect(isDistractorPlausible(slip, 'base', validWords: {}), isTrue,
            reason: '$slip is a slip of "base"');
      }
    });

    test(
        'comma-joined entry "ihn, in" splits to ["ihn","in"] — both real words',
        () {
      final validWords = {'ihn', 'in'};
      final errors = parseErrors(['ihn, in']).map(normWord).where(
            (e) => !validWords.contains(e.toLowerCase()),
          );
      expect(errors, isEmpty,
          reason:
              'Both tokens are real words; neither should survive the filter');
    });
  });
}
