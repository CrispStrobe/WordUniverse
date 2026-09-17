// Live guard for the language-pack pins (item: registry vs. published artifact).
//
// expectedCompressedBytes is a HARD gate in the transport, so rebuilding a pack
// and uploading it without bumping the registry breaks EVERY NEW INSTALL while
// every existing install keeps working — a failure that is invisible in normal
// testing. This guard uses HEAD plus a GET to verify the compressed bytes.
//
// Skipped unless WU_LIVE=1, so the offline suite stays offline. CI runs it on a
// schedule (see .github/workflows/pack-pins.yml).

library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:WortUniversum/core/models/language_pack.dart';

/// Hugging Face serves datasets through a CDN whose `etag` is a mutable entity
/// tag that changed once without the underlying bytes changing; the artifact's
/// own digest is exposed as x-linked-etag and may be missing. A CDN etag can
/// therefore NOT prove the pinned digest is wrong; only the actual bytes can.
Future<String> _downloadedSha256(Uri url) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', url)
      ..followRedirects = true
      ..maxRedirects = 5;
    final response = await client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      fail('expected 200 for the published pack, got ${response.statusCode}');
    }
    final digest = await sha256.bind(response.stream).first.timeout(const Duration(minutes: 2));
    return digest.toString();
  } finally {
    client.close();
  }
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

      test('published digest still matches expectedCompressedSha256', () async {
        final pinned = pack.expectedCompressedSha256;
        if (pinned == null) return; // Optional pin: size gate still applies.
        // The CDN etag is mutable and once changed while the pinned bytes were
        // still correct, so a header mismatch alone cannot fail this guard:
        // the actual bytes decide, and a mismatch here means a rebuilt pack.
        final digest = await _downloadedSha256(Uri.parse(pack.remoteUrl!));
        expect(digest.toLowerCase(), pinned.toLowerCase(),
            reason: 'the published bytes changed; bump the registry pins');
      }, skip: skip);

      test('supports the byte ranges that resuming depends on', () {
        expect(head.headers['accept-ranges'], 'bytes',
            reason: 'without Range support a paused download restarts at 0');
      }, skip: skip);
    });
  }
}
