import json
import re
import csv
import sys

# Increase CSV field size limit for massive SQL lines
csv.field_size_limit(sys.maxsize)

# Configuration
INPUT_JSON = 'grundwortschatz_v24.json'
SQL_DUMP_FILE = 'openthesaurus_dump.sql'
OUTPUT_JSON = 'grundwortschatz_v24_with_thesaurus.json'

# --- SQL PARSING HELPER (Same as before) ---
def parse_sql_values(line):
    start = line.find("VALUES (")
    if start == -1: return []
    content = line[start + 7:].strip().rstrip(';')
    
    rows = []
    current_row = []
    current_val = []
    in_quote = False
    in_paren = False
    escape = False
    
    for char in content:
        if escape:
            current_val.append(char)
            escape = False
            continue
        if char == '\\':
            escape = True
            continue
        if char == "'" and not escape:
            in_quote = not in_quote
            continue
        if in_quote:
            current_val.append(char)
            continue
        if char == '(':
            in_paren = True
            current_row = []
            current_val = []
        elif char == ')':
            in_paren = False
            current_row.append("".join(current_val).strip())
            rows.append(current_row)
        elif char == ',' and in_paren:
            current_row.append("".join(current_val).strip())
            current_val = []
        elif char == ',' and not in_paren:
            pass 
        else:
            current_val.append(char)
    return rows

def load_openthesaurus_sql(filepath):
    print(f"⏳ Parsing SQL Dump {filepath} (this takes ~30-60 seconds)...")
    
    # --- DATA STRUCTURES ---
    categories = {}       # id -> name
    levels = {}           # id -> name
    link_types = {}       # id -> name (e.g., "hypernym", "association")
    
    synset_categories = {} # synset_id -> [category_ids]
    synset_links = {}      # synset_id -> [ {target_id, type_id} ]
    
    word_map = {}          # word -> [ {synset_id, level_id} ]
    synset_terms = {}      # synset_id -> [ {word, level_id} ]
    synset_visible = {}    # synset_id -> bool

    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line.startswith("INSERT INTO"): continue
                
                # 1. CATEGORY
                if "INSERT INTO `category`" in line:
                    for r in parse_sql_values(line):
                        if len(r) >= 3: categories[r[0]] = r[2]

                # 2. TERM_LEVEL (Usage levels like 'umgangssprachlich')
                elif "INSERT INTO `term_level`" in line:
                    for r in parse_sql_values(line):
                        if len(r) >= 3: levels[r[0]] = r[2]

                # 3. LINK_TYPE (The missing key! defines Hypernym/Hyponym)
                elif "INSERT INTO `link_type`" in line:
                    for r in parse_sql_values(line):
                        # Schema: id, version, link_name, ...
                        if len(r) >= 3: link_types[r[0]] = r[2]

                # 4. CATEGORY_LINK
                elif "INSERT INTO `category_link`" in line:
                    for r in parse_sql_values(line):
                        if len(r) >= 4:
                            cat_id, syn_id = r[2], r[3]
                            synset_categories.setdefault(syn_id, []).append(cat_id)

                # 5. SYNSET_LINK (The semantic web)
                elif "INSERT INTO `synset_link`" in line:
                    for r in parse_sql_values(line):
                        # Schema based on dump: id(0), ver(1), eval(2), count(3), type_id(4), source_id(5), target_id(6)
                        if len(r) >= 7:
                            type_id = r[4]
                            src_id = r[5]
                            tgt_id = r[6]
                            synset_links.setdefault(src_id, []).append({'target': tgt_id, 'type': type_id})

                # 5b. SYNSET: OpenThesaurus hides the synsets it rejected
                # (is_visible = 0). Hidden synset 41007 is how "Preis" came
                # to list "Egon Schiele Art Center".
                elif "INSERT INTO `synset` " in line:
                    for r in parse_sql_values(line):
                        # id, version, evaluation, is_visible, ...
                        if len(r) >= 4:
                            synset_visible[r[0]] = r[3] not in ('0', '', '\0')

                # 6. TERM
                elif "INSERT INTO `term`" in line:
                    for r in parse_sql_values(line):
                        if len(r) >= 9:
                            # id(0), ver(1), lang(2), level(3), norm(4), orig(5), synset(6), comm(7), word(8)
                            level_id = r[3] if r[3] != 'NULL' else None
                            synset_id = r[6]
                            word = r[8]
                            
                            word_map.setdefault(word, []).append({'synset_id': synset_id, 'level_id': level_id})
                            synset_terms.setdefault(synset_id, []).append({'word': word, 'level_id': level_id})

    except FileNotFoundError:
        print("❌ SQL file not found!")
        return None

    print(f"✅ Loaded: {len(word_map)} terms, {len(synset_links)} relations.")
    return {
        'categories': categories,
        'levels': levels,
        'link_types': link_types,
        'synset_categories': synset_categories,
        'synset_links': synset_links,
        'word_map': word_map,
        'synset_terms': synset_terms,
        'synset_visible': synset_visible,
    }

OFFENSIVE_LEVELS = {'derb', 'vulgär'}


def level_of(term, db):
    return db['levels'].get(term['level_id']) if term['level_id'] else None


def resolve_terms(synset_id, db, exclude_word=None):
    """The words of a visible synset, without the word itself (compared
    case-insensitively) and without derb or vulgär terms.

    The level used to be written into the word ("Sack (derb)"), and the app
    showed it; levels are now kept apart, see synonym_levels below.
    """
    if not db['synset_visible'].get(synset_id, False):
        return []
    results = []
    for t in db['synset_terms'].get(synset_id, []):
        w = t['word']
        if exclude_word and w.lower() == exclude_word.lower():
            continue
        if level_of(t, db) in OFFENSIVE_LEVELS:
            continue
        results.append(w)
    return results


def word_is_offensive_in(synset_id, word, db):
    """True where the word itself is filed derb or vulgär: its insult sense,
    whose other terms are insults, not synonyms of the animal."""
    own = [level_of(t, db) for t in db['synset_terms'].get(synset_id, [])
           if t['word'] == word]
    return bool(own) and all(lv in OFFENSIVE_LEVELS for lv in own)

def enrich_json():
    db = load_openthesaurus_sql(SQL_DUMP_FILE)
    if not db: return

    print("Loading Vocabulary JSON...")
    with open(INPUT_JSON, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    vocab = data.get('vocabulary', [])
    stats = {'enriched': 0, 'total': 0}
    
    print("Enriching vocabulary with semantic relations...")
    
    for entry in vocab:
        stats['total'] += 1
        word = entry.get('word')
        
        if word in db['word_map']:
            matches = db['word_map'][word]
            
            # Ensure structure exists
            if 'apiEnrichment' not in entry or entry['apiEnrichment'] is None:
                entry['apiEnrichment'] = {}
            
            thesaurus_groups = []
            flat_synonyms = []

            # Process each Meaning Group (Synset)
            for match in matches:
                synset_id = match['synset_id']
                if not db['synset_visible'].get(synset_id, False):
                    continue
                if word_is_offensive_in(synset_id, word, db):
                    continue
                
                # 1. Get Categories (e.g. "Medizin")
                cat_ids = db['synset_categories'].get(synset_id, [])
                cat_names = [db['categories'][cid] for cid in cat_ids if cid in db['categories']]
                
                # 2. Get Direct Synonyms
                synonyms = resolve_terms(synset_id, db, exclude_word=word)
                flat_synonyms.extend(synonyms)

                # 3. Get Relations (Oberbegriffe, Unterbegriffe, etc.)
                relations = {'Oberbegriffe': [], 'Unterbegriffe': [], 'Assoziationen': []}
                
                links = db['synset_links'].get(synset_id, [])
                for link in links:
                    target_id = link['target']
                    type_id = link['type']
                    type_name = db['link_types'].get(type_id, 'unknown')
                    
                    # Map OpenThesaurus link names to our German labels
                    # Note: These keys depend on the SQL dump content. 
                    # Common keys: 'hypernym' (Ober), 'hyponym' (Unter), 'association'
                    target_words = resolve_terms(target_id, db)
                    
                    if not target_words: continue

                    if type_name == 'hypernym':
                        relations['Oberbegriffe'].extend(target_words)
                    elif type_name == 'hyponym':
                        relations['Unterbegriffe'].extend(target_words)
                    else:
                        # Catch-all for 'association' or others
                        relations['Assoziationen'].extend(target_words)

                # Add this semantic group
                thesaurus_groups.append({
                    'categories': cat_names,
                    'synonyms': synonyms,
                    'hypernyms': list(set(relations['Oberbegriffe'])),
                    'hyponyms': list(set(relations['Unterbegriffe'])),
                    'associations': list(set(relations['Assoziationen']))
                })

            # Save to JSON entry
            if thesaurus_groups:
                entry['apiEnrichment']['openThesaurus'] = thesaurus_groups
                
                # Merge into the flat list: what was there first, in a fixed
                # order, each word once. All senses are still in it; which
                # belong to the meaning a child is shown is decided after,
                # by tools/pack/build_synonym_senses.py.
                merged = {}
                for w in list(entry['apiEnrichment'].get('synonyms', [])) + flat_synonyms:
                    if isinstance(w, str) and w.lower() != word.lower():
                        merged.setdefault(w.lower(), w)
                entry['apiEnrichment']['synonyms'] = list(merged.values())
                
                stats['enriched'] += 1

    print(f"Enriched {stats['enriched']} / {stats['total']} words.")
    
    with open(OUTPUT_JSON, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"Saved to {OUTPUT_JSON}")

if __name__ == "__main__":
    enrich_json()