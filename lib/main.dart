// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui'; // Import for PlatformDispatcher

// --- CORE SERVICES ---
import 'core/services/audio_service.dart';
import 'core/services/debug_provider.dart';
import 'core/services/progress_service.dart';
import 'core/services/purchase_service.dart';
import 'core/services/puzzle_image_service.dart';

import 'core/services/sri_service.dart';
import 'core/services/cognitive_profile_service.dart';
import 'core/services/vocabulary_service.dart'; 
import 'core/models/skill_category.dart'; // Import for GradeLevel

import 'core/theme/space_theme.dart';

// --- PROVIDERS & MODELS ---
import 'features/games/providers/game_provider.dart';

// --- SCREENS ---
import 'features/home/screens/home_screen.dart';
import 'features/games/screens/game_menu_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/achievements/screens/achievements_screen.dart';

import 'features/games/screens/space_word_rescue_game.dart';
import 'features/games/screens/word_find_game.dart';
import 'features/games/screens/word_sort_game.dart';
import 'features/games/screens/word_snake_game.dart';

// --- UTILS & GENERATED ---
import 'shared/utils/app_utilities.dart';
import 'generated/l10n.dart';

// --- GLOBAL INSTANCES & NAVIGATOR KEY ---
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ProgressService progressService = ProgressService();
final CognitiveProfileService cognitiveProfileService = CognitiveProfileService();
final SriService sriService = SriService();
final VocabularyService vocabularyService = VocabularyService();
final PurchaseService purchaseService = PurchaseService();
final DebugProvider debugProvider = DebugProvider();
final AudioService audioService = AudioService();

final GameProvider gameProvider = GameProvider(
  progressService: progressService,
  sriService: sriService,
  cognitiveProfileService: cognitiveProfileService,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Service initialization that happens *before* app run
  await PuzzleImageService.instance.init();
  purchaseService.init(gameProvider);
  await debugProvider.init();
  GlobalErrorHandler.init(); 
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gameProvider),
        ChangeNotifierProvider.value(value: sriService),
        ChangeNotifierProvider.value(value: cognitiveProfileService),
        ChangeNotifierProvider.value(value: vocabularyService),
        ChangeNotifierProvider.value(value: purchaseService),
        ChangeNotifierProvider.value(value: debugProvider),
        Provider.value(value: progressService),
        Provider.value(value: audioService),
        // NOTE: PuzzleImageService is NOT provided because it's a singleton
        // accessed via .instance. If you wanted to provide it, you would add:
        // Provider.value(value: PuzzleImageService.instance),
        // But the current fix (removing the call) is cleaner.
      ],
      child: const SpaceMathApp(),
    ),
  );
}

class SpaceMathApp extends StatefulWidget {
  const SpaceMathApp({super.key});

  @override
  State<SpaceMathApp> createState() => _SpaceMathAppState();
}

class _SpaceMathAppState extends State<SpaceMathApp> with WidgetsBindingObserver {
  Locale? _locale;
  bool _isInitialized = false;
  String? _initializationError;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    purchaseService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _saveAppState();
    }
  }
  
  Future<void> _initializeApp() async {
    try {
      await _loadLanguagePreference();
      // Initialize vocab service first
      await vocabularyService.initialize();
      
      // Load other services
      await progressService.loadProgress(gameProvider);
      await sriService.loadSriData();
      await cognitiveProfileService.loadProfile();
      
      setState(() => _isInitialized = true);
    } catch (e, s) {
      debugPrint('Initialization Error: $e\n$s');
      setState(() {
        _initializationError = e.toString();
        _isInitialized = true; // Set to true to show the error screen
      });
    }
  }
  
  Future<void> _loadLanguagePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('language');
      
      if (languageCode != null && S.supportedLocales.any((locale) => locale.languageCode == languageCode)) {
        setState(() => _locale = Locale(languageCode));
      } else {
        final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
        if (S.supportedLocales.any((l) => l.languageCode == systemLocale.languageCode)) {
           setState(() => _locale = systemLocale);
        } else {
           setState(() => _locale = const Locale('en')); // Default fallback
        }
      }
    } catch (e) {
      // Fallback in case of any error
      setState(() => _locale = const Locale('en'));
    }
  }
  
  Future<void> _saveAppState() async {
    // Save all services on pause
    await progressService.saveProgress(gameProvider);
    await sriService.saveSriData();
    await cognitiveProfileService.saveProfile();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_locale != null) {
        await prefs.setString('language', _locale!.languageCode);
      }
    } catch (e) {
      debugPrint('Error saving language state: $e');
    }
  }
  
  Future<void> _restoreAppState() async {
    // Restore logic if needed
  }

  @override
  Widget build(BuildContext context) {
    // Show splash/loading screen
    if (!_isInitialized) {
      return MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        // Use a non-localized string here as S.of(context) is not available
        home: const SpaceLoadingScreen(message: 'Initializing...'),
        theme: SpaceTheme.lightTheme,
      );
    }
    
    // Show error screen if initialization failed
    if (_initializationError != null) {
      return MaterialApp(
        home: SpaceErrorScreen(
          title: 'Initialization Error',
          message: 'Failed to start the app: $_initializationError',
          onRetry: () {
            setState(() {
              _isInitialized = false;
              _initializationError = null;
            });
            _initializeApp();
          },
        ),
        theme: SpaceTheme.lightTheme,
      );
    }

    // App is ready, launch!
    return MaterialApp(
      title: 'Word Universe',
      navigatorKey: navigatorKey, 
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: SpaceTheme.lightTheme,
      darkTheme: SpaceTheme.darkTheme,
      themeMode: ThemeMode.light, // Force light theme
      initialRoute: AppRoutes.splash, // Start at splash
      onGenerateRoute: AppRoutes.generateRoute,
      builder: (context, child) {
        // Global error widget builder
        ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
          // Log the full error
          debugPrint("Caught Flutter Error: ${errorDetails.exception}");
          debugPrintStack(stackTrace: errorDetails.stack);
          return SpaceErrorScreen(
            title: 'Oops! Something went wrong',
            message: 'Our space engineers are working on it!\n${errorDetails.exception}',
            onRetry: () {
              final currentContext = navigatorKey.currentContext;
              if (currentContext != null) {
                // Try to reload the current route
                Navigator.of(currentContext).pushReplacementNamed(
                  ModalRoute.of(currentContext)?.settings.name ?? AppRoutes.home,
                );
              }
            },
          );
        };
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

class AppRoutes {
  // Route names
  static const String splash = '/';
  static const String home = '/home';
  static const String gameMenu = '/games';
  
  static const String spaceWordRescue = '/games/space-word-rescue';
  static const String wordFind = '/games/word-find';
  static const String wordSort = '/games/word-sort';
  static const String wordSnake = '/games/word-snake'; 

  static const String settings = '/settings';
  static const String achievements = '/achievements';
  static const String loading = '/loading';
  static const String error = '/error';
  
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final args = settings.arguments as Map<String, dynamic>?;
    
    switch (settings.name) {
        case splash:
          return _createRoute(const SplashScreen()); 
          
        case home:
          return _createRoute(const HomeScreen());
          
        case gameMenu:
          return _createRoute(const GameMenuScreen());

        case spaceWordRescue:
          final grade = args?['grade'] as int? ?? 1;
          
          GradeLevel gradeLevel;
          switch (grade) {
            case 1: gradeLevel = GradeLevel.grade1; break;
            case 2: gradeLevel = GradeLevel.grade2; break;
            case 3: gradeLevel = GradeLevel.grade3; break;
            case 4: gradeLevel = GradeLevel.grade4; break;
            case 5: gradeLevel = GradeLevel.grade5; break;
            case 6: gradeLevel = GradeLevel.grade6; break;
            default: gradeLevel = GradeLevel.grade1;
          }
          return _createRoute(SpaceWordRescueGame(gradeLevel: gradeLevel));

        case wordFind:
          final grade = args?['grade'] as int? ?? 1;
          GradeLevel gradeLevel;
          switch (grade) {
            case 1: gradeLevel = GradeLevel.grade1; break;
            case 2: gradeLevel = GradeLevel.grade2; break;
            case 3: gradeLevel = GradeLevel.grade3; break;
            case 4: gradeLevel = GradeLevel.grade4; break;
            case 5: gradeLevel = GradeLevel.grade5; break;
            case 6: gradeLevel = GradeLevel.grade6; break;
            default: gradeLevel = GradeLevel.grade1;
          }
          return _createRoute(WordFindGame(gradeLevel: gradeLevel));

        case wordSort:
          final grade = args?['grade'] as int? ?? 1;
          GradeLevel gradeLevel;
          switch (grade) {
            case 1: gradeLevel = GradeLevel.grade1; break;
            case 2: gradeLevel = GradeLevel.grade2; break;
            case 3: gradeLevel = GradeLevel.grade3; break;
            case 4: gradeLevel = GradeLevel.grade4; break;
            case 5: gradeLevel = GradeLevel.grade5; break;
            case 6: gradeLevel = GradeLevel.grade6; break;
            default: gradeLevel = GradeLevel.grade1;
          }
          return _createRoute(WordSortGame(gradeLevel: gradeLevel));

        case wordSnake:
          final grade = args?['grade'] as int? ?? 1;
          GradeLevel gradeLevel;
          switch (grade) {
            case 1: gradeLevel = GradeLevel.grade1; break;
            case 2: gradeLevel = GradeLevel.grade2; break;
            case 3: gradeLevel = GradeLevel.grade3; break;
            case 4: gradeLevel = GradeLevel.grade4; break;
            case 5: gradeLevel = GradeLevel.grade5; break;
            case 6: gradeLevel = GradeLevel.grade6; break;
            default: gradeLevel = GradeLevel.grade1;
          }
          return _createRoute(WordSnakeGame(gradeLevel: gradeLevel));
          
          
        case AppRoutes.settings:
          return _createRoute(const SettingsScreen());
        
        case AppRoutes.achievements:
        return _createRoute(const AchievementsScreen());
        
        case loading:
          final message = args?['message'] as String?;
          return _createRoute(SpaceLoadingScreen(message: message));
          
        case error:
          final title = args?['title'] as String? ?? 'Error';
          final message = args?['message'] as String? ?? 'Something went wrong';
          return _createRoute(SpaceErrorScreen(title: title, message: message));
          
        default:
          return _createRoute(
              SpaceErrorScreen(
                title: 'Route Not Found',
                message: 'The requested page could not be found.',
                onBack: () {
                  if(navigatorKey.currentState?.canPop() ?? false) {
                    navigatorKey.currentState?.pop();
                  } else {
                    navigatorKey.currentState?.pushReplacementNamed(AppRoutes.home);
                  }
                },
              ),
          );
    }
    }
  
  static PageRoute _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

// Enhanced Splash Screen with Better Initialization
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _progressController;

  late Animation<double> _logoScale;
  late Animation<double> _textOpacity;
  late Animation<double> _progressAnimation;

  String _loadingMessage = 'Initializing...'; // Non-localized default
  double _progress = 0.0;
  
  @override
  void initState() {
    super.initState();
    
    _logoController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this);
    _textController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _progressController = AnimationController(duration: const Duration(milliseconds: 3000), vsync: this);

    _logoScale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _textController, curve: Curves.easeIn));
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _progressController, curve: Curves.easeInOut));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeApp(S.of(context)!);
      }
    });
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }
  
  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _progressController.dispose();
    super.dispose();
  }
  
  Future<void> _initializeApp(S s) async {
    _logoController.forward();

    // Use the S instance to get localized strings
    await _updateProgress(0.2, s.loadingAssets);
    // FIX: This line was the error. It's removed.
    // PuzzleImageService was already initialized in main().
    // if (mounted) await context.read<PuzzleImageService>().init(); 
    await Future.delayed(const Duration(milliseconds: 500)); // Keep a small delay for visual pacing

    await _updateProgress(0.4, s.loadingProgress);
    if (mounted) await context.read<ProgressService>().loadProgress(context.read<GameProvider>());
    
    _textController.forward();
    await _updateProgress(0.6, s.preparingSpaceStation);
    if (mounted) await context.read<SriService>().loadSriData();
    
    await _updateProgress(0.8, s.calibratingNav);
    if (mounted) await context.read<CognitiveProfileService>().loadProfile();
    
    await _updateProgress(1.0, s.readyForLaunch);
    await Future.delayed(const Duration(milliseconds: 800)); // Short pause on "Ready"

    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    }
  }

  Future<void> _updateProgress(double progress, String message) async {
    if (mounted) {
      setState(() {
        _progress = progress;
        _loadingMessage = message;
      });
      _progressController.animateTo(progress);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.shortestSide < 600; 
    
    return Scaffold(
      body: Container(
        width: double.infinity, 
        height: double.infinity,
        decoration: const BoxDecoration(gradient: SpaceTheme.spaceGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: screenSize.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _logoScale,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _logoScale.value,
                          child: Container(
                            width: isSmallScreen ? 100 : 150,
                            height: isSmallScreen ? 100 : 150,
                            decoration: BoxDecoration(
                              gradient: SpaceTheme.starGradient,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: SpaceTheme.starYellow.withOpacity(0.5),
                                  blurRadius: isSmallScreen ? 20 : 30,
                                  spreadRadius: isSmallScreen ? 5 : 10,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.rocket_launch, 
                              color: Colors.white, 
                              size: isSmallScreen ? 50 : 80
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: isSmallScreen ? 20 : 40),
                    AnimatedBuilder(
                      animation: _textOpacity,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _textOpacity.value,
                          child: Column(
                            children: [
                              Text(
                                S.of(context)!.appTitle,
                                style: SpaceTheme.headlineStyle.copyWith(
                                  fontSize: isSmallScreen ? 24 : 36
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: isSmallScreen ? 8 : 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  S.of(context)!.splashScreenSubtitle,
                                  style: SpaceTheme.bodyStyle.copyWith(
                                    fontSize: isSmallScreen ? 14 : 18,
                                    color: SpaceTheme.starYellow,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    SizedBox(height: isSmallScreen ? 30 : 60),
                    AnimatedBuilder(
                      animation: _textOpacity,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _textOpacity.value,
                          child: Column(
                            children: [
                              SizedBox(
                                width: isSmallScreen ? 200 : 250,
                                child: AnimatedBuilder(
                                  animation: _progressAnimation,
                                  builder: (context, child) {
                                    return LinearProgressIndicator(
                                      value: _progressAnimation.value,
                                      backgroundColor: SpaceTheme.deepSpace,
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                        SpaceTheme.starYellow,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              SizedBox(height: isSmallScreen ? 12 : 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  _loadingMessage,
                                  style: SpaceTheme.bodyStyle.copyWith(
                                    fontSize: isSmallScreen ? 12 : 14
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              SizedBox(height: isSmallScreen ? 4 : 8),
                              Text(
                                '${(_progress * 100).toInt()}%',
                                style: SpaceTheme.bodyStyle.copyWith(
                                  fontSize: isSmallScreen ? 10 : 12,
                                  color: SpaceTheme.starYellow,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    SizedBox(height: isSmallScreen ? 20 : 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Global Error Handler
class GlobalErrorHandler {
  static void handleError(dynamic error, StackTrace stackTrace) {
    debugPrint('Global Error: $error');
    debugPrint('Stack Trace: $stackTrace');
  }
  
  static void init() {
    FlutterError.onError = (FlutterErrorDetails details) {
      handleError(details.exception, details.stack ?? StackTrace.empty);
    };
    
    PlatformDispatcher.instance.onError = (error, stack) {
      handleError(error, stack);
      return true; // Mark as handled
    };
  }
}