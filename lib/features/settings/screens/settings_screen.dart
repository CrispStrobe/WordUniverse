// lib/features/settings/screens/settings_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

import '../../../core/theme/space_theme.dart';
import '../../../core/services/debug_provider.dart';
import '../../../core/services/progress_service.dart';

// Import VocabularyService to get sources
import '../../../core/services/vocabulary_service.dart';
import '../../../core/services/sri_service.dart';

import '../../../shared/widgets/imprint_dialog.dart';

import '../../../generated/l10n.dart';

// We import this for the Grade definitions
import '../../../core/models/skill_category.dart';
import '../../games/providers/game_provider.dart';
import '../../games/widgets/space_background.dart';
// We import the dialog separately
import '../widgets/sri_statistics_dialog.dart';
import 'custom_subset_screen.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  
  late AnimationController _slideController;
  late List<Animation<Offset>> _settingAnimations;
  String currentLocale = 'en'; // Safe default
  bool _isLoading = false;
  bool _hasLoadedLocale = false; 

  // NEW: State for dynamic vocabulary sources
  Set<String> _availableSources = {};
  bool _sourcesLoaded = false;
  
  // NEW: Controllers for wildcard text fields
  final TextEditingController _includeController = TextEditingController();
  final TextEditingController _excludeController = TextEditingController();


  @override
  void initState() {
    super.initState();
    debugPrint("[SETTINGS] 🔧 initState() starting...");
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // FIX: Increased list size to 7 for the new settings card
    _settingAnimations = List.generate(7, (index) { // Was 6
      return Tween<Offset>(
        begin: const Offset(-1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Interval(
          (index * 0.1).clamp(0.0, 0.5),
          (0.4 + (index * 0.1)).clamp(0.1, 1.0),
          curve: Curves.easeOutCubic,
        ),
      ));
    });
    
    debugPrint("[SETTINGS] 🔧 initState() completed - 7 animations ready");
    _slideController.forward();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint("[SETTINGS] 🌍 didChangeDependencies() called");
    
    if (!_hasLoadedLocale) {
      _loadCurrentLocaleAndSettings();
      _hasLoadedLocale = true;
    }
  }

  Widget _buildCustomSetSelector(
    BuildContext context,
    GameProvider gameProvider,
    VocabularyService vocabService,
  ) {
    final customSets = vocabService.getCustomSets();
    final activeSetId = gameProvider.activeVocabularySetId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Dropdown to select the active set
        Text(
          S.of(context)!.taskActiveSetTitle, // You will need to add this to your S file
          style: SpaceTheme.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          S.of(context)!.taskActiveSetDesc, // You will need to add this to your S file
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 12,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: SpaceTheme.deepSpace.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: DropdownButton<String?>(
            value: activeSetId,
            isExpanded: true,
            underline: const SizedBox.shrink(), // Remove default underline
            dropdownColor: SpaceTheme.deepSpace,
            style: SpaceTheme.bodyStyle,
            onChanged: (String? newValue) {
              gameProvider.setActiveVocabularySetId(newValue);
            },
            items: [
              // "None" option
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  S.of(context)!.taskActiveSetNone, // You will need to add this
                  style: SpaceTheme.bodyStyle.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
              // List of custom sets
              ...customSets.map((set) {
                return DropdownMenuItem<String?>(
                  value: set.id,
                  child: Text(set.name),
                );
              }).toList(),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Button to manage/create sets
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.edit_rounded),
            label: Text(S.of(context)!.taskManageSets), // You will need to add this
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.cosmicPink,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CustomSubsetScreen(), // Navigate to the new screen
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // NEW: Helper to load vocab sources
  Future<void> _loadVocabularySources() async {
    if (_sourcesLoaded) return;
    
    try {
      final vocabService = context.read<VocabularyService>();
      final sources = vocabService.getAllAvailableSources();
      
      // Sort sources alphabetically for consistent display
      final sortedSources = sources.toList()..sort();
      
      if (mounted) {
        setState(() {
          _availableSources = sortedSources.toSet();
          _sourcesLoaded = true;
        });
        debugPrint("[SETTINGS] 📚 Loaded ${_availableSources.length} vocab sources");
      }
    } catch (e) {
      debugPrint("[SETTINGS] ❌ Error loading vocab sources: $e");
    }
  }
  
  @override
  void dispose() {
    debugPrint("[SETTINGS] 🗑️ Disposing settings screen");
    _slideController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  void _loadCurrentLocaleAndSettings() async {
    debugPrint("[SETTINGS] 📱 Loading current locale and settings...");
    
    try {
      final contextLocale = Localizations.localeOf(context).languageCode;
      debugPrint("[SETTINGS] 🌍 Context locale: $contextLocale");
      
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString('language');
      debugPrint("[SETTINGS] 💾 Saved locale from SharedPreferences: $savedLocale");
      
      setState(() {
        currentLocale = savedLocale ?? contextLocale;
      });
      
      debugPrint("[SETTINGS] ✅ Final locale set to: $currentLocale");
      
      await _loadAllSettings();
      
      // NEW: Load vocab sources *after* locale is set
      await _loadVocabularySources();
      
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Error loading locale/settings: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
      setState(() {
        currentLocale = 'en';
      });
    }
  }
  
  Future<void> _loadAllSettings() async {
    debugPrint("[SETTINGS] 📚 Loading all application settings...");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final keys = prefs.getKeys();
      debugPrint("[SETTINGS] 🔑 Found ${keys.length} preference keys: $keys");
      
      final soundEnabled = prefs.getBool('sound_enabled') ?? true;
      final musicEnabled = prefs.getBool('music_enabled') ?? true;
      final hintsEnabled = prefs.getBool('hints_enabled') ?? true;
      final hapticEnabled = prefs.getBool('haptic_enabled') ?? true;
      final puzzleTimerEnabled = prefs.getBool('puzzle_timer_enabled') ?? true;
      
      debugPrint("[SETTINGS] 🔊 Sound enabled: $soundEnabled");
      debugPrint("[SETTINGS] 🎵 Music enabled: $musicEnabled");
      debugPrint("[SETTINGS] 💡 Hints enabled: $hintsEnabled");
      debugPrint("[SETTINGS] 📳 Haptic enabled: $hapticEnabled");
      debugPrint("[SETTINGS] ⏱️ Puzzle timer enabled: $puzzleTimerEnabled");
      
      if (mounted) {
        final gameProvider = context.read<GameProvider>();
        gameProvider.setSoundEnabled(soundEnabled);
        gameProvider.setMusicEnabled(musicEnabled);
        gameProvider.setPuzzleTimer(puzzleTimerEnabled);
        
        debugPrint("[SETTINGS] ✅ Applied settings to GameProvider");
      }
      
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Error loading settings: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildAudioSettings(),
                      const SizedBox(height: 20),
                      _buildGameplaySettings(),
                      const SizedBox(height: 20),
                      // NEW: Add the task customization card
                      _buildTaskCustomizationSettings(),
                      const SizedBox(height: 20),
                      _buildLanguageSettings(),
                      const SizedBox(height: 20),
                      _buildDifficultySettings(),
                      const SizedBox(height: 20),
                      _buildProgressSettings(),
                      const SizedBox(height: 20),
                      _buildAboutSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E2235),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              debugPrint("[SETTINGS] 🔙 Back button pressed");
              Navigator.of(context).pop();
            },
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 28,
            ),
            style: IconButton.styleFrom(
              backgroundColor: SpaceTheme.deepSpace.withOpacity(0.8),
              padding: const EdgeInsets.all(12),
            ),
          ),
          
          const SizedBox(width: 20),
          
          Expanded(
            child: Text(
              S.of(context)!.settings,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 32),
            ),
          ),
          
          const Icon(
            Icons.settings,
            color: SpaceTheme.starYellow,
            size: 32,
          ),
        ],
      ),
    );
  }
  
  Widget _buildAudioSettings() {
    return SlideTransition(
      position: _settingAnimations[0],
      child: _buildSettingsCard(
        title: S.of(context)!.audioSettings,
        icon: Icons.volume_up,
        children: [
          Consumer<GameProvider>(
            builder: (context, gameProvider, child) {
              return Column(
                children: [
                  _buildSwitchTile(
                    title: S.of(context)!.sound,
                    subtitle: S.of(context)!.soundEffects,
                    value: gameProvider.soundEnabled,
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 🔊 Sound setting changed to: $value");
                      gameProvider.setSoundEnabled(value);
                      _saveSetting('sound_enabled', value);
                    },
                    icon: Icons.music_note,
                  ),
                  
                  _buildSwitchTile(
                    title: S.of(context)!.music,
                    subtitle: S.of(context)!.backgroundMusicDesc,
                    value: gameProvider.musicEnabled,
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 🎵 Music setting changed to: $value");
                      gameProvider.setMusicEnabled(value);
                      _saveSetting('music_enabled', value);
                    },
                    icon: Icons.library_music,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildGameplaySettings() {
    return SlideTransition(
      position: _settingAnimations[1],
      child: _buildSettingsCard(
        title: S.of(context)!.gameplay,
        icon: Icons.games,
        children: [
          Consumer2<GameProvider, DebugProvider>(
            builder: (context, gameProvider, debugProvider, child) {
              final isUnlocked = gameProvider.isFullVersionUnlocked || debugProvider.isPaidUnlockedForced;
            
              return Column(
                children: [
                  _buildSwitchTile(
                    title: S.of(context)!.adaptiveDifficulty, 
                    subtitle: S.of(context)!.adjustProblems,
                    value: gameProvider.useAdaptiveDifficulty,
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 🧠 Adaptive difficulty changed to: $value");
                      gameProvider.setUseAdaptiveDifficulty(value);
                      _saveSetting('use_adaptive_difficulty', value);
                    },
                    icon: Icons.auto_awesome,
                  ),
                  _buildSwitchTile(
                    title: S.of(context)!.puzzleTimer,
                    subtitle: S.of(context)!.puzzleTimerDesc,
                    value: gameProvider.puzzleTimerEnabled,
                    onChanged: (value) {
                      debugPrint("[SETTINGS] ⏱️ Puzzle timer setting changed to: $value");
                      gameProvider.setPuzzleTimer(value);
                      _saveSetting('puzzle_timer_enabled', value);
                    },
                    icon: Icons.timer,
                  ),
                  
                  _buildSwitchTile(
                    title: S.of(context)!.showHints,
                    subtitle: S.of(context)!.showHintsDesc,
                    value: true, // TODO: Add to GameProvider
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 💡 Hints setting changed to: $value");
                      _saveSetting('hints_enabled', value);
                    },
                    icon: Icons.lightbulb,
                  ),
                  
                  _buildSwitchTile(
                    title: S.of(context)!.hapticFeedback,
                    subtitle: S.of(context)!.hapticFeedbackDesc,
                    value: true, // TODO: Add to GameProvider
                    onChanged: (value) {
                      debugPrint("[SETTINGS] 📳 Haptic feedback setting changed to: $value");
                      _saveSetting('haptic_enabled', value);
                    },
                    icon: Icons.vibration,
                  ),

                  const Divider(color: SpaceTheme.nebulaPurple, height: 24),
                    _buildFeatureRow(
                    title: S.of(context)!.sriStatisticsTitle,
                    subtitle: S.of(context)!.sriStatisticsDesc,
                    icon: Icons.bar_chart,
                    isLocked: !isUnlocked,
                    onTap: () {
                        if (isUnlocked) {
                        showDialog(
                            context: context,
                            builder: (context) => const SriStatisticsDialog(),
                        );
                        } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                            content: Text(S.of(context)!.premiumFeature),
                            backgroundColor: SpaceTheme.planetOrange,
                            ),
                        );
                        }
                    },
                    ),

                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildTaskCustomizationSettings() {
    return SlideTransition(
      position: _settingAnimations[2], // Use the 3rd animation
      // MODIFIED: Use Consumer2 to get GameProvider AND VocabularyService
      child: Consumer2<GameProvider, VocabularyService>(
        builder: (context, gameProvider, vocabService, child) {
          
          // NEW: Check if a custom set is active
          final bool customSetIsActive = gameProvider.activeVocabularySetId != null;

          return _buildSettingsCard(
            title: S.of(context)!.taskCustomizationTitle,
            icon: Icons.filter_list,
            children: [
              _buildSwitchTile(
                title: S.of(context)!.taskCustomizationEnable,
                subtitle: S.of(context)!.taskCustomizationEnableDesc,
                value: gameProvider.tasksCustomizationEnabled,
                onChanged: (value) {
                  debugPrint("[SETTINGS] 🛠️ Task Customization changed to: $value");
                  gameProvider.setTasksCustomizationEnabled(value);
                },
                icon: Icons.edit_note,
              ),

              // Conditionally show the rest of the settings
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: gameProvider.tasksCustomizationEnabled
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(color: SpaceTheme.nebulaPurple, height: 24),

                        // NEW: Add the custom set manager widget
                        _buildCustomSetSelector(context, gameProvider, vocabService),
                        
                        const Divider(color: SpaceTheme.nebulaPurple, height: 24),

                        // NEW: Add a helper text if a set is active
                        if (customSetIsActive)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Text(
                              S.of(context)!.taskFiltersDisabled, // Add to S file
                              style: SpaceTheme.bodyStyle.copyWith(
                                color: SpaceTheme.starYellow,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        
                        // MODIFIED: Wrap existing filters in IgnorePointer and Opacity
                        // These will be disabled if a custom set is active
                        IgnorePointer(
                          ignoring: customSetIsActive,
                          child: Opacity(
                            opacity: customSetIsActive ? 0.5 : 1.0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // --- Word Length Slider ---
                                _buildWordLengthSlider(gameProvider),
                                const SizedBox(height: 20),

                                // --- Included Sources ---
                                _buildSourceSelector(gameProvider),
                                const SizedBox(height: 20),

                                // --- Include Wildcards ---
                                _buildWildcardInputSection(
                                  title: S.of(context)!.taskWildcardIncludeTitle,
                                  desc: S.of(context)!.taskWildcardIncludeDesc,
                                  controller: _includeController,
                                  currentFilters: gameProvider.taskIncludeWildcards,
                                  onAdd: (filter) {
                                    final newList = List<String>.from(gameProvider.taskIncludeWildcards)..add(filter);
                                    gameProvider.setTaskIncludeWildcards(newList);
                                  },
                                  onRemove: (filter) {
                                    final newList = List<String>.from(gameProvider.taskIncludeWildcards)..remove(filter);
                                    gameProvider.setTaskIncludeWildcards(newList);
                                  },
                                ),
                                const SizedBox(height: 20),
                                
                                // --- Exclude Wildcards ---
                                _buildWildcardInputSection(
                                  title: S.of(context)!.taskWildcardExcludeTitle,
                                  desc: S.of(context)!.taskWildcardExcludeDesc,
                                  controller: _excludeController,
                                  currentFilters: gameProvider.taskExcludeWildcards,
                                  onAdd: (filter) {
                                    final newList = List<String>.from(gameProvider.taskExcludeWildcards)..add(filter);
                                    gameProvider.setTaskExcludeWildcards(newList);
                                  },
                                  onRemove: (filter) {
                                    final newList = List<String>.from(gameProvider.taskExcludeWildcards)..remove(filter);
                                    gameProvider.setTaskExcludeWildcards(newList);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(), // Empty box when disabled
              ),
            ],
          );
        },
      ),
    );
  }

  // --- NEW: Helper for Word Length Slider ---
  Widget _buildWordLengthSlider(GameProvider gameProvider) {
    final min = gameProvider.taskWordLengthMin;
    final max = gameProvider.taskWordLengthMax;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context)!.taskWordLengthTitle,
          style: SpaceTheme.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              "2",
              style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.moonSilver),
            ),
            Expanded(
              child: RangeSlider(
                min: 2,
                max: 20, // Max word length to filter
                divisions: 18,
                values: RangeValues(min, max),
                activeColor: SpaceTheme.alienGreen,
                inactiveColor: SpaceTheme.deepSpace,
                labels: RangeLabels(
                  min.round().toString(),
                  max.round().toString(),
                ),
                onChanged: (values) {
                  gameProvider.setTaskWordLengthRange(values.start, values.end);
                },
              ),
            ),
            Text(
              "20",
              style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.moonSilver),
            ),
          ],
        ),
        Center(
          child: Text(
            S.of(context)!.taskWordLengthRange(min.round(), max.round()),
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }

  // --- NEW: Helper for Source Selector Chips ---
  Widget _buildSourceSelector(GameProvider gameProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context)!.taskIncludedSourcesTitle,
          style: SpaceTheme.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          S.of(context)!.taskIncludedSourcesDesc,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 12,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 12),
        !_sourcesLoaded
          ? const Center(child: CircularProgressIndicator())
          : _availableSources.isEmpty
            ? Center(
                child: Text(
                  "Keine Quellen gefunden", // Should not happen
                  style: SpaceTheme.bodyStyle.copyWith(color: Colors.white54),
                ),
              )
            : Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: _availableSources.map((source) {
                  final isSelected = gameProvider.taskIncludedSources.contains(source);
                  return FilterChip(
                    label: Text(source),
                    selected: isSelected,
                    onSelected: (selected) {
                      final currentSources = Set<String>.from(gameProvider.taskIncludedSources);
                      if (selected) {
                        currentSources.add(source);
                      } else {
                        currentSources.remove(source);
                      }
                      gameProvider.setTaskIncludedSources(currentSources);
                    },
                    backgroundColor: SpaceTheme.deepSpace.withOpacity(0.8),
                    selectedColor: SpaceTheme.alienGreen.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: isSelected ? SpaceTheme.alienGreen : Colors.white,
                    ),
                    checkmarkColor: SpaceTheme.alienGreen,
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: isSelected ? SpaceTheme.alienGreen : Colors.white24,
                      ),
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  // --- NEW: Helper for Wildcard Input ---
  Widget _buildWildcardInputSection({
    required String title,
    required String desc,
    required TextEditingController controller,
    required List<String> currentFilters,
    required Function(String) onAdd,
    required Function(String) onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: SpaceTheme.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          desc,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 12,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 12),
        // Text field for adding new filters
        TextField(
          controller: controller,
          style: SpaceTheme.bodyStyle,
          decoration: InputDecoration(
            hintText: S.of(context)!.taskWildcardHint,
            hintStyle: SpaceTheme.bodyStyle.copyWith(color: Colors.white38),
            filled: true,
            fillColor: SpaceTheme.deepSpace.withOpacity(0.5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: SpaceTheme.alienGreen),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_circle, color: SpaceTheme.alienGreen),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty && !currentFilters.contains(text)) {
                  onAdd(text);
                  controller.clear();
                }
              },
            ),
          ),
          onSubmitted: (value) {
            final text = value.trim();
            if (text.isNotEmpty && !currentFilters.contains(text)) {
              onAdd(text);
              controller.clear();
            }
          },
        ),
        const SizedBox(height: 8),
        // Wrap for displaying current filters
        if (currentFilters.isNotEmpty)
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: currentFilters.map((filter) {
              return Chip(
                label: Text(filter),
                labelStyle: const TextStyle(color: Colors.white),
                backgroundColor: SpaceTheme.nebulaPurple.withOpacity(0.7),
                onDeleted: () {
                  onRemove(filter);
                },
                deleteIcon: const Icon(Icons.cancel, size: 18),
                deleteIconColor: Colors.white70,
              );
            }).toList(),
          ),
      ],
    );
  }
  // --- END OF NEW WIDGETS ---

  Widget _buildFeatureRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isLocked,
    required VoidCallback onTap,
    }) {
    return InkWell(
      onTap: isLocked ? null : onTap, // Disable tap if locked
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
      opacity: isLocked ? 0.6 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: isLocked ? Colors.grey : SpaceTheme.alienGreen,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SpaceTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
            if (isLocked)
              const Icon(Icons.lock, color: SpaceTheme.starYellow, size: 20)
            else
              const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
      ),
    );
    }
  
  Widget _buildLanguageSettings() {
    return SlideTransition(
      position: _settingAnimations[3], // Was 2
      child: _buildSettingsCard(
        title: S.of(context)!.language,
        icon: Icons.language,
        children: [
          _buildLanguageSelector(),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SpaceTheme.alienGreen.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.translate,
                color: SpaceTheme.alienGreen,
                size: 24,
              ),
              
              const SizedBox(width: 16),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.of(context)!.appLanguage,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      S.of(context)!.appLanguageDesc,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          _buildLanguageOption(S.of(context)!.languageEnglish, 'en'),
          const SizedBox(height: 12),
          _buildLanguageOption(S.of(context)!.languageGerman, 'de'),
        ],
      ),
    );
  }
  
  Widget _buildLanguageOption(String displayName, String localeCode) {
    final isSelected = currentLocale == localeCode;
    
    return GestureDetector(
      onTap: _isLoading ? null : () => _changeLanguage(localeCode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected 
              ? SpaceTheme.alienGreen.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected 
                ? SpaceTheme.alienGreen 
                : Colors.white.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? SpaceTheme.alienGreen : Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  color: isSelected ? SpaceTheme.alienGreen : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                ),
              ),
            ),
            if (isSelected) 
              Icon(
                Icons.check,
                color: SpaceTheme.alienGreen,
                size: 20,
              ),
            if (_isLoading && isSelected)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(SpaceTheme.alienGreen),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultySettings() {
    return SlideTransition(
      position: _settingAnimations[4], // Was 3
      child: _buildSettingsCard(
        title: S.of(context)!.difficulty,
        icon: Icons.tune,
        children: [
          Consumer<GameProvider>(
            builder: (context, gameProvider, child) {
              return Column(
                children: [
                  _buildStatRow(
                    label: S.of(context)!.currentGrade,
                    value: S.of(context)!.gradeN(gameProvider.grade),
                    icon: Icons.school,
                    onTap: () => _showGradeSelector(gameProvider),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  _buildStatRow(
                    label: S.of(context)!.currentLevelDesc,
                    value: gameProvider.level.toString(),
                    icon: Icons.trending_up,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Text(
                    _getDifficultyDescription(gameProvider.grade),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildProgressSettings() {
    return SlideTransition(
      position: _settingAnimations[5], // Was 4
      child: _buildSettingsCard(
        title: S.of(context)!.progress,
        icon: Icons.analytics,
        children: [
          Consumer<GameProvider>(
            builder: (context, gameProvider, child) {
              return Column(
                children: [
                  _buildStatRow(
                    label: S.of(context)!.totalScore,
                    value: gameProvider.score.toString(),
                    icon: Icons.star,
                  ),
                  
                  _buildStatRow(
                    label: S.of(context)!.gamesPlayed,
                    value: gameProvider.totalGamesPlayed.toString(),
                    icon: Icons.games,
                  ),
                  
                  _buildStatRow(
                    label: S.of(context)!.achievements,
                    value: gameProvider.totalAchievements.toString(),
                    icon: Icons.emoji_events,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showResetDialog,
                      icon: const Icon(Icons.refresh),
                      label: Text(S.of(context)!.resetProgress),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SpaceTheme.rocketRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildAboutSection() {
    return SlideTransition(
      position: _settingAnimations[6], // Was 5
      child: _buildSettingsCard(
        title: S.of(context)!.about,
        icon: Icons.info,
        children: [
          _buildInfoRow(S.of(context)!.appVersion, '1.0.0 (Vocabulary)'),
          _buildInfoRow(S.of(context)!.developer, S.of(context)!.developerName),
          _buildInfoRow(S.of(context)!.targetAge, S.of(context)!.targetAgeRange),

          // --- ADD THESE LINES ---
          const Divider(color: SpaceTheme.nebulaPurple, height: 24),
          _buildFeatureRow(
            title: S.of(context)!.imprintTitle,
            subtitle: S.of(context)!.viewLegalNotice,
            icon: Icons.gavel_rounded,
            isLocked: false,
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => const ImprintDialog(),
              );
            },
          ),
          // --- END OF ADDED LINES ---

          const SizedBox(height: 16),

          Text(
            S.of(context)!.aboutApp,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: SpaceTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SpaceTheme.starYellow.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: SpaceTheme.starYellow,
                  size: 24,
                ),
              ),
              
              const SizedBox(width: 16),
              
              Text(
                title,
                style: SpaceTheme.titleStyle.copyWith(fontSize: 20),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          ...children,
        ],
      ),
    );
  }
  
  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    bool isLocked = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: SpaceTheme.alienGreen,
            size: 24,
          ),
          
          const SizedBox(width: 16),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: SpaceTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          
          Switch(
            value: value,
            onChanged: isLocked ? null : onChanged, // Disable if locked
            activeColor: SpaceTheme.alienGreen,
            inactiveThumbColor: SpaceTheme.moonSilver,
            inactiveTrackColor: SpaceTheme.deepSpace,
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatRow({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              icon,
              color: SpaceTheme.cosmicPink,
              size: 20,
            ),
            
            const SizedBox(width: 12),
            
            Expanded(
              child: Text(
                label,
                style: SpaceTheme.bodyStyle.copyWith(fontSize: 14),
              ),
            ),
            
            Text(
              value,
              style: SpaceTheme.titleStyle.copyWith(
                fontSize: 16,
                color: SpaceTheme.starYellow,
              ),
            ),
            
            if (onTap != null)
              const SizedBox(
                width: 4,
                child: Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: SpaceTheme.bodyStyle.copyWith(fontSize: 14),
          ),
          Text(
            value,
            style: SpaceTheme.bodyStyle.copyWith(
              fontSize: 14,
              color: SpaceTheme.starYellow,
            ),
          ),
        ],
      ),
    );
  }

  // SAVE INDIVIDUAL SETTING WITH LOGGING
  Future<void> _saveSetting(String key, dynamic value) async {
    debugPrint("[SETTINGS] 💾 Saving setting: $key = $value");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
      
      debugPrint("[SETTINGS] ✅ Successfully saved $key");
      
      final savedValue = _getSettingValue(prefs, key, value.runtimeType);
      debugPrint("[SETTINGS] 🔍 Verification - $key now reads: $savedValue");
      
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Failed to save $key: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
    }
  }
  
  dynamic _getSettingValue(SharedPreferences prefs, String key, Type type) {
    switch (type) {
      case bool:
        return prefs.getBool(key);
      case String:
        return prefs.getString(key);
      case int:
        return prefs.getInt(key);
      case double:
        return prefs.getDouble(key);
      case const (List<String>):
        return prefs.getStringList(key);
      default:
        return prefs.get(key);
    }
  }

  void _changeLanguage(String localeCode) async {
    if (localeCode == currentLocale) {
      debugPrint("[SETTINGS] 🌍 Language unchanged: $localeCode");
      return;
    }
    
    debugPrint("[SETTINGS] 🌍 Changing language from $currentLocale to $localeCode");
    
    setState(() {
      _isLoading = true;
      currentLocale = localeCode;
    });
    
    try {
      await _saveLanguagePreference(localeCode);
      
      if (mounted) {
        _showLanguageChangeDialog(localeCode);
      }
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Failed to change language: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to change language: $e'),
            backgroundColor: SpaceTheme.rocketRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _saveLanguagePreference(String localeCode) async {
    debugPrint("[SETTINGS] 🌍 Saving language preference: $localeCode");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', localeCode);
      
      final savedLocale = prefs.getString('language');
      debugPrint("[SETTINGS] ✅ Language saved successfully");
      debugPrint("[SETTINGS] 🔍 Verification - language now reads: $savedLocale");
      
      final allKeys = prefs.getKeys();
      debugPrint("[SETTINGS] 🗂️ All current preferences:");
      for (final key in allKeys) {
        final value = prefs.get(key);
        debugPrint("[SETTINGS]   $key: $value");
      }
      
    } catch (e, stackTrace) {
      debugPrint("[SETTINGS] ❌ Failed to save language preference: $e");
      debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
      rethrow;
    }
  }
  
  void _showLanguageChangeDialog(String localeCode) {
    debugPrint("[SETTINGS] 🔄 Showing language change dialog for: $localeCode");
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          S.of(context)!.languageChanged,
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          S.of(context)!.languageChangedDesc,
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint("[SETTINGS] 🔄 User chose to restart later");
              Navigator.of(context).pop();
            },
            child: Text(
              S.of(context)!.later,
              style: TextStyle(color: SpaceTheme.moonSilver),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              debugPrint("[SETTINGS] 🔄 User chose to restart now");
              Navigator.of(context).pop();
              _triggerAppRestart();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.alienGreen,
            ),
            child: Text(S.of(context)!.restartNow),
          ),
        ],
      ),
    );
  }

  void _showGradeSelector(GameProvider gameProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          S.of(context)!.selectGrade,
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [1, 2, 3, 4].map((grade) { 
            final isSelected = gameProvider.grade == grade;
            return GestureDetector(
              onTap: () {
                debugPrint("[SETTINGS] 🎓 Grade changed to: $grade");
                gameProvider.setGrade(grade);
                Navigator.of(context).pop();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? SpaceTheme.starYellow.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected 
                        ? SpaceTheme.starYellow 
                        : Colors.white.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.school,
                      color: isSelected ? SpaceTheme.starYellow : Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      S.of(context)!.gradeN(grade),
                      style: TextStyle(
                        color: isSelected ? SpaceTheme.starYellow : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _getDifficultyDescription(grade),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              S.of(context)!.cancel,
              style: TextStyle(color: SpaceTheme.moonSilver),
            ),
          ),
        ],
      ),
    );
  }
  
  String _getDifficultyDescription(int grade) {
    switch (grade) {
      case 1:
        return S.of(context)!.difficultyDescGrade3; // Note: Your key names are slightly off
      case 2:
        return S.of(context)!.difficultyDescGrade4;
      case 3:
        return S.of(context)!.difficultyDescGrade5;
      case 4:
        return S.of(context)!.difficultyDescGrade6;
      default:
        return '';
    }
  }

  void _triggerAppRestart() {
    debugPrint("[SETTINGS] 🔄 Triggering app restart notification");
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context)!.restartToApplyChanges),
        backgroundColor: SpaceTheme.alienGreen,
        duration: Duration(seconds: 4),
      ),
    );
  }
  
  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          S.of(context)!.resetProgress,
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          S.of(context)!.resetProgressConfirmation,
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              S.of(context)!.cancel,
              style: TextStyle(color: SpaceTheme.moonSilver),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              debugPrint("[SETTINGS] 🗑️ Resetting all game progress");
              context.read<GameProvider>().resetGame();
              // NEW: Also clear SRI data
              context.read<SriService>().clearAllData();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.of(context)!.progressResetSuccess),
                  backgroundColor: SpaceTheme.alienGreen,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.rocketRed,
            ),
            child: Text(S.of(context)!.reset),
          ),
        ],
      ),
    );
  }
}