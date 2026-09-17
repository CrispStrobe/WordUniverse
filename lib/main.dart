// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- CORE SERVICES ---
import 'core/services/audio_service.dart';
import 'core/services/crash_logger.dart';
import 'core/services/debug_provider.dart';
import 'core/services/streak_service.dart';
import 'core/services/learner_profile_service.dart';
import 'core/services/progress_service.dart';
import 'core/services/purchase_service.dart';

import 'core/services/sri_service.dart';
import 'core/services/cognitive_profile_service.dart';
import 'core/services/vocabulary_service.dart'; 
import 'core/services/language_pack_service.dart';
import 'core/models/language_pack.dart';
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
import 'features/onboarding/screens/learner_onboarding_screen.dart';
import 'features/onboarding/screens/language_setup_screen.dart';
import 'features/home/screens/daily_session_screen.dart';

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
import 'shared/widgets/language_pack_dialog.dart';
import 'generated/l10n.dart';
import 'core/models/load_status.dart';
import 'shared/utils/load_status_localization.dart';

// --- GLOBAL INSTANCES & NAVIGATOR KEY ---
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// --- FIX: These services are provided, so they can be final ---
final ProgressService progressService = ProgressService();
final CognitiveProfileService cognitiveProfileService =
    CognitiveProfileService();
final SriService sriService = SriService();
final VocabularyService vocabularyService = VocabularyService();
/// Owns language-pack install state (download / progress / removal) on top of
/// [vocabularyService]. See core/services/language_pack_service.dart.
final LanguagePackService languagePackService =
    LanguagePackService(vocabularyService);
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
        ChangeNotifierProvider.value(value: languagePackService),
        ChangeNotifierProvider.value(value: purchaseService),
        ChangeNotifierProvider.value(value: debugProvider),
        ChangeNotifierProvider.value(value: streakService),
        ChangeNotifierProvider(
          create: (_) => LearnerProfileService(prefs),
        ),
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

  static void setLocale(BuildContext context, Locale locale) {
    final state = context.findAncestorStateOfType<_MyAppState>();
    state?.updateLocale(locale);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Locale? _locale;

  /// Immediate interface-language switch without an app restart.
  void updateLocale(Locale locale) {
    if (mounted) setState(() => _locale = locale);
  }

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
          S.supportedLocales
              .any((locale) => locale.languageCode == languageCode)) {
        if (mounted) {
          setState(() => _locale = Locale(languageCode));
        }
      } else {
        // Use system locale or default to English
        final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
        if (S.supportedLocales
            .any((l) => l.languageCode == systemLocale.languageCode)) {
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
      if (kDebugMode) debugPrint('Error loading language preference: $e');
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

      if (kDebugMode) debugPrint('[APP] State saved successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('[APP] Error saving app state: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // No loading screen, no initialization checks - just launch the app!
    // SplashScreen will handle all initialization
    final screenshotRoute = kDebugMode
        ? widget.prefs.getString('app_store_screenshot_route')
        : null;
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
      // Do not let Navigator synthesize '/' below setup: that would initialize
      // vocabulary and prompt for downloads behind the very first picker.
      onGenerateInitialRoutes: (name) => [
        if (name == AppRoutes.languageSetup)
          MaterialPageRoute(builder: (context) => LanguageSetupScreen(
            prefs: widget.prefs,
            onLocaleChanged: (locale) => setState(() => _locale = locale),
            onComplete: () => Navigator.of(context).pushReplacementNamed(
              widget.prefs.getBool('learner_onboarding_complete') == true
                ? AppRoutes.splash : AppRoutes.onboarding),
          ))
        else
          AppRoutes.generateRoute(RouteSettings(name: name)),
      ],
      initialRoute: switch (screenshotRoute) {
        'home' => AppRoutes.home,
        'games' => AppRoutes.gameMenu,
        'daily' => AppRoutes.daily,
        _ => !LanguageSetupScreen.isComplete(widget.prefs)
            ? AppRoutes.languageSetup
            : widget.prefs.getBool('learner_onboarding_complete') == true
            ? AppRoutes.splash
            : AppRoutes.onboarding,
      },
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.languageSetup) {
          return MaterialPageRoute(builder: (context) => LanguageSetupScreen(
            prefs: widget.prefs,
            onLocaleChanged: (locale) => setState(() => _locale = locale),
            onComplete: () => Navigator.of(context).pushReplacementNamed(
              widget.prefs.getBool('learner_onboarding_complete') == true
                ? AppRoutes.splash : AppRoutes.onboarding),
          ));
        }
        return AppRoutes.generateRoute(settings);
      },
      builder: (context, child) {
        // Global error widget builder
        ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
          if (kDebugMode)
            debugPrint("[APP] Caught Flutter Error: ${errorDetails.exception}");
          debugPrintStack(stackTrace: errorDetails.stack);

          final s = S.of(context)!;
          return SpaceErrorScreen(
            title: s.unexpectedErrorTitle,
            message: s.unexpectedErrorMessage,
            onRetry: () {
              final currentContext = navigatorKey.currentContext;
              if (currentContext != null) {
                Navigator.of(currentContext).pushReplacementNamed(
                  ModalRoute.of(currentContext)?.settings.name ??
                      AppRoutes.home,
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
  static const String onboarding = '/onboarding';
  static const String languageSetup = '/language-setup';
  static const String home = '/home';
  static const String gameMenu = '/games';
  static const String daily = '/daily';

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
      case onboarding:
        return _createRoute(const LearnerOnboardingScreen());

      case splash:
        return _createRoute(const SplashScreen());

      case home:
        return _createRoute(const HomeScreen());

      case gameMenu:
        return _createRoute(const GameMenuScreen());

      case daily:
        return _createRoute(const DailySessionScreen());

      case spaceWordRescue:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel =
            GradeLevel.values[grade.clamp(1, 6) - 1]; // Safer way
        return _createGameRoute((_) => SpaceWordRescueGame(gradeLevel: gradeLevel));

      case wordFind:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) => WordFindGame(gradeLevel: gradeLevel));

      case wordSort:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) => WordSortGame(gradeLevel: gradeLevel));

      case wordSnake:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) => WordSnakeGame(gradeLevel: gradeLevel));

      case wordMemory:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) => WordMemoryGame(gradeLevel: gradeLevel));

      case wordBuilder:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) => WordBuilderGame(gradeLevel: gradeLevel));

      case wordWhirl:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) => WordTypeWhirlGame(gradeLevel: gradeLevel));

      case wortbaumeister:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) => WortbaumeisterGame(gradeLevel: gradeLevel));

      case grossstadt:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) => GrossstadtGame(gradeLevel: gradeLevel));

      case grossschreib:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) =>
            GrossschreibungsGalaxieGame(gradeLevel: gradeLevel));

      case verbtrenner:
        final grade = args?['grade'] as int? ?? 1;
        final gradeLevel = GradeLevel.values[grade.clamp(1, 6) - 1];
        return _createGameRoute((_) => VerbtrennerGame(gradeLevel: gradeLevel));

      case AppRoutes.settings:
        return _createRoute(const SettingsScreen());

      case AppRoutes.achievements:
        return _createRoute(const AchievementsScreen());

      case loading:
        final message = args?['message'] as String?;
        return _createRoute(SpaceLoadingScreen(message: message));

      case error:
        final title = args?['title'] as String?;
        final message = args?['message'] as String?;
        return _createRoute(Builder(
          builder: (context) {
            final s = S.of(context)!;
            return SpaceErrorScreen(
              title: title ?? s.genericErrorTitle,
              message: message ?? s.genericErrorMessage,
            );
          },
        ));

      default:
        return _createRoute(
          Builder(
            builder: (context) {
              final s = S.of(context)!;
              return SpaceErrorScreen(
                title: s.routeNotFoundTitle,
                message: s.routeNotFoundMessage,
                onBack: () {
                  if (navigatorKey.currentState?.canPop() ?? false) {
                    navigatorKey.currentState?.pop();
                  } else {
                    navigatorKey.currentState
                        ?.pushReplacementNamed(AppRoutes.home);
                  }
                },
              );
            },
          ),
        );
    }
  }

  static PageRoute _createGameRoute(WidgetBuilder builder) =>
      _createRoute(LanguagePackGate(builder: builder));

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

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _progressController;

  late Animation<double> _logoScale;
  late Animation<double> _textOpacity;
  late Animation<double> _progressAnimation;

  LoadStatus _loadingMessage = const LoadStatus(LoadStage.preparingStation);
  LoadStatus? _detailMessage;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this);
    _textController = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this);
    _progressController = AnimationController(
        duration: const Duration(milliseconds: 300), // Faster updates
        vsync: this);

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _textController, curve: Curves.easeIn));
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _progressController, curve: Curves.easeOut));

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
      await _updateProgress(0.0, const LoadStatus(LoadStage.preparingStation), const LoadStatus(LoadStage.preparingMission));

      if (mounted) {
        // The saved learning language may need a language pack that isn't on
        // this device (the German DB is GPL-3.0 and therefore downloaded, not
        // bundled — see db_platform/db_remote.dart). Resolve that here, with
        // consent and progress, and never leave the app word-less: declining
        // or a failed download falls back to the bundled pack. A pack that is
        // still missing afterwards is caught again at game launch by
        // ensureLanguagePackReady(), so games can't start on empty vocabulary.
        final vocab = context.read<VocabularyService>();
        final packs = context.read<LanguagePackService>();
        await packs.refresh();
        final saved = await packs.savedLanguageStatus();

        if (!saved.installed && mounted) {
          // Apple App Store Review Guidelines §2.4.2 / §4.2.3: disclose the
          // size and prompt before downloading resources. The dialog handles
          // disclosure, progress, retry and the fallback offer.
          await showLanguagePackDialog(
            context,
            languageCode: saved.code,
          );
          // Skip preserves the selected language. Browsing remains available;
          // every game reoffers the pack before its constructor can run.
        } else if (mounted) {
          await vocab.initialize(
            onProgress: (vocabProgress, vocabMessage) {
              // Map vocabulary progress (0.0-1.0) to overall progress (0.0-0.6)
              _updateProgress(
                vocabProgress * 0.6,
                const LoadStatus(LoadStage.preparingStation),
                vocabMessage,
              );
            },
          );
        }
      }

      // PHASE 2: Progress Service (0.6 - 0.7)
      _textController.forward();
      await _updateProgress(
          0.65, const LoadStatus(LoadStage.loadingProgress));
      if (mounted) {
        await context.read<ProgressService>().loadProgress(gameProvider);
      }

      // PHASE 3: SRI Data (0.7 - 0.85)
      await _updateProgress(0.75, const LoadStatus(LoadStage.calibrating), const LoadStatus(LoadStage.loadingLearning));
      if (mounted) {
        await context.read<SriService>().loadSriData();
      }

      // PHASE 4: Cognitive Profile (0.85 - 0.95)
      await _updateProgress(0.9, const LoadStatus(LoadStage.calibrating), const LoadStatus(LoadStage.loadingProfile));
      if (mounted) {
        await context.read<CognitiveProfileService>().loadProfile();
      }

      // PHASE 5: Complete (0.95 - 1.0)
      await _updateProgress(1.0, const LoadStatus(LoadStage.readyForLaunch));
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('[SPLASH] ❌ Initialization error: $e');
      if (kDebugMode) debugPrint('[SPLASH] Stack trace: $stackTrace');

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
                    S.of(context)!.startupFailedTitle,
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
                    S.of(context)!.startupFailed,
                    style: SpaceTheme.bodyStyle,
                  ),
                  SizedBox(height: 8),
                  Text(
                    S.of(context)!.loadFailed,
                    style: SpaceTheme.bodyStyle.copyWith(
                      color: SpaceTheme.starYellow.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // Escape hatch: a pack that refuses to load must not trap the
              // user on the splash screen. The bundled fallback pack needs no
              // network, so this always gets them into the app.
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final ok = await languagePackService.activateFallback();
                  if (!mounted) return;
                  if (ok) {
                    Navigator.pushReplacementNamed(context, AppRoutes.home);
                  } else {
                    _initializeApp(s, gameProvider);
                  }
                },
                child: Text(
                  s.packUseFallback(
                    kLanguagePacks[kFallbackLanguageCode]!.nativeName,
                  ),
                  style: SpaceTheme.bodyStyle.copyWith(
                    color: SpaceTheme.moonSilver,
                  ),
                ),
              ),
              TextButton(
                autofocus: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  // Retry initialization
                  if (mounted) {
                    setState(() {
                      _progress = 0.0;
                      _loadingMessage = const LoadStatus(LoadStage.preparingStation);
                      _detailMessage = null;
                    });
                    _initializeApp(s, gameProvider);
                  }
                },
                child: Text(
                  S.of(context)!.packRetry,
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

  Future<void> _updateProgress(double progress, LoadStatus message, [LoadStatus? detail]) async {
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
                minHeight: screenSize.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
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
                                  color: SpaceTheme.starYellow
                                      .withValues(alpha: 0.5),
                                  blurRadius: isSmallScreen ? 20 : 30,
                                  spreadRadius: isSmallScreen ? 5 : 10,
                                ),
                              ],
                            ),
                            child: Icon(Icons.auto_stories,
                                color: Colors.white,
                                size: isSmallScreen ? 50 : 80),
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
                                    fontSize: isSmallScreen ? 24 : 36),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: isSmallScreen ? 8 : 16),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
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
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  _loadingMessage.localized(S.of(context)!),
                                  style: SpaceTheme.bodyStyle.copyWith(
                                    fontSize: isSmallScreen ? 14 : 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),

                              // NEW: Detail Message (shows the granular progress)
                              if (_detailMessage != null) ...[
                                SizedBox(height: isSmallScreen ? 8 : 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: Text(
                                    _detailMessage!.localized(S.of(context)!),
                                    style: SpaceTheme.bodyStyle.copyWith(
                                      fontSize: isSmallScreen ? 11 : 13,
                                      color: SpaceTheme.starYellow
                                          .withValues(alpha: 0.8),
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
