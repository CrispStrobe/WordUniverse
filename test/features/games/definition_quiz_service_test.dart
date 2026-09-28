// test/features/games/definition_quiz_service_test.dart
//
// Which sense the Definition Quiz asks about, and how it is redacted. The quiz
// is shared with the SRI review game (sri_review_service.dart), so these rules
// cover both.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/definition_quiz_service.dart';

ApiEnrichment _enrichment(List<String> definitions,
        {List<String> synonyms = const []}) =>
    ApiEnrichment(
      enrichmentStatus: 'ok',
      definitions: definitions,
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

GermanWord _word(String word, List<String> definitions,
        {List<String> synonyms = const []}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: GermanWordType.substantiv,
      gradeLevel: 3,
      lemma: word,
      sources: const [],
      isGrundwortschatzBW: false,
      nurImPlural: false,
      graphematicVariants: const [],
      categories: const [],
      exampleSentences: const [],
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: false,
      apiEnrichment: _enrichment(definitions, synonyms: synonyms),
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

DefinitionChallenge? _build(GermanWord target, List<GermanWord> others) =>
    buildDefinitionChallenge(
      word: target,
      pool: [target, ...others],
      isGerman: false,
      rng: Random(7),
    );

List<GermanWord> _distractors() => [
      _word('table', const ['A piece of furniture.']),
      _word('river', const ['A large natural stream of water.']),
      _word('candle', const ['A block of wax with a wick.']),
    ];

void main() {
  test('prefers a self-contained sense over one that points at the sense above',
      () {
    final word = _word('papaya', const [
      'The fruit of this tree.',
      'A tropical fruit with orange flesh and black seeds.',
    ]);
    final challenge = _build(word, _distractors());
    expect(challenge, isNotNull);
    expect(challenge!.definition,
        'A tropical fruit with orange flesh and black seeds.');
  });

  test('keeps an anaphoric sense when it is the only usable one', () {
    final word = _word('papaya', const ['The fruit of this tree.']);
    final challenge = _build(word, _distractors());
    expect(challenge, isNotNull);
    expect(challenge!.definition, 'The fruit of this tree.');
  });

  test('redacts the headword rather than skipping to an obscure sense', () {
    final word = _word('organ', const [
      'An organ is a part of a body.',
      'A keyboard instrument.',
    ]);
    final challenge = _build(word, _distractors());
    expect(challenge, isNotNull);
    // The headword-free sense wins here; either way the answer is never given.
    expect(challenge!.definition.toLowerCase(), isNot(contains('organ')));
  });

  test('redaction uses word boundaries', () {
    final word = _word('organ', const ['The larger part of an organism.']);
    final challenge = _build(word, _distractors());
    expect(challenge!.definition, 'The larger part of an organism.');
  });

  test('a long primary sense is cut at its clause, not skipped', () {
    // "enable" shipped with a 130-character first sense; skipping it keyed
    // the archaic second one, "To affirm; to make firm and strong".
    final word = _word('enable', const [
      // Verbatim from the English pack, 135 characters.
      'To make somebody able (to do, or to be, something); to give sufficient '
          'ability or power to do or to be; to give strength or ability to.',
      'To affirm; to make firm and strong.',
    ]);
    final challenge = _build(word, _distractors());
    expect(challenge!.definition,
        'To make somebody able (to do, or to be, something)');
  });

  test('a synonym of the answer is never offered as an option', () {
    // The prompt is a meaning and the options are words, so a synonym answers
    // it too — offering both marks a child wrong for knowing that. Only an
    // exact label match was rejected before.
    final word = _word('sofa', const ['A long upholstered seat for sitting.'],
        synonyms: ['couch', 'settee']);
    final pool = [
      _word('couch', const ['A long upholstered seat.']),
      _word('settee', const ['A seat for two or more people.']),
      _word('river', const ['A large natural stream of water.']),
      _word('candle', const ['A block of wax with a wick.']),
      _word('table', const ['A piece of furniture.']),
    ];
    final challenge = _build(word, pool);
    expect(challenge, isNotNull);
    final offered = challenge!.options.map((o) => o.toLowerCase()).toList();
    expect(offered, contains('sofa'));
    expect(offered, isNot(contains('couch')));
    expect(offered, isNot(contains('settee')));
  });

  test('a word that is not a synonym is still offered', () {
    // Without this the test above would pass on a service that rejected every
    // option there is.
    final word = _word('sofa', const ['A long upholstered seat for sitting.'],
        synonyms: ['couch']);
    final challenge = _build(word, [
      _word('couch', const ['A long upholstered seat.']),
      ..._distractors(),
    ]);
    expect(challenge, isNotNull);
    expect(challenge!.options.map((o) => o.toLowerCase()), contains('river'));
  });

  test('refersToAnotherSense spots demonstratives in both languages', () {
    expect(refersToAnotherSense('One who does this.'), isTrue);
    expect(refersToAnotherSense('Eine Person, die solches tut.'), isTrue);
    expect(refersToAnotherSense('Diese Pflanze.'), isTrue);
    expect(refersToAnotherSense('A large natural stream of water.'), isFalse);
    expect(refersToAnotherSense('Ein Gebäude zum Wohnen.'), isFalse);
  });
}
