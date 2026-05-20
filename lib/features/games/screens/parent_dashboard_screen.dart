// lib/features/games/screens/parent_dashboard_screen.dart
//
// A grown-up summary of the player's progress. PIN-gated (4 digits).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/services/cognitive_profile_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';

const _kParentPinKey = 'parent_pin';
const _kDefaultParentPin = '1234';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  bool _unlocked = false;
  String? _storedPin;
  final TextEditingController _pinController = TextEditingController();
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _loadPin();
  }

  Future<void> _loadPin() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _storedPin = prefs.getString(_kParentPinKey) ?? _kDefaultParentPin;
    });
  }

  void _submitPin() {
    if (_pinController.text == _storedPin) {
      setState(() {
        _unlocked = true;
        _pinError = null;
      });
    } else {
      final s = S.of(context);
      setState(() => _pinError = s?.parentPinWrong ?? 'Falscher Code');
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    return Scaffold(
      backgroundColor: SpaceTheme.deepSpace,
      appBar: AppBar(
        title: Text(s.parentDashboardTitle),
        backgroundColor: SpaceTheme.deepSpace,
      ),
      body: _unlocked ? _buildDashboard(context, s) : _buildLockScreen(s),
    );
  }

  Widget _buildLockScreen(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 64, color: SpaceTheme.starYellow),
            const SizedBox(height: 16),
            Text(s.parentPinTitle, style: SpaceTheme.headlineStyle),
            const SizedBox(height: 8),
            Text(
              s.parentPinHelp(_kDefaultParentPin),
              textAlign: TextAlign.center,
              style: SpaceTheme.bodyStyle
                  .copyWith(fontSize: 13, color: Colors.white60),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, letterSpacing: 8),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  counterText: '',
                  errorText: _pinError,
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: SpaceTheme.starYellow),
                  ),
                ),
                onSubmitted: (_) => _submitPin(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submitPin,
              child: Text(s.parentPinUnlock),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, S s) {
    final gp = context.watch<GameProvider>();
    final cp = context.watch<CognitiveProfileService>();
    final sri = context.watch<SriService>();

    final progress = gp.gameProgress;
    final activeGames = progress.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final snapshot = cp.snapshot;
    SkillCategory? strongest;
    SkillCategory? weakest;
    double bestRatio = -1;
    double worstRatio = 2;
    snapshot.forEach((skill, diffMap) {
      final attempts =
          diffMap.values.fold<int>(0, (s, v) => s + v.attempts);
      if (attempts < 5) return;
      final successes =
          diffMap.values.fold<int>(0, (s, v) => s + v.successes);
      final ratio = successes / attempts;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        strongest = skill;
      }
      if (ratio < worstRatio) {
        worstRatio = ratio;
        weakest = skill;
      }
    });

    final sriTotal = sri.totalTrackedItems;
    final sriMastered = sri.masteredItemCount;
    final sriDue = sri.getAvailableReviewCount();
    final masteryPct =
        sriTotal > 0 ? (sriMastered / sriTotal * 100).round() : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: s.parentSectionLanguageMastery,
          children: [
            _StatLine(
                label: s.parentItemsTracked, value: sriTotal.toString()),
            _StatLine(
                label: s.parentItemsMastered,
                value: s.parentItemsMasteredValue(sriMastered, masteryPct)),
            _StatLine(
                label: s.parentItemsDue,
                value: sriDue.toString()),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: s.parentSectionStrengths,
          children: [
            if (cp.totalAttempts == 0)
              _StatLine(
                  label: s.parentDataBasis, value: s.parentNoDataYet),
            if (strongest != null)
              _StatLine(
                label: s.parentStrongestCategory,
                value: s.parentCategoryValue(
                    strongest!.name, (bestRatio * 100).round()),
              ),
            if (weakest != null && weakest != strongest)
              _StatLine(
                label: s.parentWeakestCategory,
                value: s.parentCategoryValue(
                    weakest!.name, (worstRatio * 100).round()),
              ),
            _StatLine(
                label: s.parentTotalAttempts,
                value: cp.totalAttempts.toString()),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: s.parentSectionGameProgress,
          children: activeGames.isEmpty
              ? [
                  _StatLine(
                      label: s.parentGamesPlayed, value: s.parentNoneYet),
                ]
              : [
                  for (final entry in activeGames)
                    _StatLine(
                      label: _gameLabel(entry.key),
                      value: s.parentLevelValue(entry.value),
                    ),
                ],
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: _changePin,
          icon: const Icon(Icons.lock_reset, color: Colors.white70),
          label: Text(s.parentChangePin,
              style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }

  Future<void> _changePin() async {
    final s = S.of(context)!;
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String? err;
        return StatefulBuilder(
          builder: (context, setSt) => AlertDialog(
            backgroundColor: SpaceTheme.deepSpace,
            title: Text(s.parentChangePinDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: s.parentNewPinLabel),
                ),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                      labelText: s.parentConfirmPinLabel, errorText: err),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s.cancel),
              ),
              TextButton(
                onPressed: () {
                  if (pinController.text.length != 4) {
                    setSt(() => err = s.parentPinRequireFour);
                    return;
                  }
                  if (pinController.text != confirmController.text) {
                    setSt(() => err = s.parentPinMismatch);
                    return;
                  }
                  Navigator.pop(context, pinController.text);
                },
                child: Text(s.save),
              ),
            ],
          ),
        );
      },
    );
    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kParentPinKey, result);
      if (mounted) {
        setState(() => _storedPin = result);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.parentPinUpdated)),
        );
      }
    }
  }

  String _gameLabel(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: SpaceTheme.nebulaPurple.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SpaceTheme.titleStyle.copyWith(fontSize: 16)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  const _StatLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: SpaceTheme.bodyStyle
                  .copyWith(fontSize: 13, color: Colors.white70),
            ),
          ),
          Text(value,
              style: SpaceTheme.titleStyle
                  .copyWith(fontSize: 14, color: Colors.white)),
        ],
      ),
    );
  }
}
