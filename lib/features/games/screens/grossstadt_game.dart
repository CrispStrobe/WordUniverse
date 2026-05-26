// lib/features/games/screens/grossstadt_game.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';
import '../widgets/space_background.dart';
import '../models/game_outcome.dart';

/// Großstadt Game - Teaching German capitalization rules
/// Refactored: Plain "Groß vs Klein" logic, All-Caps display, Contextual highlighting.
class GrossstadtGame extends StatefulWidget {
  final GradeLevel gradeLevel;
  const GrossstadtGame({super.key, required this.gradeLevel});

  @override
  State<GrossstadtGame> createState() => _GrossstadtGameState();
}

/// Represents a single item flowing on the conveyor belt
class CapitalizationItem {
  final String prefix;   // Text before the target word
  final String target;   // The word to judge
  final String suffix;   // Text after the target word
  final bool shouldBeCapitalized;
  final String rule;
  final String explanation;
  final int difficulty;
  final String wordId; // For SRI tracking
  final String lemma;  // The base form for SRI

  CapitalizationItem({
    this.prefix = '',
    required this.target,
    this.suffix = '',
    required this.shouldBeCapitalized,
    required this.rule,
    required this.explanation,
    required this.difficulty,
    required this.wordId,
    required this.lemma,
  });
}

enum FeedbackState { none, correct, incorrect }

class _GrossstadtGameState extends State<GrossstadtGame>
    with TickerProviderStateMixin {
  // Services
  late VocabularyService _vocabularyService;
  late SriService _sriService;
  late AudioService _audioService;
  late GameProvider _gameProvider;

  // Game State
  bool _isLoading = true;
  final List<CapitalizationItem> _itemQueue = [];
  CapitalizationItem? _currentItem;
  int _score = 0;
  int _itemsCompleted = 0;
  int _totalItems = 20;
  int _combo = 0;
  int _maxCombo = 0;
  int _level = 1;

  // Conveyor belt animation
  late AnimationController _conveyorController;
  late Animation<double> _conveyorAnimation;
  double _conveyorSpeed = 4.0; // seconds per item

  // Feedback
  FeedbackState _feedbackState = FeedbackState.none;
  String _feedbackMessage = '';

  // Animation Controllers
  late AnimationController _successController;
  late AnimationController _errorController;

  void _log(String message) {
    debugPrint('[GROSSSTADT] $message');
  }

  @override
  void initState() {
    super.initState();

    _conveyorController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _conveyorSpeed.toInt()),
    );

    _conveyorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _conveyorController, curve: Curves.linear),
    );

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _errorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGame();
    });
  }

  @override
  void dispose() {
    _conveyorController.dispose();
    _successController.dispose();
    _errorController.dispose();
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

    _loadLevel();
  }

  void _loadLevel() {
    _score = 0;
    _itemsCompleted = 0;
    _combo = 0;
    _maxCombo = 0;
    _level = 1;
    _conveyorSpeed = 4.0;

    _generateItemQueue();
    _showNextItem();

    setState(() => _isLoading = false);
  }

  /// Generate capitalization items from vocabulary words
  void _generateItemQueue() {
    _log('========================================');
    _log('Starting item generation');
    _log('========================================');
    
    _itemQueue.clear();

    // Get appropriate words for the grade level
    final verbs = _getWordsForGame(GermanWordType.verb, 15);
    final adjectives = _getWordsForGame(GermanWordType.adjektiv, 12);
    final nouns = _getWordsForGame(GermanWordType.substantiv, 12);

    _log('Available: ${verbs.length} verbs, ${adjectives.length} adjectives, ${nouns.length} nouns');
    _log('');

    // Generate variants
    _log('--- GENERATING VERB VARIANTS ---');
    for (final word in verbs) {
      final variants = _generateVerbVariants(word);
      _itemQueue.addAll(variants);
      if (variants.isNotEmpty) {
        _log('  Generated ${variants.length} variants for "${word.lemma}"');
      }
    }

    _log('');
    _log('--- GENERATING ADJECTIVE VARIANTS ---');
    for (final word in adjectives) {
      final variants = _generateAdjectiveVariants(word);
      _itemQueue.addAll(variants);
      if (variants.isNotEmpty) {
        _log('  Generated ${variants.length} variants for "${word.lemma}"');
      }
    }

    _log('');
    _log('--- GENERATING NOUN VARIANTS ---');
    for (final word in nouns) {
      final variants = _generateNounVariants(word);
      _itemQueue.addAll(variants);
      if (variants.isNotEmpty) {
        _log('  Generated ${variants.length} variants for "${word.word}"');
      }
    }

    // Shuffle and limit to total items
    _itemQueue.shuffle();
    if (_itemQueue.length > _totalItems) {
      _itemQueue.removeRange(_totalItems, _itemQueue.length);
    }

    _log('');
    _log('========================================');
    _log('Total items generated: ${_itemQueue.length}');
    _log('========================================');
  }

  /// Check if a verb is in infinitive form (base form)
  bool _isInfinitive(String verb) {
    final lower = verb.toLowerCase();
    return lower.endsWith('en') || lower.endsWith('ern') || lower.endsWith('eln');
  }

  /// Get clean adjective base form by stripping common endings
  String _getAdjectiveBase(String adjective) {
    String base = adjective.toLowerCase();
    
    // Remove common inflectional endings
    if (base.endsWith('es')) {
      base = base.substring(0, base.length - 2);
    } else if (base.endsWith('em') || base.endsWith('en') || base.endsWith('er')) {
      base = base.substring(0, base.length - 2);
    } else if (base.endsWith('e')) {
      base = base.substring(0, base.length - 1);
    }
    
    // Handle special cases where -el/-er are part of the stem
    if (base.length < 3) {
      // Too short, probably removed too much
      return adjective.toLowerCase();
    }
    
    return base;
  }

  List<GermanWord> _getWordsForGame(GermanWordType type, int count) {
    final allWords = _vocabularyService
        .getAllWords(_gameProvider)
        .where((w) =>
            w.wordType == type &&
            !w.word.contains(' ') && // Single words only
            w.word.length >= 3 &&
            w.gradeLevel <= widget.gradeLevel.index + 2)
        .toList();

    // Additional filtering based on word type
    List<GermanWord> filtered;
    if (type == GermanWordType.verb) {
      // For verbs: Only keep infinitives (lemma ends in -en, -ern, -eln)
      filtered = allWords.where((w) => _isInfinitive(w.lemma)).toList();
      _log('Filtered verbs: ${filtered.length} infinitives out of ${allWords.length} total');
    } else if (type == GermanWordType.adjektiv) {
      // For adjectives: Prefer words with clean lemmas
      filtered = allWords;
    } else {
      // For nouns: All are okay but filter out proper nouns that are just names
      filtered = allWords.where((w) {
        // Keep common nouns, filter out single-letter names or very short proper nouns
        if (w.word.length < 3) return false;
        // Basic check: if it's a proper noun but has no article/genus info, might be a name
        final isLikelyProperName = w.word[0] == w.word[0].toUpperCase() && 
                                    w.article == null && 
                                    w.genus == null &&
                                    w.word.length < 6;
        return !isLikelyProperName;
      }).toList();
    }

    filtered.shuffle();
    return filtered.take(count).toList();
  }

  // --- MORPHOLOGY HELPERS ---

  /// Helper to get present tense conjugated form from API data
  String? _getConjugatedForm(GermanWord word, String person) {
    _log('    → Looking for conjugation: $person form of "${word.lemma}"');
    
    // Try API data first
    if (word.wiktionaryInflections.isNotEmpty) {
      _log('      → Found ${word.wiktionaryInflections.length} inflections in data');
      
      for (final inflection in word.wiktionaryInflections) {
        final formText = inflection['form_text'] as String?;
        final tagsRaw = inflection['tags'];
        
        if (formText == null || tagsRaw == null) continue;
        
        // Handle both String and List<dynamic> for tags
        String tagString;
        if (tagsRaw is String) {
          tagString = tagsRaw.toLowerCase();
        } else if (tagsRaw is List) {
          tagString = tagsRaw.join('|').toLowerCase();
        } else {
          continue;
        }
        
        // Must be present tense and match person
        if (!tagString.contains('present') && !tagString.contains('pres')) continue;
        if (tagString.contains('past') || tagString.contains('participle')) continue;
        
        bool matches = false;
        if (person == 'ich' && tagString.contains('first-person') && tagString.contains('singular')) {
          matches = true;
        } else if (person == 'du' && tagString.contains('second-person') && tagString.contains('singular')) {
          matches = true;
        } else if (person == 'wir' && tagString.contains('first-person') && tagString.contains('plural')) {
          matches = true;
        }
        
        if (matches) {
          _log('      ✓ Found: "$formText" (tags: $tagString)');
          return formText;
        }
      }
      _log('      ✗ No matching present tense form found in inflections');
    }

    // Fallback: Basic regular verb conjugation
    _log('      → Using fallback conjugation');
    final lemma = word.lemma.toLowerCase();
    if (lemma.endsWith('en')) {
      final stem = lemma.substring(0, lemma.length - 2);
      String result;
      if (person == 'ich') {
        result = '${stem}e';
      } else if (person == 'du') {
        result = '${stem}st';
      } else if (person == 'wir') {
        result = lemma; // Same as infinitive
      } else {
        return null;
      }
      _log('      ✓ Fallback: "$result"');
      return result;
    }
    
    _log('      ✗ Cannot conjugate (lemma doesn\'t end in -en)');
    return null;
  }

  /// Helper to create correct nominalized adjectives
  String _nominalizeAdjective(String adjective) {
    String base = _getAdjectiveBase(adjective);
    
    // Add endings for "etwas [Gutes]"
    if (base.endsWith('el') || base.endsWith('er')) {
      return '${base}es'; // teuer -> teures, dunkel -> dunkeles
    } else {
      return '${base}es'; // gut -> gutes
    }
  }

  /// Get gender-appropriate possessive article.
  /// [nounArticle] is the already-normalised definite article ("DER"/"DIE"/"DAS").
  String _getPossessiveArticle(String baseArticle, String nounArticle) {
    _log('    → Noun article: $nounArticle, base possessive: $baseArticle');
    // "DIE" covers both feminine singular and all-gender plural.
    final needsEEnding = nounArticle == 'DIE';
    String result = baseArticle;
    if (needsEEnding) {
      if (baseArticle == 'MEIN') result = 'MEINE';
      else if (baseArticle == 'DEIN') result = 'DEINE';
      else if (baseArticle == 'KEIN') result = 'KEINE';
      else if (baseArticle == 'UNSER') result = 'UNSERE';
    }
    _log('    ✓ Using: $result');
    return result;
  }

  // --- VARIANT GENERATORS ---

  List<CapitalizationItem> _generateVerbVariants(GermanWord word) {
    final items = <CapitalizationItem>[];
    
    // Skip if lemma is not an infinitive
    if (!_isInfinitive(word.lemma)) {
      _log('  Verb: "${word.word}" - SKIPPED (lemma "${word.lemma}" is not infinitive)');
      return items;
    }
    
    _log('  Verb: "${word.word}" (lemma: "${word.lemma}")');
    
    final infinitive = word.lemma.toLowerCase(); 

    // 1. Nominalization (Groß) -> "DAS LAUFEN"
    final articles = ['DAS', 'BEIM', 'ZUM']; 
    final article = articles[Random().nextInt(articles.length)];
    
    items.add(CapitalizationItem(
      prefix: '$article ',
      target: infinitive,
      shouldBeCapitalized: true,
      rule: 'nominalized_verb',
      explanation: 'Nomen-Signal "$article" → Großschreibung',
      difficulty: 2,
      wordId: word.id,
      lemma: word.lemma,
    ));
    _log('    ✓ Created: "$article $infinitive" (capitalized)');

    // 2. Conjugated (Klein) -> "ICH LAUFE"
    final pronouns = ['ICH', 'DU', 'WIR'];
    final pronoun = pronouns[Random().nextInt(pronouns.length)];
    final conjugated = _getConjugatedForm(word, pronoun.toLowerCase());

    if (conjugated != null) {
      items.add(CapitalizationItem(
        prefix: '$pronoun ',
        target: conjugated,
        shouldBeCapitalized: false,
        rule: 'conjugated_verb',
        explanation: 'Verben im Satz → Kleinschreibung',
        difficulty: 1,
        wordId: word.id,
        lemma: word.lemma,
      ));
      _log('    ✓ Created: "$pronoun $conjugated" (lowercase)');
    } else {
      _log('    ✗ Skipped conjugated form (could not conjugate)');
    }

    // 3. Modal + Infinitive (Klein) -> "KANN LAUFEN"
    final modals = ['KANN', 'MUSS', 'WILL', 'DARF'];
    final modal = modals[Random().nextInt(modals.length)];
    
    items.add(CapitalizationItem(
      prefix: '$modal ',
      target: infinitive,
      shouldBeCapitalized: false,
      rule: 'infinitive_verb',
      explanation: 'Verben (Infinitiv) → Kleinschreibung',
      difficulty: 1,
      wordId: word.id,
      lemma: word.lemma,
    ));
    _log('    ✓ Created: "$modal $infinitive" (lowercase)');

    return items;
  }

  List<CapitalizationItem> _generateAdjectiveVariants(GermanWord word) {
    final items = <CapitalizationItem>[];
    
    // Get clean base form
    final adjBase = _getAdjectiveBase(word.lemma);
    _log('  Adjective: "${word.word}" (lemma: "${word.lemma}", base: "$adjBase")');

    // 1. Nominalization (Groß) -> "ETWAS GUTES"
    final indefinites = ['ETWAS', 'NICHTS', 'VIEL', 'WENIG'];
    final indefinite = indefinites[Random().nextInt(indefinites.length)];
    final nominalizedForm = _nominalizeAdjective(word.lemma);

    items.add(CapitalizationItem(
      prefix: '$indefinite ',
      target: nominalizedForm,
      shouldBeCapitalized: true,
      rule: 'nominalized_adjective',
      explanation: 'Nach "$indefinite" → Großschreibung',
      difficulty: 3,
      wordId: word.id,
      lemma: adjBase, // Use clean base for SRI
    ));
    _log('    ✓ Created: "$indefinite $nominalizedForm" (capitalized)');

    // 2. Predicative (Klein) -> "IST GUT"
    final copulas = ['IST', 'WAR', 'SIND'];
    final copula = copulas[Random().nextInt(copulas.length)];

    items.add(CapitalizationItem(
      prefix: '$copula ',
      target: adjBase, // Use clean base
      shouldBeCapitalized: false,
      rule: 'predicative_adjective',
      explanation: 'Adjektive (Wie ist es?) → Kleinschreibung',
      difficulty: 1,
      wordId: word.id,
      lemma: adjBase, // Use clean base for SRI
    ));
    _log('    ✓ Created: "$copula $adjBase" (lowercase)');

    return items;
  }

  List<CapitalizationItem> _generateNounVariants(GermanWord word) {
    final items = <CapitalizationItem>[];
    final noun = word.word;
    _log('  Noun: "$noun" (article: ${word.article}, genus: ${word.genus})');
    
    // Get proper article
    String article = (word.article ?? 'das').toUpperCase();
    if (!['DER', 'DIE', 'DAS'].contains(article.toUpperCase())) {
      article = 'DAS'; // Default fallback
    }

    // 1. Standard Noun (Groß) -> "DER TISCH"
    items.add(CapitalizationItem(
      prefix: '$article ',
      target: noun,
      shouldBeCapitalized: true,
      rule: 'noun_standard',
      explanation: 'Nomen (Namen für Dinge) → Großschreibung',
      difficulty: 1,
      wordId: word.id,
      lemma: word.lemma,
    ));
    _log('    ✓ Created: "$article $noun" (capitalized)');

    // 2. Possessive Context (Groß) -> "MEIN TISCH" / "MEINE STIRN"
    final possessiveBases = ['MEIN', 'DEIN', 'UNSER', 'KEIN'];
    final basePoss = possessiveBases[Random().nextInt(possessiveBases.length)];
    final poss = _getPossessiveArticle(basePoss, article);

    items.add(CapitalizationItem(
      prefix: '$poss ',
      target: noun,
      shouldBeCapitalized: true,
      rule: 'noun_possessive',
      explanation: 'Nach "$poss" → Großschreibung',
      difficulty: 1,
      wordId: word.id,
      lemma: word.lemma,
    ));
    _log('    ✓ Created: "$poss $noun" (capitalized)');

    return items;
  }

  // --- GAMEPLAY LOGIC ---

  void _showNextItem() {
    if (_itemsCompleted >= _totalItems || _itemQueue.isEmpty) {
      _showGameOver();
      return;
    }

    setState(() {
      _currentItem = _itemQueue.removeAt(0);
      _feedbackState = FeedbackState.none;
      _feedbackMessage = '';
    });

    _conveyorController.reset();
    _conveyorController.forward().then((_) {
      if (_feedbackState == FeedbackState.none && mounted) {
        _handleMiss();
      }
    });
  }

  void _handleChoice(bool chooseCapitalized) {
    if (_currentItem == null || _feedbackState != FeedbackState.none) return;

    _conveyorController.stop();
    final isCorrect = chooseCapitalized == _currentItem!.shouldBeCapitalized;

    setState(() {
      _feedbackState = isCorrect ? FeedbackState.correct : FeedbackState.incorrect;
      _feedbackMessage = _currentItem!.explanation;
    });

    if (isCorrect) {
      _handleCorrectAnswer();
    } else {
      _handleIncorrectAnswer();
    }
  }

  void _handleCorrectAnswer() {
    _successController.forward().then((_) => _successController.reset());
    _audioService.playSound('success');
    HapticFeedback.lightImpact();

    _combo++;
    if (_combo > _maxCombo) _maxCombo = _combo;

    final basePoints = 100 + (_currentItem!.difficulty * 20);
    final comboMultiplier = 1.0 + (_combo / 10);
    final points = (basePoints * comboMultiplier).round();

    setState(() {
      _score += points;
      _itemsCompleted++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentItem!.lemma,
      wasCorrect: true,
      metadata: {
        'rule': _currentItem!.rule,
        'responseTimeMs': ((1.0 - _conveyorAnimation.value) * _conveyorSpeed * 1000).round(),
        'combo': _combo,
      },
    );

    if (_itemsCompleted % 5 == 0) {
      _levelUp();
    }

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _showNextItem();
    });
  }

  void _handleIncorrectAnswer() {
    _errorController.forward().then((_) => _errorController.reset());
    _audioService.playSound('failure');
    HapticFeedback.heavyImpact();

    setState(() {
      _combo = 0;
      _score = max(0, _score - 50);
      _itemsCompleted++;
    });

    _sriService.recordResponse(
      skillType: LanguageSkillType.spelling,
      baseWord: _currentItem!.lemma,
      wasCorrect: false,
      metadata: {
        'rule': _currentItem!.rule,
      },
    );

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) _showNextItem();
    });
  }

  void _handleMiss() {
    final s = S.of(context);
    setState(() {
      _feedbackState = FeedbackState.incorrect;
      _feedbackMessage = s?.gameTooSlow ?? 'Zu langsam!';
      _combo = 0;
      _itemsCompleted++;
    });

    _audioService.playSound('failure');
    HapticFeedback.heavyImpact();

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _showNextItem();
    });
  }

  void _levelUp() {
    setState(() {
      _level++;
      _conveyorSpeed = max(1.5, _conveyorSpeed * 0.85);
      _conveyorController.duration = Duration(milliseconds: (_conveyorSpeed * 1000).toInt());
    });
    _audioService.playSound('levelup');
  }

  void _showGameOver() {
    final s = S.of(context);
    if (s == null) return;

    _gameProvider.reportOutcome(GameOutcome(
      gameType: 'grossstadt_game',
      difficulty: widget.gradeLevel.index + 1,
      score: _score,
      wasSuccessful: _score > 0,
    ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        title: Text(s.gameOver, style: SpaceTheme.headlineStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${s.gameScore}: $_score', style: SpaceTheme.bodyStyle),
            Text(s.gameMaxComboLine(_maxCombo), style: SpaceTheme.bodyStyle),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _loadLevel();
            },
            child: Text(s.gameReplay, style: SpaceTheme.buttonStyle),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.gameDone, style: SpaceTheme.buttonStyle),
          ),
        ],
      ),
    );
  }

  // --- UI BUILDING --- (rest of the code stays the same)
  
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final selectedFontFamily = context.watch<GameProvider>().selectedFontFamily;

    if (_isLoading || s == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildUnifiedTopBar(s),
              Expanded(
                child: _buildGameArea(s, selectedFontFamily),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedTopBar(S s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(
            color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Semantics(
            label: 'Zurück',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              onPressed: () {
                _conveyorController.stop();
                Navigator.of(context).pop();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            label: 'Stufe $_level',
            container: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SpaceTheme.nebulaPurple.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  s.gameLvlBadge(_level),
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: SpaceTheme.nebulaPurple,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Punkte: $_score',
            child: _buildCompactStat(Icons.stars, '$_score', SpaceTheme.starYellow),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Fortschritt: $_itemsCompleted von $_totalItems',
            child: _buildCompactStat(Icons.check_circle_outline, '$_itemsCompleted/$_totalItems', SpaceTheme.cosmicPink),
          ),
          const Spacer(),
          if (_combo > 1)
            Semantics(
              label: 'Kombo mal $_combo',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SpaceTheme.planetOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SpaceTheme.planetOrange),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    s.gameCombo(_combo),
                    style: SpaceTheme.bodyStyle.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: SpaceTheme.planetOrange,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: SpaceTheme.bodyStyle.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameArea(S s, String selectedFontFamily) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              s.grossstadtTitle,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: AnimatedBuilder(
            animation: _conveyorAnimation,
            builder: (context, child) {
              return _buildConveyorBelt(selectedFontFamily);
            },
          ),
        ),
        _buildSortingArea(s),
      ],
    );
  }

  Widget _buildConveyorBelt(String selectedFontFamily) {
    if (_currentItem == null) {
      return const SizedBox.shrink();
    }

    final position = _conveyorAnimation.value;

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 100,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  SpaceTheme.nebulaPurple.withValues(alpha: 0.1),
                  SpaceTheme.nebulaPurple,
                  SpaceTheme.nebulaPurple.withValues(alpha: 0.1),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: MediaQuery.of(context).size.width * position - 150,
          top: 50,
          child: _buildMovingItem(selectedFontFamily),
        ),
      ],
    );
  }

  Widget _buildMovingItem(String selectedFontFamily) {
    final scale = _feedbackState == FeedbackState.correct
        ? 1.0 + (sin(_successController.value * pi) * 0.1)
        : 1.0;

    return AnimatedBuilder(
      animation: _errorController,
      builder: (context, child) {
        final shake = _feedbackState == FeedbackState.incorrect
            ? sin(_errorController.value * pi * 4) * 10
            : 0.0;

        return Transform.translate(
          offset: Offset(shake, 0),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getItemColor(),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _getItemColor().withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        fontFamily: selectedFontFamily,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      children: [
                        TextSpan(text: _currentItem!.prefix.toUpperCase()),
                        TextSpan(
                          text: _currentItem!.target.toUpperCase(),
                          style: TextStyle(
                            color: SpaceTheme.starYellow,
                            decoration: TextDecoration.underline,
                            decorationColor: SpaceTheme.starYellow,
                          ),
                        ),
                        TextSpan(text: _currentItem!.suffix.toUpperCase()),
                      ],
                    ),
                  ),
                  if (_feedbackMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _feedbackState == FeedbackState.correct
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _feedbackMessage,
                              style: TextStyle(
                                fontFamily: selectedFontFamily,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getItemColor() {
    switch (_feedbackState) {
      case FeedbackState.correct:
        return Colors.green.shade700;
      case FeedbackState.incorrect:
        return SpaceTheme.rocketRed;
      case FeedbackState.none:
        return SpaceTheme.cosmicPink;
    }
  }

  Widget _buildSortingArea(S s) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: _buildSortButton(
              icon: Icons.text_fields,
              label: s.grossstadtCapital,
              color: SpaceTheme.starYellow,
              onTap: () => _handleChoice(true),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildSortButton(
              icon: Icons.text_format,
              label: s.grossstadtLower,
              color: SpaceTheme.nebulaPurple,
              onTap: () => _handleChoice(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: label,
      button: true,
      enabled: _feedbackState == FeedbackState.none,
      child: GestureDetector(
        onTap: _feedbackState == FeedbackState.none ? onTap : null,
        child: AnimatedOpacity(
          opacity: _feedbackState == FeedbackState.none ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 48, color: Colors.white),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}