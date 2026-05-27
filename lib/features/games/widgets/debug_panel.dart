import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/debug_provider.dart';
import '../../../core/theme/space_theme.dart';
import '../../../features/games/providers/game_provider.dart';
import '../../../generated/l10n.dart';

class DebugPanel extends StatefulWidget {
  const DebugPanel({super.key});

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  late int _grade;
  late int _level;
  Set<String> _selectedGameKeys = {};
  bool _selectAll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final gameProvider = context.read<GameProvider>();
    _grade = gameProvider.grade;
    _level = gameProvider.level;
  }

  @override
  Widget build(BuildContext context) {
    final debugProvider = context.watch<DebugProvider>();
    final s = S.of(context)!;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: SpaceTheme.deepSpace.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SpaceTheme.nebulaPurple, width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.debugPanelTitle, style: SpaceTheme.headlineStyle),
              const SizedBox(height: 24),
              _buildSwitch(s.debugForceUnlock, debugProvider.isPaidUnlockedForced, (value) {
                context.read<DebugProvider>().setPaidUnlock(value);
              }),
              const Divider(color: SpaceTheme.nebulaPurple, height: 32),
              _buildSlider('Grade', _grade.toDouble(), 1, 6, (value) {
                setState(() => _grade = value.toInt());
              }),
              _buildSlider('Game Level', _level.toDouble(), 1, 20, (value) {
                setState(() => _level = value.toInt());
              }),
              const Divider(color: SpaceTheme.nebulaPurple, height: 32),
              Text(
                'Force level for selected games:',
                style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.starYellow),
              ),
              _buildSelectAllToggle(),
              _buildGameCheckboxList(),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                onPressed: () {
                  final gp = context.read<GameProvider>();
                  gp.setDifficulty(_grade, _level);
                  gp.debugSetGameLevels(_level, _selectedGameKeys.toList());
                  Navigator.of(context).pop();
                },
                style: SpaceTheme.primaryButtonStyle,
                label: Text(s.debugApplyAndClose),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectAllToggle() {
    return CheckboxListTile(
      title: Text(
        'Select all games',
        style: SpaceTheme.bodyStyle.copyWith(fontStyle: FontStyle.italic),
      ),
      value: _selectAll,
      onChanged: (bool? value) {
        setState(() {
          _selectAll = value ?? false;
          if (_selectAll) {
            _selectedGameKeys = context.read<GameProvider>().gameSkillMap.keys.toSet();
          } else {
            _selectedGameKeys.clear();
          }
        });
      },
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: SpaceTheme.alienGreen,
      checkColor: SpaceTheme.deepSpace,
      dense: true,
    );
  }

  Widget _buildGameCheckboxList() {
    final allGameKeys = context.read<GameProvider>().gameSkillMap.keys.toList()..sort();

    return Container(
      height: 200,
      width: double.maxFinite,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: allGameKeys.length,
        itemBuilder: (context, index) {
          final gameKey = allGameKeys[index];
          return CheckboxListTile(
            title: Text(gameKey, style: SpaceTheme.bodyStyle.copyWith(fontSize: 12)),
            value: _selectedGameKeys.contains(gameKey),
            onChanged: (bool? value) {
              final total = allGameKeys.length;
              setState(() {
                if (value == true) {
                  _selectedGameKeys.add(gameKey);
                } else {
                  _selectedGameKeys.remove(gameKey);
                }
                _selectAll = _selectedGameKeys.length == total;
              });
            },
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: SpaceTheme.alienGreen,
            checkColor: SpaceTheme.deepSpace,
          );
        },
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.starYellow)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: SpaceTheme.alienGreen,
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${value.toInt()}',
          style: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.starYellow),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          label: value.toInt().toString(),
          onChanged: onChanged,
          activeColor: SpaceTheme.alienGreen,
          inactiveColor: SpaceTheme.nebulaPurple,
        ),
      ],
    );
  }
}
