import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache.dart';

class _Cache extends MemoryDbPartialCache {
  _Cache(this.failure, {this.onRead = false, this.onDelete = false});
  final Object failure;
  final bool onRead, onDelete;
  int writes = 0;
  @override
  Future<Uint8List?> readRecord(String key) async {
    if (onRead) throw failure;
    return super.readRecord(key);
  }

  @override
  Future<void> writeRecord(String key, List<int> raw) async {
    writes++;
    throw failure;
  }

  @override
  Future<void> deleteRecord(String key) async {
    if (onDelete) throw StateError('cleanup failed');
  }
}

class _Client extends http.BaseClient {
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    return http.StreamedResponse(Stream.value(Uint8List(1024 * 1024)), 200,
        contentLength: 2 * 1024 * 1024);
  }
}

void main() {
  for (final space in [false, true]) {
    test('checkpoint storage failure space=$space never retries or masks cause',
        () async {
      final error = space
          ? DbInsufficientSpaceException(requiredBytes: 1024)
          : DbStorageException('storage denied', errorName: 'SecurityError');
      final cache = _Cache(error, onDelete: true);
      final client = _Client();
      final url = 'https://test/checkpoint-error/$space';
      await expectLater(
          downloadCompressedDb(
              url: url,
              partialCache: cache,
              clientFactory: () => client,
              backoff: Duration.zero),
          throwsA(same(error)));
      expect(client.calls, 1);
      expect(cache.writes, 1);
      expect(error.isNetwork, isFalse);
      expect(DbDownloadController.sharedFor(url).snapshot.status,
          DbDownloadStatus.failed);
    });
  }
  test('checkpoint read error is non-network and sends no request', () async {
    final error = DbStorageException('unavailable', errorName: 'UnknownError');
    final client = _Client();
    await expectLater(
        downloadCompressedDb(
            url: 'https://test/read-error',
            partialCache: _Cache(error, onRead: true),
            clientFactory: () => client,
            backoff: Duration.zero),
        throwsA(same(error)));
    expect(client.calls, 0);
  });
}
