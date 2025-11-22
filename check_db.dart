import 'dart:io';
import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';

const dbPath = 'lib/features/games/data/grundwortschatz.db'; // Ensure this matches your file name

void main() {
  print("----------------------------------------------------------------");
  print("🧪  DATABASE INTEGRITY & PERFORMANCE TEST");
  print("----------------------------------------------------------------");

  if (!File(dbPath).existsSync()) {
    print("❌ Error: Database file '$dbPath' not found.");
    return;
  }

  final db = sqlite3.open(dbPath);

  try {
    // --- TEST 1: General Stats ---
    runStatsCheck(db);

    // --- TEST 2: Specific Word Lookup (Checking Normalization) ---
    runSpecificWordCheck(db, "Unterricht");

    // --- TEST 3: Full Text Search (FTS5) Performance ---
    runSearchPerformanceCheck(db, "sch"); 
    runSearchPerformanceCheck(db, "un"); 

    // --- TEST 4: Data Integrity (API Enrichment Blob) ---
    runJsonBlobCheck(db, "Uni");

    // --- TEST 5: Translation Linkage ---
    runTranslationCheck(db);

  } catch (e, stack) {
    print("❌ CRITICAL ERROR: $e");
    print(stack);
  } finally {
    db.dispose();
    print("\n----------------------------------------------------------------");
    print("✅  Tests Completed.");
    print("----------------------------------------------------------------");
  }
}

void runStatsCheck(Database db) {
  print("\n[1] 📊 TABLE STATISTICS");
  
  final tables = ['words', 'translations', 'examples', 'search_index'];
  
  for (var table in tables) {
    final count = db.select('SELECT count(*) as c FROM $table').first['c'];
    print("   • $table: $count rows");
  }
}

void runSpecificWordCheck(Database db, String targetWord) {
  print("\n[2] 🔎 SPECIFIC WORD CHECK: '$targetWord'");

  final result = db.select(
    'SELECT * FROM words WHERE word = ?', 
    [targetWord]
  );

  if (result.isEmpty) {
    print("   ⚠️ Word not found!");
    return;
  }

  final row = result.first;
  final id = row['id'];
  print("   • ID: $id");
  print("   • Lemma: ${row['lemma']}");
  print("   • Grade Level: ${row['grade_level']}");
  print("   • Audio Path: ${row['audio_path'] ?? 'None'}");
  
  // Check linked translations
  final transResult = db.select(
    'SELECT lang_code, translation FROM translations WHERE word_id = ?', 
    [id]
  );
  print("   • Translations found: ${transResult.length}");
  for (var t in transResult.take(3)) {
    print("     - [${t['lang_code']}] ${t['translation']}");
  }
}

void runSearchPerformanceCheck(Database db, String query) {
  print("\n[3] 🚀 FTS SEARCH PERFORMANCE: '$query'");
  
  final stopwatch = Stopwatch()..start();
  
  // FIXED: Added 'words.' prefix to the ORDER BY clause
  final results = db.select('''
    SELECT words.word, words.lemma 
    FROM words 
    JOIN search_index ON words.id = search_index.rowid 
    WHERE search_index MATCH '$query*' 
    ORDER BY length(words.word) ASC 
    LIMIT 10
  ''');
  
  stopwatch.stop();
  print("   • Time taken: ${stopwatch.elapsedMilliseconds}ms");
  print("   • Results found: ${results.length}");
  
  if (results.isNotEmpty) {
    final preview = results.map((r) => r['word']).join(", ");
    print("   • Matches: $preview...");
  }
}

void runJsonBlobCheck(Database db, String targetWord) {
  print("\n[4] 📦 JSON BLOB INTEGRITY: '$targetWord'");
  
  final result = db.select('SELECT raw_json FROM words WHERE word = ?', [targetWord]);
  
  if (result.isEmpty) {
    print("   ⚠️ Word not found.");
    return;
  }

  final jsonStr = result.first['raw_json'] as String?;
  
  if (jsonStr == null || jsonStr.isEmpty || jsonStr == "{}") {
    print("   ⚠️ Raw JSON is empty/null.");
    return;
  }

  try {
    // Try decoding
    final data = jsonDecode(jsonStr);
    print("   • JSON Decoding: SUCCESS");
    
    // Check if specific V24 enriched fields exist inside
    final inflections = data['inflections'];
    if (inflections != null) {
      print("   • Enrichment Data (Inflections): Found ${inflections.length} items");
      if (inflections.isNotEmpty) {
        print("     - Sample: ${inflections[0]['form_text']}");
      }
    } else {
      print("   • Enrichment Data: Not found in blob.");
    }
    
  } catch (e) {
    print("   ❌ JSON Decoding FAILED: $e");
  }
}

void runTranslationCheck(Database db) {
  print("\n[5] 🔗 RELATIONAL INTEGRITY (Orphans)");
  
  // Check for translations pointing to non-existent words
  final orphans = db.select('''
    SELECT count(*) as c 
    FROM translations 
    WHERE word_id NOT IN (SELECT id FROM words)
  ''').first['c'];

  if (orphans > 0) {
    print("   ❌ FOUND $orphans ORPHAN TRANSLATIONS!");
  } else {
    print("   ✅ No orphan translations found (Foreign Keys valid).");
  }
}