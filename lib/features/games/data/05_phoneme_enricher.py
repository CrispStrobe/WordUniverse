import json
import sys

# --- espeak-ng setup for macOS ---
from phonemizer.backend.espeak.wrapper import EspeakWrapper
espeak_lib_path = '/opt/homebrew/lib/libespeak-ng.dylib'
EspeakWrapper.set_library(espeak_lib_path)

from phonemizer import phonemize

# --- Configuration ---
INPUT_JSON_FILE = 'grundwortschatz.json'
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
    """Converts IPA string to X-SAMPA."""
    if not ipa_string:
        return ''
    
    result = ipa_string
    # Sort by length (longest first) to handle multi-char sequences
    sorted_mappings = sorted(IPA_TO_XSAMPA.items(), key=lambda x: len(x[0]), reverse=True)
    
    for ipa_char, xsampa_char in sorted_mappings:
        result = result.replace(ipa_char, xsampa_char)
    
    return result

def phonemize_words_batch(words, language='de', batch_size=100):
    """Phonemizes a list of words in batches for efficiency."""
    ipa_results = []
    sampa_results = []
    
    print(f"Phonemizing {len(words)} words in batches of {batch_size}...")
    
    for i in tqdm(range(0, len(words), batch_size), desc="Phonemizing"):
        batch = words[i:i + batch_size]
        
        try:
            ipa_list = phonemize(
                batch,
                language=language,
                backend='espeak',
                strip=True,
                preserve_punctuation=False,
                with_stress=True
            )
            
            if not isinstance(ipa_list, list):
                ipa_list = [ipa_list]
            
            while len(ipa_list) < len(batch):
                ipa_list.append('')
                
            ipa_results.extend(ipa_list[:len(batch)])
            sampa_list = [ipa_to_xsampa(ipa) for ipa in ipa_list[:len(batch)]]
            sampa_results.extend(sampa_list)
            
        except Exception as e:
            print(f"Warning: Batch phonemization failed: {e}", file=sys.stderr)
            ipa_results.extend([''] * len(batch))
            sampa_results.extend([''] * len(batch))
    
    return ipa_results, sampa_results

def add_phonemes_to_json(input_file, output_file):
    """
    Loads grundwortschatz.json, adds phoneme fields, and saves to new file.
    """
    print("=" * 60)
    print("German Vocabulary Phonemization Script")
    print("=" * 60)
    
    # Load JSON
    print(f"\nLoading '{input_file}'...")
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: File not found: '{input_file}'")
        print("Please run the JSON conversion script first.")
        sys.exit(1)
    
    vocabulary = data.get('vocabulary', [])
    print(f"Loaded {len(vocabulary)} words.")
    
    if not vocabulary:
        print("Error: No vocabulary found in JSON file.")
        sys.exit(1)
    
    # Extract words
    words = [word_obj['word'] for word_obj in vocabulary]
    
    # Phonemize
    print("\nPhonemizing words...")
    ipa_list, sampa_list = phonemize_words_batch(words, language='de')
    
    # Add phonemes to each word object
    print("\nAdding phonemes to vocabulary entries...")
    for i, word_obj in enumerate(tqdm(vocabulary, desc="Adding phonemes")):
        word_obj['ipaPhoneme'] = ipa_list[i] if ipa_list[i] else None
        word_obj['sampaPhoneme'] = sampa_list[i] if sampa_list[i] else None
    
    # Update metadata if it exists
    if 'metadata' in data:
        data['metadata']['phonemized'] = True
        data['metadata']['phonemizationDate'] = None  # Could add timestamp here
    
    # Save to output file
    print(f"\nSaving phonemized vocabulary to '{output_file}'...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    
    # Statistics
    phonemized_count = sum(1 for w in vocabulary if w.get('ipaPhoneme'))
    
    print("\n" + "=" * 60)
    print("✨ All done!")
    print("=" * 60)
    print(f"\n=== Statistics ===")
    print(f"Total words: {len(vocabulary)}")
    print(f"Words with phonemes: {phonemized_count} ({phonemized_count/len(vocabulary)*100:.1f}%)")
    
    # Show sample
    print(f"\nSample of phonemized words:")
    for i, word_obj in enumerate(vocabulary[:10], 1):
        word = word_obj['word']
        ipa = word_obj.get('ipaPhoneme', 'N/A')
        sampa = word_obj.get('sampaPhoneme', 'N/A')
        print(f"  {i}. {word:15} IPA: {ipa:20} SAMPA: {sampa}")
    
    print(f"\n✓ Output saved to: {output_file}")
    print("Copy this file to your Flutter project's 'assets/data/' directory.")

def main():
    add_phonemes_to_json(INPUT_JSON_FILE, OUTPUT_JSON_FILE)

if __name__ == "__main__":
    main()