// Platform-neutral partial download storage. Large byte payloads never use
// preferences. Native files and browser IndexedDB survive process restarts.
//
// One checkpoint is ONE record: the envelope carries the resume validator
// (ETag / Last-Modified) next to the bytes it belongs to, so a prefix can
// never be paired with a validator from a different write. Platforms only
// implement raw read/write/delete; the envelope and all integrity checks live
// here, once.
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'db_partial_cache_stub.dart'
    if (dart.library.io) 'db_partial_cache_io.dart'
    if (dart.library.js_interop) 'db_partial_cache_web.dart' as platform;

export 'db_partial_cache_stub.dart'
    if (dart.library.io) 'db_partial_cache_io.dart'
    if (dart.library.js_interop) 'db_partial_cache_web.dart';

final DbPartialCache defaultDbPartialCache = platform.createDbPartialCache();

/// A stored checkpoint: the contiguous prefix plus the validator that the
/// server gave for the entity those bytes came from.
class DbPartial {
  const DbPartial(this.bytes, this.validator);
  final Uint8List bytes;

  /// Null when the server exposed no usable validator, or when the validator
  /// did not fit the envelope. Resuming then cannot send `If-Range`, which
  /// callers compensate for with a stricter post-download check.
  final String? validator;
}

abstract class DbPartialCache {
  /// Raw record access. Implementations store and return the exact bytes they
  /// are given; they never inspect the envelope.
  Future<Uint8List?> readRecord(String key);
  Future<void> writeRecord(String key, List<int> raw);
  Future<void> deleteRecord(String key);

  String keyFor(String url) => sha256.convert(utf8.encode(url)).toString();

  /// The stored prefix, or null when nothing valid is cached.
  Future<Uint8List?> load(String url) async => (await loadRecord(url))?.bytes;

  /// Prefix and validator in a single read — one decode, one digest pass.
  Future<DbPartial?> loadRecord(String url) async {
    final raw = await readRecord(keyFor(url));
    return raw == null ? null : decodeDbPartial(raw);
  }

  Future<void> save(String url, List<int> bytes, {String? validator}) =>
      writeRecord(keyFor(url), encodeDbPartial(bytes, validator: validator));

  Future<void> clear(String url) => deleteRecord(keyFor(url));

  /// Writes prefix and validator together; there is no second record to tear.
  Future<void> saveCheckpoint(
          String url, List<int> bytes, String? validator) =>
      save(url, bytes, validator: validator);

  /// The validator stored with [bytes]. Null when nothing is cached, when the
  /// record was written without one, or when the cached prefix is no longer
  /// the one the caller is holding.
  Future<String?> loadValidator(String url, List<int> bytes) async {
    final record = await loadRecord(url);
    if (record == null || record.bytes.length != bytes.length) return null;
    return record.validator;
  }

  Future<void> clearCheckpoint(String url) => clear(url);

  /// How many bytes are checkpointed for [url], without verifying them — the
  /// header is enough to label "Resume — 12 of 25 MB", and hashing a 12 MB
  /// prefix to draw a caption would be absurd. Null when nothing is cached or
  /// the record is not a well-formed envelope.
  Future<int?> cachedLength(String url) async {
    final raw = await readRecord(keyFor(url));
    return raw == null ? null : peekDbPartialLength(raw);
  }
}

/// Test/in-memory fallback. Instances do not share entries.
class MemoryDbPartialCache extends DbPartialCache {
  final Map<String, Uint8List> _store = {};

  @override
  Future<Uint8List?> readRecord(String key) async {
    final bytes = _store[key];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeRecord(String key, List<int> raw) async {
    _store[key] = Uint8List.fromList(raw);
  }

  @override
  Future<void> deleteRecord(String key) async {
    _store.remove(key);
  }
}

// Envelope v2:
//   0  'D' 'P'                    magic
//   2  version (2)
//   3  validator length (bytes, 0-255)
//   4  payload length (uint32 LE)
//   8  sha256(payload)
//  40  validator (utf8)
//      payload
//
// The digest detects torn writes AND same-length corruption before a stored
// prefix is used; it protects storage, not upstream authenticity. A v1 record
// from an older build fails the magic check, so an in-flight download from a
// previous app version simply restarts instead of being misread.
const int _magic0 = 0x44; // 'D'
const int _magic1 = 0x50; // 'P'
const int _version = 2;
const int _headerBytes = 40;
const int _maxValidatorBytes = 255;

Uint8List encodeDbPartial(List<int> bytes, {String? validator}) {
  var validatorBytes = const <int>[];
  if (validator != null && validator.isNotEmpty) {
    final encoded = utf8.encode(validator);
    // Real ETags and HTTP dates are short. Anything longer is stored without a
    // validator rather than truncated into a value that would never match.
    if (encoded.length <= _maxValidatorBytes) validatorBytes = encoded;
  }
  final header = ByteData(_headerBytes)
    ..setUint8(0, _magic0)
    ..setUint8(1, _magic1)
    ..setUint8(2, _version)
    ..setUint8(3, validatorBytes.length)
    ..setUint32(4, bytes.length, Endian.little);
  final digest = sha256.convert(bytes).bytes;
  for (var i = 0; i < 32; i++) {
    header.setUint8(8 + i, digest[i]);
  }
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(validatorBytes)
        ..add(bytes))
      .takeBytes();
}

/// Payload length from the header alone: no digest pass. Returns null unless
/// the envelope is self-consistent (magic, version, declared lengths).
int? peekDbPartialLength(Uint8List bytes) {
  if (bytes.length < _headerBytes) return null;
  final header = ByteData.sublistView(bytes, 0, _headerBytes);
  if (header.getUint8(0) != _magic0 ||
      header.getUint8(1) != _magic1 ||
      header.getUint8(2) != _version) {
    return null;
  }
  final payloadLength = header.getUint32(4, Endian.little);
  if (bytes.length != _headerBytes + header.getUint8(3) + payloadLength) {
    return null;
  }
  return payloadLength;
}

DbPartial? decodeDbPartial(Uint8List bytes) {
  if (bytes.length < _headerBytes) return null;
  final header = ByteData.sublistView(bytes, 0, _headerBytes);
  if (header.getUint8(0) != _magic0 ||
      header.getUint8(1) != _magic1 ||
      header.getUint8(2) != _version) {
    return null;
  }
  final validatorLength = header.getUint8(3);
  final payloadLength = header.getUint32(4, Endian.little);
  if (bytes.length != _headerBytes + validatorLength + payloadLength) {
    return null;
  }
  final payload =
      Uint8List.sublistView(bytes, _headerBytes + validatorLength);
  final digest = sha256.convert(payload).bytes;
  for (var i = 0; i < 32; i++) {
    if (digest[i] != header.getUint8(8 + i)) return null;
  }
  if (validatorLength == 0) return DbPartial(payload, null);
  try {
    return DbPartial(
      payload,
      utf8.decode(
          Uint8List.sublistView(bytes, _headerBytes, _headerBytes + validatorLength)),
    );
  } catch (_) {
    // Corrupt validator text: the bytes are still verified, so resume without
    // If-Range rather than throwing the prefix away.
    return DbPartial(payload, null);
  }
}
