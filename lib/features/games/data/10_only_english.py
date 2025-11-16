import json
import sys

INPUT_FILE = 'grundwortschatz_safe_enriched_v23.json'
OUTPUT_FILE = 'grundwortschatz_safe_enriched_v23_only_english.json'

def filter_translations_to_english():
    """
    Loads the enriched JSON, filters wiktionary_translations to English-only,
    and saves to a new file.
    """
    print(f"Attempting to load '{INPUT_FILE}'...")
    try:
        with open(INPUT_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: Input file '{INPUT_FILE}' not found.", file=sys.stderr)
        return
    except json.JSONDecodeError as e:
        print(f"Error: Could not decode JSON from '{INPUT_FILE}'. Corrupted file? {e}", file=sys.stderr)
        return
    
    if 'vocabulary' not in data:
        print(f"Error: Expected 'vocabulary' key in JSON, but not found.", file=sys.stderr)
        return
        
    vocabulary = data.get('vocabulary', [])
    print(f"✓ Successfully loaded {len(vocabulary)} word entries.")
    
    filtered_entry_count = 0
    
    # Iterate over each word object in the vocabulary list
    for word_obj in vocabulary:
        # Check for apiEnrichment and the translations list
        if ('apiEnrichment' in word_obj and 
            word_obj['apiEnrichment'] and 
            'wiktionary_translations' in word_obj['apiEnrichment']):
            
            original_translations = word_obj['apiEnrichment']['wiktionary_translations']
            
            # Use a list comprehension to build a new list
            # keeping only English translations
            english_translations = [
                t for t in original_translations 
                if t.get('lang') == 'Englisch' or t.get('lang_code') == 'en'
            ]
            
            # If the list changed, increment our counter
            if len(english_translations) < len(original_translations):
                filtered_entry_count += 1
            
            # Overwrite the old list with the new, filtered list
            word_obj['apiEnrichment']['wiktionary_translations'] = english_translations

    print(f"Filtered translation lists for {filtered_entry_count} entries.")
    print(f"\nSaving data with English-only translations to '{OUTPUT_FILE}'...")

    try:
        # Save the entire modified data structure
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print("✓ Save complete.")
        
    except IOError as e:
        print(f"Error: Could not write to output file '{OUTPUT_FILE}': {e}", file=sys.stderr)

if __name__ == "__main__":
    filter_translations_to_english()