// lib/features/settings/screens/custom_subset_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../../core/services/vocabulary_service.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../../games/providers/game_provider.dart';
import '../../games/widgets/space_background.dart';

class CustomSubsetScreen extends StatefulWidget {
  /// Pass an existing set to edit it, or null to create a new one.
  final VocabularySet? set;

  const CustomSubsetScreen({super.key, this.set});

  @override
  State<CustomSubsetScreen> createState() => _CustomSubsetScreenState();
}

class _CustomSubsetScreenState extends State<CustomSubsetScreen> {
  // ... (all state properties are unchanged)
  final _formKey = GlobalKey<FormState>();

  // Form Controllers
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late GradeLevel _targetGrade;

  // Search Controllers
  final _availableSearchController = TextEditingController();
  final _selectedSearchController = TextEditingController();

  // Word Lists
  List<GermanWord> _allWords = [];
  Set<String> _selectedWordIds = {};

  // Filtered Lists for UI
  List<GermanWord> _availableWordsFiltered = [];
  List<GermanWord> _selectedWordsFiltered = [];

  // Source Filtering
  Set<String> _allSources = {};
  Set<String> _selectedSources = {}; // Filters for the 'available' list

  bool _isLoading = true;
  bool get _isEditing => widget.set != null;

  @override
  void initState() {
    super.initState();

    final vocabService = context.read<VocabularyService>();
    final gameProvider = context.read<GameProvider>();

    // 1. Initialize Form Fields
    _nameController = TextEditingController(text: widget.set?.name);
    _descriptionController =
        TextEditingController(text: widget.set?.description);
    final initialBand = widget.set == null
        ? gameProvider.grade
        : bandFromGradeLevel(widget.set!.targetGrade);
    _targetGrade = gradeLevelFromBand(initialBand.clamp(1, 4));

    // 2. Load Vocabulary
    // This NEW method is required in VocabularyService
    _allWords = vocabService.getFullVocabularyList();
    _allSources = vocabService.getAllAvailableSources();

    if (widget.set != null) {
      _selectedWordIds = widget.set!.wordIds.toSet();
    }

    // 3. Add listeners to search controllers
    _availableSearchController.addListener(_runFilter);
    _selectedSearchController.addListener(_runFilter);

    // 4. Run initial filter
    _runFilter();
    setState(() {
      _isLoading = false;
    });
  }

  // ... (dispose, _runFilter, _onWordTapped, _addAllFiltered, _removeAllFiltered are unchanged)
  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _availableSearchController.dispose();
    _selectedSearchController.dispose();
    super.dispose();
  }

  void _runFilter() {
    final availableQuery = _availableSearchController.text.toLowerCase();
    final selectedQuery = _selectedSearchController.text.toLowerCase();

    final newAvailable = <GermanWord>[];
    final newSelected = <GermanWord>[];

    for (final word in _allWords) {
      if (_selectedWordIds.contains(word.id)) {
        // Word is in the RIGHT column (Selected)
        if (selectedQuery.isEmpty ||
            word.word.toLowerCase().contains(selectedQuery)) {
          newSelected.add(word);
        }
      } else {
        // Word is in the LEFT column (Available)

        // Check search query
        if (availableQuery.isNotEmpty &&
            !word.word.toLowerCase().contains(availableQuery)) {
          continue;
        }

        // Check source filters
        if (_selectedSources.isNotEmpty) {
          if (word.sources.isEmpty ||
              !word.sources.any((s) => _selectedSources.contains(s))) {
            continue;
          }
        }

        newAvailable.add(word);
      }
    }

    setState(() {
      _availableWordsFiltered = newAvailable;
      _selectedWordsFiltered = newSelected;
    });
  }

  void _onWordTapped(GermanWord word, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedWordIds.remove(word.id);
      } else {
        _selectedWordIds.add(word.id);
      }
    });
    // Re-run the filter to move the word to the other list
    _runFilter();
  }

  void _addAllFiltered() {
    setState(() {
      for (final word in _availableWordsFiltered) {
        _selectedWordIds.add(word.id);
      }
    });
    _runFilter();
  }

  void _removeAllFiltered() {
    setState(() {
      for (final word in _selectedWordsFiltered) {
        _selectedWordIds.remove(word.id);
      }
    });
    _runFilter();
  }

  Future<void> _onSave() async {
    // ... (this method is unchanged)
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final vocabService = context.read<VocabularyService>();

    final name = _nameController.text;
    final description = _descriptionController.text;
    final wordIds = _selectedWordIds.toList();

    try {
      if (_isEditing) {
        // Update existing set
        await vocabService.updateCustomSet(
          id: widget.set!.id,
          name: name,
          description: description,
          wordIds: wordIds,
          // targetGrade: _targetGrade, // Add this if you modify updateCustomSet
        );
      } else {
        // Create new set
        await vocabService.createCustomSet(
          name: name,
          description: description,
          wordIds: wordIds,
          targetGrade: _targetGrade,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Error saving custom set: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving: $e"),
            backgroundColor: SpaceTheme.rocketRed,
          ),
        );
      }
    }
  }

  // --- DELETED: _onDelete() method is removed from this file ---

  @override
  Widget build(BuildContext context) {
    // ... (build method is unchanged, but the header it calls is)
    final s = S.of(context)!;
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(s),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          _buildForm(s),
                          const Divider(
                              color: SpaceTheme.nebulaPurple, height: 1),
                          Expanded(
                            child: Row(
                              children: [
                                _buildWordColumn(
                                  s.customSetAvailableWords,
                                  _availableSearchController,
                                  _availableWordsFiltered,
                                  false,
                                  s,
                                  onBulkAdd: _addAllFiltered,
                                ),
                                const VerticalDivider(
                                    color: SpaceTheme.nebulaPurple, width: 1),
                                _buildWordColumn(
                                  s.customSetSelectedWords(
                                      _selectedWordIds.length),
                                  _selectedSearchController,
                                  _selectedWordsFiltered,
                                  true,
                                  s,
                                  onBulkRemove: _removeAllFiltered,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- MODIFIED: Header no longer has a Delete button ---
  Widget _buildHeader(S s) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
              padding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              _isEditing ? s.customSetEditTitle : s.customSetCreateTitle,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 32),
            ),
          ),
          // --- DELETE BUTTON REMOVED ---
          const SizedBox(width: 10),
          IconButton(
            onPressed: _onSave,
            icon: const Icon(Icons.save, color: SpaceTheme.alienGreen),
            style: IconButton.styleFrom(
              backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  // ... (rest of the file is unchanged)
  Widget _buildForm(S s) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration:
                  _inputDecoration(s.customSetNameLabel, s.customSetNameHint),
              style: SpaceTheme.bodyStyle,
              validator: (value) =>
                  (value == null || value.isEmpty) ? "Name is required" : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: _inputDecoration(
                  s.customSetDescriptionLabel, s.customSetDescriptionHint),
              style: SpaceTheme.bodyStyle,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<GradeLevel>(
              initialValue: _targetGrade,
              items: [
                DropdownMenuItem(
                    value: GradeLevel.grade1, child: Text(s.gradeN(1))),
                DropdownMenuItem(
                    value: GradeLevel.grade2, child: Text(s.gradeN(2))),
                DropdownMenuItem(
                    value: GradeLevel.grade3, child: Text(s.gradeN(3))),
                DropdownMenuItem(
                    value: GradeLevel.grade4, child: Text(s.gradeN(4))),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _targetGrade = value);
                }
              },
              decoration: _inputDecoration(s.customSetTargetGrade, ""),
              style: SpaceTheme.bodyStyle,
              dropdownColor: SpaceTheme.deepSpace,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.starYellow),
      hintStyle: SpaceTheme.bodyStyle.copyWith(color: Colors.white38),
      filled: true,
      fillColor: SpaceTheme.deepSpace.withValues(alpha: 0.5),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white24)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white24)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SpaceTheme.alienGreen)),
    );
  }

  Widget _buildWordColumn(
    String title,
    TextEditingController controller,
    List<GermanWord> words,
    bool isSelectedList,
    S s, {
    VoidCallback? onBulkAdd,
    VoidCallback? onBulkRemove,
  }) {
    return Expanded(
      child: Column(
        children: [
          // 1. Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style:
                  SpaceTheme.titleStyle.copyWith(color: SpaceTheme.starYellow),
            ),
          ),

          // 2. Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: controller,
              style: SpaceTheme.bodyStyle,
              decoration: _inputDecoration(s.customSetSearchHint, "").copyWith(
                prefixIcon: Icon(Icons.search, color: Colors.white54, size: 20),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // 3. Source Filters (only for 'Available' column)
          if (!isSelectedList) _buildSourceFilterChipList(),

          // 4. Bulk Action Buttons
          if (onBulkAdd != null || onBulkRemove != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextButton(
                child: Text(
                  isSelectedList ? s.customSetRemoveAll : s.customSetAddAll,
                  style: TextStyle(
                      color: isSelectedList
                          ? SpaceTheme.rocketRed
                          : SpaceTheme.alienGreen),
                ),
                onPressed: () {
                  if (isSelectedList) {
                    onBulkRemove?.call();
                  } else {
                    onBulkAdd?.call();
                  }
                },
              ),
            ),

          // 5. Word List
          Expanded(
            child: _buildWordList(words, isSelectedList, s),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceFilterChipList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        children: _allSources.map((source) {
          final isSelected = _selectedSources.contains(source);
          return FilterChip(
            label: Text(source),
            selected: isSelected,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _selectedSources.add(source);
                } else {
                  _selectedSources.remove(source);
                }
                _runFilter();
              });
            },
            backgroundColor: SpaceTheme.deepSpace.withValues(alpha: 0.8),
            selectedColor: SpaceTheme.alienGreen.withValues(alpha: 0.3),
            labelStyle: TextStyle(
                color: isSelected ? SpaceTheme.alienGreen : Colors.white),
            checkmarkColor: SpaceTheme.alienGreen,
            shape: StadiumBorder(
                side: BorderSide(
                    color:
                        isSelected ? SpaceTheme.alienGreen : Colors.white24)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWordList(List<GermanWord> words, bool isSelectedList, S s) {
    if (words.isEmpty) {
      return Center(
        child: Text(
          isSelectedList ? s.customSetEmpty : s.customSetNoAvailable,
          style: SpaceTheme.bodyStyle.copyWith(color: Colors.white54),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      itemCount: words.length,
      itemBuilder: (context, index) {
        final word = words[index];
        return ListTile(
          title: Text(word.displayName, style: SpaceTheme.bodyStyle),
          subtitle: Text(
            word.wordType.toString().split('.').last,
            style: SpaceTheme.bodyStyle
                .copyWith(color: Colors.white54, fontSize: 12),
          ),
          trailing: Icon(
            isSelectedList
                ? Icons.remove_circle_outline
                : Icons.add_circle_outline,
            color:
                isSelectedList ? SpaceTheme.rocketRed : SpaceTheme.alienGreen,
          ),
          onTap: () => _onWordTapped(word, isSelectedList),
        );
      },
    );
  }
}
