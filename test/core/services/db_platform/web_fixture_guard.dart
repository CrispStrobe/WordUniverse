// Fails a browser suite fast, and says why, when the SQLite fixtures are not
// really being served.
//
// test/fixtures/sqlite_web/ holds symlinks to the app's own binaries. A
// checkout that cannot store symlinks — Windows without developer mode, some
// network mounts — leaves a ~25-byte text file containing the target path in
// their place. The test server then answers 200 with that text, the wasm never
// instantiates, and every test in the suite hangs until its 30-second timeout,
// including tests that have nothing to do with SQLite. That is a confusing
// half hour; this turns it into one clear failure.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Magic bytes every WebAssembly module starts with: "\0asm".
const _wasmMagic = [0x00, 0x61, 0x73, 0x6d];

/// Call from `setUpAll` in any browser suite that opens a database.
Future<void> assertWebFixturesServed() async {
  final wasm = await http.get(Uri.parse('/fixtures/sqlite_web/sqlite3.wasm'));
  final head = wasm.bodyBytes.take(4).toList();

  if (wasm.statusCode != 200 || head.length < 4 || !_looksLikeWasm(head)) {
    fail('/fixtures/sqlite_web/sqlite3.wasm is not a WebAssembly module '
        '(${wasm.statusCode}, ${wasm.bodyBytes.length} bytes: '
        '"${_preview(wasm.body)}").\n'
        'The fixtures are symlinks into web/. This checkout did not preserve '
        'them, so the browser is being served the link text instead of the '
        'binary. Restore them with `git checkout -- test/fixtures/sqlite_web/` '
        'on a filesystem that supports symlinks, or copy web/sqlite3.wasm and '
        'web/sqflite_sw.js over them to run the suite here.');
  }

  final worker = await http.get(Uri.parse('/fixtures/sqlite_web/sqflite_sw.js'));
  if (worker.statusCode != 200 || worker.bodyBytes.length < 1024) {
    fail('/fixtures/sqlite_web/sqflite_sw.js is not the worker script '
        '(${worker.statusCode}, ${worker.bodyBytes.length} bytes). See above.');
  }
}

bool _looksLikeWasm(List<int> head) {
  for (var i = 0; i < _wasmMagic.length; i++) {
    if (head[i] != _wasmMagic[i]) return false;
  }
  return true;
}

String _preview(String body) {
  final trimmed = body.trim();
  return trimmed.length <= 60 ? trimmed : '${trimmed.substring(0, 57)}...';
}
