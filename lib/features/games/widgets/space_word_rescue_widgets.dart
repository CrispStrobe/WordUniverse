// ignore_for_file: unused_element
import 'package:flutter/material.dart';

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';

enum AnswerResultType {
  perfect,
  commonMistake,
  incorrect
}

class WordParticle {
  Offset position;
  Offset velocity;
  Color color;
  double size;
  double life;

  WordParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    this.life = 1.0,
  });
}

class ParticlePainter extends CustomPainter {
  final List<WordParticle> particles;

  ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final paint = Paint()
        ..color = particle.color.withValues(alpha: particle.life)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        particle.position,
        particle.size * particle.life,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ParticlePainter oldDelegate) => true;
}

class SpaceWordRescueCard extends StatelessWidget {
  final VoidCallback onTap;

  const SpaceWordRescueCard({
    Key? key,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SpaceTheme.planetOrange.withValues(alpha: 0.8),
              SpaceTheme.cosmicPink.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: SpaceTheme.planetOrange.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.rocket_launch,
              size: 48,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              s.wordRescueTitle,
              style: SpaceTheme.titleStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              s.wordRescueCardDescription,
              style: SpaceTheme.bodyStyle.copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
