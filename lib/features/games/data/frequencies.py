import json
import os
import shutil
import sys
import datetime
import argparse # New import
from pathlib import Path
from collections import Counter

# --- Configuration ---
# Set paths relative to this script
SCRIPT_DIR = Path(__file__).resolve().parent
JSON_FILE_PATH = SCRIPT_DIR / "grundwortschatz_with_errors.json"
FREQ_FILE_PATH = SCRIPT_DIR / "top10000de.txt" # Your new frequency file
BACKUP_DIR = SCRIPT_DIR / "backups"
# --- End Configuration ---

# ANSI Colors for logging
class Colors:
    RESET = '\033[0m'
    BOLD = '\033[1m'
    RED = '\033[31m'
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    CYAN = '\033[36m'

def log(color, message):
    print(f"{color}{message}{Colors.RESET}")

def create_backup(file_path, backup_dir):
    """Creates a timestamped backup of the JSON file."""
    if not file_path.exists():
        log(Colors.RED, f"FATAL: JSON file not found at {file_path}")
        sys.exit(1)
        
    log(Colors.CYAN, "Creating backup...")
    try:
        backup_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        backup_name = f"{file_path.stem}_BACKUP_{timestamp}{file_path.suffix}"
        backup_path = backup_dir / backup_name
        
        shutil.copy2(file_path, backup_path)
        log(Colors.GREEN, f"✓ Backup saved to: {backup_path}")
    except Exception as e:
        log(Colors.RED, f"FATAL: Could not create backup. Aborting. Error: {e}")
        sys.exit(1)

def load_frequency_map(freq_path):
    """
    Reads the top10000de.txt file and creates a dictionary
    mapping each word to its 1-based rank.
    """
    if not freq_path.exists():
        log(Colors.RED, f"FATAL: Frequency file not found at {freq_path}")
        log(Colors.YELLOW, "Please make sure 'top10000de.txt' is in the same directory.")
        sys.exit(1)
        
    frequency_map = {}
    with open(freq_path, 'r', encoding='utf-8') as f:
        # enumerate starts at 0, so 0+1=1 for the first line.
        for i, line in enumerate(f):
            # Strip whitespace (like \n) and convert to lowercase
            word = line.strip().lower()
            if word:
                frequency_map[word] = i + 1
                
    log(Colors.GREEN, f"✓ Loaded {len(frequency_map)} words from frequency list.")
    return frequency_map

def add_frequency_ranks(json_path, freq_map):
    """
    Loads the JSON file, adds the 'frequencyRank' field,
    and saves the file back.
    
    Returns a set of all lowercase words found in the JSON for comparison.
    """
    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        log(Colors.RED, f"FATAL: Could not read or parse JSON file. Error: {e}")
        sys.exit(1)
        
    if 'vocabulary' not in data or not isinstance(data['vocabulary'], list):
        log(Colors.RED, "FATAL: JSON format is incorrect. Expected a 'vocabulary' list.")
        sys.exit(1)

    vocab_list = data['vocabulary']
    log(Colors.CYAN, f"Processing {len(vocab_list)} words...")
    
    stats = {
        "words_ranked": 0,
        "words_not_in_list": 0,
    }
    
    # NEW: Keep track of all words in the JSON
    json_word_set = set()

    for word_obj in vocab_list:
        if not isinstance(word_obj, dict):
            continue

        word = word_obj.get('word')
        if not word:
            continue

        word_to_check = word.lower()
        json_word_set.add(word_to_check) # Add word to our set
        
        rank = freq_map.get(word_to_check)
        
        word_obj['frequencyRank'] = rank
        
        if rank is not None:
            stats["words_ranked"] += 1
        else:
            stats["words_not_in_list"] += 1

    # --- End of Loop ---
    
    if 'metadata' not in data:
        data['metadata'] = {}
    data['metadata']['lastFrequencyRankRun'] = datetime.datetime.now().isoformat()
    data['metadata']['frequencyRankStats'] = stats
    
    # --- Save Data Back ---
    try:
        with open(json_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        log(Colors.RED, f"FATAL: Could not write updated data. Error: {e}")
        log(Colors.YELLOW, "Your data is safe in the backup directory.")
        sys.exit(1)

    log(Colors.GREEN, f"\n{Colors.BOLD}--- 📈 Frequency Ranking Complete! ---")
    log(Colors.GREEN, f"Words assigned a rank:   {stats['words_ranked']}")
    log(Colors.GREEN, f"Words not in freq list:  {stats['words_not_in_list']}")
    log(Colors.GREEN, f"\n✓ Successfully saved updated data to: {json_path}")
    
    return json_word_set # Return the set of words we found

def report_missing_words(freq_map, json_words, top_n):
    """
    Compares the frequency list to the JSON words and prints
    the top N most frequent words that are missing.
    """
    log(Colors.CYAN, "\n--- 🔍 Finding most common words NOT in JSON ---")
    
    missing_words = []
    for word, rank in freq_map.items():
        if word not in json_words:
            missing_words.append((rank, word))
            
    # Sort by rank (the first item in the tuple)
    missing_words.sort()
    
    log(Colors.YELLOW, f"Found {len(missing_words)} words from the freq list that are missing from the JSON.")
    log(Colors.YELLOW, f"Showing Top {top_n}:\n")
    
    print(f"{Colors.BOLD}Rank  | Word{Colors.RESET}")
    print("------+----------")
    
    for rank, word in missing_words[:top_n]:
        print(f"{rank:<5} | {word}")

def main():
    # NEW: Argument parser
    parser = argparse.ArgumentParser(description="Add frequency ranks to Wortschatz JSON.")
    parser.add_argument(
        '--top_n', 
        type=int, 
        default=20, 
        help="Number of missing common words to report (default: 20)"
    )
    args = parser.parse_args()

    log(Colors.BOLD, "--- 🏛️  Wortschatz Frequency Rank Adder ---")
    
    abs_json_path = JSON_FILE_PATH.resolve()
    abs_freq_path = FREQ_FILE_PATH.resolve()
    abs_backup_dir = BACKUP_DIR.resolve()
    
    log(Colors.CYAN, f"JSON file:   {abs_json_path}")
    log(Colors.CYAN, f"Freq file:   {abs_freq_path}")
    log(Colors.CYAN, f"Report size: {args.top_n} words")
    
    # 1. Create Backup
    create_backup(abs_json_path, abs_backup_dir)
    
    # 2. Load Frequency List
    freq_map = load_frequency_map(abs_freq_path)
    
    # 3. Add ranks and save, getting back the set of JSON words
    json_words = add_frequency_ranks(abs_json_path, freq_map)
    
    # 4. NEW: Run the report
    report_missing_words(freq_map, json_words, args.top_n)

if __name__ == "__main__":
    main()