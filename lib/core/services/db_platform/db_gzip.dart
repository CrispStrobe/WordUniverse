import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Raised when a decompressed database fails a payload gate. Platform loaders
/// translate it into a user-facing download error.
class DbPayloadException implements Exception {
  DbPayloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

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

/// Everything the decompression isolate needs, so decode AND verification both
/// run off the UI thread. Plain data: safe to send through [compute].
@immutable
class DbGzipJob {
  const DbGzipJob({
    required this.compressed,
    this.expectedDecompressedBytes,
    this.expectedDecompressedSha256,
    this.requireSha256 = false,
  });
  final Uint8List compressed;
  final int? expectedDecompressedBytes;
  final String? expectedDecompressedSha256;

  /// Promotes the SHA-256 pin from advisory to enforced. Set when the bytes
  /// were resumed from a cached prefix that carried no HTTP validator, where
  /// the digest is the only thing that can catch a prefix spliced onto a
  /// different revision of the file.
  final bool requireSha256;
}

/// Decompresses and gates in one isolate hop. Top-level for [compute].
List<int> decodeAndVerifyDbGzip(DbGzipJob job) {
  final decoded = decodeDbGzip(job.compressed);
  verifyDecompressedDb(
    decoded,
    expectedDecompressedBytes: job.expectedDecompressedBytes,
    expectedDecompressedSha256: job.expectedDecompressedSha256,
    requireSha256: job.requireSha256,
  );
  return decoded;
}

/// Decompressed size is a hard gate. SHA-256 keeps the soft policy by default
/// so an intentional upstream update with a stale pin does not brick the app —
/// the digest is only computed when it can change the outcome, since hashing
/// ~150 MB is not free.
void verifyDecompressedDb(
  List<int> bytes, {
  int? expectedDecompressedBytes,
  String? expectedDecompressedSha256,
  bool requireSha256 = false,
}) {
  verifyDecompressedSize(bytes.length, expectedDecompressedBytes);
  if (!shouldVerifySha256(
    expectedDecompressedSha256: expectedDecompressedSha256,
    requireSha256: requireSha256,
  )) {
    return;
  }
  verifySha256Digest(
    actual: sha256.convert(bytes).toString(),
    expected: expectedDecompressedSha256!,
    requireSha256: requireSha256,
  );
}

/// The size gate, split out so a platform that computes the digest by other
/// means (the browser's crypto.subtle) still applies the same rules in the
/// same order. See [verifyDecompressedDb].
void verifyDecompressedSize(int actualBytes, int? expectedDecompressedBytes) {
  if (expectedDecompressedBytes != null &&
      actualBytes != expectedDecompressedBytes) {
    throw DbPayloadException(
        'The database failed validation after decompression '
        '($actualBytes bytes, expected $expectedDecompressedBytes).');
  }
}

/// Whether the digest can change the outcome, and is therefore worth computing.
bool shouldVerifySha256({
  required String? expectedDecompressedSha256,
  required bool requireSha256,
}) =>
    expectedDecompressedSha256 != null && (requireSha256 || kDebugMode);

/// The digest verdict: enforced when [requireSha256], advisory otherwise.
void verifySha256Digest({
  required String actual,
  required String expected,
  required bool requireSha256,
}) {
  if (actual.toLowerCase() == expected.toLowerCase()) return;
  if (requireSha256) {
    throw DbPayloadException(
        'The downloaded database did not match its published checksum. '
        'The partial download was discarded; please try again.');
  }
  debugPrint('[DB_GZIP] decompressed sha256 mismatch — expected '
      '$expected, got $actual. Proceeding (structural checks passed).');
}
