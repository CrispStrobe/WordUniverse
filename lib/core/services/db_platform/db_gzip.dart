import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Explicit trailer checks are required: archive's decodeBytes defaults to
/// verify:false, and some implementations return partial output on truncation.
/// Kept top-level so platform loaders can run this through compute().
List<int> decodeDbGzip(Uint8List bytes) {
  if (bytes.length < 18 ||
      bytes[0] != 0x1f ||
      bytes[1] != 0x8b ||
      bytes[2] != 8) {
    throw const FormatException('Invalid gzip database header');
  }
  final decoded = GZipDecoder().decodeBytes(bytes, verify: true);
  final trailer = ByteData.sublistView(bytes, bytes.length - 8);
  if (trailer.getUint32(0, Endian.little) != getCrc32(decoded) ||
      trailer.getUint32(4, Endian.little) != decoded.length % 0x100000000) {
    throw const FormatException('Database gzip checksum or size mismatch');
  }
  return decoded;
}
