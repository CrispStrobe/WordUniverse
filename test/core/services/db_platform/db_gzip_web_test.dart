@TestOn('browser')
library;

// The browser-native decompression path must be indistinguishable from the
// portable Dart one: same bytes out, same exceptions, same gates in the same
// order. Only the speed differs (db_gzip_web.dart has the measurements).

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'web_fixture_guard.dart';

import 'package:WortUniversum/core/services/db_platform/db_digest_web.dart';
import 'package:WortUniversum/core/services/db_platform/db_gzip.dart';
import 'package:WortUniversum/core/services/db_platform/db_gzip_web.dart';
import 'package:WortUniversum/core/services/db_platform/db_revision.dart';

void main() {
  setUpAll(assertWebFixturesServed);

  final payload =
      Uint8List.fromList(utf8.encode('word universe ' * 5000));
  final gz = Uint8List.fromList(GZipEncoder().encode(payload));
  final digest = sha256.convert(payload).toString();

  test('this browser has the native primitives', () {
    expect(supportsNativeGzip, isTrue,
        reason: 'DecompressionStream is required for the fast path');
    expect(supportsNativeDigest, isTrue,
        reason: 'crypto.subtle needs a secure context');
  });

  test('produces the same bytes as the portable path', () async {
    final native = await decodeAndVerifyDbGzipNative(DbGzipJob(compressed: gz));
    expect(native, payload);
    expect(native, decodeDbGzip(gz));
  });

  test('applies the size gate', () async {
    await expectLater(
      decodeAndVerifyDbGzipNative(
          DbGzipJob(compressed: gz, expectedDecompressedBytes: 12)),
      throwsA(isA<DbPayloadException>()),
    );
    // The matching size passes.
    await decodeAndVerifyDbGzipNative(
        DbGzipJob(compressed: gz, expectedDecompressedBytes: payload.length));
  });

  test('enforces a pinned digest when it is required', () async {
    await decodeAndVerifyDbGzipNative(DbGzipJob(
      compressed: gz,
      expectedDecompressedSha256: digest,
      requireSha256: true,
    ));

    await expectLater(
      decodeAndVerifyDbGzipNative(DbGzipJob(
        compressed: gz,
        expectedDecompressedSha256: 'f' * 64,
        requireSha256: true,
      )),
      throwsA(isA<DbPayloadException>()),
    );
  });

  test('a mismatched digest stays advisory when it is not required', () async {
    // Outside debug mode the digest is not even computed; in a debug test run
    // it is, and must not throw. Either way the bytes come back.
    final bytes = await decodeAndVerifyDbGzipNative(DbGzipJob(
      compressed: gz,
      expectedDecompressedSha256: 'f' * 64,
    ));
    expect(bytes, payload);
  });

  test('rejects a payload that is not gzip', () async {
    await expectLater(
      decodeAndVerifyDbGzipNative(
          DbGzipJob(compressed: Uint8List.fromList(List.filled(32, 7)))),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a truncated member', () async {
    await expectLater(
      decodeAndVerifyDbGzipNative(
          DbGzipJob(compressed: gz.sublist(0, gz.length ~/ 2))),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a corrupted body', () async {
    final corrupted = Uint8List.fromList(gz);
    corrupted[corrupted.length ~/ 2] ^= 0xff;
    await expectLater(
      decodeAndVerifyDbGzipNative(DbGzipJob(compressed: corrupted)),
      throwsA(isA<FormatException>()),
      reason: 'the gzip CRC-32 has to be checked, natively or not',
    );
  });

  test('rejects a trailer that disagrees with the output', () async {
    final tampered = Uint8List.fromList(gz);
    // ISIZE is the last four bytes; claim a different length.
    tampered[tampered.length - 4] ^= 0x01;
    await expectLater(
      decodeAndVerifyDbGzipNative(DbGzipJob(compressed: tampered)),
      throwsA(isA<FormatException>()),
    );
  });

  test('the native digest agrees with package:crypto', () async {
    // Legacy adoption compares a whole installed database against the pinned
    // digest; the two implementations have to produce the same string or an
    // upgrade silently stops adopting anything.
    expect(await nativeSha256HexOfBytes(payload), databaseDigest(payload));
    expect(await nativeSha256HexOfBytes(Uint8List(0)), databaseDigest(Uint8List(0)));
  });
}
