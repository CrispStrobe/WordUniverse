// lib/features/settings/screens/settings_screen.dart
import 'package:flutter/material.dart';
import '../../../main.dart' show MyApp;
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/space_theme.dart';
import '../../../core/services/debug_provider.dart';

import '../../../core/theme/app_fonts.dart';

// Import VocabularyService to get sources
import '../../../core/services/vocabulary_service.dart';
import '../../../core/services/language_pack_service.dart';
import '../../../core/models/language_pack.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/services/learner_profile_service.dart';

import '../../../shared/widgets/imprint_dialog.dart';
import '../../../shared/widgets/language_pack_dialog.dart';
import 'diagnostics_screen.dart';
import '../../games/screens/parent_dashboard_screen.dart';
import '../../../shared/widgets/privacy_policy_dialog.dart';
import '../../../shared/widgets/parental_gate.dart';

import '../../../generated/l10n.dart';
import '../../../shared/utils/load_status_localization.dart';

// We import this for the Grade definitions
import '../../games/providers/game_provider.dart';
import '../../games/widgets/space_background.dart';
// We import the dialog separately
import '../widgets/sri_statistics_dialog.dart';

import '../widgets/manage_sets_dialog.dart';

import '../../../core/services/custom_licenses_registry.dart';

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
  String currentLearningLanguage = kDefaultLanguageCode;
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
    if (kDebugMode) debugPrint("[SETTINGS] 🔧 initState() starting...");

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _settingAnimations = List.generate(7, (index) {
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

    if (kDebugMode)
      debugPrint("[SETTINGS] 🔧 initState() completed - 7 animations ready");
    _slideController.forward();
    ensureCustomLicensesRegistered();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kDebugMode) debugPrint("[SETTINGS] 🌍 didChangeDependencies() called");

    if (!_hasLoadedLocale) {
      _loadCurrentLocaleAndSettings();
      // Re-check what's actually on disk so the pack rows are truthful even
      // after the user cleared app storage between sessions.
      context.read<LanguagePackService>().refresh(probePartialDownloads: true);
      _hasLoadedLocale = true;
    }
  }

  Widget _buildFontSelector(GameProvider gameProvider) {
    final String title = S.of(context)!.fontFamilyTitle;
    final String subtitle = S.of(context)!.fontFamilySubtitle;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          const Icon(Icons.font_download,
              color: SpaceTheme.alienGreen, size: 24),
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

          // The Dropdown Button
          DropdownButton<String>(
            value: gameProvider.selectedFontFamily,
            dropdownColor: SpaceTheme.deepSpace,
            style: SpaceTheme.bodyStyle,
            onChanged: (String? newValue) {
              if (newValue != null) {
                gameProvider.setSelectedFontFamily(newValue);
              }
            },
            items: AppFonts.selectableFonts.entries.map((entry) {
              return DropdownMenuItem<String>(
                value: entry.key, // e.g., "SASBienchen"
                child: Text(entry.value), // e.g., "SAS Bienchen"
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomSetSelector(
    BuildContext context,
    GameProvider gameProvider,
    VocabularyService vocabService,
  ) {
    final s = S.of(context)!;
    final customSets = vocabService.getCustomSets();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Title
        Text(
          s.taskActiveSetTitle,
          style: SpaceTheme.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          s.taskActiveSetDesc,
          style: SpaceTheme.bodyStyle.copyWith(
            fontSize: 12,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 12),

        // 2. List of Checkboxes
        if (customSets.isEmpty)
          Center(
            child: Text(
              S.of(context)!.noCustomSetsYet,
              style: SpaceTheme.bodyStyle
                  .copyWith(color: Colors.white54, fontStyle: FontStyle.italic),
            ),
          )
        else
          Container(
            height: 150, // Constrain height to make it scrollable
            decoration: BoxDecoration(
              color: SpaceTheme.deepSpace.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: ListView.builder(
              itemCount: customSets.length,
              itemBuilder: (context, index) {
                final set = customSets[index];
                return CheckboxListTile(
                  title: Text(set.name, style: SpaceTheme.bodyStyle),
                  subtitle: Text(
                    set.description,
                    style: SpaceTheme.bodyStyle
                        .copyWith(fontSize: 10, color: Colors.white60),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: gameProvider.activeVocabularySetIds.contains(set.id),
                  onChanged: (bool? value) {
                    gameProvider.toggleActiveVocabularySet(set.id);
                  },
                  activeColor: SpaceTheme.alienGreen,
                  checkColor: Colors.black,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // 3. Button to manage/create sets
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.edit_rounded),
            label: Text(s.taskManageSets),
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceTheme.cosmicPink,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const ManageSetsDialog(),
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
        if (kDebugMode)
          debugPrint(
              "[SETTINGS] 📚 Loaded ${_availableSources.length} vocab sources");
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint("[SETTINGS] ❌ Error loading vocab sources: $e");
    }
  }

  @override
  void dispose() {
    if (kDebugMode) debugPrint("[SETTINGS] 🗑️ Disposing settings screen");
    _slideController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  void _loadCurrentLocaleAndSettings() async {
    try {
      final contextLocale = Localizations.localeOf(context).languageCode;
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString('language');
      final savedLearningLanguage =
          prefs.getString('learning_language') ?? 'de';

      setState(() {
        currentLocale = savedLocale ?? contextLocale;
        currentLearningLanguage = savedLearningLanguage == 'en' ? 'en' : 'de';
      });

      // Load vocab sources *after* locale is set
      await _loadVocabularySources();
    } catch (e) {
      setState(() {
        currentLocale = 'en';
      });
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
              if (kDebugMode) debugPrint("[SETTINGS] 🔙 Back button pressed");
              Navigator.of(context).pop();
            },
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 28,
            ),
            style: IconButton.styleFrom(
              backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
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
                      if (kDebugMode)
                        debugPrint(
                            "[SETTINGS] 🔊 Sound setting changed to: $value");
                      gameProvider.setSoundEnabled(value);
                    },
                    icon: Icons.music_note,
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
          Consumer3<GameProvider, DebugProvider, LearnerProfileService>(
            builder: (context, gameProvider, debugProvider, profile, child) {
              final isUnlocked = gameProvider.isFullVersionUnlocked ||
                  debugProvider.isPaidUnlockedForced;

              return Column(
                children: [
                  _buildSwitchTile(
                    title: S.of(context)!.focusMode,
                    subtitle: S.of(context)!.focusModeDesc,
                    value: profile.focusMode,
                    onChanged: profile.setFocusMode,
                    icon: Icons.center_focus_strong,
                  ),
                  _buildSwitchTile(
                    title: S.of(context)!.puzzleTimer,
                    subtitle: S.of(context)!.puzzleTimerDesc,
                    value: gameProvider.puzzleTimerEnabled,
                    onChanged: (value) {
                      if (kDebugMode)
                        debugPrint(
                            "[SETTINGS] ⏱️ Puzzle timer setting changed to: $value");
                      gameProvider.setPuzzleTimer(value);
                    },
                    icon: Icons.timer,
                  ),
                  _buildSwitchTile(
                    title: S.of(context)!.showHints,
                    subtitle: S.of(context)!.showHintsDesc,
                    value: gameProvider.hintsEnabled,
                    onChanged: (value) {
                      if (kDebugMode)
                        debugPrint(
                            "[SETTINGS] 💡 Hints setting changed to: $value");
                      gameProvider.setHintsEnabled(value);
                    },
                    icon: Icons.lightbulb,
                  ),
                  _buildSwitchTile(
                    title: S.of(context)!.hapticFeedback,
                    subtitle: S.of(context)!.hapticFeedbackDesc,
                    value: gameProvider.hapticEnabled,
                    onChanged: (value) {
                      if (kDebugMode)
                        debugPrint(
                            "[SETTINGS] 📳 Haptic feedback setting changed to: $value");
                      gameProvider.setHapticEnabled(value);
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
                  const Divider(color: SpaceTheme.nebulaPurple, height: 24),
                  _buildFontSelector(gameProvider),
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
      position: _settingAnimations[2],
      child: Consumer2<GameProvider, VocabularyService>(
        builder: (context, gameProvider, vocabService, child) {
          final bool customSetIsActive =
              gameProvider.activeVocabularySetIds.isNotEmpty;

          return _buildSettingsCard(
            title: S.of(context)!.taskCustomizationTitle,
            icon: Icons.filter_list,
            children: [
              _buildSwitchTile(
                title: S.of(context)!.taskCustomizationEnable,
                subtitle: S.of(context)!.taskCustomizationEnableDesc,
                value: gameProvider.tasksCustomizationEnabled,
                onChanged: (value) {
                  if (kDebugMode)
                    debugPrint(
                        "[SETTINGS] 🛠️ Task Customization changed to: $value");
                  gameProvider.setTasksCustomizationEnabled(value);

                  if (value == false) {
                    gameProvider.clearActiveVocabularySets();
                    if (kDebugMode)
                      debugPrint(
                          "[SETTINGS] 🧹 Cleared active vocabulary sets.");
                  }
                },
                icon: Icons.edit_note,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: gameProvider.tasksCustomizationEnabled
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(
                              color: SpaceTheme.nebulaPurple, height: 24),
                          _buildCustomSetSelector(
                              context, gameProvider, vocabService),
                          const Divider(
                              color: SpaceTheme.nebulaPurple, height: 24),
                          if (customSetIsActive)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Text(
                                S.of(context)!.taskFiltersDisabled,
                                style: SpaceTheme.bodyStyle.copyWith(
                                  color: SpaceTheme.starYellow,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          IgnorePointer(
                            ignoring: customSetIsActive,
                            child: Opacity(
                              opacity: customSetIsActive ? 0.5 : 1.0,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildWordLengthSlider(gameProvider),
                                  const SizedBox(height: 20),
                                  _buildSourceSelector(gameProvider),
                                  const SizedBox(height: 20),
                                  _buildWildcardInputSection(
                                    title:
                                        S.of(context)!.taskWildcardIncludeTitle,
                                    desc:
                                        S.of(context)!.taskWildcardIncludeDesc,
                                    controller: _includeController,
                                    currentFilters:
                                        gameProvider.taskIncludeWildcards,
                                    onAdd: (filter) {
                                      final newList = List<String>.from(
                                          gameProvider.taskIncludeWildcards)
                                        ..add(filter);
                                      gameProvider
                                          .setTaskIncludeWildcards(newList);
                                    },
                                    onRemove: (filter) {
                                      final newList = List<String>.from(
                                          gameProvider.taskIncludeWildcards)
                                        ..remove(filter);
                                      gameProvider
                                          .setTaskIncludeWildcards(newList);
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                  _buildWildcardInputSection(
                                    title:
                                        S.of(context)!.taskWildcardExcludeTitle,
                                    desc:
                                        S.of(context)!.taskWildcardExcludeDesc,
                                    controller: _excludeController,
                                    currentFilters:
                                        gameProvider.taskExcludeWildcards,
                                    onAdd: (filter) {
                                      final newList = List<String>.from(
                                          gameProvider.taskExcludeWildcards)
                                        ..add(filter);
                                      gameProvider
                                          .setTaskExcludeWildcards(newList);
                                    },
                                    onRemove: (filter) {
                                      final newList = List<String>.from(
                                          gameProvider.taskExcludeWildcards)
                                        ..remove(filter);
                                      gameProvider
                                          .setTaskExcludeWildcards(newList);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }

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
              style:
                  SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.moonSilver),
            ),
            Expanded(
              child: RangeSlider(
                min: 2,
                max: 20,
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
              style:
                  SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.moonSilver),
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
                      S.of(context)!.noSourcesFound,
                      style:
                          SpaceTheme.bodyStyle.copyWith(color: Colors.white54),
                    ),
                  )
                : Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: _availableSources.map((source) {
                      final isSelected =
                          gameProvider.taskIncludedSources.contains(source);
                      return FilterChip(
                        label: Text(source),
                        selected: isSelected,
                        onSelected: (selected) {
                          final currentSources = Set<String>.from(
                              gameProvider.taskIncludedSources);
                          if (selected) {
                            currentSources.add(source);
                          } else {
                            currentSources.remove(source);
                          }
                          gameProvider.setTaskIncludedSources(currentSources);
                        },
                        backgroundColor:
                            SpaceTheme.deepSpace.withValues(alpha: 0.8),
                        selectedColor:
                            SpaceTheme.alienGreen.withValues(alpha: 0.3),
                        labelStyle: TextStyle(
                          color:
                              isSelected ? SpaceTheme.alienGreen : Colors.white,
                        ),
                        checkmarkColor: SpaceTheme.alienGreen,
                        shape: StadiumBorder(
                          side: BorderSide(
                            color: isSelected
                                ? SpaceTheme.alienGreen
                                : Colors.white24,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
      ],
    );
  }

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
        TextField(
          controller: controller,
          style: SpaceTheme.bodyStyle,
          decoration: InputDecoration(
            hintText: S.of(context)!.taskWildcardHint,
            hintStyle: SpaceTheme.bodyStyle.copyWith(color: Colors.white38),
            filled: true,
            fillColor: SpaceTheme.deepSpace.withValues(alpha: 0.5),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        if (currentFilters.isNotEmpty)
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: currentFilters.map((filter) {
              return Chip(
                label: Text(filter),
                labelStyle: const TextStyle(color: Colors.white),
                backgroundColor: SpaceTheme.nebulaPurple.withValues(alpha: 0.7),
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

  Widget _buildFeatureRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isLocked,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: isLocked ? null : onTap,
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
      position: _settingAnimations[3],
      child: _buildSettingsCard(
        title: S.of(context)!.language,
        icon: Icons.language,
        children: [
          _buildLanguageSelector(),
          const SizedBox(height: 16),
          _buildLearningLanguageSelector(),
          const SizedBox(height: 16),
          _buildLanguagePackSection(),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SpaceTheme.alienGreen.withValues(alpha: 0.3),
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
              ? SpaceTheme.alienGreen.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? SpaceTheme.alienGreen
                : Colors.white.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
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
                  valueColor:
                      AlwaysStoppedAnimation<Color>(SpaceTheme.alienGreen),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLearningLanguageSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SpaceTheme.starYellow.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.school,
                color: SpaceTheme.starYellow,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.of(context)!.learningLanguage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      S.of(context)!.learningLanguageDesc,
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
          // Built from the pack registry, so adding a language needs no edit
          // here — see core/models/language_pack.dart.
          ..._buildLearningLanguageOptions(),
        ],
      ),
    );
  }

  List<Widget> _buildLearningLanguageOptions() {
    final packs = orderedLanguagePacks;
    final widgets = <Widget>[];
    for (var i = 0; i < packs.length; i++) {
      if (i > 0) widgets.add(const SizedBox(height: 12));
      widgets.add(
        _buildLearningLanguageOption(packs[i].nativeName, packs[i].code),
      );
    }
    return widgets;
  }

  /// Per-pack status, size, license and actions. This is where a user who
  /// skipped the first-launch download (or removed a pack) gets it back, with
  /// a live progress bar while it downloads.
  Widget _buildLanguagePackSection() {
    final s = S.of(context)!;
    return Consumer<LanguagePackService>(
      builder: (context, service, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: SpaceTheme.deepSpace.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: SpaceTheme.alienGreen.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.dataset_outlined,
                      color: SpaceTheme.alienGreen, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.languagePacksTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          s.languagePacksDesc,
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
              const SizedBox(height: 12),
              for (final state in service.packs)
                _buildPackRow(s, service, state),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPackRow(
    S s,
    LanguagePackService service,
    LanguagePackState state,
  ) {
    final pack = state.pack;
    final isActive = service.selectedLanguage == pack.code && service.isActivePackReady;
    final (String label, Color color) = switch (state.status) {
      LanguagePackStatus.installed => pack.requiresDownload
          ? (s.packStatusInstalled, SpaceTheme.alienGreen)
          : (s.packStatusBundled, SpaceTheme.alienGreen),
      LanguagePackStatus.installing =>
        (s.packStatusInstalling, SpaceTheme.starYellow),
      LanguagePackStatus.paused =>
        (s.downloadPaused, SpaceTheme.starYellow),
      LanguagePackStatus.failed =>
        (s.packStatusFailed, SpaceTheme.planetOrange),
      LanguagePackStatus.notInstalled =>
        (s.packStatusNotInstalled, SpaceTheme.moonSilver),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pack.nativeName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          _PackChip(
                            text: s.packInUse,
                            color: SpaceTheme.starYellow,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !pack.requiresDownload
                          ? '$label · ${pack.licenseLabel}'
                          : pack.installedSizeLabel == null
                              ? '$label · ${s.packMetaSizeLicense(pack.downloadSizeLabel, pack.licenseLabel)}'
                              : '$label · ${s.packMetaSizes(pack.downloadSizeLabel, pack.installedSizeLabel!, pack.licenseLabel)}',
                      style: TextStyle(color: color, fontSize: 11),
                    ),
                    // A pack that is part-way downloaded looked untouched
                    // before, even though tapping Resume continues from disk.
                    if (state.isResumable)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          s.packResumeProgress(
                            '${(state.cachedBytes! / (1024 * 1024)).toStringAsFixed(1)} MB',
                            pack.downloadSizeLabel,
                          ),
                          style: const TextStyle(
                              color: SpaceTheme.moonSilver, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              _buildPackAction(s, service, state, isActive),
            ],
          ),
          if (state.isInstalling) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
                minHeight: 6,
                backgroundColor: Colors.white24,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(SpaceTheme.starYellow),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${state.message.localized(s)}  ·  ${(state.progress * 100).round()}%',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
          if (state.status == LanguagePackStatus.failed &&
              state.error != null) ...[
            const SizedBox(height: 4),
            Text(
              state.error!,
              style: const TextStyle(
                  color: SpaceTheme.planetOrange, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPackAction(
    S s,
    LanguagePackService service,
    LanguagePackState state,
    bool isActive,
  ) {
    if (state.isInstalling) {
      return TextButton(
        onPressed: () => service.pause(state.pack.code),
        child: Text(s.downloadPause),
      );
    }

    final busy = _isLoading || service.isAnyInstalling;

    if (!state.isInstalled) {
      return TextButton(
        onPressed: busy ? null : () => _installPack(state.pack.code),
        child: Text(
          state.status == LanguagePackStatus.paused || state.isResumable
              ? s.downloadResume
              : state.status == LanguagePackStatus.failed
              ? s.packRetry
              : s.packDownloadAction,
          style: const TextStyle(color: SpaceTheme.starYellow, fontSize: 13),
        ),
      );
    }

    if (isActive) {
      // Nothing to do: it's installed and in use. Removing it would leave the
      // games without words.
      return const Icon(Icons.check_circle,
          color: SpaceTheme.alienGreen, size: 20);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: busy ? null : () => _changeLearningLanguage(state.pack.code),
          child: Text(
            s.packUseAction,
            style: const TextStyle(color: SpaceTheme.alienGreen, fontSize: 13),
          ),
        ),
        if (state.pack.requiresDownload)
          IconButton(
            tooltip: s.packRemoveAction,
            onPressed: busy ? null : () => _confirmRemovePack(state.pack),
            icon: const Icon(Icons.delete_outline,
                color: SpaceTheme.moonSilver, size: 20),
          ),
      ],
    );
  }

  /// Downloads a pack from Settings, with the same consent + progress dialog
  /// the splash uses.
  Future<void> _installPack(String code) async {
    await context.read<LanguagePackService>().selectLanguage(code);
    if (!mounted) return;
    setState(() => currentLearningLanguage = code);
    final ok = await showLanguagePackDialog(context, languageCode: code);
    if (!mounted) return;
    if (ok == true) {
      setState(() {
        currentLearningLanguage =
            context.read<VocabularyService>().learningLanguage;
        _sourcesLoaded = false;
        _availableSources = {};
      });
      await _loadVocabularySources();
      if (!mounted) return;
      final pack = languagePackFor(code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            S.of(context)!.packReadyToast(pack?.nativeName ?? code),
          ),
          backgroundColor: SpaceTheme.alienGreen,
        ),
      );
    }
  }

  Future<void> _confirmRemovePack(LanguagePack pack) async {
    final s = S.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        title: Text(
          s.packRemoveConfirmTitle(pack.nativeName),
          style: SpaceTheme.headlineStyle.copyWith(fontSize: 18),
        ),
        content: Text(
          s.packRemoveConfirmMessage(pack.nativeName,
              pack.installedSizeLabel ?? pack.downloadSizeLabel),
          style: SpaceTheme.bodyStyle,
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel, style: SpaceTheme.bodyStyle),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              s.packRemoveAction,
              style: SpaceTheme.buttonStyle
                  .copyWith(color: SpaceTheme.planetOrange),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final removed = await context.read<LanguagePackService>().remove(pack.code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed
              ? s.packRemoved(pack.nativeName)
              : s.packRemoveFailed(pack.nativeName),
        ),
        backgroundColor:
            removed ? SpaceTheme.alienGreen : SpaceTheme.rocketRed,
      ),
    );
  }

  Widget _buildLearningLanguageOption(String displayName, String languageCode) {
    final isSelected = currentLearningLanguage == languageCode;

    return GestureDetector(
      onTap: _isLoading ? null : () => _changeLearningLanguage(languageCode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? SpaceTheme.starYellow.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? SpaceTheme.starYellow
                : Colors.white.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? SpaceTheme.starYellow : Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  color: isSelected ? SpaceTheme.starYellow : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check,
                color: SpaceTheme.starYellow,
                size: 20,
              ),
            if (_isLoading && isSelected)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    SpaceTheme.starYellow,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultySettings() {
    return SlideTransition(
      position: _settingAnimations[4],
      child: _buildSettingsCard(
        title: S.of(context)!.difficulty,
        icon: Icons.tune,
        children: [
          Consumer2<GameProvider, LearnerProfileService>(
            builder: (context, gameProvider, profile, child) {
              return Column(
                children: [
                  _buildStatRow(
                    label: S.of(context)!.currentGrade,
                    value: S.of(context)!.gradeN(gameProvider.grade),
                    icon: Icons.menu_book_outlined,
                    onTap: () => _showGradeSelector(gameProvider),
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
                  const SizedBox(height: 16),
                  DropdownButtonFormField<LearnerGoal>(
                    initialValue: profile.goal,
                    dropdownColor: SpaceTheme.deepSpace,
                    decoration: InputDecoration(
                        labelText: S.of(context)!.onboardingGoal),
                    items: LearnerGoal.values
                        .map((goal) => DropdownMenuItem(
                              value: goal,
                              child: Text(_goalLabel(goal)),
                            ))
                        .toList(),
                    onChanged: (goal) {
                      if (goal != null) profile.setGoal(goal);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: profile.sessionMinutes,
                    dropdownColor: SpaceTheme.deepSpace,
                    decoration: InputDecoration(
                        labelText: S.of(context)!.onboardingDailyTime),
                    items: const [5, 10, 15]
                        .map((minutes) => DropdownMenuItem(
                              value: minutes,
                              child: Text('$minutes min'),
                            ))
                        .toList(),
                    onChanged: (minutes) {
                      if (minutes != null) profile.setSessionMinutes(minutes);
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

  Widget _buildProgressSettings() {
    return SlideTransition(
      position: _settingAnimations[5],
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
      position: _settingAnimations[6],
      child: _buildSettingsCard(
        title: S.of(context)!.about,
        icon: Icons.info,
        children: [
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final v = snap.data == null
                  ? '…'
                  : '${snap.data!.version} (${snap.data!.buildNumber})';
              return _buildInfoRow(S.of(context)!.appVersion, v);
            },
          ),
          _buildInfoRow(S.of(context)!.developer, S.of(context)!.developerName),
          _buildInfoRow(
              S.of(context)!.targetAge, S.of(context)!.targetAgeRange),
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
          _buildFeatureRow(
            title: S.of(context)!.diagnosticsTitle,
            subtitle: S.of(context)!.diagnosticsSubtitle,
            icon: Icons.bug_report,
            isLocked: false,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DiagnosticsScreen(),
                ),
              );
            },
          ),
          _buildFeatureRow(
            title: S.of(context)!.parentDashboardTitle,
            subtitle: S.of(context)!.parentDashboardSubtitle,
            icon: Icons.family_restroom,
            isLocked: false,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ParentDashboardScreen(),
                ),
              );
            },
          ),
          _buildFeatureRow(
            title: S.of(context)!.privacyTitle,
            subtitle: S.of(context)!.privacySubtitle,
            icon: Icons.shield_outlined,
            isLocked: false,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const PrivacyPolicyDialog(),
              );
            },
          ),
          _buildFeatureRow(
            title: S.of(context)!.deleteAllDataTitle,
            subtitle: S.of(context)!.deleteAllDataSubtitle,
            icon: Icons.delete_forever,
            isLocked: false,
            onTap: () => _confirmResetAllData(context),
          ),
          _buildFeatureRow(
            title: S.of(context)!.licensesTitle,
            subtitle: S.of(context)!.viewOssLicenses,
            icon: Icons.article_rounded,
            isLocked: false,
            onTap: () async {
              final info = await PackageInfo.fromPlatform();
              if (!context.mounted) return;
              showLicensePage(
                context: context,
                applicationName: S.of(context)!.appName,
                applicationVersion: '${info.version}+${info.buildNumber}',
                applicationLegalese: S.of(context)!.appLegalese,
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Icon(
                    Icons.rocket_launch,
                    size: 48,
                    color: SpaceTheme.starYellow,
                  ),
                ),
              );
            },
          ),
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
                  color: SpaceTheme.starYellow.withValues(alpha: 0.2),
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
            onChanged: isLocked ? null : onChanged,
            activeThumbColor: SpaceTheme.alienGreen,
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

  void _changeLanguage(String localeCode) async {
    if (localeCode == currentLocale) {
      if (kDebugMode)
        debugPrint("[SETTINGS] 🌍 Language unchanged: $localeCode");
      return;
    }

    if (kDebugMode)
      debugPrint(
          "[SETTINGS] 🌍 Changing language from $currentLocale to $localeCode");

    setState(() {
      _isLoading = true;
      currentLocale = localeCode;
    });

    try {
      await _saveLanguagePreference(localeCode);

      if (mounted) {
        MyApp.setLocale(context, Locale(localeCode));
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint("[SETTINGS] ❌ Failed to change language: $e");
      if (kDebugMode) debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.languageChangeFailed),
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

  /// Switches the learning language. If the target pack isn't on the device,
  /// this offers the download (with progress) instead of silently trying to
  /// fetch ~25 MB — and a failure leaves the previous language active rather
  /// than a half-initialized one, which is what used to crash the minigames.
  Future<void> _changeLearningLanguage(String languageCode) async {
    if (languageCode == currentLearningLanguage &&
        context.read<LanguagePackService>().isActivePackReady) {
      if (kDebugMode) {
        debugPrint("[SETTINGS] 📚 Learning language unchanged: $languageCode");
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
        "[SETTINGS] 📚 Changing learning language from "
        "$currentLearningLanguage to $languageCode",
      );
    }

    final service = context.read<LanguagePackService>();
    await service.selectLanguage(languageCode);
    if (!mounted) return;
    setState(() => currentLearningLanguage = languageCode);
    if (!service.isInstalled(languageCode)) {
      // Not downloaded yet → consent + progress dialog, which also activates
      // the pack on success.
      await _installPack(languageCode);
      return;
    }

    setState(() {
      _isLoading = true;
      _sourcesLoaded = false;
      _availableSources = {};
    });

    try {
      final activated = await service.activate(languageCode);
      if (!mounted) return;

      if (!activated) {
        // The pack vanished between the status check and the switch (cleared
        // storage, corrupted file): offer the download instead of failing.
        await _installPack(languageCode);
        return;
      }

      setState(() {
        currentLearningLanguage =
            context.read<VocabularyService>().learningLanguage;
      });
      await _loadVocabularySources();
      if (!mounted) return;

      final pack = languagePackFor(languageCode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            S.of(context)!.packReadyToast(pack?.nativeName ?? languageCode),
          ),
          backgroundColor: SpaceTheme.alienGreen,
        ),
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint("[SETTINGS] ❌ Failed to change learning language: $e");
        debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
      }

      if (mounted) {
        setState(() {
          // Keep the desired selection even if the installer rolled back.
          currentLearningLanguage =
              context.read<LanguagePackService>().selectedLanguage;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.learningLanguageChangeFailed),
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
    if (kDebugMode)
      debugPrint("[SETTINGS] 🌍 Saving language preference: $localeCode");

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', localeCode);

      final savedLocale = prefs.getString('language');
      if (kDebugMode) debugPrint("[SETTINGS] ✅ Language saved successfully");
      if (kDebugMode)
        debugPrint(
            "[SETTINGS] 🔍 Verification - language now reads: $savedLocale");

      final allKeys = prefs.getKeys();
      if (kDebugMode) debugPrint("[SETTINGS] 🗂️ All current preferences:");
      for (final key in allKeys) {
        final value = prefs.get(key);
        if (kDebugMode) debugPrint("[SETTINGS]   $key: $value");
      }
    } catch (e, stackTrace) {
      if (kDebugMode)
        debugPrint("[SETTINGS] ❌ Failed to save language preference: $e");
      if (kDebugMode) debugPrint("[SETTINGS] 📚 Stack trace: $stackTrace");
      rethrow;
    }
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
                if (kDebugMode)
                  debugPrint("[SETTINGS] 🎓 Grade changed to: $grade");
                gameProvider.setGrade(grade);
                Navigator.of(context).pop();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? SpaceTheme.starYellow.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? SpaceTheme.starYellow
                        : Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      color:
                          isSelected ? SpaceTheme.starYellow : Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      S.of(context)!.gradeN(grade),
                      style: TextStyle(
                        color:
                            isSelected ? SpaceTheme.starYellow : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
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
        return S.of(context)!.difficultyDescGrade3;
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

  String _goalLabel(LearnerGoal goal) {
    final s = S.of(context)!;
    switch (goal) {
      case LearnerGoal.balanced:
        return s.goalBalanced;
      case LearnerGoal.vocabulary:
        return s.goalVocabulary;
      case LearnerGoal.spelling:
        return s.goalSpelling;
      case LearnerGoal.grammar:
        return s.goalGrammar;
      case LearnerGoal.dafDaz:
        return s.goalDafDaz;
    }
  }

  /// Parental-gated full reset. Math challenge first, then existing
  /// confirmation dialog.
  void _confirmResetAllData(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ParentalGateDialog(
        onSuccess: () {
          Navigator.of(context).pop();
          _showResetDialog();
        },
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
            autofocus: true,
            onPressed: () {
              if (kDebugMode)
                debugPrint("[SETTINGS] 🗑️ Resetting all game progress");
              context.read<GameProvider>().resetGame();
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

/// Small status pill used by the language-pack rows.
class _PackChip extends StatelessWidget {
  const _PackChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
