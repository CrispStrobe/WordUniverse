import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/services/db_platform/db_gzip.dart';

void main() {
  final original = List<int>.generate(3000, (i) => i % 251);
  test('valid gzip passes hard CRC and size checks', () {
    expect(decodeDbGzip(Uint8List.fromList(GZipEncoder().encode(original))),
        original);
  });
  test('bad CRC is refused even when compressed size matches', () {
    final bytes = Uint8List.fromList(GZipEncoder().encode(original));
    bytes[bytes.length - 8] ^= 1;
    expect(() => decodeDbGzip(bytes), throwsA(anything));
  });
  test('truncated trailer is refused', () {
    final bytes = Uint8List.fromList(GZipEncoder().encode(original));
    expect(
        () => decodeDbGzip(Uint8List.sublistView(bytes, 0, bytes.length - 3)),
        throwsA(anything));
  });

  group('payload gates', () {
    final compressed = Uint8List.fromList(GZipEncoder().encode(original));
    const digest =
        'ce2f4c1b3f8bd4f8b49e08d0f5cdf1e5f9a8a2ad7a0e5c9ee6b1f0f6b0c6bd11';

    test('decodeAndVerifyDbGzip returns the payload when gates pass', () {
      expect(
        decodeAndVerifyDbGzip(DbGzipJob(
          compressed: compressed,
          expectedDecompressedBytes: original.length,
        )),
        original,
      );
    });

    test('a decompressed-size mismatch is always fatal', () {
      expect(
        () => decodeAndVerifyDbGzip(DbGzipJob(
          compressed: compressed,
          expectedDecompressedBytes: original.length + 1,
        )),
        throwsA(isA<DbPayloadException>()),
      );
    });

    test('an enforced checksum mismatch is fatal, so an unvalidated resume '
        'cannot install spliced bytes', () {
      expect(
        () => decodeAndVerifyDbGzip(DbGzipJob(
          compressed: compressed,
          expectedDecompressedSha256: digest,
          requireSha256: true,
        )),
        throwsA(isA<DbPayloadException>()),
      );
    });

    test('a wrong checksum stays advisory when it is not enforced, so a stale '
        'pin never bricks an install', () {
      expect(
        decodeAndVerifyDbGzip(DbGzipJob(
          compressed: compressed,
          expectedDecompressedSha256: digest,
        )),
        original,
      );
    });
  });
}