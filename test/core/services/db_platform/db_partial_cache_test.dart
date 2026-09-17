// Tests for the durable partial-download cache (native file + web-friendly
// abstraction). Shared prefs are explicitly NOT used for large byte payloads.

@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache_io.dart';

class _FailingFile implements File {
  _FailingFile(this.error);
  final FileSystemException error;
  @override
  Future<File> writeAsBytes(List<int> bytes,
          {FileMode mode = FileMode.write, bool flush = false}) async =>
      throw error;
  @override
  Future<File> delete({bool recursive = false}) async =>
      throw StateError('cleanup failed');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('db_partial_cache_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('FileDbPartialCache (native)', () {
    for (final code in [28, 112, 13]) {
      test('write errno $code is typed and cleanup preserves original cause',
          () async {
        final error =
            FileSystemException('write failed', '', OSError('failure', code));
        final cache = FileDbPartialCache(
            baseDirectory: tmp,
            temporaryFileFactory: (_) => _FailingFile(error));
        await expectLater(
            cache.save('u', [1]),
            throwsA(isA<DbStorageException>()
                .having((e) => e.cause, 'cause', same(error))
                .having((e) => e.isNetwork, 'network', false)
                .having((e) => e is DbInsufficientSpaceException, 'space',
                    code != 13)));
      });
    }
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

  group('checkpoint envelope', () {
    test('one record carries prefix and validator together', () async {
      final cache = MemoryDbPartialCache();
      await cache.saveCheckpoint('u', [1, 2, 3], '"tag"');
      final record = await cache.loadRecord('u');
      expect(record!.bytes, [1, 2, 3]);
      expect(record.validator, '"tag"');
    });

    test('a record written without a validator reports none', () async {
      final cache = MemoryDbPartialCache();
      await cache.save('u', [1, 2, 3]);
      expect((await cache.loadRecord('u'))!.validator, isNull);
      expect(await cache.loadValidator('u', [1, 2, 3]), isNull);
    });

    test('an oversized validator is stored as none rather than truncated',
        () async {
      final cache = MemoryDbPartialCache();
      await cache.saveCheckpoint('u', [1], '"${'x' * 300}"');
      final record = await cache.loadRecord('u');
      expect(record!.bytes, [1]);
      expect(record.validator, isNull,
          reason: 'a truncated validator would never match the server');
    });

    test('a v1 record from an older build is refused, not misread', () async {
      final cache = MemoryDbPartialCache();
      // Legacy layout: [4B length][32B sha256][payload], no magic/version.
      final legacy = BytesBuilder()
        ..add(Uint8List(4)..buffer.asByteData().setUint32(0, 3, Endian.little))
        ..add(sha256.convert([1, 2, 3]).bytes)
        ..add([1, 2, 3]);
      await cache.writeRecord(cache.keyFor('u'), legacy.takeBytes());
      expect(await cache.load('u'), isNull);
    });

    test('validator is dropped when the cached prefix moved on', () async {
      final cache = MemoryDbPartialCache();
      await cache.saveCheckpoint('u', [1, 2, 3], '"tag"');
      expect(await cache.loadValidator('u', [1, 2]), isNull);
      expect(await cache.loadValidator('u', [1, 2, 3]), '"tag"');
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
