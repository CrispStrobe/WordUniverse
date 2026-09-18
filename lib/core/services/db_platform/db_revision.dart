// One-time legacy adoption: schema compatibility alone cannot prove revision.
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_schema.dart';

/// Isolate entry for hosts that can only hand over the whole artifact (web).
String databaseDigest(Uint8List bytes) => sha256.convert(bytes).toString();

/// Copy only an exact artifact match. Never rename/delete the old usable slot.
/// A failed adoption is harmless: normal consent/install can retry later.
///
/// [digestOf] and [copy] are passed per platform rather than taking the bytes
/// here, because the artifact is ~150 MB: native streams it (constant memory),
/// while a browser has no streaming path and must hand over a buffer. Holding
/// the whole database in RAM on the upgrade path would risk an out-of-memory
/// kill — which no catch block can turn into "adoption failed, carry on" — for
/// every existing user of a republished pack.
Future<bool> adoptLegacyDatabase({
  required DatabaseFactory factory,
  required String destination,
  required List<String> candidates,
  required String digest,
  required Future<String> Function(String source) digestOf,
  required Future<void> Function(String source, String staging) copy,
  required Future<void> Function(String staging, String destination) promote,
}) async {
  for (final source in candidates.where((name) => name != destination)) {
    final staging = '$destination.adopting';
    try {
      if (!await factory.databaseExists(source)) continue;
      if (await digestOf(source) != digest) continue;
      await copy(source, staging);
      final checked = await openValidatedDictionary(factory, staging);
      await checked.close();
      await promote(staging, destination);
      final installed = await openValidatedDictionary(factory, destination);
      await installed.close();
      return true;
    } catch (_) {
      // Retain the source even if storage is unavailable or validation fails.
    } finally {
      try {
        await factory.deleteDatabase(staging);
      } catch (_) {}
    }
  }
  return false;
}
