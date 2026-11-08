// lib/core/services/sri_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- FIX: Import enums from the single source of truth ---
import '../models/skill_category.dart';
import '../models/sri_item_identity.dart';
import '../../features/games/tuning.dart';
// --- END FIX ---

// --- FIX: REMOVED duplicate enum LanguageSkillType ---
// --- FIX: REMOVED duplicate enum GermanWordType ---

// Data model for each tracked skill/problem
class SriLanguageData {
  final String itemId;
  final LanguageSkillType skillType;
  int successCount;
  int failureCount;
  double easinessFactor; // E-Factor from SM-2 algorithm
  int repetitions;
  DateTime nextReviewDate;
  DateTime? lastReviewedAt;
  int assistedSuccessCount;
  Map<String, dynamic>
  metadata; // Store additional info like grade level, topic

  SriLanguageData({
    required this.itemId,
    required this.skillType,
    this.successCount = 0,
    this.failureCount = 0,
    this.easinessFactor = kSm2InitialEasiness,
    this.repetitions = 0,
    required this.nextReviewDate,
    this.lastReviewedAt,
    this.assistedSuccessCount = 0,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};

  Map<String, dynamic> toJson() => {
    'id': itemId,
    'skillType': skillType.index,
    's': successCount,
    'f': failureCount,
    'ef': easinessFactor,
    'r': repetitions,
    'next': nextReviewDate.toIso8601String(),
    if (lastReviewedAt != null) 'last': lastReviewedAt!.toIso8601String(),
    'assisted': assistedSuccessCount,
    'meta': metadata,
  };

  factory SriLanguageData.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final storedSkill = json['skillType'];
    final inferredSkill = SriItemIdentity.fromId(id).skillType;
    final skill =
        storedSkill is int &&
            storedSkill >= 0 &&
            storedSkill < LanguageSkillType.values.length
        ? LanguageSkillType.values[storedSkill]
        : inferredSkill;
    if (skill == null) throw const FormatException('Unknown review skill');
    return SriLanguageData(
      itemId: id,
      skillType: skill,
      successCount: (json['s'] as num?)?.toInt() ?? 0,
      failureCount: (json['f'] as num?)?.toInt() ?? 0,
      easinessFactor: (json['ef'] as num?)?.toDouble() ?? kSm2InitialEasiness,
      repetitions: (json['r'] as num?)?.toInt() ?? 0,
      nextReviewDate: DateTime.parse(json['next'] as String),
      lastReviewedAt: DateTime.tryParse(json['last'] as String? ?? ''),
      assistedSuccessCount: (json['assisted'] as num?)?.toInt() ?? 0,
      metadata: Map<String, dynamic>.from(json['meta'] as Map? ?? const {}),
    );
  }

  SriItemIdentity get identity =>
      SriItemIdentity.fromId(itemId, skillType: skillType, metadata: metadata);
}

// Statistics for competence areas
class CompetenceStat {
  final int tracked;
  final int mastered;
  final double averageEasiness;
  final int totalAttempts;
  final double successRate;

  CompetenceStat({
    required this.tracked,
    required this.mastered,
    required this.averageEasiness,
    required this.totalAttempts,
    required this.successRate,
  });
}

// The main service class
class SriService with ChangeNotifier {
  SriService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  Map<String, SriLanguageData> _sriDatabase = {};
  final Map<String, String> _canonicalItemIds = {};
  // A malformed or newer-format record must not erase all the valid records,
  // nor disappear when a later answer saves the database.
  final Map<String, dynamic> _unparsedRecords = {};
  static const _sriStorageKey = 'sri_language_database';

  final Set<String> _alreadyReturnedThisSession = {};
  DateTime? _sessionStartTime;

  int get totalTrackedItems => _sriDatabase.length;
  int get totalAttempts => _sriDatabase.values.fold(
    0,
    (sum, item) => sum + item.successCount + item.failureCount,
  );
  int get totalMasteredItems => _sriDatabase.keys.where(isItemMastered).length;

  // UNCHANGED - Keep logging functionality
  void _log(String message) {
    if (kDebugMode) debugPrint('[SRI_SERVICE] 🚀 $message');
  }

  // UNCHANGED
  void resetSession() {
    _alreadyReturnedThisSession.clear();
    _sessionStartTime = _clock();
    _log('Session reset. Clearing returned items cache.');
  }

  // UNCHANGED
  void _checkSessionExpiry() {
    if (_sessionStartTime == null ||
        _clock().difference(_sessionStartTime!).inMinutes > 10) {
      resetSession();
    }
  }

  /// MODIFIED: Generate unique IDs for different language learning tasks
  String getItemId({
    required LanguageSkillType skillType,
    required String baseWord,
    String? additionalInfo,
  }) {
    return SriItemIdentity.itemId(
      skillType: skillType,
      baseWord: baseWord,
      additionalInfo: additionalInfo,
    );
  }

  /// MODIFIED: Check if an item is mastered
  bool isItemMastered(String itemId) {
    final data = getItemData(itemId);
    if (data == null) return false;
    return _isMastered(data);
  }

  bool _isMastered(SriLanguageData data) {
    final manualBox = data.metadata['manualBox'];
    if (manualBox is int && manualBox >= 1 && manualBox <= 5) {
      return manualBox == 5;
    }
    // Lifetime mistakes remain useful history, but never permanently bar a
    // learner from recovering. Repetitions resets after each new mistake.
    return data.repetitions >= kSm2MinimumRepetitionsForMastery &&
        data.easinessFactor > kSm2MasteryEasinessThreshold &&
        data.successCount - data.assistedSuccessCount >=
            kSm2MinimumSuccessesForMastery;
  }

  /// Calculate detailed breakdown by skill type and grade level
  Map<LanguageSkillType, Map<int, CompetenceStat>> getDetailedBreakdown() {
    _log('Calculating detailed language skills breakdown...');

    // Initialize breakdown structure
    final breakdown = <LanguageSkillType, Map<int, Map<String, dynamic>>>{};
    for (var skill in LanguageSkillType.values) {
      breakdown[skill] = {};
      for (var grade in List.generate(6, (i) => i + 1)) {
        breakdown[skill]![grade] = {
          'tracked': 0,
          'mastered': 0,
          'totalEFactor': 0.0,
          'totalAttempts': 0,
          'successfulAttempts': 0,
        };
      }
    }

    // Aggregate data
    _sriDatabase.forEach((itemId, data) {
      final gradeLevel = _gradeLevel(data) ?? 1;
      final skillType = data.skillType;

      if (gradeLevel >= 1 && gradeLevel <= 6) {
        // Safety check for old/invalid skill types
        if (breakdown.containsKey(skillType)) {
          final stats = breakdown[skillType]![gradeLevel]!;
          stats['tracked'] = (stats['tracked'] as int) + 1;
          stats['totalEFactor'] =
              (stats['totalEFactor'] as double) + data.easinessFactor;
          stats['totalAttempts'] =
              (stats['totalAttempts'] as int) +
              data.successCount +
              data.failureCount;
          stats['successfulAttempts'] =
              (stats['successfulAttempts'] as int) + data.successCount;

          if (isItemMastered(itemId)) {
            stats['mastered'] = (stats['mastered'] as int) + 1;
          }
        }
      }
    });

    // Convert to CompetenceStat objects
    final finalBreakdown = <LanguageSkillType, Map<int, CompetenceStat>>{};
    breakdown.forEach((skill, gradeMap) {
      finalBreakdown[skill] = {};
      gradeMap.forEach((grade, stats) {
        final tracked = stats['tracked'] as int;
        final mastered = stats['mastered'] as int;
        final totalEFactor = stats['totalEFactor'] as double;
        final totalAttempts = stats['totalAttempts'] as int;
        final successfulAttempts = stats['successfulAttempts'] as int;

        finalBreakdown[skill]![grade] = CompetenceStat(
          tracked: tracked,
          mastered: mastered,
          averageEasiness: tracked > 0 ? (totalEFactor / tracked) : 2.5,
          totalAttempts: totalAttempts,
          successRate: totalAttempts > 0
              ? successfulAttempts / totalAttempts
              : 0.0,
        );
      });
    });

    _log('✅ Detailed breakdown calculated.');
    return finalBreakdown;
  }

  /// Get breakdown by word type competence
  Map<GermanWordType, CompetenceStat> getWordTypeBreakdown() {
    final breakdown = <GermanWordType, Map<String, dynamic>>{};

    // Initialize
    for (var wordType in GermanWordType.values) {
      breakdown[wordType] = {
        'tracked': 0,
        'mastered': 0,
        'totalEFactor': 0.0,
        'totalAttempts': 0,
        'successfulAttempts': 0,
      };
    }

    // Aggregate word type identification skills
    _sriDatabase.forEach((itemId, data) {
      if (data.skillType == LanguageSkillType.wordType) {
        final wordType = (data.metadata['wordType'] as String?)
            ?.split('.')
            .last;
        if (wordType != null) {
          final enumType = GermanWordType.values.firstWhere(
            (e) => e.toString().split('.').last == wordType,
            orElse: () => GermanWordType.andere,
          );

          final stats = breakdown[enumType]!;
          stats['tracked'] = (stats['tracked'] as int) + 1;
          stats['totalEFactor'] =
              (stats['totalEFactor'] as double) + data.easinessFactor;
          stats['totalAttempts'] =
              (stats['totalAttempts'] as int) +
              data.successCount +
              data.failureCount;
          stats['successfulAttempts'] =
              (stats['successfulAttempts'] as int) + data.successCount;

          if (isItemMastered(itemId)) {
            stats['mastered'] = (stats['mastered'] as int) + 1;
          }
        }
      }
    });

    // Convert to CompetenceStat
    return breakdown.map((wordType, stats) {
      final tracked = stats['tracked'] as int;
      final totalAttempts = stats['totalAttempts'] as int;
      final successfulAttempts = stats['successfulAttempts'] as int;

      return MapEntry(
        wordType,
        CompetenceStat(
          tracked: tracked,
          mastered: stats['mastered'] as int,
          averageEasiness: tracked > 0
              ? ((stats['totalEFactor'] as double) / tracked)
              : 2.5,
          totalAttempts: totalAttempts,
          successRate: totalAttempts > 0
              ? (successfulAttempts / totalAttempts)
              : 0.0,
        ),
      );
    });
  }

  /// MODIFIED: Load data from storage
  Future<void> loadSriData() async {
    _log('Loading SRI language database from storage...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_sriStorageKey);
      if (jsonString != null) {
        final jsonMap = Map<String, dynamic>.from(json.decode(jsonString));
        _sriDatabase = {};
        _canonicalItemIds.clear();
        _unparsedRecords.clear();
        for (final entry in jsonMap.entries) {
          try {
            final value = Map<String, dynamic>.from(entry.value as Map);
            // The storage key is the identity other saved screens refer to.
            // Keep it intact even if an old row's redundant id differs.
            value['id'] = entry.key;
            final data = SriLanguageData.fromJson(value);
            _sriDatabase[entry.key] = data;
            _indexIdentity(data);
          } catch (error) {
            _unparsedRecords[entry.key] = entry.value;
            _log('Keeping unreadable record ${entry.key}: $error');
          }
        }
        _log(
          '✅ Successfully loaded ${_sriDatabase.length} SRI language records.',
        );
      } else {
        _log('No SRI data found. Starting with a fresh database.');
      }
    } catch (e) {
      _log('❌ Error loading SRI data: $e. Keeping existing in-memory data.');
    }

    resetSession();
    notifyListeners();
  }

  /// MODIFIED: Save data to storage
  Future<void> saveSriData() async {
    _log('Saving SRI language database to storage...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode({
        ..._unparsedRecords,
        ..._sriDatabase.map((key, value) => MapEntry(key, value.toJson())),
      });
      await prefs.setString(_sriStorageKey, jsonString);
      _log('✅ Successfully saved ${_sriDatabase.length} SRI language records.');
    } catch (e) {
      _log('❌ Error saving SRI data: $e');
    }
  }

  /// MODIFIED: Record a learning response
  void recordResponse({
    required LanguageSkillType skillType,
    required String baseWord,
    required bool wasCorrect,
    String? additionalInfo,
    Map<String, dynamic>? metadata,
    bool wasAssisted = false,
    Iterable<String> legacyBaseWords = const [],
  }) {
    final itemId = getItemId(
      skillType: skillType,
      baseWord: baseWord,
      additionalInfo: additionalInfo,
    );

    _log(
      'Recording response for "$itemId": ${wasCorrect ? "Correct ✅" : "Incorrect ❌"}',
    );

    SriLanguageData? existing = getItemData(itemId);
    // Older games sometimes stored displayName ("der Hund") rather than the
    // word ("Hund"). Preserve the exact existing key and its history while
    // adding canonical metadata, so future reviews can resolve the word.
    for (final legacyWord in legacyBaseWords) {
      existing ??= getItemData(
        getItemId(
          skillType: skillType,
          baseWord: legacyWord,
          additionalInfo: additionalInfo,
        ),
      );
    }
    final data =
        existing ??
        SriLanguageData(
          itemId: itemId,
          skillType: skillType,
          nextReviewDate: _clock(),
        );
    if (data.skillType != skillType) {
      throw StateError('A response cannot update a different review skill');
    }
    data.metadata.addAll({
      ...?metadata,
      'baseWord': baseWord,
      if (additionalInfo != null) 'additionalInfo': additionalInfo,
    });
    _recordResponse(data, wasCorrect: wasCorrect, wasAssisted: wasAssisted);
  }

  /// Updates exactly the item that was asked, preserving contextual suffixes
  /// and old ids. A different exercise cannot credit the original skill.
  void recordReviewResponse({
    required String itemId,
    required LanguageSkillType assessedSkill,
    required bool wasCorrect,
    bool wasAssisted = false,
    Map<String, dynamic>? metadata,
  }) {
    final data = getItemData(itemId);
    if (data == null) throw StateError('Unknown review item: $itemId');
    if (data.skillType != assessedSkill) {
      throw ArgumentError.value(
        assessedSkill,
        'assessedSkill',
        'Does not match the reviewed item',
      );
    }
    data.metadata.addAll(metadata ?? const {});
    _recordResponse(data, wasCorrect: wasCorrect, wasAssisted: wasAssisted);
  }

  void _indexIdentity(SriLanguageData data) {
    final canonical = data.identity.canonicalId;
    if (canonical != null) {
      _canonicalItemIds[canonical] = data.itemId;
    }
  }

  void _recordResponse(
    SriLanguageData data, {
    required bool wasCorrect,
    required bool wasAssisted,
  }) {
    final now = _clock();
    data.lastReviewedAt = now;
    data.metadata.remove('manualBox');
    data.metadata['lastResponseAssisted'] = wasAssisted;

    // Update success/failure counts
    if (wasCorrect) {
      data.successCount++;
      if (wasAssisted) data.assistedSuccessCount++;
    } else {
      data.failureCount++;
    }

    // SM-2 algorithm implementation
    final q = wasCorrect ? (wasAssisted ? 3 : 5) : 1;

    if (q < 3) {
      data.repetitions = 0;
    } else if (!wasAssisted) {
      data.repetitions++;
    }

    // Correct with support is useful practice, but not evidence to advance
    // independent mastery. Keep its ease unchanged and revisit it soon.
    if (!wasCorrect || !wasAssisted) {
      data.easinessFactor += 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02);
    }
    if (data.easinessFactor < kSm2MinimumEasiness) {
      data.easinessFactor = kSm2MinimumEasiness;
    }

    // Calculate next review interval
    int intervalInDays;
    if (wasAssisted || data.repetitions <= 1) {
      intervalInDays = 1;
    } else if (data.repetitions == 2) {
      intervalInDays = 3; // Shorter interval for language learning
    } else {
      intervalInDays = (data.repetitions - 1) * data.easinessFactor.round();
      // Cap maximum interval for young learners
      if (intervalInDays > 30) intervalInDays = 30;
    }

    data.nextReviewDate = now.add(Duration(days: intervalInDays));

    _sriDatabase[data.itemId] = data;
    _indexIdentity(data);
    _alreadyReturnedThisSession.add(data.itemId);
    _log(
      'Updated SRI for "${data.itemId}": EF=${data.easinessFactor.toStringAsFixed(2)}, Reps=${data.repetitions}, NextReview=${data.nextReviewDate.toIso8601String().substring(0, 10)}',
    );

    notifyListeners();
    saveSriData();
  }

  /// MODIFIED: Get items for review with skill type filtering
  List<String> getItemsForReview({
    int limit = 10,
    Set<String>? excludeIds,
    bool resetSessionFirst = false,
    LanguageSkillType? skillTypeFilter,
    int? gradeLevelFilter,
    bool markReturned = true,
  }) {
    if (limit <= 0) return const [];
    if (resetSessionFirst) {
      resetSession();
    } else {
      _checkSessionExpiry();
    }

    final now = _clock();
    final allExcluded = <String>{
      ..._alreadyReturnedThisSession,
      ...?excludeIds,
    };

    var reviewable = _sriDatabase.values
        .where(
          (data) =>
              !data.nextReviewDate.isAfter(now) &&
              !allExcluded.contains(data.itemId),
        )
        .toList();

    // Apply filters
    if (skillTypeFilter != null) {
      reviewable = reviewable
          .where((data) => data.skillType == skillTypeFilter)
          .toList();
    }

    if (gradeLevelFilter != null) {
      reviewable = reviewable
          .where(
            (data) =>
                _gradeLevel(data) == null ||
                _gradeLevel(data) == gradeLevelFilter,
          )
          .toList();
    }

    // Oldest due first prevents mastered maintenance cards being starved by
    // an endless stream of newer difficult cards. Ease breaks equal dates.
    reviewable.sort((a, b) {
      final dueComparison = a.nextReviewDate.compareTo(b.nextReviewDate);
      if (dueComparison != 0) return dueComparison;
      return a.easinessFactor.compareTo(b.easinessFactor);
    });

    final itemIds = reviewable.map((data) => data.itemId).take(limit).toList();

    if (markReturned) markItemsReturned(itemIds);

    _log(
      'Found ${itemIds.length} items for review (skill filter: $skillTypeFilter, grade: $gradeLevelFilter)',
    );
    if (itemIds.isNotEmpty) {
      _log('Returning: ${itemIds.join(", ")}');
    }

    return itemIds;
  }

  /// Reserve only the items that actually reached a playable round. Selection
  /// may inspect more candidates than it uses, and those stay available.
  void markItemsReturned(Iterable<String> itemIds) {
    _checkSessionExpiry();
    _alreadyReturnedThisSession.addAll(itemIds);
  }

  int? _gradeLevel(SriLanguageData data) {
    final grade = data.metadata['gradeLevel'];
    return grade is num ? grade.toInt() : int.tryParse('$grade');
  }

  /// NEW: Get available review count by skill type
  Map<LanguageSkillType, int> getAvailableReviewsBySkill({
    Set<String>? excludeIds,
  }) {
    _checkSessionExpiry();

    final now = _clock();
    final allExcluded = <String>{
      ..._alreadyReturnedThisSession,
      ...?excludeIds,
    };

    final counts = <LanguageSkillType, int>{};
    for (var skill in LanguageSkillType.values) {
      counts[skill] = 0;
    }

    _sriDatabase.values
        .where(
          (data) =>
              !data.nextReviewDate.isAfter(now) &&
              !allExcluded.contains(data.itemId),
        )
        .forEach((data) {
          // Ensure skill type exists in map (safety check)
          counts.update(
            data.skillType,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        });

    return counts;
  }

  /// NEW: Get user's current level for a skill type
  String getSkillLevel(LanguageSkillType skillType, int gradeLevel) {
    final breakdown = getDetailedBreakdown();
    final stat = breakdown[skillType]?[gradeLevel];

    if (stat == null || stat.tracked == 0) return "Anfänger";

    // This is safe because of the check above (stat.tracked > 0)
    final masteryRate = stat.mastered / stat.tracked;
    final avgEasiness = stat.averageEasiness;

    if (masteryRate > 0.8 && avgEasiness > 3.5) {
      return "Experte 🌟";
    } else if (masteryRate > 0.6 && avgEasiness > 3.0) {
      return "Fortgeschritten 🚀";
    } else if (masteryRate > 0.3 && avgEasiness > 2.5) {
      return "Geübt 💫";
    } else if (stat.tracked > 5) {
      return "Lernend 🌱";
    } else {
      return "Anfänger 🌿";
    }
  }

  // UNCHANGED - Keep these utility methods
  int getAvailableReviewCount({Set<String>? excludeIds}) {
    _checkSessionExpiry();

    final now = _clock();
    final allExcluded = <String>{
      ..._alreadyReturnedThisSession,
      ...?excludeIds,
    };

    return _sriDatabase.values
        .where(
          (data) =>
              !data.nextReviewDate.isAfter(now) &&
              !allExcluded.contains(data.itemId),
        )
        .length;
  }

  // UNCHANGED
  List<String> getFreshItemsForReview({
    int limit = 10,
    Set<String>? excludeIds,
  }) {
    return getItemsForReview(
      limit: limit,
      excludeIds: excludeIds,
      resetSessionFirst: true,
    );
  }

  // UNCHANGED
  void debugPrintSessionState() {
    _log(
      'SESSION DEBUG: ${_alreadyReturnedThisSession.length} items returned this session',
    );
    _log('Returned items: ${_alreadyReturnedThisSession.join(", ")}');
    _log('Available for review: ${getAvailableReviewCount()}');
  }

  /// MODIFIED: Get statistics
  int get masteredItemCount {
    return _sriDatabase.keys.where((id) => isItemMastered(id)).length;
  }

  int get learningItemCount => totalTrackedItems - masteredItemCount;

  /// Returns the items currently tracked with the lowest easiness factor,
  /// across all skill types. These are the player's toughest problems.
  List<SriLanguageData> getMostDifficultItems({int limit = 10}) {
    final items = _sriDatabase.values.toList();
    items.sort((a, b) => a.easinessFactor.compareTo(b.easinessFactor));
    return items.take(limit).toList();
  }

  /// NEW: Get most challenging words (for spelling)
  List<String> getMostChallengingWords({int limit = 10}) {
    final spellingItems = _sriDatabase.values
        .where((data) => data.skillType == LanguageSkillType.spelling)
        .where(
          (data) => (data.successCount + data.failureCount) > 0,
        ) // Check for any attempts
        .toList();

    spellingItems.sort((a, b) {
      final aTotal = a.successCount + a.failureCount;
      final bTotal = b.successCount + b.failureCount;

      final aFailureRate = aTotal > 0 ? a.failureCount / aTotal : 0.0;
      final bFailureRate = bTotal > 0 ? b.failureCount / bTotal : 0.0;

      if (aFailureRate != bFailureRate) {
        return bFailureRate.compareTo(
          aFailureRate,
        ); // Higher failure rate first
      }
      return a.easinessFactor.compareTo(
        b.easinessFactor,
      ); // Lower easiness first
    });

    return spellingItems
        .take(limit)
        .map((data) => data.identity.baseWord)
        .toList();
  }

  /// NEW: Get recently learned items
  List<String> getRecentlyLearnedItems({int days = 7, int limit = 20}) {
    final cutoffDate = _clock().subtract(Duration(days: days));

    final recentItems = _sriDatabase.values
        .where(
          (data) =>
              data.successCount > 0 &&
              data.lastReviewedAt != null &&
              !data.lastReviewedAt!.isBefore(cutoffDate),
        )
        .toList();

    recentItems.sort((a, b) => b.lastReviewedAt!.compareTo(a.lastReviewedAt!));

    return recentItems.take(limit).map((data) => data.itemId).toList();
  }

  /// NEW: Get skill-specific data for an item
  SriLanguageData? getItemData(String itemId) {
    return _sriDatabase[itemId] ?? _sriDatabase[_canonicalItemIds[itemId]];
  }

  /// NEW: Clear all data (for testing or reset)
  Future<void> clearAllData() async {
    _sriDatabase.clear();
    _canonicalItemIds.clear();
    _unparsedRecords.clear();
    _alreadyReturnedThisSession.clear();
    await saveSriData();
    notifyListeners();
    _log('⚠️ All SRI data cleared!');
  }

  // ============== Karteikasten (Leitner-style) projection ==============
  //
  // Maps the SM-2 state onto 5 boxes for a flashcard-box UI. Mastery
  // criterion mirrors isItemMastered.

  /// Returns 1..5 for the given item data. 1 = Neu, 5 = Gemeistert.
  int getBoxFor(SriLanguageData d) {
    final manualBox = d.metadata['manualBox'];
    if (manualBox is int && manualBox >= 1 && manualBox <= 5) {
      return manualBox;
    }
    if (_isMastered(d)) return 5;
    if (d.repetitions == 0) return 1;
    if (d.repetitions == 1) return 2;
    if (d.repetitions == 2) return 3;
    return 4;
  }

  /// All items currently sitting in [box] (1..5).
  List<SriLanguageData> getItemsInBox(int box) {
    return _sriDatabase.values.where((d) => getBoxFor(d) == box).toList();
  }

  /// Item count per box; map keys are always 1..5.
  Map<int, int> getBoxCounts() {
    final counts = <int, int>{for (var i = 1; i <= 5; i++) i: 0};
    for (final d in _sriDatabase.values) {
      final b = getBoxFor(d);
      counts[b] = (counts[b] ?? 0) + 1;
    }
    return counts;
  }

  /// Manually place a card and schedule it without rewriting its attempt
  /// history. Manual placement is a self-assessment; the next answer clears
  /// it and returns the card to the same evidence-based mastery calculation
  /// used by the dashboard.
  Future<void> moveItemToBox(String itemId, int targetBox) async {
    final data = getItemData(itemId);
    if (data == null || targetBox < 1 || targetBox > 5) return;
    data.metadata['manualBox'] = targetBox;
    data.nextReviewDate = _clock().add(
      Duration(days: const [0, 1, 3, 7, 30][targetBox - 1]),
    );
    _alreadyReturnedThisSession.remove(data.itemId);
    _log('Moved "$itemId" to box $targetBox');
    notifyListeners();
    await saveSriData();
  }
}
