import json
import sys

# --- Configuration ---
BASE_JSON_FILE = 'grundwortschatz.json'  # Your main file with 1000s of words
NRW_JSON_FILE = 'output_nested.json'     # The file we created from the Excel
OUTPUT_JSON_FILE = 'grundwortschatz_merged.json' # The final, combined file
# ---------------------

def load_json(filename):
    """Helper function to load a JSON file with error handling."""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            print(f"Loading {filename}...")
            return json.load(f)
    except FileNotFoundError:
        print(f"Error: The file '{filename}' was not found.")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: Failed to decode JSON from '{filename}'.")
        sys.exit(1)

def build_nrw_lookup(nrw_data_list):
    """
    Converts the list of NRW data into a dictionary (map) keyed by the
    word for fast O(1) lookups.
    """
    nrw_map = {}
    for item in nrw_data_list:
        artikel_block = item.get("Artikel")
        word_key = None
        
        # Extract the word ("Artikel") from the complex block
        if isinstance(artikel_block, dict):
            word_key = artikel_block.get("_value")
        elif isinstance(artikel_block, str):
            word_key = artikel_block
            
        if word_key:
            nrw_map[word_key] = item
        else:
            print(f"Warning: Could not find word key for item: {item}")
            
    print(f"Created lookup map with {len(nrw_map)} entries from NRW data.")
    return nrw_map

def main():
    # 1. Load both JSON files
    base_data = load_json(BASE_JSON_FILE)
    nrw_data_list = load_json(NRW_JSON_FILE)
    
    # 2. Create the fast lookup map
    nrw_lookup = build_nrw_lookup(nrw_data_list)
    
    # 3. Iterate and merge
    print("Starting merge process...")
    merged_count = 0
    
    if "vocabulary" not in base_data:
        print(f"Error: The base file '{BASE_JSON_FILE}' does not have a 'vocabulary' key.")
        sys.exit(1)

    for vocab_item in base_data["vocabulary"]:
        word = vocab_item.get("word")
        if not word:
            continue
            
        # Find the matching entry in the NRW data
        nrw_entry = nrw_lookup.get(word)
        
        if nrw_entry:
            merged_count += 1
            
            # --- This is the integration magic ---
            
            # 1. Intelligently update the article
            nrw_artikel_block = nrw_entry.get("Artikel", {})
            if isinstance(nrw_artikel_block, dict):
                if "der" in nrw_artikel_block:
                    vocab_item["article"] = "der"
                elif "die" in nrw_artikel_block:
                    vocab_item["article"] = "die"
                elif "das" in nrw_artikel_block:
                    vocab_item["article"] = "das"
            
            # 2. Add all other top-level grammatical info
            for key, value in nrw_entry.items():
                if key == "Artikel":
                    # We've handled this. But we can add the other info
                    # like "häufig gebrauchte..." under a new key.
                    if isinstance(value, dict) and len(value) > 1:
                        # Copy only the *extra* info, not the word itself
                        extra_artikel_info = {k: v for k, v in value.items() if k != "_value"}
                        if extra_artikel_info:
                             vocab_item["artikelDetailsNRW"] = extra_artikel_info
                else:
                    # Add all other principles directly
                    # e.g., "morphematisches Prinzip": {...}
                    vocab_item[key] = value

    print(f"Merge complete. Enriched {merged_count} word entries.")

    # 4. Save the new merged file
    try:
        with open(OUTPUT_JSON_FILE, 'w', encoding='utf-8') as f:
            json.dump(base_data, f, ensure_ascii=False, indent=2)
        print(f"Successfully saved merged data to '{OUTPUT_JSON_FILE}'")
    except Exception as e:
        print(f"Error saving final file: {e}")

if __name__ == "__main__":
    main()