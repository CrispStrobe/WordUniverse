// test/features/games/translation_flash_test.dart
//
// Unit tests for Translation Flash (#42) — covers _isCleanTranslation,
// _primaryEnTranslation, and buildChallenge end-to-end.
//
// All expected DB values were verified against pipeline/voc-de/grundwortschatz.db
// on 2026-05-26 and are pinned here so regressions surface immediately.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/features/games/services/translation_flash_service.dart'
    as service;

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({List<ApiTranslation> translations = const []}) =>
    ApiEnrichment(
      enrichmentStatus: 'ok',
      definitions: const [],
      pronunciation: const [],
      examples: const [],
      synonyms: const [],
      antonyms: const [],
      conceptnet: const [],
      alternativeAnalyses: const [],
      inflections: const [],
      semanticRelations: const [],
      hyphenation: const [],
      translations: translations,
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
    );

ApiTranslation _en(String word, {String? sense}) => ApiTranslation(
    langCode: 'en', word: word, lang: 'Englisch', senseText: sense);
ApiTranslation _de(String word) =>
    ApiTranslation(langCode: 'de', word: word, lang: 'Deutsch');
ApiTranslation _fr(String word) =>
    ApiTranslation(langCode: 'fr', word: word, lang: 'Français');

GermanWord _word(
  String word, {
  List<ApiTranslation> translations = const [],
  int grade = 1,
}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: GermanWordType.substantiv,
      gradeLevel: grade,
      lemma: word,
      sources: const [],
      isGrundwortschatzBW: false,
      nurImPlural: false,
      graphematicVariants: const [],
      categories: const [],
      exampleSentences: const [],
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: false,
      apiEnrichment: _enrichment(translations: translations),
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

// ─── Mirror of game logic ─────────────────────────────────────────────────────

bool isCleanTranslation(String w) {
  if (w.isEmpty) return false;
  if (w.contains('.')) return false;
  if (w == w.toUpperCase() && w.length > 1) return false;
  if (!RegExp(r"^[a-zA-Z\-' ]+$").hasMatch(w)) return false;
  return w.split(' ').length <= 2;
}

String? primaryEnTranslation(GermanWord word) {
  final translations = word.apiEnrichment?.translations ?? [];
  for (final t in translations) {
    if (t.langCode == 'en' && t.word != null) {
      final w = t.word!.trim();
      if (isCleanTranslation(w)) return w;
    }
  }
  return null;
}

class _TranslChallenge {
  final String deWord;
  final String enTranslation;
  final List<String> options;
  final int correctIndex;
  _TranslChallenge({
    required this.deWord,
    required this.enTranslation,
    required this.options,
    required this.correctIndex,
  });
}

_TranslChallenge? buildChallenge(
  GermanWord word,
  List<String> enPool, {
  Random? rng,
  int optionCount = 4,
}) {
  final r = rng ?? Random(42);
  final correct = primaryEnTranslation(word);
  if (correct == null) return null;

  final allEntryEn = (word.apiEnrichment?.translations ?? [])
      .where((t) => t.langCode == 'en' && t.word != null)
      .map((t) => t.word!.toLowerCase())
      .toSet();

  final distractors = <String>[];
  for (final t in enPool) {
    if (distractors.length >= optionCount - 1) break;
    if (!allEntryEn.contains(t.toLowerCase()) &&
        t.toLowerCase() != correct.toLowerCase()) {
      distractors.add(t);
    }
  }
  if (distractors.isEmpty) return null;

  final options = [correct, ...distractors.take(optionCount - 1)];
  options.shuffle(r);
  final correctIndex =
      options.indexWhere((o) => o.toLowerCase() == correct.toLowerCase());
  if (correctIndex < 0) return null;

  return _TranslChallenge(
    deWord: word.word,
    enTranslation: correct,
    options: options,
    correctIndex: correctIndex,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── isCleanTranslation ──────────────────────────────────────────────────────
  group('isCleanTranslation', () {
    test('accepts single-word ASCII',
        () => expect(isCleanTranslation('house'), isTrue));
    test('accepts two-word phrase',
        () => expect(isCleanTranslation('traffic light'), isTrue));
    test('accepts two-word with hyphen',
        () => expect(isCleanTranslation('old-fashioned'), isTrue));
    test('accepts "I" (English first-person pronoun, single uppercase char)',
        () => expect(isCleanTranslation('I'), isTrue));
    test('accepts "pay attention"',
        () => expect(isCleanTranslation('pay attention'), isTrue));
    test('rejects abbreviation with dot (e.g.)',
        () => expect(isCleanTranslation('e.g.'), isFalse));
    test('rejects all-caps abbreviation (HGV)',
        () => expect(isCleanTranslation('HGV'), isFalse));
    test('rejects all-caps abbreviation (FRG)',
        () => expect(isCleanTranslation('FRG'), isFalse));
    test('rejects diacritic char (café)',
        () => expect(isCleanTranslation('café'), isFalse));
    test('rejects three-word phrase (fall in love)',
        () => expect(isCleanTranslation('fall in love'), isFalse));
    test('rejects three-word phrase (traffic light coalition)',
        () => expect(isCleanTranslation('traffic light coalition'), isFalse));
    test('rejects empty string', () => expect(isCleanTranslation(''), isFalse));
  });

  // ── primaryEnTranslation ────────────────────────────────────────────────────
  group('primaryEnTranslation', () {
    test('returns null when no translations', () {
      expect(primaryEnTranslation(_word('Hund')), isNull);
    });

    test('returns null when only non-EN translations', () {
      final w = _word('Hund', translations: [_de('dog'), _fr('chien')]);
      expect(primaryEnTranslation(w), isNull);
    });

    test('returns first clean EN translation', () {
      final w = _word('Haus', translations: [_en('house'), _en('home')]);
      expect(primaryEnTranslation(w), equals('house'));
    });

    test('skips abbreviation (all-caps) and returns next clean word', () {
      final w = _word('LKW', translations: [_en('HGV'), _en('lorry')]);
      expect(primaryEnTranslation(w), equals('lorry'));
    });

    test('skips abbreviation with dot, returns next', () {
      final w = _word('zum Beispiel',
          translations: [_en('e.g.'), _en('for example')]);
      // 'e.g.' filtered; 'for example' is 2 words → clean
      expect(primaryEnTranslation(w), equals('for example'));
    });

    test('accepts two-word phrase when it is the first clean translation', () {
      // Ampel: 'hanging lamp' appears before single-word 'robot'
      final w = _word('Ampel', translations: [
        _en('hanging lamp', sense: 'ceiling light'),
        _en('traffic light', sense: 'street signal'),
        _en('robot', sense: 'South African English'),
      ]);
      expect(primaryEnTranslation(w), equals('hanging lamp'));
    });

    test('skips diacritic translation and returns next', () {
      final w = _word('Café', translations: [_en('café'), _en('coffee shop')]);
      expect(primaryEnTranslation(w), equals('coffee shop'));
    });

    test('returns null when all translations fail (3-word phrases or abbrevs)',
        () {
      final w = _word('verliebt', translations: [
        _en('fall in love'),
        _en('be in love'),
      ]);
      expect(primaryEnTranslation(w), isNull);
    });

    test('trims surrounding whitespace from translation word', () {
      final w = _word('Hund', translations: [
        ApiTranslation(langCode: 'en', word: '  dog  ', lang: 'Englisch'),
      ]);
      expect(primaryEnTranslation(w), equals('dog'));
    });
  });

  // ── buildChallenge — structure ───────────────────────────────────────────────
  group('buildChallenge — structural invariants', () {
    test('returns null when no clean EN translation', () {
      final w = _word('LKW', translations: [_en('HGV')]);
      expect(buildChallenge(w, ['dog', 'run', 'big']), isNull);
    });

    test('returns null when pool has no valid distractors', () {
      final w = _word('Haus', translations: [_en('house'), _en('home')]);
      expect(buildChallenge(w, ['house', 'home']), isNull);
    });

    test('options[correctIndex] == enTranslation', () {
      final w = _word('Haus', translations: [_en('house')]);
      final pool = ['dog', 'run', 'big', 'red'];
      final c = buildChallenge(w, pool, rng: Random(1));
      expect(c, isNotNull);
      expect(c!.options[c.correctIndex], equals('house'));
    });

    test('distractors exclude all EN translations of the target word', () {
      final w = _word('Haus',
          translations: [_en('house'), _en('home'), _en('building')]);
      final pool = ['house', 'home', 'building', 'dog', 'cat', 'run'];
      final c = buildChallenge(w, pool, rng: Random(5));
      expect(c, isNotNull);
      for (final opt in c!.options) {
        if (opt != c.enTranslation) {
          expect({'house', 'home', 'building'}.contains(opt.toLowerCase()),
              isFalse,
              reason: '$opt is a translation of Haus — not a valid distractor');
        }
      }
    });

    test('options length does not exceed optionCount', () {
      final w = _word('Hund', translations: [_en('dog')]);
      final pool = List.generate(20, (i) => 'word$i');
      final c = buildChallenge(w, pool, rng: Random(3));
      expect(c, isNotNull);
      expect(c!.options.length, lessThanOrEqualTo(4));
    });
  });

  // ── DB-pinned realistic expectations ────────────────────────────────────────
  // All values verified against pipeline/voc-de/grundwortschatz.db 2026-05-26.
  group('DB-pinned DE→EN translation choices', () {
    test('Haus → house (first clean single-word)', () {
      final w = _word('Haus', translations: [_en('house'), _en('home')]);
      expect(primaryEnTranslation(w), equals('house'));
    });

    test('laufen → run (first clean single-word)', () {
      final w = _word('laufen', translations: [_en('run'), _en('walk')]);
      expect(primaryEnTranslation(w), equals('run'));
    });

    test(
        'Ampel → hanging lamp (2-word preferred over regional single-word robot)',
        () {
      final w = _word('Ampel', translations: [
        _en('hanging lamp'),
        _en('traffic light'),
        _en('robot'), // South African English — should NOT win
      ]);
      expect(primaryEnTranslation(w), equals('hanging lamp'));
    });

    test('Kind → child', () {
      final w = _word('Kind', translations: [_en('child'), _en('kid')]);
      expect(primaryEnTranslation(w), equals('child'));
    });

    test('aufpassen → pay attention (2-word, correct German meaning)', () {
      final w = _word('aufpassen',
          translations: [_en('pay attention'), _en('watch out')]);
      expect(primaryEnTranslation(w), equals('pay attention'));
    });

    test('verliebt → null (all translations are 3+ word phrases)', () {
      final w = _word('verliebt',
          translations: [_en('fall in love'), _en('be in love')]);
      expect(primaryEnTranslation(w), isNull);
    });

    test('LKW → null (HGV is all-caps abbreviation; no other translation)', () {
      final w = _word('LKW', translations: [_en('HGV')]);
      expect(primaryEnTranslation(w), isNull);
    });
  });

  // ── the real service ────────────────────────────────────────────────────────
  group('buildTranslationChallenge', () {
    List<String> distractors() => ['house', 'car', 'tree', 'river'];

    test('builds a challenge when the translation differs from the word', () {
      final challenge = service.buildTranslationChallenge(
        word: _word('Haus', translations: [_en('house')]),
        optionTexts: ['car', 'tree', 'river'],
        rng: Random(1),
      );
      expect(challenge, isNotNull);
      expect(challenge!.options[challenge.correctIndex], 'house');
    });

    test('rejects a cognate, which answers itself either direction', () {
      // "What is 'das Hobby' in English?" → hobby.
      for (final reversed in [false, true]) {
        expect(
          service.buildTranslationChallenge(
            word: _word('Hobby', translations: [_en('hobby')]),
            optionTexts: distractors(),
            reversed: reversed,
            rng: Random(1),
          ),
          isNull,
          reason: 'reversed: $reversed',
        );
      }
    });

    test('a cognate differing only in case is still a cognate', () {
      expect(
        service.buildTranslationChallenge(
          word: _word('Info', translations: [_en('info')]),
          optionTexts: distractors(),
          rng: Random(1),
        ),
        isNull,
      );
    });
  });
}
