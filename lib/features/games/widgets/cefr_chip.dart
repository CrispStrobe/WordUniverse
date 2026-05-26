import 'package:flutter/material.dart';

/// A small colored badge showing a CEFR level (A1–C2).
class CefrChip extends StatelessWidget {
  final String level;
  const CefrChip(this.level, {super.key});

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        'CEFR $level',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
