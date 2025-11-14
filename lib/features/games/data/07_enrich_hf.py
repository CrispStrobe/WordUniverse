import json
import time
import argparse
from gradio_client import Client
from typing import Dict, Any, List, Optional
import traceback

# ============================================================================
# SCRIPT CONFIG (V22)
# ============================================================================
# This script is designed for the "CONSOLIDATED APP V22"
#
# CRITICAL: This URL must point to your *RUNNING INSTANCE* of the
#           "CONSOLIDATED APP V22".
#           The default 'http://127.0.0.1:7860/' assumes you are
#           running the app locally.
# GRADIO_API_URL = "http://127.0.0.1:7860/"
GRADIO_API_URL = "cstr/WiktionaryDE" # Old V1 URL

# --- File Configuration ---
INPUT_JSON = 'grundwortschatz_merged.json'
OUTPUT_JSON = 'grundwortschatz_enriched_v22.json'
CHECKPOINT_FILE = 'enrichment_checkpoint_v22.json'

# --- Performance Configuration ---
DELAY_BETWEEN_CALLS = 0.5   # Can be faster for local app
CHECKPOINT_INTERVAL = 50    # Save progress every N words
TOP_N_SEMANTICS = 5         # Limit senses/relations from API

# --- Global Verbose Flag ---
VERBOSE = False

# --- Helper for progress ---
try:
    from tqdm import tqdm
    print("Progress bar enabled (tqdm found).")
except ImportError:
    print("Note: Install 'tqdm' for progress bars.")
    def tqdm(iterable, **kwargs):
        return iterable

# --- POS Mapping (Unchanged) ---
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
        tqdm.write(message)

def load_checkpoint(vocabulary: List[Dict[str, Any]], no_resume_errors: bool = False) -> Dict[str, Any]:
    """
    (Unchanged) Load checkpoint data and sync it with any data already 
    present in the loaded vocabulary list.
    """
    processed_words = set()
    enriched_count = 0
    
    # 1. Load from checkpoint file
    try:
        with open(CHECKPOINT_FILE, 'r', encoding='utf-8') as f:
            checkpoint_data = json.load(f)
            processed_words = set(checkpoint_data.get('processed_words', []))
            enriched_count = checkpoint_data.get('enriched_count', 0)
    except FileNotFoundError:
        pass # No checkpoint
    
    # 2. Sync with loaded data (from the output file)
    words_from_data = set()
    for word_obj in vocabulary:
        if 'apiEnrichment' in word_obj:
            status = word_obj['apiEnrichment'].get('enrichment_status')
            word_id = word_obj.get('id')
            if not word_id:
                continue

            if status in ('success', 'no_data'):
                words_from_data.add(word_id)
            
            elif status == 'error' and no_resume_errors:
                words_from_data.add(word_id)

    combined_words = processed_words.union(words_from_data)
    
    # Recalculate enriched_count from data (more reliable)
    enriched_from_data = 0
    for word_obj in vocabulary:
         if 'apiEnrichment' in word_obj:
            if word_obj['apiEnrichment'].get('enrichment_status') == 'success':
                 enriched_from_data += 1
    
    enriched_count = enriched_from_data
        
    return {"processed_words": combined_words, "enriched_count": enriched_count}

def save_checkpoint(checkpoint_data: Dict[str, Any]):
    """(Unchanged) Save checkpoint data."""
    checkpoint_data['processed_words'] = list(checkpoint_data['processed_words'])
    with open(CHECKPOINT_FILE, 'w', encoding='utf-8') as f:
        json.dump(checkpoint_data, f, ensure_ascii=False)

def build_enrichment_data(api_response: Dict[str, Any], primary_pos: str) -> Dict[str, Any]:
    """
    (Unchanged) Build enrichment from the V22 API response.
    
    This function is already robustly designed to handle the V22 output
    structure (Wiktionary, DWDSmor, or HanTa) by prioritizing keys like
    'semantics_combined', 'inflections_wiktionary', etc.
    """
    enrichment = {}
    analysis = api_response.get('analysis', {})
    
    # 1. Get PRIMARY entry
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
    
    # 2. Find the correct semantics block (handles V22)
    semantics = primary_entry.get('semantics_combined', 
                                  primary_entry.get('semantics', {}))
    
    enrichment['primary_lemma'] = semantics.get('lemma')
    
    # 3. PRIORITIZE: Definitions (Wiktionary > OdeNet)
    definitions = [
        sense.get('definition')
        for sense in semantics.get('wiktionary_senses', [])
        if sense.get('definition')
    ]
    if not definitions:
        definitions = [
            sense.get('definition')
            for sense in semantics.get('odenet_senses', [])
            if sense.get('definition')
        ]
    enrichment['definitions'] = definitions

    # 4. PRIORITIZE: Inflections (Wiktionary > Pattern > HanTa)
    wikt_forms = primary_entry.get('inflections_wiktionary', {}).get('forms_list', [])
    if wikt_forms:
        enrichment['inflections'] = wikt_forms[:20]  # Priority 1: Wiktionary
    else:
        pattern_forms = primary_entry.get('inflections_pattern', {})
        if pattern_forms and not pattern_forms.get('error'):
            enrichment['inflections_pattern'] = pattern_forms  # Priority 2: Pattern (from DWDSmor/HanTa)
        else:
            hanta_inflections = primary_entry.get('inflections', {}) # Legacy HanTa
            if hanta_inflections.get('declension'):
                enrichment['inflections_hanta'] = hanta_inflections.get('declension')

    # 5. PRIORITIZE: Pronunciation & Examples (Wiktionary only)
    pronunciation = primary_entry.get('wiktionary_metadata', {}).get('pronunciation', [])
    if pronunciation:
        enrichment['pronunciation'] = [
            p for p in pronunciation if p.get('ipa') or p.get('audio')
        ]
    
    examples = primary_entry.get('wiktionary_metadata', {}).get('examples', [])
    if examples:
        enrichment['examples'] = examples[:3]

    # 6. AGGREGATE: Synonyms & Antonyms (Wiktionary + OdeNet)
    odenet_senses = semantics.get('odenet_senses', [])
    
    syn_set = set(semantics.get('wiktionary_synonyms', []))
    ant_set = set(semantics.get('wiktionary_antonyms', []))
    
    for s in odenet_senses:
        for syn in s.get('synonyms', []): syn_set.add(syn)
        for ant in s.get('antonyms', []): ant_set.add(ant)
            
    if syn_set:
        enrichment['synonyms'] = list(syn_set)[:10]
    if ant_set:
        enrichment['antonyms'] = list(ant_set)[:5]

    # 7. Store Semantic Relations & ConceptNet
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

    # 8. Flag alternative entries
    alternatives = []
    
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

    # 9. Final Status
    enrichment['enrichment_status'] = 'success'
    if api_response.get('info'):
        enrichment['api_info'] = api_response.get('info')
        # The V22 app's info field tells us which engine was used
        log_verbose(f"i API Info for '{api_response.get('input_word')}': {api_response.get('info')}")


    if not definitions and not enrichment.get('inflections') and not enrichment.get('inflections_pattern'):
         enrichment['enrichment_status'] = 'no_data'

    return enrichment

def enrich_vocabulary(input_file: str, output_file: str, api_url: str, no_resume_errors: bool = False):
    """
    Main enrichment function (V22 UPDATE)
    
    - 'api_url' is now a parameter.
    - Removed client-side fallback logic.
    """
    print("="*70)
    print("GRUNDWORTSCHATZ ENRICHMENT SCRIPT (V22 APP)")
    print("="*70)
    
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
    print(f"\nConnecting to Gradio API: {api_url}")
    try:
        client = Client(api_url)
        print("✓ Successfully connected to API.")
    except Exception as e:
        print(f"✗ FAILED to connect to API: {e}")
        print("  Please ensure the 'CONSOLIDATED APP V22' is running at this address.")
        return
    
    print(f"\nEnriching vocabulary...")
    
    failed_words = []
    
    try:
        for idx, word_obj in enumerate(tqdm(vocabulary, desc="Enriching")):
            word = word_obj.get('word', '')
            word_id = word_obj.get('id', '')
            
            if not word_id:
                log_verbose(f"SKIPPING: Word '{word}' at index {idx} has no ID.")
                continue
            
            if word_id in processed_words:
                log_verbose(f"Skipping '{word}' (ID: {word_id}) - already processed.")
                continue
            
            word_type = word_obj.get('wordType', 'andere')
            primary_pos = WORDTYPE_TO_POS.get(word_type, 'other')
            
            try:
                log_verbose(f"Enriching '{word}' (ID: {word_id}) as POS: '{primary_pos}'...")
                
                # ==========================================================
                # === V22 CHANGE: REMOVED CLIENT-SIDE FALLBACK           ===
                # ==========================================================
                # We make ONE call using the default 'wiktionary' engine.
                # The V22 server will *automatically* fall back to
                # DWDSmor, HanTa, and IWNLP if it finds no results.
                
                result = client.predict(
                    word=word,
                    top_n_value=TOP_N_SEMANTICS,
                    engine_choice="wiktionary", # Start the server's full fallback chain
                    api_name="/analyze_word"
                )
                
                # The build function is already robust for V22 output
                enrichment = build_enrichment_data(result, primary_pos)

                word_obj['apiEnrichment'] = enrichment
                
                # ==========================================================
                
                if enrichment.get('enrichment_status') in ('success', 'no_data'):
                    if enrichment.get('enrichment_status') == 'success':
                        enriched_count += 1
                        log_verbose(f"✓ Success for '{word}'.")
                    else:
                        log_verbose(f"i No data found for '{word}' (even with server fallback).")
                    
                    processed_words.add(word_id)
                
                time.sleep(DELAY_BETWEEN_CALLS)
                
            except Exception as e:
                log_verbose(f"\n✗ Error enriching '{word}': {e}")
                
                word_obj['apiEnrichment'] = {
                    'enrichment_status': 'error',
                    'error_message': str(e),
                    'traceback': traceback.format_exc()
                }
                failed_words.append(word)
                
                if no_resume_errors:
                    processed_words.add(word_id)
            
            # Save checkpoint
            if (idx + 1) % CHECKPOINT_INTERVAL == 0:
                log_verbose(f"\nCheckpointing... {len(processed_words)} words processed.")
                checkpoint['processed_words'] = processed_words
                checkpoint['enriched_count'] = enriched_count
                save_checkpoint(checkpoint)
                
                with open(output_file, 'w', encoding='utf-8') as f:
                    json.dump(data, f, indent=2, ensure_ascii=False)

    except KeyboardInterrupt:
        print("\n\n!! User interruption (Ctrl+C) detected. Saving progress...")

    # --- Final Save ---
    print(f"\nSaving final enriched data to '{output_file}'...")
    
    checkpoint['processed_words'] = processed_words
    checkpoint['enriched_count'] = enriched_count
    save_checkpoint(checkpoint)
    
    # Re-calculate final stats for metadata
    final_enriched_count = 0
    final_failed_words = []
    for word_obj in data.get('vocabulary', []):
        status = word_obj.get('apiEnrichment', {}).get('enrichment_status')
        if status == 'success':
            final_enriched_count += 1
        elif status == 'error':
            final_failed_words.append(word_obj.get('word', ''))

    if 'metadata' not in data:
        data['metadata'] = {}
        
    data['metadata']['enrichment_v22'] = {
        'enriched_at': time.strftime('%Y-%m-%d %H:%M:%S'),
        'words_enriched': final_enriched_count,
        'total_words': len(vocabulary),
        'success_rate': f"{final_enriched_count/len(vocabulary)*100:.1f}%",
        'failed_words': final_failed_words[:20]
    }
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    
    print("\n" + "="*70)
    print("✨ SCRIPT STOPPED/COMPLETE!")
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
        description="Enrich a Grundwortschatz JSON file using the CONSOLIDATED V22 Gradio API."
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
    
    # --- NEW API URL ARGUMENT ---
    parser.add_argument(
        '--api_url',
        default=GRADIO_API_URL,
        help=f"URL of the running V22 Gradio App (default: {GRADIO_API_URL})"
    )
    
    parser.add_argument(
        '--no-resume-errors',
        action='store_true',
        help="Do not retry words that failed with an error in the previous run."
    )
    
    args = parser.parse_args()
    
    if args.verbose:
        VERBOSE = True
        print(">>> Verbose logging enabled. <<<")
    
    enrich_vocabulary(args.input, args.output, args.api_url, args.no_resume_errors)

if __name__ == "__main__":
    main()