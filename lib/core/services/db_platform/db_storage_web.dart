import 'dart:js_interop';

@JS('navigator')
external _Navigator get _navigator;

extension type _Navigator(JSObject _) implements JSObject {
  external _StorageManager? get storage;
}

extension type _StorageManager(JSObject _) implements JSObject {
  external JSPromise<_Estimate> estimate();
}

extension type _Estimate(JSObject _) implements JSObject {
  external int? get quota;
  external int? get usage;
}

/// Browsers publish a storage quota, so the download can be refused before it
/// starts rather than failing 150 MB into writing IndexedDB. Returns null when
/// the API is unavailable or throws (private modes, older engines).
Future<int?> availableStorageBytes() async {
  try {
    final storage = _navigator.storage;
    if (storage == null) return null;
    final estimate = await storage.estimate().toDart;
    final quota = estimate.quota;
    if (quota == null) return null;
    final remaining = quota - (estimate.usage ?? 0);
    return remaining < 0 ? 0 : remaining;
  } catch (_) {
    return null;
  }
}
