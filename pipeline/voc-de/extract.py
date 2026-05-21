#!/usr/bin/env python3
"""
Map ORTHOGRAPHIC errors (not grammatical) from Falko-MERLIN to Grundwortschatz
Filters out inflectional changes (ein→eine, viel→viele, etc.)
"""
import json
from collections import defaultdict, Counter
from difflib import SequenceMatcher
import re
import Levenshtein

# Common German inflectional suffixes to detect grammatical changes
INFLECTIONAL_SUFFIXES = [
    'e', 'en', 'er', 'em', 'es', 's', 'n', 'm', 'r',  # Articles, adjectives
    'st', 'est', 't', 'te', 'ten', 'test', 'tet',     # Verbs
]

def normalize_word(word):
    """Remove punctuation, keep umlauts, lowercase"""
    return re.sub(r'[^\wäöüßÄÖÜ]', '', word).lower()

def get_stem(word):
    """
    Get approximate stem by removing common suffixes
    This is crude but effective for filtering inflectional changes
    """
    word_norm = normalize_word(word)
    
    # Try removing suffixes
    for suffix in sorted(INFLECTIONAL_SUFFIXES, key=len, reverse=True):
        if word_norm.endswith(suffix) and len(word_norm) > len(suffix) + 2:
            return word_norm[:-len(suffix)]
    
    return word_norm

def is_likely_inflectional_change(word1, word2):
    """
    Check if two words differ only by inflection (grammatical),
    not by spelling (orthographic)
    """
    norm1 = normalize_word(word1)
    norm2 = normalize_word(word2)
    
    if not norm1 or not norm2:
        return False
    
    # Check if stems are identical
    stem1 = get_stem(word1)
    stem2 = get_stem(word2)
    
    if stem1 == stem2 and stem1:
        return True
    
    # Check for simple suffix addition/removal
    # e.g., "viel" vs "viele" - one is substring of other
    if norm1 in norm2 or norm2 in norm1:
        diff_len = abs(len(norm1) - len(norm2))
        # If difference is just 1-2 chars and it's a known suffix
        if diff_len <= 2:
            longer = norm1 if len(norm1) > len(norm2) else norm2
            shorter = norm2 if len(norm1) > len(norm2) else norm1
            suffix = longer[len(shorter):]
            if suffix in INFLECTIONAL_SUFFIXES:
                return True
    
    return False

def is_only_capitalization_change(word1, word2):
    """Check if words differ only in capitalization"""
    return normalize_word(word1) == normalize_word(word2)

def is_orthographic_error(correct_word, error_word):
    """
    Determine if this is a TRUE orthographic (spelling) error,
    not a grammatical or capitalization change
    """
    # Filter 1: Must be similar
    norm1 = normalize_word(correct_word)
    norm2 = normalize_word(error_word)
    
    if not norm1 or not norm2:
        return False
    
    # Filter 2: Not just capitalization
    if is_only_capitalization_change(correct_word, error_word):
        return False
    
    # Filter 3: Not inflectional change
    if is_likely_inflectional_change(correct_word, error_word):
        return False
    
    # Filter 4: Must be reasonably similar (not completely different words)
    len_diff = abs(len(norm1) - len(norm2))
    if len_diff > 4:
        return False
    
    edit_dist = Levenshtein.distance(norm1, norm2)
    if edit_dist > 4:
        return False
    
    # Filter 5: Must share reasonable character overlap
    set1 = set(norm1)
    set2 = set(norm2)
    overlap = len(set1 & set2) / len(set1 | set2) if (set1 | set2) else 0
    
    if overlap < 0.5:
        return False
    
    return True

def extract_orthographic_errors(learner_file, correct_file):
    """
    Extract ONLY orthographic errors (not grammatical or capitalization)
    """
    word_errors = defaultdict(Counter)
    total_candidates = 0
    total_filtered = 0
    
    with open(learner_file, 'r', encoding='utf-8') as learner, \
         open(correct_file, 'r', encoding='utf-8') as correct:
        
        for learner_sent, correct_sent in zip(learner, correct):
            correct_words = correct_sent.strip().split()
            learner_words = learner_sent.strip().split()
            
            matcher = SequenceMatcher(None, correct_words, learner_words)
            
            for tag, i1, i2, j1, j2 in matcher.get_opcodes():
                if tag == 'replace' and i2 - i1 == 1 and j2 - j1 == 1:
                    correct_word = correct_words[i1]
                    error_word = learner_words[j1]
                    
                    total_candidates += 1
                    
                    # Filter: must be orthographic error
                    if is_orthographic_error(correct_word, error_word):
                        correct_norm = normalize_word(correct_word)
                        word_errors[correct_norm][error_word] += 1
                    else:
                        total_filtered += 1
    
    print(f"Total candidate pairs: {total_candidates}")
    print(f"Filtered out (grammatical/caps): {total_filtered}")
    print(f"True orthographic errors: {total_candidates - total_filtered}")
    
    return word_errors

def load_grundwortschatz(json_file):
    """Load your Grundwortschatz vocabulary"""
    print(f"Loading Grundwortschatz from {json_file}...")
    with open(json_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    vocabulary = data.get('vocabulary', [])
    print(f"Loaded {len(vocabulary)} words")
    
    return vocabulary

def match_errors_to_grundwortschatz(grundwortschatz, falko_errors):
    """
    Match observed orthographic errors to Grundwortschatz words
    """
    enriched_vocab = []
    total_matches = 0
    words_with_errors = 0
    
    for entry in grundwortschatz:
        word = entry.get('word', '')
        word_norm = normalize_word(word)
        
        # Check if we have observed errors for this word
        if word_norm in falko_errors:
            errors = falko_errors[word_norm]
            
            # Add common errors to entry
            common_errors = [
                {
                    'error': error_form,
                    'count': count,
                    'source': 'Falko-MERLIN',
                    'type': 'orthographic'
                }
                for error_form, count in errors.most_common(10)
            ]
            
            entry['commonLearnerErrors'] = common_errors
            total_matches += sum(errors.values())
            words_with_errors += 1
        else:
            entry['commonLearnerErrors'] = []
        
        enriched_vocab.append(entry)
    
    print(f"\n=== Matching Statistics ===")
    print(f"Grundwortschatz words: {len(grundwortschatz)}")
    print(f"Words with observed orthographic errors: {words_with_errors}")
    print(f"Total error instances matched: {total_matches}")
    print(f"Coverage: {words_with_errors/len(grundwortschatz)*100:.1f}%")
    
    return enriched_vocab

def save_enriched_vocabulary(vocabulary, output_file):
    """Save enriched vocabulary"""
    output_data = {
        'metadata': {
            'description': 'Grundwortschatz enriched with real ORTHOGRAPHIC learner errors from Falko-MERLIN corpus',
            'note': 'Excludes grammatical (inflectional) and capitalization changes',
            'source': 'Falko-MERLIN GEC Corpus',
            'total_words': len(vocabulary),
            'words_with_errors': sum(1 for v in vocabulary if v.get('commonLearnerErrors'))
        },
        'vocabulary': vocabulary
    }
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(output_data, f, indent=2, ensure_ascii=False)
    
    print(f"\n✓ Saved to {output_file}")

def show_examples(vocabulary, num_examples=30):
    """Show example words with errors"""
    print(f"\n=== Example Words with Orthographic Errors ===")
    print("-" * 80)
    
    # Find words with errors
    words_with_errors = [v for v in vocabulary if v.get('commonLearnerErrors')]
    
    # Sort by total error count
    words_with_errors.sort(
        key=lambda v: sum(e['count'] for e in v['commonLearnerErrors']),
        reverse=True
    )
    
    for entry in words_with_errors[:num_examples]:
        word = entry['word']
        errors = entry['commonLearnerErrors']
        
        print(f"\n{word}")
        if entry.get('ipaPhoneme'):
            print(f"  IPA: {entry['ipaPhoneme']}")
        
        print(f"  Orthographic errors:")
        for err in errors[:5]:
            print(f"    - {err['error']} ({err['count']}×)")

def main():
    print("=" * 80)
    print("Mapping ORTHOGRAPHIC Errors from Falko-MERLIN to Grundwortschatz")
    print("(Excluding grammatical and capitalization changes)")
    print("=" * 80)
    
    # Step 1: Extract orthographic errors only
    print("\nStep 1: Extracting orthographic errors from Falko-MERLIN...")
    falko_errors = extract_orthographic_errors('fm-train.src', 'fm-train.trg')
    print(f"Found orthographic errors for {len(falko_errors)} unique words")
    
    # Step 2: Load Grundwortschatz
    print("\nStep 2: Loading Grundwortschatz...")
    grundwortschatz = load_grundwortschatz('grundwortschatz_variations.json')
    
    # Step 3: Match errors to vocabulary
    print("\nStep 3: Matching errors to Grundwortschatz words...")
    enriched_vocab = match_errors_to_grundwortschatz(grundwortschatz, falko_errors)
    
    # Step 4: Show examples
    show_examples(enriched_vocab, num_examples=40)
    
    # Step 5: Save
    print("\nStep 4: Saving enriched vocabulary...")
    save_enriched_vocabulary(enriched_vocab, 'grundwortschatz_with_real_errors.json')
    
    print("\n" + "=" * 80)
    print("✨ Done! Check grundwortschatz_with_real_errors.json")
    print("=" * 80)
    print("\nThese are REAL orthographic errors from actual learners!")
    print("No theoretical phoneme-grapheme combinations - just observed mistakes.")

if __name__ == "__main__":
    main()