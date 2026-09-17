@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache.dart';

void main() {
  test('real HTTP socket aborts on pause; next connection uses Range',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = 'http://${server.address.address}:${server.port}/db.gz';
    final c = DbDownloadController.sharedFor(url);
    final cache = MemoryDbPartialCache();
    final firstBytes = Completer<void>();
    final ranges = <String?>[];
    final handlers = <Future<void>>[];
    final subscription = server.listen((request) {
      handlers.add(() async {
        ranges.add(request.headers.value('range'));
        try {
          if (ranges.length == 1) {
            request.response.bufferOutput = false;
            request.response.contentLength = 4;
            request.response.headers.set('etag', '"v1"');
            request.response.add([1, 2]);
            await request.response.flush();
            // Stall the first response until client cancellation.
            await request.response.done;
          } else {
            expect(request.headers.value('range'), 'bytes=2-');
            expect(request.headers.value('if-range'), '"v1"');
            request.response.statusCode = 206;
            request.response.contentLength = 2;
            request.response.headers.set('content-range', 'bytes 2-3/4');
            request.response.add([3, 4]);
            await request.response.close();
          }
        } on IOException {
          // Expected when the client aborts the first response.
        }
      }());
    });
    try {
      final original = downloadCompressedDb(
          url: url,
          partialCache: cache,
          onChunk: () {
            if (!firstBytes.isCompleted) firstBytes.complete();
          });
      final assertion =
          expectLater(original, throwsA(isA<DbDownloadPausedException>()));
      await firstBytes.future.timeout(const Duration(seconds: 5));
      c.pause();
      await assertion.timeout(const Duration(seconds: 5));
      expect(await cache.load(url), [1, 2]);
      c.resume();
      expect(await downloadCompressedDb(url: url, partialCache: cache),
          [1, 2, 3, 4]);
      expect(ranges, [null, 'bytes=2-']);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      // Do not wait for HttpResponse.done on an intentionally unfinished
      // server response: socket cancellation has platform-specific timing.
    }
  });
}
