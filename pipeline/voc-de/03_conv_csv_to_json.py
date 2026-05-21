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
    - A list of all sources (e.g., ['A1', 'BW3', 'LEEDS', 'BUCHMEIER'])
    - The *lowest* applicable grade level based on priority
    - Whether it's part of BW Grundwortschatz
    """
    if not source_str:
        return [], 5, False  # Default grade 1 if no sources

    sources = [s.strip() for s in source_str.split(',')]
    
    school_grades = []
    cefr_grades = []
    is_bw = False
    
    for source in sources:
        # --- School Grade Lists (Highest Priority) ---
        if source == 'BW1':
            school_grades.append(1)  # Grades 1&2
            is_bw = True
        elif source == 'BW3':
            school_grades.append(3)  # Grades 3&4
            is_bw = True
        elif source == 'NRW111':
            school_grades.append(1)  # Merkwörter (sight words), assume Grade 1
        # Add other school lists like 'NRW422' here if needed
        # elif source == 'NRW422':
        #     school_grades.append(2) # Nachdenkwörter
            
        # --- CEFR Levels (Secondary) ---
        # These are only used if no school grades are found
        elif source == 'A1':
            cefr_grades.append(4)  # Per your request
        elif source == 'A2':
            cefr_grades.append(5)  # Per your request
        elif source == 'B1':
            cefr_grades.append(6)  # Per your request
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
    
    # If neither list was populated (e.g., only 'HERMIT', 'LEEDS'),
    # the grade remains the default of 5.
        
    return sources, final_grade, is_bw

def safe_int(value):
    """Convert value to int, return None if empty/invalid"""
    if pd.isna(value) or value == '' or value == '0' or value == '0.0':
        return None
    try:
        return int(float(value))
    except (ValueError, TypeError):
        return None

def safe_float(value):
    """Convert value to float, return None if empty/invalid"""
    if pd.isna(value) or value == '' or value == '0' or value == '0.0':
        return None
    try:
        return float(value)
    except (ValueError, TypeError):
        return None

def build_frequency_data(row):
    """
    Build frequency data object from row.
    Returns a dict with frequency info from all sources.
    """
    freq_data = {}
    
    # Buchmeier
    buchmeier_rank = safe_int(row.get('BUCHMEIER_rank', ''))
    buchmeier_freq = safe_int(row.get('BUCHMEIER_freq', ''))
    if buchmeier_rank is not None or buchmeier_freq is not None:
        freq_data['buchmeier'] = {
            'rank': buchmeier_rank,
            'frequency': buchmeier_freq
        }
    
    # Leeds
    leeds_rank = safe_int(row.get('LEEDS_rank', ''))
    leeds_freq = safe_float(row.get('LEEDS_freq', ''))
    if leeds_rank is not None or leeds_freq is not None:
        freq_data['leeds'] = {
            'rank': leeds_rank,
            'frequency': leeds_freq
        }
    
    # Leipzig
    leipzig_rank = safe_int(row.get('LEIPZIG_rank', ''))
    if leipzig_rank is not None:
        freq_data['leipzig'] = {
            'rank': leipzig_rank
        }
    
    # Hermit
    hermit_rank = safe_int(row.get('HERMIT_rank', ''))
    hermit_freq = safe_int(row.get('HERMIT_freq', ''))
    if hermit_rank is not None or hermit_freq is not None:
        freq_data['hermit'] = {
            'rank': hermit_rank,
            'frequency': hermit_freq
        }
    
    return freq_data if freq_data else None

def calculate_avg_rank(freq_data):
    """
    Calculate average rank across all sources that have rank data.
    Returns None if no rank data available.
    """
    if not freq_data:
        return None
    
    ranks = []
    for source_data in freq_data.values():
        if source_data.get('rank') is not None:
            ranks.append(source_data['rank'])
    
    if not ranks:
        return None
    
    return round(sum(ranks) / len(ranks), 1)

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
        
        # Build frequency data
        freq_data = build_frequency_data(row)
        avg_rank = calculate_avg_rank(freq_data)
        
        # Create the JSON object for this word
        word_obj = {
            'id': word_id,
            'word': row['Word'],
            'article': row['Article'] if row['Article'] else None,
            'wordType': enum_wortart,
            'gradeLevel': grade_level,
            'sources': sources,
            'isGrundwortschatzBW': is_bw,
            'lemma': row['Lemma_spacy'] if row['Lemma_spacy'] else None,
            'forms': row['Forms'] if row['Forms'] else None,
            'genus': row.get('Genus', '') if row.get('Genus', '') else None,
            'nurImPlural': nur_im_plural,
            'url': row['URL'] if row['URL'] else None,
            
            # spaCy morphological fields
            'caseSpacy': row['Case_spacy'] if row['Case_spacy'] else None,
            'numberSpacy': row['Number_spacy'] if row['Number_spacy'] else None,
            'degreeSpacy': row['Degree_spacy'] if row['Degree_spacy'] else None,
            'pronTypeSpacy': row['PronType_spacy'] if row['PronType_spacy'] else None,
            'verbFormSpacy': row['VerbForm_spacy'] if row['VerbForm_spacy'] else None,
            
            # Frequency data
            'frequencyData': freq_data,
            'averageRank': avg_rank,
            
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
        'metadata': {
            'version': '1.0',
            'generatedAt': pd.Timestamp.now().isoformat(),
            'totalWords': len(vocabulary_list),
            'sources': ['A1', 'A2', 'B1', 'BW1', 'BW3', 'BUCHMEIER', 'LEEDS', 'LEIPZIG', 'HERMIT']
        }
    }

    print(f"Saving {len(vocabulary_list)} words to '{output_file}'...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(final_json, f, indent=2, ensure_ascii=False)
        
    print("Done. ✨")
    print(f"Copy '{output_file}' to your Flutter project's 'assets/data/' directory.")
    
    # Print some stats
    bw_words = sum(1 for w in vocabulary_list if w['isGrundwortschatzBW'])
    plural_only = sum(1 for w in vocabulary_list if w['nurImPlural'])
    freq_words = sum(1 for w in vocabulary_list if w['frequencyData'])
    buchmeier_words = sum(1 for w in vocabulary_list if w['frequencyData'] and 'buchmeier' in w['frequencyData'])
    
    print(f"\nStatistics:")
    print(f"  Total words: {len(vocabulary_list)}")
    print(f"  BW Grundwortschatz words: {bw_words}")
    print(f"  Plural-only nouns: {plural_only}")
    print(f"  Words with frequency data: {freq_words}")
    print(f"  Words in Buchmeier: {buchmeier_words}")
    
    # Show sample of top words by average rank
    print(f"\nTop 10 most frequent words (by average rank):")
    sorted_by_freq = sorted(vocabulary_list, key=lambda x: x['averageRank'] if x['averageRank'] else float('inf'))
    for i, word in enumerate(sorted_by_freq[:10], 1):
        avg = word['averageRank']
        freq_info = word['frequencyData']
        sources_info = ', '.join(freq_info.keys()) if freq_info else 'none'
        print(f"  {i}. {word['word']} (avg rank: {avg}, sources: {sources_info})")

if __name__ == "__main__":
    convert_csv_to_json(INPUT_CSV_FILE, OUTPUT_JSON_FILE)