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
// --- FIX: Add import for models ---
import 'core/models/vocabulary_models.dart';

// --- SCREENS ---
import 'features/home/screens/home_screen.dart';
import 'features/games/screens/game_menu_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/achievements/screens/achievements_screen.dart';

import 'features/games/screens/space_word_rescue_game.dart';
import 'features/games/screens/word_find_game.dart';
import 'features/games/screens/word_sort_game.dart';
import 'features/games/screens/word_snake_game.dart';
import 'features/games/screens/word_memory_game.dart';
import 'features/games/screens/word_builder_game.dart';
import 'features/games/screens/word_type_whirl_game.dart';

// --- UTILS & GENERATED ---
import 'shared/utils/app_utilities.dart';
import 'generated/l10n.dart';

// --- GLOBAL INSTANCES & NAVIGATOR KEY ---
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// --- FIX: These services are provided, so they can be final ---
final ProgressService progressService = ProgressService();
final CognitiveProfileService cognitiveProfileService = CognitiveProfileService();
final SriService sriService = SriService();
final VocabularyService vocabularyService = VocabularyService();
final PurchaseService purchaseService = PurchaseService();
final DebugProvider debugProvider = DebugProvider();
final AudioService audioService = AudioService();

// --- FIX: REMOVED the global instance that was causing the crash ---
/*
final GameProvider gameProvider = GameProvider(
  progressService: progressService,
  sriService: sriService,
  cognitiveProfileService: cognitiveProfileService,
);
*/

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // --- FIX: Load SharedPreferences BEFORE starting the app ---
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  // --- END FIX ---

  // Service initialization that happens *before* app run
  await PuzzleImageService.instance.init();
  // We can't init purchaseService yet because it needs GameProvider
  await debugProvider.init();
  GlobalErrorHandler.init(); 
  
  runApp(
    MultiProvider(
      providers: [
        // --- FIX: Create GameProvider HERE, passing in prefs ---
        ChangeNotifierProvider(
          create: (_) => GameProvider(
            progressService: progressService,
            sriService: sriService,
            cognitiveProfileService: cognitiveProfileService,
            prefs: prefs, // <-- Pass the loaded prefs
          ),
        ),
        // --- END FIX ---
        ChangeNotifierProvider.value(value: sriService),
        ChangeNotifierProvider.value(value: cognitiveProfileService),
        ChangeNotifierProvider.value(value: vocabularyService),
        ChangeNotifierProvider.value(value: purchaseService),
        ChangeNotifierProvider.value(value: debugProvider),
        Provider.value(value: progressService),
        Provider.value(value: audioService),
      ],
      // --- FIX: Pass prefs to the app ---
      child: MyApp(prefs: prefs),
    ),
  );
}

class MyApp extends StatefulWidget {
  // --- FIX: Accept prefs ---
  final SharedPreferences prefs;
  const MyApp({super.key, required this.prefs});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Locale? _locale;
  bool _isInitialized = false;
  String? _initializationError;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // --- FIX: Init PurchaseService *after* GameProvider is created ---
    // We can access it via context now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gameProvider = context.read<GameProvider>();
      context.read<PurchaseService>().init(gameProvider);
      _initializeApp(gameProvider);
    });
    // --- END FIX ---
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
  
  // --- FIX: Pass GameProvider to init functions ---
  Future<void> _initializeApp(GameProvider gameProvider) async {
    try {
      // Use the prefs instance we already loaded
      await _loadLanguagePreference(widget.prefs); 
      
      // Initialize vocab service first
      await vocabularyService.initialize();
      
      // Load other services
      // --- FIX: Pass GameProvider to loadProgress ---
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
  
  Future<void> _loadLanguagePreference(SharedPreferences prefs) async {
    try {
      // Use the passed-in prefs
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
    // --- FIX: Get GameProvider from context ---
    if (mounted) {
      final gameProvider = context.read<GameProvider>();
      // The GameProvider's _saveProgress now handles saving all its state to prefs
      await gameProvider.recordLevelWin(gameType: 'app_close', scoreGained: 0, difficulty: 0, wasSuccessful: false); // This triggers a save
    }
    await sriService.saveSriData();
    await cognitiveProfileService.saveProfile();
    try {
      // Use the passed-in prefs
      if (_locale != null) {
        await widget.prefs.setString('language', _locale!.languageCode);
      }
    } catch (e) {
      debugPrint('Error saving language state: $e');
    }
  }
  // --- END FIX ---
  
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
            // --- FIX: Get GameProvider from context ---
            _initializeApp(context.read<GameProvider>());
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
  static const String wordMemory = '/word-memory';
  static const String wordBuilder = '/word-builder';
  static const String wordWhirl = '/word-whirl';

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
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1]; // Safer way
          return _createRoute(SpaceWordRescueGame(gradeLevel: gradeLevel));

        case wordFind:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(WordFindGame(gradeLevel: gradeLevel));

        case wordSort:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(WordSortGame(gradeLevel: gradeLevel));

        case wordSnake:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(WordSnakeGame(gradeLevel: gradeLevel));

        case wordMemory:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(WordMemoryGame(gradeLevel: gradeLevel));

        case wordBuilder:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(WordBuilderGame(gradeLevel: gradeLevel));

        case wordWhirl:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(WordTypeWhirlGame(gradeLevel: gradeLevel));

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
        // --- FIX: Pass GameProvider to _initializeApp ---
        _initializeApp(S.of(context)!, context.read<GameProvider>());
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
  
  // --- FIX: Accept GameProvider ---
  Future<void> _initializeApp(S s, GameProvider gameProvider) async {
    _logoController.forward();

    // Use the S instance to get localized strings
    await _updateProgress(0.2, s.loadingAssets);
    // PuzzleImageService is already initialized in main()
    await Future.delayed(const Duration(milliseconds: 500)); 

    await _updateProgress(0.4, s.loadingProgress);
    // --- FIX: Pass GameProvider ---
    if (mounted) await context.read<ProgressService>().loadProgress(gameProvider);
    
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
    // ... (rest of SplashScreen build method is unchanged) ...
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