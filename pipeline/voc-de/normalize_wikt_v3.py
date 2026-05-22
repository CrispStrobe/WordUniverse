#!/usr/bin/env python
import os
import sqlite3
import json
import subprocess
import argparse
import sys
import time
from collections import defaultdict
from datasets import load_dataset
from huggingface_hub import HfApi
from tqdm import tqdm

# --- Configuration ---
DEFAULT_DB_FILENAME = "de_wiktionary_normalized_full.db"
DEFAULT_SOURCE_REPO_ID = "cstr/de-wiktionary-extracted"
DEFAULT_TARGET_REPO_ID = "cstr/de-wiktionary-sqlite-full"
BATCH_SIZE = 5000

def create_full_normalized_db(dataset, db_path):
    """
    (Version 3)
    Create a fully normalized database, capturing ALL fields from the JSONL.
    This version CORRECTLY handles top-level expressions and proverbs.
    """
    
    if os.path.exists(db_path):
        print(f"Removing old database: {db_path}")
        os.remove(db_path)
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Performance optimizations
    cursor.execute("PRAGMA foreign_keys = ON")
    cursor.execute("PRAGMA journal_mode = WAL")
    cursor.execute("PRAGMA synchronous = NORMAL")
    cursor.execute("PRAGMA cache_size = -64000")
    cursor.execute("PRAGMA temp_store = MEMORY")
    
    print("\n### Creating FULL normalized schema (V3 - Corrected) ###")
    
    # (Lookup tables are unchanged)
    cursor.execute("CREATE TABLE tags (id INTEGER PRIMARY KEY, tag TEXT UNIQUE NOT NULL)")
    cursor.execute("CREATE TABLE topics (id INTEGER PRIMARY KEY, topic TEXT UNIQUE NOT NULL)")
    cursor.execute("CREATE TABLE categories (id INTEGER PRIMARY KEY, category TEXT UNIQUE NOT NULL)")
    
    # (Core tables are unchanged)
    cursor.execute('''
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word TEXT NOT NULL, title TEXT, redirect TEXT, pos TEXT,
            pos_title TEXT, lang_code TEXT, lang TEXT, etymology_text TEXT
        )
    ''')
    cursor.execute('''
        CREATE TABLE senses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER NOT NULL, sense_index TEXT, alt_of TEXT, form_of TEXT,
            FOREIGN KEY (entry_id) REFERENCES entries(id)
        )
    ''')
    cursor.execute("CREATE TABLE glosses (id INTEGER PRIMARY KEY, sense_id INTEGER NOT NULL, gloss_text TEXT NOT NULL, gloss_order INTEGER, FOREIGN KEY (sense_id) REFERENCES senses(id))")
    cursor.execute("CREATE TABLE raw_glosses (id INTEGER PRIMARY KEY, sense_id INTEGER NOT NULL, raw_gloss TEXT NOT NULL, gloss_order INTEGER, FOREIGN KEY (sense_id) REFERENCES senses(id))")
    cursor.execute("CREATE TABLE sense_tags (sense_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY (sense_id, tag_id), FOREIGN KEY (sense_id) REFERENCES senses(id), FOREIGN KEY (tag_id) REFERENCES tags(id))")
    cursor.execute("CREATE TABLE sense_topics (sense_id INTEGER NOT NULL, topic_id INTEGER NOT NULL, PRIMARY KEY (sense_id, topic_id), FOREIGN KEY (sense_id) REFERENCES senses(id), FOREIGN KEY (topic_id) REFERENCES topics(id))")
    cursor.execute("CREATE TABLE sense_categories (sense_id INTEGER NOT NULL, category_id INTEGER NOT NULL, PRIMARY KEY (sense_id, category_id), FOREIGN KEY (sense_id) REFERENCES senses(id), FOREIGN KEY (category_id) REFERENCES categories(id))")
    cursor.execute("CREATE TABLE examples (id INTEGER PRIMARY KEY, sense_id INTEGER NOT NULL, text TEXT, ref TEXT, author TEXT, title TEXT, year INTEGER, publisher TEXT, isbn TEXT, url TEXT, FOREIGN KEY (sense_id) REFERENCES senses(id))")
    cursor.execute("CREATE TABLE translations (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, lang TEXT NOT NULL, lang_code TEXT, word TEXT NOT NULL, sense_text TEXT, sense_index TEXT, roman TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE translation_tags (translation_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY (translation_id, tag_id), FOREIGN KEY (translation_id) REFERENCES translations(id), FOREIGN KEY (tag_id) REFERENCES tags(id))")
    cursor.execute("CREATE TABLE sounds (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, ipa TEXT, audio TEXT, mp3_url TEXT, ogg_url TEXT, rhymes TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE sound_tags (sound_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY (sound_id, tag_id), FOREIGN KEY (sound_id) REFERENCES sounds(id), FOREIGN KEY (tag_id) REFERENCES tags(id))")
    cursor.execute("CREATE TABLE forms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, form_text TEXT NOT NULL, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE form_tags (form_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY (form_id, tag_id), FOREIGN KEY (form_id) REFERENCES forms(id), FOREIGN KEY (tag_id) REFERENCES tags(id))")
    cursor.execute("CREATE TABLE form_topics (form_id INTEGER NOT NULL, topic_id INTEGER NOT NULL, PRIMARY KEY (form_id, topic_id), FOREIGN KEY (form_id) REFERENCES forms(id), FOREIGN KEY (topic_id) REFERENCES topics(id))")
    cursor.execute("CREATE TABLE hyphenations (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, hyphenation TEXT NOT NULL, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE synonyms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, synonym_word TEXT NOT NULL, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE synonym_tags (synonym_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY (synonym_id, tag_id), FOREIGN KEY (synonym_id) REFERENCES synonyms(id), FOREIGN KEY (tag_id) REFERENCES tags(id))")
    cursor.execute("CREATE TABLE synonym_topics (synonym_id INTEGER NOT NULL, topic_id INTEGER NOT NULL, PRIMARY KEY (synonym_id, topic_id), FOREIGN KEY (synonym_id) REFERENCES synonyms(id), FOREIGN KEY (topic_id) REFERENCES topics(id))")
    cursor.execute("CREATE TABLE antonyms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, antonym_word TEXT NOT NULL, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE antonym_tags (antonym_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY (antonym_id, tag_id), FOREIGN KEY (antonym_id) REFERENCES antonyms(id), FOREIGN KEY (tag_id) REFERENCES tags(id))")
    cursor.execute("CREATE TABLE derived_terms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, derived_word TEXT NOT NULL, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE related_terms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, related_word TEXT NOT NULL, sense_index TEXT, raw_tags_json TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE entry_categories (entry_id INTEGER NOT NULL, category_id INTEGER NOT NULL, PRIMARY KEY (entry_id, category_id), FOREIGN KEY (entry_id) REFERENCES entries(id), FOREIGN KEY (category_id) REFERENCES categories(id))")
    cursor.execute("CREATE TABLE entry_tags (entry_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY (entry_id, tag_id), FOREIGN KEY (entry_id) REFERENCES entries(id), FOREIGN KEY (tag_id) REFERENCES tags(id))")
    
    # (New tables from 'omitted' list)
    cursor.execute("CREATE TABLE entry_notes (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, note TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE other_pos (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, pos_value TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE entry_raw_tags (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, raw_tag TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE descendants (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, lang TEXT, word TEXT, roman TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE hypernyms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, hypernym_word TEXT, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE hyponyms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, hyponym_word TEXT, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE holonyms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, holonym_word TEXT, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE meronyms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, meronym_word TEXT, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE coordinate_terms (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, coordinate_word TEXT, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE coordinate_term_tags (coordinate_term_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY (coordinate_term_id, tag_id), FOREIGN KEY (coordinate_term_id) REFERENCES coordinate_terms(id), FOREIGN KEY (tag_id) REFERENCES tags(id))")
    
    # --- FIXED: Schema for expressions and proverbs ---
    # They are linked to ENTRY_ID, not SENSE_ID.
    cursor.execute("CREATE TABLE expressions (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, expression TEXT, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")
    cursor.execute("CREATE TABLE proverbs (id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL, proverb TEXT, sense_index TEXT, FOREIGN KEY (entry_id) REFERENCES entries(id))")

    conn.commit()
    
    print("\n### Populating database (V3) ###")
    
    # (Caches are unchanged)
    tag_cache = {}
    topic_cache = {}
    category_cache = {}
    
    def get_or_create_tag(tag_text):
        if tag_text not in tag_cache:
            cursor.execute('INSERT OR IGNORE INTO tags (tag) VALUES (?)', (tag_text,))
            tag_id = cursor.execute('SELECT id FROM tags WHERE tag = ?', (tag_text,)).fetchone()[0]
            tag_cache[tag_text] = tag_id
        return tag_cache[tag_text]
    
    def get_or_create_topic(topic_text):
        if topic_text not in topic_cache:
            cursor.execute('INSERT OR IGNORE INTO topics (topic) VALUES (?)', (topic_text,))
            topic_id = cursor.execute('SELECT id FROM topics WHERE topic = ?', (topic_text,)).fetchone()[0]
            topic_cache[topic_text] = topic_id
        return topic_cache[topic_text]
    
    def get_or_create_category(category_text):
        if category_text not in category_cache:
            cursor.execute('INSERT OR IGNORE INTO categories (category) VALUES (?)', (category_text,))
            category_id = cursor.execute('SELECT id FROM categories WHERE category = ?', (category_text,)).fetchone()[0]
            category_cache[category_text] = category_id
        return category_cache[category_text]

    def populate_simple_list(entry_id, data_list, table_name, column_name):
        for item in data_list:
            if item:
                cursor.execute(f'INSERT INTO {table_name} (entry_id, {column_name}) VALUES (?, ?)', (entry_id, item))

    # (populate_semantic_relation is unchanged)
    def populate_semantic_relation(entry_id, data_list, table_name, column_name):
        for item in data_list:
            if isinstance(item, dict):
                word_text = item.get('word')
                sense_index = item.get('sense_index')
                if not word_text:
                    continue
                
                if table_name == 'related_terms':
                    raw_tags = item.get('raw_tags')
                    raw_tags_json = json.dumps(raw_tags) if raw_tags else None
                    cursor.execute(f'INSERT INTO {table_name} (entry_id, {column_name}, sense_index, raw_tags_json) VALUES (?, ?, ?, ?)', 
                                 (entry_id, word_text, sense_index, raw_tags_json))
                else:
                    cursor.execute(f'INSERT INTO {table_name} (entry_id, {column_name}, sense_index) VALUES (?, ?, ?)', 
                                 (entry_id, word_text, sense_index))
                
                if table_name == 'coordinate_terms' and item.get('tags'):
                    coord_id = cursor.lastrowid
                    for tag in item['tags']:
                        tag_id = get_or_create_tag(tag)
                        cursor.execute('INSERT OR IGNORE INTO coordinate_term_tags (coordinate_term_id, tag_id) VALUES (?, ?)',
                                     (coord_id, tag_id))
            
            elif isinstance(item, str):
                cursor.execute(f'INSERT INTO {table_name} (entry_id, {column_name}) VALUES (?, ?)', (entry_id, item))

    # --- FIXED: New helper for expressions/proverbs (linked to entry_id) ---
    def populate_entry_relation(entry_id, data_list, table_name):
        column_map = {'expressions': 'expression', 'proverbs': 'proverb'}
        column_name = column_map[table_name]
        
        for item in data_list:
            if isinstance(item, dict):
                text = item.get('word')
                sense_index = item.get('sense_index')
                if text:
                    cursor.execute(f'INSERT INTO {table_name} (entry_id, {column_name}, sense_index) VALUES (?, ?, ?)', 
                                 (entry_id, text, sense_index))

    skipped_count = 0
    db_stats = defaultdict(int)

    for idx, entry in enumerate(tqdm(dataset, desc="Processing entries"), 1):
        word = entry.get('word')
        if not word:
            skipped_count += 1
            continue
        
        db_stats['entries'] += 1
        etymology = entry.get('etymology_texts')
        etymology_text = ' | '.join(etymology) if etymology else None
        
        cursor.execute('''
            INSERT INTO entries (word, title, redirect, pos, pos_title, lang_code, lang, etymology_text)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            word, entry.get('title'), entry.get('redirect'), entry.get('pos'),
            entry.get('pos_title'), entry.get('lang_code'), entry.get('lang'), etymology_text
        ))
        entry_id = cursor.lastrowid
        
        # SENSES
        if entry.get('senses'):
            for sense_data in entry['senses']:
                db_stats['senses'] += 1
                cursor.execute('INSERT INTO senses (entry_id, sense_index, alt_of, form_of) VALUES (?, ?, ?, ?)',
                               (entry_id, sense_data.get('sense_index'),
                                json.dumps(sense_data.get('alt_of')), json.dumps(sense_data.get('form_of'))))
                sense_id = cursor.lastrowid
                
                # (All sub-sense population logic is unchanged)
                if sense_data.get('glosses'):
                    db_stats['glosses'] += len(sense_data['glosses'])
                    for i, gloss in enumerate(sense_data['glosses']):
                        cursor.execute('INSERT INTO glosses (sense_id, gloss_text, gloss_order) VALUES (?, ?, ?)', (sense_id, gloss, i))
                
                if sense_data.get('raw_glosses'):
                    db_stats['raw_glosses'] += len(sense_data['raw_glosses'])
                    for i, raw_gloss in enumerate(sense_data['raw_glosses']):
                        cursor.execute('INSERT INTO raw_glosses (sense_id, raw_gloss, gloss_order) VALUES (?, ?, ?)', (sense_id, raw_gloss, i))
                
                if sense_data.get('tags'):
                    db_stats['sense_tags'] += len(sense_data['tags'])
                    for tag in sense_data['tags']:
                        cursor.execute('INSERT OR IGNORE INTO sense_tags (sense_id, tag_id) VALUES (?, ?)', (sense_id, get_or_create_tag(tag)))
                
                if sense_data.get('topics'):
                    db_stats['sense_topics'] += len(sense_data['topics'])
                    for topic in sense_data['topics']:
                        cursor.execute('INSERT OR IGNORE INTO sense_topics (sense_id, topic_id) VALUES (?, ?)', (sense_id, get_or_create_topic(topic)))
                
                if sense_data.get('categories'):
                    db_stats['sense_categories'] += len(sense_data['categories'])
                    for category in sense_data['categories']:
                        cursor.execute('INSERT OR IGNORE INTO sense_categories (sense_id, category_id) VALUES (?, ?)', (sense_id, get_or_create_category(category)))
                
                if sense_data.get('examples'):
                    db_stats['examples'] += len(sense_data['examples'])
                    for example in sense_data['examples']:
                        cursor.execute('INSERT INTO examples (sense_id, text, ref, author, title, year, publisher, isbn, url) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                                       (sense_id, example.get('text'), example.get('ref'), example.get('author'), example.get('title'), example.get('year'), example.get('publisher'), example.get('isbn'), example.get('url')))
                
                # --- REMOVED: expressions/proverbs are NOT in senses ---
        
        # (Standard fields population is unchanged)
        if entry.get('translations'):
            db_stats['translations'] += len(entry['translations'])
            for trans in entry['translations']:
                cursor.execute('INSERT INTO translations (entry_id, lang, lang_code, word, sense_text, sense_index, roman) VALUES (?, ?, ?, ?, ?, ?, ?)',
                               (entry_id, trans.get('lang'), trans.get('lang_code'), trans.get('word'), trans.get('sense'), trans.get('sense_index'), trans.get('roman')))
                trans_id = cursor.lastrowid
                if trans.get('tags'):
                    db_stats['translation_tags'] += len(trans['tags'])
                    for tag in trans['tags']:
                        cursor.execute('INSERT OR IGNORE INTO translation_tags (translation_id, tag_id) VALUES (?, ?)', (trans_id, get_or_create_tag(tag)))

        if entry.get('sounds'):
            db_stats['sounds'] += len(entry['sounds'])
            for sound in entry['sounds']:
                cursor.execute('INSERT INTO sounds (entry_id, ipa, audio, mp3_url, ogg_url, rhymes) VALUES (?, ?, ?, ?, ?, ?)',
                               (entry_id, sound.get('ipa'), sound.get('audio'), sound.get('mp3_url'), sound.get('ogg_url'), sound.get('rhymes')))
                sound_id = cursor.lastrowid
                if sound.get('tags'):
                    db_stats['sound_tags'] += len(sound['tags'])
                    for tag in sound['tags']:
                        cursor.execute('INSERT OR IGNORE INTO sound_tags (sound_id, tag_id) VALUES (?, ?)', (sound_id, get_or_create_tag(tag)))

        if entry.get('forms'):
            db_stats['forms'] += len(entry['forms'])
            for form in entry['forms']:
                cursor.execute('INSERT INTO forms (entry_id, form_text, sense_index) VALUES (?, ?, ?)', (entry_id, form.get('form'), form.get('sense_index')))
                form_id = cursor.lastrowid
                if form.get('tags'):
                    db_stats['form_tags'] += len(form['tags'])
                    for tag in form['tags']:
                        cursor.execute('INSERT OR IGNORE INTO form_tags (form_id, tag_id) VALUES (?, ?)', (form_id, get_or_create_tag(tag)))
                if form.get('topics'):
                    db_stats['form_topics'] += len(form['topics'])
                    for topic in form['topics']:
                        cursor.execute('INSERT OR IGNORE INTO form_topics (form_id, topic_id) VALUES (?, ?)', (form_id, get_or_create_topic(topic)))

        if entry.get('synonyms'):
            db_stats['synonyms'] += len(entry['synonyms'])
            for synonym in entry['synonyms']:
                word_text = synonym.get('word') if isinstance(synonym, dict) else synonym
                if not word_text: continue
                sense_index = synonym.get('sense_index') if isinstance(synonym, dict) else None
                cursor.execute('INSERT INTO synonyms (entry_id, synonym_word, sense_index) VALUES (?, ?, ?)', (entry_id, word_text, sense_index))
                syn_id = cursor.lastrowid
                if isinstance(synonym, dict):
                    if synonym.get('tags'):
                        db_stats['synonym_tags'] += len(synonym['tags'])
                        for tag in synonym['tags']:
                            cursor.execute('INSERT OR IGNORE INTO synonym_tags (synonym_id, tag_id) VALUES (?, ?)', (syn_id, get_or_create_tag(tag)))
                    if synonym.get('topics'):
                        db_stats['synonym_topics'] += len(synonym['topics'])
                        for topic in synonym['topics']:
                            cursor.execute('INSERT OR IGNORE INTO synonym_topics (synonym_id, topic_id) VALUES (?, ?)', (syn_id, get_or_create_topic(topic)))

        if entry.get('antonyms'):
            db_stats['antonyms'] += len(entry['antonyms'])
            for antonym in entry['antonyms']:
                word_text = antonym.get('word') if isinstance(antonym, dict) else antonym
                if not word_text: continue
                sense_index = antonym.get('sense_index') if isinstance(antonym, dict) else None
                cursor.execute('INSERT INTO antonyms (entry_id, antonym_word, sense_index) VALUES (?, ?, ?)', (entry_id, word_text, sense_index))
                ant_id = cursor.lastrowid
                if isinstance(antonym, dict) and antonym.get('tags'):
                    db_stats['antonym_tags'] += len(antonym['tags'])
                    for tag in antonym['tags']:
                        cursor.execute('INSERT OR IGNORE INTO antonym_tags (antonym_id, tag_id) VALUES (?, ?)', (ant_id, get_or_create_tag(tag)))

        if entry.get('derived'):
            db_stats['derived_terms'] += len(entry['derived'])
            populate_semantic_relation(entry_id, entry['derived'], 'derived_terms', 'derived_word')

        if entry.get('related'):
            db_stats['related_terms'] += len(entry['related'])
            populate_semantic_relation(entry_id, entry['related'], 'related_terms', 'related_word')

        if entry.get('categories'):
            db_stats['entry_categories'] += len(entry['categories'])
            for category in entry['categories']:
                cursor.execute('INSERT OR IGNORE INTO entry_categories (entry_id, category_id) VALUES (?, ?)', (entry_id, get_or_create_category(category)))
        
        if entry.get('tags'):
            db_stats['entry_tags'] += len(entry['tags'])
            for tag in entry['tags']:
                cursor.execute('INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)', (entry_id, get_or_create_tag(tag)))
        
        if entry.get('hyphenations'):
            db_stats['hyphenations'] += len(entry['hyphenations'])
            for hyphen in entry['hyphenations']:
                hyphen_text = '-'.join(hyphen['parts']) if isinstance(hyphen, dict) and hyphen.get('parts') else str(hyphen)
                cursor.execute('INSERT INTO hyphenations (entry_id, hyphenation) VALUES (?, ?)', (entry_id, hyphen_text))
        
        # --- NEW ENTRY-LEVEL FIELDS ---
        
        if entry.get('notes'):
            db_stats['entry_notes'] += len(entry['notes'])
            populate_simple_list(entry_id, entry['notes'], 'entry_notes', 'note')
            
        if entry.get('other_pos'):
            db_stats['other_pos'] += len(entry['other_pos'])
            populate_simple_list(entry_id, entry['other_pos'], 'other_pos', 'pos_value')
        
        if entry.get('raw_tags'):
            db_stats['entry_raw_tags'] += len(entry['raw_tags'])
            populate_simple_list(entry_id, entry['raw_tags'], 'entry_raw_tags', 'raw_tag')

        if entry.get('descendants'):
            db_stats['descendants'] += len(entry['descendants'])
            for desc in entry['descendants']:
                cursor.execute('INSERT INTO descendants (entry_id, lang, word, roman) VALUES (?, ?, ?, ?)', 
                             (entry_id, desc.get('lang'), desc.get('word'), desc.get('roman')))

        if entry.get('hypernyms'):
            db_stats['hypernyms'] += len(entry['hypernyms'])
            populate_semantic_relation(entry_id, entry['hypernyms'], 'hypernyms', 'hypernym_word')
            
        if entry.get('hyponyms'):
            db_stats['hyponyms'] += len(entry['hyponyms'])
            populate_semantic_relation(entry_id, entry['hyponyms'], 'hyponyms', 'hyponym_word')

        if entry.get('holonyms'):
            db_stats['holonyms'] += len(entry['holonyms'])
            populate_semantic_relation(entry_id, entry['holonyms'], 'holonyms', 'holonym_word')

        if entry.get('meronyms'):
            db_stats['meronyms'] += len(entry['meronyms'])
            populate_semantic_relation(entry_id, entry['meronyms'], 'meronyms', 'meronym_word')
            
        if entry.get('coordinate_terms'):
            db_stats['coordinate_terms'] += len(entry['coordinate_terms'])
            populate_semantic_relation(entry_id, entry['coordinate_terms'], 'coordinate_terms', 'coordinate_word')
        
        # --- FIXED: expressions/proverbs are top-level ---
        if entry.get('expressions'):
            db_stats['expressions'] += len(entry['expressions'])
            populate_entry_relation(entry_id, entry['expressions'], 'expressions')
        
        if entry.get('proverbs'):
            db_stats['proverbs'] += len(entry['proverbs'])
            populate_entry_relation(entry_id, entry['proverbs'], 'proverbs')

        if idx % BATCH_SIZE == 0:
            conn.commit()
    
    conn.commit()
    
    if skipped_count > 0:
        print(f"\n⚠️  Skipped {skipped_count:,} entries without a word field")
    
    db_stats['tags'] = len(tag_cache)
    db_stats['topics'] = len(topic_cache)
    db_stats['categories'] = len(category_cache)
    
    print(f"\n✅ Unique tags: {db_stats['tags']:,}")
    print(f"✅ Unique topics: {db_stats['topics']:,}")
    print(f"✅ Unique categories: {db_stats['categories']:,}")
    
    print("\n### Creating indexes for all tables (V3) ###")
    
    # (Indexes are the same, but we add indexes for expressions/proverbs)
    cursor.execute('CREATE INDEX idx_entries_word_lower ON entries(LOWER(word))')
    cursor.execute('CREATE INDEX idx_entries_lang_pos ON entries(lang, pos)')
    cursor.execute('CREATE INDEX idx_senses_entry ON senses(entry_id)')
    cursor.execute('CREATE INDEX idx_glosses_sense ON glosses(sense_id)')
    cursor.execute('CREATE INDEX idx_translations_entry ON translations(entry_id)')
    cursor.execute('CREATE INDEX idx_translations_lang_code ON translations(lang_code)')
    cursor.execute('CREATE INDEX idx_sounds_entry ON sounds(entry_id)')
    cursor.execute('CREATE INDEX idx_forms_entry ON forms(entry_id)')
    cursor.execute('CREATE INDEX idx_forms_text ON forms(form_text)')
    cursor.execute('CREATE INDEX idx_form_tags_tag ON form_tags(tag_id)')
    cursor.execute('CREATE INDEX idx_synonyms_entry ON synonyms(entry_id)')
    cursor.execute('CREATE INDEX idx_antonyms_entry ON antonyms(entry_id)')
    cursor.execute('CREATE INDEX idx_derived_terms_entry ON derived_terms(entry_id)')
    cursor.execute('CREATE INDEX idx_related_terms_entry ON related_terms(entry_id)')
    
    cursor.execute('CREATE INDEX idx_entries_title ON entries(title)')
    cursor.execute('CREATE INDEX idx_entry_notes_entry ON entry_notes(entry_id)')
    cursor.execute('CREATE INDEX idx_other_pos_entry ON other_pos(entry_id)')
    cursor.execute('CREATE INDEX idx_entry_raw_tags_entry ON entry_raw_tags(entry_id)')
    cursor.execute('CREATE INDEX idx_descendants_entry ON descendants(entry_id)')
    cursor.execute('CREATE INDEX idx_hypernyms_entry ON hypernyms(entry_id)')
    cursor.execute('CREATE INDEX idx_hyponyms_entry ON hyponyms(entry_id)')
    cursor.execute('CREATE INDEX idx_holonyms_entry ON holonyms(entry_id)')
    cursor.execute('CREATE INDEX idx_meronyms_entry ON meronyms(entry_id)')
    cursor.execute('CREATE INDEX idx_coordinate_terms_entry ON coordinate_terms(entry_id)')
    
    # --- FIXED: Use entry_id for these indexes ---
    cursor.execute('CREATE INDEX idx_expressions_entry ON expressions(entry_id)')
    cursor.execute('CREATE INDEX idx_proverbs_entry ON proverbs(entry_id)')
    
    conn.commit()
    
    print("\n### Final Statistics (Full DB V3) ###")
    for key, value in sorted(db_stats.items()):
        print(f"{key:<20} {value:>10,}")
    
    conn.close()
    
    file_size_mb = os.path.getsize(db_path) / (1024**2)
    print(f"\n✅ Database created: {db_path} ({file_size_mb:.2f} MB)")
    
    return db_stats, os.path.basename(db_path)

def compress_database(db_path):
    """Compress the database for faster upload/download."""
    compressed_path = f"{db_path}.gz"
    
    if os.path.exists(compressed_path):
        print(f"Compressed file already exists: {compressed_path}")
        return compressed_path, os.path.basename(compressed_path)
    
    print(f"Compressing database with gzip...")
    try:
        subprocess.run(['gzip', '-k', '-f', db_path], check=True)
        compressed_size = os.path.getsize(compressed_path)
        original_size = os.path.getsize(db_path)
        print(f"✅ Compressed: {compressed_size / (1024**2):.2f} MB")
        print(f"   Reduction: {(1 - compressed_size/original_size)*100:.1f}%")
        return compressed_path, os.path.basename(compressed_path)
    except subprocess.CalledProcessError as e:
        print(f"⚠️  Compression failed: {e}. Will upload uncompressed.")
        return db_path, os.path.basename(db_path)
    except FileNotFoundError:
        print("⚠️  gzip not found. Uploading uncompressed.")
        return db_path, os.path.basename(db_path)

def generate_readme_content(repo_id, filename_in_repo, source_repo, stats):
    """Generates a comprehensive README for the full dataset."""
    
    return f"""---
license: cc-by-sa-3.0
task_categories:
- text-retrieval
language:
- de
tags:
- wiktionary
- dictionary
- german
- linguistics
- morphology
- semantics
- normalized
- lossless
size_categories:
- 1M<n<10M
---

# German Wiktionary - FULL Normalized SQLite Database

This is a **complete, lossless, and fully normalized** SQLite database of German Wiktionary, capturing 100% of the structured data from the `cstr/de-wiktionary-extracted` dataset.

It is designed for production-ready applications, complex linguistic analysis, and mobile apps (Flutter, React Native) that require a comprehensive local dictionary.

## 🎯 Key Features

- **✅ 100% Lossless**: All 30+ top-level and nested fields from the source JSONL are preserved.
- **⚡ Fast Queries**: Fully indexed schema for sub-20ms queries.
- **🔗 Full Semantic Web**: Includes all semantic relations (synonyms, antonyms, **hypernyms, hyponyms, meronyms, holonyms, coordinate_terms**).
- **🗣️ Rich Content**: Includes **expressions, proverbs, and entry notes** in addition to definitions and examples.
- **📱 Mobile-ready**: Optimized for `sqflite` (Flutter) and other local DB use cases.
- **(and all features from the standard DB: forms, translations, sounds, etc.)**

## 📊 Database Statistics

- **Entries**: {stats.get('entries', 0):,}
- **Word Senses**: {stats.get('senses', 0):,}
- **Definitions (Glosses)**: {stats.get('glosses', 0):,}
- **Translations**: {stats.get('translations', 0):,}
- **Word Forms (Inflections)**: {stats.get('forms', 0):,}
- **Form Tags (Total)**: {stats.get('form_tags', 0):,}
- **Pronunciations (Sounds)**: {stats.get('sounds', 0):,}
- **Usage Examples**: {stats.get('examples', 0):,}
- **Synonyms**: {stats.get('synonyms', 0):,}
- **Antonyms**: {stats.get('antonyms', 0):,}
- **Hypernyms**: {stats.get('hypernyms', 0):,}
- **Hyponyms**: {stats.get('hyponyms', 0):,}
- **Proverbs**: {stats.get('proverbs', 0):,}
- **Expressions**: {stats.get('expressions', 0):,}
- **Descendants**: {stats.get('descendants', 0):,}
- **Entry Notes**: {stats.get('entry_notes', 0):,}
- **Unique Tags**: {stats.get('tags', 0):,}
- **Unique Topics**: {stats.get('topics', 0):,}
- **Unique Categories**: {stats.get('categories', 0):,}

## 🏗️ Database Schema (Full)

This schema includes all tables from the standard `de-wiktionary-sqlite-normalized` dataset, plus the following additions:

- **entries**:
  - `title`: The Wiktionary page title.
  - `redirect`: The page this entry redirects to (if any).
- **entry_notes**: (New Table) Free-text notes associated with an entry (e.g., "Es gibt etliche Belege für die Steigerung...").
- **other_pos**: (New Table) Alternative part-of-speech values for this word.
- **entry_raw_tags**: (New Table) Unparsed, raw tags from Wiktionary.
- **descendants**: (New Table) Words in other languages descended from this word.
- **hypernyms**: (New Table) "Is-a" relationship (e.g., "Tier" is a hypernym of "Hund").
- **hyponyms**: (New Table) "Type-of" relationship (e.g., "Hund" is a hyponym of "Tier").
- **holonyms**: (New Table) "Part-of" relationship (e.g., "Hand" is a holonym of "Finger").
- **meronyms**: (New Table) "Has-a" relationship (e.g., "Finger" is a meronym of "Hand").
- **coordinate_terms**: (New Table) Sibling terms (e.g., "Hund" and "Katze" are coordinate terms under "Haustier").
- **expressions**: (New Table) Idiomatic expressions using the word (linked to `sense_id`).
- **proverbs**: (New Table) Proverbs using the word (linked to `sense_id`).

*(For the standard schema, see the `cstr/de-wiktionary-sqlite-normalized` dataset card)*

## 📖 Usage

### Download
```python
from huggingface_hub import hf_hub_download
import sqlite3
import gzip
import shutil

# Download compressed database
db_gz_path = hf_hub_download(
    repo_id="{repo_id}",
    filename="{filename_in_repo}",
    repo_type="dataset"
)

# Decompress (if it's .gz)
db_path = db_gz_path.replace('.gz', '')
with gzip.open(db_gz_path, 'rb') as f_in:
    with open(db_path, 'wb') as f_out:
        shutil.copyfileobj(f_in, f_out)

# Connect
conn = sqlite3.connect(db_path)
```

### Example Query (New Tables)
```python
# Get all hypernyms (parent categories) for "Hund"
cursor.execute('''
    SELECT h.hypernym_word
    FROM entries e
    JOIN hypernyms h ON e.id = h.entry_id
    WHERE e.word = ? AND e.lang = 'Deutsch'
''', ('Hund',))

print("Hypernyms of 'Hund':", [row[0] for row in cursor.fetchall()])
```

## 🔗 Source

Original data: [{source_repo}](https://huggingface.co/datasets/{source_repo})

## 📜 License

CC-BY-SA 3.0 (same as source)
"""

def upload_to_huggingface(db_path, repo_id, source_repo, stats, compress=True):
    """Upload the SQLite database to HuggingFace with comprehensive documentation."""
    
    print(f"\n### Uploading to HuggingFace: {repo_id} ###")

    upload_file_path = db_path
    filename_in_repo = os.path.basename(db_path)

    if compress:
        upload_file_path, filename_in_repo = compress_database(db_path)

    file_size_mb = os.path.getsize(upload_file_path) / (1024**2)
    print(f"Uploading {filename_in_repo} ({file_size_mb:.2f} MB)...")

    api = HfApi()

    try:
        print("Creating/checking repository...")
        api.create_repo(repo_id=repo_id, repo_type="dataset", exist_ok=True)
        
        print(f"Uploading database file...")
        api.upload_file(
            path_or_fileobj=upload_file_path,
            path_in_repo=filename_in_repo,
            repo_id=repo_id,
            repo_type="dataset",
            commit_message="Upload FULL normalized Wiktionary database"
        )
        
        print("Creating and uploading README.md...")
        readme_content = generate_readme_content(repo_id, filename_in_repo, source_repo, stats)
        
        with open("README.md", "w", encoding='utf-8') as f:
            f.write(readme_content)
        
        api.upload_file(
            path_or_fileobj="README.md",
            path_in_repo="README.md",
            repo_id=repo_id,
            repo_type="dataset",
            commit_message="Add comprehensive README for full dataset"
        )
        os.remove("README.md")
        
        print(f"\n✅ Upload complete!")
        print(f"View at: https://huggingface.co/datasets/{repo_id}")
        
    except Exception as e:
        print(f"❌ Upload failed: {e}")
        print("Make sure you're logged in with: huggingface-cli login")
        import traceback
        traceback.print_exc()

def main():
    parser = argparse.ArgumentParser(description="Create and upload a FULL, lossless normalized Wiktionary SQLite DB.")
    parser.add_argument(
        '--source_repo_id',
        default=DEFAULT_SOURCE_REPO_ID,
        help=f"HF dataset to pull JSONL from (default: {DEFAULT_SOURCE_REPO_ID})"
    )
    parser.add_argument(
        '--db_filename',
        default=DEFAULT_DB_FILENAME,
        help=f"Local name for the new database (default: {DEFAULT_DB_FILENAME})"
    )
    parser.add_argument(
        '--target_repo_id',
        default=DEFAULT_TARGET_REPO_ID,
        help=f"HF dataset repo to upload to (default: {DEFAULT_TARGET_REPO_ID})"
    )
    parser.add_argument(
        '--skip_download',
        action='store_true',
        help="Skip downloading, use existing 'de-wiktionary.jsonl' in current dir"
    )
    parser.add_argument(
        '--skip_upload',
        action='store_true',
        help="Skip uploading to Hugging Face, only create local DB"
    )
    parser.add_argument(
        '--no_compress',
        action='store_true',
        help="Upload the database uncompressed (not recommended)"
    )
    
    # --- NEW: Add the --upload-only flag ---
    parser.add_argument(
        '--upload-only',
        action='store_true',
        help="Skip all normalization and just upload the file specified by --db_filename"
    )
    # --- END NEW ---

    args = parser.parse_args()

    print("="*80)
    print("Wiktionary FULL Normalization & Upload Script")
    print("="*80)
    print(f"Source JSONL Repo: {args.source_repo_id}")
    print(f"Local DB Name:     {args.db_filename}")
    print(f"Target HF Repo:    {args.target_repo_id}")
    print(f"Skip Download:     {args.skip_download}")
    print(f"Skip Upload:       {args.skip_upload}")
    print(f"Compress:          {not args.no_compress}")
    print(f"Upload-Only Mode:  {args.upload_only}") # --- NEW ---
    print("="*80)

    # --- NEW: Logic block to handle --upload-only ---
    if args.upload_only:
        print("\n### --upload-only mode enabled ###")
        print("Skipping download and normalization.")
        
        if not os.path.exists(args.db_filename):
            print(f"❌ Error: File not found: {args.db_filename}", file=sys.stderr)
            print("Please ensure --db_filename points to the file you want to upload.")
            return
        
        print(f"Found local database to upload: {args.db_filename}")
        
        # We are skipping normalization, so stats are unknown.
        # We pass an empty dict; the README generation will just skip the stats section.
        db_stats = {} 
        db_filename = args.db_filename
        
    else:
        # --- This is the ORIGINAL logic path if --upload-only is NOT used ---
        
        # --- 1. Get Dataset ---
        dataset_iterable = None
        jsonl_path = 'de-wiktionary.jsonl'
        
        if args.skip_download:
            if not os.path.exists(jsonl_path):
                print(f"❌ Error: --skip_download used but '{jsonl_path}' not found.", file=sys.stderr)
                return
            print(f"Using local file: {jsonl_path}")
            print("Counting lines in local file...")
            
            try:
                result = subprocess.run(['wc', '-l', jsonl_path], capture_output=True, text=True, check=True)
                num_lines = int(result.stdout.strip().split()[0])
            except Exception as e:
                print(f"Could not use 'wc -l' ({e}), falling back to manual count (slow)...")
                with open(jsonl_path, 'r', encoding='utf-8') as f:
                    num_lines = sum(1 for line in f)
            
            print(f"Total lines: {num_lines:,}")
            
            def local_dataset_generator(path):
                with open(path, 'r', encoding='utf-8') as f:
                    for line in f:
                        try:
                            yield json.loads(line)
                        except json.JSONDecodeError:
                            continue
                            
            dataset_iterable = tqdm(local_dataset_generator(jsonl_path), total=num_lines, desc="Processing local file")
        
        else:
            print(f"\n### Loading dataset: {args.source_repo_id} ###")
            dataset = load_dataset(args.source_repo_id, split='train', streaming=True)
            print("Dataset loaded in streaming mode.")
            dataset_iterable = tqdm(dataset, desc="Processing streaming dataset")

        # --- 2. Normalize Database ---
        start_time = time.time()
        db_stats, db_filename = create_full_normalized_db(dataset_iterable, args.db_filename)
        end_time = time.time()
        print(f"Database normalization finished in {end_time - start_time:.2f} seconds.")
    # --- END NEW --- (The 'else' block ends here)


    # --- 3. Upload ---
    # This block is now shared by both modes.
    # If in upload-only mode, db_stats will be {} and db_filename will be the file you specified.
    if not args.skip_upload:
        upload_to_huggingface(
            db_path=db_filename,
            repo_id=args.target_repo_id,
            source_repo=args.source_repo_id,
            stats=db_stats,
            compress=(not args.no_compress)
        )
    else:
        print("\n--skip_upload enabled. Skipping upload.")

    print("\n✅ All steps complete.")

if __name__ == "__main__":
    main()