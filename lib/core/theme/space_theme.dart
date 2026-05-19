import 'package:flutter/material.dart';

class SpaceTheme {
  // Space color palette
  static const Color spaceBlue = Color(0xFF0B1426);
  static const Color deepSpace = Color(0xFF1A1A2E);
  static const Color nebulaPurple = Color(0xFF16213E);
  static const Color starYellow = Color(0xFFFFD700);
  static const Color planetOrange = Color(0xFFFF6B35);
  static const Color rocketRed = Color(0xFFE63946);
  static const Color alienGreen = Color(0xFF06FFA5);
  static const Color moonSilver = Color(0xFFC0C0C0);
  static const Color cosmicPink = Color(0xFFFF69B4);
  
  // Gradients
  static const LinearGradient spaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [spaceBlue, deepSpace, nebulaPurple],
  );
  
  static const LinearGradient starGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [starYellow, planetOrange],
  );
  
  static const RadialGradient planetGradient = RadialGradient(
    colors: [planetOrange, rocketRed],
  );
  
  // Text styles
  static const TextStyle headlineStyle = TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: Colors.white,
    shadows: [
      Shadow(
        offset: Offset(2, 2),
        blurRadius: 4,
        color: Colors.black54,
      ),
    ],
  );
  
  static const TextStyle titleStyle = TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
  
  static const TextStyle bodyStyle = TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 16,
    color: Colors.white70,
  );
  
  static const TextStyle buttonStyle = TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  
  // Button themes
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: planetOrange,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    ),
    elevation: 8,
    shadowColor: Colors.black54,
  );
  
  static ButtonStyle secondaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: alienGreen,
    foregroundColor: spaceBlue,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(25),
    ),
    elevation: 6,
  );
  
  // Card theme
  static const BoxDecoration cardDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF2A2D3E),
        Color(0xFF1E2235),
      ],
    ),
    borderRadius: BorderRadius.all(Radius.circular(20)),
    boxShadow: [
      BoxShadow(
        color: Colors.black26,
        blurRadius: 10,
        offset: Offset(0, 4),
      ),
    ],
  );
  
  // Game UI colors
  static const Color correctAnswer = alienGreen;
  static const Color wrongAnswer = rocketRed;
  static const Color warning = starYellow;
  static const Color info = cosmicPink;
  
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: spaceBlue,
        brightness: Brightness.light,
      ),
      fontFamily: 'SpaceGrotesk',
      
      // App Bar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: titleStyle,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      
      // Elevated Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: primaryButtonStyle,
      ),
      
      // Text Button Theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: starYellow,
          textStyle: const TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      
      // Card Theme - Fixed
      cardTheme: const CardThemeData(
        elevation: 8,
        margin: EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      
      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white54),
      ),
    );
  }
  
  static ThemeData get darkTheme {
    return lightTheme.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: spaceBlue,
        brightness: Brightness.dark,
      ),
    );
  }
  
  // Animation durations
  static const Duration fastAnimation = Duration(milliseconds: 200);
  static const Duration normalAnimation = Duration(milliseconds: 400);
  static const Duration slowAnimation = Duration(milliseconds: 800);
  
  // Screen breakpoints for iPad optimization
  static const double tabletBreakpoint = 768;
  static const double ipadBreakpoint = 1024;
  
  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }
  
  static bool isIPad(BuildContext context) {
    return MediaQuery.of(context).size.width >= ipadBreakpoint;
  }
}