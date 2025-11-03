import pandas as pd
import json
import re

# --- Configuration ---
INPUT_CSV_FILE = 'voc_de_enriched.csv'
OUTPUT_JSON_FILE = 'grundwortschatz.json'

# Mapping from our CSV 'Wortart' to the Dart 'GermanWordType' enum strings
WORTART_TO_ENUM_MAP = {
    'Substantiv': 'substantiv',
    'Verb': 'verb',
    'Adjektiv': 'adjektiv',
    'Adverb': 'adverb',
    'Artikel': 'artikel',
    'Pronomen': 'pronomen',
    'Präposition': 'praeposition',
    'Konjunktion': 'konjunktion',
    'Partikel': 'partikel',
    'Numerale': 'numerale',
    'Kardinalzahlwort': 'kardinalzahlwort',
    'Ordinalzahlwort': 'ordinalzahlwort',
    'Affix': 'affix',
    'Mehrwortausdruck': 'mehrwortausdruck',
    'Andere': 'andere',
    'Symbol': 'andere',
}

def parse_sources(source_str):
    """
    Parses the Source column and returns:
    - A list of all sources (e.g., ['A1', 'BW3'])
    - The highest grade level found
    - Whether it's part of BW Grundwortschatz
    """
    if not source_str:
        return [], 1, False
    
    sources = [s.strip() for s in source_str.split(',')]
    
    grade_levels = []
    is_bw = False
    
    for source in sources:
        if source == 'A1':
            grade_levels.append(1)
        elif source == 'A2':
            grade_levels.append(2)
        elif source == 'B1':
            grade_levels.append(3)
        elif source == 'B2':
            grade_levels.append(4)
        elif source == 'C1':
            grade_levels.append(5)
        elif source == 'C2':
            grade_levels.append(6)
        elif source == 'BW1':
            grade_levels.append(1)  # Grades 1&2
            is_bw = True
        elif source == 'BW3':
            grade_levels.append(3)  # Grades 3&4
            is_bw = True
    
    # Use the highest grade level found
    max_grade = max(grade_levels) if grade_levels else 1
    
    return sources, max_grade, is_bw

def convert_csv_to_json(input_file, output_file):
    """
    Loads the enriched CSV and converts it to the app's JSON format.
    """
    print(f"Loading '{input_file}'...")
    try:
        df = pd.read_csv(input_file, delimiter=';')
    except FileNotFoundError:
        print(f"Error: File not found: '{input_file}'")
        print("Please run the 'enrich.py' script first.")
        return

    df = df.fillna('')
    print(f"Loaded {len(df)} entries.")
    
    vocabulary_list = []
    word_id_counter = 1

    print("Converting rows to JSON format...")
    for index, row in df.iterrows():
        # Create a stable ID
        word_id = f"word_{word_id_counter:05d}"
        word_id_counter += 1

        # Map Wortart to the Dart enum string
        wortart = row['Wortart']
        enum_wortart = WORTART_TO_ENUM_MAP.get(wortart, 'andere')
        
        # Parse sources and get grade level
        sources, grade_level, is_bw = parse_sources(row['Source'])
        
        # Handle nur_im_Plural - convert to boolean
        nur_im_plural_val = row.get('nur_im_Plural', '')
        if nur_im_plural_val == '' or nur_im_plural_val == '0' or nur_im_plural_val == '0.0':
            nur_im_plural = False
        else:
            nur_im_plural = True
        
        # Create the JSON object for this word
        word_obj = {
            'id': word_id,
            'word': row['Word'],
            'article': row['Article'],
            'wordType': enum_wortart,
            'gradeLevel': grade_level,
            'sources': sources,
            'isGrundwortschatzBW': is_bw,
            'lemma': row['Lemma_spacy'],
            'forms': row['Forms'],
            'genus': row.get('Genus', ''),  # NEW: Added Genus
            'nurImPlural': nur_im_plural,    # NEW: Added nur_im_Plural as boolean
            'url': row['URL'],
            
            # spaCy morphological fields
            'caseSpacy': row['Case_spacy'],
            'numberSpacy': row['Number_spacy'],
            'degreeSpacy': row['Degree_spacy'],
            'pronTypeSpacy': row['PronType_spacy'],
            'verbFormSpacy': row['VerbForm_spacy'],
            
            # App-specific fields (empty, to be filled in-app or manually)
            'plural': None, 
            'categories': [],
            'exampleSentences': [],
            'spellingDifficulty': 0,
            'commonMistakes': None,
            'audioPath': None,
        }
        
        vocabulary_list.append(word_obj)

    # Wrap the list in the final JSON structure
    final_json = {
        'vocabulary': vocabulary_list,
        'grammarExercises': [],
    }

    print(f"Saving {len(vocabulary_list)} words to '{output_file}'...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(final_json, f, indent=2, ensure_ascii=False)
        
    print("Done. ✨")
    print(f"Copy '{output_file}' to your Flutter project's 'assets/data/' directory.")
    
    # Print some stats
    bw_words = sum(1 for w in vocabulary_list if w['isGrundwortschatzBW'])
    plural_only = sum(1 for w in vocabulary_list if w['nurImPlural'])
    print(f"\nStatistics:")
    print(f"  Total words: {len(vocabulary_list)}")
    print(f"  BW Grundwortschatz words: {bw_words}")
    print(f"  Plural-only nouns: {plural_only}")

if __name__ == "__main__":
    convert_csv_to_json(INPUT_CSV_FILE, OUTPUT_JSON_FILE)