@TestOn('vm')
library;

// The packs attach a lemma's senses to its inflected forms, and sometimes to
// the wrong word outright. Anything a learner sees has to come from
// displayDefinitions, which withholds senses that describe a different word.

import 'package:flutter_test/flutter_test.dart';

import 'package:WortUniversum/core/models/vocabulary_models.dart';

GermanWord word(String spelling, {String? lemma, List<String> definitions = const []}) =>
    GermanWord.fromJson({
      'id': spelling,
      'word': spelling,
      if (lemma != null) 'lemma': lemma,
      'wordType': 'noun',
      'gradeLevel': 1,
      'apiEnrichment': {'definitions': definitions},
    });

void main() {
  test('a headword shows its own definitions', () {
    final entry = word('dog', lemma: 'dog', definitions: ['a domestic animal']);
    expect(entry.isHeadword, isTrue);
    expect(entry.displayDefinitions, ['a domestic animal']);
  });

  test('an inflected form shows nothing', () {
    // "ideas" carries the definition of "idea": keying it to the plural is a
    // mismatch, and the plural would also take a singular article.
    final entry = word('ideas', lemma: 'idea', definitions: ['a thought']);
    expect(entry.isHeadword, isFalse);
    expect(entry.displayDefinitions, isEmpty);
    expect(entry.apiEnrichment!.definitions, isNotEmpty,
        reason: 'the data is still there; it is simply not shown');
  });

  test('a mis-attached entry shows nothing', () {
    // The English pack's entry for "come" carries the senses of "cum", and
    // several games render definitions.firstOrNull to children.
    final entry = word('come', lemma: 'cum', definitions: ['To ejaculate.']);
    expect(entry.displayDefinitions, isEmpty);
  });

  test('case alone does not make an entry foreign', () {
    expect(word('Haus', lemma: 'haus', definitions: ['a house']).displayDefinitions,
        ['a house']);
  });

  test('a word with no enrichment shows nothing', () {
    expect(word('bare', lemma: 'bare').displayDefinitions, isEmpty);
  });
}
