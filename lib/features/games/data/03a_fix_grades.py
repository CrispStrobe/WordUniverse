import json
import sys

INPUT_JSON_FILE = 'grundwortschatz_safe.json'
OUTPUT_JSON_FILE = 'grundwortschatz_safe_grades_fixed.json'

def get_corrected_grade(sources):
    """
    Calculates the corrected grade level based on the list of sources.
    Logic:
    - School lists (BW, NRW) determine the grade (use the lowest).
    - If no school lists, CEFR lists (A1, A2) determine the grade (use the lowest).
    - If neither, default to 1.
    """
    if not sources:
        return 5  # Default grade 1
    
    school_grades = []
    cefr_grades = []
    
    for source in sources:
        # --- School Grade Lists (Highest Priority) ---
        if source == 'BW1':
            school_grades.append(1)  # Grades 1&2
        elif source == 'BW3':
            school_grades.append(3)  # Grades 3&4
        elif source == 'NRW111':
            school_grades.append(2)  # Merkwörter (sight words), assume Grade 2
        elif source == 'NRW422':
            school_grades.append(2)  # Nachdenkwörter (reflection words), assume Grade 2 // 
        elif source == 'LEO739':
            school_grades.append(3)  # Merkwörter (sight words), assume Grade 3
            
        # --- CEFR Levels (Secondary) ---
        elif source == 'A1':
            cefr_grades.append(4)  # >533, >739
        elif source == 'A2':
            cefr_grades.append(5)  # even larger
        elif source == 'B1':
            cefr_grades.append(6)  # even larger
        elif source == 'B2':
            cefr_grades.append(7)  # Extrapolated
        elif source == 'C1':
            cefr_grades.append(8)  # Extrapolated
        elif source == 'C2':
            cefr_grades.append(9)  # Extrapolated
    
    final_grade = 5  # Default if no grade-specific source is found
    
    if school_grades:
        # If any school source exists, use the lowest school grade
        final_grade = min(school_grades)
    elif cefr_grades:
        # Otherwise, if any CEFR source exists, use the lowest CEFR grade
        final_grade = min(cefr_grades)
    
    return final_grade

def fix_json_grades(input_file, output_file):
    """
    Loads the JSON, recalculates 'gradeLevel' for each word based on its
    'sources' list, and saves to a new file.
    """
    print(f"Loading '{input_file}'...")
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: File not found: '{input_file}'")
        print("Please make sure the file is in the same directory.")
        return
    except json.JSONDecodeError:
        print(f"Error: Could not decode JSON from '{input_file}'.")
        return

    if 'vocabulary' not in data:
        print("Error: JSON format is incorrect. 'vocabulary' key not found.")
        return

    vocabulary_list = data['vocabulary']
    print(f"Loaded {len(vocabulary_list)} word entries.")
    
    changes_count = 0
    
    print("Recalculating grade levels...")
    for word_obj in vocabulary_list:
        original_grade = word_obj.get('gradeLevel', 1)
        sources = word_obj.get('sources', [])
        
        corrected_grade = get_corrected_grade(sources)
        
        if original_grade != corrected_grade:
            # Uncomment to see every change:
            # print(f"  Fixing '{word_obj['word']}': {original_grade} -> {corrected_grade} (Sources: {sources})")
            word_obj['gradeLevel'] = corrected_grade
            changes_count += 1
    
    print(f"Updated {changes_count} word entries.")
    
    print(f"Saving corrected data to '{output_file}'...")
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"Successfully saved to '{output_file}'. ✨")
    except IOError as e:
        print(f"Error writing to file '{output_file}': {e}")

if __name__ == "__main__":
    fix_json_grades(INPUT_JSON_FILE, OUTPUT_JSON_FILE)