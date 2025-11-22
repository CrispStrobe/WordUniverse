import json
import sqlite3
import os
import sys

# Configuration
INPUT_FILE = 'grundwortschatz_v24_with_thesaurus.json'
DB_FILE = 'grundwortschatz.db'

# --- TYPE SAFETY HELPERS ---
def safe_int(value, default=0):
    """Robustly converts any value to int, handling strings like '1.0' or '5'."""
    try:
        if value is None: return default
        if isinstance(value, (int, float)): return int(value)
        if isinstance(value, str):
            value = value.strip()
            if not value: return default
            if '.' in value: return int(float(value))
            return int(value)
        return default
    except (ValueError, TypeError):
        return default

def safe_float(value, default=0.0):
    """Robustly converts any value to float."""
    try:
        if value is None: return default
        return float(value)
    except (ValueError, TypeError):
        return default

# --- DATABASE OPERATIONS ---
def init_db_schema(cursor):
    print("🛠️  Creating Database Schema...")
    
    # Enable Foreign Keys
    cursor.execute("PRAGMA foreign_keys = ON;")

    # 1. Main Words Table
    cursor.execute('''
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
    ''')

    # 2. Translations Table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS translations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER NOT NULL,
        lang_code TEXT,
        translation TEXT,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    )
    ''')

    # 3. Examples Table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS examples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER NOT NULL,
        sentence TEXT,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    )
    ''')

    # 4. Full Text Search (FTS5)
    cursor.execute('CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(word, lemma, translations, content=words, content_rowid=id)')

def create_triggers(cursor):
    """
    Adds Triggers to keep FTS index in sync if the App updates the DB later.
    Ref: https://sqlite.org/fts5.html#external_content_tables
    """
    print("⚙️  Creating FTS Triggers for future updates...")
    
    # Trigger: INSERT
    cursor.execute('''
    CREATE TRIGGER IF NOT EXISTS words_ai AFTER INSERT ON words BEGIN
      INSERT INTO search_index(rowid, word, lemma, translations) 
      VALUES (new.id, new.word, new.lemma, ' '); 
    END;
    ''')
    
    # Trigger: DELETE
    cursor.execute('''
    CREATE TRIGGER IF NOT EXISTS words_ad AFTER DELETE ON words BEGIN
      INSERT INTO search_index(search_index, rowid, word, lemma, translations) 
      VALUES('delete', old.id, old.word, old.lemma, ' ');
    END;
    ''')
    
    # Trigger: UPDATE
    cursor.execute('''
    CREATE TRIGGER IF NOT EXISTS words_au AFTER UPDATE ON words BEGIN
      INSERT INTO search_index(search_index, rowid, word, lemma, translations) 
      VALUES('delete', old.id, old.word, old.lemma, ' ');
      INSERT INTO search_index(rowid, word, lemma, translations) 
      VALUES (new.id, new.word, new.lemma, ' ');
    END;
    ''')

def process_and_insert(conn, data):
    print("🚀 Processing and Inserting Data...")
    cursor = conn.cursor()
    vocabulary = data.get('vocabulary', [])
    total_count = len(vocabulary)
    
    # PREPARED STATEMENTS (Optimization)
    sql_insert_word = '''
        INSERT INTO words (original_id, word, lemma, article, genus, word_type, grade_level, audio_path, frequency_json, enrichment_json, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    '''
    sql_insert_trans = 'INSERT INTO translations (word_id, lang_code, translation) VALUES (?, ?, ?)'
    sql_insert_ex = 'INSERT INTO examples (word_id, sentence) VALUES (?, ?)'
    sql_insert_fts = 'INSERT INTO search_index (rowid, word, lemma, translations) VALUES (?, ?, ?, ?)'

    # Start a single TRANSACTION for massive speedup
    cursor.execute("BEGIN TRANSACTION")

    try:
        for index, entry in enumerate(vocabulary):
            if index % 1000 == 0:
                print(f"   ... processed {index}/{total_count} words")

            # --- 1. PREPARE WORD DATA ---
            # Extract main fields
            original_id = entry.get('id')
            word = entry.get('word', '')
            lemma = entry.get('lemma', '')
            article = entry.get('article')
            genus = entry.get('genus')
            word_type = entry.get('wordType')
            grade_level = safe_int(entry.get('gradeLevel'), 1) # Safety Fix
            audio_path = entry.get('audioPath')

            # Prepare JSON Blobs
            frequency_data = entry.get('frequencyData')
            frequency_json = json.dumps(frequency_data) if frequency_data else None

            # Deep Clean Enrichment (Recursively clean numbers in blobs)
            api_enrichment = entry.get('apiEnrichment')
            if api_enrichment:
                if 'conceptnet' in api_enrichment:
                    for c in api_enrichment['conceptnet']:
                        c['weight'] = safe_float(c.get('weight'))
                # Add OpenThesaurus checks if needed here
            
            enrichment_json = json.dumps(api_enrichment) if api_enrichment else None

            # Prepare Metadata (Clean generic fields)
            meta_copy = entry.copy()
            if 'spellingDifficulty' in meta_copy:
                meta_copy['spellingDifficulty'] = safe_int(meta_copy['spellingDifficulty'], 0)
            if 'averageRank' in meta_copy:
                meta_copy['averageRank'] = safe_float(meta_copy['averageRank'])
            
            # Remove fields that are now their own columns
            keys_to_remove = [
                'id', 'word', 'lemma', 'article', 'genus', 'wordType', 'gradeLevel', 
                'audioPath', 'frequencyData', 'apiEnrichment', 
                'translations', 'wiktionary_translations', 'exampleSentences'
            ]
            for k in keys_to_remove:
                meta_copy.pop(k, None)
            
            metadata_json = json.dumps(meta_copy)

            # --- 2. INSERT WORD (Get ID) ---
            cursor.execute(sql_insert_word, (
                original_id, word, lemma, article, genus, word_type, 
                grade_level, audio_path, frequency_json, enrichment_json, metadata_json
            ))
            word_db_id = cursor.lastrowid

            # --- 3. PREPARE CHILDREN (Translations) ---
            # Merge old string format and new object format
            raw_translations = entry.get('translations', []) or entry.get('wiktionary_translations', [])
            trans_batch = []
            all_trans_text = [] # For FTS

            for t in raw_translations:
                t_text = ""
                t_lang = "en"
                
                if isinstance(t, str):
                    t_text = t
                elif isinstance(t, dict):
                    t_text = t.get('word', '')
                    t_lang = t.get('lang_code', 'en')

                if t_text:
                    trans_batch.append((word_db_id, t_lang, t_text))
                    all_trans_text.append(t_text)

            # --- 4. PREPARE CHILDREN (Examples) ---
            raw_examples = entry.get('exampleSentences', [])
            # Merge enriched examples
            if api_enrichment and 'examples' in api_enrichment:
                for ex in api_enrichment['examples']:
                    if isinstance(ex, dict) and 'text' in ex:
                        raw_examples.append(ex['text'])
            
            # Deduplicate and clean
            ex_batch = []
            seen_ex = set()
            for ex in raw_examples:
                if isinstance(ex, str) and ex.strip():
                    clean_ex = ex.strip()
                    if clean_ex not in seen_ex:
                        ex_batch.append((word_db_id, clean_ex))
                        seen_ex.add(clean_ex)

            # --- 5. BULK INSERT CHILDREN ---
            # executemany is much faster than looping execute
            if trans_batch:
                cursor.executemany(sql_insert_trans, trans_batch)
            if ex_batch:
                cursor.executemany(sql_insert_ex, ex_batch)

            # --- 6. INSERT INTO SEARCH INDEX ---
            # Manual population for the static build is faster/safer than relying on triggers during bulk load
            trans_blob = " ".join(all_trans_text)
            cursor.execute(sql_insert_fts, (word_db_id, word, lemma, trans_blob))

        # Commit everything at once
        conn.commit()
        print(f"✅ Successfully inserted {total_count} words.")

    except Exception as e:
        conn.rollback()
        print(f"❌ Error during insertion: {e}")
        raise e

def optimize_db(conn):
    print("🧹 Optimizing Database (Indexing & Vacuuming)...")
    cursor = conn.cursor()
    # Create indices for fast lookups in the App
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_word ON words(word)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_grade ON words(grade_level)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_original_id ON words(original_id)')
    
    conn.commit()
    cursor.execute('VACUUM')

def main():
    # 1. Remove old DB
    if os.path.exists(DB_FILE):
        try:
            os.remove(DB_FILE)
        except PermissionError:
            print(f"❌ Error: Cannot delete {DB_FILE}. Is it open in another program?")
            return

    # 2. Connect
    try:
        conn = sqlite3.connect(DB_FILE)
        # Performance optimizations for bulk loading
        conn.execute('PRAGMA journal_mode = MEMORY') 
        conn.execute('PRAGMA synchronous = OFF')
        
        # 3. Run Pipeline
        init_db_schema(conn.cursor())
        
        if not os.path.exists(INPUT_FILE):
            print(f"❌ Input file {INPUT_FILE} not found!")
            return

        with open(INPUT_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        process_and_insert(conn, data)
        create_triggers(conn.cursor()) # Add triggers AFTER bulk insert
        optimize_db(conn)
        
        print("---------------------------------------------------")
        print(f"🎉 Done! Database created at: {os.path.abspath(DB_FILE)}")
        print("⚠️  NEXT STEP: Copy this file to 'assets/grundwortschatz.db' in your Flutter project.")
        print("---------------------------------------------------")
        
    except Exception as e:
        print(f"\n❌ Critical Script Error: {e}")
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    main()