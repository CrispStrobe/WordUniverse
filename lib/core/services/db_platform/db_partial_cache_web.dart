// Durable browser checkpoints in IndexedDB, never localStorage/preferences.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'db_partial_cache.dart';

@JS('indexedDB')
external _Factory get _indexedDB;
extension type _Factory(JSObject _) implements JSObject {
  external _OpenRequest open(String name, int version);
}
extension type _Request(JSObject _) implements JSObject {
  external JSAny? get result;
  external set onsuccess(JSFunction callback);
  external set onerror(JSFunction callback);
}
extension type _OpenRequest(JSObject _) implements _Request {
  external set onupgradeneeded(JSFunction callback);
}
extension type _Database(JSObject _) implements JSObject {
  external JSObject createObjectStore(String name);
  external _Transaction transaction(String name, String mode);
}
extension type _Transaction(JSObject _) implements JSObject {
  external _Store objectStore(String name);
  external set oncomplete(JSFunction callback);
  external set onabort(JSFunction callback);
  external set onerror(JSFunction callback);
}
extension type _Store(JSObject _) implements JSObject {
  @JS('get')
  external _Request read(String key);
  external _Request put(JSAny value, String key);
  external _Request delete(String key);
}

DbPartialCache createDbPartialCache() => IndexedDbPartialCache();

class IndexedDbPartialCache extends DbPartialCache {
  Future<_Database>? _database;
  Future<_Database> _open() => _database ??= () {
        final done = Completer<_Database>();
        final request = _indexedDB.open('worduniverse-downloads', 1);
        request.onupgradeneeded = (() {
          _Database(request.result as JSObject).createObjectStore('partials');
        }).toJS;
        request.onsuccess = (() {
          done.complete(_Database(request.result as JSObject));
        }).toJS;
        request.onerror = (() {
          _database = null;
          done.completeError(
              StateError('Browser download storage unavailable'));
        }).toJS;
        return done.future;
      }();

  Future<JSAny?> _run(String mode, _Request Function(_Store) operation) async {
    final db = await _open();
    final done = Completer<JSAny?>();
    final tx = db.transaction('partials', mode);
    JSAny? result;
    void fail() {
      if (!done.isCompleted)
        done.completeError(
            StateError('Browser download storage transaction failed'));
    }

    tx.onabort = fail.toJS;
    tx.onerror = fail.toJS;
    tx.oncomplete = (() {
      if (!done.isCompleted) done.complete(result);
    }).toJS;
    final request = operation(tx.objectStore('partials'));
    request.onsuccess = (() {
      result = request.result;
    }).toJS;
    request.onerror = fail.toJS;
    return done.future;
  }

  @override
  Future<Uint8List?> readRecord(String key) async {
    final value = await _run('readonly', (store) => store.read(key));
    return value == null ? null : (value as JSUint8Array).toDart;
  }

  @override
  Future<void> writeRecord(String key, List<int> raw) async {
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    await _run('readwrite', (store) => store.put(bytes.toJS, key));
  }

  @override
  Future<void> deleteRecord(String key) async {
    await _run('readwrite', (store) => store.delete(key));
  }
}
