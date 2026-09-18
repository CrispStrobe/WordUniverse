@TestOn('vm')
library;

// The feature index is computed with SQLite's JSON1 functions, and on the web
// those come from the sqlite3.wasm this repository ships. If that binary were
// ever regenerated without JSON support, the index build would fail, every
// word would read as carrying no enrichment, and every game would open with an
// empty pool — on the deployed web build, silently.
//
// The browser suites that would catch it (`flutter test --platform chrome`) do
// not run in CI, so this checks the shipped binary itself. It is a VM test on
// purpose: it must run everywhere the suite runs.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Names SQLite registers for its built-in functions appear verbatim in the
/// compiled binary's function table.
Set<String> _symbols(File binary) {
  final bytes = binary.readAsBytesSync();
  final found = <String>{};
  final buffer = StringBuffer();
  for (final byte in bytes) {
    if (byte >= 0x20 && byte < 0x7f) {
      buffer.writeCharCode(byte);
      continue;
    }
    if (buffer.isNotEmpty) {
      found.add(buffer.toString());
      buffer.clear();
    }
  }
  if (buffer.isNotEmpty) found.add(buffer.toString());
  return found;
}

void main() {
  test('the shipped sqlite3.wasm can run the feature index build', () {
    final wasm = File('web/sqlite3.wasm');
    expect(wasm.existsSync(), isTrue,
        reason: 'run from the repository root; web/sqlite3.wasm is the '
            'binary the web build serves');

    final symbols = _symbols(wasm);
    // Every SQL function db_feature_index.dart depends on.
    for (final function in [
      'json_each',
      'json_array_length',
      'json_extract',
      'json_type',
      'group_concat',
    ]) {
      expect(symbols, contains(function),
          reason: 'sqlite3.wasm has no $function: the feature index would fail '
              'to build and every game pool would be empty on web');
    }
  });
}
