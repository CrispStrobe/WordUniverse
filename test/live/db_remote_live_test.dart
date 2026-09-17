// Live transport test: the real published pack, the real disk cache, the real
// resume path. The offline suite covers the transport with fake clients; this
// is the run that proves the pieces those fakes stand in for — Hugging Face
// honouring Range/If-Range, the on-disk checkpoint envelope surviving a real
// pause, and the published bytes matching the registry pins.
//
// Skipped unless WU_LIVE=1. Add WU_LIVE_DECOMPRESS=1 to also decompress the
// ~150 MB database and enforce its digest (slower, memory-hungry).

@Tags(['live'])
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:WortUniversum/core/services/db_platform/db_gzip.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache_io.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';

void main() {
  final live = Platform.environment['WU_LIVE'] == '1';
  final skip = live ? null : 'set WU_LIVE=1 to run live network checks';
  final pack = kLanguagePacks['de']!;

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wu_live_download');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('a paused download resumes from disk and still matches its pins',
      () async {
    final cache = FileDbPartialCache(baseDirectory: tmp);
    var paused = false;
    var received = 0;

    // First attempt: stop a little way in, the way a user backgrounding the
    // app or losing signal would.
    await expectLater(
      downloadCompressedDb(
        url: pack.remoteUrl!,
        expectedCompressedBytes: pack.expectedCompressedBytes,
        partialCache: cache,
        onProgress: (_, status) => received = status.bytes,
        isPaused: () => paused,
        onChunk: () {
          if (received > 1024 * 1024) paused = true;
        },
      ),
      throwsA(isA<DbDownloadPausedException>()),
    );

    final checkpoint = await cache.loadRecord(pack.remoteUrl!);
    expect(checkpoint, isNotNull,
        reason: 'a real pause must leave a usable prefix on disk');
    expect(checkpoint!.bytes, isNotEmpty);
    expect(checkpoint.bytes.length,
        lessThan(pack.expectedCompressedBytes!));
    expect(checkpoint.validator, isNotNull,
        reason: 'Hugging Face publishes an ETag, so the resume can send '
            'If-Range and the checksum stays advisory');

    // Resume: the transport must ask for the remaining bytes, not start over.
    paused = false;
    final bytes = await downloadCompressedDb(
      url: pack.remoteUrl!,
      expectedCompressedBytes: pack.expectedCompressedBytes,
      partialCache: cache,
    );

    expect(bytes.length, pack.expectedCompressedBytes);
    if (pack.expectedCompressedSha256 != null) {
      expect(sha256.convert(bytes).toString(), pack.expectedCompressedSha256,
          reason: 'resumed bytes must reassemble the published artifact '
              'exactly — a bad prefix would corrupt the database');
    }
    expect(await cache.load(pack.remoteUrl!), isNull,
        reason: 'a completed download leaves no checkpoint behind');
    expect(
        DbDownloadController.sharedFor(pack.remoteUrl!)
            .resumedWithoutValidator,
        isFalse,
        reason: 'the resume was validated, so the digest stays advisory');
  }, timeout: const Timeout(Duration(minutes: 10)), skip: skip);

  test('the published database passes every payload gate', () async {
    final bytes = await downloadCompressedDb(
      url: pack.remoteUrl!,
      expectedCompressedBytes: pack.expectedCompressedBytes,
      partialCache: FileDbPartialCache(baseDirectory: tmp),
    );
    // Enforced, not advisory: this asserts the registry digest is still right.
    final database = decodeAndVerifyDbGzip(DbGzipJob(
      compressed: bytes,
      expectedDecompressedBytes: pack.expectedDecompressedBytes,
      expectedDecompressedSha256: pack.expectedDecompressedSha256,
      requireSha256: true,
    ));
    expect(database.length, pack.expectedDecompressedBytes);
  },
      timeout: const Timeout(Duration(minutes: 15)),
      skip: live && Platform.environment['WU_LIVE_DECOMPRESS'] == '1'
          ? null
          : 'set WU_LIVE=1 WU_LIVE_DECOMPRESS=1 (downloads and decompresses '
              '~180 MB)');
}
