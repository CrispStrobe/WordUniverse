import json
import time
import argparse
from gradio_client import Client
from typing import Dict, Any, List, Optional
import traceback

# --- Configuration ---
INPUT_JSON = 'grundwortschatz_with_grapheme_variations.json'
OUTPUT_JSON = 'grundwortschatz_enriched_final.json'
CHECKPOINT_FILE = 'enrichment_checkpoint.json'
GRADIO_API_URL = "cstr/WiktionaryDE"
# GRADIO_API_URL = "http://127.0.0.1:7860/"

# Rate limiting
BATCH_SIZE = 100
DELAY_BETWEEN_CALLS = 1.0  # seconds
CHECKPOINT_INTERVAL = 50  # Save progress every N words

# --- Global Verbose Flag ---
# This will be set by argparse
VERBOSE = False

# --- Helper for progress ---
try:
    from tqdm import tqdm
    print("Progress bar enabled (tqdm found).")
except ImportError:
    print("Note: Install 'tqdm' for progress bars.")
    def tqdm(iterable, **kwargs):
        return iterable

# --- POS Mapping ---
# Map from JSON wordType to API POS keys
WORDTYPE_TO_POS = {
    'substantiv': 'noun',
    'verb': 'verb',
    'adjektiv': 'adjective',
    'adverb': 'adverb',
    'artikel': 'det',
    'pronomen': 'pron',
    'praeposition': 'adp',
    'konjunktion': 'conj',
    'partikel': 'part',
    'numerale': 'num',
    'kardinalzahlwort': 'num',
    'ordinalzahlwort': 'num',
    'affix': 'affix',
    'mehrwortausdruck': 'phrase',
    'andere': 'other'
}

def log_verbose(message: str):
    """Prints a message only if the -v flag is used."""
    if VERBOSE:
        # We use tqdm.write to avoid breaking the progress bar
        tqdm.write(message)

def load_checkpoint(vocabulary: List[Dict[str, Any]], no_resume_errors: bool = False) -> Dict[str, Any]:
    """
    Load checkpoint data and sync it with any data already present in the
    loaded vocabulary list.
    
    If 'no_resume_errors' is True, it will also add words marked 'error'
    to the processed_words set, forcing them to be skipped.
    """
    processed_words = set()
    enriched_count = 0
    
    # 1. Load from checkpoint file if it exists
    try:
        with open(CHECKPOINT_FILE, 'r', encoding='utf-8') as f:
            checkpoint_data = json.load(f)
            # We trust the checkpoint file completely for words that
            # were fully processed ('success' or 'no_data')
            processed_words = set(checkpoint_data.get('processed_words', []))
            enriched_count = checkpoint_data.get('enriched_count', 0)
    except FileNotFoundError:
        pass # No checkpoint, will build from scratch
    
    # 2. Sync with loaded data (from the output file)
    # This finds words that were processed but not in the last checkpoint
    # AND handles the --no-resume-errors logic.
    words_from_data = set()
    for word_obj in vocabulary:
        if 'apiEnrichment' in word_obj:
            status = word_obj['apiEnrichment'].get('enrichment_status')
            word_id = word_obj.get('id')
            if not word_id:
                continue

            # 'success' or 'no_data' are always considered processed.
            if status in ('success', 'no_data'):
                words_from_data.add(word_id)
            
            # If the user flags --no-resume-errors, we ALSO
            # treat 'error' as "processed" to skip it.
            elif status == 'error' and no_resume_errors:
                words_from_data.add(word_id)

    combined_words = processed_words.union(words_from_data)
    
    # Recalculate enriched_count based on the data, as it's more reliable
    # (Note: this logic assumes 'enriched_count' means 'success' only)
    enriched_from_data = 0
    for word_obj in vocabulary:
         if 'apiEnrichment' in word_obj:
            if word_obj['apiEnrichment'].get('enrichment_status') == 'success':
                 enriched_from_data += 1
    
    enriched_count = enriched_from_data
        
    return {"processed_words": combined_words, "enriched_count": enriched_count}

def save_checkpoint(checkpoint_data: Dict[str, Any]):
    """Save checkpoint data."""
    # Convert set to list for JSON serialization
    checkpoint_data['processed_words'] = list(checkpoint_data['processed_words'])
    with open(CHECKPOINT_FILE, 'w', encoding='utf-8') as f:
        json.dump(checkpoint_data, f, ensure_ascii=False)

def build_enrichment_data(api_response: Dict[str, Any], primary_pos: str) -> Dict[str, Any]:
    """
    Build enrichment using a "prioritize and aggregate" strategy.
    
    - PRIORITIZES: Definitions and Inflections from Wiktionary first.
    - AGGREGATES: Synonyms and Antonyms from all available sources.
    - HANDLES: All 3 API response structures (Wiktionary, DWDSmor, HanTa).
    """
    enrichment = {}
    analysis = api_response.get('analysis', {})
    
    # --- 1. Get PRIMARY entry (first in primary_pos, or first available) ---
    primary_entry = None
    primary_pos_key = None
    
    if primary_pos in analysis and analysis[primary_pos]:
        primary_entry = analysis[primary_pos][0]
        primary_pos_key = primary_pos
    else:
        for pos_key, entries in analysis.items():
            if entries:
                primary_entry = entries[0]
                primary_pos_key = pos_key
                break
    
    if not primary_entry:
        enrichment['enrichment_status'] = 'no_data'
        return enrichment

    enrichment['primary_pos'] = primary_pos_key
    
    # --- 2. Find the correct semantics block (handles all 3 response types) ---
    semantics = primary_entry.get('semantics_combined', 
                                  primary_entry.get('semantics', {}))
    
    enrichment['primary_lemma'] = semantics.get('lemma')
    
    # --- 3. PRIORITIZE: Definitions (Wiktionary > OdeNet) ---
    definitions = [
        sense.get('definition')
        for sense in semantics.get('wiktionary_senses', [])
        if sense.get('definition')
    ]
    # Fallback to OdeNet if wiktionary_senses was empty or missing
    if not definitions:
        definitions = [
            sense.get('definition')
            for sense in semantics.get('odenet_senses', [])
            if sense.get('definition')
        ]
    enrichment['definitions'] = definitions

    # --- 4. PRIORITIZE: Inflections (Wiktionary > Pattern > HanTa) ---
    wikt_forms = primary_entry.get('inflections_wiktionary', {}).get('forms_list', [])
    if wikt_forms:
        enrichment['inflections'] = wikt_forms[:20]  # Priority 1: Wiktionary
    else:
        pattern_forms = primary_entry.get('inflections_pattern', {})
        if pattern_forms and not pattern_forms.get('error'):
            enrichment['inflections_pattern'] = pattern_forms  # Priority 2: Pattern (DWDSmor)
        else:
            hanta_inflections = primary_entry.get('inflections', {})
            if hanta_inflections.get('declension'):
                enrichment['inflections_hanta'] = hanta_inflections.get('declension') # Priority 3: HanTa

    # --- 5. PRIORITIZE: Pronunciation & Examples (Wiktionary only) ---
    pronunciation = primary_entry.get('wiktionary_metadata', {}).get('pronunciation', [])
    if pronunciation:
        enrichment['pronunciation'] = [
            p for p in pronunciation if p.get('ipa') or p.get('audio')
        ]
    
    examples = primary_entry.get('wiktionary_metadata', {}).get('examples', [])
    if examples:
        enrichment['examples'] = examples[:3]  # Limit to 3

    # --- 6. AGGREGATE: Synonyms & Antonyms (Wiktionary + OdeNet) ---
    odenet_senses = semantics.get('odenet_senses', [])
    
    # Use sets for automatic deduplication
    syn_set = set(semantics.get('wiktionary_synonyms', []))
    ant_set = set(semantics.get('wiktionary_antonyms', []))
    
    # Add all synonyms/antonyms from all OdeNet senses
    for s in odenet_senses:
        for syn in s.get('synonyms', []): syn_set.add(syn)
        for ant in s.get('antonyms', []): ant_set.add(ant)
            
    if syn_set:
        enrichment['synonyms'] = list(syn_set)[:10] # Limit after aggregation
    if ant_set:
        enrichment['antonyms'] = list(ant_set)[:5]

    # --- 7. Store Semantic Relations & ConceptNet ---
    if odenet_senses:
        enrichment['semantic_relations'] = [
            {
                'definition': s.get('definition'),
                'synonyms': s.get('synonyms', [])[:10],
                'antonyms': s.get('antonyms', [])[:5]
            }
            for s in odenet_senses[:3]
        ]
    
    conceptnet = semantics.get('conceptnet_relations', [])
    if conceptnet:
        enrichment['conceptnet'] = [
            {
                'relation': r.get('relation'),
                'target': r.get('other_node'),
                'weight': r.get('weight')
            }
            for r in conceptnet[:10]
        ]

    # --- 8. Flag alternative entries (Robustly) ---
    alternatives = []
    
    # Check for multiple entries in PRIMARY pos
    if primary_pos_key in analysis and len(analysis[primary_pos_key]) > 1:
        for entry in analysis[primary_pos_key][1:]:
            alt_sem = entry.get('semantics_combined', entry.get('semantics', {}))
            alt_lemma = alt_sem.get('lemma')
            alt_senses = alt_sem.get('wiktionary_senses', alt_sem.get('odenet_senses', []))
            alt_def = alt_senses[0].get('definition') if alt_senses else None
            if alt_lemma:
                alternatives.append({
                    'pos': primary_pos_key,
                    'lemma': alt_lemma,
                    'definition': alt_def
                })
    
    # Check for other POS
    for pos_key, entries in analysis.items():
        if pos_key != primary_pos_key and entries:
            alt_sem = entries[0].get('semantics_combined', entries[0].get('semantics', {}))
            alt_lemma = alt_sem.get('lemma')
            alt_senses = alt_sem.get('wiktionary_senses', alt_sem.get('odenet_senses', []))
            alt_def = alt_senses[0].get('definition') if alt_senses else None
            alternatives.append({
                'pos': pos_key,
                'lemma': alt_lemma,
                'definition': alt_def
            })
    
    if alternatives:
        enrichment['alternative_analyses'] = alternatives

    # --- 9. Final Status ---
    enrichment['enrichment_status'] = 'success'
    if api_response.get('info'):
        enrichment['api_info'] = api_response.get('info')

    # If we *still* have no useful data, mark as 'no_data'
    # This helps the calling function decide if a fallback worked.
    if not definitions and not enrichment.get('inflections') and not enrichment.get('inflections_pattern'):
         enrichment['enrichment_status'] = 'no_data'

    return enrichment

def enrich_vocabulary(input_file: str, output_file: str, no_resume_errors: bool = False):
    """
    Main enrichment function.
    Accepts 'no_resume_errors' flag to control retry behavior.
    """
    print("="*70)
    print("GRUNDWORTSCHATZ ENRICHMENT SCRIPT")
    print("="*70)
    
    # Load OUTPUT file to resume, or INPUT file to start
    print(f"\nAttempting to resume from '{output_file}'...")
    try:
        with open(output_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        print("✓ Successfully loaded previous output file.")
    except FileNotFoundError:
        print(f"No output file found. Loading clean input from '{input_file}'...")
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        print(f"✗ Error reading output file (corrupted?). Loading clean input from '{input_file}'...")
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    
    vocabulary = data.get('vocabulary', [])
    print(f"Loaded {len(vocabulary)} words.")
    
    # Load checkpoint and pass the new flag
    checkpoint = load_checkpoint(vocabulary, no_resume_errors)
    processed_words = checkpoint.get('processed_words', set())
    enriched_count = checkpoint.get('enriched_count', 0)
    
    if processed_words:
        resume_msg = f"Resuming from checkpoint: {len(processed_words)} words already processed."
        if no_resume_errors:
            resume_msg += " (Skipping all errors)."
        else:
            resume_msg += " (Will retry errors)."
        print(resume_msg)
    
    # Initialize Gradio client
    print(f"\nConnecting to Gradio API: {GRADIO_API_URL}")
    try:
        client = Client(GRADIO_API_URL)
        print("✓ Successfully connected to API.")
    except Exception as e:
        print(f"✗ FAILED to connect to API: {e}")
        return
    
    # Process words
    print(f"\nEnriching vocabulary (batch size: {BATCH_SIZE})...")
    
    failed_words = []
    
    # Handle KeyboardInterrupt (Ctrl+C)
    try:
        for idx, word_obj in enumerate(tqdm(vocabulary, desc="Enriching")):
            word = word_obj.get('word', '')
            word_id = word_obj.get('id', '')
            
            if not word_id:
                log_verbose(f"SKIPPING: Word '{word}' at index {idx} has no ID.")
                continue
            
            # Skip if already processed (based on new load_checkpoint logic)
            if word_id in processed_words:
                log_verbose(f"Skipping '{word}' (ID: {word_id}) - already processed.")
                continue
            
            # Get primary POS from JSON
            word_type = word_obj.get('wordType', 'andere')
            primary_pos = WORDTYPE_TO_POS.get(word_type, 'other')
            
            try:
                log_verbose(f"Enriching '{word}' (ID: {word_id}) as POS: '{primary_pos}'...")
                
                # --- TRY WIKTIONARY FIRST ---
                result = client.predict(
                    word=word,
                    top_n_value=5,
                    engine_choice="wiktionary",
                    api_name="/analyze_word"
                )
                
                enrichment = build_enrichment_data(result, primary_pos)
                
                # --- IF IT FAILS, TRY FALLBACK ---
                if enrichment.get('enrichment_status') == 'no_data':
                    log_verbose(f"i Wiktionary engine found no data for '{word}'. Trying 'hanta' fallback...")
                    
                    # --- BUG FIX: 'hybrid' -> 'hanta' ---
                    fallback_result = client.predict(
                        word=word,
                        top_n_value=5,
                        engine_choice="hanta", # Was 'hybrid'
                        api_name="/analyze_word"
                    )
                    enrichment = build_enrichment_data(fallback_result, primary_pos)

                word_obj['apiEnrichment'] = enrichment
                
                # --- NEW CHECKPOINT LOGIC (INSIDE TRY) ---
                # Only add to 'processed' if it's a final state
                if enrichment.get('enrichment_status') in ('success', 'no_data'):
                    if enrichment.get('enrichment_status') == 'success':
                        enriched_count += 1
                        log_verbose(f"✓ Success for '{word}'.")
                    else:
                        log_verbose(f"i No data found for '{word}' (even with fallback).")
                    
                    # Add to set of words to skip next time
                    processed_words.add(word_id)
                
                # Rate limiting
                time.sleep(DELAY_BETWEEN_CALLS)
                
            except Exception as e:
                log_verbose(f"\n✗ Error enriching '{word}': {e}")
                
                word_obj['apiEnrichment'] = {
                    'enrichment_status': 'error',
                    'error_message': str(e)
                }
                failed_words.append(word)
                
                # --- NEW CHECKPOINT LOGIC (INSIDE CATCH) ---
                # Only add to 'processed' if the user *doesn't* want to retry
                if no_resume_errors:
                    processed_words.add(word_id)
            
            # Save checkpoint periodically
            if (idx + 1) % CHECKPOINT_INTERVAL == 0:
                log_verbose(f"\nCheckpointing... {len(processed_words)} words processed.")
                checkpoint['processed_words'] = processed_words
                checkpoint['enriched_count'] = enriched_count
                save_checkpoint(checkpoint)
                
                # Also save intermediate output
                with open(output_file, 'w', encoding='utf-8') as f:
                    json.dump(data, f, indent=2, ensure_ascii=False)

    except KeyboardInterrupt:
        print("\n\n!! User interruption (Ctrl+C) detected. Saving progress...")

    # --- Final Save (also runs after Ctrl+C) ---
    print(f"\nSaving final enriched data to '{output_file}'...")
    
    # Save final checkpoint
    checkpoint['processed_words'] = processed_words
    checkpoint['enriched_count'] = enriched_count
    save_checkpoint(checkpoint)
    
    # Update metadata
    if 'metadata' not in data:
        data['metadata'] = {}
    
    # Re-calculate final stats for metadata
    final_enriched_count = 0
    final_failed_words = []
    for word_obj in data.get('vocabulary', []):
        status = word_obj.get('apiEnrichment', {}).get('enrichment_status')
        if status == 'success':
            final_enriched_count += 1
        elif status == 'error':
            final_failed_words.append(word_obj.get('word', ''))

    
    data['metadata']['enrichment'] = {
        'enriched_at': time.strftime('%Y-%m-%d %H:%M:%S'),
        'words_enriched': final_enriched_count,
        'total_words': len(vocabulary),
        'success_rate': f"{final_enriched_count/len(vocabulary)*100:.1f}%",
        'failed_words': final_failed_words[:20]  # Show first 20 failures
    }
    
    # Save with metadata
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    
    print("\n" + "="*70)
    print("✨ SCRIPT STOPPED/COMPLETE!")
    # Fix the 7E0 typo
    print("="*70)
    print(f"\n=== Statistics ===")
    print(f"Total words: {len(vocabulary)}")
    print(f"Successfully enriched: {final_enriched_count} ({final_enriched_count/len(vocabulary)*100:.1f}%)")
    print(f"Failed: {len(final_failed_words)}")
    
    if final_failed_words:
        print(f"\nFirst 10 failed words: {final_failed_words[:10]}")
    
    print(f"\n✓ Output saved to: {output_file}")


def main():
    global VERBOSE 
    
    parser = argparse.ArgumentParser(
        description="Enrich a Grundwortschatz JSON file using the WiktionaryDE Gradio API."
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help="Enable verbose logging for debugging API calls."
    )
    
    parser.add_argument(
        '--input',
        default=INPUT_JSON,
        help=f"Input JSON file (default: {INPUT_JSON})"
    )
    
    parser.add_argument(
        '--output',
        default=OUTPUT_JSON,
        help=f"Output JSON file (default: {OUTPUT_JSON})"
    )
    
    # --- NEW ARGUMENT ---
    parser.add_argument(
        '--no-resume-errors',
        action='store_true',
        help="Do not retry words that failed with an error in the previous run. (Default is to retry errors)"
    )
    
    args = parser.parse_args()
    
    if args.verbose:
        VERBOSE = True
        print(">>> Verbose logging enabled. <<<")
    
    # --- PASS THE NEW ARGUMENT ---
    enrich_vocabulary(args.input, args.output, args.no_resume_errors)

if __name__ == "__main__":
    main()
    