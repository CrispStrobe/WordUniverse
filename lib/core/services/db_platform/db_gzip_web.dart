// lib/core/services/db_platform/db_gzip_web.dart
//
// Decompression and hashing through the browser's own primitives.
//
// The portable path in db_gzip.dart is pure Dart, and `compute()` — which
// gives native platforms a real isolate — is only a microtask on the web, so
// all of it ran on the main thread. Measured in Chromium on the 18 MB English
// pack (93 MB decompressed):
//
//   gunzip  package:archive   60,556 ms     DecompressionStream     1,717 ms
//   sha256  package:crypto   190,095 ms     crypto.subtle             624 ms
//
// The German pack is 157 MB and pins a digest that is enforced, so it paid
// both. Everything here is a browser built-in running off the Dart heap; the
// gates, their order and their messages stay in db_gzip.dart so the two paths
// cannot drift.
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'db_digest_web.dart';
import 'db_gzip.dart';

@JS('DecompressionStream')
external JSFunction? get _decompressionStreamConstructor;

@JS('DecompressionStream')
extension type _DecompressionStream._(JSObject _) implements JSObject {
  external factory _DecompressionStream(String format);
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts);
  external JSObject stream();
}

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response(JSAny? body);
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension on JSObject {
  external JSObject pipeThrough(JSObject transform);
}

/// Whether this browser can decompress natively.
///
/// Chrome 80+, Firefox 113+, Safari 16.4+. Anything older falls back to the
/// portable path rather than failing the install.
bool get supportsNativeGzip => _decompressionStreamConstructor != null;

/// Decompresses [job] and applies exactly the gates [verifyDecompressedDb]
/// applies, using the browser's gzip and SHA-256.
///
/// Throws the same [FormatException] and [DbPayloadException] the portable
/// path throws, so callers cannot tell which one ran.
Future<Uint8List> decodeAndVerifyDbGzipNative(DbGzipJob job) async {
  final compressed = job.compressed;
  // Same structural header check as decodeDbGzip: a truncated or non-gzip
  // payload should fail here, not inside the browser's stream machinery.
  if (compressed.length < 18 ||
      compressed[0] != 0x1f ||
      compressed[1] != 0x8b ||
      compressed[2] != 8) {
    throw const FormatException('Invalid gzip database header');
  }

  final JSArrayBuffer buffer;
  try {
    final blob = _Blob([compressed.toJS].toJS);
    final stream = blob
        .stream()
        .pipeThrough(_DecompressionStream('gzip') as JSObject);
    buffer = await _Response(stream).arrayBuffer().toDart;
  } catch (error) {
    // DecompressionStream validates the gzip CRC-32 and rejects a truncated
    // member, so a failure here is the same condition the portable path
    // reports from its own trailer check.
    throw FormatException('Database gzip checksum or size mismatch ($error)');
  }
  final decoded = buffer.toDart.asUint8List();

  // ISIZE from the trailer, which the stream does not hand back. O(1), and it
  // catches a member whose declared length disagrees with what came out.
  final trailer = ByteData.sublistView(compressed, compressed.length - 8);
  if (trailer.getUint32(4, Endian.little) != decoded.length % 0x100000000) {
    throw const FormatException('Database gzip checksum or size mismatch');
  }

  verifyDecompressedSize(decoded.length, job.expectedDecompressedBytes);
  if (!shouldVerifySha256(
    expectedDecompressedSha256: job.expectedDecompressedSha256,
    requireSha256: job.requireSha256,
  )) {
    return decoded;
  }

  if (!supportsNativeDigest) {
    // Hashing ~150 MB in Dart on the main thread is minutes; the portable
    // path is the right place for that, not here.
    throw const _NativeDigestUnavailable();
  }
  verifySha256Digest(
    actual: await nativeSha256Hex(buffer),
    expected: job.expectedDecompressedSha256!,
    requireSha256: job.requireSha256,
  );
  return decoded;
}

/// Raised internally when the digest is required but unavailable, so the
/// caller falls back to the portable path instead of skipping a gate.
class _NativeDigestUnavailable implements Exception {
  const _NativeDigestUnavailable();
}

/// True when [error] means "this browser cannot finish natively", as opposed
/// to "this payload is bad".
bool isNativeGzipUnavailable(Object error) => error is _NativeDigestUnavailable;

/// Logs which path ran, once per install, so a slow install can be explained.
void logGzipPath(String path, int milliseconds, int bytes) {
  if (!kDebugMode) return;
  debugPrint('[DB_GZIP] $path: ${(bytes / 1048576).toStringAsFixed(1)} MB '
      'in $milliseconds ms');
}
