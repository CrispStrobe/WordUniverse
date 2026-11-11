import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/vocabulary_quality.dart';
import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/bw_vocabulary_overlay.dart';

const _packHash =
    '1df66b74d7074ce82d866acc7a5684db1647d9d1d1e45a3d5c5cb363a2d4af63';

void main() {
  late BwVocabularyOverlay overlay;
  setUp(() {
    overlay = BwVocabularyOverlay.fromJson(
      jsonDecode(File(BwVocabularyOverlay.membershipAsset).readAsStringSync()),
      jsonDecode(File(BwVocabularyOverlay.lexicalAsset).readAsStringSync()),
    );
  });

  GermanWord word(
    String written, {
    String? id,
    String type = 'noun',
    List<String> sources = const ['BW1', 'BW3', 'BERLIN'],
    String definition = 'Eine bereits vorhandene Bedeutung.',
    bool light = true,
  }) =>
      GermanWord.fromJson({
        'id': id ?? 'existing_$written',
        'rowId': 17,
        'word': written,
        'lemma': written,
        'wordType': type,
        'gradeLevel': 3,
        'sources': sources,
        'features': WordFeature.definitions.mask |
            WordFeature.headword.mask |
            WordFeature.curriculum.mask |
            WordFeature.nameLike.mask,
        'isHydrated': !light,
        if (!light)
          'apiEnrichment': {
            'primary_lemma': written,
            'definitions': [definition],
            'synonyms': ['vorhanden'],
          },
      });

  test('authoritative bands replace old tags and preserve exact case', () {
    final catalogue = overlay.applyCatalogue([
      for (final name in [
        'Arm',
        'Paar',
        'Weg',
        'Essen',
        'Leben',
        'Morgen',
        'Nächste',
        'Vertrauen'
      ])
        word(name),
      word('Sie', type: 'pronoun'),
      word('sein', type: 'verb'),
    ], packSha256: _packHash);
    GermanWord at(String written, [GermanWordType? type]) =>
        catalogue.singleWhere((word) =>
            word.word == written && (type == null || word.wordType == type));
    List<String> bw(GermanWord word) =>
        word.sources.where((s) => s == 'BW1' || s == 'BW3').toList();
    expect(overlay.membershipCount, 857);
    expect(bw(at('Arm')), ['BW1']);
    expect(bw(at('arm')), ['BW1']);
    expect(at('Arm').wordType, GermanWordType.substantiv);
    expect(at('arm').wordType, GermanWordType.adjektiv);
    expect(at('Paar').id, isNot(at('paar').id));
    expect(bw(at('Weg')), ['BW1']);
    expect(bw(at('weg')), ['BW3']);
    expect(bw(at('Sie')), isEmpty);
    expect(bw(at('sie')), ['BW1']);
    for (final name in ['Essen', 'Leben', 'Morgen', 'Nächste', 'Vertrauen']) {
      expect(bw(at(name)), isEmpty,
          reason: 'the source lists the lowercase sense');
      expect(at(name).sources, contains('BERLIN'));
      expect(at(name).has(WordFeature.curriculum), isTrue);
    }
    expect(bw(at('sein', GermanWordType.verb)), ['BW1']);
    expect(bw(at('sein', GermanWordType.pronomen)), ['BW3']);
  });

  test('six exact pinned corrections agree before and after hydration', () {
    final originals = [
      word('August', id: 'word_00692', type: 'proper_noun'),
      word('Gabel', id: 'word_03407', type: 'proper_noun'),
      word('Herr', id: 'word_04368', type: 'proper_noun'),
      word('Luchs', id: 'word_05837'),
      word('Mandarine', id: 'word_05944'),
      word('Band', id: 'word_00876'),
    ];
    final catalogue = overlay.applyCatalogue(originals, packSha256: _packHash);
    for (final original in originals) {
      final light = catalogue.singleWhere((word) => word.id == original.id);
      expect(light.isHydrated, isFalse);
      expect(light.rowId, original.rowId);
      expect(light.wordType, GermanWordType.substantiv);
      expect(light.isProperNoun, isFalse);
      expect(namesSomething(light), isFalse);
      expect(light.has(WordFeature.definitions), isTrue);
      expect(light.has(WordFeature.gradeExamples), isTrue);
      final full = overlay.hydrateOrApply(light);
      expect(full.isHydrated, isTrue);
      expect(full.features, light.features);
      expect(full.sources, light.sources);
      expect(full.isHeadword, isTrue);
      expect(full.lemma, full.word);
      expect(isUsableDefinition(full.learnerDefinitions.single), isTrue);
      expect(namesSomething(full), isFalse);
      expect(full.sources, contains('BERLIN'));
    }
    final band = overlay.hydrateOrApply(
        catalogue.singleWhere((word) => word.id == 'word_00876'));
    expect(band.article, 'das');
    expect(band.learnerDefinitions.single, contains('Streifen'));
    // The supplied database objects themselves were never mutated.
    expect(originals.first.isProperNoun, isTrue);
    expect(originals.first.has(WordFeature.nameLike), isTrue);
  });

  test('unrelated name senses and another pack revision are not retyped', () {
    final name = word('August', id: 'another_name_sense', type: 'proper_noun');
    final pinnedId = word('August', id: 'word_00692', type: 'proper_noun');
    final result =
        overlay.applyCatalogue([name, pinnedId], packSha256: 'different-pack');
    for (final id in [name.id, pinnedId.id]) {
      final unchanged = result.singleWhere((word) => word.id == id);
      expect(unchanged.isProperNoun, isTrue);
      expect(unchanged.isGrundwortschatzBW, isFalse);
    }
  });

  test(
      'ordinary hydrated data survives membership changes without a lossy copy',
      () {
    final original = word('Arm',
        light: false, definition: 'Ein Körperteil zwischen Schulter und Hand.');
    final result =
        overlay.applyCatalogue([original], packSha256: _packHash).first;
    expect(result.isHydrated, isTrue);
    expect(result.rowId, original.rowId);
    expect(result.apiEnrichment, same(original.apiEnrichment));
    expect(result.apiEnrichment!.synonyms, ['vorhanden']);
    expect(result.displayDefinitions, original.displayDefinitions);
    expect(result.sources, ['BERLIN', 'BW1']);
    expect(result.isGrundwortschatzBW, isTrue);
  });

  test('supplements remain light in the catalogue and have honest feature bits',
      () {
    final catalogue = overlay.applyCatalogue([], packSha256: _packHash);
    expect(catalogue, hasLength(14));
    expect(catalogue.every((word) => !word.isHydrated), isTrue);
    for (final light in catalogue) {
      final full = overlay.hydrateOrApply(light);
      expect(full.isHydrated, isTrue);
      expect(full.has(WordFeature.definitions), isTrue);
      expect(full.has(WordFeature.curriculum), isTrue);
      expect(full.has(WordFeature.nameLike), isFalse);
      expect(isPresentableVocabularyEntry(full), isTrue);
      expect(isUsableDefinition(full.learnerDefinitions.single), isTrue);
      expect(full.spellingDifficultySource, 'unknown');
      expect(full.spellingDifficultyEvidence['status'], 'unknown');
      expect(full.litekeyErrorRate, isNull);
      expect(full.gradeLevelEstimate, isNull);
    }
    expect(catalogue.any((word) => word.word == 'E-Mail'), isTrue);
    expect(BwVocabularyOverlay.normalize('  na\u0308chste  '), 'nächste');
  });

  test('a future pack with an exact ordinary sense does not get a duplicate',
      () {
    final existing = word('arm', type: 'adjective', id: 'already_correct');
    final catalogue =
        overlay.applyCatalogue([existing], packSha256: 'future-pack');
    expect(catalogue.where((word) => word.word == 'arm'), hasLength(1));
    expect(catalogue.first.id, 'already_correct');
  });
}
