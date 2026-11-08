import 'package:flutter/foundation.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../models/vocabulary_models.dart';
import '../models/word_features.dart';
import 'db_platform/db_feature_index.dart' show featuresFromDecodedJson;

/// Verified source membership plus a small, independently authored lexical
/// supplement. The immutable downloaded database and its cached index stay
/// untouched; corrected feature flags are carried by the catalogue words.
class BwVocabularyOverlay {
  BwVocabularyOverlay.fromJson(
    Map<String, dynamic> membership,
    Map<String, dynamic> lexical,
  ) {
    if (membership['schemaVersion'] != 1 ||
        lexical['schemaVersion'] != 1 ||
        membership['language'] != 'de' ||
        lexical['language'] != 'de') {
      throw const FormatException('Unsupported BW vocabulary overlay');
    }
    for (final value in membership['memberships'] as List) {
      final row = Map<String, dynamic>.from(value as Map);
      final word = normalize(row['word'] as String);
      final bands = List<String>.from(row['sourceBands'] as List);
      if (word.isEmpty ||
          _memberships.containsKey(word) ||
          bands.isEmpty ||
          bands.any((band) => !_bwBands.contains(band))) {
        throw FormatException('Invalid or duplicate BW membership: $word');
      }
      _memberships[word] = List.unmodifiable(bands);
    }
    _targetPackHash = lexical['appliesToPackSha256'] as String;
    for (final value in lexical['senseRules'] as List? ?? const []) {
      final rule = Map<String, dynamic>.from(value as Map);
      final word = normalize(rule['word'] as String);
      final band = rule['sourceBand'] as String;
      if (!(_memberships[word]?.contains(band) ?? false)) {
        throw FormatException('Sense rule has no BW source: $word/$band');
      }
      _senseRules['$word\u001f$band'] =
          Set<String>.from(rule['allowedWordTypes'] as List);
    }
    final authoredIds = <String>{};
    for (final value in lexical['overrides'] as List? ?? const []) {
      final row = Map<String, dynamic>.from(value as Map);
      final target = Map<String, dynamic>.from(row['target'] as Map);
      final record = Map<String, dynamic>.from(row['record'] as Map);
      final id = target['id'] as String;
      if (id != record['id'] ||
          target['word'] != record['word'] ||
          !authoredIds.add(id)) {
        throw const FormatException('Invalid BW lexical correction identity');
      }
      _overrides[id] = record;
      _ordinarySenseWords.add(normalize(record['word'] as String));
    }
    for (final value in lexical['supplements'] as List? ?? const []) {
      final record = Map<String, dynamic>.from(value as Map);
      if (!authoredIds.add(record['id'] as String)) {
        throw const FormatException('Duplicate BW supplemental identity');
      }
      _supplements.add(record);
    }
  }

  static const membershipAsset = 'assets/data/bw_membership_v1.json';
  static const lexicalAsset = 'assets/data/bw_lexical_overlay_v1.json';
  static const authoredSource = 'PROJECT_BW_LEXICAL_V1';
  static const _bwBands = {'BW1', 'BW3'};

  final Map<String, List<String>> _memberships = {};
  final Map<String, Set<String>> _senseRules = {};
  final Map<String, Map<String, dynamic>> _overrides = {};
  final List<Map<String, dynamic>> _supplements = [];
  final Set<String> _ordinarySenseWords = {};
  final Map<String, GermanWord> _fullAuthoredWords = {};
  late final String _targetPackHash;

  /// NFC and whitespace normalization deliberately retain case and punctuation.
  /// Arm/arm and Paar/paar are different source entries, not spelling aliases.
  static String normalize(String text) =>
      unicode.nfc(text).trim().replaceAll(RegExp(r'\s+'), ' ');

  int get membershipCount => _memberships.length;
  Iterable<GermanWord> get authoredWords => _fullAuthoredWords.values;

  List<String> bandsFor(GermanWord word) {
    final written = normalize(word.word);
    // A listed ordinary noun does not validate a homonymous personal name.
    if (word.isProperNoun && _ordinarySenseWords.contains(written))
      return const [];
    return [
      for (final band in _memberships[written] ?? const <String>[])
        if (_senseRules['$written\u001f$band']?.contains(word.wordType.name) ??
            true)
          band,
    ];
  }

  GermanWord _withMembership(GermanWord word) {
    final bands = bandsFor(word);
    final sources = <String>{
      ...word.sources.where((source) => !_bwBands.contains(source)),
      ...bands,
    }.toList();
    // Reuse the index's curriculum rule; retain every unrelated feature bit.
    final curriculum = featuresFromDecodedJson(
          word: word.word,
          enrichment: const {},
          metadata: {'sources': sources},
        ) &
        WordFeature.curriculum.mask;
    final features =
        (word.features & ~WordFeature.curriculum.mask) | curriculum;
    if (listEquals(sources, word.sources) &&
        features == word.features &&
        word.isGrundwortschatzBW == bands.isNotEmpty) return word;
    return word.withCurriculumSources(
      sources: List.unmodifiable(sources),
      isGrundwortschatzBW: bands.isNotEmpty,
      features: features,
    );
  }

  GermanWord _authored(Map<String, dynamic> record, {GermanWord? original}) {
    final enrichment =
        Map<String, dynamic>.from(record['apiEnrichment'] as Map);
    final sources = <String>{
      ...?original?.sources.where((source) => !_bwBands.contains(source)),
      ...List<String>.from(record['sources'] as List? ?? const []),
      authoredSource,
    }.toList();
    final features = featuresFromDecodedJson(
      word: record['word'] as String,
      enrichment: enrichment,
      metadata: {
        'sources': sources,
        if (enrichment['grade_examples'] != null)
          'grade_examples': enrichment['grade_examples'],
      },
    );
    final full = _withMembership(GermanWord.fromJson({
      ...record,
      'id': original?.id ?? record['id'],
      'rowId': original?.rowId,
      'sources': sources,
      'features': features,
      'isHydrated': true,
    }));
    if (!full.isGrundwortschatzBW) {
      throw FormatException(
          'Authored word has no matching BW sense: ${full.word}');
    }
    return full;
  }

  GermanWord _light(GermanWord full) => GermanWord.fromJson({
        'id': full.id,
        'rowId': full.rowId,
        'word': full.word,
        'lemma': full.lemma,
        'wordType': full.wordType.name,
        'gradeLevel': full.gradeLevel,
        'article': full.article,
        'genus': full.genus,
        'sources': full.sources,
        'features': full.features,
        'isGrundwortschatzBW': full.isGrundwortschatzBW,
        'isHydrated': false,
      });

  /// Applies source bands to every pack row and adds only missing exact senses.
  /// Corrections are restricted to the audited immutable pack and exact ids.
  List<GermanWord> applyCatalogue(
    Iterable<GermanWord> words, {
    required String? packSha256,
  }) {
    _fullAuthoredWords.clear();
    final result = <GermanWord>[];
    for (final word in words) {
      final correction =
          packSha256 == _targetPackHash ? _overrides[word.id] : null;
      if (correction != null && correction['word'] == word.word) {
        final full = _authored(correction, original: word);
        _fullAuthoredWords[full.id] = full;
        result.add(_light(full));
      } else {
        result.add(_withMembership(word));
      }
    }
    for (final record in _supplements) {
      final full = _authored(record);
      final alreadyPresent = result.any((word) =>
          normalize(word.word) == normalize(full.word) &&
          word.wordType == full.wordType &&
          !word.isProperNoun);
      if (alreadyPresent) continue;
      if (result.any((word) => word.id == full.id)) {
        throw FormatException(
            'Supplement would overwrite an existing id: ${full.id}');
      }
      _fullAuthoredWords[full.id] = full;
      result.add(_light(full));
    }
    return result;
  }

  /// Called before and after database hydration, and on asynchronous searches.
  /// Authored rows resolve to their complete records; other pack rows retain
  /// the same source metadata that the feature-filtered catalogue showed.
  GermanWord hydrateOrApply(GermanWord word) {
    // User-authored words and fixtures are not rewritten by a pack overlay.
    if (word.rowId == null && !word.sources.contains(authoredSource))
      return word;
    return _fullAuthoredWords[word.id] ?? _withMembership(word);
  }
}
