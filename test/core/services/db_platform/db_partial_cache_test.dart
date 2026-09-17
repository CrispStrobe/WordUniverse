// Tests for the durable partial-download cache (native file + web-friendly
// abstraction). Shared prefs are explicitly NOT used for large byte payloads.

@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache_io.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('db_partial_cache_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('FileDbPartialCache (native)', () {
    late FileDbPartialCache cache;

    setUp(() => cache = FileDbPartialCache(baseDirectory: tmp));

    test('save/load round-trips bytes under a URL-derived key', () async {
      final key = cache.keyFor('https://example.test/db.gz');
      expect(key, isNotEmpty);
      // No path-hostile characters survive in the file name.
      expect(key, isNot(contains('/')));
      await cache.save(
          'https://example.test/db.gz', Uint8List.fromList([1, 2, 3]));
      final loaded = await cache.load('https://example.test/db.gz');
      expect(loaded, [1, 2, 3]);
    });

    test('load returns null for a missing or truncated entry', () async {
      expect(await cache.load('https://x.test/none'), isNull);

      final url = 'https://x.test/corrupt';
      await cache.save(url, Uint8List.fromList([4, 5, 6]));
      final file = File('${tmp.path}/${cache.keyFor(url)}.partial');
      await file.writeAsString('short');
      expect(await cache.load(url), isNull, reason: 'length prefix mismatch');
    });

    test('checkpoint validator survives a new native cache instance', () async {
      const url = 'https://x.test/validator';
      await cache.saveCheckpoint(url, [1, 2, 3], '"version-1"');
      final reopened = FileDbPartialCache(baseDirectory: tmp);
      final bytes = await reopened.load(url);
      expect(bytes, [1, 2, 3]);
      expect(await reopened.loadValidator(url, bytes!), '"version-1"');
      // A torn write must not pair new bytes with an old validator.
      await reopened.save(url, [1, 2, 4]);
      expect(await cache.loadValidator(url, (await cache.load(url))!), isNull);
      await reopened.clearCheckpoint(url);
      expect(await cache.load(url), isNull);
      expect(await cache.loadValidator(url, [1, 2, 3]), isNull);
    });

    test('same-length corruption of stored bytes is rejected', () async {
      const url = 'https://x.test/digest';
      await cache.save(url, [1, 2, 3]);
      final file = File('${tmp.path}/${cache.keyFor(url)}.partial');
      final raw = await file.readAsBytes();
      raw[raw.length - 1] ^= 1;
      await file.writeAsBytes(raw);
      expect(await cache.load(url), isNull);
    });

    test('clear removes the partial bytes', () async {
      const url = 'https://x.test/clear-me';
      await cache.save(url, Uint8List.fromList([7]));
      await cache.clear(url);
      expect(await cache.load(url), isNull);
    });
  });

  group('MemoryDbPartialCache', () {
    test('round-trips and clears', () async {
      final cache = MemoryDbPartialCache();
      await cache.save('u', Uint8List.fromList([1]));
      expect(await cache.load('u'), [1]);
      await cache.clear('u');
      expect(await cache.load('u'), isNull);
    });
  });
}
