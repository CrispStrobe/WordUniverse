// Resumable download transport tests for db_remote.dart.
//
// Uses a fake streaming http.Client so the transport (Range resume, 200 on
// Range, malformed 206, timeouts, pause/abort, integrity, cache flushes) is
// exercised without any network.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:WortUniversum/core/services/db_platform/db_partial_cache.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';

class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final List<http.BaseRequest> requests = [];
  int closeCount = 0;
  bool get closed => closeCount > 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() => closeCount++;
}

http.StreamedResponse _bytesResponse(
  List<int> bytes, {
  int status = 200,
  Map<String, String> headers = const {},
}) {
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable([
      for (var i = 0; i < bytes.length; i += 3)
        bytes.sublist(i, (i + 3).clamp(0, bytes.length)),
    ]),
    status,
    contentLength: bytes.length,
    headers: headers,
  );
}

void main() {
  const url = 'https://example.test/db.gz';
  final payload = List<int>.generate(20, (i) => i);

  group('downloadCompressedDb transport', () {
    test('reports byte-level progress while streaming', () async {
      final client = _FakeHttp((_) async => _bytesResponse(payload));
      final progress = <double>[];
      await downloadCompressedDb(
        url: url,
        clientFactory: () => client,
        partialCache: MemoryDbPartialCache(),
        backoff: Duration.zero,
        onProgress: (p, _) => progress.add(p),
      );
      expect(progress.first, 0.0);
      expect(progress.last, 1.0);
      // Monotonically non-decreasing and driven by real chunks (not one jump).
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      expect(progress.length, greaterThan(2));
    });

    test(
        'pause aborts the connection and persists partial bytes; '
        'resume uses a Range request and completes', () async {
      final cache = MemoryDbPartialCache();
      var paused = false;
      RangeHeader? seenRange;

      final client = _FakeHttp((req) async {
        if (req.headers['range'] case final r?) {
          seenRange = RangeHeader.parse(r);
          final start = seenRange!.start;
          return _bytesResponse(payload.sublist(start), status: 206, headers: {
            'content-range':
                'bytes $start-${payload.length - 1}/${payload.length}',
          });
        }
        return _bytesResponse(payload);
      });

      // First attempt: pause after the second chunk.
      var chunkCount = 0;
      Future<void> drivePause() async {
        try {
          await downloadCompressedDb(
            url: url,
            clientFactory: () => client,
            partialCache: cache,
            backoff: Duration.zero,
            isPaused: () => paused,
            onChunk: () {
              if (++chunkCount == 2) paused = true;
            },
          );
          fail('should have thrown paused');
        } on DbDownloadPausedException {
          // expected
        }
      }

      await drivePause();
      expect(client.closed, isTrue, reason: 'pause must abort the network');
      final partial = await cache.load(url);
      expect(partial, isNotNull);
      expect(partial!.length, lessThan(payload.length));

      // Resume: no pause this time, server honours the Range.
      paused = false;
      final result = await downloadCompressedDb(
        url: url,
        clientFactory: () => client,
        partialCache: cache,
        backoff: Duration.zero,
        isPaused: () => false,
      );
      expect(result, payload);
      expect(seenRange, isNotNull);
      expect(seenRange!.start, partial.length);
      // Cache cleaned up after success.
      expect(await cache.load(url), isNull);
    });

    test('a 200 response despite a Range header restarts from scratch',
        () async {
      final cache = MemoryDbPartialCache();
      await cache.save(url, [9, 9, 9, 9, 9]);

      var sawRange = false;
      final client = _FakeHttp((req) async {
        if (req.headers.containsKey('range')) sawRange = true;
        return _bytesResponse(payload);
      });

      final result = await downloadCompressedDb(
        url: url,
        clientFactory: () => client,
        partialCache: cache,
        backoff: Duration.zero,
      );
      expect(sawRange, isTrue);
      expect(result, payload, reason: 'must be the full body, not appended');
      expect(await cache.load(url), isNull);
    });

    test('a malformed/mismatched 206 restarts from scratch', () async {
      final cache = MemoryDbPartialCache();
      await cache.save(url, [1, 2, 3]);

      var requests = 0;
      final client = _FakeHttp((req) async {
        requests++;
        if (req.headers.containsKey('range') && requests == 1) {
          // Lie about where the body starts.
          return _bytesResponse(
            payload,
            status: 206,
            headers: {'content-range': 'bytes 99-118/${payload.length}'},
          );
        }
        return _bytesResponse(payload);
      });

      final result = await downloadCompressedDb(
        url: url,
        clientFactory: () => client,
        partialCache: cache,
        backoff: Duration.zero,
      );
      expect(result, payload);
      expect(requests, greaterThanOrEqualTo(2));
    });

    test('a well-formed 206 continues from the offset', () async {
      final cache = MemoryDbPartialCache();
      const offset = 7;
      await cache.save(url, payload.sublist(0, offset));

      final client = _FakeHttp((req) async {
        expect(req.headers['range'], 'bytes=$offset-');
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([payload.sublist(offset)]),
          206,
          contentLength: payload.length - offset,
          headers: {
            'content-range':
                'bytes $offset-${payload.length - 1}/${payload.length}',
          },
        );
      });

      final result = await downloadCompressedDb(
        url: url,
        clientFactory: () => client,
        partialCache: cache,
        backoff: Duration.zero,
      );
      expect(result, payload);
    });

    test('a timeout closes the client and a retry resumes from the cache',
        () async {
      final cache = MemoryDbPartialCache();
      final clients = <_FakeHttp>[];

      _FakeHttp makeClient() {
        final c = _FakeHttp((req) async {
          // First request: stream that flushes 6 bytes then hangs forever.
          if (clients.length == 1) {
            return http.StreamedResponse(
              () async* {
                yield payload.sublist(0, 6);
                await Completer<void>().future;
              }(),
              200,
              contentLength: payload.length,
            );
          }
          return _bytesResponse(payload.sublist(6), status: 206, headers: {
            'content-range': 'bytes 6-${payload.length - 1}/${payload.length}',
          });
        });
        clients.add(c);
        return c;
      }

      var current = makeClient();
      final result = await downloadCompressedDb(
        url: url,
        clientFactory: () => current,
        partialCache: cache,
        backoff: Duration.zero,
        attemptTimeout: const Duration(milliseconds: 50),
        maxAttempts: 2,
        onChunk: () {
          // After the first client hangs, swap so the retry gets a good one.
          if (clients.length == 1) current = makeClient();
        },
      );
      expect(result, payload);
      expect(clients.first.closed, isTrue,
          reason: 'timeout must close the client to abort the socket');
      // Second attempt resumed via Range rather than restarting at 0.
      expect(clients.last.requests.first.headers['range'], 'bytes=6-');
    });

    test('truncated body (Content-Length mismatch) is a retryable failure',
        () async {
      final client = _FakeHttp((_) async {
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([payload.sublist(0, 5)]),
          200,
          contentLength: payload.length,
        );
      });
      await expectLater(
        downloadCompressedDb(
          url: url,
          clientFactory: () => client,
          partialCache: MemoryDbPartialCache(),
          backoff: Duration.zero,
          maxAttempts: 1,
        ),
        throwsA(isA<DbDownloadException>()
            .having((e) => e.isNetwork, 'isNetwork', isTrue)),
      );
    });

    test('wrong pinned compressed size is a non-network failure', () async {
      final client = _FakeHttp((_) async => _bytesResponse(payload));
      await expectLater(
        downloadCompressedDb(
          url: url,
          expectedCompressedBytes: 999,
          clientFactory: () => client,
          partialCache: MemoryDbPartialCache(),
          backoff: Duration.zero,
          maxAttempts: 1,
        ),
        throwsA(isA<DbDownloadException>()
            .having((e) => e.isNetwork, 'isNetwork', isFalse)),
      );
    });

    test('pausing during the retry backoff also surfaces as paused', () async {
      final cache = MemoryDbPartialCache();
      var paused = false;
      final client = _FakeHttp((_) async {
        // Always fail with a server error; pause is requested meanwhile.
        paused = true;
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([]),
          503,
        );
      });
      await expectLater(
        downloadCompressedDb(
          url: url,
          clientFactory: () => client,
          partialCache: cache,
          backoff: Duration.zero,
          maxAttempts: 2,
          isPaused: () => paused,
        ),
        throwsA(isA<DbDownloadPausedException>()),
      );
    });
  });
}

typedef RangeHeader = _RangeHeader;

class _RangeHeader {
  final int start;
  final int? end;
  _RangeHeader(this.start, this.end);
  static _RangeHeader? parse(String value) {
    final m = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(value.trim());
    if (m == null) return null;
    return _RangeHeader(
      int.parse(m.group(1)!),
      m.group(2)!.isEmpty ? null : int.parse(m.group(2)!),
    );
  }
}
