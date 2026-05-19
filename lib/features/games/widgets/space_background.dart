import 'package:flutter/material.dart';

class SpaceBackground extends StatelessWidget {
  final Widget child;
  
  const SpaceBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B1426), // spaceBlue
            Color(0xFF1A1A2E), // deepSpace
            Color(0xFF16213E), // nebulaPurple
          ],
        ),
      ),
      child: child,
    );
  }
}