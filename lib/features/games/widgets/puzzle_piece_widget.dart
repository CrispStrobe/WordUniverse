// lib/features/games/widgets/puzzle_piece_widget.dart
import 'package.flutter/material.dart';
import 'dart:ui' as ui;

// A simple model to hold puzzle piece data
class PuzzlePieceData {
  final int id;
  final int value; // The math answer
  final ui.Image image;
  final Offset targetPosition; // Position on the final board
  final Size size;
  
  PuzzlePieceData({
    required this.id,
    required this.value,
    required this.image,
    required this.targetPosition,
    required this.size,
  });
}

class PuzzlePieceWidget extends StatelessWidget {
  final PuzzlePieceData piece;

  const PuzzlePieceWidget({super.key, required this.piece});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: piece.size,
      painter: PuzzlePiecePainter(
        image: piece.image,
        value: piece.value,
        textStyle: Theme.of(context).textTheme.headlineMedium!.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              shadows: [
                const Shadow(blurRadius: 2.0, color: Colors.black, offset: Offset(2, 2)),
              ],
            ),
      ),
    );
  }
}

class PuzzlePiecePainter extends CustomPainter {
  final ui.Image image;
  final int value;
  final TextStyle textStyle;

  PuzzlePiecePainter({required this.image, required this.value, required this.textStyle});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    
    // Draw the piece's image content
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
    
    // Draw a semi-transparent overlay to make the number more readable
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withOpacity(0.3),
    );

    // Draw the number (answer) in the center
    final textSpan = TextSpan(text: value.toString(), style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: size.width);
    final offset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}