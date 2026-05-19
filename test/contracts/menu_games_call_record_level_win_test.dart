// Contract test: every game class registered in the menu actually calls
// recordLevelWin somewhere in its source. Catches the class of bug we hit
// where 6 of 11 voc games never reported progress at all — players could
// finish them but the global score / level / cognitive profile never
// advanced.
//
// Strategy: walk game_menu_screen.dart for class constructors invoked
// inside onTap, then check that each class's source file contains a
// recordLevelWin( call. Dart convention is class FooGame in foo_game.dart
// — we map class → snake_case file under lib/features/games/screens/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _classToSnakeCase(String className) {
  // CamelCase → snake_case, e.g. SpaceWordRescueGame → space_word_rescue_game.
  final buf = StringBuffer();
  for (var i = 0; i < className.length; i++) {
    final c = className[i];
    if (c == c.toUpperCase() && c != c.toLowerCase()) {
      if (i > 0) buf.write('_');
      buf.write(c.toLowerCase());
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}

/// One-off overrides for class → file name mappings that don't follow the
/// strict snake_case-of-class-name convention.
const Map<String, String> _filenameOverrides = {
  'GrossschreibungsGalaxieGame': 'grossschreib_game',
};

void main() {
  test('every game class in the menu calls recordLevelWin', () {
    final menuFile =
        File('lib/features/games/screens/game_menu_screen.dart')
            .readAsStringSync();

    // Extract class names from `_navigateToGame(SomeGame(...)`
    final regex = RegExp(r'_navigateToGame\(\s*(\w+Game)\s*\(');
    final gameClasses = regex
        .allMatches(menuFile)
        .map((m) => m.group(1)!)
        .toSet();

    expect(gameClasses, isNotEmpty,
        reason: 'No game classes extracted from menu — regex drifted?');

    final missingFiles = <String>[];
    final missingRecordCalls = <String>[];

    for (final cls in gameClasses) {
      final filename = _filenameOverrides[cls] ?? _classToSnakeCase(cls);
      final path = 'lib/features/games/screens/$filename.dart';
      final file = File(path);
      if (!file.existsSync()) {
        missingFiles.add('$cls → $path (not found)');
        continue;
      }
      final source = file.readAsStringSync();
      if (!source.contains('recordLevelWin(')) {
        missingRecordCalls.add('$cls ($path)');
      }
    }

    expect(missingFiles, isEmpty,
        reason: 'Could not locate game source file for class(es): '
            '$missingFiles. Either rename the file to match the class '
            '(snake_case) or add an entry to _filenameOverrides above.');

    expect(missingRecordCalls, isEmpty,
        reason: 'Menu-registered game class(es) do not call '
            'recordLevelWin anywhere in their source: $missingRecordCalls. '
            'Without it, players can complete the game but global '
            'progression/scoring will not advance.');
  });
}
