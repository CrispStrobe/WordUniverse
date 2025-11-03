import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../providers/game_provider.dart';

// Space Background Widget with animated stars and planets
class SpaceBackground extends StatefulWidget {
  final Widget child;
  
  const SpaceBackground({
    super.key,
    required this.child,
  });

  @override
  State<SpaceBackground> createState() => _SpaceBackgroundState();
}

class _SpaceBackgroundState extends State<SpaceBackground>
    with TickerProviderStateMixin {
  
  late AnimationController _starsController;
  late AnimationController _planetsController;
  late List<Star> stars;
  late List<Planet> planets;
  
  @override
  void initState() {
    super.initState();
    
    _starsController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    
    _planetsController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    )..repeat();
    
    _generateStars();
    _generatePlanets();
  }
  
  @override
  void dispose() {
    _starsController.dispose();
    _planetsController.dispose();
    super.dispose();
  }
  
  void _generateStars() {
    final random = math.Random();
    stars = List.generate(100, (index) {
      return Star(
        position: Offset(
          random.nextDouble() * 2000,
          random.nextDouble() * 1000,
        ),
        size: random.nextDouble() * 3 + 1,
        opacity: random.nextDouble() * 0.8 + 0.2,
        twinkleSpeed: random.nextDouble() * 2 + 1,
      );
    });
  }
  
  void _generatePlanets() {
    final random = math.Random();
    planets = List.generate(5, (index) {
      return Planet(
        position: Offset(
          random.nextDouble() * 1500,
          random.nextDouble() * 800,
        ),
        size: random.nextDouble() * 60 + 40,
        color: [
          SpaceTheme.planetOrange,
          SpaceTheme.cosmicPink,
          SpaceTheme.alienGreen,
          SpaceTheme.starYellow,
          SpaceTheme.moonSilver,
        ][index],
        rotationSpeed: random.nextDouble() * 0.5 + 0.2,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: SpaceTheme.spaceGradient,
      ),
      child: Stack(
        children: [
          // Animated Stars
          AnimatedBuilder(
            animation: _starsController,
            builder: (context, child) {
              return CustomPaint(
                painter: StarsPainter(
                  stars: stars,
                  animation: _starsController.value,
                ),
                size: MediaQuery.of(context).size,
              );
            },
          ),
          
          // Animated Planets
          AnimatedBuilder(
            animation: _planetsController,
            builder: (context, child) {
              return CustomPaint(
                painter: PlanetsPainter(
                  planets: planets,
                  animation: _planetsController.value,
                ),
                size: MediaQuery.of(context).size,
              );
            },
          ),
          
          // Content
          widget.child,
        ],
      ),
    );
  }
}

// Game UI Header Widget
class GameUI extends StatelessWidget {
  final String title;
  final int level;
  final int? timeLeft;
  final VoidCallback onBack;
  
  const GameUI({
    super.key,
    required this.title,
    required this.level,
    this.timeLeft,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E2235),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Back Button
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 28,
            ),
            style: IconButton.styleFrom(
              backgroundColor: SpaceTheme.deepSpace.withOpacity(0.8),
              padding: const EdgeInsets.all(12),
            ),
          ),
          
          const SizedBox(width: 20),
          
          // Title
          Expanded(
            child: Text(
              title,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 28),
            ),
          ),
          
          // Game Stats
          Row(
            children: [
              // Level
              _buildStatItem(
                icon: Icons.emoji_events,
                label: S.of(context).level,
                value: level.toString(),
                color: SpaceTheme.starYellow,
              ),
              
              const SizedBox(width: 20),
              
              // Score
              Consumer<GameProvider>(
                builder: (context, gameProvider, child) {
                  return _buildStatItem(
                    icon: Icons.star,
                    label: S.of(context).score,
                    value: gameProvider.score.toString(),
                    color: SpaceTheme.alienGreen,
                  );
                },
              ),
              
              // Time (if provided)
              if (timeLeft != null) ...[
                const SizedBox(width: 20),
                _buildStatItem(
                  icon: Icons.timer,
                  label: S.of(context).time,
                  value: _formatTime(timeLeft!),
                  color: timeLeft! > 10 ? SpaceTheme.cosmicPink : SpaceTheme.rocketRed,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceTheme.deepSpace.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: SpaceTheme.bodyStyle.copyWith(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              Text(
                value,
                style: SpaceTheme.titleStyle.copyWith(
                  fontSize: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

// Space Button Widget
class SpaceButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  final Color? color;
  final double? width;
  final double? height;
  
  const SpaceButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.color,
    this.width,
    this.height,
  });

  @override
  State<SpaceButton> createState() => _SpaceButtonState();
}

class _SpaceButtonState extends State<SpaceButton>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }
  
  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
  }
  
  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              height: widget.height ?? 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.color ?? SpaceTheme.planetOrange,
                    (widget.color ?? SpaceTheme.planetOrange).withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: (widget.color ?? SpaceTheme.planetOrange).withOpacity(0.5),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    widget.text,
                    style: SpaceTheme.buttonStyle,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Data classes for space elements
class Star {
  final Offset position;
  final double size;
  final double opacity;
  final double twinkleSpeed;
  
  Star({
    required this.position,
    required this.size,
    required this.opacity,
    required this.twinkleSpeed,
  });
}

class Planet {
  final Offset position;
  final double size;
  final Color color;
  final double rotationSpeed;
  
  Planet({
    required this.position,
    required this.size,
    required this.color,
    required this.rotationSpeed,
  });
}

// Custom Painters
class StarsPainter extends CustomPainter {
  final List<Star> stars;
  final double animation;
  
  StarsPainter({
    required this.stars,
    required this.animation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in stars) {
      final twinkle = math.sin(animation * 2 * math.pi * star.twinkleSpeed) * 0.5 + 0.5;
      final paint = Paint()
        ..color = SpaceTheme.starYellow.withOpacity(star.opacity * twinkle)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(
          star.position.dx % size.width,
          star.position.dy % size.height,
        ),
        star.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(StarsPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}

class PlanetsPainter extends CustomPainter {
  final List<Planet> planets;
  final double animation;
  
  PlanetsPainter({
    required this.planets,
    required this.animation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final planet in planets) {
      final rotation = animation * planet.rotationSpeed * 2 * math.pi;
      
      canvas.save();
      canvas.translate(
        planet.position.dx % size.width,
        planet.position.dy % size.height,
      );
      canvas.rotate(rotation);
      
      // Planet gradient
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            planet.color,
            planet.color.withOpacity(0.6),
            planet.color.withOpacity(0.3),
          ],
        ).createShader(Rect.fromCircle(
          center: Offset.zero,
          radius: planet.size / 2,
        ));
      
      canvas.drawCircle(Offset.zero, planet.size / 2, paint);
      
      // Planet details (rings, spots, etc.)
      final detailPaint = Paint()
        ..color = Colors.white.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      
      canvas.drawCircle(Offset.zero, planet.size / 3, detailPaint);
      
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PlanetsPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}