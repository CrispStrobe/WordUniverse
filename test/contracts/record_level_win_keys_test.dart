// Contract test: every gameType: literal in lib/ has a matching entry in
// GameProvider.gameSkillMap. Catches the class of bug where a game calls
// recordLevelWin with a key the provider can't resolve — the call returns
// false silently and progression stops working.
//
// gameSkillMap is an instance field on GameProvider (not a top-level
// const), so we extract its keys via text-parsing instead of importing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _extractGameSkillMapKeys() {
  final providerFile =
      File('lib/features/games/providers/game_provider.dart').readAsStringSync();
  // Locate the gameSkillMap = { ... }; literal.
  final mapRegex = RegExp(
    r'gameSkillMap\s*=\s*\{([\s\S]*?)\};',
  );
  final mapMatch = mapRegex.firstMatch(providerFile);
  if (mapMatch == null) {
    fail('Could not locate gameSkillMap literal in game_provider.dart — '
        'regex drifted?');
  }
  final body = mapMatch.group(1)!;
  // Each entry: 'key_name': ...
  final keyRegex = RegExp(r"'([a-zA-Z_][a-zA-Z0-9_]*)'\s*:");
  return keyRegex.allMatches(body).map((m) => m.group(1)!).toSet();
}

void main() {
  test('every gameType: literal across the codebase is in gameSkillMap', () {
    final mapKeys = _extractGameSkillMapKeys();
    expect(mapKeys, isNotEmpty,
        reason: 'gameSkillMap appears empty — extraction failed?');

    final regex = RegExp(r"gameType:\s*'([^']+)'");
    final usedKeys = <String>{};

    final libDir = Directory('lib');
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      for (final m in regex.allMatches(content)) {
        usedKeys.add(m.group(1)!);
      }
    }

    expect(usedKeys, isNotEmpty,
        reason: 'No gameType: literals found in lib/ — regex drifted?');

    final missing = usedKeys.where((k) => !mapKeys.contains(k)).toSet();
    expect(missing, isEmpty,
        reason: 'gameType key(s) used at call sites but not in gameSkillMap: '
            '$missing. recordLevelWin will silently return false and '
            'progression will not advance.');
  });
}
