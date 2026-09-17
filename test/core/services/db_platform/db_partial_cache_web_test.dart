@TestOn('browser')
library;

import 'dart:js_interop';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache_web.dart';

@JS('Function')
external JSFunction _function(String body);

void main() {
  for (final phase in ['open', 'request', 'abort', 'sync']) {
    for (final name in ['QuotaExceededError', 'SecurityError']) {
      test('$phase preserves DOMException $name', () async {
        final factory = _function('''
          const error = new DOMException('storage failed', '$name');
          return {open() {
            if ('$phase' === 'sync') throw error;
            const request = {error, result: {transaction() {
              const tx = {error, objectStore() {return {put() {
                const r = {error};
                setTimeout(() => { if ('$phase' === 'abort') tx.onabort(); else r.onerror(); }, 0);
                return r;
              }}}};
              return tx;
            }}};
            setTimeout(() => {if ('$phase' === 'open') request.onerror(); else request.onsuccess();}, 0);
            return request;
          }};
        ''').callAsFunction() as JSObject;
        final cache = IndexedDbPartialCache(factory: factory);
        await expectLater(
            cache.save('u', [1]),
            throwsA(isA<DbStorageException>()
                .having((e) => e.errorName, 'DOM name', name)
                .having((e) => e.isNetwork, 'network', false)
                .having((e) => e is DbInsufficientSpaceException, 'space',
                    name == 'QuotaExceededError')));
      });
    }
  }
  test('IndexedDB checkpoint survives a new cache instance and clears',
      () async {
    final url =
        'https://test/persistent/${DateTime.now().microsecondsSinceEpoch}';
    final first = IndexedDbPartialCache();
    expect(await first.load(url), isNull);
    await first.saveCheckpoint(url, [1, 2, 3], '"version-1"');
    final reopened = IndexedDbPartialCache();
    expect(await reopened.load(url), [1, 2, 3]);
    expect(await reopened.loadValidator(url, (await reopened.load(url))!),
        '"version-1"');
    await reopened.save(url, [1, 2, 3, 4]);
    expect(await first.load(url), [1, 2, 3, 4]);
    await reopened.clear(url);
    expect(await first.load(url), isNull);
  });
}
