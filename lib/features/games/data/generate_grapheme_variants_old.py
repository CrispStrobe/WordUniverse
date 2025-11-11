# Save this as: generate_grapheme_variants.py

import json
import itertools
from collections import defaultdict
import re

# --- Configuration ---
GRAPHEME_FILE = 'grapheme.json'
INPUT_JSON_FILE = 'grundwortschatz_phonemized.json'
OUTPUT_JSON_FILE = 'grundwortschatz_variations.json'
MAX_VARIANTS_PER_WORD = 20  # Limit to avoid explosion

# Manual fallback mappings for phonemes not in grapheme.json
# These are common German phonemes that espeak generates
FALLBACK_MAPPINGS = {
    # R-sounds (all map to 'r')
    'ɾ': [('r', 100.0)],  # tap/flap r
    'r': [('r', 100.0)],  # trilled r
    'ʀ': [('r', 100.0)],  # uvular trill
    'ʁ': [('r', 100.0)],  # uvular fricative (already in main mapping but included for safety)
    
    # A-sounds
    'ɑ': [('a', 90.0), ('ah', 10.0)],  # open back a (like in "Vater")
    'ɐ': [('er', 60.0), ('a', 40.0)],  # near-open central (reduced, like final -er)
    
    # E/schwa-r sounds
    'ɜ': [('er', 100.0)],  # open-mid central (r-colored schwa, like in "Butter")
    'ɚ': [('er', 100.0)],  # r-colored schwa
    'e': [('e', 87.44), ('ä', 12.56)],  # short e (like in grapheme.json /ε/)
    
    # G-sound
    'ɡ': [('g', 100.0)],  # voiced velar stop
    
    # O-sounds (if not already mapped)
    'ɒ': [('o', 100.0)],  # open back rounded
    
    # Additional umlauts (if espeak uses different symbols)
    # Add common learner mistakes for umlauts
    'ø': [('ö', 60.0), ('öh', 10.0), ('oe', 20.0), ('oi', 10.0)],  # ö with alternatives
    'œ': [('ö', 100.0)],  # short ö
    
    # I-sounds (from loanwords)
    'i': [('i', 99.75), ('ie', 0.25)],  # short i (like in grapheme.json /I/)
    
    # W-sound (English loanwords)
    'w': [('w', 99.25), ('v', 0.75)],  # same as in grapheme.json /v/
    
    # Zh-sound (French loanwords like "Garage")
    'ʒ': [('g', 70.0), ('j', 30.0)],  # voiced postalveolar fricative
    
    # Diacritics and combining marks
    '̃': [('n', 100.0)],  # nasalization (approximate with 'n')
    '̩': [],  # syllabic consonant marker (ignore it, the consonant is already there)
    
    # Ignore these characters (don't map them)
    ' ': [],  # space
    '(': [],  # parenthesis
    ')': [],  # parenthesis
    '-': [],  # hyphen
}

def load_grapheme_mapping(grapheme_file):
    """
    Loads grapheme.json and creates a lookup dictionary:
    {ipa_phoneme: [(grapheme, probability), ...]}
    Also adds fallback mappings.
    """
    print(f"Loading grapheme mappings from '{grapheme_file}'...")
    
    with open(grapheme_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    phoneme_to_graphemes = {}
    
    for kategorie in data['kategorien']:
        for eintrag in kategorie['eintraege']:
            ipa_raw = eintrag['ipa_phonem']
            
            # Handle cases like "x / ç" - split and map both
            ipa_variants = [p.strip() for p in ipa_raw.split('/')]
            
            # Collect all graphemes for this phoneme
            graphemes = []
            
            # Add base grapheme
            base = eintrag['basisgraphem']
            graphemes.append((
                base['graphem'].strip('<>'),  # Remove < > markers
                base['prozent']
            ))
            
            # Add orthographemes
            for ortho in eintrag.get('orthographeme', []):
                graphemes.append((
                    ortho['graphem'].strip('<>'),
                    ortho['prozent']
                ))
            
            # Sort by probability (highest first)
            graphemes.sort(key=lambda x: x[1], reverse=True)
            
            # Map ALL IPA variants to the same graphemes
            for ipa in ipa_variants:
                phoneme_to_graphemes[ipa] = graphemes
    
    # Add fallback mappings
    print(f"Adding {len(FALLBACK_MAPPINGS)} fallback mappings...")
    for phoneme, graphemes in FALLBACK_MAPPINGS.items():
        if phoneme not in phoneme_to_graphemes and graphemes:  # Only add if not already mapped and not empty
            phoneme_to_graphemes[phoneme] = graphemes
    
    print(f"Total phoneme mappings: {len(phoneme_to_graphemes)}")
    
    # Debug: show what we have for problematic phonemes
    test_phonemes = ['ç', 'x', 'ʃ', 'ŋ', 'ɑ', 'ɾ', 'r', 'ɡ', 'ɜ', 'ø', 'e', 'i', 'w', 'ʒ', 'ɔʏ', 'ɔø']
    print("\nDebug - Sample mappings:")
    for p in test_phonemes:
        if p in phoneme_to_graphemes:
            graphemes_str = ', '.join([f"{g}({prob:.1f}%)" for g, prob in phoneme_to_graphemes[p][:4]])
            print(f"  {p} → {graphemes_str}")
        else:
            print(f"  {p} → NOT MAPPED")
    
    return phoneme_to_graphemes

def parse_ipa_to_phonemes(ipa_string):
    """
    Parses an IPA string into a list of individual phonemes.
    Handles multi-character phonemes and diacritics.
    """
    if not ipa_string:
        return []
    
    # Define multi-character phonemes (longest first for proper matching)
    # IMPORTANT: Add espeak's variant diphthongs!
    multi_char_phonemes = [
        'aɪ', 'aʊ', 'ɔʏ',  # Standard diphthongs from grapheme.json
        'ɔø',  # espeak variant of ɔʏ (freuen, heute, etc.)
        't͡s', 'p͡f', 't͡ʃ', 'd͡ʒ',  # Affricates
        'eː', 'iː', 'oː', 'uː', 'aː', 'ɛː', 'øː', 'yː',  # Long vowels
    ]
    
    # Stress and length markers (to preserve but not match as separate phonemes)
    diacritics = ['ˈ', 'ˌ', 'ː']
    
    phonemes = []
    i = 0
    
    while i < len(ipa_string):
        # Check for stress markers (keep them separate)
        if ipa_string[i] in diacritics:
            phonemes.append(ipa_string[i])
            i += 1
            continue
        
        # Try to match multi-character phonemes
        matched = False
        for multi in multi_char_phonemes:
            if ipa_string[i:i+len(multi)] == multi:
                phonemes.append(multi)
                i += len(multi)
                matched = True
                break
        
        if not matched:
            # Single character phoneme
            phonemes.append(ipa_string[i])
            i += 1
    
    return phonemes

def clean_word(word):
    """
    Cleans word by removing parentheses and extra spaces.
    "(ein) bisschen" → "ein bisschen"
    """
    # Remove parentheses
    word = word.replace('(', '').replace(')', '')
    # Normalize spaces
    word = ' '.join(word.split())
    return word.strip()

def generate_grapheme_variants(word, ipa_phoneme, phoneme_to_graphemes, max_variants=MAX_VARIANTS_PER_WORD):
    """
    Generates spelling variants for a word based on its IPA transcription.
    Returns a list of (variant, probability) tuples, sorted by probability.
    """
    if not ipa_phoneme:
        return []
    
    # Clean the word
    clean_w = clean_word(word)
    
    # Parse IPA into phonemes
    phonemes = parse_ipa_to_phonemes(ipa_phoneme)
    
    if not phonemes:
        return []
    
    # For each phoneme, get possible graphemes
    phoneme_grapheme_options = []
    unmapped_phonemes = []
    
    for phoneme in phonemes:
        # Skip stress markers and length markers for grapheme mapping
        if phoneme in ['ˈ', 'ˌ', 'ː']:
            continue
        
        # Special handling: map ɔø to the same as ɔʏ (the eu/äu diphthong)
        if phoneme == 'ɔø':
            # Use the mapping from ɔʏ if available
            if 'ɔʏ' in phoneme_to_graphemes:
                options = phoneme_to_graphemes['ɔʏ']
                phoneme_grapheme_options.append(options)
                continue
        
        # Look up grapheme options
        if phoneme in phoneme_to_graphemes:
            options = phoneme_to_graphemes[phoneme]
            # Only add if there are actual grapheme options (empty list means "skip this phoneme")
            if options:
                phoneme_grapheme_options.append(options)
        else:
            # No mapping found
            unmapped_phonemes.append(phoneme)
    
    # If we have unmapped phonemes that aren't in our "skip" list, warn
    skip_chars = [' ', '(', ')', '-', '̩']
    real_unmapped = [p for p in unmapped_phonemes if p not in skip_chars]
    if real_unmapped:
        print(f"Warning: Word '{word}' has unmapped phonemes: {real_unmapped}")
        return []
    
    # Generate all combinations
    if not phoneme_grapheme_options:
        return []
    
    # Limit combinations to prevent explosion
    total_combinations = 1
    for options in phoneme_grapheme_options:
        total_combinations *= len(options)
    
    if total_combinations > 1000:
        # Reduce options per phoneme to keep it manageable
        max_options_per_phoneme = 2
        phoneme_grapheme_options = [
            options[:max_options_per_phoneme] for options in phoneme_grapheme_options
        ]
    
    # Generate all combinations
    all_combinations = list(itertools.product(*phoneme_grapheme_options))
    
    # Calculate variants with probabilities
    variants = []
    
    for combo in all_combinations:
        # Build the spelling variant
        variant_spelling = ''.join(grapheme for grapheme, _ in combo)
        
        # Calculate combined probability
        probability = 1.0
        for _, prob in combo:
            probability *= (prob / 100.0)
        probability *= 100.0
        
        # Skip the original word spelling (cleaned)
        if variant_spelling.lower() == clean_w.lower().replace(' ', ''):
            continue
        
        variants.append({
            'spelling': variant_spelling,
            'probability': round(probability, 4)
        })
    
    # Sort by probability (highest first) and limit
    variants.sort(key=lambda x: x['probability'], reverse=True)
    
    return variants[:max_variants]

def enrich_with_variants(input_file, output_file, phoneme_to_graphemes):
    """
    Loads the phonemized JSON, adds grapheme variants, and saves.
    """
    print(f"\nLoading '{input_file}'...")
    
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    vocabulary = data.get('vocabulary', [])
    print(f"Loaded {len(vocabulary)} words.")
    
    print("Generating grapheme variants for each word...")
    
    words_with_variants = 0
    total_variants = 0
    words_skipped = 0
    
    for entry in vocabulary:
        word = entry.get('word', '')
        ipa = entry.get('ipaPhoneme', '')
        
        if not ipa:
            entry['graphematicVariants'] = []
            continue
        
        # Generate variants
        variants = generate_grapheme_variants(word, ipa, phoneme_to_graphemes)
        
        entry['graphematicVariants'] = variants
        
        if variants:
            words_with_variants += 1
            total_variants += len(variants)
        else:
            words_skipped += 1
    
    # Save enriched data
    print(f"\nSaving enriched data to '{output_file}'...")
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    
    print(f"✓ Successfully saved enriched data.")
    print(f"\n=== Statistics ===")
    print(f"Total words: {len(vocabulary)}")
    print(f"Words with variants: {words_with_variants}")
    print(f"Words skipped (unmapped phonemes): {words_skipped}")
    print(f"Total variants generated: {total_variants}")
    if words_with_variants > 0:
        print(f"Average variants per word: {total_variants/words_with_variants:.1f}")

def main():
    """
    Main execution: Load grapheme mappings, generate variants, save.
    """
    print("=" * 60)
    print("Grapheme Variant Generation Script")
    print("=" * 60)
    
    # Step 1: Load grapheme mappings
    phoneme_to_graphemes = load_grapheme_mapping(GRAPHEME_FILE)
    
    # Step 2: Generate and add variants
    enrich_with_variants(INPUT_JSON_FILE, OUTPUT_JSON_FILE, phoneme_to_graphemes)
    
    print("\n" + "=" * 60)
    print("✨ All done!")
    print(f"Output: {OUTPUT_JSON_FILE}")
    print("=" * 60)
    
    # Show samples
    print("\n=== Sample Output ===")
    with open(OUTPUT_JSON_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # Find words with variants to show
    sample_count = 0
    for entry in data['vocabulary']:
        if entry.get('graphematicVariants') and sample_count < 5:
            word = entry['word']
            ipa = entry['ipaPhoneme']
            variants = entry['graphematicVariants'][:5]
            
            print(f"\nWord: {word}")
            print(f"IPA: {ipa}")
            print("Top variants:")
            for v in variants:
                print(f"  - {v['spelling']} (probability: {v['probability']:.2f}%)")
            sample_count += 1

if __name__ == "__main__":
    main()