// test/features/games/conjugation_drill_service_test.dart
//
// Unit tests for conjugation_drill_service.dart pure helpers.
// Tests cover: extractPraesens, extractPraesensFromWiktionary,
// getPraesensForWord, isConjugatableVerb, pickDistractors,
// and realistic example challenges.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/services/conjugation_drill_service.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';

// ─── Helper ──────────────────────────────────────────────────────────────────

/// Minimal GermanWord factory for tests. Only fills fields relevant to
/// conjugation logic; everything else uses sane defaults.
GermanWord _verb(
  String word, {
  Map<String, dynamic>? inflectionData,
  List<Map<String, dynamic>> wiktionaryInflections = const [],
  bool isProperNoun = false,
  bool hasSpace = false,
}) {
  final w = hasSpace ? 'zwei Wörter' : word;
  return GermanWord(
    id: 'test_$w',
    word: w,
    wordType: GermanWordType.verb,
    gradeLevel: 1,
    lemma: w,
    sources: const [],
    isGrundwortschatzBW: false,
    nurImPlural: false,
    graphematicVariants: const [],
    categories: const [],
    exampleSentences: const [],
    spellingDifficulty: SpellingDifficulty.easy,
    isProperNoun: isProperNoun,
    inflectionData: inflectionData,
    examples: const [],
    hyphenation: const [],
    wiktionaryInflections: wiktionaryInflections,
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
}

/// Build a flat wiktionary-style inflection list with exact 'present' tags
/// in the canonical ich/du/er/sie/es order.
List<Map<String, dynamic>> _wikiInflections(List<String> presentForms) => [
      for (final f in presentForms)
        {'form_text': f, 'tags': 'present', 'sense_index': null, 'topics': null},
    ];

Map<String, dynamic> _praesensData(Map<String, String> forms) => {
      'conjugation': {
        'Präsens': forms,
      },
    };

void main() {
  // ─── extractPraesens ─────────────────────────────────────────────────────

  group('extractPraesens', () {
    test('returns null for null input', () {
      expect(extractPraesens(null), isNull);
    });

    test('returns null when conjugation key is absent', () {
      expect(extractPraesens({'declension': {}}), isNull);
    });

    test('returns null when Präsens key is absent', () {
      expect(extractPraesens({'conjugation': {'Präteritum': {}}}), isNull);
    });

    test('returns null for empty Präsens map', () {
      expect(extractPraesens(_praesensData({})), isNull);
    });

    test('returns null when all values are empty strings', () {
      expect(
        extractPraesens(_praesensData({'ich': '', 'du': ''})),
        isNull,
      );
    });

    test('returns only non-empty entries', () {
      final result = extractPraesens(_praesensData({
        'ich': 'laufe',
        'du': '',
        'er/sie/es': 'läuft',
      }));
      expect(result, {'ich': 'laufe', 'er/sie/es': 'läuft'});
    });

    test('returns full Präsens map for laufen', () {
      final result = extractPraesens(_praesensData({
        'ich': 'laufe',
        'du': 'läufst',
        'er/sie/es': 'läuft',
        'wir': 'laufen',
        'ihr': 'lauft',
        'sie': 'laufen',
      }));
      expect(result, isNotNull);
      expect(result!.length, 6);
      expect(result['du'], 'läufst');
      expect(result['er/sie/es'], 'läuft');
    });

    test('handles non-map value for conjugation gracefully', () {
      expect(extractPraesens({'conjugation': 'invalid'}), isNull);
    });

    test('handles non-map value for Präsens gracefully', () {
      expect(
        extractPraesens({'conjugation': {'Präsens': 'invalid'}}),
        isNull,
      );
    });
  });

  // ─── extractPraesensFromWiktionary ───────────────────────────────────────

  group('extractPraesensFromWiktionary', () {
    test('returns null for empty list', () {
      expect(extractPraesensFromWiktionary([]), isNull);
    });

    test('ignores entries without exact "present" tag', () {
      // infinitive and passive forms have additional tags
      final forms = [
        {'form_text': 'laufen', 'tags': 'present, active, infinitive'},
        {'form_text': 'gelaufen', 'tags': 'participle-2, perfect'},
      ];
      expect(extractPraesensFromWiktionary(forms), isNull);
    });

    test('maps first 3 exact-present forms to ich/du/er/sie/es', () {
      final result = extractPraesensFromWiktionary(
          _wikiInflections(['laufe', 'läufst', 'läuft']));
      expect(result, {
        'ich': 'laufe',
        'du': 'läufst',
        'er/sie/es': 'läuft',
      });
    });

    test('handles single present form (ich only)', () {
      final result = extractPraesensFromWiktionary(
          _wikiInflections(['bin']));
      expect(result, {'ich': 'bin'});
    });

    test('trims whitespace from form_text', () {
      final forms = [{'form_text': '  laufe  ', 'tags': 'present'}];
      final result = extractPraesensFromWiktionary(forms);
      expect(result!['ich'], 'laufe');
    });

    test('skips empty form_text entries', () {
      final forms = [
        {'form_text': '', 'tags': 'present'},
        {'form_text': 'läufst', 'tags': 'present'},
      ];
      final result = extractPraesensFromWiktionary(forms);
      expect(result!['ich'], 'läufst');
    });

    test('realistic: laufen → ich/du/er from Wiktionary data', () {
      final result = extractPraesensFromWiktionary(
          _wikiInflections(['laufe', 'läufst', 'läuft']));
      expect(result!['ich'], 'laufe');
      expect(result['du'], 'läufst');
      expect(result['er/sie/es'], 'läuft');
    });

    test('realistic: haben (irregular) → ich/du/er', () {
      final result = extractPraesensFromWiktionary(
          _wikiInflections(['habe', 'hast', 'hat']));
      expect(result!['er/sie/es'], 'hat');
    });

    test('realistic: sein (highly irregular)', () {
      final result = extractPraesensFromWiktionary(
          _wikiInflections(['bin', 'bist', 'ist']));
      expect(result!['ich'], 'bin');
      expect(result['du'], 'bist');
      expect(result['er/sie/es'], 'ist');
    });
  });

  // ─── getPraesensForWord ───────────────────────────────────────────────────

  group('getPraesensForWord', () {
    test('returns null when both sources are empty', () {
      expect(getPraesensForWord(_verb('laufen')), isNull);
    });

    test('structured inflectionData wins over wiktionaryInflections', () {
      final w = _verb('laufen',
          inflectionData: _praesensData({
            'ich': 'structured-form',
            'du': 'structured-du',
          }),
          wiktionaryInflections: _wikiInflections(['wiki-ich', 'wiki-du', 'wiki-er']));
      final result = getPraesensForWord(w)!;
      expect(result['ich'], 'structured-form');
    });

    test('falls back to wiktionaryInflections when inflectionData is null', () {
      final w = _verb('laufen',
          wiktionaryInflections: _wikiInflections(['laufe', 'läufst', 'läuft']));
      final result = getPraesensForWord(w)!;
      expect(result['er/sie/es'], 'läuft');
    });

    test('falls back to wiktionaryInflections when inflectionData has no valid Präsens', () {
      final w = _verb('laufen',
          inflectionData: {'conjugation': {'Präteritum': {'ich': 'lief'}}},
          wiktionaryInflections: _wikiInflections(['laufe', 'läufst', 'läuft']));
      final result = getPraesensForWord(w)!;
      expect(result['ich'], 'laufe');
    });
  });

  // ─── isConjugatableVerb ───────────────────────────────────────────────────

  group('isConjugatableVerb', () {
    final goodData = _praesensData({'ich': 'laufe', 'du': 'läufst'});

    test('returns true for verb with valid Präsens data', () {
      expect(isConjugatableVerb(_verb('laufen', inflectionData: goodData)),
          isTrue);
    });

    test('returns false when both inflectionData and wiktionaryInflections are absent', () {
      expect(isConjugatableVerb(_verb('laufen')), isFalse);
    });

    test('returns true when inflectionData is null but wiktionaryInflections has present forms', () {
      final w = _verb('laufen',
          wiktionaryInflections: _wikiInflections(['laufe', 'läufst', 'läuft']));
      expect(isConjugatableVerb(w), isTrue);
    });

    test('returns false for proper noun even with verb wordType', () {
      expect(
        isConjugatableVerb(
            _verb('Google', inflectionData: goodData, isProperNoun: true)),
        isFalse,
      );
    });

    test('returns false when word contains a space', () {
      expect(
        isConjugatableVerb(
            _verb('', inflectionData: goodData, hasSpace: true)),
        isFalse,
      );
    });

    test('returns false for non-verb with conjugation data', () {
      final noun = GermanWord(
        id: 'test_haus',
        word: 'Haus',
        wordType: GermanWordType.substantiv,
        gradeLevel: 1,
        lemma: 'Haus',
        sources: const [],
        isGrundwortschatzBW: false,
        nurImPlural: false,
        graphematicVariants: const [],
        categories: const [],
        exampleSentences: const [],
        spellingDifficulty: SpellingDifficulty.easy,
        isProperNoun: false,
        inflectionData: goodData,
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
      expect(isConjugatableVerb(noun), isFalse);
    });
  });

  // ─── pickDistractors ──────────────────────────────────────────────────────

  group('pickDistractors', () {
    const correct = 'läuft';
    const infinitive = 'laufen';
    final pool = ['geht', 'kommt', 'sieht', 'rennt', 'fährt', 'tanzt'];

    test('returns up to count distinct distractors', () {
      final d = pickDistractors('er/sie/es', correct, infinitive, pool);
      expect(d.length, 3);
    });

    test('does not include the correct form', () {
      final d = pickDistractors('er/sie/es', correct, infinitive, pool);
      expect(d, isNot(contains(correct)));
    });

    test('does not include the verb infinitive', () {
      final poolWithInfinitive = ['laufen', 'geht', 'kommt', 'sieht'];
      final d = pickDistractors('er/sie/es', correct, infinitive,
          poolWithInfinitive);
      expect(d, isNot(contains(infinitive)));
    });

    test('returns fewer items when pool is small', () {
      final d = pickDistractors('er/sie/es', correct, infinitive,
          ['geht', 'kommt']);
      expect(d.length, 2);
    });

    test('returns empty list for empty pool', () {
      final d = pickDistractors('er/sie/es', correct, infinitive, []);
      expect(d, isEmpty);
    });

    test('deduplicates pool entries', () {
      final d = pickDistractors(
          'er/sie/es', correct, infinitive, ['geht', 'geht', 'geht', 'kommt']);
      expect(d, ['geht', 'kommt']);
    });
  });

  // ─── Realistic challenge examples ────────────────────────────────────────

  group('Realistic challenge pipeline', () {
    final laufen = _verb(
      'laufen',
      inflectionData: _praesensData({
        'ich': 'laufe',
        'du': 'läufst',
        'er/sie/es': 'läuft',
        'wir': 'laufen',
        'ihr': 'lauft',
        'sie': 'laufen',
      }),
    );
    final gehen = _verb(
      'gehen',
      inflectionData: _praesensData({
        'ich': 'gehe',
        'du': 'gehst',
        'er/sie/es': 'geht',
        'wir': 'gehen',
        'ihr': 'geht',
        'sie': 'gehen',
      }),
    );
    final sehen = _verb(
      'sehen',
      inflectionData: _praesensData({
        'ich': 'sehe',
        'du': 'siehst',
        'er/sie/es': 'sieht',
        'wir': 'sehen',
        'ihr': 'seht',
        'sie': 'sehen',
      }),
    );

    test('laufen er/sie/es → läuft', () {
      final pres = extractPraesens(laufen.inflectionData)!;
      expect(pres['er/sie/es'], 'läuft');
    });

    test('gehen du → gehst', () {
      final pres = extractPraesens(gehen.inflectionData)!;
      expect(pres['du'], 'gehst');
    });

    test('sehen ihr → seht', () {
      final pres = extractPraesens(sehen.inflectionData)!;
      expect(pres['ihr'], 'seht');
    });

    test('distractors for laufen er/sie/es exclude läuft and laufen', () {
      final pool = ['geht', 'sieht', 'rennt'];
      final d = pickDistractors('er/sie/es', 'läuft', 'laufen', pool);
      expect(d, isNot(contains('läuft')));
      expect(d, isNot(contains('laufen')));
      expect(d.length, 3);
    });

    test('all three verbs are conjugatable', () {
      for (final v in [laufen, gehen, sehen]) {
        expect(isConjugatableVerb(v), isTrue,
            reason: '${v.word} should be conjugatable');
      }
    });

    test('extractPraesens returns 6-form map for regular verb', () {
      final pres = extractPraesens(gehen.inflectionData)!;
      expect(pres.keys,
          containsAll(['ich', 'du', 'er/sie/es', 'wir', 'ihr', 'sie']));
    });

    test('verb with only partial Präsens data is still usable', () {
      final partial = _verb(
        'tun',
        inflectionData: _praesensData({'ich': 'tue', 'er/sie/es': 'tut'}),
      );
      expect(isConjugatableVerb(partial), isTrue);
      final pres = extractPraesens(partial.inflectionData)!;
      expect(pres.length, 2);
    });
  });
}
