@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/services/db_platform/db_partial_cache_web.dart';

void main() {
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
