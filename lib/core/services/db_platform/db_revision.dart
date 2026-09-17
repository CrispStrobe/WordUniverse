// One-time legacy adoption: schema compatibility alone cannot prove revision.
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_schema.dart';

String databaseDigest(Uint8List bytes) => sha256.convert(bytes).toString();

/// Copy only an exact artifact match. Never rename/delete the old usable slot.
/// A failed adoption is harmless: normal consent/install can retry later.
Future<bool> adoptLegacyDatabase({
  required DatabaseFactory factory,
  required String destination,
  required List<String> candidates,
  required String digest,
  required Future<Uint8List> Function(String) read,
  required Future<void> Function(String, Uint8List) write,
  required Future<void> Function(String, String, Uint8List) promote,
}) async {
  for (final source in candidates.where((name) => name != destination)) {
    final staging = '$destination.adopting';
    try {
      if (!await factory.databaseExists(source)) continue;
      final bytes = await read(source);
      if (await compute(databaseDigest, bytes) != digest) continue;
      await write(staging, bytes);
      final checked = await openValidatedDictionary(factory, staging);
      await checked.close();
      await promote(staging, destination, bytes);
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
