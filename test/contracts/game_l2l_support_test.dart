// Contract test: every GameInfo in game_menu_screen.dart declares a
// supportedLearningLanguages list that matches its actual language scope.
//
// Guards against:
//   - SpellingSpotter regressing back to ['en'] only (now supports DE via LiTKey)
//   - German-only games (compound-noun builder, verb-splitter, etc.) accidentally
//     gaining 'en' support before the game logic is wired for it
//   - Unsupported language codes being introduced

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Extract all `supportedLearningLanguages: const [...]` literals from a
/// Dart source string. Returns a list of (title-preceding-comment, langs) pairs.
List<({String nearTitle, List<String> langs})> _extractL2lEntries(
    String source) {
  final result = <({String nearTitle, List<String> langs})>[];

  // Match blocks like: supportedLearningLanguages: const ['de', 'en']
  final re = RegExp(
      r"supportedLearningLanguages\s*:\s*const\s*\[([^\]]*)\]",
      dotAll: true);

  for (final m in re.allMatches(source)) {
    final body = m.group(1)!;
    // Extract the quoted strings from inside the brackets
    final langRe = RegExp(r"'([^']+)'");
    final langs = langRe.allMatches(body).map((lm) => lm.group(1)!).toList();

    // Grab a bit of context before this match to identify which game it is
    final start = (m.start - 300).clamp(0, source.length);
    final context = source.substring(start, m.start);
    // Find the last title: s.xxxTitle or title: s.xxx string nearby
    final titleRe = RegExp(r"title\s*:\s*s\.(\w+)");
    final titleMatch = titleRe.allMatches(context).lastOrNull;
    final nearTitle = titleMatch?.group(1) ?? '(unknown)';

    result.add((nearTitle: nearTitle, langs: langs));
  }

  return result;
}

void main() {
  late String menuSource;

  setUpAll(() {
    menuSource = File('lib/features/games/screens/game_menu_screen.dart')
        .readAsStringSync();
  });

  test('only known language codes are used in supportedLearningLanguages', () {
    const knownCodes = {'de', 'en'};
    final entries = _extractL2lEntries(menuSource);

    expect(entries, isNotEmpty,
        reason:
            'No supportedLearningLanguages entries found — regex drifted?');

    final unknown = <String>[];
    for (final e in entries) {
      for (final lang in e.langs) {
        if (!knownCodes.contains(lang)) {
          unknown.add("'$lang' in ${e.nearTitle}");
        }
      }
    }
    expect(unknown, isEmpty,
        reason: 'Unknown language code(s) in supportedLearningLanguages: '
            '$unknown. Only ${knownCodes.join(', ')} are supported.');
  });

  test('SpellingSpotter supports both de and en', () {
    final entries = _extractL2lEntries(menuSource);
    final spotter = entries.where((e) => e.nearTitle.contains('spellingSpotter'));
    expect(spotter, isNotEmpty,
        reason: 'spellingSpotterTitle GameInfo not found in menu — '
            'was it renamed or removed?');

    for (final e in spotter) {
      expect(e.langs, containsAll(['de', 'en']),
          reason: 'SpellingSpotter must support both de and en (DE uses '
              'LiTKey corpus, EN uses commonLearnerErrors). Found: ${e.langs}');
    }
  });

  test('DE-only games do not accidentally include en', () {
    // These games teach German-specific orthography rules (compound nouns,
    // capitalisation, separable verbs). Adding 'en' would show them to EN
    // learners without implementing EN-specific game logic.
    const deOnlyTitleKeys = [
      'wortbaumeisterCardTitle',
      'verbtrennerCardTitle',
      'grossschreibTitle', // GrossschreibungsGalaxie
      'grossstadtCardTitle', // Grossstadt / NounSorter
    ];

    final entries = _extractL2lEntries(menuSource);

    for (final key in deOnlyTitleKeys) {
      final matches = entries.where((e) => e.nearTitle == key);
      // Only assert if the game is present — a missing game is caught by the
      // menu_games_call_record_level_win_test, not here.
      for (final e in matches) {
        expect(e.langs, isNot(contains('en')),
            reason: "'$key' is a DE-only game and must not include 'en' in "
                'supportedLearningLanguages. Found: ${e.langs}');
      }
    }
  });

  test('no game has an empty supportedLearningLanguages list', () {
    final entries = _extractL2lEntries(menuSource);
    final empty = entries.where((e) => e.langs.isEmpty).toList();
    expect(empty, isEmpty,
        reason: 'Game(s) with empty supportedLearningLanguages: '
            '${empty.map((e) => e.nearTitle).toList()}. '
            'An empty list means the game never appears in the menu.');
  });
}
