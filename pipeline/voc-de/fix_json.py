import json
import os
import shutil
import sys
import datetime
from pathlib import Path

# --- Configuration ---
# Set the path to the JSON file relative to this script
SCRIPT_DIR = Path(__file__).resolve().parent
JSON_FILE_PATH = SCRIPT_DIR / "grundwortschatz_with_errors.json"
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
        log(Colors.RED, f"FATAL: File not found at {file_path}")
        log(Colors.YELLOW, "Please run the full pipeline (enrich_data.py, convert_to_json.py) first.")
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

def fix_json_data(file_path):
    """
    Loads the JSON file and applies all data consistency fixes.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        log(Colors.RED, f"FATAL: Could not read or parse JSON file. Error: {e}")
        sys.exit(1)
        
    if 'vocabulary' not in data or not isinstance(data['vocabulary'], list):
        log(Colors.RED, "FATAL: JSON format is incorrect. Expected a 'vocabulary' list.")
        sys.exit(1)

    vocab_list = data['vocabulary']
    log(Colors.CYAN, f"Processing {len(vocab_list)} words...")

    # --- Stats Tracker ---
    stats = {
        "nurImPlural_fixed": 0,
        "plurals_promoted": 0,
        "inflection_genus_conflicts_removed": 0,
        "inflection_pos_conflicts_removed": 0, # NEW STAT
        "learner_errors_removed": 0,
    }
    
    # Map our 'genus' (from enrich.py) to API 'gender' (from inflection_enricher.dart)
    genus_to_api_gender_map = {
        "mask.": "Masculine",
        "fem.": "Feminine",
        "neut.": "Neuter",
    }
    
    # NEW: Map our 'wordType' to the API's 'pos' hint
    word_type_to_pos_map = {
        "verb": "VB",
        "substantiv": "NN",
        "adjektiv": "ADJ",
        "pronomen": "PRON",
    }

    # --- Main Processing Loop ---
    for word_obj in vocab_list:
        if not isinstance(word_obj, dict):
            continue

        correct_word = word_obj.get('word')
        word_type = word_obj.get('wordType')
        correct_genus = word_obj.get('genus')
        inflection_data = word_obj.get('inflectionData')

        # === FIX 1: 'nurImPlural' Inconsistency ===
        if word_obj.get('nurImPlural') is True:
            is_singular = (
                word_type != 'substantiv' or
                word_obj.get('numberSpacy') == 'Sing' or
                word_obj.get('article') in ('der', 'die', 'das')
            )
            if is_singular:
                word_obj['nurImPlural'] = False
                stats["nurImPlural_fixed"] += 1
                
        # === FIX 2: 'genus' vs. 'inflectionData.gender' Conflict ===
        if (word_type == 'substantiv' and # Only check genus for nouns
            correct_genus and 
            inflection_data and 
            isinstance(inflection_data, dict) and 
            'analyses' in inflection_data):
            
            try:
                api_gender = inflection_data.get('analyses', {}).get('noun', {}).get('gender')
                expected_api_gender = genus_to_api_gender_map.get(correct_genus)
                
                # Check for conflict: if API gender exists AND doesn't match our 'truth'
                if (api_gender and 
                    expected_api_gender and 
                    api_gender != expected_api_gender):
                    
                    # CONFLICT! Nullify the API data.
                    word_obj['inflectionData'] = None
                    word_obj['inflectionDataEnrichedAt'] = None # Clean this up too
                    stats["inflection_genus_conflicts_removed"] += 1
                    inflection_data = None # Stop other fixes from running on this null data
                    
            except Exception:
                pass # Error parsing inflection data, just skip it

        # === FIX 3: Promote 'plural' from inflectionData ===
        # MODIFIED: Added check for word_type == 'substantiv'
        if (word_type == 'substantiv' and # <--- THIS IS THE FIX
            word_obj.get('plural') is None and 
            inflection_data and 
            isinstance(inflection_data, dict)):
            
            try:
                api_plural = inflection_data.get('analyses', {}).get('noun', {}).get('plural')
                # Promote if it's a non-empty string and not the placeholder dash
                if api_plural and isinstance(api_plural, str) and api_plural not in ('', '—'):
                    word_obj['plural'] = api_plural
                    stats["plurals_promoted"] += 1
            except Exception:
                pass # Error parsing, leave plural as null

        # === FIX 4: Clean 'commonLearnerErrors' ===
        learner_errors = word_obj.get('commonLearnerErrors')
        if correct_word and learner_errors and isinstance(learner_errors, list):
            
            original_count = len(learner_errors)
            cleaned_errors = [
                entry for entry in learner_errors
                if (isinstance(entry, dict) and 
                    entry.get('error') and 
                    entry.get('error').lower() != correct_word.lower())
            ]
            
            removed_count = original_count - len(cleaned_errors)
            if removed_count > 0:
                word_obj['commonLearnerErrors'] = cleaned_errors
                stats["learner_errors_removed"] += removed_count
                
        # === NEW FIX 5: 'wordType' vs. 'inflectionData.pos' Conflict ===
        if (inflection_data and 
            isinstance(inflection_data, dict) and
            'parser_hint' in inflection_data):
            
            try:
                api_pos = inflection_data.get('parser_hint', {}).get('pos')
                expected_pos = word_type_to_pos_map.get(word_type)
                
                # CONFLICT: If we have an expected POS and the API's POS exists and *doesn't match*
                if (expected_pos and 
                    api_pos and
                    api_pos != expected_pos):
                    
                    # This is the 'zurückfahren' problem
                    word_obj['inflectionData'] = None
                    word_obj['inflectionDataEnrichedAt'] = None
                    stats["inflection_pos_conflicts_removed"] += 1
                    
                    # Also clean up the 'plural' field that may have been
                    # incorrectly promoted in a *previous* run
                    if word_type != 'substantiv':
                         word_obj['plural'] = None
                         
            except Exception:
                pass # Error parsing, just skip it

    # --- End of Loop ---
    
    # Update metadata
    if 'metadata' not in data:
        data['metadata'] = {}
    data['metadata']['lastFixupRun'] = datetime.datetime.now().isoformat()
    data['metadata']['fixupStats'] = stats
    
    # --- Save Data Back ---
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            # Use indent=2 to match the format from convert_to_json.py
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        log(Colors.RED, f"FATAL: Could not write cleaned data. Error: {e}")
        log(Colors.YELLOW, "Your data is safe in the backup directory.")
        sys.exit(1)

    log(Colors.GREEN, f"\n{Colors.BOLD}--- 🧹 Clean-up Complete! ---")
    log(Colors.GREEN, f"Fixed 'nurImPlural' flags:     {stats['nurImPlural_fixed']}")
    log(Colors.GREEN, f"Promoted 'plural' fields:    {stats['plurals_promoted']}")
    log(Colors.GREEN, f"Removed conflicting 'inflectionData' (Genus): {stats['inflection_genus_conflicts_removed']}")
    log(Colors.GREEN, f"Removed conflicting 'inflectionData' (POS):  {stats['inflection_pos_conflicts_removed']}")
    log(Colors.GREEN, f"Removed invalid learner errors: {stats['learner_errors_removed']}")
    log(Colors.GREEN, f"\n✓ Successfully saved cleaned data to: {file_path}")

def main():
    log(Colors.BOLD, "--- 🏛️  Wortschatz JSON Post-Processing Fixer ---")
    
    # Normalize paths
    abs_file_path = JSON_FILE_PATH.resolve()
    abs_backup_dir = BACKUP_DIR.resolve()
    
    log(Colors.CYAN, f"Target file: {abs_file_path}")
    log(Colors.CYAN, f"Backup dir:  {abs_backup_dir}")
    
    create_backup(abs_file_path, abs_backup_dir)
    fix_json_data(abs_file_path)

if __name__ == "__main__":
    main()