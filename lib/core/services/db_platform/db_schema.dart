import 'package:sqflite/sqflite.dart';

/// Structural compatibility, not a dataset/content revision. Legacy packs use
/// user_version=0, so inspect the actual schema instead of requiring a version.
class DbSchemaException implements Exception {
  const DbSchemaException(this.message);
  final String message;
  @override
  String toString() => 'Incompatible dictionary database: $message';
}

/// Returns the word count only after the core query contract is satisfied.
/// The row parser defaults optional lemma/grammar/audio/JSON fields. Language
/// extras (phrasal_verbs, false_friends) and the FTS index are not launch gates.
Future<int> validateDictionarySchema(DatabaseExecutor db) async {
  const requiredColumns = {
    'id',
    'original_id',
    'word',
    'word_type',
    'grade_level'
  };
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND lower(name)='words'",
  );
  if (tables.isEmpty) {
    throw const DbSchemaException('missing words table');
  }
  final columns = await db.rawQuery('PRAGMA table_info(words)');
  final names = columns.map((c) => (c['name'] as String).toLowerCase()).toSet();
  final missing = requiredColumns.difference(names);
  if (missing.isNotEmpty) {
    throw DbSchemaException('missing words columns: ${missing.join(', ')}');
  }
  final count = Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM words'),
  );
  if (count == null || count <= 0) {
    throw const DbSchemaException('empty words table');
  }
  return count;
}

/// Owns the opened handle until validation succeeds. Never leaks a rejected
/// connection, including on SQLite query errors.
Future<Database> openValidatedDictionary(
  DatabaseFactory factory,
  String path,
) async {
  final db = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    await validateDictionarySchema(db);
    return db;
  } catch (_) {
    await db.close();
    rethrow;
  }
}
