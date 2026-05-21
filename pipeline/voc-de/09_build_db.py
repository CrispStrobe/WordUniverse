import json
import sqlite3
import os
from typing import Dict, Any, List

# --- Configuration ---
JSON_FILE = 'grundwortschatz_enriched_final.json'
DB_FILE = 'grundwortschatz.sqlite'
# ---------------------

try:
    from tqdm import tqdm
    print("Progress bar enabled (tqdm found).")
except ImportError:
    print("Note: Install 'tqdm' for progress bars.")
    def tqdm(iterable, **kwargs):
        return iterable

def create_tables(conn: sqlite3.Connection):
    """
    Creates the normalized database schema.
    We use ON DELETE CASCADE so that if a word is deleted,
    all its related data is automatically cleaned up.
    """
    cursor = conn.cursor()
    
    # Enable foreign key support
    cursor.execute("PRAGMA foreign_keys = ON;")
    
    # --- Main 'words' Table ---
    # Stores the primary, one-to-one information for each word.
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS words (
        id TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        wordType TEXT,
        primary_pos TEXT,
        primary_lemma TEXT,
        inflections_pattern_json TEXT 
    );
    """)
    
    # --- One-to-Many Tables ---
    
    # Grapheme variations
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS grapheme_variations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        variation TEXT NOT NULL,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)

    # Definitions
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS definitions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        definition TEXT NOT NULL,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)
    
    # Inflections (Wiktionary list)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS inflections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        inflection TEXT NOT NULL,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)
    
    # Examples
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS examples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        example_text TEXT NOT NULL,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)

    # Synonyms (Wiktionary)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS synonyms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        synonym TEXT NOT NULL,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)

    # Antonyms (Wiktionary)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS antonyms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        antonym TEXT NOT NULL,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)

    # --- One-to-Many (Complex Objects) ---

    # Pronunciation
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS pronunciation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        ipa TEXT,
        audio_url TEXT,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)

    # ConceptNet Relations
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS conceptnet_relations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        relation TEXT,
        target TEXT,
        weight REAL,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)
    
    # Alternative Analyses
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS alternative_analyses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        pos TEXT,
        lemma TEXT,
        definition TEXT,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)

    # --- Multi-Table Normalization for OdeNet Senses ---
    # This is the most complex part. A word has multiple senses.
    # Each sense has its own synonyms and antonyms.
    # We need 3 tables to model this relation.
    
    # 1. The Senses (linked to the word)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS odenet_senses (
        sense_id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        definition TEXT,
        FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
    );
    """)
    
    # 2. Synonyms for each sense
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS odenet_synonyms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sense_id INTEGER NOT NULL,
        synonym TEXT NOT NULL,
        FOREIGN KEY(sense_id) REFERENCES odenet_senses(sense_id) ON DELETE CASCADE
    );
    """)
    
    # 3. Antonyms for each sense
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS odenet_antonyms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sense_id INTEGER NOT NULL,
        antonym TEXT NOT NULL,
        FOREIGN KEY(sense_id) REFERENCES odenet_senses(sense_id) ON DELETE CASCADE
    );
    """)
    
    conn.commit()

def process_json(conn: sqlite3.Connection, vocabulary: List[Dict[str, Any]]):
    """
    Iterates through the vocabulary and inserts data into the
    normalized database tables.
    """
    cursor = conn.cursor()
    
    for word_obj in tqdm(vocabulary, desc="Inserting data"):
        word_id = word_obj.get('id')
        if not word_id:
            continue
            
        enrichment = word_obj.get('apiEnrichment', {})
        
        # --- 1. Insert into 'words' table ---
        inflections_pattern = enrichment.get('inflections_pattern')
        inflections_json = json.dumps(inflections_pattern) if inflections_pattern else None
        
        cursor.execute("""
        INSERT INTO words (id, word, wordType, primary_pos, primary_lemma, inflections_pattern_json)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO NOTHING;
        """, (
            word_id,
            word_obj.get('word'),
            word_obj.get('wordType'),
            enrichment.get('primary_pos'),
            enrichment.get('primary_lemma'),
            inflections_json
        ))
        
        # --- 2. Insert into one-to-many list tables ---
        
        # Grapheme Variations
        variations = word_obj.get('graphemeVariations', [])
        if variations:
            cursor.executemany("""
            INSERT INTO grapheme_variations (word_id, variation) VALUES (?, ?)
            """, [(word_id, v) for v in variations])

        # Definitions
        definitions = enrichment.get('definitions', [])
        if definitions:
            cursor.executemany("""
            INSERT INTO definitions (word_id, definition) VALUES (?, ?)
            """, [(word_id, d) for d in definitions])

        # Inflections
        inflections = enrichment.get('inflections', [])
        if inflections:
            cursor.executemany("""
            INSERT INTO inflections (word_id, inflection) VALUES (?, ?)
            """, [(word_id, i) for i in inflections])

        # Examples
        examples = enrichment.get('examples', [])
        if examples:
            cursor.executemany("""
            INSERT INTO examples (word_id, example_text) VALUES (?, ?)
            """, [(word_id, e) for e in examples])

        # Synonyms
        synonyms = enrichment.get('synonyms', [])
        if synonyms:
            cursor.executemany("""
            INSERT INTO synonyms (word_id, synonym) VALUES (?, ?)
            """, [(word_id, s) for s in synonyms])
        
        # Antonyms
        antonyms = enrichment.get('antonyms', [])
        if antonyms:
            cursor.executemany("""
            INSERT INTO antonyms (word_id, antonym) VALUES (?, ?)
            """, [(word_id, a) for a in antonyms])

        # --- 3. Insert into complex object tables ---

        # Pronunciation
        for p in enrichment.get('pronunciation', []):
            cursor.execute("""
            INSERT INTO pronunciation (word_id, ipa, audio_url) VALUES (?, ?, ?)
            """, (word_id, p.get('ipa'), p.get('audio')))

        # ConceptNet
        for r in enrichment.get('conceptnet', []):
            cursor.execute("""
            INSERT INTO conceptnet_relations (word_id, relation, target, weight) 
            VALUES (?, ?, ?, ?)
            """, (word_id, r.get('relation'), r.get('target'), r.get('weight')))

        # Alternative Analyses
        for a in enrichment.get('alternative_analyses', []):
            cursor.execute("""
            INSERT INTO alternative_analyses (word_id, pos, lemma, definition) 
            VALUES (?, ?, ?, ?)
            """, (word_id, a.get('pos'), a.get('lemma'), a.get('definition')))
            
        # --- 4. Handle OdeNet Senses (multi-table) ---
        for sense in enrichment.get('semantic_relations', []):
            # Insert the sense itself
            cursor.execute("""
            INSERT INTO odenet_senses (word_id, definition) VALUES (?, ?)
            """, (word_id, sense.get('definition')))
            
            sense_id = cursor.lastrowid
            
            # Insert synonyms for this sense
            sense_syns = sense.get('synonyms', [])
            if sense_syns:
                cursor.executemany("""
                INSERT INTO odenet_synonyms (sense_id, synonym) VALUES (?, ?)
                """, [(sense_id, s) for s in sense_syns])

            # Insert antonyms for this sense
            sense_ants = sense.get('antonyms', [])
            if sense_ants:
                cursor.executemany("""
                INSERT INTO odenet_antonyms (sense_id, antonym) VALUES (?, ?)
                """, [(sense_id, a) for a in sense_ants])

def create_indexes(conn: sqlite3.Connection):
    """
    Creates indexes on common search columns and all foreign keys
    to speed up queries.
    """
    cursor = conn.cursor()
    
    print("Creating indexes... (this may take a moment)")
    
    # --- Indexes for main 'words' table ---
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_words_word ON words(word);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_words_lemma ON words(primary_lemma);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_words_wordType ON words(wordType);")
    
    # --- Indexes for Foreign Keys (CRITICAL for JOIN performance) ---
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_variations_word_id ON grapheme_variations(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_definitions_word_id ON definitions(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_inflections_word_id ON inflections(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_examples_word_id ON examples(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_synonyms_word_id ON synonyms(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_antonyms_word_id ON antonyms(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_pronunciation_word_id ON pronunciation(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_conceptnet_word_id ON conceptnet_relations(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_alternatives_word_id ON alternative_analyses(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_odenet_senses_word_id ON odenet_senses(word_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_odenet_synonyms_sense_id ON odenet_synonyms(sense_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_odenet_antonyms_sense_id ON odenet_antonyms(sense_id);")
    
    # --- Indexes for common search values ---
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_variations_variation ON grapheme_variations(variation);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_synonyms_synonym ON synonyms(synonym);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_antonyms_antonym ON antonyms(antonym);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_conceptnet_target ON conceptnet_relations(target);")

    conn.commit()

def main():
    if not os.path.exists(JSON_FILE):
        print(f"Error: Input file '{JSON_FILE}' not found.")
        return

    # Delete old DB file to start fresh
    if os.path.exists(DB_FILE):
        print(f"Removing old database '{DB_FILE}'...")
        os.remove(DB_FILE)

    conn = None
    try:
        print(f"Loading '{JSON_FILE}'... (this can take a while)")
        with open(JSON_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        vocabulary = data.get('vocabulary', [])
        if not vocabulary:
            print("Error: No 'vocabulary' key found in JSON.")
            return
            
        print(f"Loaded {len(vocabulary)} word entries.")
        
        conn = sqlite3.connect(DB_FILE)
        
        # Set performance pragmas
        conn.execute("PRAGMA journal_mode = WAL;")
        conn.execute("PRAGMA synchronous = NORMAL;")
        
        print("Creating database schema...")
        create_tables(conn)
        
        print("Starting transaction...")
        conn.execute("BEGIN;")
        
        process_json(conn, vocabulary)
        
        print("Committing data... (this is the main save operation)")
        conn.commit()
        
        create_indexes(conn)
        
        print("\n" + "="*70)
        print("✨ Database build complete!")
        print(f"✓ Successfully created and indexed '{DB_FILE}'")
        print("="*70)

    except json.JSONDecodeError:
        print(f"Error: Could not decode '{JSON_FILE}'. Is it valid JSON?")
    except sqlite3.Error as e:
        print(f"An SQLite error occurred: {e}")
        if conn:
            conn.rollback()
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        if conn:
            conn.rollback()
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    main()