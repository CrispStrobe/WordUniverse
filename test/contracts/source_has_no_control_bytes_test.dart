@TestOn('vm')
library;

// A regex written through a script can arrive with a control character in it.
//
// `_geographyGloss` shipped dead: its trailing `\b` was a literal backspace
// byte, because the tool that wrote the file read `\b` as an escape rather
// than as two characters. Dart compiled it, `dart format` formatted it, the
// analyzer passed it and every test passed, because the rule simply never
// matched anything — and the one place it was cross-checked, repair_pack.py,
// carries its own correct copy in Python.
//
// The rule's own test now asserts it fires. This asserts the shape of the
// mistake, for the next rule written the same way.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tab, newline and carriage return are the only ones that belong in source.
final _control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]');

void main() {
  test('no source file carries a control character', () {
    final offenders = <String>[];
    for (final directory in ['lib', 'test', 'tools']) {
      final root = Directory(directory);
      if (!root.existsSync()) continue;
      for (final entry in root.listSync(recursive: true)) {
        if (entry is! File) continue;
        if (!const ['.dart', '.py', '.sh', '.yml', '.yaml', '.json']
            .any(entry.path.endsWith)) {
          continue;
        }
        final String text;
        try {
          text = entry.readAsStringSync();
        } on FileSystemException {
          continue; // not text; nothing to read
        }
        for (final match in _control.allMatches(text)) {
          final line = '\n'.allMatches(text.substring(0, match.start)).length;
          final code = match.group(0)!.codeUnitAt(0);
          offenders.add('${entry.path}:${line + 1} '
              'U+${code.toRadixString(16).padLeft(4, '0')}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a control character in source is almost always a `\\b`, '
            '`\\t` or `\\n` that a generating script consumed as an escape:\n'
            '  ${offenders.join('\n  ')}');
  });
}
