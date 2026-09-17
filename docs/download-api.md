FINAL DOWNLOAD API / integration notes (verified native + Chrome)

Import lib/core/services/db_platform/db_remote.dart.

final controller = DbDownloadController.sharedFor(pack.remoteUrl!);
// Alias: DbDownloadController.shared(url). Same instance used automatically by
// existing downloadCompressedDb(url: ..., expectedCompressedBytes: ...).
controller.addListener(listener); // removeListener on service disposal; DO NOT dispose shared controller
controller.snapshot: DbDownloadSnapshot
  status: DbDownloadStatus {idle, downloading, paused, completed, failed}
  received: int compressed bytes
  total: int? compressed bytes (null means indeterminate)
  progress: double? in [0,1]
  message: LoadStatus (core/models/load_status.dart: stage + bytes/total/attempt)
           render it with shared/utils/load_status_localization.dart
  error: Object?
Convenience getters controller.received/total/progress/isPaused/isDownloading.

PAUSE/RESUME CONTRACT (important):
controller.pause() is synchronous: immediately closes HTTP client + triggers
AbortableRequest cancellation (including stalled headers/body and browser fetch).
The existing download/install Future then throws DbDownloadPausedException
(subclass of DbDownloadException) AFTER its partial checkpoint is flushed.
Treat this as PAUSED, not FAILED. Await that install attempt settling first.
controller.resume() ONLY clears paused state (status becomes idle); it does not
start detached work. Re-enter your existing install flow to continue with Range.
Do not attempt to resume by calling install while old install is still running.
Pause after completed is a no-op: compressed completion is distinct from install.

Existing downloadCompressedDb named arguments remain compatible. Optional knobs:
clientFactory, partialCache, attemptTimeout, backoff, isPaused, onChunk.
runDownload(controller, ...) is the explicit equivalent.
Concurrent same-URL calls share one active transfer; each callback receives byte
progress. Conflicting compressed-size pins are refused. Per-URL ownership is
within one Dart isolate, not an OS-wide/cross-tab lease.

IMPLEMENTED:
- Streaming byte progress (~200 updates per transfer: emits are spaced by
  total/200, every chunk when the total is tiny or unknown, so a few-KB socket
  chunk no longer walks every listener), bounded retries/exponential backoff,
  prompt abort on pause or timeout, no detached worker allowed to mutate cache
  after timeout.
- Range continuation; ignored Range (200) consumes a clean full body; malformed
  206, changed exposed validator, or 416 triggers bounded clean restart.
- Durable partial cache in app support/db-downloads on native and IndexedDB
  worduniverse-downloads/partials on web; no prefs or localStorage for bytes.
  Checkpoint spacing scales with the transfer (total/16, 1 MiB floor, 4 MiB when
  the size is unknown) because each checkpoint rewrites the whole prefix; plus a
  pause/network-error flush, atomic file replace / IDB transaction. One record
  per checkpoint: a magic+version envelope holding payload length, SHA256 and
  the validator, so torn or same-size corrupt checkpoints are rejected and a
  prefix can never be paired with another write's validator. v1 records from an
  older build fail the magic check and restart cleanly.
- Strong ETag/Last-Modified persisted in the same record as the bytes, If-Range
  on resume. CORS-hidden validators remain optional; hidden/malformed Content-Range
  requires safe full restart. Upstream CORS must allow Range/If-Range requests.
- Compressed size/Content-Length hard checks, empty/oversize rejection. Success
  deletes compressed checkpoint (downstream retry then gets fresh bytes).
- NEW db_gzip.dart explicitly checks gzip CRC and ISIZE. Both loaders call this
  from their existing compute helper; no loader signature changes. Existing
  decodeBytes default verify:false was not sufficient, especially in browsers.
- decodeAndVerifyDbGzip(DbGzipJob) runs decode AND the payload gates inside the
  compute() isolate, so nothing hashes ~150 MB on the UI thread. Hard
  decompressed-size gate; SOFT SHA policy by default (computed only when it can
  change the outcome, i.e. in debug or when enforced).
- requireSha256 promotes the SHA pin to a hard gate for exactly one case: the
  bytes include a cached prefix whose record carried no HTTP validator
  (controller.resumedWithoutValidator), where If-Range could not prove the
  server still serves the same revision. Failure discards the (already deleted)
  checkpoint and the next attempt starts at offset 0 with the soft policy, so a
  stale pin cannot brick the install. Payload gates raise DbPayloadException;
  loaders surface its message verbatim.

- Space: LanguagePackService refuses an install when a platform-reported quota
  is smaller than pack.requiredFreeBytes (decompressed + compressed copy);
  availableStorageBytes() is navigator.storage.estimate() on web and null on
  native, where ENOSPC (errno 28) and browser quota errors are translated into
  DbInsufficientSpaceException instead. LanguagePackState.errorIsSpace drives a
  localized "needs about N MB" message rather than an unhelpful Retry hint.
- Resume visibility: DbPartialCache.cachedLength(url) reads the envelope header
  only (native reads 40 bytes, not the prefix), so refresh() can label a row
  "12.4 of 25 MB downloaded" and offer Resume without hashing anything.

VERIFICATION:
Final combined native run: 61 tests passed (26 downloader/storage/gzip/socket
and 35 existing LanguagePackService/registry regression tests). Chrome: 20 tests
passed. Native/IndexedDB new-cache instance tests confirm validator persistence.
Targeted flutter analyze clean; git diff --check clean.
Native log: /tmp/worduniverse-download-native-tests.log.
Live checks (opt-in, WU_LIVE=1): test/live/language_pack_pins_live_test.dart
HEADs every published pack and compares content-length, sha256-shaped ETag and
Accept-Ranges against the registry; test/live/db_remote_live_test.dart pauses a
real Hugging Face download, resumes it from the on-disk checkpoint and checks
the reassembled bytes against the pins (add WU_LIVE_DECOMPRESS=1 to also verify
the decompressed digest). Registry pins were confirmed against the live
artifact on 2026-09-17: 26,619,920 compressed, 156,913,664 decompressed,
sha256 c66e3b49…00df.

CAVEATS:
- Bytes are still accumulated in memory for legacy Uint8List return; checkpoints
  rewrite current prefix rather than an append-only chunk store (reasonable for
  present ~25MB packs, not intended for multi-GB assets). Spacing now bounds
  that cost to ~16 rewrites per transfer; an append-only store would need
  per-block records on web, where IndexedDB values cannot be appended.
- Browser storage quota/access failures currently surface as retryable failure;
  no silent memory-only fallback. Browser may evict IndexedDB under storage pressure.
- No cross-tab/process lock, cache expiration/eviction UI, or explicit discard API.
  One active transfer per URL in one app isolate is enforced.
- Tested browser transport cancellation via fake streamed clients plus real
  IndexedDB; native has an actual socket test. No live Hugging Face download run.
