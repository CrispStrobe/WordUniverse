import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';

// Loading Screen with Space Animation
class SpaceLoadingScreen extends StatefulWidget {
  final String? message;
  final VoidCallback? onTimeout;
  final Duration timeout;
  
  const SpaceLoadingScreen({
    super.key,
    this.message,
    this.onTimeout,
    this.timeout = const Duration(seconds: 30),
  });

  @override
  State<SpaceLoadingScreen> createState() => _SpaceLoadingScreenState();
}

class _SpaceLoadingScreenState extends State<SpaceLoadingScreen>
    with TickerProviderStateMixin {
  
  late AnimationController _rocketController;
  late AnimationController _orbitsController;
  late AnimationController _starsController;
  
  late Animation<double> _rocketAnimation;
  late Animation<double> _orbitsAnimation;
  late Animation<double> _starsAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _rocketController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _orbitsController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
    
    _starsController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    
    _rocketAnimation = Tween<double>(
      begin: -10.0,
      end: 10.0,
    ).animate(CurvedAnimation(
      parent: _rocketController,
      curve: Curves.easeInOut,
    ));
    
    _orbitsAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(_orbitsController);
    
    _starsAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _starsController,
      curve: Curves.easeInOut,
    ));
    
    // Set timeout
    Future.delayed(widget.timeout, () {
      if (mounted && widget.onTimeout != null) {
        widget.onTimeout!();
      }
    });
  }
  
  @override
  void dispose() {
    _rocketController.dispose();
    _orbitsController.dispose();
    _starsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: SpaceTheme.spaceGradient,
        ),
        child: Stack(
          children: [
            // Animated Stars Background
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _starsAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: LoadingStarsPainter(
                      animation: _starsAnimation.value,
                    ),
                  );
                },
              ),
            ),
            
            // Main Loading Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Rocket with Orbits
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Orbit Rings
                        AnimatedBuilder(
                          animation: _orbitsAnimation,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _orbitsAnimation.value,
                              child: const CustomPaint(
                                size: Size(200, 200),
                                painter: OrbitPainter(),
                              ),
                            );
                          },
                        ),
                        
                        // Floating Rocket
                        AnimatedBuilder(
                          animation: _rocketAnimation,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(0, _rocketAnimation.value),
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: const BoxDecoration(
                                  gradient: SpaceTheme.starGradient,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.rocket_launch,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Loading Message
                  Text(
                    // FIX: This now works because the MaterialApp provides the S delegate.
                    widget.message ?? S.of(context)!.loadingAdventure,
                    style: SpaceTheme.titleStyle.copyWith(fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Progress Indicator
                  const SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      backgroundColor: SpaceTheme.deepSpace,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        SpaceTheme.starYellow,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Text(
                    // FIX: This also works now.
                    S.of(context)!.preparingMission,
                    style: SpaceTheme.bodyStyle.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Error Screen with Space Theme
class SpaceErrorScreen extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final IconData? errorIcon;
  
  const SpaceErrorScreen({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.onBack,
    this.errorIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: SpaceTheme.spaceGradient,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: SpaceTheme.cardDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Error Icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: SpaceTheme.rocketRed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Icon(
                      errorIcon ?? Icons.error_outline,
                      size: 60,
                      color: SpaceTheme.rocketRed,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Error Title
                  Text(
                    title,
                    style: SpaceTheme.headlineStyle.copyWith(fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Error Message
                  Text(
                    message,
                    style: SpaceTheme.bodyStyle.copyWith(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (onBack != null) ...[
                        ElevatedButton.icon(
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Go Back'),
                          style: SpaceTheme.secondaryButtonStyle,
                        ),
                        const SizedBox(width: 16),
                      ],
                      
                      if (onRetry != null)
                        ElevatedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                          style: SpaceTheme.primaryButtonStyle,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Custom Dialog for Space Theme
class SpaceDialog extends StatelessWidget {
  final String title;
  final String? content;
  final List<Widget>? actions;
  final Widget? customContent;
  
  const SpaceDialog({
    super.key,
    required this.title,
    this.content,
    this.actions,
    this.customContent,
   }) : assert(content != null || customContent != null, 'Either content or customContent must be provided.');

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        decoration: SpaceTheme.cardDecoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: SpaceTheme.headlineStyle.copyWith(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // This logic correctly handles showing customContent or default text content.
            if (customContent != null)
              customContent!
            else
              Text(
                content ?? '', // Use content, with a fallback for safety
                style: SpaceTheme.bodyStyle,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 24),
            if (actions != null && actions!.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: actions!,
              )
            else
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: SpaceTheme.primaryButtonStyle,
                child: const Text('OK'),
              ),
          ],
        ),
      ),
    );
  }
}

// Snackbar Utility
class SpaceSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    Color? backgroundColor,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? action,
    String? actionLabel,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor ?? SpaceTheme.nebulaPurple,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        action: action != null && actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: SpaceTheme.starYellow,
                onPressed: action,
              )
            : null,
      ),
    );
  }
  
  static void showSuccess(BuildContext context, String message) {
    show(
      context,
      message: message,
      backgroundColor: SpaceTheme.alienGreen,
      icon: Icons.check_circle,
    );
  }
  
  static void showError(BuildContext context, String message) {
    show(
      context,
      message: message,
      backgroundColor: SpaceTheme.rocketRed,
      icon: Icons.error,
    );
  }
  
  static void showWarning(BuildContext context, String message) {
    show(
      context,
      message: message,
      backgroundColor: SpaceTheme.warning,
      icon: Icons.warning,
    );
  }
  
  static void showInfo(BuildContext context, String message) {
    show(
      context,
      message: message,
      backgroundColor: SpaceTheme.info,
      icon: Icons.info,
    );
  }
}

// Navigation Utilities
class SpaceNavigation {
  static Future<T?> fadeTransition<T>(
    BuildContext context,
    Widget destination, {
    Duration duration = const Duration(milliseconds: 500),
  }) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: duration,
      ),
    );
  }
  
  static Future<T?> slideTransition<T>(
    BuildContext context,
    Widget destination, {
    Duration duration = const Duration(milliseconds: 500),
    Offset begin = const Offset(1.0, 0.0),
  }) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: begin,
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            )),
            child: child,
          );
        },
        transitionDuration: duration,
      ),
    );
  }
  
  static Future<T?> scaleTransition<T>(
    BuildContext context,
    Widget destination, {
    Duration duration = const Duration(milliseconds: 500),
  }) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return ScaleTransition(
            scale: Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.elasticOut,
            )),
            child: child,
          );
        },
        transitionDuration: duration,
      ),
    );
  }
}

// Input Validation Utilities
class InputValidator {
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }
  
  static String? validateNumber(String? value, {int? min, int? max}) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a number';
    }
    
    final number = int.tryParse(value);
    if (number == null) {
      return 'Please enter a valid number';
    }
    
    if (min != null && number < min) {
      return 'Number must be at least $min';
    }
    
    if (max != null && number > max) {
      return 'Number must be at most $max';
    }
    
    return null;
  }
}

// Custom Painters for Loading Screen
class LoadingStarsPainter extends CustomPainter {
  final double animation;
  
  LoadingStarsPainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SpaceTheme.starYellow.withValues(alpha: animation)
      ..style = PaintingStyle.fill;
    
    final random = math.Random(42);
    
    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final starSize = random.nextDouble() * 2 + 1;
      
      canvas.drawCircle(
        Offset(x, y),
        starSize * animation,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(LoadingStarsPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}

class OrbitPainter extends CustomPainter {
  // FIX: Add const to the constructor
  const OrbitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SpaceTheme.alienGreen.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    final center = Offset(size.width / 2, size.height / 2);
    
    // Draw multiple orbit rings
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, 30.0 * i, paint);
    }
  }

  @override
  bool shouldRepaint(OrbitPainter oldDelegate) => false;
}

// Performance Monitoring
class PerformanceTracker {
  static final Map<String, DateTime> _startTimes = {};
  static final Map<String, List<Duration>> _durations = {};
  
  static void startTracking(String operation) {
    _startTimes[operation] = DateTime.now();
  }
  
  static void endTracking(String operation) {
    final startTime = _startTimes[operation];
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);
      _durations[operation] = (_durations[operation] ?? [])..add(duration);
      _startTimes.remove(operation);
    }
  }
  
  static Duration? getAverageDuration(String operation) {
    final durations = _durations[operation];
    if (durations == null || durations.isEmpty) return null;
    
    final total = durations.fold(
      Duration.zero,
      (prev, duration) => prev + duration,
    );
    
    return Duration(microseconds: total.inMicroseconds ~/ durations.length);
  }
  
  static void logPerformance() {
    _durations.forEach((operation, durations) {
      final avg = getAverageDuration(operation);
      print('$operation: avg ${avg?.inMilliseconds}ms (${durations.length} samples)');
    });
  }
}