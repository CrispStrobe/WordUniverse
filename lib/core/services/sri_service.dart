// lib/core/services/sri_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- FIX: Import enums from the single source of truth ---
import '../models/skill_category.dart';
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
  Map<String, dynamic> metadata; // Store additional info like grade level, topic

  SriLanguageData({
    required this.itemId,
    required this.skillType,
    this.successCount = 0,
    this.failureCount = 0,
    this.easinessFactor = kSm2InitialEasiness,
    this.repetitions = 0,
    required this.nextReviewDate,
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
    'meta': metadata,
  };

  factory SriLanguageData.fromJson(Map<String, dynamic> json) => SriLanguageData(
    itemId: json['id'],
    skillType: LanguageSkillType.values[json['skillType'] ?? 0],
    successCount: json['s'] ?? 0,
    failureCount: json['f'] ?? 0,
    easinessFactor: json['ef'] ?? kSm2InitialEasiness,
    repetitions: json['r'] ?? 0,
    nextReviewDate: DateTime.parse(json['next']),
    metadata: json['meta'] ?? {},
  );
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
  Map<String, SriLanguageData> _sriDatabase = {};
  static const _sriStorageKey = 'sri_language_database';
  
  final Set<String> _alreadyReturnedThisSession = {};
  DateTime? _sessionStartTime;

  // UNCHANGED - Keep logging functionality
  void _log(String message) {
    debugPrint('[SRI_SERVICE] 🚀 $message');
  }

  // UNCHANGED
  void resetSession() {
    _alreadyReturnedThisSession.clear();
    _sessionStartTime = DateTime.now();
    _log('Session reset. Clearing returned items cache.');
  }

  // UNCHANGED
  void _checkSessionExpiry() {
    if (_sessionStartTime == null || 
        DateTime.now().difference(_sessionStartTime!).inMinutes > 10) {
      resetSession();
    }
  }

  /// MODIFIED: Generate unique IDs for different language learning tasks
  String getItemId({
    required LanguageSkillType skillType,
    required String baseWord,
    String? additionalInfo,
  }) {
    // Create consistent IDs for tracking
    switch (skillType) {
      case LanguageSkillType.spelling:
        return 'SPELL_${baseWord.toLowerCase()}';
      case LanguageSkillType.articleSelection:
        return 'ARTICLE_${baseWord.toLowerCase()}';
      case LanguageSkillType.pluralForm:
        return 'PLURAL_${baseWord.toLowerCase()}';
      case LanguageSkillType.wordType:
        return 'WORDTYPE_${baseWord.toLowerCase()}';
      case LanguageSkillType.sentenceStructure:
        return 'SENTENCE_${additionalInfo ?? baseWord}';
      case LanguageSkillType.punctuation:
        return 'PUNCT_${additionalInfo ?? baseWord}';
      case LanguageSkillType.capitalization:
        return 'CAPITAL_${baseWord.toLowerCase()}';
      case LanguageSkillType.verbConjugation:
        // Ensure additionalInfo doesn't create trailing underscore
        final info = additionalInfo?.isNotEmpty == true ? '_$additionalInfo' : '';
        return 'CONJUG_${baseWord.toLowerCase()}$info';
      case LanguageSkillType.caseUsage:
        // Ensure additionalInfo doesn't create trailing underscore
        final info = additionalInfo?.isNotEmpty == true ? '_$additionalInfo' : '';
        return 'CASE_${baseWord.toLowerCase()}$info';
      case LanguageSkillType.vocabulary:
        return 'VOCAB_${baseWord.toLowerCase()}';
      case LanguageSkillType.reading:
        return 'READ_${baseWord.toLowerCase()}';
    }
  }

  /// MODIFIED: Check if an item is mastered
  bool isItemMastered(String itemId) {
    final data = _sriDatabase[itemId];
    if (data == null) return false;

    // Adjusted mastery criteria for language learning
    // Requires more repetitions and higher easiness factor
    final isMastered = data.repetitions >= 5 && 
                      data.easinessFactor > 3.5 && 
                      data.failureCount <= 2 &&
                      data.successCount >= 8;

    if (isMastered) {
      _log('Item "$itemId" is considered MASTERED. 🌟');
    }
    return isMastered;
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
      final gradeLevel = data.metadata['gradeLevel'] as int? ?? 1;
      final skillType = data.skillType;
      
      if (gradeLevel >= 1 && gradeLevel <= 6) {
        // Safety check for old/invalid skill types
        if (breakdown.containsKey(skillType)) {
          final stats = breakdown[skillType]![gradeLevel]!;
          stats['tracked'] = (stats['tracked'] as int) + 1;
          stats['totalEFactor'] = (stats['totalEFactor'] as double) + data.easinessFactor;
          stats['totalAttempts'] = (stats['totalAttempts'] as int) + data.successCount + data.failureCount;
          stats['successfulAttempts'] = (stats['successfulAttempts'] as int) + data.successCount;
          
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
          successRate: totalAttempts > 0 ? successfulAttempts / totalAttempts : 0.0,
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
        final wordType = data.metadata['wordType'] as String?;
        if (wordType != null) {
          final enumType = GermanWordType.values.firstWhere(
            (e) => e.toString().split('.').last == wordType,
            orElse: () => GermanWordType.andere,
          );
          
          final stats = breakdown[enumType]!;
          stats['tracked'] = (stats['tracked'] as int) + 1;
          stats['totalEFactor'] = (stats['totalEFactor'] as double) + data.easinessFactor;
          stats['totalAttempts'] = (stats['totalAttempts'] as int) + data.successCount + data.failureCount;
          stats['successfulAttempts'] = (stats['successfulAttempts'] as int) + data.successCount;
          
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
      
      return MapEntry(wordType, CompetenceStat(
        tracked: tracked,
        mastered: stats['mastered'] as int,
        averageEasiness: tracked > 0 ? ((stats['totalEFactor'] as double) / tracked) : 2.5,
        totalAttempts: totalAttempts,
        successRate: totalAttempts > 0 ? (successfulAttempts / totalAttempts) : 0.0,
      ));
    });
  }

  /// MODIFIED: Load data from storage
  Future<void> loadSriData() async {
    _log('Loading SRI language database from storage...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_sriStorageKey);
      if (jsonString != null) {
        final Map<String, dynamic> jsonMap = json.decode(jsonString);
        _sriDatabase = jsonMap.map(
          (key, value) => MapEntry(key, SriLanguageData.fromJson(value)),
        );
        _log('✅ Successfully loaded ${_sriDatabase.length} SRI language records.');
      } else {
        _log('No SRI data found. Starting with a fresh database.');
      }
    } catch (e) {
      _log('❌ Error loading SRI data: $e. Using an empty database.');
      _sriDatabase = {};
    }
    
    resetSession();
    notifyListeners();
  }

  /// MODIFIED: Save data to storage
  Future<void> saveSriData() async {
    _log('Saving SRI language database to storage...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(
        _sriDatabase.map((key, value) => MapEntry(key, value.toJson())),
      );
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
  }) {
    final itemId = getItemId(
      skillType: skillType,
      baseWord: baseWord,
      additionalInfo: additionalInfo,
    );
    
    _log('Recording response for "$itemId": ${wasCorrect ? "Correct ✅" : "Incorrect ❌"}');

    final data = _sriDatabase[itemId] ?? SriLanguageData(
      itemId: itemId,
      skillType: skillType,
      nextReviewDate: DateTime.now(),
      metadata: metadata ?? {},
    );

    // Update metadata if provided
    if (metadata != null) {
      data.metadata.addAll(metadata);
    }

    // Update success/failure counts
    if (wasCorrect) {
      data.successCount++;
    } else {
      data.failureCount++;
    }

    // SM-2 algorithm implementation
    final q = wasCorrect ? 5 : 1;

    if (q < 3) {
      data.repetitions = 0;
    } else {
      data.repetitions++;
    }

    data.easinessFactor = data.easinessFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    if (data.easinessFactor < kSm2MinimumEasiness) data.easinessFactor = kSm2MinimumEasiness;

    // Calculate next review interval
    int intervalInDays;
    if (data.repetitions <= 1) {
      intervalInDays = 1;
    } else if (data.repetitions == 2) {
      intervalInDays = 3; // Shorter interval for language learning
    } else {
      intervalInDays = (data.repetitions - 1) * data.easinessFactor.round();
      // Cap maximum interval for young learners
      if (intervalInDays > 30) intervalInDays = 30;
    }

    data.nextReviewDate = DateTime.now().add(Duration(days: intervalInDays));
    
    _sriDatabase[itemId] = data;
    _log('Updated SRI for "$itemId": EF=${data.easinessFactor.toStringAsFixed(2)}, Reps=${data.repetitions}, NextReview=${data.nextReviewDate.toIso8601String().substring(0, 10)}');
    
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
  }) {
    if (resetSessionFirst) {
      resetSession();
    } else {
      _checkSessionExpiry();
    }

    final now = DateTime.now();
    final allExcluded = <String>{
      ..._alreadyReturnedThisSession,
      ...?excludeIds,
    };

    var reviewable = _sriDatabase.values
        .where((data) => 
            data.nextReviewDate.isBefore(now) && 
            !allExcluded.contains(data.itemId) &&
            !isItemMastered(data.itemId))
        .toList();

    // Apply filters
    if (skillTypeFilter != null) {
      reviewable = reviewable.where((data) => data.skillType == skillTypeFilter).toList();
    }
    
    if (gradeLevelFilter != null) {
      reviewable = reviewable.where((data) => 
        data.metadata['gradeLevel'] == gradeLevelFilter
      ).toList();
    }

    // Sort by priority: lower easiness factor and earlier review date first
    reviewable.sort((a, b) {
      int efComparison = a.easinessFactor.compareTo(b.easinessFactor);
      if (efComparison != 0) return efComparison;
      return a.nextReviewDate.compareTo(b.nextReviewDate);
    });
    
    final itemIds = reviewable.map((data) => data.itemId).take(limit).toList();
    
    _alreadyReturnedThisSession.addAll(itemIds);
    
    _log('Found ${itemIds.length} items for review (skill filter: $skillTypeFilter, grade: $gradeLevelFilter)');
    if (itemIds.isNotEmpty) {
      _log('Returning: ${itemIds.join(", ")}');
    }
    
    return itemIds;
  }

  /// NEW: Get available review count by skill type
  Map<LanguageSkillType, int> getAvailableReviewsBySkill({Set<String>? excludeIds}) {
    _checkSessionExpiry();
    
    final now = DateTime.now();
    final allExcluded = <String>{
      ..._alreadyReturnedThisSession,
      ...?excludeIds,
    };

    final counts = <LanguageSkillType, int>{};
    for (var skill in LanguageSkillType.values) {
      counts[skill] = 0;
    }

    _sriDatabase.values
        .where((data) => 
            data.nextReviewDate.isBefore(now) && 
            !allExcluded.contains(data.itemId) &&
            !isItemMastered(data.itemId))
        .forEach((data) {
          // Ensure skill type exists in map (safety check)
          counts.update(data.skillType, (value) => value + 1, ifAbsent: () => 1);
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
    
    final now = DateTime.now();
    final allExcluded = <String>{
      ..._alreadyReturnedThisSession,
      ...?excludeIds,
    };

    return _sriDatabase.values
        .where((data) => 
            data.nextReviewDate.isBefore(now) && 
            !allExcluded.contains(data.itemId) &&
            !isItemMastered(data.itemId))
        .length;
  }

  // UNCHANGED
  List<String> getFreshItemsForReview({int limit = 10, Set<String>? excludeIds}) {
    return getItemsForReview(
      limit: limit, 
      excludeIds: excludeIds, 
      resetSessionFirst: true
    );
  }

  // UNCHANGED
  void debugPrintSessionState() {
    _log('SESSION DEBUG: ${_alreadyReturnedThisSession.length} items returned this session');
    _log('Returned items: ${_alreadyReturnedThisSession.join(", ")}');
    _log('Available for review: ${getAvailableReviewCount()}');
  }

  /// MODIFIED: Get statistics
  // --- FIX: Renamed to match property names ---
  int get totalTrackedItems => _sriDatabase.length;

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
        .where((data) => (data.successCount + data.failureCount) > 0) // Check for any attempts
        .toList();
    
    spellingItems.sort((a, b) {
      final aTotal = a.successCount + a.failureCount;
      final bTotal = b.successCount + b.failureCount;
      
      final aFailureRate = aTotal > 0 ? a.failureCount / aTotal : 0.0;
      final bFailureRate = bTotal > 0 ? b.failureCount / bTotal : 0.0;
      
      if (aFailureRate != bFailureRate) {
        return bFailureRate.compareTo(aFailureRate); // Higher failure rate first
      }
      return a.easinessFactor.compareTo(b.easinessFactor); // Lower easiness first
    });
    
    return spellingItems
        .take(limit)
        .map((data) => data.itemId.replaceFirst('SPELL_', ''))
        .toList();
  }

  /// NEW: Get recently learned items
  List<String> getRecentlyLearnedItems({int days = 7, int limit = 20}) {
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    
    final recentItems = _sriDatabase.values
        .where((data) => 
            data.successCount > 0 &&
            data.nextReviewDate.isAfter(cutoffDate))
        .toList();
    
    recentItems.sort((a, b) => b.nextReviewDate.compareTo(a.nextReviewDate));
    
    return recentItems.take(limit).map((data) => data.itemId).toList();
  }

  /// NEW: Get skill-specific data for an item
  SriLanguageData? getItemData(String itemId) {
    return _sriDatabase[itemId];
  }

  /// NEW: Clear all data (for testing or reset)
  Future<void> clearAllData() async {
    _sriDatabase.clear();
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
    final mastered = d.repetitions >= kSm2MinimumRepetitionsForMastery &&
        d.easinessFactor > kSm2MasteryEasinessThreshold &&
        d.failureCount <= kSm2MaxFailuresForMastery;
    if (mastered) return 5;
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

  /// Manually move an item into [targetBox] (1..5). Adjusts repetitions,
  /// easiness, failureCount and nextReviewDate so [getBoxFor] returns the
  /// requested value. Persists and notifies listeners.
  Future<void> moveItemToBox(String itemId, int targetBox) async {
    final data = _sriDatabase[itemId];
    if (data == null) return;
    final now = DateTime.now();
    switch (targetBox) {
      case 1:
        data.repetitions = 0;
        data.easinessFactor = kSm2InitialEasiness;
        data.failureCount = 0;
        data.nextReviewDate = now;
        break;
      case 2:
        data.repetitions = 1;
        if (data.easinessFactor < kSm2InitialEasiness) {
          data.easinessFactor = kSm2InitialEasiness;
        }
        data.nextReviewDate = now.add(const Duration(days: 1));
        break;
      case 3:
        data.repetitions = 2;
        if (data.easinessFactor < kSm2InitialEasiness + 0.5) {
          data.easinessFactor = kSm2InitialEasiness + 0.5;
        }
        data.nextReviewDate = now.add(const Duration(days: 3));
        break;
      case 4:
        if (data.repetitions < kSm2MinimumRepetitionsForMastery) {
          data.repetitions = kSm2MinimumRepetitionsForMastery;
        }
        if (data.easinessFactor < kSm2InitialEasiness + 1.0) {
          data.easinessFactor = kSm2InitialEasiness + 1.0;
        }
        if (data.easinessFactor > kSm2MasteryEasinessThreshold) {
          data.easinessFactor = kSm2MasteryEasinessThreshold;
        }
        data.nextReviewDate = now.add(const Duration(days: 7));
        break;
      case 5:
        if (data.repetitions < kSm2MinimumRepetitionsForMastery) {
          data.repetitions = kSm2MinimumRepetitionsForMastery + 2;
        }
        if (data.easinessFactor <= kSm2MasteryEasinessThreshold) {
          data.easinessFactor = kSm2MasteryEasinessThreshold + 0.1;
        }
        data.failureCount = 0;
        data.nextReviewDate = now.add(const Duration(days: 30));
        break;
      default:
        return;
    }
    _log('Moved "$itemId" to box $targetBox');
    notifyListeners();
    await saveSriData();
  }
}