// lib/core/services/db_platform/db_feature_index.dart
//
// Builds — and caches — the per-word answers that used to require decoding
// every enrichment blob at launch.
//
// The pack database is opened read-only (see db_schema.dart), so the index
// cannot live inside it. It is derived once per pack revision and cached as a
// compact binary record through the same platform byte store the downloader
// uses (files on native, IndexedDB in the browser).
//
// The derivation itself runs entirely inside SQLite's JSON1 functions: only
// two integers per word cross into Dart, never the JSON.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/word_features.dart';
import 'db_partial_cache.dart';

/// SQL predicate per feature, evaluated against the `words` row.
///
/// `json_array_length` yields NULL for a missing path, and `NULL > 0` is not
/// true, so absent enrichment reads as "feature absent" without extra guards.
const Map<WordFeature, String> _featureSql = {
  WordFeature.definitions:
      "json_array_length(enrichment_json, '\$.definitions') > 0",
  WordFeature.synonyms: "json_array_length(enrichment_json, '\$.synonyms') > 0",
  WordFeature.antonyms: "json_array_length(enrichment_json, '\$.antonyms') > 0",
  WordFeature.hyphenation:
      "json_array_length(enrichment_json, '\$.hyphenation') > 0",
  // wiktionary_translations, which is the key the packs use and the key
  // GermanWord.translations reads. '$.translations' is empty in both packs, so
  // this bit answered false for every word and the translation games opened
  // with nothing.
  WordFeature.translations:
      "json_array_length(enrichment_json, '\$.wiktionary_translations') > 0",
  // EN fills commonLearnerErrors (Norvig/Wikipedia); DE fills commonMistakes
  // (LiTKey/DysList). Either means the word can carry a spelling-error round.
  WordFeature.learnerErrors:
      "json_array_length(metadata_json, '\$.commonLearnerErrors') > 0 "
          "OR json_array_length(metadata_json, '\$.commonMistakes') > 0",
  WordFeature.gradeExamples:
      "json_type(metadata_json, '\$.grade_examples') IS NOT NULL",
  WordFeature.examples: "json_array_length(enrichment_json, '\$.examples') > 0",
  WordFeature.hypernyms:
      "json_array_length(enrichment_json, '\$.hypernyms') > 0",
  WordFeature.hyponyms: "json_array_length(enrichment_json, '\$.hyponyms') > 0",
  WordFeature.expressions:
      "json_array_length(enrichment_json, '\$.expressions') > 0",
  WordFeature.proverbs: "json_array_length(enrichment_json, '\$.proverbs') > 0",
  WordFeature.gutenbergExamples:
      "json_array_length(metadata_json, '\$.gutenberg_examples') > 0",
  WordFeature.enrichmentSuccess:
      "json_extract(enrichment_json, '\$.enrichment_status') = 'success'",
  WordFeature.ipa: "json_array_length(enrichment_json, '\$.pronunciation') > 0",
  WordFeature.inflections:
      "json_array_length(enrichment_json, '\$.inflections') > 0",
  // knownMisspelling is not a per-row test — see _misspellingSql.
  WordFeature.curriculum: _curriculumSql,
  // A missing primary_lemma means nothing claims the entry is derived.
  WordFeature.headword:
      "coalesce(lower(json_extract(enrichment_json, '\$.primary_lemma')), "
          "lower(word)) = lower(word)",
};

/// Whether the word is on a word list a curriculum actually prescribes.
///
/// The two packs record this differently: German carries a Bundesland token in
/// `metadata_json.sources` for each state whose Grundwortschatz lists the word,
/// English carries the list in `metadata_json.tags`. Everything else in those
/// fields is a frequency corpus (Leipzig, Gutenberg, HermitDave), a name
/// register, or generation provenance, none of which says a teacher chose the
/// word.
///
/// Two English tags are deliberately excluded. `source:cefr_j` is a graded EFL
/// list covering 6,879 of 11,539 entries — broad enough that the bit would
/// stop selecting, and adult-leaning enough to put "psychological" and
/// "genetic" in front of a nine-year-old. `source:curriculum_added` only
/// records that an entry was inserted *because* a list named it; that list's
/// own tag is stored alongside, so nothing is lost by ignoring the marker.
/// What remains is 1,764 words from Dolch, Fry, Cambridge YLE and the UK DfE
/// statutory year lists.
const String _curriculumSql = '''
  EXISTS (
    SELECT 1 FROM json_each(words.metadata_json, '\$.sources') AS entry
     WHERE entry.value IN (
       'BAYERN', 'BERLIN', 'BRANDENBURG', 'BW1', 'BW3', 'HESSEN',
       'NIEDERSACHSEN', 'NRW111', 'NRW422', 'RHEINLAND_PFALZ',
       'SCHLESWIG_HOLSTEIN')
  )
  OR EXISTS (
    SELECT 1 FROM json_each(words.metadata_json, '\$.tags') AS entry
     WHERE entry.value IN (
       'source:dolch', 'source:fry', 'source:de_curriculum_en')
        OR entry.value LIKE 'source:cambridge_yle_%'
        OR entry.value LIKE 'source:uk_y%'
  )
'''; 

/// Rowids whose spelling appears in another entry's recorded learner errors.
///
/// A corpus-wide join rather than a per-row predicate, so it runs as its own
/// query; the CTE is materialised once and probed by the `IN`.
const String _misspellingSql = '''
  WITH errors(spelling) AS (
    SELECT DISTINCT lower(trim(entry.value))
      FROM words AS other,
           json_each(other.metadata_json, '\$.commonLearnerErrors') AS entry
    UNION
    SELECT DISTINCT lower(trim(entry.value))
      FROM words AS other,
           json_each(other.metadata_json, '\$.commonMistakes') AS entry
  )
  SELECT id AS row_id FROM words
   WHERE lower(trim(word)) IN (SELECT spelling FROM errors)
''';

/// The JSON half of [isPresentableVocabularyEntry], expressed in SQL.
///
/// The headword shape is a regular expression and stays in Dart, where it costs
/// nothing: it reads the `word` column, which is loaded anyway. These two
/// clauses are the ones that would otherwise force every blob to be decoded.
///
/// Markers are matched per definition/note rather than against the whole joined
/// description, which differs from the Dart version only for a marker split
/// across two entries.
const List<String> _invalidSpellingMarkers = [
  'misspelling of',
  'misspelt form of',
  'misspelled form of',
  'incorrect spelling of',
  'nonstandard spelling of',
  'obsolete spelling of',
  'obsolete form of',
  'falschschreibung von',
];

String _presentableSql() {
  final markerTest = _invalidSpellingMarkers
      .map((marker) => "lower(entry.value) LIKE '%$marker%'")
      .join(' OR ');
  return '''
    NOT EXISTS (
      SELECT 1 FROM json_each(words.metadata_json, '\$.sources') AS entry
      WHERE upper(entry.value) LIKE '%COMMON_MISSPELL%'
    )
    AND NOT EXISTS (
      SELECT 1 FROM json_each(words.enrichment_json, '\$.definitions') AS entry
      WHERE $markerTest
    )
    AND NOT EXISTS (
      SELECT 1 FROM json_each(words.enrichment_json, '\$.entryNotes') AS entry
      WHERE $markerTest
    )
  ''';
}

/// Internal flag stored alongside the feature bits. Kept above every
/// [WordFeature] bit; see [kWordFeatureIndexFormat] before reusing bits.
const int _presentableBit = 1 << 30;

/// Separates source tokens inside one packed record (never valid in a token).
const String _sourceSeparator = '\u001f';

/// What the index knows about one word.
@immutable
class WordIndexEntry {
  const WordIndexEntry(this.flags, this.sources);

  final int flags;

  /// `metadata_json.sources`, carried here because vocabulary filtering and the
  /// custom-subset screen need it for every word — the only part of the
  /// metadata blob that is not per-word-on-demand.
  final List<String> sources;
}

/// Feature bits, presentability and sources for every row of a pack, by rowid.
@immutable
class WordFeatureIndex {
  const WordFeatureIndex(this._entriesByRowId) : isAvailable = true;

  /// Empty index: every word reads as un-enriched but presentable, which is
  /// how the app behaved for packs without enrichment before the index.
  const WordFeatureIndex.empty()
      : _entriesByRowId = const {},
        isAvailable = true;

  /// The index could not be derived at all.
  ///
  /// Distinct from [WordFeatureIndex.empty] on purpose: an empty index is also
  /// how a pack with no enrichment legitimately reads, so treating a failed
  /// build as empty would leave every pool empty and every enrichment game
  /// silently unplayable while the app looked healthy. Callers check
  /// [isAvailable] and fall back to deriving the bits from the decoded rows.
  const WordFeatureIndex.unavailable()
      : _entriesByRowId = const {},
        isAvailable = false;

  final Map<int, WordIndexEntry> _entriesByRowId;

  /// False only when the derivation itself failed. See
  /// [WordFeatureIndex.unavailable].
  final bool isAvailable;

  int get length => _entriesByRowId.length;
  bool get isEmpty => _entriesByRowId.isEmpty;

  int featuresOf(int rowId) =>
      (_entriesByRowId[rowId]?.flags ?? 0) & ~_presentableBit;

  List<String> sourcesOf(int rowId) =>
      _entriesByRowId[rowId]?.sources ?? const [];

  /// Unknown rows count as presentable: a word the index has not seen must not
  /// silently vanish from the catalogue.
  bool isPresentable(int rowId) {
    final entry = _entriesByRowId[rowId];
    return entry == null || entry.flags & _presentableBit != 0;
  }

  /// Derives the index from an open (read-only) pack database.
  static Future<WordFeatureIndex> build(DatabaseExecutor db) async {
    // Driven by the map, not by WordFeature.values: features that are not a
    // per-row JSON test (knownMisspelling) are computed separately.
    final bits = _featureSql.entries
        .map((entry) =>
            'CASE WHEN (${entry.value}) THEN ${entry.key.mask} ELSE 0 END')
        .join(' + ');
    final rows = await db.rawQuery('''
      SELECT id AS row_id,
             ($bits) AS features,
             CASE WHEN ${_presentableSql()} THEN 1 ELSE 0 END AS presentable,
             (SELECT group_concat(entry.value, '$_sourceSeparator')
                FROM json_each(words.metadata_json, '\$.sources') AS entry)
               AS sources
      FROM words
    ''');
    // Folded in as a bit so the word-of-the-day pool — and anything else that
    // must not present a misspelling — can be filtered without decoding.
    final misspelled = <int>{};
    for (final row in await db.rawQuery(_misspellingSql)) {
      misspelled.add((row['row_id'] as num).toInt());
    }

    final entries = <int, WordIndexEntry>{};
    for (final row in rows) {
      final rowId = (row['row_id'] as num).toInt();
      final features = (row['features'] as num?)?.toInt() ?? 0;
      final presentable = (row['presentable'] as num?)?.toInt() ?? 1;
      final sources = (row['sources'] as String?) ?? '';
      entries[rowId] = WordIndexEntry(
        features |
            (presentable != 0 ? _presentableBit : 0) |
            (misspelled.contains(rowId) ? WordFeature.knownMisspelling.mask : 0),
        sources.isEmpty ? const [] : sources.split(_sourceSeparator),
      );
    }
    return WordFeatureIndex(entries);
  }

  /// `WFX` magic, format, revision digest, then one record per row:
  /// rowid, flags, and the word's sources as a length-prefixed UTF-8 run.
  Uint8List encode(String revision) {
    final digest = utf8.encode(revision);
    final packed = <int, Uint8List>{
      for (final entry in _entriesByRowId.entries)
        entry.key: Uint8List.fromList(
            utf8.encode(entry.value.sources.join(_sourceSeparator))),
    };
    final payload =
        packed.values.fold<int>(0, (total, bytes) => total + 10 + bytes.length);
    final bytes = ByteData(16 + digest.length + payload);
    var offset = 0;
    bytes.setUint32(offset, _magic);
    offset += 4;
    bytes.setUint32(offset, kWordFeatureIndexFormat);
    offset += 4;
    bytes.setUint32(offset, digest.length);
    offset += 4;
    bytes.setUint32(offset, _entriesByRowId.length);
    offset += 4;
    for (final byte in digest) {
      bytes.setUint8(offset++, byte);
    }
    _entriesByRowId.forEach((rowId, entry) {
      final sources = packed[rowId]!;
      bytes.setUint32(offset, rowId);
      offset += 4;
      bytes.setUint32(offset, entry.flags);
      offset += 4;
      bytes.setUint16(offset, sources.length);
      offset += 2;
      for (final byte in sources) {
        bytes.setUint8(offset++, byte);
      }
    });
    return bytes.buffer.asUint8List();
  }

  /// Null when the record is absent, truncated, written by another format
  /// version, or belongs to a different pack revision.
  static WordFeatureIndex? decode(Uint8List? raw, String revision) {
    if (raw == null || raw.length < 16) return null;
    final bytes = ByteData.sublistView(raw);
    if (bytes.getUint32(0) != _magic) return null;
    if (bytes.getUint32(4) != kWordFeatureIndexFormat) return null;
    final digestLength = bytes.getUint32(8);
    final count = bytes.getUint32(12);
    if (raw.length < 16 + digestLength) return null;
    if (utf8.decode(raw.sublist(16, 16 + digestLength), allowMalformed: true) !=
        revision) {
      return null;
    }
    final entries = <int, WordIndexEntry>{};
    var offset = 16 + digestLength;
    for (var i = 0; i < count; i++) {
      if (offset + 10 > raw.length) return null;
      final rowId = bytes.getUint32(offset);
      final flags = bytes.getUint32(offset + 4);
      final length = bytes.getUint16(offset + 8);
      offset += 10;
      if (offset + length > raw.length) return null;
      final sources = length == 0
          ? const <String>[]
          : utf8
              .decode(raw.sublist(offset, offset + length), allowMalformed: true)
              .split(_sourceSeparator);
      offset += length;
      entries[rowId] = WordIndexEntry(flags, sources);
    }
    return offset == raw.length ? WordFeatureIndex(entries) : null;
  }
}

/// 'WFX\x01'.
const int _magic = 0x57465801;

/// Reads the cached index for [revision], deriving and caching it on a miss.
///
/// A cache failure is never fatal: the index is rebuilt next launch, and a
/// build failure degrades to [WordFeatureIndex.empty].
Future<WordFeatureIndex> loadWordFeatureIndex(
  DatabaseExecutor db, {
  required String cacheKey,
  required String revision,
  DbPartialCache? cache,
}) async {
  final store = cache ?? defaultDbPartialCache;
  final recordKey = 'features-${store.keyFor(cacheKey)}';

  try {
    final cached = WordFeatureIndex.decode(
      await store.readRecord(recordKey),
      revision,
    );
    if (cached != null) {
      if (kDebugMode) {
        debugPrint('[FEATURE_INDEX] ♻️ reused ${cached.length} rows');
      }
      return cached;
    }
  } catch (_) {
    // Unreadable cache: fall through and rebuild.
  }

  final WordFeatureIndex index;
  try {
    final watch = Stopwatch()..start();
    index = await WordFeatureIndex.build(db);
    if (kDebugMode) {
      debugPrint('[FEATURE_INDEX] 🔨 built ${index.length} rows '
          'in ${watch.elapsedMilliseconds} ms');
    }
  } catch (error) {
    // Never a silent empty index — see WordFeatureIndex.unavailable.
    debugPrint('[FEATURE_INDEX] ❌ build failed, falling back to decoding the '
        'pack in Dart: $error');
    return const WordFeatureIndex.unavailable();
  }

  try {
    await store.writeRecord(recordKey, index.encode(revision));
  } catch (error) {
    if (kDebugMode) debugPrint('[FEATURE_INDEX] ⚠️ cache write failed: $error');
  }
  return index;
}

/// The feature bits of one word, derived in Dart from its decoded JSON.
///
/// The twin of the SQL in [_featureSql], for the path taken when the index
/// could not be built. `db_feature_index_test.dart` asserts the two agree over
/// a fixture pack, so they cannot drift apart unnoticed.
///
/// [WordFeature.knownMisspelling] is not derived here: it is a corpus-wide
/// question, and on this path the words are decoded anyway, so the word-of-the
/// -day picker recomputes that exclusion from the real data itself.
int featuresFromDecodedJson({
  required String word,
  required Map<String, dynamic> enrichment,
  required Map<String, dynamic> metadata,
}) {
  bool nonEmptyList(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is List && value.isNotEmpty;
  }

  var features = 0;
  void set(WordFeature feature, bool present) {
    if (present) features |= feature.mask;
  }

  set(WordFeature.definitions, nonEmptyList(enrichment, 'definitions'));
  set(WordFeature.synonyms, nonEmptyList(enrichment, 'synonyms'));
  set(WordFeature.antonyms, nonEmptyList(enrichment, 'antonyms'));
  set(WordFeature.hyphenation, nonEmptyList(enrichment, 'hyphenation'));
  set(WordFeature.translations,
      nonEmptyList(enrichment, 'wiktionary_translations'));
  set(
      WordFeature.learnerErrors,
      nonEmptyList(metadata, 'commonLearnerErrors') ||
          nonEmptyList(metadata, 'commonMistakes'));
  set(WordFeature.gradeExamples, metadata['grade_examples'] != null);
  set(WordFeature.examples, nonEmptyList(enrichment, 'examples'));
  set(WordFeature.hypernyms, nonEmptyList(enrichment, 'hypernyms'));
  set(WordFeature.hyponyms, nonEmptyList(enrichment, 'hyponyms'));
  set(WordFeature.expressions, nonEmptyList(enrichment, 'expressions'));
  set(WordFeature.proverbs, nonEmptyList(enrichment, 'proverbs'));
  set(WordFeature.gutenbergExamples,
      nonEmptyList(metadata, 'gutenberg_examples'));
  set(WordFeature.enrichmentSuccess,
      enrichment['enrichment_status'] == 'success');
  set(WordFeature.ipa, nonEmptyList(enrichment, 'pronunciation'));
  set(WordFeature.inflections, nonEmptyList(enrichment, 'inflections'));

  const germanCurricula = {
    'BAYERN', 'BERLIN', 'BRANDENBURG', 'BW1', 'BW3', 'HESSEN',
    'NIEDERSACHSEN', 'NRW111', 'NRW422', 'RHEINLAND_PFALZ',
    'SCHLESWIG_HOLSTEIN',
  };
  const englishLists = {
    'source:dolch', 'source:fry', 'source:de_curriculum_en',
  };
  final primaryLemma = enrichment['primary_lemma'];
  set(
      WordFeature.headword,
      primaryLemma is! String ||
          primaryLemma.toLowerCase() == word.toLowerCase());

  final sources = metadata['sources'];
  final tags = metadata['tags'];
  set(
      WordFeature.curriculum,
      (sources is List && sources.any(germanCurricula.contains)) ||
          (tags is List &&
              tags.any((tag) =>
                  englishLists.contains(tag) ||
                  (tag is String &&
                      (tag.startsWith('source:cambridge_yle_') ||
                          tag.startsWith('source:uk_y'))))));
  return features;
}
