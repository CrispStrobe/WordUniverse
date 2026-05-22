"""Convert grundwortschatz_en.json to the app-compatible SQLite schema.

This is the EN mirror of voc-de/14_convert_db_to_sqflite.py. It accepts the
base step-03 JSON as well as later V24-enriched JSON files, so the EN pipeline
can produce a runnable DB before the long WiktionaryEN sweep exists.
"""
import json
import os
import sqlite3
import argparse

INPUT_FILE = "grundwortschatz_en.json"
DB_FILE = "grundwortschatz_en.db"


def safe_int(value, default=0):
    try:
        if value is None:
            return default
        if isinstance(value, (int, float)):
            return int(value)
        if isinstance(value, str):
            value = value.strip()
            if not value:
                return default
            if "." in value:
                return int(float(value))
            return int(value)
        return default
    except (ValueError, TypeError):
        return default


def safe_float(value, default=0.0):
    try:
        if value is None:
            return default
        return float(value)
    except (ValueError, TypeError):
        return default


def init_db_schema(cursor):
    cursor.execute("PRAGMA foreign_keys = ON;")
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            original_id TEXT UNIQUE,
            word TEXT NOT NULL,
            lemma TEXT,
            article TEXT,
            genus TEXT,
            word_type TEXT,
            grade_level INTEGER,
            audio_path TEXT,
            frequency_json TEXT,
            enrichment_json TEXT,
            metadata_json TEXT
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS translations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word_id INTEGER NOT NULL,
            lang_code TEXT,
            translation TEXT,
            FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS examples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word_id INTEGER NOT NULL,
            sentence TEXT,
            FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
        )
        """
    )
    cursor.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS search_index "
        "USING fts5(word, lemma, translations, content=words, content_rowid=id)"
    )


def create_triggers(cursor):
    cursor.execute(
        """
        CREATE TRIGGER IF NOT EXISTS words_ai AFTER INSERT ON words BEGIN
          INSERT INTO search_index(rowid, word, lemma, translations)
          VALUES (new.id, new.word, new.lemma, ' ');
        END;
        """
    )
    cursor.execute(
        """
        CREATE TRIGGER IF NOT EXISTS words_ad AFTER DELETE ON words BEGIN
          INSERT INTO search_index(search_index, rowid, word, lemma, translations)
          VALUES('delete', old.id, old.word, old.lemma, ' ');
        END;
        """
    )
    cursor.execute(
        """
        CREATE TRIGGER IF NOT EXISTS words_au AFTER UPDATE ON words BEGIN
          INSERT INTO search_index(search_index, rowid, word, lemma, translations)
          VALUES('delete', old.id, old.word, old.lemma, ' ');
          INSERT INTO search_index(rowid, word, lemma, translations)
          VALUES (new.id, new.word, new.lemma, ' ');
        END;
        """
    )


def build_enrichment_json(entry):
    enrichment = entry.get("apiEnrichment")
    if not isinstance(enrichment, dict):
        enrichment = {}

    for key in [
        "definitions",
        "examples",
        "commonLearnerErrors",
        "graphemeVariants",
        "spellingVariants",
        "pronunciation",
        "inflectionData",
    ]:
        value = entry.get(key)
        if value not in (None, [], {}):
            enrichment.setdefault(key, value)

    if "tags" in entry:
        enrichment.setdefault("tags", entry["tags"])

    if enrichment.get("conceptnet"):
        for rel in enrichment["conceptnet"]:
            if isinstance(rel, dict) and "weight" in rel:
                rel["weight"] = safe_float(rel.get("weight"))

    return json.dumps(enrichment) if enrichment else None


def process_and_insert(conn, data):
    cursor = conn.cursor()
    vocabulary = data.get("vocabulary", [])
    total_count = len(vocabulary)

    sql_insert_word = """
        INSERT INTO words (
            original_id, word, lemma, article, genus, word_type, grade_level,
            audio_path, frequency_json, enrichment_json, metadata_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    sql_insert_trans = (
        "INSERT INTO translations (word_id, lang_code, translation) VALUES (?, ?, ?)"
    )
    sql_insert_ex = "INSERT INTO examples (word_id, sentence) VALUES (?, ?)"
    sql_insert_fts = (
        "INSERT INTO search_index (rowid, word, lemma, translations) VALUES (?, ?, ?, ?)"
    )

    cursor.execute("BEGIN TRANSACTION")
    try:
        for index, entry in enumerate(vocabulary):
            if index % 1000 == 0:
                print(f"   ... processed {index}/{total_count} words")

            frequency_data = entry.get("frequencyData")
            frequency_json = json.dumps(frequency_data) if frequency_data else None
            enrichment_json = build_enrichment_json(entry)

            meta_copy = entry.copy()
            for key in [
                "id",
                "word",
                "lemma",
                "article",
                "genus",
                "wordType",
                "gradeLevel",
                "audioPath",
                "frequencyData",
                "apiEnrichment",
                "translations",
                "wiktionary_translations",
                "exampleSentences",
                "examples",
                "definitions",
            ]:
                meta_copy.pop(key, None)
            metadata_json = json.dumps(meta_copy)

            cursor.execute(
                sql_insert_word,
                (
                    entry.get("id"),
                    entry.get("word", ""),
                    entry.get("lemma", ""),
                    entry.get("article"),
                    entry.get("genus"),
                    entry.get("wordType"),
                    safe_int(entry.get("gradeLevel"), 1),
                    entry.get("audioPath"),
                    frequency_json,
                    enrichment_json,
                    metadata_json,
                ),
            )
            word_db_id = cursor.lastrowid

            trans_batch = []
            all_trans_text = []
            for item in entry.get("translations", []) or entry.get(
                "wiktionary_translations", []
            ):
                if isinstance(item, str):
                    text = item
                    lang = "de"
                elif isinstance(item, dict):
                    text = item.get("word") or item.get("translation") or ""
                    lang = item.get("lang_code", "de")
                else:
                    continue
                if text:
                    trans_batch.append((word_db_id, lang, text))
                    all_trans_text.append(text)

            raw_examples = list(entry.get("exampleSentences", []) or [])
            raw_examples.extend(entry.get("examples", []) or [])
            if isinstance(entry.get("apiEnrichment"), dict):
                for ex in entry["apiEnrichment"].get("examples", []) or []:
                    if isinstance(ex, dict):
                        raw_examples.append(ex.get("text", ""))
                    else:
                        raw_examples.append(ex)

            seen_examples = set()
            ex_batch = []
            for ex in raw_examples:
                if isinstance(ex, str) and ex.strip() and ex.strip() not in seen_examples:
                    clean = ex.strip()
                    ex_batch.append((word_db_id, clean))
                    seen_examples.add(clean)

            if trans_batch:
                cursor.executemany(sql_insert_trans, trans_batch)
            if ex_batch:
                cursor.executemany(sql_insert_ex, ex_batch)
            cursor.execute(
                sql_insert_fts,
                (word_db_id, entry.get("word", ""), entry.get("lemma", ""), " ".join(all_trans_text)),
            )

        conn.commit()
        print(f"Inserted {total_count} words.")
    except Exception:
        conn.rollback()
        raise


def optimize_db(conn):
    cursor = conn.cursor()
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_word ON words(word)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_grade ON words(grade_level)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_original_id ON words(original_id)")
    conn.commit()
    cursor.execute("VACUUM")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default=INPUT_FILE)
    parser.add_argument("--output", default=DB_FILE)
    args = parser.parse_args()

    if os.path.exists(args.output):
        os.remove(args.output)

    conn = sqlite3.connect(args.output)
    try:
        conn.execute("PRAGMA journal_mode = MEMORY")
        conn.execute("PRAGMA synchronous = OFF")
        init_db_schema(conn.cursor())

        if not os.path.exists(args.input):
            print(f"Input file {args.input} not found.")
            return

        with open(args.input, "r", encoding="utf-8") as fh:
            data = json.load(fh)

        process_and_insert(conn, data)
        create_triggers(conn.cursor())
        optimize_db(conn)
        print(f"Done: {os.path.abspath(args.output)}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
