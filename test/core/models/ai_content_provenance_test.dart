import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';

GermanWord _word(Map<String, dynamic> metadata) => GermanWord.fromJson({
      'id': 'example',
      'word': 'cat',
      'wordType': 'noun',
      'sources': ['dictionary'],
      'gradeLevel': 1,
      ...metadata,
    });

void main() {
  test('new field provenance survives persistence and curriculum copies', () {
    const provenance = {
      'schema': 'word_universe.ai_content.v1',
      'fields': {
        'metadata.grade_examples': {
          'origin': 'ai_generated',
          'details_status': 'recorded',
          'generation': {
            'provider_host': 'provider.example',
            'requested_model': 'requested',
            'response_model': 'served',
            'received_at': '2026-01-01T00:00:00+00:00',
          },
        },
      },
    };
    final original = _word({'ai_content': provenance});
    final copied = original.withCurriculumSources(
        sources: ['dictionary', 'BW1'], isGrundwortschatzBW: true, features: 0);
    for (final word in [
      original,
      copied,
      GermanWord.fromJson(copied.toJson())
    ]) {
      expect(word.aiContent, provenance);
      expect(word.hasAiContentEvidence, isTrue);
      expect(word.sources, contains('dictionary'));
    }
  });

  test('legacy and unrecorded items never acquire invented providers', () {
    final unknown = _word({});
    expect(unknown.hasAiContentEvidence, isFalse);
    expect(unknown.aiContent, isEmpty);
    for (final metadata in [
      {
        'sources': ['dictionary', 'LLM_GENERATED']
      },
      {'gloss_source': 'llm-reviewed'},
      {'gloss_source': 'llm-sense'},
    ]) {
      final old = _word(metadata);
      final restored = GermanWord.fromJson(old.toJson());
      expect(old.hasAiContentEvidence, isTrue);
      expect(restored.hasAiContentEvidence, isTrue);
      expect(restored.aiContent, isEmpty);
    }
  });

  test('pack flags describe known packs without attributing every future pack',
      () {
    expect(languagePackFor('en')!.containsAiAssistedContent, isTrue);
    expect(languagePackFor('de')!.containsAiAssistedContent, isTrue);
    const future = LanguagePack(
        code: 'xx',
        nativeName: 'Example',
        databaseName: 'example.db',
        licenseLabel: 'Example license');
    expect(future.containsAiAssistedContent, isFalse);
  });
}
