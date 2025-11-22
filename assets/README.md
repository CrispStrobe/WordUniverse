---
license: cc-by-sa-4.0
language:
- de
- en
tags:
- linguistics
- education
- german
- vocabulary
- sqlite
pretty_name: Grundwortschatz DB
size_categories:
- 1K<n<10K
task_categories:
- text-classification
- translation
---
# 🇩🇪 Grundwortschatz.db: German Basic Vocabulary Database

**A high-performance, enriched SQLite database for German language learning applications.**

This database consolidates basic German vocabulary (Grundwortschatz) suitable for primary education (Grades 1-4) and language learners (A1-B1). It is heavily enriched with semantic data, translations, audio references, and linguistic metadata, optimized for use in mobile applications (Flutter/iOS/Android) and data analysis.

## 📂 Database Overview

  * **Format:** SQLite 3 (`.db`)
  * **Encoding:** UTF-8
  * **Optimization:**
      * Normalized tables for one-to-many relationships (Translations, Examples).
      * **FTS5 Enabled:** Includes a pre-built Full-Text Search virtual table for millisecond-latency lookups.
      * **JSON Columns:** deeply nested linguistic data is stored in queryable JSON blobs to maintain a flexible schema.

-----

## 🗄️ Schema Documentation

The database consists of four primary tables.

### 1\. `words` (Master Table)

This is the core table containing one row per unique word entry.

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `INTEGER PK` | Auto-incrementing internal ID. |
| `original_id` | `TEXT` | Unique string ID (e.g., `word_001`) for external mapping. |
| `word` | `TEXT` | The surface form of the word (e.g., "Häuser"). |
| `lemma` | `TEXT` | The dictionary form (e.g., "Haus"). |
| `article` | `TEXT` | Definite article for nouns (`der`, `die`, `das`). Nullable. |
| `genus` | `TEXT` | Grammatical gender (`m`, `f`, `n`). Nullable. |
| `word_type` | `TEXT` | Part of speech (e.g., `substantiv`, `verb`, `adjektiv`). |
| `grade_level` | `INTEGER` | Recommended grade level (1-4) or difficulty tier. |
| `audio_path` | `TEXT` | Filename or URL hash for pronunciation audio. |
| `frequency_json` | `TEXT (JSON)` | Corpus frequency statistics. |
| `enrichment_json`| `TEXT (JSON)` | **The "Treasure Chest":** Semantic relations, Wiktionary data, IPA. |
| `metadata_json` | `TEXT (JSON)` | App-specific metadata (spelling difficulty, categories). |

### 2\. `translations`

Normalized table for looking up words by their English translation.

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `INTEGER PK` | |
| `word_id` | `INTEGER` | Foreign Key to `words.id`. |
| `lang_code` | `TEXT` | ISO language code (e.g., `en`). |
| `translation` | `TEXT` | The translated text. |

### 3\. `examples`

Contains sentence-level usage examples.

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `INTEGER PK` | |
| `word_id` | `INTEGER` | Foreign Key to `words.id`. |
| `sentence` | `TEXT` | Full German sentence usage. |

### 4\. `search_index` (Virtual Table)

An FTS5 (Full-Text Search) table linked to the `words` table.

  * **Columns Indexed:** `word`, `lemma`, `translations`.
  * **Usage:** Allows for super-fast prefix matching and fuzzy search.

-----

## 🔍 JSON Blob Detail

To keep the schema clean while retaining massive linguistic detail, we use SQLite JSON columns.

### `enrichment_json` structure

Derived from Wiktionary and OpenThesaurus processing.

```json
{
  "definitions": ["Building for human habitation", "Family lineage"],
  "pronunciation": [
    { "ipa": "/haʊ̯s/", "audio": "De-Haus.ogg" }
  ],
  "synonyms": ["Gebäude", "Daheim"],
  "antonyms": [],
  "hypernyms": [{ "word": "Gebäude" }],
  "hyponyms": [{ "word": "Hochhaus" }],
  "inflections": [ ... ], // Raw inflection tables
  "hyphenation": ["Haus"]
}
```

### `metadata_json` structure

Contains pedagogical data.

```json
{
  "sources": ["Grundwortschatz_BW", "A1_List"],
  "categories": ["zuhause", "stadt"],
  "spellingDifficulty": 1, // 0=Easy, 5=Hard
  "graphematicVariants": [
    { "spelling": "Hauz", "probability": 0.1 } // Common misspelling analysis
  ]
}
```

-----

## ⚡ Usage Examples

### 1\. Basic SQL Queries

**Get all Nouns for Grade Level 1:**

```sql
SELECT word, article, lemma 
FROM words 
WHERE word_type = 'substantiv' AND grade_level = 1;
```

**Search for a word (English or German) using FTS:**

```sql
SELECT w.* FROM words w
JOIN search_index s ON w.id = s.rowid
WHERE s.search_index MATCH 'house*'; -- Finds "Haus" via translation
```

**Extract specific data from JSON (SQLite JSON1 Extension):**

```sql
-- Get words where the IPA pronunciation is available
SELECT word, json_extract(enrichment_json, '$.pronunciation[0].ipa') as ipa
FROM words
WHERE json_extract(enrichment_json, '$.pronunciation[0].ipa') IS NOT NULL;
```

### 2\. Python Example (`sqlite3`)

```python
import sqlite3
import json

conn = sqlite3.connect('grundwortschatz.db')
conn.row_factory = sqlite3.Row # Access columns by name
cursor = conn.cursor()

# Fetch a complex word object
word_query = "SELECT * FROM words WHERE word = 'Haus'"
row = cursor.execute(word_query).fetchone()

if row:
    print(f"Word: {row['article']} {row['word']}")
    
    # Parse the JSON blob for synonyms
    enrichment = json.loads(row['enrichment_json'])
    print("Synonyms:", ", ".join(enrichment.get('synonyms', [])))
    
    # Get Translations via join
    trans_query = "SELECT translation FROM translations WHERE word_id = ?"
    translations = cursor.execute(trans_query, (row['id'],)).fetchall()
    print("English:", [t[0] for t in translations])

conn.close()
```

### 3\. Dart/Flutter Integration

This database is designed for `sqflite`.

```dart
// Example raw query in Dart
final List<Map<String, dynamic>> results = await db.rawQuery('''
  SELECT * FROM words 
  WHERE json_extract(metadata_json, '$.spellingDifficulty') > 2
''');

// Map the result
final word = GermanWord.fromJson(results.first); // Assuming you have the model
```

-----

## 🛠 Data Provenance & License

  * **Core Vocabulary:** Based on German Primary School "Grundwortschatz" lists (e.g., Baden-Württemberg, NRW).
  * **Enrichment:** Data derived from [Wiktionary](https://www.wiktionary.org/), OpenThesaurus etc
  * **License:**
      * Inherits [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) due sources
