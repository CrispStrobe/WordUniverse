// lib/core/services/db_platform/db_remote.dart
//
// Shared remote-download + integrity helpers for the platform DB loaders
// (db_platform_mobile.dart / db_platform_web.dart).
//
// Why this exists: the German vocabulary database is GPL-3.0 (it includes
// data derived from childLex, GPL-3.0). Shipping a GPL blob inside an
// App Store binary collides with Apple's FairPlay DRM + per-device usage
// rules ("no further restrictions" / anti-Tivoization in GPL-3.0 §3/§6/§10 —
// the historic VLC-on-App-Store conflict). The clean fix is to NOT bundle
// the GPL DB in any store binary and instead fetch it on first launch from a
// GPL-compliant distribution point (the Hugging Face dataset), then cache it
// in the app's container. The English DB is CC-BY-SA-4.0 and stays bundled.
//
// Apple explicitly permits downloading *data* (not code) after install,
// provided the size is disclosed and the user is prompted (App Store Review
// Guidelines §2.5.2 vs §2.4.2/§4.2.3). A SQLite database is data.
//
// Integrity policy (see the loaders for where each gate runs):
//   HARD  received bytes == Content-Length (when the header is exposed)
//   HARD  received bytes == [expectedCompressedBytes] (works even when CORS
//         hides Content-Length, as Hugging Face does for browser fetches)
//   HARD  gzip decode succeeds — gzip's CRC-32 trailer validates the payload
//   HARD  word count > 0 after the DB opens (done in the loader)
//   SOFT  decompressed sha256 == [expectedDecompressedSha256] — logged on
//         mismatch but NOT fatal, so a legitimately updated remote DB still
//         loads (the hard gates already guarantee a structurally valid DB).

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Raised when the remote database cannot be fetched or fails an integrity
/// gate. [isNetwork] distinguishes "you're offline / the server hiccuped"
/// (retryable, user-actionable) from "the bytes were wrong" (corruption).
class DbDownloadException implements Exception {
  final String message;
  final bool isNetwork;
  DbDownloadException(this.message, {this.isNetwork = false});
  @override
  String toString() => message;
}

const Duration _attemptTimeout = Duration(seconds: 120);

/// Downloads the gzipped database at [url] with progress, bounded retries and
/// a compressed-size integrity check. Returns the compressed bytes; the caller
/// decompresses (gzip CRC-32 then validates the payload). Throws
/// [DbDownloadException] after the final attempt fails.
Future<Uint8List> downloadCompressedDb({
  required String url,
  int? expectedCompressedBytes,
  int maxAttempts = 3,
  void Function(double progress, String message)? onProgress,
}) async {
  DbDownloadException? lastError;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      onProgress?.call(
        0.0,
        attempt == 1
            ? 'Downloading German word database…'
            : 'Retrying download (attempt $attempt of $maxAttempts)…',
      );
      return await _attemptDownload(
        url,
        expectedCompressedBytes,
        onProgress,
      ).timeout(_attemptTimeout);
    } on TimeoutException {
      lastError = DbDownloadException(
        'The download timed out. Check your connection and try again.',
        isNetwork: true,
      );
    } on DbDownloadException catch (e) {
      lastError = e;
    } catch (e) {
      lastError = DbDownloadException(
        'Could not download the word database: $e',
        isNetwork: true,
      );
    }

    if (kDebugMode) {
      debugPrint('[DB_REMOTE] ⚠️ attempt $attempt/$maxAttempts failed: '
          '${lastError.message}');
    }
    if (attempt < maxAttempts) {
      // Exponential backoff: 1s, 2s, 4s…
      await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
    }
  }

  throw lastError ??
      DbDownloadException('Could not download the word database.',
          isNetwork: true);
}

Future<Uint8List> _attemptDownload(
  String url,
  int? expectedCompressedBytes,
  void Function(double progress, String message)? onProgress,
) async {
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(url)));

    if (response.statusCode != 200) {
      throw DbDownloadException(
        'The server returned HTTP ${response.statusCode} for the database.',
        // 5xx and 429 are transient → worth a retry; 4xx usually isn't.
        isNetwork: response.statusCode >= 500 || response.statusCode == 429,
      );
    }

    // Content-Length is often hidden from browsers by CORS (Hugging Face does
    // not expose it), so fall back to the pinned size for the progress total.
    final int? declared = response.contentLength ?? expectedCompressedBytes;
    final builder = BytesBuilder(copy: false);
    var received = 0;

    await for (final chunk in response.stream) {
      builder.add(chunk);
      received += chunk.length;
      if (declared != null && declared > 0) {
        onProgress?.call(
          (received / declared).clamp(0.0, 1.0),
          'Downloading… ${_mb(received)} / ${_mb(declared)} MB',
        );
      } else {
        onProgress?.call(0.5, 'Downloading… ${_mb(received)} MB');
      }
    }

    final bytes = builder.toBytes();

    // HARD: if the server told us a length, every byte must have arrived.
    final contentLength = response.contentLength;
    if (contentLength != null && bytes.length != contentLength) {
      throw DbDownloadException(
        'The download was incomplete (${bytes.length} of $contentLength bytes).',
        isNetwork: true,
      );
    }
    // HARD: pinned compressed size (catches truncation even when CORS hid
    // Content-Length, and catches a wrong/replaced file early).
    if (expectedCompressedBytes != null &&
        bytes.length != expectedCompressedBytes) {
      throw DbDownloadException(
        'The downloaded database has an unexpected size '
        '(${bytes.length} bytes, expected $expectedCompressedBytes). '
        'It may be incomplete or out of date.',
        isNetwork: false,
      );
    }

    onProgress?.call(1.0, 'Download complete (${_mb(bytes.length)} MB)');
    return bytes;
  } finally {
    client.close();
  }
}

/// SOFT integrity gate over the *decompressed* database bytes. Logs a warning
/// on mismatch but does not throw — the hard gates (size + gzip CRC + word
/// count) already guarantee a structurally valid DB, so a legitimately updated
/// remote DB whose pin wasn't bumped still loads instead of bricking.
///
/// [expectedDecompressedBytes], when given, IS enforced as a hard size check.
void verifyDecompressedDb(
  List<int> bytes, {
  int? expectedDecompressedBytes,
  String? expectedDecompressedSha256,
}) {
  if (expectedDecompressedBytes != null &&
      bytes.length != expectedDecompressedBytes) {
    throw DbDownloadException(
      'The database failed validation after decompression '
      '(${bytes.length} bytes, expected $expectedDecompressedBytes).',
      isNetwork: false,
    );
  }
  if (expectedDecompressedSha256 != null) {
    final actual = sha256.convert(bytes).toString();
    if (actual.toLowerCase() != expectedDecompressedSha256.toLowerCase()) {
      if (kDebugMode) {
        debugPrint('[DB_REMOTE] ⚠️ decompressed sha256 mismatch — '
            'expected $expectedDecompressedSha256, got $actual. '
            'Proceeding (structural checks passed); update the pin if the '
            'remote DB was intentionally rebuilt.');
      }
    }
  }
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
