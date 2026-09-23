// Contract test for the language-pack registry (lib/core/models/language_pack.dart).
//
// The registry is the only place a learning language is declared, so these
// invariants are what keeps "add a language" from turning into a crash:
// every pack must be obtainable, every downloadable pack must be verifiable,
// and the fallback pack must never need the network.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:WortUniversum/core/models/language_pack.dart';

void main() {
  test('installation budget covers platform promotion plus download reserve',
      () {
    final pack = kLanguagePacks['de']!;
    final databaseCopies = kIsWeb ? 2 : 1;
    expect(
        pack.requiredFreeBytes,
        databaseCopies * pack.expectedDecompressedBytes! +
            pack.expectedCompressedBytes!);
    // Down from 325/175 MiB: the published artifact carries only the
    // enrichment the app reads (tools/pack/slim_pack.py), and a megabyte of
    // that is the feature index it also ships (tools/pack/index_pack.sh),
    // which the device no longer has to derive.
    //
    // Up from 182/98 by five megabytes on 2026-09-23, deliberately. The
    // slimmer had also dropped openThesaurus, which is the only thing in the
    // pack that says which *sense* a synonym belongs to — without it the
    // synonym list is every sense poured together, and Spielzeug was
    // answered Werkzeug. Reduced to the synsets the games read it costs
    // about a megabyte compressed, and the number here is why that trade is
    // stated rather than slipped in.
    expect(pack.requiredFreeSizeLabel, kIsWeb ? '192 MiB' : '104 MiB');
    expect(kLanguagePacks['en']!.requiredFreeBytes, isNull);
    expect(kLanguagePacks['en']!.requiredFreeSizeLabel, isNull);
  });

  test('every pack is obtainable (bundled asset or remote URL)', () {
    for (final pack in kLanguagePacks.values) {
      expect(pack.isBundled || pack.requiresDownload, isTrue,
          reason: 'Pack "${pack.code}" has neither assetPath nor remoteUrl, '
              'so it can never be installed.');
    }
  });

  test('registry keys match their pack code', () {
    kLanguagePacks.forEach((key, pack) {
      expect(pack.code, key,
          reason: 'Registry key "$key" disagrees with pack.code '
              '"${pack.code}"; lookups by code would miss.');
    });
  });

  test('downloadable packs pin their integrity data', () {
    for (final pack in kLanguagePacks.values.where((p) => p.requiresDownload)) {
      expect(pack.expectedCompressedBytes, isNotNull,
          reason: 'Pack "${pack.code}" needs expectedCompressedBytes: it is '
              'both the hard truncation check and the size disclosed to the '
              'user before downloading.');
      expect(pack.expectedDecompressedSha256, isNotNull,
          reason: 'Pack "${pack.code}" needs expectedDecompressedSha256.');
      expect(pack.remoteUrl, startsWith('https://'),
          reason: 'Pack "${pack.code}" must be fetched over TLS.');
    }
  });

  test('database names are unique', () {
    final names = kLanguagePacks.values.map((p) => p.databaseName).toList();
    expect(names.toSet().length, names.length,
        reason: 'Two packs share a databaseName; they would overwrite each '
            'other in app storage.');
  });

  test('packs declare a data license', () {
    for (final pack in kLanguagePacks.values) {
      expect(pack.licenseLabel, isNotEmpty,
          reason: 'Pack "${pack.code}" must state its data license — it is '
              'shown in Settings and in the download disclosure.');
    }
  });

  test('default and fallback codes exist, and the fallback needs no network',
      () {
    expect(kLanguagePacks.containsKey(kDefaultLanguageCode), isTrue);
    final fallback = kLanguagePacks[kFallbackLanguageCode];
    expect(fallback, isNotNull);
    expect(fallback!.isBundled, isTrue,
        reason: 'The fallback pack is what we drop to when a download fails, '
            'so it must be bundled — otherwise the failure path also needs '
            'the network.');
  });

  test('orderedLanguagePacks lists every pack, default first', () {
    final ordered = orderedLanguagePacks;
    expect(ordered.length, kLanguagePacks.length);
    expect(ordered.first.code, kDefaultLanguageCode);
    expect(ordered.map((p) => p.code).toSet(), kLanguagePacks.keys.toSet());
  });
}
