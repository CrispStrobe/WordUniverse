// Shared resumable transport for the platform vocabulary database loaders.
// The GPL German database is downloaded as data, not bundled in App Store
// binaries (FairPlay's additional restrictions conflict with GPL-3.0).
// Compressed length is a hard gate; loaders also validate gzip and DB content.
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'db_partial_cache.dart';

export 'db_partial_cache.dart' show DbPartialCache;

class DbDownloadException implements Exception {
  final String message;
  final bool isNetwork;
  DbDownloadException(this.message, {this.isNetwork = false});
  @override
  String toString() => message;
}

/// Pause is not a failure. Await the original install settling, call resume(),
/// then re-enter the normal installation flow to continue from cached bytes.
class DbDownloadPausedException extends DbDownloadException {
  DbDownloadPausedException() : super('Download paused.', isNetwork: true);
}

enum DbDownloadStatus { idle, downloading, paused, completed, failed }

@immutable
class DbDownloadSnapshot {
  const DbDownloadSnapshot({
    this.status = DbDownloadStatus.idle,
    this.received = 0,
    this.total,
    this.message = '',
    this.error,
  });
  final DbDownloadStatus status;
  final int received;
  final int? total;
  final String message;
  final Object? error;
  double? get progress =>
      total == null || total! <= 0 ? null : (received / total!).clamp(0.0, 1.0);
}

/// Shared per URL, including downloads started through the legacy function.
/// Subscribe with addListener/removeListener; do not dispose shared instances.
/// Concurrent callers share a transfer, but each receives its own progress.
class DbDownloadController extends ChangeNotifier {
  DbDownloadController._(this.url);
  final String url;
  static final Map<String, DbDownloadController> _shared = {};
  factory DbDownloadController.shared(String url) =>
      _shared.putIfAbsent(url, () => DbDownloadController._(url));
  static DbDownloadController sharedFor(String url) =>
      DbDownloadController.shared(url);

  DbDownloadSnapshot _snapshot = const DbDownloadSnapshot();
  DbDownloadSnapshot get snapshot => _snapshot;
  int get received => snapshot.received;
  int? get total => snapshot.total;
  double? get progress => snapshot.progress;
  bool get isPaused => snapshot.status == DbDownloadStatus.paused;
  bool get isDownloading => snapshot.status == DbDownloadStatus.downloading;
  bool _pauseRequested = false;
  Future<Uint8List>? _running;
  int? _expected;
  void Function()? _abort;

  /// Immediately closes the active HTTP client, even before headers arrive or
  /// while a body is stalled. The original future settles after cache flush.
  void pause() {
    if (_running == null && snapshot.status == DbDownloadStatus.completed) {
      return;
    }
    _pauseRequested = true;
    _abort?.call();
    _emit(DbDownloadStatus.paused, received, total, 'Download paused');
  }

  /// Arms a new installation attempt; does NOT initiate a detached download.
  void resume() {
    _pauseRequested = false;
    if (isPaused) {
      _emit(DbDownloadStatus.idle, received, total, 'Ready to resume');
    }
  }

  void _emit(DbDownloadStatus status, int bytes, int? size, String message,
      [Object? error]) {
    _snapshot = DbDownloadSnapshot(
      status: status,
      received: bytes,
      total: size,
      message: message,
      error: error,
    );
    notifyListeners();
  }
}

/// Backward-compatible entry point. Native uses application-support files;
/// browsers use IndexedDB. Optional transport/cache knobs allow offline tests.
Future<Uint8List> downloadCompressedDb({
  required String url,
  int? expectedCompressedBytes,
  int maxAttempts = 3,
  void Function(double progress, String message)? onProgress,
  http.Client Function()? clientFactory,
  DbPartialCache? partialCache,
  bool Function()? isPaused,
  void Function()? onChunk,
  Duration attemptTimeout = const Duration(seconds: 120),
  Duration backoff = const Duration(seconds: 1),
}) =>
    runDownload(
      DbDownloadController.sharedFor(url),
      expectedCompressedBytes: expectedCompressedBytes,
      maxAttempts: maxAttempts,
      onProgress: onProgress,
      clientFactory: clientFactory,
      partialCache: partialCache,
      isPaused: isPaused,
      onChunk: onChunk,
      attemptTimeout: attemptTimeout,
      backoff: backoff,
    );

Future<Uint8List> runDownload(
  DbDownloadController controller, {
  int? expectedCompressedBytes,
  int maxAttempts = 3,
  void Function(double progress, String message)? onProgress,
  http.Client Function()? clientFactory,
  DbPartialCache? partialCache,
  bool Function()? isPaused,
  void Function()? onChunk,
  Duration attemptTimeout = const Duration(seconds: 120),
  Duration backoff = const Duration(seconds: 1),
}) async {
  if (maxAttempts < 1 ||
      attemptTimeout <= Duration.zero ||
      backoff < Duration.zero ||
      (expectedCompressedBytes != null && expectedCompressedBytes <= 0)) {
    throw ArgumentError('Invalid download limits');
  }
  if (controller._running != null &&
      controller._expected != expectedCompressedBytes) {
    throw ArgumentError(
        'Concurrent downloads of one URL must use the same size pin');
  }
  void progressListener() =>
      onProgress?.call(controller.progress ?? 0, controller.snapshot.message);
  if (onProgress != null) controller.addListener(progressListener);
  try {
    if (controller._running == null) {
      final done = Completer<Uint8List>();
      controller._running = done.future;
      controller._expected = expectedCompressedBytes;
      // Assign _running before emitting any notifications (listeners may join).
      unawaited(() async {
        try {
          final bytes = await _downloadLoop(
            controller,
            expectedCompressedBytes: expectedCompressedBytes,
            maxAttempts: maxAttempts,
            clientFactory: clientFactory ?? http.Client.new,
            cache: partialCache ?? defaultDbPartialCache,
            isPaused: isPaused,
            onChunk: onChunk,
            attemptTimeout: attemptTimeout,
            backoff: backoff,
          );
          controller._running = null;
          done.complete(bytes);
        } catch (error, stack) {
          controller._running = null;
          done.completeError(error, stack);
        }
      }());
      return await done.future;
    }
    progressListener();
    return await controller._running!;
  } finally {
    if (onProgress != null) controller.removeListener(progressListener);
  }
}

class _Restart implements Exception {}

Future<Uint8List> _downloadLoop(
  DbDownloadController c, {
  required int? expectedCompressedBytes,
  required int maxAttempts,
  required http.Client Function() clientFactory,
  required DbPartialCache cache,
  required bool Function()? isPaused,
  required void Function()? onChunk,
  required Duration attemptTimeout,
  required Duration backoff,
}) async {
  bool paused() => c._pauseRequested || (isPaused?.call() ?? false);
  try {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (paused()) throw DbDownloadPausedException();
      try {
        c._emit(
            DbDownloadStatus.downloading,
            0,
            expectedCompressedBytes,
            attempt == 1
                ? 'Downloading database…'
                : 'Retrying download (attempt $attempt of $maxAttempts)…');
        final bytes = await _attempt(
          c,
          expectedCompressedBytes,
          cache,
          clientFactory,
          paused,
          onChunk,
          attemptTimeout,
        );
        c._emit(DbDownloadStatus.completed, bytes.length, bytes.length,
            'Download complete (${_mb(bytes.length)} MB)');
        return bytes;
      } catch (error) {
        if (paused() || error is DbDownloadPausedException) {
          throw DbDownloadPausedException();
        }
        final failure = error is DbDownloadException
            ? error
            : DbDownloadException(
                error is TimeoutException
                    ? 'The download timed out. Check your connection and try again.'
                    : 'Could not download the word database: $error',
                isNetwork: true);
        if (attempt == maxAttempts || !failure.isNetwork) throw failure;
        // Pause interrupts backoff as well as a socket. No subsequent request
        // is sent until the caller explicitly resumes and starts again.
        final wake = Completer<void>();
        c._abort = () {
          if (!wake.isCompleted) wake.complete();
        };
        final timer = Timer(backoff * (1 << (attempt - 1).clamp(0, 6)), () {
          if (!wake.isCompleted) wake.complete();
        });
        try {
          await wake.future;
        } finally {
          timer.cancel();
          c._abort = null;
        }
      }
    }
    throw StateError('Unreachable');
  } catch (error) {
    c._emit(
        error is DbDownloadPausedException
            ? DbDownloadStatus.paused
            : DbDownloadStatus.failed,
        c.received,
        c.total,
        error.toString(),
        error);
    rethrow;
  }
}

Future<Uint8List> _attempt(
  DbDownloadController c,
  int? expected,
  DbPartialCache cache,
  http.Client Function() clientFactory,
  bool Function() paused,
  void Function()? onChunk,
  Duration timeout,
) async {
  // A small bounded number of protocol resets is separate from retry backoff.
  for (var resets = 0; resets < 2; resets++) {
    final cached = await cache.load(c.url);
    if (paused()) throw DbDownloadPausedException();
    var prefix = cached ?? Uint8List(0);
    if (expected != null && prefix.length >= expected) {
      // A complete cache without a validated completion marker is not trusted.
      await cache.clearCheckpoint(c.url);
      prefix = Uint8List(0);
    }
    var validator =
        prefix.isEmpty ? null : await cache.loadValidator(c.url, prefix);
    var offset = prefix.length;
    final buffer = BytesBuilder(copy: false)..add(prefix);
    var count = offset;
    var checkpoint = count;
    var total = expected;
    final client = clientFactory();
    final abort = Completer<void>();
    final interrupted = Completer<void>();
    Object? interruption;
    StreamIterator<List<int>>? iterator;
    var closed = false;
    void close() {
      if (!closed) {
        closed = true;
        client.close();
      }
    }

    void interrupt(Object reason) {
      if (interruption != null) return;
      interruption = reason;
      if (!abort.isCompleted) abort.complete();
      close();
      interrupted.complete();
    }

    c._abort = () => interrupt(DbDownloadPausedException());
    final timer =
        Timer(timeout, () => interrupt(TimeoutException('Download timed out')));
    Future<T> wait<T>(Future<T> operation) async {
      // Unlike Future.timeout on the whole worker, this only races network
      // waits. All cache writes settle before another attempt can write.
      final value = await Future.any<Object?>([operation, interrupted.future]);
      if (interruption != null) throw interruption!;
      return value as T;
    }

    try {
      c._emit(
          DbDownloadStatus.downloading, count, total, 'Downloading database…');
      if (paused()) throw DbDownloadPausedException();
      final request = http.AbortableRequest('GET', Uri.parse(c.url),
          abortTrigger: abort.future);
      if (offset > 0) {
        request.headers['range'] = 'bytes=$offset-';
        if (validator != null) request.headers['if-range'] = validator;
      }
      final response = await wait(client.send(request));
      final etag = response.headers['etag'];
      final responseValidator = etag != null && !etag.startsWith('W/')
          ? etag
          : response.headers['last-modified'];
      final length = response.contentLength;
      int? bodyLength = length;
      if (response.statusCode == 416 && offset > 0) throw _Restart();
      if (response.statusCode == 206) {
        final range = _parseContentRange(response.headers['content-range']);
        if ((validator != null &&
                responseValidator != null &&
                validator != responseValidator) ||
            offset == 0 ||
            range == null ||
            range.$1 != offset ||
            range.$2 < range.$1 ||
            range.$3 <= range.$2 ||
            range.$2 != range.$3 - 1 ||
            (length != null && length != range.$2 - range.$1 + 1) ||
            (expected != null && expected != range.$3)) {
          throw _Restart();
        }
        total = range.$3;
        bodyLength = range.$2 - range.$1 + 1;
      } else if (response.statusCode == 200) {
        if (offset > 0) {
          // Range ignored (also the correct If-Range response for a changed
          // entity): consume this full body, never append it to old bytes.
          buffer.clear();
          offset = count = checkpoint = 0;
          await cache.clearCheckpoint(c.url);
        }
        validator = responseValidator;
        total = length ?? expected;
      } else {
        throw DbDownloadException(
            'The server returned HTTP ${response.statusCode} for the database.',
            isNetwork:
                response.statusCode >= 500 || response.statusCode == 429);
      }
      if (expected != null && total != null && total != expected) {
        await cache.clearCheckpoint(c.url);
        throw DbDownloadException(
            'The downloaded database has an unexpected size ($total bytes, expected $expected).');
      }
      iterator = StreamIterator(response.stream);
      while (await wait(iterator.moveNext())) {
        if (paused()) throw DbDownloadPausedException();
        final chunk = iterator.current;
        if ((total != null && count + chunk.length > total) ||
            count + chunk.length > (expected ?? 512 * 1024 * 1024)) {
          await cache.clearCheckpoint(c.url);
          throw DbDownloadException('The server sent more data than declared.');
        }
        buffer.add(chunk);
        count += chunk.length;
        onChunk?.call();
        c._emit(
            DbDownloadStatus.downloading,
            count,
            total,
            total == null
                ? 'Downloading… ${_mb(count)} MB'
                : 'Downloading… ${_mb(count)} / ${_mb(total)} MB');
        if (count - checkpoint >= 1024 * 1024) {
          await cache.saveCheckpoint(c.url, buffer.toBytes(), validator);
          checkpoint = count;
        }
        if (paused()) throw DbDownloadPausedException();
      }
      if (bodyLength != null && count - offset != bodyLength) {
        throw DbDownloadException(
            'The download was incomplete ($count of $total bytes).',
            isNetwork: true);
      }
      if (expected != null && count != expected) {
        throw DbDownloadException(
            'The downloaded database has an unexpected size ($count bytes, expected $expected).');
      }
      if (count == 0)
        throw DbDownloadException('The downloaded database was empty.');
      if (interruption != null) throw interruption!;
      await cache.clearCheckpoint(c.url);
      return buffer.toBytes();
    } on _Restart {
      await cache.clearCheckpoint(c.url);
      if (resets == 1) {
        throw DbDownloadException(
            'The server returned an invalid Content-Range.');
      }
    } catch (error) {
      // Never retain known-invalid data. Network loss and user pause retain
      // the last contiguous prefix. Writes finish before _running is released.
      if (error is! DbDownloadException || error.isNetwork) {
        if (count > 0)
          await cache.saveCheckpoint(c.url, buffer.toBytes(), validator);
      } else {
        await cache.clearCheckpoint(c.url);
      }
      rethrow;
    } finally {
      timer.cancel();
      c._abort = null;
      if (!abort.isCompleted) abort.complete();
      close();
      // A badly behaved test/custom stream may never finish cancellation;
      // there is no longer any worker that can mutate cache or progress.
      if (iterator != null)
        unawaited(iterator.cancel().catchError((Object _) {}));
    }
  }
  throw StateError('Unreachable');
}

(int, int, int)? _parseContentRange(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
  if (m == null) return null;
  final start = int.tryParse(m[1]!);
  final end = int.tryParse(m[2]!);
  final total = int.tryParse(m[3]!);
  return start == null || end == null || total == null
      ? null
      : (start, end, total);
}

/// Decompressed size is a hard gate. SHA-256 retains the existing soft policy
/// so an intentional upstream update with a stale pin does not brick the app.
void verifyDecompressedDb(
  List<int> bytes, {
  int? expectedDecompressedBytes,
  String? expectedDecompressedSha256,
}) {
  if (expectedDecompressedBytes != null &&
      bytes.length != expectedDecompressedBytes) {
    throw DbDownloadException(
        'The database failed validation after decompression '
        '(${bytes.length} bytes, expected $expectedDecompressedBytes).');
  }
  if (expectedDecompressedSha256 != null) {
    final actual = sha256.convert(bytes).toString();
    if (actual.toLowerCase() != expectedDecompressedSha256.toLowerCase() &&
        kDebugMode) {
      debugPrint('[DB_REMOTE] decompressed sha256 mismatch — expected '
          '$expectedDecompressedSha256, got $actual. Proceeding (structural checks passed).');
    }
  }
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
