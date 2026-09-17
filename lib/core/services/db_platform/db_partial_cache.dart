// Platform-neutral partial download storage. Large byte payloads never use
// preferences. Native files and browser IndexedDB survive process restarts.
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

abstract class DbPartialCache {
  Future<Uint8List?> load(String url);
  Future<void> save(String url, List<int> bytes);
  Future<void> clear(String url);
  String keyFor(String url) => sha256.convert(utf8.encode(url)).toString();

  // Metadata is small, but lives in the same storage rather than preferences.
  // Binding it to the prefix digest makes a torn two-record write fail closed.
  String _metadataKey(String url) => '$url\u0000validator';
  Future<void> saveCheckpoint(
      String url, List<int> bytes, String? validator) async {
    await save(url, bytes);
    await save(
        _metadataKey(url),
        utf8.encode(jsonEncode({
          'digest': sha256.convert(bytes).toString(),
          'validator': validator,
        })));
  }

  Future<String?> loadValidator(String url, List<int> bytes) async {
    final data = await load(_metadataKey(url));
    if (data == null) return null;
    try {
      final value = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      if (value['digest'] != sha256.convert(bytes).toString()) return null;
      return value['validator'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCheckpoint(String url) async {
    await clear(url);
    await clear(_metadataKey(url));
  }
}

/// Test/in-memory fallback. Instances do not share entries.
class MemoryDbPartialCache extends DbPartialCache {
  final Map<String, Uint8List> _store = {};
  @override
  Future<Uint8List?> load(String url) async {
    final bytes = _store[keyFor(url)];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> save(String url, List<int> bytes) async {
    _store[keyFor(url)] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> clear(String url) async {
    _store.remove(keyFor(url));
  }
}

/// Envelope detects torn writes AND same-length cache corruption before using
/// a stored prefix. This digest protects storage, not upstream authenticity.
Uint8List encodeDbPartial(List<int> bytes) {
  final header = ByteData(4)..setUint32(0, bytes.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(sha256.convert(bytes).bytes)
        ..add(bytes))
      .takeBytes();
}

Uint8List? decodeDbPartial(Uint8List bytes) {
  if (bytes.length < 36) return null;
  final length = ByteData.sublistView(bytes).getUint32(0, Endian.little);
  if (length != bytes.length - 36) return null;
  final payload = Uint8List.sublistView(bytes, 36);
  final digest = sha256.convert(payload).bytes;
  for (var i = 0; i < 32; i++) {
    if (digest[i] != bytes[i + 4]) return null;
  }
  return payload;
}
