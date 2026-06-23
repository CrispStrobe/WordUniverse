// lib/shared/widgets/parental_gate.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/space_theme.dart';
import '../../generated/l10n.dart';
import '../../shared/utils/app_utilities.dart';

class ParentalGateDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const ParentalGateDialog({super.key, required this.onSuccess});

  @override
  State<ParentalGateDialog> createState() => _ParentalGateDialogState();
}

class _ParentalGateDialogState extends State<ParentalGateDialog> {
  late int num1;
  late int num2;
  String challenge = "";
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    num1 = math.Random().nextInt(5) + 5; // e.g., 5-9
    num2 = math.Random().nextInt(5) + 1; // e.g., 1-5
    challenge = "$num1 + $num2";
  }

  void _checkAnswer() {
    final s = S.of(context)!;
    final userAnswer = int.tryParse(_controller.text);
    if (userAnswer != null && userAnswer == num1 + num2) {
        widget.onSuccess();
    } else {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(s.pleaseTryAgain), // Localized
            backgroundColor: SpaceTheme.rocketRed,
        ),
        );
        _controller.clear();
    }
    }


  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!; // Get the localization delegate
    return SpaceDialog(
      title: s.parentalGateTitle, // Localized
      content: s.parentalGateChallenge, // Localized
      customContent: Column(
        children: [
          Text(
            challenge,
            style: SpaceTheme.headlineStyle.copyWith(color: SpaceTheme.starYellow),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: SpaceTheme.bodyStyle.copyWith(color: Colors.white, fontSize: 24),
            decoration: const InputDecoration(
              hintText: '?',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), 
            child: Text(s.cancel) // Use existing 'cancel' key
        ),
        ElevatedButton(
            autofocus: true,
            onPressed: _checkAnswer,
            child: Text(s.confirm) // Localized
        ),
      ],
    );
  }
}