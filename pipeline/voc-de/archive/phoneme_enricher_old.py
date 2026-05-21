
import pandas as pd
import json
import os
import sys
import re

# --- espeak-ng setup for macOS ---
from phonemizer.backend.espeak.wrapper import EspeakWrapper
espeak_lib_path = '/opt/homebrew/lib/libespeak-ng.dylib'
EspeakWrapper.set_library(espeak_lib_path)

from phonemizer import phonemize

# --- Configuration ---
INPUT_CSV_FILE = 'voc_de_enriched.csv'
OUTPUT_CSV_FILE = 'voc_de_phonemized.csv'
OUTPUT_JSON_FILE = 'grundwortschatz_phonemized.json'

# --- Helper for progress ---
try:
    from tqdm import tqdm
    print("Progress bar enabled (tqdm found).")
except ImportError:
    print("Note: Install 'tqdm' for progress bars.")
    def tqdm(iterable, **kwargs):
        return iterable

# --- IPA to X-SAMPA Mapping ---
IPA_TO_XSAMPA = {
    # Vowels
    'i': 'i',
    'y': 'y',
    'ɨ': '1',
    'ʉ': '}',
    'ɯ': 'M',
    'u': 'u',
    'ɪ': 'I',
    'ʏ': 'Y',
    'ʊ': 'U',
    'e': 'e',
    'ø': '2',
    'ɘ': '@\\',
    'ɵ': '8',
    'ɤ': '7',
    'o': 'o',
    'ə': '@',
    'ɛ': 'E',
    'œ': '9',
    'ɜ': '3',
    'ɞ': '3\\',
    'ʌ': 'V',
    'ɔ': 'O',
    'æ': '{',
    'ɐ': '6',
    'a': 'a',
    'ɶ': '&',
    'ɑ': 'A',
    'ɒ': 'Q',
    
    # Consonants
    'p': 'p',
    'b': 'b',
    't': 't',
    'd': 'd',
    'ʈ': 't`',
    'ɖ': 'd`',
    'c': 'c',
    'ɟ': 'J\\',
    'k': 'k',
    'g': 'g',
    'q': 'q',
    'ɢ': 'G\\',
    'ʔ': '?',
    'm': 'm',
    'ɱ': 'F',
    'n': 'n',
    'ɳ': 'n`',
    'ɲ': 'J',
    'ŋ': 'N',
    'ɴ': 'N\\',
    'ʙ': 'B\\',
    'r': 'r',
    'ʀ': 'R\\',
    'ⱱ': 'v\\',
    'ɾ': '4',
    'ɽ': 'r`',
    'ɸ': 'p\\',
    'β': 'B',
    'f': 'f',
    'v': 'v',
    'θ': 'T',
    'ð': 'D',
    's': 's',
    'z': 'z',
    'ʃ': 'S',
    'ʒ': 'Z',
    'ʂ': 's`',
    'ʐ': 'z`',
    'ç': 'C',
    'ʝ': 'j\\',
    'x': 'x',
    'ɣ': 'G',
    'χ': 'X',
    'ʁ': 'R',
    'ħ': 'X\\',
    'ʕ': '?\\',
    'h': 'h',
    'ɦ': 'h\\',
    'ɬ': 'K',
    'ɮ': 'K\\',
    'ʋ': 'P',
    'ɹ': 'r\\',
    'ɻ': 'r\\`',
    'j': 'j',
    'ɰ': 'M\\',
    'l': 'l',
    'ɭ': 'l`',
    'ʎ': 'L',
    'ʟ': 'L\\',
    'w': 'w',
    'ʍ': 'W',
    'ɥ': 'H',
    
    # Affricates (common German ones)
    'p͡f': 'pf',
    't͡s': 'ts',
    't͡ʃ': 'tS',
    'd͡ʒ': 'dZ',
    
    # Diacritics and suprasegmentals
    'ː': ':',      # Length mark
    'ˈ': '"',      # Primary stress
    'ˌ': '%',      # Secondary stress
    'ʰ': '_h',     # Aspirated
    'ʷ': '_w',     # Labialized
    'ʲ': "'",      # Palatalized
    'ˠ': '_G',     # Velarized
    'ˤ': '_?\\',   # Pharyngealized
    '̃': '~',       # Nasalized (combining)
    'ⁿ': '~',      # Nasal release
}

def ipa_to_xsampa(ipa_string):
    """
    Converts IPA string to X-SAMPA.
    Handles multi-character sequences first, then single characters.
    """
    if not ipa_string:
        return ''
    
    result = ipa_string
    
    # Sort by length (longest first) to handle multi-char sequences
    sorted_mappings = sorted(IPA_TO_XSAMPA.items(), key=lambda x: len(x[0]), reverse=True)
    
    for ipa_char, xsampa_char in sorted_mappings:
        result = result.replace(ipa_char, xsampa_char)
    
    return result

def phonemize_words_batch(words, language='de', batch_size=100):
    """
    Phonemizes a list of words in batches for efficiency.
    Returns lists of IPA and X-SAMPA transcriptions.
    """
    ipa_results = []
    sampa_results = []
    
    print(f"Phonemizing {len(words)} words in batches of {batch_size}...")
    
    for i in tqdm(range(0, len(words), batch_size), desc="Batch progress"):
        batch = words[i:i + batch_size]
        
        try:
            # Phonemize batch - IPA
            ipa_list = phonemize(
                batch,
                language=language,
                backend='espeak',
                strip=True,
                preserve_punctuation=False,
                with_stress=True
            )
            
            # Ensure it's a list
            if not isinstance(ipa_list, list):
                ipa_list = [ipa_list]
            
            # Ensure we have the same number of results as inputs
            while len(ipa_list) < len(batch):
                ipa_list.append('')
                
            ipa_results.extend(ipa_list[:len(batch)])
            
            # Convert IPA to X-SAMPA
            sampa_list = [ipa_to_xsampa(ipa) for ipa in ipa_list[:len(batch)]]
            sampa_results.extend(sampa_list)
            
        except Exception as e:
            print(f"Warning: Batch phonemization failed: {e}", file=sys.stderr)
            # Add empty strings for failed batch
            ipa_results.extend([''] * len(batch))
            sampa_results.extend([''] * len(batch))
    
    return ipa_results, sampa_results

def add_phonemes_to_csv(input_file, output_file):
    """
    Reads the enriched CSV, adds IPA and SAMPA columns, and saves.
    """
    print(f"Loading '{input_file}'...")
    try:
        df = pd.read_csv(input_file, delimiter=';')
    except FileNotFoundError:
        print(f"Error: File not found: '{input_file}'")
        print("Please run 'enrich.py' first.")
        sys.exit(1)
    
    df = df.fillna('')
    print(f"Loaded {len(df)} entries.")
    
    # Get all words
    words = df['Word'].astype(str).tolist()
    
    # Phonemize in batch
    ipa_list, sampa_list = phonemize_words_batch(words, language='de')
    
    # Add to dataframe
    df['IPA_phoneme'] = ipa_list
    df['SAMPA_phoneme'] = sampa_list
    
    # Save to new CSV
    print(f"Saving phonemized data to '{output_file}'...")
    df.to_csv(output_file, sep=';', index=False, encoding='utf-8')
    
    print(f"✓ Successfully saved {len(df)} entries with phonemes.")
    print("\nSample entries:")
    print(df[['Word', 'IPA_phoneme', 'SAMPA_phoneme']].head(10))
    
    return df

def csv_to_json_with_phonemes(df, output_file):
    """
    Converts the phonemized CSV to JSON format with all fields.
    """
    print(f"\nConverting to JSON format...")
    
    # Mapping from CSV 'Wortart' to Dart enum strings
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
        """Parse sources and return list, grade level, and BW flag."""
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
                grade_levels.append(1)
                is_bw = True
            elif source == 'BW3':
                grade_levels.append(3)
                is_bw = True
        
        max_grade = max(grade_levels) if grade_levels else 1
        return sources, max_grade, is_bw
    
    vocabulary_list = []
    word_id_counter = 1
    
    for index, row in df.iterrows():
        word_id = f"word_{word_id_counter:05d}"
        word_id_counter += 1
        
        # Map Wortart
        wortart = row['Wortart']
        enum_wortart = WORTART_TO_ENUM_MAP.get(wortart, 'andere')
        
        # Parse sources
        sources, grade_level, is_bw = parse_sources(row['Source'])
        
        # Handle nur_im_Plural
        nur_im_plural_val = row.get('nur_im_Plural', '')
        nur_im_plural = (nur_im_plural_val not in ['', '0', '0.0'])
        
        # Create JSON object
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
            'genus': row.get('Genus', ''),
            'nurImPlural': nur_im_plural,
            'url': row['URL'],
            
            # Phoneme fields
            'ipaPhoneme': row.get('IPA_phoneme', ''),
            'sampaPhoneme': row.get('SAMPA_phoneme', ''),
            
            # spaCy morphological fields
            'caseSpacy': row['Case_spacy'],
            'numberSpacy': row['Number_spacy'],
            'degreeSpacy': row['Degree_spacy'],
            'pronTypeSpacy': row['PronType_spacy'],
            'verbFormSpacy': row['VerbForm_spacy'],
            
            # App-specific fields
            'plural': None,
            'categories': [],
            'exampleSentences': [],
            'spellingDifficulty': 0,
            'commonMistakes': None,
            'audioPath': None,
        }
        
        vocabulary_list.append(word_obj)
    
    # Create final JSON structure
    final_json = {
        'vocabulary': vocabulary_list,
        'grammarExercises': [],
    }
    
    # Save JSON
    print(f"Saving {len(vocabulary_list)} words to '{output_file}'...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(final_json, f, indent=2, ensure_ascii=False)
    
    print(f"✓ Successfully saved JSON.")
    
    # Statistics
    phonemized_count = sum(1 for w in vocabulary_list if w['ipaPhoneme'])
    bw_count = sum(1 for w in vocabulary_list if w['isGrundwortschatzBW'])
    
    print(f"\n=== Statistics ===")
    print(f"Total words: {len(vocabulary_list)}")
    print(f"Words with phonemes: {phonemized_count} ({phonemized_count/len(vocabulary_list)*100:.1f}%)")
    print(f"BW Grundwortschatz words: {bw_count}")

def main():
    """
    Main execution: Read CSV, add phonemes, save CSV and JSON.
    """
    print("=" * 60)
    print("German Vocabulary Phonemization Script")
    print("=" * 60)
    
    # Step 1: Add phonemes to CSV
    df_phonemized = add_phonemes_to_csv(INPUT_CSV_FILE, OUTPUT_CSV_FILE)
    
    # Step 2: Convert to JSON with phonemes
    csv_to_json_with_phonemes(df_phonemized, OUTPUT_JSON_FILE)
    
    print("\n" + "=" * 60)
    print("✨ All done!")
    print(f"CSV: {OUTPUT_CSV_FILE}")
    print(f"JSON: {OUTPUT_JSON_FILE}")
    print("=" * 60)

if __name__ == "__main__":
    main()