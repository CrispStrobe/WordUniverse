// test/core/models/shown_synonyms_test.dart
//
// The synonyms a child sees beside a word (Word of the Day, Word Sort
// hints): what the three-judge review accepted first, then the pack's list,
// which it ranks by sense, without what the review turned down.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';

import '../../features/games/word_fixture.dart';

void main() {
  test('accepted first, then the list without what the judges turned down',
      () {
    final word = testWord('Auto',
        enrichment: testEnrichment(
            synonyms: ['Kiste', 'PKW', 'Fahrzeug', 'Wagen', 'Automobil']),
        reviewedSynonyms: ['Wagen'],
        rejectedSynonyms: ['Kiste', 'fahrzeug']);
    expect(word.shownSynonyms, ['Wagen', 'PKW', 'Automobil']);
  });

  test('an empty review still leaves the terms it was not shown', () {
    // The judges only see candidates that are pack words; "Wauwau" is not.
    final word = testWord('Hund',
        enrichment: testEnrichment(synonyms: ['Köter', 'Wauwau']),
        reviewedSynonyms: const [],
        rejectedSynonyms: ['Köter']);
    expect(word.shownSynonyms, ['Wauwau']);
  });

  test('unreviewed: the list as the pack ranks it', () {
    final word = testWord('leise',
        type: GermanWordType.adjektiv,
        enrichment: testEnrichment(antonyms: ['laut']));
    expect(word.shownAntonyms, ['laut']);
  });
}
