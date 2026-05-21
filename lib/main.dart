// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- CORE SERVICES ---
import 'core/services/audio_service.dart';
import 'core/services/crash_logger.dart';
import 'core/services/debug_provider.dart';
import 'core/services/streak_service.dart';
import 'core/services/progress_service.dart';
import 'core/services/purchase_service.dart';

import 'core/services/sri_service.dart';
import 'core/services/cognitive_profile_service.dart';
import 'core/services/vocabulary_service.dart'; 
import 'core/models/skill_category.dart'; // Import for GradeLevel

import 'core/theme/space_theme.dart';

// --- PROVIDERS & MODELS ---
import 'features/games/providers/game_provider.dart';
// --- FIX: Add import for models ---

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
import 'features/games/screens/wortbaumeister_game.dart';
import 'features/games/screens/grossstadt_game.dart';
import 'features/games/screens/grossschreib_game.dart';
import 'features/games/screens/verbtrenner_game.dart';

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
final StreakService streakService = StreakService();

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

  // Install crash logger before anything else so we catch init failures.
  await CrashLogger.instance.init();

  // Service initialization that happens *before* app run.
  // We can't init purchaseService yet because it needs GameProvider
  await debugProvider.init();
  await streakService.load();
  await streakService.markPlayed();
  
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
        ChangeNotifierProvider.value(value: streakService),
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
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize PurchaseService and load language preference ONLY
    // All other initialization happens in SplashScreen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final gameProvider = context.read<GameProvider>();
        context.read<PurchaseService>().init(gameProvider);
        _loadLanguagePreference(widget.prefs);
      }
    });
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
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.detached) {
      _saveAppState();
    }
  }
  
  /// Load language preference from SharedPreferences
  Future<void> _loadLanguagePreference(SharedPreferences prefs) async {
    try {
      final languageCode = prefs.getString('language');
      
      if (languageCode != null && 
          S.supportedLocales.any((locale) => locale.languageCode == languageCode)) {
        if (mounted) {
          setState(() => _locale = Locale(languageCode));
        }
      } else {
        // Use system locale or default to English
        final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
        if (S.supportedLocales.any((l) => l.languageCode == systemLocale.languageCode)) {
          if (mounted) {
            setState(() => _locale = systemLocale);
          }
        } else {
          if (mounted) {
            setState(() => _locale = const Locale('en'));
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading language preference: $e');
      // Fallback to English
      if (mounted) {
        setState(() => _locale = const Locale('en'));
      }
    }
  }
  
  /// Save app state when pausing/closing
  Future<void> _saveAppState() async {
    if (!mounted) return;
    
    try {
      final gameProvider = context.read<GameProvider>();

      // Flush all GameProvider state to SharedPreferences.
      await gameProvider.saveProgress();

      // Save other services
      await sriService.saveSriData();
      await cognitiveProfileService.saveProfile();
      
      // Save language preference
      if (_locale != null) {
        await widget.prefs.setString('language', _locale!.languageCode);
      }
      
      debugPrint('[APP] State saved successfully');
    } catch (e) {
      debugPrint('[APP] Error saving app state: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // No loading screen, no initialization checks - just launch the app!
    // SplashScreen will handle all initialization
    return MaterialApp(
      title: 'Word Universe',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: SpaceTheme.lightTheme,
      darkTheme: SpaceTheme.darkTheme,
      themeMode: ThemeMode.light,
      initialRoute: AppRoutes.splash, // Start at splash - it handles everything
      onGenerateRoute: AppRoutes.generateRoute,
      builder: (context, child) {
        // Global error widget builder
        ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
          debugPrint("[APP] Caught Flutter Error: ${errorDetails.exception}");
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
  static const String wordMemory = '/games/word-memory';
  static const String wordBuilder = '/games/word-builder';
  static const String wordWhirl = '/games/word-whirl';
  static const String wortbaumeister = '/games/wortbaumeister';
  static const String grossstadt = '/games/grossstadt';
  static const String grossschreib = '/games/grossschreib';
  static const String verbtrenner = '/games/verbtrenner';

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

        case wortbaumeister:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(WortbaumeisterGame(gradeLevel: gradeLevel));

        case grossstadt:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(GrossstadtGame(gradeLevel: gradeLevel));

        case grossschreib:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(GrossschreibungsGalaxieGame(gradeLevel: gradeLevel));

        case verbtrenner:
          final grade = args?['grade'] as int? ?? 1;
          final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
          return _createRoute(VerbtrennerGame(gradeLevel: gradeLevel));

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

  String _loadingMessage = 'Initializing...';
  String _detailMessage = ''; // NEW: More detailed sub-message
  double _progress = 0.0;
  
  @override
  void initState() {
    super.initState();
    
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 2000), 
      vsync: this
    );
    _textController = AnimationController(
      duration: const Duration(milliseconds: 1000), 
      vsync: this
    );
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300), // Faster updates
      vsync: this
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _textController, curve: Curves.easeIn));
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _progressController, curve: Curves.easeOut));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeApp(S.of(context)!, context.read<GameProvider>());
      }
    });
  }
  
  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _progressController.dispose();
    super.dispose();
  }
  
  Future<void> _initializeApp(S s, GameProvider gameProvider) async {
    try {
      _logoController.forward();

      // PHASE 1: Vocabulary Service (0.0 - 0.6) - THIS IS THE LONG PART
      await _updateProgress(0.0, s.preparingSpaceStation, s.preparingMission);
      
      if (mounted) {
        await context.read<VocabularyService>().initialize(
          onProgress: (vocabProgress, vocabMessage) {
            // Map vocabulary progress (0.0-1.0) to overall progress (0.0-0.6)
            final overallProgress = vocabProgress * 0.6;
            _updateProgress(
              overallProgress,
              s.preparingSpaceStation,
              vocabMessage,
            );
          },
        );
      }

      // PHASE 2: Progress Service (0.6 - 0.7)
      _textController.forward();
      await _updateProgress(0.65, s.loadingProgress, 'Loading your progress...');
      if (mounted) {
        await context.read<ProgressService>().loadProgress(gameProvider);
      }
      
      // PHASE 3: SRI Data (0.7 - 0.85)
      await _updateProgress(0.75, s.calibratingNav, 'Loading learning data...');
      if (mounted) {
        await context.read<SriService>().loadSriData();
      }
      
      // PHASE 4: Cognitive Profile (0.85 - 0.95)
      await _updateProgress(0.9, s.calibratingNav, 'Loading your profile...');
      if (mounted) {
        await context.read<CognitiveProfileService>().loadProfile();
      }
      
      // PHASE 5: Complete (0.95 - 1.0)
      await _updateProgress(1.0, s.readyForLaunch, '');
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
      
    } catch (e, stackTrace) {
      debugPrint('[SPLASH] ❌ Initialization error: $e');
      debugPrint('[SPLASH] Stack trace: $stackTrace');
      
      if (mounted) {
        // Show error dialog with retry option
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: SpaceTheme.deepSpace,
            title: Row(
              children: [
                Icon(Icons.error_outline, color: SpaceTheme.planetOrange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Initialization Failed',
                    style: SpaceTheme.headlineStyle.copyWith(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Failed to initialize the app:',
                    style: SpaceTheme.bodyStyle,
                  ),
                  SizedBox(height: 8),
                  Text(
                    e.toString(),
                    style: SpaceTheme.bodyStyle.copyWith(
                      color: SpaceTheme.starYellow.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Retry initialization
                  if (mounted) {
                    setState(() {
                      _progress = 0.0;
                      _loadingMessage = 'Initializing...';
                      _detailMessage = '';
                    });
                    _initializeApp(s, gameProvider);
                  }
                },
                child: Text(
                  'Retry',
                  style: SpaceTheme.buttonStyle.copyWith(
                    color: SpaceTheme.starYellow,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _updateProgress(double progress, String message, [String detail = '']) async {
    if (mounted) {
      setState(() {
        _progress = progress;
        _loadingMessage = message;
        _detailMessage = detail;
      });
      await _progressController.animateTo(progress);
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
                    // Logo
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
                                  color: SpaceTheme.starYellow.withValues(alpha: 0.5),
                                  blurRadius: isSmallScreen ? 20 : 30,
                                  spreadRadius: isSmallScreen ? 5 : 10,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.auto_stories,
                              color: Colors.white,
                              size: isSmallScreen ? 50 : 80
                            ),
                          ),
                        );
                      },
                    ),
                    
                    SizedBox(height: isSmallScreen ? 20 : 40),
                    
                    // Title
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
                    
                    // Progress Section
                    AnimatedBuilder(
                      animation: _textOpacity,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _textOpacity.value,
                          child: Column(
                            children: [
                              // Progress Bar
                              SizedBox(
                                width: isSmallScreen ? 250 : 300,
                                child: AnimatedBuilder(
                                  animation: _progressAnimation,
                                  builder: (context, child) {
                                    return LinearProgressIndicator(
                                      value: _progressAnimation.value,
                                      backgroundColor: SpaceTheme.deepSpace,
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                        SpaceTheme.starYellow,
                                      ),
                                      minHeight: 8,
                                    );
                                  },
                                ),
                              ),
                              
                              SizedBox(height: isSmallScreen ? 16 : 20),
                              
                              // Main Loading Message
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  _loadingMessage,
                                  style: SpaceTheme.bodyStyle.copyWith(
                                    fontSize: isSmallScreen ? 14 : 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              
                              // NEW: Detail Message (shows the granular progress)
                              if (_detailMessage.isNotEmpty) ...[
                                SizedBox(height: isSmallScreen ? 8 : 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: Text(
                                    _detailMessage,
                                    style: SpaceTheme.bodyStyle.copyWith(
                                      fontSize: isSmallScreen ? 11 : 13,
                                      color: SpaceTheme.starYellow.withValues(alpha: 0.8),
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              
                              SizedBox(height: isSmallScreen ? 8 : 12),
                              
                              // Percentage
                              Text(
                                '${(_progress * 100).toInt()}%',
                                style: SpaceTheme.bodyStyle.copyWith(
                                  fontSize: isSmallScreen ? 12 : 14,
                                  color: SpaceTheme.starYellow,
                                  fontWeight: FontWeight.bold,
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

