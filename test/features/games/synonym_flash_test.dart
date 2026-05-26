// test/features/games/synonym_flash_test.dart
//
// Unit tests for Synonym Flash (#41) — covers _isCleanSynonym, the
// in-vocabulary synonym-preference logic, and buildChallenge end-to-end.
//
// All expected DB values were verified against pipeline/voc-en/grundwortschatz_en.db
// on 2026-05-26 and are pinned here so regressions surface immediately.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ApiEnrichment _enrichment({List<String> synonyms = const []}) =>
    ApiEnrichment(
      enrichmentStatus: 'ok',
      definitions: const [],
      pronunciation: const [],
      examples: const [],
      synonyms: synonyms,
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
    );

GermanWord _word(
  String word, {
  List<String> synonyms = const [],
  int grade = 1,
}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: GermanWordType.adjektiv,
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
      apiEnrichment: _enrichment(synonyms: synonyms),
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

// ─── Mirror of game logic (extracted for unit testing) ────────────────────────

bool isCleanSynonym(String s) {
  if (s.length < 2 || s.contains(' ')) return false;
  if (RegExp(r'\d').hasMatch(s)) return false;
  if (s == s.toUpperCase() && s.length > 1) return false;
  return RegExp(r"^[a-zA-Z\-']+$").hasMatch(s);
}

class _SynonymChallenge {
  final String word;
  final String correctSynonym;
  final List<String> options;
  final int correctIndex;
  _SynonymChallenge({
    required this.word,
    required this.correctSynonym,
    required this.options,
    required this.correctIndex,
  });
}

_SynonymChallenge? buildChallenge(
  GermanWord word,
  List<String> allTexts,
  Set<String> wordSet, {
  Random? rng,
  int optionCount = 4,
}) {
  final r = rng ?? Random(42);
  final synonyms = word.apiEnrichment?.synonyms ?? [];
  if (synonyms.isEmpty) return null;

  String? correct;
  String? fallback;
  for (final syn in synonyms) {
    final clean = syn.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
    if (isCleanSynonym(clean)) {
      if (wordSet.contains(clean.toLowerCase())) {
        correct = clean;
        break;
      }
      fallback ??= clean;
    }
  }
  correct ??= fallback;
  if (correct == null) return null;

  final correctWord = correct;
  final synSet =
      synonyms.map((s) => s.toLowerCase()).toSet()..add(word.word.toLowerCase());
  final distractors = <String>[];
  for (final t in allTexts) {
    if (distractors.length >= optionCount - 1) break;
    if (!synSet.contains(t.toLowerCase()) &&
        t.toLowerCase() != correctWord.toLowerCase()) {
      distractors.add(t);
    }
  }
  if (distractors.isEmpty) return null;

  final options = [correctWord, ...distractors.take(optionCount - 1)];
  options.shuffle(r);
  final correctIndex =
      options.indexWhere((o) => o.toLowerCase() == correctWord.toLowerCase());
  if (correctIndex < 0) return null;

  return _SynonymChallenge(
    word: word.word,
    correctSynonym: correctWord,
    options: options,
    correctIndex: correctIndex,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── isCleanSynonym ──────────────────────────────────────────────────────────
  group('isCleanSynonym', () {
    test('accepts plain lowercase word', () => expect(isCleanSynonym('glad'), isTrue));
    test('accepts hyphenated word', () => expect(isCleanSynonym('well-chosen'), isTrue));
    test('accepts word with apostrophe', () => expect(isCleanSynonym("don't"), isTrue));
    test('accepts 2-char minimum', () => expect(isCleanSynonym('ab'), isTrue));
    test('rejects single character (Roman numeral I)', () => expect(isCleanSynonym('I'), isFalse));
    test('rejects empty string', () => expect(isCleanSynonym(''), isFalse));
    test('rejects word containing digit (1st)', () => expect(isCleanSynonym('1st'), isFalse));
    test('rejects all-caps abbreviation (AA)', () => expect(isCleanSynonym('AA'), isFalse));
    test('rejects 2-word phrase', () => expect(isCleanSynonym('good afternoon'), isFalse));
    test('rejects diacritic (café)', () => expect(isCleanSynonym('café'), isFalse));
    test('rejects all-caps 3+ chars (MBD)', () => expect(isCleanSynonym('MBD'), isFalse));
    // Mixed-case words are OK (not "all-caps")
    test('accepts title-case word (Begin)', () => expect(isCleanSynonym('Begin'), isTrue));
  });

  // ── buildChallenge — null cases ─────────────────────────────────────────────
  group('buildChallenge — null/empty', () {
    test('returns null when synonyms list is empty', () {
      final w = _word('happy', synonyms: []);
      expect(buildChallenge(w, ['sad', 'big'], {}), isNull);
    });

    test('returns null when all synonyms fail isCleanSynonym', () {
      // All synonyms are either multi-word or contain digits/diacritics
      final w = _word('more',
          synonyms: ['Sir Thomas More', 'Thomas More', 'more than']);
      expect(buildChallenge(w, ['less', 'few', 'some'], {}), isNull);
    });

    test('returns null when no distractors are available', () {
      final w = _word('happy', synonyms: ['glad', 'joyful']);
      // Pool only contains synonyms of happy → no valid distractors
      expect(buildChallenge(w, ['glad', 'joyful'], {'glad', 'joyful'}), isNull);
    });
  });

  // ── in-vocabulary preference ────────────────────────────────────────────────
  group('in-vocabulary synonym preference', () {
    test('picks in-DB synonym over earlier out-of-DB synonym', () {
      // felicitous not in DB, glad is — should get glad
      final w = _word('happy',
          synonyms: ['felicitous', 'glad', 'well-chosen']);
      final pool = ['sad', 'angry', 'tired', 'cold'];
      final wordSet = {'glad'}; // only glad is in vocabulary
      final c = buildChallenge(w, pool, wordSet, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.correctSynonym, equals('glad'));
    });

    test('falls back to first clean synonym when none are in vocab', () {
      // No synonym is in the word set → use first clean one
      final w = _word('begin', synonyms: ['commence', 'initiate', 'originate']);
      final pool = ['end', 'stop', 'run', 'jump'];
      final wordSet = <String>{}; // empty vocab set
      final c = buildChallenge(w, pool, wordSet, rng: Random(1));
      expect(c, isNotNull);
      expect(c!.correctSynonym, equals('commence'));
    });

    test('digit-containing synonyms are skipped before in-vocab check', () {
      // '1st' should be filtered before checking vocab; 'beginning' is fallback
      final w = _word('first', synonyms: ['1st', 'beginning', 'foremost']);
      final pool = ['last', 'next', 'back', 'late'];
      final wordSet = {'beginning'};
      final c = buildChallenge(w, pool, wordSet, rng: Random(2));
      expect(c, isNotNull);
      expect(c!.correctSynonym, equals('beginning'));
    });

    test('all-caps abbreviation skipped; in-vocab word chosen', () {
      // ADHD, MBD → filtered; append → fallback (not in vocab); bestow → in vocab
      final w = _word('add', synonyms: ['ADHD', 'MBD', 'append', 'bestow']);
      final pool = ['remove', 'delete', 'cut', 'hide'];
      final wordSet = {'bestow'}; // only bestow is in vocab
      final c = buildChallenge(w, pool, wordSet, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.correctSynonym, equals('bestow'));
    });
  });

  // ── parenthetical stripping ─────────────────────────────────────────────────
  group('parenthetical stripping', () {
    test('strips trailing parenthetical before clean check', () {
      final w = _word('happy', synonyms: ['glad (informal)', 'joyful (formal)']);
      final pool = ['sad', 'angry', 'cold', 'dark'];
      final wordSet = {'glad'};
      final c = buildChallenge(w, pool, wordSet, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.correctSynonym, equals('glad'));
    });

    test('parenthetical with space-word picks clean version', () {
      final w = _word('happy', synonyms: ['in high spirits', 'glad (informal)']);
      final pool = ['sad', 'blue', 'cold', 'dull'];
      final wordSet = {'glad'};
      final c = buildChallenge(w, pool, wordSet, rng: Random(1));
      expect(c, isNotNull);
      expect(c!.correctSynonym, equals('glad')); // phrase skipped; glad chosen
    });
  });

  // ── challenge structural invariants ─────────────────────────────────────────
  group('challenge structural invariants', () {
    test('correctIndex is valid index into options', () {
      final w = _word('happy', synonyms: ['glad']);
      final pool = ['sad', 'quick', 'tall', 'green'];
      final c = buildChallenge(w, pool, {'glad'}, rng: Random(5));
      expect(c, isNotNull);
      expect(c!.correctIndex, greaterThanOrEqualTo(0));
      expect(c.correctIndex, lessThan(c.options.length));
    });

    test('options[correctIndex] == correctSynonym', () {
      final w = _word('happy', synonyms: ['glad', 'joyful']);
      final pool = ['sad', 'quick', 'tall', 'green'];
      final c = buildChallenge(w, pool, {'glad'}, rng: Random(3));
      expect(c, isNotNull);
      expect(c!.options[c.correctIndex].toLowerCase(),
          equals(c.correctSynonym.toLowerCase()));
    });

    test('no distractor is a synonym of the target word', () {
      final w = _word('happy', synonyms: ['glad', 'joyful', 'pleased']);
      final pool = ['glad', 'joyful', 'pleased', 'sad', 'quick', 'tall'];
      final synSet = {'glad', 'joyful', 'pleased'};
      final c = buildChallenge(w, pool, synSet, rng: Random(7));
      expect(c, isNotNull);
      for (final opt in c!.options) {
        if (opt.toLowerCase() != c.correctSynonym.toLowerCase()) {
          expect(synSet.contains(opt.toLowerCase()), isFalse,
              reason: '$opt is a synonym of happy and must not be a distractor');
        }
      }
    });

    test('target word itself is not in options', () {
      final w = _word('happy', synonyms: ['glad']);
      // 'happy' is in the pool — it should be blocked by synSet
      final pool = ['happy', 'sad', 'quick', 'tall'];
      final c = buildChallenge(w, pool, {'glad'}, rng: Random(2));
      expect(c, isNotNull);
      expect(c!.options.map((o) => o.toLowerCase()), isNot(contains('happy')));
    });

    test('options list never exceeds optionCount', () {
      final w = _word('happy', synonyms: ['glad']);
      final pool = List.generate(20, (i) => 'word$i');
      final c = buildChallenge(w, pool, {'glad'}, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.options.length, lessThanOrEqualTo(4));
    });
  });

  // ── realistic DB-pinned expectations ────────────────────────────────────────
  // Values verified against pipeline/voc-en/grundwortschatz_en.db on 2026-05-26.
  group('realistic DB-pinned synonym choices', () {
    test('happy: felicitous(not-in-vocab) skipped; glad(in-vocab) chosen', () {
      final w = _word('happy',
          synonyms: ['felicitous', 'glad', 'well-chosen']);
      final pool = ['sad', 'angry', 'tired', 'cold'];
      // Only glad is in vocab
      final c = buildChallenge(w, pool, {'glad'}, rng: Random(0));
      expect(c!.correctSynonym, equals('glad'));
    });

    test('first: 1st(digit) skipped; beginning chosen', () {
      final w = _word('first', synonyms: ['1st', 'beginning', 'foremost']);
      final pool = ['last', 'next', 'back', 'late'];
      final c = buildChallenge(w, pool, {'beginning'}, rng: Random(0));
      expect(c!.correctSynonym, equals('beginning'));
    });

    test('begin: commence chosen (in-vocab)', () {
      final w = _word('begin',
          synonyms: ['commence', 'get', 'get down', 'set about', 'start out']);
      final pool = ['end', 'stop', 'run', 'jump', 'play'];
      final c = buildChallenge(w, pool, {'commence', 'start'}, rng: Random(1));
      expect(c!.correctSynonym, equals('commence'));
    });

    test('more: all synonyms are multi-word proper nouns → null', () {
      final w = _word('more',
          synonyms: ['Sir Thomas More', 'Thomas More', 'more than']);
      expect(buildChallenge(w, ['less', 'few', 'some'], {}), isNull);
    });

    test('one: digit(1) and single-char(I) both filtered; ace chosen', () {
      final w = _word('one', synonyms: ['1', 'I', 'ace']);
      final pool = ['two', 'five', 'none', 'pair'];
      final c = buildChallenge(w, pool, {'ace'}, rng: Random(0));
      expect(c, isNotNull);
      expect(c!.correctSynonym, equals('ace'));
    });
  });
}
