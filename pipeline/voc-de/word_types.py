import json
from collections import Counter
from pathlib import Path

# --- Configuration ---
# Set the path to the JSON file relative to this script
SCRIPT_DIR = Path(__file__).resolve().parent
JSON_FILE_PATH = SCRIPT_DIR / "grundwortschatz_with_errors.json"
# --- End Configuration ---

def count_word_types(file_path):
    """
    Loads the JSON file and counts all 'wordType' entries.
    """
    print(f"Loading data from: {file_path}")
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"FATAL: File not found at {file_path}")
        print("Please make sure the file name and path are correct.")
        return
    except Exception as e:
        print(f"FATAL: Could not read or parse JSON file. Error: {e}")
        return
        
    if 'vocabulary' not in data or not isinstance(data['vocabulary'], list):
        print("FATAL: JSON format is incorrect. Expected a 'vocabulary' list.")
        return

    vocab_list = data['vocabulary']
    
    if not vocab_list:
        print("The 'vocabulary' list is empty.")
        return
        
    print(f"Found {len(vocab_list)} total entries.")
    
    # 1. Extract all wordType strings
    all_word_types = [word.get('wordType', 'N/A') for word in vocab_list]
    
    # 2. Count them
    type_counts = Counter(all_word_types)
    
    # 3. Print the results
    print("\n--- Word Type Counts (Sorted by Type) ---")
    
    # Sort by the word type name for a clean list
    sorted_counts = sorted(type_counts.items())
    
    total_width = max(len(word_type) for word_type, _ in sorted_counts)
    
    for word_type, count in sorted_counts:
        print(f"{word_type:<{total_width}} : {count}")
        
    print("-" * (total_width + 10))
    print(f"{'Total':<{total_width}} : {len(all_word_types)}")

if __name__ == "__main__":
    count_word_types(JSON_FILE_PATH)