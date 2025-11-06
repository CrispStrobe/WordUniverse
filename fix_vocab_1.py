import json
import os
import shutil
import sys

# --- Configuration ---

# 1. Define the path to your JSON file from the script's location.
#    This path assumes the script is in your project's root.
JSON_FILE_PATH = "lib/features/games/data/grundwortschatz_with_errors.json"

# --- End Configuration ---

def get_expected_gender(article):
    """Helper to map article to gender string used in inflectionData."""
    if article == 'der':
        return 'Masculine'
    if article == 'die':
        return 'Feminine'
    if article == 'das':
        return 'Neuter'
    return None

def clean_vocabulary_file(file_path):
    """
    Loads the vocabulary JSON, applies all fixes, and saves it back.
    """
    
    # --- 1. Safety Backup ---
    if not os.path.exists(file_path):
        print(f"Error: File not found at {file_path}", file=sys.stderr)
        print("Please check the JSON_FILE_PATH variable in the script.", file=sys.stderr)
        return

    backup_path = file_path.replace(".json", "_BACKUP.json")
    try:
        shutil.copy2(file_path, backup_path)
        print(f"✅ Safety backup created at: {backup_path}")
    except Exception as e:
        print(f"Error creating backup: {e}", file=sys.stderr)
        return

    # --- 2. Load Data ---
    try:
        # Use 'utf-8' to handle German Umlaute correctly
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON: {e}", file=sys.stderr)
        print("The file might be corrupted. Restore from backup.", file=sys.stderr)
        return
    except Exception as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        return

    # The data is a map {'vocabulary': [...]}
    if 'vocabulary' not in data or not isinstance(data['vocabulary'], list):
        print("Error: Expected JSON structure {'vocabulary': [...]} not found.", file=sys.stderr)
        return
        
    vocabulary_list = data['vocabulary']
    
    # --- 3. Process Words & Track Fixes ---
    print(f"\nProcessing {len(vocabulary_list)} words...")
    
    fixes_nur_im_plural = 0
    errors_removed_count = 0
    words_errors_cleaned = 0
    fixes_inflection_data = 0
    
    for word_obj in vocabulary_list:
        if not isinstance(word_obj, dict):
            continue

        correct_word = word_obj.get('word')
        article = word_obj.get('article')
        word_type = word_obj.get('wordType')
        number_spacy = word_obj.get('numberSpacy')

        # --- FIX 1: Correct 'nurImPlural' inconsistencies ---
        if word_obj.get('nurImPlural') is True:
            is_singular = (
                word_type != 'substantiv' or
                number_spacy == 'Sing' or
                article in ('der', 'die', 'das')
            )
            if is_singular:
                word_obj['nurImPlural'] = False
                fixes_nur_im_plural += 1

        # --- FIX 2: Clean 'commonLearnerErrors' ---
        # (Remove errors that are just the correct word)
        learner_errors = word_obj.get('commonLearnerErrors')
        if correct_word and learner_errors and isinstance(learner_errors, list):
            
            original_error_count = len(learner_errors)
            # Rebuild the list, keeping only valid errors
            cleaned_errors = [
                error_entry for error_entry in learner_errors
                if (isinstance(error_entry, dict) and 
                    error_entry.get('error') and 
                    error_entry.get('error').lower() != correct_word.lower())
            ]
            
            if len(cleaned_errors) < original_error_count:
                removed_count = original_error_count - len(cleaned_errors)
                errors_removed_count += removed_count
                words_errors_cleaned += 1
                word_obj['commonLearnerErrors'] = cleaned_errors

        # --- FIX 3: Remove inconsistent 'inflectionData' ---
        inflection_data = word_obj.get('inflectionData')
        expected_gender = get_expected_gender(article)

        # Check if data is present and contradictory
        if (word_type == 'substantiv' and 
            expected_gender and 
            inflection_data and 
            isinstance(inflection_data, dict)):
            
            try:
                # Safely get the nested gender
                inflection_gender = inflection_data.get('analyses', {}).get('noun', {}).get('gender')
                
                # If gender is present and *does not* match the article's gender
                if (inflection_gender and 
                    inflection_gender != expected_gender):
                    
                    word_obj['inflectionData'] = None # Nullify the bad data
                    fixes_inflection_data += 1
                    
            except Exception:
                # Error parsing this, skip it
                pass

    # --- 4. Save Data Back ---
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            # ensure_ascii=False keeps Umlaute as 'ä' instead of '\u00e4'
            # indent=4 makes the file human-readable
            json.dump(data, f, ensure_ascii=False, indent=4)
    except Exception as e:
        print(f"Error writing cleaned data: {e}", file=sys.stderr)
        print("Your original file is safe in the .backup file.", file=sys.stderr)
        return

    # --- 5. Report ---
    print("\n--- 🧹 Cleaning Complete! ---")
    print(f"Fixed 'nurImPlural' flag:  {fixes_nur_im_plural} words")
    print(f"Removed 'inflectionData': {fixes_inflection_data} words (due to gender conflict)")
    print(f"Removed identical errors: {errors_removed_count} entries (across {words_errors_cleaned} words)")
    print(f"\n✅ Successfully saved cleaned data to: {file_path}")


# --- Run the script ---
if __name__ == "__main__":
    clean_vocabulary_file(JSON_FILE_PATH)