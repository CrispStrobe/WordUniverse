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
}
