@TestOn('vm')
library;

import 'dart:convert';


import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:WortUniversum/core/models/word_features.dart';
import 'package:WortUniversum/core/services/db_platform/db_feature_index.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache.dart';

/// The shape the packs actually ship (see pipeline/): enrichment and metadata
/// as JSON text columns, keyed by an integer rowid.
Future<Database> packFixture(List<Map<String, Object?>> words) async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE words (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      original_id TEXT UNIQUE,
      word TEXT NOT NULL,
      lemma TEXT,
      article TEXT,
      genus TEXT,
      word_type TEXT,
      grade_level INTEGER,
      audio_path TEXT,
      frequency_json TEXT,
      enrichment_json TEXT,
      metadata_json TEXT
    )''');
  for (final word in words) {
    await db.insert('words', {
      'original_id': word['word'],
      'word': word['word'],
      'word_type': 'noun',
      'grade_level': 1,
      'enrichment_json': jsonEncode(word['enrichment'] ?? {}),
      'metadata_json': jsonEncode(word['metadata'] ?? {}),
    });
  }
  return db;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('feature bits', () {
    test('are read from the JSON without decoding it in Dart', () async {
      final db = await packFixture([
        {
          'word': 'Hund',
          'enrichment': {
            'definitions': ['a dog'],
            'synonyms': ['Köter'],
            'hyphenation': ['Hund'],
            'enrichment_status': 'success',
          },
          'metadata': {
            'commonLearnerErrors': ['Hunt'],
            'grade_examples': {'1': ['Der Hund bellt.']},
          },
        },
        {'word': 'Leer'},
      ]);
      addTearDown(db.close);

      final index = await WordFeatureIndex.build(db);

      expect(index.featuresOf(1).hasFeature(WordFeature.definitions), isTrue);
      expect(index.featuresOf(1).hasFeature(WordFeature.synonyms), isTrue);
      expect(index.featuresOf(1).hasFeature(WordFeature.hyphenation), isTrue);
      expect(index.featuresOf(1).hasFeature(WordFeature.learnerErrors), isTrue);
      expect(index.featuresOf(1).hasFeature(WordFeature.gradeExamples), isTrue);
      expect(
          index.featuresOf(1).hasFeature(WordFeature.enrichmentSuccess), isTrue);
      expect(index.featuresOf(1).hasFeature(WordFeature.antonyms), isFalse);
      // "Leer" carries no enrichment, but it is still its own headword —
      // nothing claims it was derived from another entry.
      expect(index.featuresOf(2), WordFeature.headword.mask);
    });

    test('learner errors count under either pack\'s key', () async {
      // EN fills commonLearnerErrors, DE fills commonMistakes.
      final db = await packFixture([
        {'word': 'accommodate', 'metadata': {'commonLearnerErrors': ['acommodate']}},
        {'word': 'Rhythmus', 'metadata': {'commonMistakes': ['Rytmus']}},
      ]);
      addTearDown(db.close);

      final index = await WordFeatureIndex.build(db);
      expect(index.featuresOf(1).hasFeature(WordFeature.learnerErrors), isTrue);
      expect(index.featuresOf(2).hasFeature(WordFeature.learnerErrors), isTrue);
    });
  });

  group('presentability', () {
    test('rejects source-tagged and definition-marked misspellings', () async {
      final db = await packFixture([
        {'word': 'clean', 'enrichment': {'definitions': ['tidy']}},
        {
          'word': 'accomodate',
          'metadata': {'sources': ['SOURCE:COMMON_MISSPELLED']},
        },
        {
          'word': 'didnt',
          'enrichment': {'definitions': ["Misspelling of didn't."]},
        },
        {
          'word': 'noted',
          'enrichment': {'entryNotes': ['Obsolete form of note.']},
        },
      ]);
      addTearDown(db.close);

      final index = await WordFeatureIndex.build(db);
      expect(index.isPresentable(1), isTrue);
      expect(index.isPresentable(2), isFalse, reason: 'tagged as a misspelling');
      expect(index.isPresentable(3), isFalse, reason: 'defined as a misspelling');
      expect(index.isPresentable(4), isFalse, reason: 'noted as obsolete');
    });

    test('a headword recorded as another entry\'s learner error is flagged',
        () async {
      final db = await packFixture([
        {'word': 'didnt'},
        {
          'word': "didn't",
          'metadata': {'commonMistakes': ['didnt']},
        },
      ]);
      addTearDown(db.close);

      final index = await WordFeatureIndex.build(db);
      expect(index.featuresOf(1).hasFeature(WordFeature.knownMisspelling), isTrue);
      expect(index.featuresOf(2).hasFeature(WordFeature.knownMisspelling), isFalse);
    });
  });

  group('sources', () {
    test('travel with the index so filtering needs no metadata', () async {
      final db = await packFixture([
        {'word': 'Haus', 'metadata': {'sources': ['BERLIN', 'HESSEN']}},
        {'word': 'Baum'},
      ]);
      addTearDown(db.close);

      final index = await WordFeatureIndex.build(db);
      expect(index.sourcesOf(1), ['BERLIN', 'HESSEN']);
      expect(index.sourcesOf(2), isEmpty);
    });
  });

  group('the Dart fallback', () {
    test('derives exactly what the SQL derives', () async {
      // If the index cannot be built, the bits are derived in Dart from the
      // decoded rows instead. Two implementations of one rule drift unless
      // something holds them together; this is that something.
      final words = <Map<String, Object?>>[
        {
          'word': 'full',
          'enrichment': {
            'definitions': ['a meaning'],
            'synonyms': ['another'],
            'antonyms': ['opposite'],
            'hyphenation': ['full'],
            'translations': [{'lang_code': 'en', 'word': 'full'}],
            'examples': [{'text': 'A full sentence.'}],
            'hypernyms': [{'hypernym_word': 'thing'}],
            'hyponyms': [{'hyponym_word': 'part'}],
            'expressions': [{'expression': 'in full'}],
            'proverbs': [{'proverb': 'full is full'}],
            'pronunciation': [{'ipa': 'fʊl'}],
            'inflections': [{'form_text': 'fuller'}],
            'enrichment_status': 'success',
          },
          'metadata': {
            'commonLearnerErrors': ['ful'],
            'grade_examples': {'1': ['A full cup.']},
            'gutenberg_examples': ['Full of it.'],
          },
        },
        {'word': 'bare', 'enrichment': const {}, 'metadata': const {}},
        // Empty lists must read as absent, not present.
        {
          'word': 'hollow',
          'enrichment': {'definitions': [], 'synonyms': [], 'pronunciation': []},
          'metadata': {'commonLearnerErrors': []},
        },
        // The German pack's spelling of learner errors.
        {'word': 'deutsch', 'enrichment': const {}, 'metadata': {'commonMistakes': ['deutch']}},
        // enrichment_status present but not success.
        {'word': 'partial', 'enrichment': {'enrichment_status': 'failed'}, 'metadata': const {}},
        // Enrichment that belongs to another word, and a curriculum listing.
        {
          'word': 'ideas',
          'enrichment': {'primary_lemma': 'idea', 'definitions': ['a thought']},
          'metadata': {'sources': ['HESSEN']},
        },
        {
          'word': 'cat',
          'enrichment': {'primary_lemma': 'cat'},
          'metadata': {'tags': ['source:cambridge_yle_starters']},
        },
        {'word': 'corpus', 'enrichment': const {}, 'metadata': {'sources': ['LEIPZIG']}},
      ];

      final db = await packFixture(words);
      addTearDown(db.close);
      final index = await WordFeatureIndex.build(db);

      for (var i = 0; i < words.length; i++) {
        final word = words[i];
        final dart = featuresFromDecodedJson(
          word: word['word'] as String,
          enrichment: (word['enrichment'] as Map).cast<String, dynamic>(),
          metadata: (word['metadata'] as Map).cast<String, dynamic>(),
        );
        // knownMisspelling is corpus-wide and deliberately not derived in
        // Dart, so compare everything else.
        final sql = index.featuresOf(i + 1) & ~WordFeature.knownMisspelling.mask;
        expect(dart, sql, reason: 'SQL and Dart disagree on "${word['word']}"');
      }
    });

    test('a failed build is not mistaken for a pack without enrichment', () {
      expect(const WordFeatureIndex.empty().isAvailable, isTrue);
      expect(const WordFeatureIndex.unavailable().isAvailable, isFalse,
          reason: 'the caller has to be able to tell these apart');
    });
  });

  group('cache record', () {
    Future<WordFeatureIndex> fixtureIndex() async {
      final db = await packFixture([
        {
          'word': 'Hund',
          'enrichment': {'definitions': ['a dog']},
          'metadata': {'sources': ['BERLIN']},
        },
        {'word': 'Katze', 'metadata': {'sources': ['COMMON_MISSPELLED']}},
      ]);
      addTearDown(db.close);
      return WordFeatureIndex.build(db);
    }

    test('round-trips bits, presentability and sources', () async {
      final index = await fixtureIndex();
      final restored = WordFeatureIndex.decode(index.encode('rev-1'), 'rev-1')!;

      expect(restored.length, index.length);
      expect(restored.featuresOf(1), index.featuresOf(1));
      expect(restored.sourcesOf(1), ['BERLIN']);
      expect(restored.isPresentable(2), isFalse);
    });

    test('is rejected for a different pack revision', () async {
      final index = await fixtureIndex();
      expect(WordFeatureIndex.decode(index.encode('rev-1'), 'rev-2'), isNull);
    });

    test('is rejected when truncated', () async {
      final index = await fixtureIndex();
      final raw = index.encode('rev-1');
      expect(WordFeatureIndex.decode(raw.sublist(0, raw.length - 3), 'rev-1'),
          isNull);
    });

    test('is built once and reused on the next launch', () async {
      final db = await packFixture([
        {'word': 'Hund', 'enrichment': {'definitions': ['a dog']}},
      ]);
      addTearDown(db.close);
      final cache = MemoryDbPartialCache();

      final first = await loadWordFeatureIndex(db,
          cacheKey: 'pack.db', revision: 'rev-1', cache: cache);
      expect(first.featuresOf(1).hasFeature(WordFeature.definitions), isTrue);

      // Dropping the table proves the second load never touched the database.
      await db.execute('DROP TABLE words');
      final second = await loadWordFeatureIndex(db,
          cacheKey: 'pack.db', revision: 'rev-1', cache: cache);
      expect(second.featuresOf(1).hasFeature(WordFeature.definitions), isTrue);

      // A new revision must not reuse the old record — and a failed rebuild
      // degrades to an empty index rather than throwing.
      final stale = await loadWordFeatureIndex(db,
          cacheKey: 'pack.db', revision: 'rev-2', cache: cache);
      expect(stale.isEmpty, isTrue);
    });
  });
}
