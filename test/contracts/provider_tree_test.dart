// Contract test: every type consumed via `context.read<T>()` /
// `context.watch<T>()` / `Consumer<T>` somewhere in lib/ is registered in
// the provider tree in lib/main.dart. Catches the class of bug where a
// game uses context.read<NewService>() but NewService was never registered.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Provider types registered in lib/main.dart's MultiProvider.
/// Mirror exactly what runApp(MultiProvider(providers: [...])) sets up.
const Set<String> registeredProviders = {
  'GameProvider',
  'SriService',
  'CognitiveProfileService',
  'VocabularyService',
  'PurchaseService',
  'DebugProvider',
  'ProgressService',
  'AudioService',
  'StreakService',
};

void main() {
  test('every context.read<T>() / context.watch<T>() / Consumer<T> '
      'type is in the registered provider tree', () {
    final regex = RegExp(
      r'(?:context\.(?:read|watch)|Consumer|Selector(?:\d+)?)<(\w+)>',
    );
    final consumedTypes = <String>{};

    final libDir = Directory('lib');
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('lib/main.dart')) continue;
      final content = entity.readAsStringSync();
      for (final m in regex.allMatches(content)) {
        consumedTypes.add(m.group(1)!);
      }
    }

    expect(consumedTypes, isNotEmpty,
        reason: 'No provider consumers found in lib/ — regex drifted?');

    final unregistered = consumedTypes
        .where((t) => !registeredProviders.contains(t))
        .toSet();
    expect(unregistered, isEmpty,
        reason: 'Type(s) consumed via Provider but not registered in '
            'lib/main.dart: $unregistered. Either register them in the '
            'MultiProvider, or update registeredProviders in this test.');
  });
}
