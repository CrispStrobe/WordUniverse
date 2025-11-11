// lib/features/settings/widgets/manage_sets_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../screens/custom_subset_screen.dart';

class ManageSetsDialog extends StatefulWidget {
  const ManageSetsDialog({super.key});

  @override
  State<ManageSetsDialog> createState() => _ManageSetsDialogState();
}

class _ManageSetsDialogState extends State<ManageSetsDialog> {
  // This widget is stateful to reflect deletions in the list immediately

  Future<void> _deleteSet(VocabularySet set) async {
    final s = S.of(context)!;
    final vocabService = context.read<VocabularyService>();

    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SpaceTheme.deepSpace,
        title: Text(s.customSetDeleteConfirmTitle, style: SpaceTheme.titleStyle),
        content: Text(
          s.customSetDeleteConfirmContent(set.name),
          style: SpaceTheme.bodyStyle,
        ),
        actions: [
          TextButton(
            child: Text(S.of(context)!.cancel, style: TextStyle(color: SpaceTheme.moonSilver)),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SpaceTheme.rocketRed),
            child: Text(s.customSetDelete, style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await vocabService.deleteCustomSet(set.id);
      // We call setState to force this dialog's consumer to rebuild
      setState(() {});
    }
  }

  void _editSet(VocabularySet set) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomSubsetScreen(set: set),
      ),
    ).then((_) {
      // When the edit screen closes, refresh the list
      setState(() {});
    });
  }

  void _createNewSet() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CustomSubsetScreen(), // No set passed
      ),
    ).then((_) {
      // When the create screen closes, refresh the list
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    // We use a Consumer *inside* the dialog
    return Consumer<VocabularyService>(
      builder: (context, vocabService, child) {
        final customSets = vocabService.getCustomSets();

        return AlertDialog(
          backgroundColor: SpaceTheme.deepSpace,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: SpaceTheme.nebulaPurple),
          ),
          title: Row(
            children: [
              Icon(Icons.folder_special, color: SpaceTheme.starYellow),
              SizedBox(width: 12),
              Expanded(child: Text(s.taskManageSets, style: SpaceTheme.titleStyle)),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: customSets.isEmpty
                ? Center(
                    child: Text(
                      "No custom sets created yet.",
                      style: SpaceTheme.bodyStyle.copyWith(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: customSets.length,
                    itemBuilder: (context, index) {
                      final set = customSets[index];
                      return Container(
                        margin: EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: SpaceTheme.deepSpace.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: ListTile(
                          title: Text(set.name, style: SpaceTheme.bodyStyle),
                          subtitle: Text(
                            set.description.isEmpty ? "No description" : set.description,
                            style: SpaceTheme.bodyStyle.copyWith(fontSize: 12, color: Colors.white60),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, color: SpaceTheme.alienGreen),
                                onPressed: () => _editSet(set),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete, color: SpaceTheme.rocketRed),
                                onPressed: () => _deleteSet(set),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              child: Text(S.of(context)!.cancel, style: TextStyle(color: SpaceTheme.moonSilver)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.add_circle),
              label: Text(s.customSetCreateTitle),
              style: ElevatedButton.styleFrom(backgroundColor: SpaceTheme.alienGreen),
              onPressed: _createNewSet,
            ),
          ],
        );
      },
    );
  }
}