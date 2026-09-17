import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu defers all game constructors and displays selected language', () {
    final menu = File('lib/features/games/screens/game_menu_screen.dart').readAsStringSync();
    expect(menu, contains('_navigateToGame(WidgetBuilder builder)'));
    expect(menu, contains('context.watch<LanguagePackService>().selectedLanguage'));
    expect(RegExp(r'_navigateToGame\(\s*(?:const )?\w+Game\(').hasMatch(menu), false);
  });
  test('first route is not layered over an initializing splash', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('onGenerateInitialRoutes:'));
  });
  test('startup picker precedes onboarding and splash never auto-falls back on skip', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('LanguageSetupScreen.isComplete(widget.prefs)'));
    expect(main, contains('LanguageSetupScreen('));
    final startup = main.substring(main.indexOf('if (!saved.installed'),
      main.indexOf('// PHASE 2:'));
    expect(startup, isNot(contains('activateFallback')));
  });
  test('all named games use lazy guarded route factories', () {
    final main = File('lib/main.dart').readAsStringSync();
    final games = main.substring(main.indexOf('case spaceWordRescue:'),
      main.indexOf('case AppRoutes.settings:'));
    expect(RegExp(r'_createGameRoute\(').allMatches(games).length, 11);
    expect(games, isNot(contains('_createRoute(')));
  });
  test('daily game and review factories run only after readiness gate', () {
    final daily = File('lib/features/home/screens/daily_session_screen.dart').readAsStringSync();
    expect(daily, contains('WidgetBuilder builder'));
    expect(daily, contains('await ensureLanguagePackReady(context)'));
    expect(daily, contains('_play(2, (_) => _goalGame(profile.goal))'));
  });
  test('settings expose paused status and do not demand locale restart', () {
    final settings = File('lib/features/settings/screens/settings_screen.dart').readAsStringSync();
    expect(settings, contains('LanguagePackStatus.paused'));
    expect(settings, contains('service.pause(state.pack.code)'));
    expect(settings, contains('MyApp.setLocale(context, Locale(localeCode))'));
    expect(settings, isNot(contains('_showLanguageChangeDialog(localeCode);')));
  });
}
