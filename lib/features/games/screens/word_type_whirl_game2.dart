// lib/features/games/screens/word_type_whirl_game.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:collection'; // For Queue

import '../../../core/services/audio_service.dart';
import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';

import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/game_ui.dart';
import '../widgets/space_background.dart';

class WordTypeWhirlGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const WordTypeWhirlGame({super.key, required this.gradeLevel});

  @override
  State<WordTypeWhirlGame> createState() => _WordTypeWhirlGameState();
}

class WhirlingWord {
  final GermanWord word;
  final double angle;
  final double radius; // This will now be relative (0.0 to 1.0)
  final double speed;
  bool isTapped;
  bool isCorrect;
  bool shouldRemove;

  WhirlingWord({
    required this.word,
    required this.angle,
    required this.radius,
    required this.speed,
    this.isTapped = false,
    this.isCorrect = false,
    this.shouldRemove = false,
  });
}

class RoundStats {
  final GermanWordType targetType;
  int correctTaps;
  int incorrectTaps;
  int missedWords;

  RoundStats({
    required this.targetType,
    this.correctTaps = 0,
    this.incorrectTaps = 0,
    this.missedWords = 0,
  });
}

// --- NEW: Class to hold hint data ---
class HintMessage {
  final String text;
  final bool isError;
  final String id; // Unique ID for AnimatedList

  HintMessage({required this.text, required this.isError})
      : id = UniqueKey().toString();
}

class _WordTypeWhirlGameState extends State<WordTypeWhirlGame>
    with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  List<WhirlingWord> _whirlingWords = [];
  GermanWordType? _currentTargetType;
  int _score = 0;
  int _streak = 0;
  int _maxStreak = 0;
  int _round = 1;
  int _totalRounds = 8;
  double _baseSpeed = 1.0;
  bool _isEndingRound = false;

  // --- MODIFIED: Auto-hint system ---
  Timer? _autoHintTimer; // This replaces the old _hintTimer
  bool _showAutoHints = false; // This replaces the old _showHints
  static const _autoHintDelay =
      7; // Show auto-hints after 7 seconds of no correct taps
  int _secondsSinceLastCorrectTap = 0;

  // Round management
  Timer? _roundTimer;
  int _roundTimeRemaining = 15;
  List<RoundStats> _roundHistory = [];

  // Animation
  late AnimationController _whirlController;
  late AnimationController _pulseController;
  Timer? _spawnTimer;
  final Stopwatch _whirlStopwatch = Stopwatch();

  // --- NEW: Responsive layout state ---
  Size _whirlAreaSize = Size.zero; // Size of the whirl area for responsiveness

  // --- NEW: Non-blocking hint queue system ---
  final Queue<HintMessage> _hintQueue = Queue<HintMessage>();
  HintMessage? _currentHintMessage;
  Timer? _hintDisplayTimer;
  final GlobalKey<AnimatedListState> _hintListKey =
      GlobalKey<AnimatedListState>();
  final List<HintMessage> _visibleHints = [];

  // Available word types based on grade
  late Map<GermanWordType, ({String label, IconData icon, Color color})>
      _wordTypes;

  // Word pool for current session
  List<GermanWord> _wordPool = [];
  int _wordPoolIndex = 0;

  @override
  void initState() {
    super.initState();

    _whirlController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // larger numbers make it easier
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _whirlStopwatch.start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = S.of(context)!;

    // Basic word types for all grades
    _wordTypes = {
      GermanWordType.substantiv: (
        label: s.wordSortCategoryNoun,
        icon: Icons.home,
        color: SpaceTheme.planetOrange
      ),
      GermanWordType.verb: (
        label: s.wordSortCategoryVerb,
        icon: Icons.directions_run,
        color: SpaceTheme.alienGreen
      ),
      GermanWordType.adjektiv: (
        label: s.wordSortCategoryAdjective,
        icon: Icons.palette,
        color: SpaceTheme.cosmicPink
      ),
    };

    // Add advanced types for higher grades
    if (widget.gradeLevel.index >= 2) {
      // Grade 3+
      _wordTypes[GermanWordType.adverb] =
          (label: 'Adverb', icon: Icons.speed, color: Colors.purple);
    }

    if (widget.gradeLevel.index >= 3) {
      // Grade 4+
      _wordTypes[GermanWordType.pronomen] =
          (label: 'Pronomen', icon: Icons.person, color: Colors.teal);
    }
  }

  @override
  void dispose() {
    _whirlController.dispose();
    _pulseController.dispose();
    _roundTimer?.cancel();
    _spawnTimer?.cancel();
    _autoHintTimer?.cancel(); // Modified
    _hintDisplayTimer?.cancel(); // New
    _whirlStopwatch.stop();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    setState(() => _isLoading = true);

    _vocabularyService = context.read<VocabularyService>();
    _sriService = context.read<SriService>();
    _audioService = context.read<AudioService>();
    _gameProvider = context.read<GameProvider>();

    if (!_vocabularyService.isInitialized) {
      await _vocabularyService.initialize();
    }

    _loadWordPool();
    _loadLevel();
  }

  String? _extractBaseWordFromSriId(String id) {
    if (id.startsWith('SPELL_')) return id.substring('SPELL_'.length);
    if (id.startsWith('WORDTYPE_')) return id.substring('WORDTYPE_'.length);
    return null;
  }

  void _loadWordPool() {
    // --- ADAPTIVE WORD SELECTION ---
    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};

    // Get review words (50%)
    final reviewItemIds = _sriService.getItemsForReview(
      limit: 50,
      skillTypeFilter: LanguageSkillType.wordType,
      gradeLevelFilter: widget.gradeLevel.index + 1,
    );

    for (final id in reviewItemIds) {
      final wordString = _extractBaseWordFromSriId(id);
      if (wordString == null) continue;

      try {
        final word = _vocabularyService
            .getAllWords(_gameProvider)
            .firstWhere(
                (w) => w.word.toLowerCase() == wordString.toLowerCase());

        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          wordsForGame.add(word);
          addedWordIds.add(word.id);
        }
      } catch (e) {
        // Word from SRI not in vocab, skip
      }
    }

    // Get new words
    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: 50,
      settingsProvider: _gameProvider,
    );

    for (final word in newWords) {
      if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
        wordsForGame.add(word);
        addedWordIds.add(word.id);
      }
    }

    // Fill with random words if needed
    if (wordsForGame.length < 60) {
      final allWords =
          _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
      allWords.shuffle();

      for (final word in allWords) {
        if (_isWordValidForGame(word) && !addedWordIds.contains(word.id)) {
          wordsForGame.add(word);
          addedWordIds.add(word.id);
          if (wordsForGame.length >= 100) break;
        }
      }
    }
    // --- END ADAPTIVE SELECTION ---

    // CRITICAL FIX: Ensure we have words of all types
    final wordsByType = <GermanWordType, List<GermanWord>>{};
    for (final type in _wordTypes.keys) {
      wordsByType[type] =
          wordsForGame.where((w) => w.wordType == type).toList();
    }

    // If any type has too few words, add more
    for (final type in _wordTypes.keys) {
      if ((wordsByType[type]?.length ?? 0) < 10) {
        final allWords = _vocabularyService.getAllWords(_gameProvider);
        final moreWords = allWords
            .where((w) =>
                w.wordType == type &&
                _isWordValidForGame(w) &&
                !addedWordIds.contains(w.id))
            .take(15)
            .toList();

        wordsForGame.addAll(moreWords);
        addedWordIds.addAll(moreWords.map((w) => w.id));
      }
    }

    wordsForGame.shuffle();
    _wordPool = wordsForGame;
    _wordPoolIndex = 0;

    debugPrint('[WHIRL] Word pool loaded: ${_wordPool.length} total words');
    for (final type in _wordTypes.keys) {
      final count = _wordPool.where((w) => w.wordType == type).length;
      debugPrint('[WHIRL] ${type.toString().split('.').last}: $count words');
    }
  }

  void _loadLevel() {
    setState(() {
      _score = 0;
      _streak = 0;
      _maxStreak = 0;
      _round = 1;
      _baseSpeed = 1.0;
      _roundHistory.clear();
      _isLoading = false;
      // --- NEW: Clear hint queue ---
      _hintQueue.clear();
      _visibleHints.clear();
      _currentHintMessage = null;
    });

    _startRound();
  }

  void _startRound() {
    _isEndingRound = false;
    if (_round > _totalRounds) {
      _showGameOver();
      return;
    }

    // Pick random target word type
    final types = _wordTypes.keys.toList()..shuffle();

    GermanWordType? selectedType;
    for (final type in types) {
      if (_hasEnoughWordsOfType(type)) {
        selectedType = type;
        break;
      }
    }

    _currentTargetType = selectedType ?? types.first;

    // Set round time based on grade
    switch (widget.gradeLevel) {
      case GradeLevel.grade1:
      case GradeLevel.grade2:
        _roundTimeRemaining = 20;
        break;
      case GradeLevel.grade3:
      case GradeLevel.grade4:
        _roundTimeRemaining = 15;
        break;
      default:
        _roundTimeRemaining = 12;
    }

    _baseSpeed = 1.0 + (_round - 1) * 0.08;

    // CRITICAL FIX: Reset hint system BEFORE setState
    _showAutoHints = false;
    _secondsSinceLastCorrectTap = 0;
    // --- NEW: Clear hints between rounds ---
    _hintQueue.clear();
    _hintDisplayTimer?.cancel();
    _currentHintMessage = null;
    // Clear visible list
    for (int i = _visibleHints.length - 1; i >= 0; i--) {
      _hintListKey.currentState?.removeItem(
        0,
        (context, animation) => const SizedBox.shrink(),
      );
    }
    _visibleHints.clear();
    // --- End New ---

    setState(() {
      _whirlingWords.clear();
      _roundHistory.add(RoundStats(targetType: _currentTargetType!));
    });

    _startRoundTimer();
    _startWordSpawning();

    _audioService.playSound('tap');

    debugPrint(
        '[WHIRL] Round $_round started - Target: $_currentTargetType - AutoHints: $_showAutoHints');
  }

  void _startRoundTimer() {
    _roundTimer?.cancel();
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_roundTimeRemaining > 0) {
        setState(() {
          _roundTimeRemaining--;

          // Track time since last correct tap for hints
          if (!_showAutoHints) {
            _secondsSinceLastCorrectTap++;
            if (_secondsSinceLastCorrectTap >= _autoHintDelay) {
              _showAutoHints = true;
            }
          }
        });

        // CRITICAL FIX: Check if all target words are tapped
        _checkRoundCompletion();
      } else {
        _endRound();
      }
    });
  }

  // Add this new method after _startRoundTimer
  void _checkRoundCompletion() {
    // Check if any target words remain
    final hasTargetWords = _whirlingWords
        .any((w) => !w.isTapped && w.word.wordType == _currentTargetType);

    if (!hasTargetWords && _whirlingWords.isNotEmpty) {
      // All target words tapped! Auto-complete round
      debugPrint('[WHIRL] All target words tapped! Auto-completing round.');
      _endRound();
    }
  }

  void _startWordSpawning() {
    _spawnTimer?.cancel();

    // Spawn interval decreases with difficulty
    final spawnInterval = (1500 ~/ _baseSpeed).clamp(600, 2000);

    _spawnTimer = Timer.periodic(Duration(milliseconds: spawnInterval), (timer) {
      if (_roundTimeRemaining > 0 && _whirlingWords.length < 12) {
        _spawnWord();
      }
    });

    // --- FIX: Simplify initial spawn ---
    // Just call _spawnWord(), which already has all the
    // correct logic for radius, uniqueness, and target-rate.
    final random = Random();
    for (int i = 0; i < 6; i++) {
      Future.delayed(Duration(milliseconds: i * 250 + random.nextInt(100)), () {
        if (mounted) _spawnWord();
      });
    }
  }

  bool _hasEnoughWordsOfType(GermanWordType type) {
    final count = _wordPool.where((w) => w.wordType == type).length;
    return count >= 5; // Need at least 5 words of each type
  }

  void _spawnWord() {
    if (_wordPoolIndex >= _wordPool.length) {
      _wordPool.shuffle();
      _wordPoolIndex = 0;
    }
    // --- NEW: Check if layout is ready ---
    final maxRadius = min(_whirlAreaSize.width, _whirlAreaSize.height) / 2.0;
    if (maxRadius <= 50) {
      // Area not laid out yet or too small, skip spawning
      return;
    }
    // --- END NEW ---

    final random = Random();

    // --- Make check case/whitespace-insensitive ---
    final Set<String> onScreenWords =
        _whirlingWords.map((w) => w.word.word.trim().toLowerCase()).toSet();

    // Ensure 40% of words are the target type
    final shouldSpawnTarget = random.nextDouble() < 0.4;

    GermanWord? selectedWord;
    int searchStartIndex = _wordPoolIndex;
    int maxAttempts = _wordPool.length; // Max search iteration

    if (shouldSpawnTarget) {
      // --- Try to find a word of the target type NOT on screen ---
      for (int i = 0; i < maxAttempts; i++) {
        int currentIndex = (searchStartIndex + i) % _wordPool.length;
        final candidateWord = _wordPool[currentIndex];
        final cleanWord = candidateWord.word.trim().toLowerCase();

        if (candidateWord.wordType == _currentTargetType &&
            !onScreenWords.contains(cleanWord)) {
          selectedWord = candidateWord;
          _wordPoolIndex = currentIndex + 1; // Set index for next spawn
          break;
        }
      }
    }

    // If still no target word found, or we want a non-target word
    if (selectedWord == null) {
      // --- Try to find a non-target word NOT on screen ---
      for (int i = 0; i < maxAttempts; i++) {
        int currentIndex = (searchStartIndex + i) % _wordPool.length;
        final candidateWord = _wordPool[currentIndex];
        final cleanWord = candidateWord.word.trim().toLowerCase();

        if (candidateWord.wordType != _currentTargetType &&
            !onScreenWords.contains(cleanWord)) {
          selectedWord = candidateWord;
          _wordPoolIndex = currentIndex + 1;
          break;
        }
      }
    }

    // Fallback: If STILL no word, find the *first available* word of *any* type
    if (selectedWord == null) {
      // --- Fallback to ANY word NOT on screen ---
      for (int i = 0; i < maxAttempts; i++) {
        int currentIndex = (searchStartIndex + i) % _wordPool.length;
        final candidateWord = _wordPool[currentIndex];
        final cleanWord = candidateWord.word.trim().toLowerCase();

        if (!onScreenWords.contains(cleanWord)) {
          selectedWord = candidateWord;
          _wordPoolIndex = currentIndex + 1;
          break;
        }
      }
    }

    // If no unique word could be found at all
    if (selectedWord == null) {
      debugPrint("[WHIRL] Could not find a unique word to spawn. Skipping.");
      return;
    }

    // --- MODIFIED: Use relative radii based on maxRadius ---
    // Use 25% to 50% of radius for inner band
    final innerRadiusMin = 0.25;
    final innerRadiusMax = 0.50;

    // Use 60% to 90% of radius for outer band
    final outerRadiusMin = 0.60;
    final outerRadiusMax = 0.90;
    // --- END MODIFIED ---

    final double radius;
    final bool isInnerBand; // Need to know which band we're in
    if (random.nextBool()) {
      // Inner band
      radius =
          innerRadiusMin + random.nextDouble() * (innerRadiusMax - innerRadiusMin);
      isInnerBand = true;
    } else {
      // Outer band
      radius =
          outerRadiusMin + random.nextDouble() * (outerRadiusMax - outerRadiusMin);
      isInnerBand = false;
    }

    // --- NEW FIX: Check for angular collision in the *same band* ---
    double newAngle;
    int attempt = 0;
    bool collision;

    // --- MODIFIED: Dynamic card width and angle separation ---
    final cardWidth = (maxRadius * 0.4).clamp(80.0, 120.0);
    // Calculate minimum separation based on the *inner* band for safety
    final minAngleSeparation =
        2 * asin((cardWidth / 2) / (innerRadiusMin * maxRadius));
    // --- END MODIFIED ---

    do {
      collision = false;
      newAngle = random.nextDouble() * 2 * pi;

      // Check against all existing words
      for (final existingWord in _whirlingWords) {
        // Are they in the same band? (use 0.55 as midpoint)
        final bool existingIsInner = existingWord.radius < 0.55;

        if (isInnerBand == existingIsInner) {
          // Yes. Check their angle separation.
          double angleDiff = (newAngle - existingWord.angle).abs();
          if (angleDiff > pi) {
            angleDiff = 2 * pi - angleDiff; // Get shortest arc
          }

          if (angleDiff < minAngleSeparation) {
            collision = true;
            break; // Collision found, break inner loop to try new angle
          }
        }
      }
      attempt++;
    } while (collision && attempt < 40); // Try 40 times to find a free spot

    if (collision) {
      // Still colliding after 40 attempts, band is likely full.
      // Don't spawn the word.
      debugPrint("[WHIRL] Could not find a non-colliding spot. Skipping.");
      return;
    }

    final whirlingWord = WhirlingWord(
      word: selectedWord,
      angle: newAngle, // Use the collision-checked angle
      radius: radius, // Store the RELATIVE radius
      speed: (0.5 + random.nextDouble() * 0.5) * _baseSpeed,
    );

    setState(() {
      _whirlingWords.add(whirlingWord);
    });
  }

  void _onWordTapped(WhirlingWord whirlingWord) {
    if (whirlingWord.isTapped) return;

    final isCorrect = whirlingWord.word.wordType == _currentTargetType;

    setState(() {
      whirlingWord.isTapped = true;
      whirlingWord.isCorrect = isCorrect;
    });

    if (isCorrect) {
      _onCorrectTap(whirlingWord);
    } else {
      _onIncorrectTap(whirlingWord);
    }

    // Remove word after animation
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          whirlingWord.shouldRemove = true;
          _whirlingWords.remove(whirlingWord);
        });
      }
    });
  }

  bool _isWordValidForGame(GermanWord word) {
    return _wordTypes.containsKey(word.wordType) &&
        !word.word.contains(" ") &&
        word.word.length >= 3 &&
        word.word.length <= 10 &&
        // Only use words that have successful, rich data from our API.
        // This guarantees all hints are high-quality.
        word.apiEnrichment?.enrichmentStatus == 'success';
  }

  // --- NEW: Hint Generation Logic ---
  String _generateEducationalHint(GermanWord word,
      {required bool isCorrect, GermanWordType? tappedTargetType}) {
    final typeName = _wordTypes[word.wordType]?.label ?? 'Wort';
    final targetName = tappedTargetType != null
        ? (_wordTypes[tappedTargetType]?.label ?? 'Wort')
        : '';

    // Get the new, reliable API data
    final apiData = word.apiEnrichment;
    final patternData = apiData?.inflectionsPattern; // This is the Pattern.de data

    if (isCorrect) {
      // --- SUCCESS HINTS (using API data) ---
      switch (word.wordType) {
        case GermanWordType.substantiv:
          String? plural;
          if (patternData?['plural'] is String) {
            plural = patternData!['plural'] as String;
          }
          if (plural != null && plural.isNotEmpty && plural != word.word) {
            return '✓ ${typeName}! Mehrzahl: ${plural}';
          }
          // Use displayName to show article
          return '✓ Richtig! ${word.displayName} (Nomen)';
          
        case GermanWordType.verb:
          String? ichForm;
          if (patternData?['conjugation']?['Präsens']?['ich'] is String) {
            ichForm = patternData!['conjugation']['Präsens']['ich'] as String;
          }
          if (ichForm != null) {
            return '✓ ${typeName}! (z.B. ich ${ichForm})';
          }
          return '✓ Richtig! ${word.word} ist ein ${typeName} (Tun-Wort)';
          
        case GermanWordType.adjektiv:
          String? komparativ;
          if (patternData?['comparative'] is String) {
            komparativ = patternData!['comparative'] as String;
          }
          if (komparativ != null && komparativ.isNotEmpty) {
            return '✓ ${typeName}! (z.B. ${komparativ})';
          }
          return '✓ Richtig! ${word.word} ist ein ${typeName} (Wie-Wort)';
          
        default:
          // Fallback to the first API definition
          if (apiData?.definitions.isNotEmpty ?? false) {
             return '✓ ${typeName}! ${apiData!.definitions.first}';
          }
          return '✓ Richtig! ${word.word} ist ein ${typeName}';
      }
    } else {
      // --- FAILURE HINTS (using API data) ---
      final correctTypeName = _wordTypes[_currentTargetType!]?.label ?? 'Wort';
      switch (word.wordType) {
        case GermanWordType.substantiv:
          // Use displayName to show article
          return "✗ ${word.displayName} ist ein Nomen (hat Artikel), kein ${correctTypeName}";
        case GermanWordType.verb:
          return '✗ ${word.word} ist ein Verb (Tun-Wort), kein ${correctTypeName}';
        case GermanWordType.adjektiv:
          return '✗ ${word.word} ist ein Adjektiv (Wie-Wort), kein ${correctTypeName}';
        default:
          // Fallback to the first API definition
          if (apiData?.definitions.isNotEmpty ?? false) {
             return '✗ ${typeName}: "${apiData!.definitions.first}", kein ${correctTypeName}';
          }
          return '✗ ${word.word} ist ein ${typeName}, kein ${correctTypeName}';
      }
    }
  }

  String _generateEducationalHint_old(GermanWord word,
      {required bool isCorrect, GermanWordType? tappedTargetType}) {
    final typeName = _wordTypes[word.wordType]?.label ?? 'Wort';
    final targetName = tappedTargetType != null
        ? (_wordTypes[tappedTargetType]?.label ?? 'Wort')
        : '';

    if (isCorrect) {
      // --- SUCCESS HINTS ---
      switch (word.wordType) {
        case GermanWordType.substantiv:
          if (word.article != null && word.article!.isNotEmpty) {
            return '✓ Richtig! ${word.article} ${word.word} (Nomen)';
          }
          if (word.plural != null && word.plural!.isNotEmpty && word.plural != '-') {
            return '✓ ${typeName}! Plural: ${word.plural}';
          }
          return '✓ Richtig! ${word.word} ist ein ${typeName}';
        case GermanWordType.verb:
          String? ichForm;
          if (word.inflectionData != null) {
            try {
              ichForm = word.inflectionData!['analyses']?['verb']
                  ?['conjugation']?['Präsens']?['ich'] as String?;
            } catch (e) {
              /* ignore */
            }
          }
          if (ichForm != null) {
            return '✓ ${typeName}! (z.B. ich ${ichForm})';
          }
          return '✓ Richtig! ${word.word} ist ein ${typeName}';
        case GermanWordType.adjektiv:
          String? komparativ;
          if (word.inflectionData != null) {
            try {
              komparativ = word.inflectionData!['analyses']?['adjektiv']
                  ?['comparison']?['Komparativ'] as String?;
            } catch (e) {
              /* ignore */
            }
          }
          if (komparativ != null && komparativ.isNotEmpty && komparativ != '-') {
            return '✓ ${typeName}! (z.B. ${komparativ})';
          }
          return '✓ Richtig! ${word.word} ist ein ${typeName} (Wie-Wort)';
        default:
          return '✓ Richtig! ${word.word} ist ein ${typeName}';
      }
    } else {
      // --- FAILURE HINTS ---
      // User tapped `word` (e.g., a Noun) but the target was `tappedTargetType` (e.g., a Verb)
      final correctTypeName = _wordTypes[_currentTargetType!]?.label ?? 'Wort';
      switch (word.wordType) {
        case GermanWordType.substantiv:
          if (word.article != null && word.article!.isNotEmpty) {
            return "✗ ${word.article} ${word.word} ist ein Nomen (hat Artikel), kein ${correctTypeName}";
          }
          return '✗ ${word.word} ist ein Nomen (groß), kein ${correctTypeName}';
        case GermanWordType.verb:
          return '✗ ${word.word} ist ein Verb (Tun-Wort), kein ${correctTypeName}';
        case GermanWordType.adjektiv:
          return '✗ ${word.word} ist ein Adjektiv (Wie-Wort), kein ${correctTypeName}';
        default:
          return '✗ ${word.word} ist ein ${typeName}, kein ${correctTypeName}';
      }
    }
  }

  // --- NEW: Hint Queue Processing Logic ---
  void _showHint(String message, bool isError) {
    final newHint = HintMessage(text: message, isError: isError);
    _hintQueue.add(newHint);
    if (_currentHintMessage == null) {
      _processHintQueue();
    }
  }

  void _processHintQueue() {
    if (_currentHintMessage != null || _hintQueue.isEmpty) {
      return; // A hint is already showing, or queue is empty
    }

    _hintDisplayTimer?.cancel();
    _currentHintMessage = _hintQueue.removeFirst();
    
    // Add to visible list for animation
    _visibleHints.insert(0, _currentHintMessage!);
    _hintListKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 400));

    _hintDisplayTimer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      
      // Remove from visible list for animation
      final removedHint = _visibleHints.removeAt(0);
      _hintListKey.currentState?.removeItem(
        0,
        (context, animation) => _buildHintToast(removedHint, animation, isRemoving: true),
        duration: const Duration(milliseconds: 300)
      );
      
      _currentHintMessage = null;
      _processHintQueue(); // Check for the next hint
    });
  }
  // --- END NEW HINT LOGIC ---

  void _onCorrectTap(WhirlingWord whirlingWord) {
    _audioService.playSound('success');
    _pulseController.forward(from: 0);

    // CRITICAL FIX: Reset auto-hint system IMMEDIATELY
    _secondsSinceLastCorrectTap = 0;
    _showAutoHints = false;

    // --- NEW: Show educational hint ---
    _showHint(
      _generateEducationalHint(whirlingWord.word, isCorrect: true),
      false, // isError = false
    );
    // --- END NEW ---

    setState(() {
      _streak++;
      if (_streak > _maxStreak) _maxStreak = _streak;

      final multiplier = min(1 + (_streak ~/ 3) * 0.5, 3.0);
      _score += (10 * multiplier).round();

      _roundHistory.last.correctTaps++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.wordType,
      baseWord: whirlingWord.word.word,
      wasCorrect: true,
      metadata: {
        'game': 'word_type_whirl',
        'round': _round,
        'streak': _streak,
      },
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _checkRoundCompletion();
    });
  }

  void _onIncorrectTap(WhirlingWord whirlingWord) {
    _audioService.playSound('failure');

    // --- NEW: Show educational hint ---
    _showHint(
      _generateEducationalHint(
        whirlingWord.word,
        isCorrect: false,
        tappedTargetType: _currentTargetType,
      ),
      true, // isError = true
    );
    // --- END NEW ---

    setState(() {
      _streak = 0;
      _score = max(0, _score - 5);
      _roundHistory.last.incorrectTaps++;
    });

    // Record failure in SRI
    _sriService.recordResponse(
      skillType: LanguageSkillType.wordType,
      baseWord: whirlingWord.word.word,
      wasCorrect: false,
      metadata: {
        'game': 'word_type_whirl',
        'round': _round,
      },
    );
  }

  void _endRound() {
    if (_isEndingRound) return;
    _isEndingRound = true;
    _roundTimer?.cancel();
    _spawnTimer?.cancel();

    // CRITICAL FIX: Force reset auto-hints before next round
    _showAutoHints = false;
    _secondsSinceLastCorrectTap = 0;

    // Count missed target words
    final missedCount = _whirlingWords
        .where(
            (w) => !w.isTapped && w.word.wordType == _currentTargetType)
        .length;

    _roundHistory.last.missedWords = missedCount;

    // Brief pause before next round
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _round++;
        });
        _startRound();
      }
    });
  }

  void _showGameOver() {
    _roundTimer?.cancel();
    _spawnTimer?.cancel();

    final s = S.of(context)!;

    // Calculate performance
    final totalCorrect = _roundHistory.fold<int>(
        0, (sum, stats) => sum + stats.correctTaps);
    final totalIncorrect = _roundHistory.fold<int>(
        0, (sum, stats) => sum + stats.incorrectTaps);
    final totalMissed =
        _roundHistory.fold<int>(0, (sum, stats) => sum + stats.missedWords);
    final total = totalCorrect + totalIncorrect + totalMissed;
    final accuracy = total > 0 ? (totalCorrect / total * 100).round() : 0;

    int stars = 1;
    if (accuracy >= 85)
      stars = 3;
    else if (accuracy >= 70) stars = 2;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.emoji_events,
                color: SpaceTheme.starYellow, size: 32),
            const SizedBox(width: 12),
            Text(
              s.wordWhirlGameOver,
              style: SpaceTheme.titleStyle,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return Icon(
                  index < stars ? Icons.star : Icons.star_border,
                  color: SpaceTheme.starYellow,
                  size: 40,
                );
              }),
            ),
            const SizedBox(height: 20),
            Text(
              '${s.gameScore}: $_score',
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 18),
            ),
            Text(
              '${s.wordWhirlAccuracy}: $accuracy%',
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 16),
            ),
            Text(
              '${s.wordWhirlBestStreak}: $_maxStreak',
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 16,
                color: SpaceTheme.starYellow,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${s.wordWhirlCorrect}: $totalCorrect',
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 14,
                color: SpaceTheme.alienGreen,
              ),
            ),
            Text(
              '${s.wordWhirlIncorrect}: $totalIncorrect',
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 14,
                color: SpaceTheme.rocketRed,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _loadLevel();
            },
            child: Text(
              s.gameReplay,
              style:
                  SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.alienGreen),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.planetOrange,
            ),
            child: Text(
              s.gameDone,
              style: SpaceTheme.bodyStyle.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final selectedFontFamily =
        context.watch<GameProvider>().selectedFontFamily;

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          // --- MODIFIED: Wrap in Stack for hint overlay ---
          child: Stack(
            children: [
              Column(
                children: [
                  GameUI(
                    title: s.wordWhirlTitle,
                    level: widget.gradeLevel.index + 1,
                    onBack: () {
                      _roundTimer?.cancel();
                      _spawnTimer?.cancel();
                      Navigator.of(context).pop();
                    },
                  ),
                  if (_isLoading)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Expanded(
                      child: Column(
                        children: [
                          // Stats bar
                          _buildStatsBar(s),

                          // Target instruction
                          _buildTargetBanner(s, selectedFontFamily),

                          // Whirl area
                          Expanded(
                            child: _buildWhirlArea(selectedFontFamily),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              // --- NEW: Non-blocking hint overlay ---
              _buildHintOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBar(S s) {
    final timeColor = _roundTimeRemaining < 5
        ? SpaceTheme.rocketRed
        : (_roundTimeRemaining < 10
            ? SpaceTheme.planetOrange
            : SpaceTheme.alienGreen);

    // --- MODIFIED: Use Flexible for responsiveness ---
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Flexible(
            child: _buildStatItem(s.gameScore, _score.toString(), Icons.stars,
                SpaceTheme.starYellow),
          ),
          Flexible(
            child: _buildStatItem(s.wordWhirlRound, '$_round/$_totalRounds',
                Icons.replay, SpaceTheme.cosmicPink),
          ),
          Flexible(
            child: _buildStatItem(s.wordWhirlStreak, _streak.toString(),
                Icons.local_fire_department,
                _streak > 5 ? SpaceTheme.starYellow : Colors.orange),
          ),
          Flexible(
            child: _buildStatItem(s.wordBuilderTime, '${_roundTimeRemaining}s',
                Icons.timer, timeColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 11,
            color: Colors.white70,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  Widget _buildTargetBanner(S s, String selectedFontFamily) {
    if (_currentTargetType == null) return const SizedBox.shrink();

    final typeInfo = _wordTypes[_currentTargetType!]!;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.1);

        return Transform.scale(
          scale: scale,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  typeInfo.color.withOpacity(0.3),
                  typeInfo.color.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: typeInfo.color, width: 3),
              boxShadow: [
                BoxShadow(
                  color: typeInfo.color.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(typeInfo.icon, color: typeInfo.color, size: 32),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        s.wordWhirlTapAll(typeInfo.label),
                        style: SpaceTheme.titleStyle.copyWith(
                          fontFamily: selectedFontFamily,
                          fontSize: 20,
                          color: typeInfo.color,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                // CRITICAL FIX: Show auto-hint indicator
                if (_showAutoHints)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lightbulb,
                            color: SpaceTheme.starYellow, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Hinweise aktiv!',
                          style: SpaceTheme.bodyStyle.copyWith(
                            fontSize: 12,
                            color: SpaceTheme.starYellow,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- NEW: Hint Overlay Widget ---
  Widget _buildHintOverlay() {
    // This Align widget ensures the hint list is positioned correctly
    // and doesn't interfere with other UI elements.
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        // Constrain the width on large screens
        constraints: const BoxConstraints(maxWidth: 500),
        // Use padding to keep it off the edges
        padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        // Ignore pointer events so taps fall through to the game
        child: AnimatedList(
          key: _hintListKey,
          initialItemCount: _visibleHints.length,
          itemBuilder: (context, index, animation) {
            // Get the hint from the *visible* list
            return _buildHintToast(_visibleHints[index], animation);
          },
          shrinkWrap: true,
          reverse: true,
        ),
      ),
    );
  }

  // --- NEW: Individual Hint Toast Widget ---
  Widget _buildHintToast(HintMessage hint, Animation<double> animation, {bool isRemoving = false}) {
    final color = hint.isError ? SpaceTheme.rocketRed : SpaceTheme.alienGreen;
    final icon = hint.isError ? Icons.cancel_outlined : Icons.check_circle_outline;

    // Use a SlideTransition and FadeTransition for smooth entry/exit
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.5), // Slide down
          end: const Offset(0, 0),
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: isRemoving ? Curves.easeOut : Curves.easeIn),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: SpaceTheme.deepSpace.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hint.text,
                      style: SpaceTheme.bodyStyle.copyWith(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWhirlArea(String selectedFontFamily) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // --- MODIFIED: Update responsive size ---
        // Use postFrameCallback to avoid setState during build
        if (constraints.biggest != _whirlAreaSize) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _whirlAreaSize = constraints.biggest;
              });
            }
          });
        }
        // --- END MODIFIED ---

        // --- MODIFIED: Use state variable for size ---
        final centerX = _whirlAreaSize.width / 2;
        final centerY = _whirlAreaSize.height / 2;
        final maxRadius = min(_whirlAreaSize.width, _whirlAreaSize.height) / 2.0;
        // --- END MODIFIED ---

        // Prevent division by zero if layout is 0
        if (maxRadius <= 0) return const SizedBox.shrink();

        return AnimatedBuilder(
          animation: _whirlController,
          builder: (context, child) {
            // --- FIX for jumpy animation ---
            // Use total elapsed time for a continuous, non-jumping rotation
            final double elapsedSeconds =
                _whirlStopwatch.elapsedMilliseconds / 1000.0;
            // Base speed: one full rotation (2*pi) every 8 seconds
            final double baseRadsPerSec = pi / 4;

            return Stack(
              clipBehavior: Clip.none, // Allow cards to go to the edge
              children: [
                // Center vortex decoration
                Positioned(
                  left: centerX - 30,
                  top: centerY - 30,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          SpaceTheme.cosmicPink.withOpacity(0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.tornado,
                        color: SpaceTheme.cosmicPink.withOpacity(0.5),
                        size: 32,
                      ),
                    ),
                  ),
                ),

                // Whirling words
                ..._whirlingWords.map((whirlingWord) {
                  // --- FIX for jumpy animation ---
                  // The angle is now based on the elapsed time and the word's speed
                  final currentAngle = whirlingWord.angle +
                      (elapsedSeconds * baseRadsPerSec * whirlingWord.speed);

                  // --- MODIFIED: Calculate position using relative radius ---
                  final x = centerX +
                      cos(currentAngle) * (whirlingWord.radius * maxRadius);
                  final y = centerY +
                      sin(currentAngle) * (whirlingWord.radius * maxRadius);
                  // --- END MODIFIED ---
                  
                  // --- MODIFIED: Responsive card size ---
                  final cardWidth = (maxRadius * 0.4).clamp(90.0, 130.0);
                  final cardHeight = (cardWidth * 0.5).clamp(45.0, 65.0);
                  // --- END MODIFIED ---

                  return Positioned(
                    // --- THIS IS THE FIX ---
                    // Give each word a unique key based on its text.
                    // This stops Flutter from reusing the wrong widget state.
                    key: ValueKey<String>(whirlingWord.word.id), // Use unique ID
                    // --- END OF FIX ---

                    left: x - (cardWidth / 2),
                    top: y - (cardHeight / 2),
                    child: _buildWhirlingWordWidget(
                      whirlingWord,
                      selectedFontFamily,
                      currentAngle,
                      cardWidth,
                      cardHeight,
                    ),
                  );
                }).toList(),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWhirlingWordWidget(
    WhirlingWord whirlingWord,
    String selectedFontFamily,
    double currentAngle,
    double cardWidth,
    double cardHeight,
  ) {
    final typeInfo = _wordTypes[whirlingWord.word.wordType];
    final isTarget = whirlingWord.word.wordType == _currentTargetType;

    final shouldHighlight = isTarget && _showAutoHints && !whirlingWord.isTapped;

    Color backgroundColor;
    Color borderColor;
    Color textColor = Colors.white;

    if (whirlingWord.isTapped) {
      if (whirlingWord.isCorrect) {
        backgroundColor = SpaceTheme.alienGreen.withOpacity(0.9);
        borderColor = SpaceTheme.alienGreen;
        textColor = SpaceTheme.deepSpace;
      } else {
        backgroundColor = SpaceTheme.rocketRed.withOpacity(0.9);
        borderColor = SpaceTheme.rocketRed;
      }
    } else if (shouldHighlight) {
      backgroundColor = SpaceTheme.deepSpace.withOpacity(0.9);
      borderColor = typeInfo?.color ?? SpaceTheme.starYellow;
      textColor = Colors.white;
    } else {
      backgroundColor = SpaceTheme.deepSpace.withOpacity(0.7);
      borderColor = Colors.white.withOpacity(0.3); // Neutral border
      textColor = Colors.white;
    }

    return GestureDetector(
      onTap: () => _onWordTapped(whirlingWord),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: cardWidth, // Responsive
        height: cardHeight, // Responsive
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: shouldHighlight ? 4 : 2, 
          ),
          boxShadow: [
            if (shouldHighlight)
              BoxShadow(
                color: borderColor.withOpacity(0.7),
                blurRadius: 12,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (shouldHighlight)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: RadialGradient(
                      colors: [
                        typeInfo!.color.withOpacity(0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    // --- OPTIMIZATION ---
                    // Use displayName to show "das Haus" instead of "Haus"
                    whirlingWord.word.displayName,
                    // --- END OPTIMIZATION ---
                    style: TextStyle(
                      fontFamily: selectedFontFamily,
                      fontSize: 16,
                      fontWeight:
                          shouldHighlight ? FontWeight.w900 : FontWeight.bold,
                      color: textColor,
                      shadows: [
                        Shadow(
                          blurRadius: shouldHighlight ? 4 : 2,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhirlingWordWidget_old(
    WhirlingWord whirlingWord,
    String selectedFontFamily,
    double currentAngle,
    double cardWidth,
    double cardHeight,
  ) {
    final typeInfo = _wordTypes[whirlingWord.word.wordType];
    final isTarget = whirlingWord.word.wordType == _currentTargetType;

    // Apply hint highlighting
    // This variable is key: it's only true if it's a target, hints are on, and it's not tapped
    final shouldHighlight = isTarget && _showAutoHints && !whirlingWord.isTapped;

    Color backgroundColor;
    Color borderColor;
    Color textColor = Colors.white;

    if (whirlingWord.isTapped) {
      if (whirlingWord.isCorrect) {
        backgroundColor = SpaceTheme.alienGreen.withOpacity(0.9);
        borderColor = SpaceTheme.alienGreen;
        textColor = SpaceTheme.deepSpace;
      } else {
        backgroundColor = SpaceTheme.rocketRed.withOpacity(0.9);
        borderColor = SpaceTheme.rocketRed;
      }
    } else if (shouldHighlight) {
      // --- FIX #1 ---
      // ONLY apply hint styling if shouldHighlight is true
      backgroundColor = SpaceTheme.deepSpace.withOpacity(0.9);
      borderColor = typeInfo?.color ?? SpaceTheme.starYellow;
      textColor = Colors.white;
    } else {
      // --- FIX #2 ---
      // This is the new default state for all un-tapped cards
      // (either non-target, or target with hints OFF)
      backgroundColor = SpaceTheme.deepSpace.withOpacity(0.7);
      borderColor = Colors.white.withOpacity(0.3); // Neutral border
      textColor = Colors.white;
    }

    return GestureDetector(
      onTap: () => _onWordTapped(whirlingWord),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: cardWidth, // Responsive
        height: cardHeight, // Responsive
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            // --- FIX #3 ---
            // Width is 5 if highlighted, otherwise a standard 2
            width: shouldHighlight ? 4 : 2, // Slightly thinner highlight
          ),
          boxShadow: [
            // --- FIX #4 ---
            // ONLY show the glow effect if shouldHighlight is true
            if (shouldHighlight)
              BoxShadow(
                color: borderColor.withOpacity(0.7),
                blurRadius: 12,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // This pulsing indicator is already correct
            if (shouldHighlight)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: RadialGradient(
                      colors: [
                        typeInfo!.color.withOpacity(0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    whirlingWord.word.word,
                    style: TextStyle(
                      fontFamily: selectedFontFamily,
                      fontSize: 16,
                      // These style changes are also correct as they depend on shouldHighlight
                      fontWeight:
                          shouldHighlight ? FontWeight.w900 : FontWeight.bold,
                      color: textColor,
                      shadows: [
                        Shadow(
                          blurRadius: shouldHighlight ? 4 : 2,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}