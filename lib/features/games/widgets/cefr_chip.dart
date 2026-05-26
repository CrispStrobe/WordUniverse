import 'package:flutter/material.dart';

/// A small colored badge showing a CEFR level (A1–C2).
class CefrChip extends StatelessWidget {
  final String level;
  final bool small;
  const CefrChip(this.level, {super.key, this.small = false});

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      'A1' => const Color(0xFF43A047),
      'A2' => const Color(0xFF7CB342),
      'B1' => const Color(0xFF1E88E5),
      'B2' => const Color(0xFF8E24AA),
      'C1' => const Color(0xFFFB8C00),
      'C2' => const Color(0xFFE53935),
      _ => Colors.white38,
    };
    final hPad = small ? 7.0 : 10.0;
    final vPad = small ? 2.0 : 3.0;
    final fontSize = small ? 10.0 : 11.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        'CEFR $level',
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
