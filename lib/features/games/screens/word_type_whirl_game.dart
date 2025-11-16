import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:collection'; // For Queue

import '../../../core/services/audio_service.dart';
import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart'; // <-- This is the correct source for models

import '../../../core/services/sri_service.dart';
// --- Use 'as' to prevent class name conflict ---
import '../../../core/services/vocabulary_service.dart' as vocab_service;
// --- END FIX ---

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
  // --- FIX: Use the aliased service type ---
  late vocab_service.VocabularyService _vocabularyService;
  // --- END FIX ---
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
  Timer? _autoHintTimer;
  bool _showAutoHints = false;
  static const _autoHintDelay = 7;
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
  Size _whirlAreaSize = Size.zero;

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
      duration: const Duration(seconds: 4),
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
    _autoHintTimer?.cancel();
    _hintDisplayTimer?.cancel();
    _whirlStopwatch.stop();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    setState(() => _isLoading = true);

    // --- FIX: Use the aliased service type ---
    _vocabularyService = context.read<vocab_service.VocabularyService>();
    // --- END FIX ---
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
    if (id.startsWith('ARTICLE_')) return id.substring('ARTICLE_'.length);
    return null;
  }

  bool _isWordValidForGame(GermanWord word, {bool requireApiData = false}) {
    final bool hasValidType = _wordTypes.containsKey(word.wordType);
    final bool isCleanWord = !word.word.contains(" ") &&
        word.word.length >= 3 &&
        word.word.length <= 10;

    if (requireApiData) {
      // For prioritized lists, we demand successful enrichment
      return hasValidType &&
          isCleanWord &&
          word.apiEnrichment?.enrichmentStatus == 'success';
    }

    // For general use, just check type and cleanliness
    return hasValidType && isCleanWord;
  }

  // --- MODIFIED: More robust word pool loading ---
  void _loadWordPool() {
    final List<GermanWord> wordsForGame = [];
    final Set<String> addedWordIds = {};
    
    // --- Prioritize enriched words ---
    final List<GermanWord> enrichedReviewWords = [];
    final List<GermanWord> nonEnrichedReviewWords = [];

    final reviewItemIds = _sriService.getItemsForReview(
      limit: 50,
      skillTypeFilter: LanguageSkillType.wordType,
      gradeLevelFilter: widget.gradeLevel.index + 1,
    );

    for (final id in reviewItemIds) {
      String? wordString = _extractBaseWordFromSriId(id);
      if (wordString == null) continue;

      if (wordString.startsWith('der ') ||
          wordString.startsWith('die ') ||
          wordString.startsWith('das ')) {
        wordString = wordString.split(' ')[1];
      }

      try {
        final word = _vocabularyService
            .getAllWords(_gameProvider) // Use filtered list first
            .firstWhere(
                (w) => w.word.toLowerCase() == wordString!.toLowerCase());

        if (!addedWordIds.contains(word.id)) {
          if (_isWordValidForGame(word, requireApiData: true)) {
            enrichedReviewWords.add(word);
            addedWordIds.add(word.id);
          } else if (_isWordValidForGame(word)) {
            nonEnrichedReviewWords.add(word);
            addedWordIds.add(word.id);
          }
        }
      } catch (e) {
        // Word from SRI not in vocab, skip
      }
    }

    wordsForGame.addAll(enrichedReviewWords);

    // Get new words, split by enrichment
    final newWords = _vocabularyService.getNewWords(
      sriService: _sriService,
      grade: widget.gradeLevel,
      limit: 100, // Get a larger pool to filter
      settingsProvider: _gameProvider,
    );

    final List<GermanWord> enrichedNewWords = [];
    final List<GermanWord> nonEnrichedNewWords = [];

    for (final word in newWords) {
      if (!addedWordIds.contains(word.id)) {
        if (_isWordValidForGame(word, requireApiData: true)) {
          enrichedNewWords.add(word);
          addedWordIds.add(word.id);
        } else if (_isWordValidForGame(word)) {
          nonEnrichedNewWords.add(word);
          addedWordIds.add(word.id);
        }
      }
    }

    wordsForGame.addAll(enrichedNewWords);
    wordsForGame.addAll(nonEnrichedReviewWords);
    wordsForGame.addAll(nonEnrichedNewWords);

    // Fill with random words if needed (prioritizing enriched)
    if (wordsForGame.length < 60) {
      final allWords =
          _vocabularyService.getWordsByGrade(widget.gradeLevel, _gameProvider);
      allWords.shuffle();

      final allEnriched = allWords
          .where((w) =>
              _isWordValidForGame(w, requireApiData: true) &&
              !addedWordIds.contains(w.id))
          .toList();
      wordsForGame.addAll(allEnriched);
      addedWordIds.addAll(allEnriched.map((w) => w.id));

      if (wordsForGame.length < 60) {
        final allNonEnriched = allWords
            .where((w) =>
                _isWordValidForGame(w) && !addedWordIds.contains(w.id))
            .toList();
        wordsForGame.addAll(allNonEnriched);
        addedWordIds.addAll(allNonEnriched.map((w) => w.id));
      }
    }

    // <-- FIX: CRITICAL FIX - This loop guarantees a minimum number of words for each playable type.
    final wordsByType = <GermanWordType, List<GermanWord>>{};
    for (final word in wordsForGame) {
      wordsByType.putIfAbsent(word.wordType, () => []).add(word);
    }

    // Get the *entire* vocabulary list as a fallback
    final allWordsFromService = _vocabularyService.getFullVocabularyList();
    allWordsFromService.shuffle();

    for (final type in _wordTypes.keys) {
      final int currentCount = wordsByType[type]?.length ?? 0;
      final int needed = 15 - currentCount; // Need at least 15 of each type

      if (needed > 0) {
        debugPrint(
            '[WHIRL] Topping up type $type. Need $needed more words...');
        // Find more words of this type from the *entire* service
        final moreWords = allWordsFromService
            .where((w) =>
                w.wordType == type &&
                _isWordValidForGame(w) && // Use non-strict check for fill
                !addedWordIds.contains(w.id))
            .take(needed)
            .toList();
        
        if (moreWords.isNotEmpty) {
          wordsForGame.addAll(moreWords);
          addedWordIds.addAll(moreWords.map((w) => w.id));
        } else {
          debugPrint('[WHIRL] WARNING: Could not find $needed more words for type $type.');
        }
      }
    }
    // <-- END FIX

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

    // <-- FIX: Safor round type selection. Only pick from types that have enough words.
    final validTypes = _wordTypes.keys
        .where((type) => _hasEnoughWordsOfType(type))
        .toList();

    if (validTypes.isEmpty) {
      debugPrint(
          "[WHIRL] CRITICAL ERROR: No word types have enough words to start a round. Check _loadWordPool.");
      // Show an error to the user
      showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Fehler beim Laden'),
                content: const Text(
                    'Es konnten nicht genügend Wörter für das Spiel geladen werden. Bitte starte das Spiel neu.'),
                actions: [
                  TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pop();
                      },
                      child: const Text('OK'))
                ],
              ));
      return;
    }

    validTypes.shuffle();
    _currentTargetType = validTypes.first;
    // <-- END FIX

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

    _showAutoHints = false;
    _secondsSinceLastCorrectTap = 0;
    _hintQueue.clear();
    _hintDisplayTimer?.cancel();
    _currentHintMessage = null;

    for (int i = _visibleHints.length - 1; i >= 0; i--) {
      _hintListKey.currentState?.removeItem(
        0,
        (context, animation) => const SizedBox.shrink(),
      );
    }
    _visibleHints.clear();

    setState(() {
      _whirlingWords.clear();
      _roundHistory.add(RoundStats(targetType: _currentTargetType!));
    });

    _startRoundTimer();
    _startWordSpawning(); // This will now guarantee at least 2 target words

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

          if (!_showAutoHints) {
            _secondsSinceLastCorrectTap++;
            if (_secondsSinceLastCorrectTap >= _autoHintDelay) {
              _showAutoHints = true;
            }
          }
        });

        // <-- FIX: Removed race condition.
        // The timer no longer checks for round completion.
        // _checkRoundCompletion();
        // <-- END FIX
      } else {
        _endRound(); // This is the timer's *only* way to end the round.
      }
    });
  }

  void _checkRoundCompletion() {
    // This function is now ONLY called by _onCorrectTap.
    final hasTargetWords = _whirlingWords
        .any((w) => !w.isTapped && w.word.wordType == _currentTargetType);

    // We check .isNotEmpty to avoid ending the round if a new word
    // just hasn't spawned yet.
    if (!hasTargetWords && _whirlingWords.isNotEmpty) {
      debugPrint('[WHIRL] All target words tapped! Auto-completing round.');
      _endRound();
    }
  }

  void _startWordSpawning() {
    _spawnTimer?.cancel();

    final spawnInterval = (1500 ~/ _baseSpeed).clamp(600, 2000);

    _spawnTimer = Timer.periodic(Duration(milliseconds: spawnInterval), (timer) {
      if (_roundTimeRemaining > 0 && _whirlingWords.length < 12) {
        _spawnWord();
      }
    });

    // <-- FIX: Spawn the initial words, guaranteeing targets.
    final random = Random();
    // Guarantee at least 2 target words at the start
    _spawnWord(forceTarget: true);
    _spawnWord(forceTarget: true);
    
    // Spawn a few more random words for the initial flurry
    for (int i = 0; i < 4; i++) {
      Future.delayed(Duration(milliseconds: i * 250 + random.nextInt(100)), () {
        if (mounted) _spawnWord();
      });
    }
    // <-- END FIX
  }

  bool _hasEnoughWordsOfType(GermanWordType type) {
    // We check for >= 10 in loading, so checking for 5 here is safe.
    final count = _wordPool.where((w) => w.wordType == type).length;
    return count >= 5;
  }

  void _spawnWord({bool forceTarget = false}) { // <-- FIX: Added forceTarget
    if (_wordPoolIndex >= _wordPool.length) {
      _wordPool.shuffle();
      _wordPoolIndex = 0;
    }

    final maxRadius = min(_whirlAreaSize.width, _whirlAreaSize.height) / 2.0;
    if (maxRadius <= 50) {
      return;
    }

    final random = Random();

    final Set<String> onScreenWords =
        Set<String>.from(_whirlingWords.map((w) => w.word.word.trim().toLowerCase()));

    // <-- FIX: Smarter spawn logic to guarantee targets if needed
    bool shouldSpawnTarget;
    if (forceTarget) {
      shouldSpawnTarget = true;
    } else {
      // Check how many are on screen
      final unTappedTargetCount = _whirlingWords
          .where((w) => !w.isTapped && w.word.wordType == _currentTargetType)
          .length;

      if (unTappedTargetCount < 2) {
        // We are below the minimum, force a target to spawn
        shouldSpawnTarget = true;
        debugPrint("[WHIRL] Forcing target spawn. Count: $unTappedTargetCount");
      } else {
        // We are at or above the minimum, use random chance
        shouldSpawnTarget = random.nextDouble() < 0.4;
      }
    }
    // <-- END FIX

    GermanWord? selectedWord;
    int searchStartIndex = _wordPoolIndex;
    int maxAttempts = _wordPool.length;

    if (shouldSpawnTarget) {
      for (int i = 0; i < maxAttempts; i++) {
        int currentIndex = (searchStartIndex + i) % _wordPool.length;
        final candidateWord = _wordPool[currentIndex];
        final cleanWord = candidateWord.word.trim().toLowerCase();

        if (candidateWord.wordType == _currentTargetType &&
            !onScreenWords.contains(cleanWord)) {
          selectedWord = candidateWord;
          _wordPoolIndex = currentIndex + 1;
          break;
        }
      }
    }

    // If we *tried* to spawn a target but failed (e.g., all on-screen)
    // or if we decided to spawn a non-target...
    if (selectedWord == null) {
      for (int i = 0; i < maxAttempts; i++) {
        int currentIndex = (searchStartIndex + i) % _wordPool.length;
        final candidateWord = _wordPool[currentIndex];
        final cleanWord = candidateWord.word.trim().toLowerCase();

        // Only spawn a non-target if we weren't forced to spawn a target
        if (!forceTarget && candidateWord.wordType != _currentTargetType &&
            !onScreenWords.contains(cleanWord)) {
          selectedWord = candidateWord;
          _wordPoolIndex = currentIndex + 1;
          break;
        }
      }
    }

    // Final fallback: just grab the next available unique word
    if (selectedWord == null) {
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

    if (selectedWord == null) {
      debugPrint("[WHIRL] Could not find a unique word to spawn. Skipping.");
      return;
    }

    final innerRadiusMin = 0.25;
    final innerRadiusMax = 0.50;
    final outerRadiusMin = 0.60;
    final outerRadiusMax = 0.90;

    final double radius;
    final bool isInnerBand;
    if (random.nextBool()) {
      radius =
          innerRadiusMin + random.nextDouble() * (innerRadiusMax - innerRadiusMin);
      isInnerBand = true;
    } else {
      radius =
          outerRadiusMin + random.nextDouble() * (outerRadiusMax - outerRadiusMin);
      isInnerBand = false;
    }

    double newAngle;
    int attempt = 0;
    bool collision;

    final cardWidth = (maxRadius * 0.4).clamp(80.0, 120.0);

    final minAngleSeparation = (maxRadius > 0 && innerRadiusMin > 0)
        ? 2 * asin((cardWidth / 2) / (innerRadiusMin * maxRadius))
        : 0.5; // Fallback if radius is 0

    do {
      collision = false;
      newAngle = random.nextDouble() * 2 * pi;

      for (final existingWord in _whirlingWords) {
        final bool existingIsInner = existingWord.radius < 0.55;

        if (isInnerBand == existingIsInner) {
          double angleDiff = (newAngle - existingWord.angle).abs();
          if (angleDiff > pi) {
            angleDiff = 2 * pi - angleDiff;
          }

          if (angleDiff < minAngleSeparation) {
            collision = true;
            break;
          }
        }
      }
      attempt++;
    } while (collision && attempt < 40);

    if (collision) {
      debugPrint("[WHIRL] Could not find a non-colliding spot. Skipping.");
      return;
    }

    final whirlingWord = WhirlingWord(
      word: selectedWord,
      angle: newAngle,
      radius: radius,
      speed: (0.5 + random.nextDouble() * 0.5) * _baseSpeed,
    );

    setState(() {
      _whirlingWords.add(whirlingWord);
    });
  }

  void _onWordTapped(WhirlingWord whirlingWord) {
    if (whirlingWord.isTapped || _isEndingRound) return; // <-- FIX: Don't allow taps if round is ending

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

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          whirlingWord.shouldRemove = true;
          _whirlingWords.remove(whirlingWord);
        });
      }
    });
  }

  // --- This hint logic correctly uses the API data ---
  String _generateEducationalHint(GermanWord word,
      {required bool isCorrect, GermanWordType? tappedTargetType}) {
    final typeName = _wordTypes[word.wordType]?.label ?? 'Wort';
    
    // Get the new, reliable API data
    final apiData = word.apiEnrichment;
    final patternData = apiData?.inflectionsPattern;
    final definitions = apiData?.definitions ?? [];

    if (isCorrect) {
      // --- SUCCESS HINTS ---
      List<String> hints = ['✓ ${typeName}!'];
      String? definitionHint =
          definitions.isNotEmpty ? '"${definitions.first}"' : null;

      switch (word.wordType) {
        case GermanWordType.substantiv:
          String? plural;
          // Try to get plural from pattern.de data first
          if (patternData != null && patternData['conjugation']?['Plural']?['Nominativ'] is String) {
            plural = patternData['conjugation']['Plural']['Nominativ'] as String;
          }
          // Fallback to old plural field
          else if (word.plural != null &&
              word.plural!.isNotEmpty &&
              word.plural != '-') {
            plural = word.plural;
          }

          if (plural != null && plural.isNotEmpty && plural != word.word) {
            hints.add('Mehrzahl: $plural');
          } else if (word.nurImPlural) {
             hints.add('Nur Mehrzahl');
          }
          if (definitionHint != null) {
            hints.add(definitionHint);
          }
          return hints.join(' • ');

        case GermanWordType.verb:
          String? ichForm;
          if (patternData?['conjugation']?['Präsens']?['ich'] is String) {
            ichForm = patternData!['conjugation']['Präsens']['ich'] as String;
          }

          if (ichForm != null) {
            hints.add('z.B. ich $ichForm');
          }
          if (definitionHint != null) {
            hints.add(definitionHint);
          }
          return hints.join(' • ');

        case GermanWordType.adjektiv:
          String? komparativ;
          if (patternData?['comparative'] is String) {
            komparativ = patternData!['comparative'] as String;
          }

          if (komparativ != null && komparativ.isNotEmpty && komparativ != '-') {
            hints.add('Steigerung: $komparativ');
          }
          if (definitionHint != null) {
            hints.add(definitionHint);
          }
          return hints.join(' • ');

        default:
          if (definitionHint != null) {
            return '✓ ${typeName}! • $definitionHint';
          }
          return '✓ Richtig! ${word.word} ist ein ${typeName}';
      }
    } else {
      // --- FAILURE HINTS ---
      final correctTypeName = _wordTypes[_currentTargetType!]?.label ?? 'Wort';
      switch (word.wordType) {
        case GermanWordType.substantiv:
          return "✗ ${word.displayName} ist ein Nomen (hat Artikel), kein $correctTypeName";
        case GermanWordType.verb:
          return '✗ ${word.word} ist ein Verb (Tun-Wort), kein $correctTypeName';
        case GermanWordType.adjektiv:
          return '✗ ${word.word} ist ein Adjektiv (Wie-Wort), kein $correctTypeName';
        default:
          if (definitions.isNotEmpty) {
            return '✗ $typeName: "${definitions.first}", kein $correctTypeName';
          }
          return '✗ ${word.word} ist ein $typeName, kein $correctTypeName';
      }
    }
  }

  void _showHint(String message, bool isError) {
    final newHint = HintMessage(text: message, isError: isError);
    _hintQueue.add(newHint);
    if (_currentHintMessage == null) {
      _processHintQueue();
    }
  }

  void _processHintQueue() {
    if (_currentHintMessage != null || _hintQueue.isEmpty) {
      return;
    }

    _hintDisplayTimer?.cancel();
    _currentHintMessage = _hintQueue.removeFirst();

    _visibleHints.insert(0, _currentHintMessage!);
    _hintListKey.currentState
        ?.insertItem(0, duration: const Duration(milliseconds: 400));

    _hintDisplayTimer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted) return;

      if (_visibleHints.isNotEmpty) {
        final removedHint = _visibleHints.removeAt(0);
        _hintListKey.currentState?.removeItem(
            0,
            (context, animation) =>
                _buildHintToast(removedHint, animation, isRemoving: true),
            duration: const Duration(milliseconds: 300));
      }

      _currentHintMessage = null;
      _processHintQueue();
    });
  }

  void _onCorrectTap(WhirlingWord whirlingWord) {
    _audioService.playSound('success');
    _pulseController.forward(from: 0);

    _secondsSinceLastCorrectTap = 0;
    _showAutoHints = false;

    _showHint(
      _generateEducationalHint(whirlingWord.word, isCorrect: true),
      false,
    );

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
        'gradeLevel': widget.gradeLevel.index + 1,
        'wordType': whirlingWord.word.wordType.toString().split('.').last,
      },
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _checkRoundCompletion(); // This is the safe place to call this
    });
  }

  void _onIncorrectTap(WhirlingWord whirlingWord) {
    _audioService.playSound('failure');

    _showHint(
      _generateEducationalHint(
        whirlingWord.word,
        isCorrect: false,
        tappedTargetType: _currentTargetType,
      ),
      true,
    );

    setState(() {
      _streak = 0;
      _score = max(0, _score - 5);
      _roundHistory.last.incorrectTaps++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.wordType,
      baseWord: whirlingWord.word.word,
      wasCorrect: false,
      metadata: {
        'game': 'word_type_whirl',
        'round': _round,
        'gradeLevel': widget.gradeLevel.index + 1,
        'wordType': whirlingWord.word.wordType.toString().split('.').last,
      },
    );
  }

  void _endRound() {
    if (_isEndingRound) return;
    _isEndingRound = true;
    _roundTimer?.cancel();
    _spawnTimer?.cancel();

    _showAutoHints = false;
    _secondsSinceLastCorrectTap = 0;

    final missedCount = _whirlingWords
        .where(
            (w) => !w.isTapped && w.word.wordType == _currentTargetType)
        .length;

    if (mounted) {
      _roundHistory.last.missedWords = missedCount;
    }

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

    if (mounted) {
      final gameProvider = context.read<GameProvider>();
      gameProvider.recordLevelWin(
        gameType: 'word_type_whirl_game',
        scoreGained: _score,
        difficulty: widget.gradeLevel.index + 1,
        wasSuccessful: accuracy >= 70, // e.g., 2+ stars to pass
      );
    }

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
                          _buildStatsBar(s),
                          _buildTargetBanner(s, selectedFontFamily),
                          Expanded(
                            child: _buildWhirlArea(selectedFontFamily),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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

  Widget _buildHintOverlay() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        child: AnimatedList(
          key: _hintListKey,
          initialItemCount: _visibleHints.length,
          itemBuilder: (context, index, animation) {
            return _buildHintToast(_visibleHints[index], animation);
          },
          shrinkWrap: true,
          reverse: true,
        ),
      ),
    );
  }

  Widget _buildHintToast(HintMessage hint, Animation<double> animation,
      {bool isRemoving = false}) {
    final color = hint.isError ? SpaceTheme.rocketRed : SpaceTheme.alienGreen;
    final icon =
        hint.isError ? Icons.cancel_outlined : Icons.check_circle_outline;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.5),
          end: const Offset(0, 0),
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: CurvedAnimation(
              parent: animation, curve: isRemoving ? Curves.easeOut : Curves.easeIn),
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
        if (constraints.biggest != _whirlAreaSize) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _whirlAreaSize = constraints.biggest;
              });
            }
          });
        }

        final centerX = _whirlAreaSize.width / 2;
        final centerY = _whirlAreaSize.height / 2;
        final maxRadius = min(_whirlAreaSize.width, _whirlAreaSize.height) / 2.0;

        if (maxRadius <= 0) return const SizedBox.shrink();

        return AnimatedBuilder(
          animation: _whirlController,
          builder: (context, child) {
            final double elapsedSeconds =
                _whirlStopwatch.elapsedMilliseconds / 1000.0;
            final double baseRadsPerSec = pi / 4;

            return Stack(
              clipBehavior: Clip.none,
              children: [
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
                ..._whirlingWords.map((whirlingWord) {
                  final currentAngle = whirlingWord.angle +
                      (elapsedSeconds * baseRadsPerSec * whirlingWord.speed);

                  final x = centerX +
                      cos(currentAngle) * (whirlingWord.radius * maxRadius);
                  final y = centerY +
                      sin(currentAngle) * (whirlingWord.radius * maxRadius);

                  final cardWidth = (maxRadius * 0.4).clamp(90.0, 130.0);
                  final cardHeight = (cardWidth * 0.5).clamp(45.0, 65.0);

                  return Positioned(
                    key: ValueKey<String>(whirlingWord.word.id),
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
      borderColor = Colors.white.withOpacity(0.3);
      textColor = Colors.white;
    }

    return GestureDetector(
      onTap: () => _onWordTapped(whirlingWord),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: cardWidth,
        height: cardHeight,
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
                    whirlingWord.word.displayName,
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
}