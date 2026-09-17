// Durable browser checkpoints in IndexedDB, never localStorage/preferences.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'db_partial_cache.dart';
import 'db_download_exception.dart';

@JS('indexedDB')
external _Factory get _indexedDB;
extension type _Factory(JSObject _) implements JSObject {
  external _OpenRequest open(String name, int version);
}
extension type _DomError(JSObject _) implements JSObject {
  external String? get name;
}
extension type _Request(JSObject _) implements JSObject {
  external JSAny? get result;
  external _DomError? get error;
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
  external _DomError? get error;
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

DbStorageException _storageError(Object? error) {
  if (error is DbStorageException) return error;
  String? name;
  if (error != null) {
    try {
      name = _DomError(error as JSObject).name;
    } catch (_) {}
  }
  return name == 'QuotaExceededError'
      ? DbInsufficientSpaceException(errorName: name, cause: error)
      : DbStorageException('Browser download storage failed.',
          errorName: name, cause: error);
}

DbPartialCache createDbPartialCache() => IndexedDbPartialCache();

class IndexedDbPartialCache extends DbPartialCache {
  /// Optional factory permits deterministic DOM failures without exhausting quota.
  IndexedDbPartialCache({JSObject? factory})
      : _factory = factory == null ? _indexedDB : _Factory(factory);
  final _Factory _factory;
  Future<_Database>? _database;
  Future<_Database> _open() => _database ??= () {
        final done = Completer<_Database>();
        final request = _factory.open('worduniverse-downloads', 1);
        request.onupgradeneeded = (() {
          _Database(request.result as JSObject).createObjectStore('partials');
        }).toJS;
        request.onsuccess = (() {
          done.complete(_Database(request.result as JSObject));
        }).toJS;
        request.onerror = (() {
          _database = null;
          done.completeError(_storageError(request.error));
        }).toJS;
        return done.future;
      }();

  Future<JSAny?> _run(String mode, _Request Function(_Store) operation) async {
    try {
      final db = await _open();
      final done = Completer<JSAny?>();
      final tx = db.transaction('partials', mode);
      JSAny? result;
      _Request? request;
      void fail() {
        if (!done.isCompleted) {
          // Request errors bubble before the transaction error is populated.
          done.completeError(_storageError(request?.error ?? tx.error));
        }
      }

      tx.onabort = fail.toJS;
      tx.onerror = fail.toJS;
      tx.oncomplete = (() {
        if (!done.isCompleted) done.complete(result);
      }).toJS;
      request = operation(tx.objectStore('partials'));
      request.onsuccess = (() {
        result = request!.result;
      }).toJS;
      request.onerror = fail.toJS;
      return await done.future;
    } catch (error, stack) {
      Error.throwWithStackTrace(_storageError(error), stack);
    }
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
