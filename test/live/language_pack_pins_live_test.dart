// Live guard for the language-pack pins (item: registry vs. published artifact).
//
// expectedCompressedBytes is a HARD gate in the transport, so rebuilding a pack
// and uploading it without bumping the registry breaks EVERY NEW INSTALL while
// every existing install keeps working — a failure that is invisible in normal
// testing. This test is the cheap guard: one HEAD per downloadable pack.
//
// Skipped unless WU_LIVE=1, so the offline suite stays offline. CI runs it on a
// schedule (see .github/workflows/pack-pins.yml).

@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:WortUniversum/core/models/language_pack.dart';

/// Hugging Face exposes the artifact's own digest as x-linked-etag and the CDN
/// entity tag as etag; either may be quoted.
String? _digestHeader(Map<String, String> headers) {
  for (final name in const ['x-linked-etag', 'etag']) {
    final value = headers[name]?.replaceAll('"', '').replaceAll('W/', '');
    if (value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      return value.toLowerCase();
    }
  }
  return null;
}

void main() {
  final live = Platform.environment['WU_LIVE'] == '1';
  final skip = live ? null : 'set WU_LIVE=1 to run live network checks';

  for (final pack
      in kLanguagePacks.values.where((pack) => pack.requiresDownload)) {
    group('${pack.code} pack (${pack.remoteUrl})', () {
      late http.Response head;

      setUpAll(() async {
        if (!live) return;
        head = await http.head(Uri.parse(pack.remoteUrl!));
      });

      test('is reachable', () {
        expect(head.statusCode, 200,
            reason: 'the published pack must be fetchable anonymously');
      }, skip: skip);

      test('published size still matches expectedCompressedBytes', () {
        final length = int.tryParse(head.headers['content-length'] ?? '');
        expect(length, pack.expectedCompressedBytes,
            reason: 'the pack was rebuilt without bumping the registry pin; '
                'every new install would fail the hard size gate. Update '
                'lib/core/models/language_pack.dart.');
      }, skip: skip);

      test('published digest still matches expectedCompressedSha256', () {
        final pinned = pack.expectedCompressedSha256;
        if (pinned == null) return; // Optional pin: size gate still applies.
        final published = _digestHeader(head.headers);
        // Only assert when the host actually exposes a sha256-shaped tag.
        if (published == null) return;
        expect(published, pinned.toLowerCase(),
            reason: 'the published bytes changed; bump the registry pins');
      }, skip: skip);

      test('supports the byte ranges that resuming depends on', () {
        expect(head.headers['accept-ranges'], 'bytes',
            reason: 'without Range support a paused download restarts at 0');
      }, skip: skip);
    });
  }
}
