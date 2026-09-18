// lib/core/services/db_platform/db_digest_web.dart
//
// SHA-256 through the browser instead of through Dart.
//
// package:crypto is pure Dart, and on the web it runs on the main thread:
// measured in Chromium, hashing the 93.9 MB English database took 190,095 ms
// against 624 ms for crypto.subtle — the same work, 300x apart. The German
// database is 157 MB.
//
// Two callers need it: the decompression gate (db_gzip_web.dart) and legacy
// adoption, which hashes a whole installed database to decide whether it is
// the artifact the registry pins.
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('crypto')
external _Crypto? get _crypto;

extension type _Crypto(JSObject _) implements JSObject {
  external _SubtleCrypto? get subtle;
}

extension type _SubtleCrypto(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> digest(String algorithm, JSAny data);
}

/// Whether this browser can hash natively.
///
/// `crypto.subtle` exists only in a secure context, so an http:// origin has
/// to fall back to the Dart implementation.
bool get supportsNativeDigest => _crypto?.subtle != null;

/// Lowercase hex SHA-256 of [data], computed by the browser.
///
/// Only call when [supportsNativeDigest]; it throws otherwise.
Future<String> nativeSha256Hex(JSAny data) async {
  final digest = await _crypto!.subtle!.digest('SHA-256', data).toDart;
  final bytes = digest.toDart.asUint8List();
  final hex = StringBuffer();
  for (final byte in bytes) {
    hex.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return hex.toString();
}

/// [nativeSha256Hex] for bytes the caller holds as Dart.
Future<String> nativeSha256HexOfBytes(Uint8List bytes) =>
    nativeSha256Hex(bytes.toJS);
