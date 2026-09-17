import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache.dart';

class Client extends http.BaseClient {
  Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  int calls = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    return handler(request);
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  test(
      'pause during stalled headers closes immediately and settles; retry is possible',
      () async {
    const url = 'https://test/headers';
    final controller = DbDownloadController.sharedFor(url);
    final sent = Completer<void>();
    final client = Client((_) {
      sent.complete();
      return Completer<http.StreamedResponse>().future;
    });
    final future = downloadCompressedDb(
        url: url,
        clientFactory: () => client,
        partialCache: MemoryDbPartialCache());
    final assertion =
        expectLater(future, throwsA(isA<DbDownloadPausedException>()));
    await sent.future;
    controller.pause();
    expect(client.closed, isTrue);
    await assertion;
    expect(controller.snapshot.status, DbDownloadStatus.paused);
    controller.resume();
    final good = Client((_) async =>
        http.StreamedResponse(Stream.value([1, 2]), 200, contentLength: 2));
    expect(
        await downloadCompressedDb(
            url: url,
            clientFactory: () => good,
            partialCache: MemoryDbPartialCache()),
        [1, 2]);
  });

  test('pause of stalled body retains bytes and resume sends exact Range',
      () async {
    const url = 'https://test/body';
    final c = DbDownloadController.sharedFor(url);
    final cache = MemoryDbPartialCache();
    final body = StreamController<List<int>>();
    final got = Completer<void>();
    final client = Client(
        (_) async => http.StreamedResponse(body.stream, 200, contentLength: 4));
    final f = downloadCompressedDb(
        url: url,
        clientFactory: () => client,
        partialCache: cache,
        onChunk: () {
          if (!got.isCompleted) got.complete();
        });
    final assertion = expectLater(f, throwsA(isA<DbDownloadPausedException>()));
    body.add([1, 2]);
    await got.future;
    c.pause();
    expect(client.closed, isTrue);
    await assertion;
    expect(await cache.load(url), [1, 2]);
    await body.close();
    c.resume();
    final resumed = Client((r) async {
      expect(r.headers['range'], 'bytes=2-');
      return http.StreamedResponse(Stream.value([3, 4]), 206,
          contentLength: 2, headers: {'content-range': 'bytes 2-3/4'});
    });
    expect(
        await downloadCompressedDb(
            url: url, clientFactory: () => resumed, partialCache: cache),
        [1, 2, 3, 4]);
  });

  test(
      'concurrent callers join and both receive progress; later calls are fresh',
      () async {
    const url = 'https://test/concurrency';
    final body = StreamController<List<int>>();
    final sent = Completer<void>();
    final client = Client((_) async {
      sent.complete();
      return http.StreamedResponse(body.stream, 200, contentLength: 4);
    });
    final aProgress = <double>[];
    final bProgress = <double>[];
    final a = downloadCompressedDb(
        url: url,
        clientFactory: () => client,
        partialCache: MemoryDbPartialCache(),
        onProgress: (p, _) => aProgress.add(p));
    await sent.future;
    final b = downloadCompressedDb(
        url: url,
        clientFactory: () => throw StateError('must join'),
        onProgress: (p, _) => bProgress.add(p));
    body.add([1, 2]);
    body.add([3, 4]);
    await body.close();
    expect(await a, [1, 2, 3, 4]);
    expect(await b, [1, 2, 3, 4]);
    expect(client.calls, 1);
    expect(aProgress, contains(0.5));
    expect(bProgress, contains(0.5));
    expect(bProgress.last, 1);
    final next = Client((_) async =>
        http.StreamedResponse(Stream.value([9]), 200, contentLength: 1));
    expect(
        await downloadCompressedDb(
            url: url,
            clientFactory: () => next,
            partialCache: MemoryDbPartialCache()),
        [9]);
  });

  test('no late header response can write after timeout', () async {
    const url = 'https://test/late';
    final headers = Completer<http.StreamedResponse>();
    final old = Client((_) => headers.future);
    final good = Client((r) async =>
        http.StreamedResponse(Stream.value([7, 8]), 200, contentLength: 2));
    var attempt = 0;
    final cache = MemoryDbPartialCache();
    final bytes = await downloadCompressedDb(
        url: url,
        clientFactory: () => attempt++ == 0 ? old : good,
        partialCache: cache,
        backoff: Duration.zero,
        attemptTimeout: const Duration(milliseconds: 20));
    expect(bytes, [7, 8]);
    expect(old.closed, isTrue);
    headers.complete(
        http.StreamedResponse(Stream.value([1, 2, 3]), 200, contentLength: 3));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(await cache.load(url), isNull);
    expect(DbDownloadController.sharedFor(url).received, 2);
  });

  test('invalid 206 variants cannot append and are retried without Range',
      () async {
    for (final header in [
      null,
      'bytes 2-1/4',
      'bytes 2-9/4',
      'bytes 2-3/*',
      'bytes 2-2/4'
    ]) {
      final cache = MemoryDbPartialCache();
      final url = 'https://test/ranges/$header';
      await cache.save(url, [1, 2]);
      var n = 0;
      final bytes = await downloadCompressedDb(
          url: url,
          partialCache: cache,
          clientFactory: () => Client((r) async {
                if (n++ == 0)
                  return http.StreamedResponse(Stream.value([9]), 206,
                      headers: {if (header != null) 'content-range': header});
                expect(r.headers['range'], isNull);
                return http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200,
                    contentLength: 4);
              }));
      expect(bytes, [1, 2, 3, 4]);
    }
  });

  test('resume uses If-Range and rejects a changed entity in a 206', () async {
    const url = 'https://test/validator';
    final cache = MemoryDbPartialCache();
    final c = DbDownloadController.sharedFor(url);
    final first = Client((_) async => http.StreamedResponse(
        Stream.value([1, 2]), 200,
        contentLength: 4, headers: {'etag': '"old"'}));
    await expectLater(
        downloadCompressedDb(
            url: url,
            partialCache: cache,
            clientFactory: () => first,
            onChunk: c.pause),
        throwsA(isA<DbDownloadPausedException>()));
    c.resume();
    var requests = 0;
    final result = await downloadCompressedDb(
        url: url,
        partialCache: cache,
        clientFactory: () => Client((r) async {
              if (requests++ == 0) {
                expect(r.headers['if-range'], '"old"');
                return http.StreamedResponse(Stream.value([9, 9]), 206,
                    contentLength: 2,
                    headers: {'etag': '"new"', 'content-range': 'bytes 2-3/4'});
              }
              expect(r.headers['range'], isNull);
              return http.StreamedResponse(Stream.value([8, 8, 9, 9]), 200,
                  contentLength: 4);
            }));
    expect(result, [8, 8, 9, 9]);
  });

  test('size pin conflict is rejected while another caller is running',
      () async {
    const url = 'https://test/pins';
    final sent = Completer<void>();
    final client = Client((_) {
      sent.complete();
      return Completer<http.StreamedResponse>().future;
    });
    final f = downloadCompressedDb(
        url: url,
        expectedCompressedBytes: 2,
        clientFactory: () => client,
        partialCache: MemoryDbPartialCache());
    final assertion = expectLater(f, throwsA(isA<DbDownloadPausedException>()));
    await sent.future;
    await expectLater(
        downloadCompressedDb(url: url, expectedCompressedBytes: 3),
        throwsArgumentError);
    DbDownloadController.sharedFor(url).pause();
    await assertion;
  });
}
