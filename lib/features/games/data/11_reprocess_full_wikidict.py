import json
import time
import argparse
from gradio_client import Client
from typing import Dict, Any, List, Optional
import traceback

# ============================================================================
# SCRIPT CONFIG (V24.1 - Full Data Reprocessing with --no-limits)
# ============================================================================
# This script is designed for the "CONSOLIDATED APP V23+"
# (The one using the full normalized database)
#
# CRITICAL: This URL must point to your *RUNNING INSTANCE* of the
#           "CONSOLIDATED APP V23+".
#
# GRADIO_API_URL = "http://127.0.0.1:7860/"
GRADIO_API_URL = "cstr/WiktionaryDE" # online API

# --- File Configuration ---
# Point this to your *existing* enriched file
INPUT_JSON = 'grundwortschatz_safe.json'
# This will be the new, upgraded output file
OUTPUT_JSON = 'grundwortschatz_safe_enriched_v24.json'
CHECKPOINT_FILE = 'enrichment_checkpoint_v24.json'

# --- Performance Configuration ---
DELAY_BETWEEN_CALLS = 0.5
CHECKPOINT_INTERVAL = 50
TOP_N_SEMANTICS = 5 # Default limit (Set to 0 to get ALL semantic senses)

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

def load_checkpoint(
    vocabulary: List[Dict[str, Any]], 
    no_resume_errors: bool = False, 
    reprocess_hyphenation: bool = False,
    reprocess_full_data: bool = False
) -> Dict[str, Any]:
    """
    (Corrected V24.1)
    Load checkpoint data and sync it.
    This relies on build_enrichment_data to ALWAYS add the new keys.
    """
    processed_words = set()
    enriched_count = 0
    
    try:
        with open(CHECKPOINT_FILE, 'r', encoding='utf-8') as f:
            checkpoint_data = json.load(f)
            processed_words = set(checkpoint_data.get('processed_words', []))
            enriched_count = checkpoint_data.get('enriched_count', 0)
    except FileNotFoundError:
        pass # No checkpoint
    
    words_from_data = set()
    for word_obj in vocabulary:
        if 'apiEnrichment' in word_obj:
            api_data = word_obj['apiEnrichment']
            status = api_data.get('enrichment_status')
            word_id = word_obj.get('id')
            if not word_id:
                continue

            if status == 'no_data':
                words_from_data.add(word_id)
            
            elif status == 'error' and no_resume_errors:
                words_from_data.add(word_id)
                
            elif status == 'success':
                is_complete = True # Assume complete
                
                if reprocess_hyphenation and 'hyphenation' not in api_data:
                    # This key is now guaranteed to exist (even as [])
                    # so this check is for old v23 files
                    is_complete = False
                    log_verbose(f"Flagging '{word_id}' for missing hyphenation.")
                
                if reprocess_full_data:
                    # We check for keys that our new build_enrichment_data
                    # *guarantees* will exist, even if empty.
                    # If the 'hypernyms' key is missing entirely, 
                    # it MUST be an old V23 entry.
                    if 'hypernyms' not in api_data or 'expressions' not in api_data:
                        is_complete = False
                        log_verbose(f"Flagging '{word_obj.get('word')}' for missing full V24 data (key not found).")

                if is_complete:
                    words_from_data.add(word_id)
                # If is_complete is False, we force reprocessing.
            
    combined_words = processed_words.union(words_from_data)
    
    # Recalculate enriched_count from data
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

def build_enrichment_data(
    api_response: Dict[str, Any], 
    primary_pos: str,
    no_limits: bool = False # <-- NEW ARG
) -> Dict[str, Any]:
    """
    (Corrected V24.2 - with --no-limits logic)
    Build enrichment from the V23/V24 API response.
    """
    enrichment = {}
    analysis = api_response.get('analysis', {})
    
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
    
    # Get the two main data blocks from the API, defaulting to empty dicts
    semantics = primary_entry.get('semantics_combined', {})
    wikt_meta = primary_entry.get('wiktionary_metadata', {})
    
    enrichment['primary_lemma'] = semantics.get('lemma')
    
    # 3. Definitions
    wikt_senses = semantics.get('wiktionary_senses', [])
    odenet_senses_list = semantics.get('odenet_senses', []) # Get this once
    
    definitions = [
        sense.get('definition')
        for sense in wikt_senses
        if sense.get('definition')
    ]
    if not definitions:
        definitions = [
            sense.get('definition')
            for sense in odenet_senses_list
            if sense.get('definition')
        ]
    enrichment['definitions'] = definitions # No limit on definitions
    log_verbose(f"    Found {len(definitions)} definitions.")

    # 4. Inflections
    wikt_forms = primary_entry.get('inflections_wiktionary', {}).get('forms_list', [])
    if wikt_forms:
        # --- MODIFIED WITH --no-limits ---
        all_wikt_forms = wikt_forms
        if not no_limits and len(all_wikt_forms) > 20:
            log_verbose(f"    Found {len(all_wikt_forms)} inflections. Limiting to 20.")
            enrichment['inflections'] = all_wikt_forms[:20]
        else:
            log_verbose(f"    Found {len(all_wikt_forms)} inflections. Saving all.")
            enrichment['inflections'] = all_wikt_forms
        # --- END MODIFICATION ---
    else:
        pattern_forms = primary_entry.get('inflections_pattern', {})
        if pattern_forms and not pattern_forms.get('error'):
            enrichment['inflections_pattern'] = pattern_forms
            log_verbose(f"    Using pattern.de inflections.")
        else:
            hanta_inflections = primary_entry.get('inflections', {})
            if hanta_inflections.get('declension'):
                enrichment['inflections_hanta'] = hanta_inflections.get('declension')
    
    # 5. Wiktionary Metadata (Guaranteed Keys)
    pronunciation = wikt_meta.get('pronunciation', [])
    enrichment['pronunciation'] = [
        p for p in pronunciation if p.get('ipa') or p.get('audio')
    ]
    log_verbose(f"    Found {len(enrichment['pronunciation'])} pronunciation entries.")
    
    # --- MODIFIED WITH --no-limits ---
    all_examples = wikt_meta.get('examples', [])
    if not no_limits and len(all_examples) > 3:
        log_verbose(f"    Found {len(all_examples)} examples. Limiting to 3.")
        enrichment['examples'] = all_examples[:3]
    else:
        log_verbose(f"    Found {len(all_examples)} examples. Saving all.")
        enrichment['examples'] = all_examples
    # --- END MODIFICATION ---
    
    enrichment['hyphenation'] = wikt_meta.get('hyphenation', [])

    # --- V24 Keys (Guaranteed to exist) ---
    enrichment['expressions'] = wikt_meta.get('expressions', [])
    enrichment['proverbs'] = wikt_meta.get('proverbs', [])
    enrichment['entryNotes'] = wikt_meta.get('entry_notes', []) # Renamed to match Dart
    enrichment['hypernyms'] = wikt_meta.get('hypernyms', [])
    enrichment['hyponyms'] = wikt_meta.get('hyponyms', [])
    enrichment['holonyms'] = wikt_meta.get('holonyms', [])
    enrichment['meronyms'] = wikt_meta.get('meronyms', [])
    enrichment['coordinateTerms'] = wikt_meta.get('coordinate_terms', []) # Renamed to match Dart
    
    log_verbose(f"    Found V24 data: {len(enrichment['expressions'])} expressions, "
                f"{len(enrichment['hypernyms'])} hypernyms, "
                f"{len(enrichment['hyponyms'])} hyponyms.")
    # --- END V24 KEYS ---

    # 6. Aggregated Semantics (Guaranteed Keys)
    wikt_synonyms = semantics.get('wiktionary_synonyms', [])
    syn_set = set(
        item['synonym_word'] for item in wikt_synonyms if isinstance(item, dict) and 'synonym_word' in item
    )
    wikt_antonyms = semantics.get('wiktionary_antonyms', [])
    ant_set = set(
        item['antonym_word'] for item in wikt_antonyms if isinstance(item, dict) and 'antonym_word' in item
    )
    for s in odenet_senses_list:
        for syn in s.get('synonyms', []): syn_set.add(syn)
        for ant in s.get('antonyms', []): ant_set.add(ant)
        
    # --- MODIFIED WITH --no-limits ---
    all_synonyms = list(syn_set)
    all_antonyms = list(ant_set)
    
    if not no_limits and len(all_synonyms) > 10:
        log_verbose(f"    Found {len(all_synonyms)} synonyms. Limiting to 10.")
        enrichment['synonyms'] = all_synonyms[:10]
    else:
        log_verbose(f"    Found {len(all_synonyms)} synonyms. Saving all.")
        enrichment['synonyms'] = all_synonyms

    if not no_limits and len(all_antonyms) > 5:
        log_verbose(f"    Found {len(all_antonyms)} antonyms. Limiting to 5.")
        enrichment['antonyms'] = all_antonyms[:5]
    else:
        log_verbose(f"    Found {len(all_antonyms)} antonyms. Saving all.")
        enrichment['antonyms'] = all_antonyms
    # --- END MODIFICATION ---

    # 7. Other Semantic Fields (Guaranteed Keys)
    
    # --- MODIFIED WITH --no-limits ---
    all_odenet_senses = odenet_senses_list
    if not no_limits and len(all_odenet_senses) > 3:
        log_verbose(f"    Found {len(all_odenet_senses)} OdeNet senses. Limiting to 3 for 'semantic_relations'.")
        all_odenet_senses = odenet_senses_list[:3]
    else:
         log_verbose(f"    Found {len(all_odenet_senses)} OdeNet senses. Processing all for 'semantic_relations'.")
    # --- END MODIFICATION ---

    enrichment['semantic_relations'] = []
    for s in all_odenet_senses:
        syns = s.get('synonyms', [])
        ants = s.get('antonyms', [])
        enrichment['semantic_relations'].append({
            'definition': s.get('definition'), 
             # --- MODIFY THESE LINES ---
             'synonyms': syns if no_limits else syns[:10], 
             'antonyms': ants if no_limits else ants[:5]
             # --- END MODIFICATION ---
        })
    
    conceptnet = semantics.get('conceptnet_relations', [])
    
    # --- MODIFIED WITH --no-limits ---
    all_conceptnet_relations = conceptnet
    if not no_limits and len(all_conceptnet_relations) > 10:
        log_verbose(f"    Found {len(all_conceptnet_relations)} ConceptNet relations. Limiting to 10.")
        all_conceptnet_relations = conceptnet[:10]
    else:
        log_verbose(f"    Found {len(all_conceptnet_relations)} ConceptNet relations. Saving all.")
    # --- END MODIFICATION ---
    
    enrichment['conceptnet'] = [
        {'relation': r.get('relation'), 'target': r.get('other_node'), 'weight': r.get('weight')}
        for r in all_conceptnet_relations
    ]

    enrichment['wiktionary_translations'] = semantics.get('wiktionary_translations', [])
    enrichment['wiktionary_derived_terms'] = semantics.get('wiktionary_derived_terms', [])
    enrichment['wiktionary_related_terms'] = semantics.get('wiktionary_related_terms', [])
    log_verbose(f"    Found {len(enrichment['wiktionary_translations'])} translations.")
    
    # 8. Alternative Analyses (Guaranteed Key)
    alternatives = []
    if primary_pos_key in analysis and len(analysis[primary_pos_key]) > 1:
        for entry in analysis[primary_pos_key][1:]:
            alt_sem = entry.get('semantics_combined', entry.get('semantics', {}))
            alt_lemma = alt_sem.get('lemma')
            alt_senses = alt_sem.get('wiktionary_senses', alt_sem.get('odenet_senses', []))
            alt_def = alt_senses[0].get('definition') if alt_senses else None
            if alt_lemma:
                alternatives.append({'pos': primary_pos_key, 'lemma': alt_lemma, 'definition': alt_def})
    
    for pos_key, entries in analysis.items():
        if pos_key != primary_pos_key and entries:
            alt_sem = entries[0].get('semantics_combined', entries[0].get('semantics', {}))
            alt_lemma = alt_sem.get('lemma')
            alt_senses = alt_sem.get('wiktionary_senses', alt_sem.get('odenet_senses', []))
            alt_def = alt_senses[0].get('definition') if alt_senses else None
            alternatives.append({'pos': pos_key, 'lemma': alt_lemma, 'definition': alt_def})
    
    enrichment['alternative_analyses'] = alternatives # Will be [] if none found
    log_verbose(f"    Found {len(alternatives)} alternative analyses.")

    # 9. Final Status
    enrichment['enrichment_status'] = 'success'
    if api_response.get('info'):
        enrichment['api_info'] = api_response.get('info')
        log_verbose(f"    API Info: {api_response.get('info')}")
    
    # Re-check for "empty success"
    if not definitions and not enrichment.get('inflections') and not enrichment.get('inflections_pattern') and not enrichment.get('hyphenation'):
         log_verbose(f"    WARNING: No data found for '{api_response.get('input_word')}'. Marking as 'no_data'.")
         enrichment['enrichment_status'] = 'no_data'

    return enrichment

def enrich_vocabulary(
    input_file: str, 
    output_file: str, 
    api_url: str, 
    no_resume_errors: bool = False, 
    reprocess_hyphenation: bool = False,
    reprocess_full_data: bool = False,
    no_limits: bool = False # <-- NEW ARG
):
    """
    Main enrichment function (V24.1 UPDATE)
    """
    print("="*70)
    print("GRUNDWORTSCHATZ RE-ENRICHMENT SCRIPT (V24.1 with --no-limits)")
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
    
    # --- PASS NEW FLAG ---
    checkpoint = load_checkpoint(
        vocabulary, 
        no_resume_errors, 
        reprocess_hyphenation,
        reprocess_full_data  # <-- NEW
    )
    processed_words = checkpoint.get('processed_words', set())
    enriched_count = checkpoint.get('enriched_count', 0)
    
    if processed_words:
        resume_msg = f"Resuming from checkpoint: {len(processed_words)} words already processed."
        if reprocess_hyphenation:
            resume_msg += " (REPROCESSING missing hyphenation)."
        if reprocess_full_data:
            resume_msg += " (REPROCESSING missing full data)." # <-- NEW
        if no_resume_errors:
            resume_msg += " (Skipping all errors)."
        else:
            resume_msg += " (Will retry errors)."
        print(resume_msg)
    
    print(f"\nConnecting to Gradio API: {api_url}")
    try:
        client = Client(api_url)
        print("Loaded as API: " + getattr(client, 'src', 'local URL') + " ✔")
        print("✓ Successfully connected to API.")
    except Exception as e:
        print(f"✗ FAILED to connect to API: {e}")
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
                # This check is now controlled by the logic in load_checkpoint
                log_verbose(f"Skipping '{word}' (ID: {word_id}) - already processed and complete.")
                continue
            
            word_type = word_obj.get('wordType', 'andere')
            primary_pos = WORDTYPE_TO_POS.get(word_type, 'other')
            
            try:
                log_verbose(f"Enriching '{word}' (ID: {word_id}) as POS: '{primary_pos}'...")
                
                result = client.predict(
                    word=word,
                    # --- MODIFIED: Pass 0 if no_limits is True ---
                    top_n_value= 0 if no_limits else TOP_N_SEMANTICS,
                    # --- END MODIFICATION ---
                    engine_choice="wiktionary", # Use the full-power engine
                    api_name="/analyze_word"
                )
                
                # --- MODIFIED: Pass no_limits flag ---
                enrichment = build_enrichment_data(result, primary_pos, no_limits)
                word_obj['apiEnrichment'] = enrichment
                
                if enrichment.get('enrichment_status') in ('success', 'no_data'):
                    if enrichment.get('enrichment_status') == 'success':
                        enriched_count += 1
                        log_verbose(f"✓ Success for '{word}'.")
                    else:
                        log_verbose(f"i No data found for '{word}'.")
                    
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
        
    data['metadata']['enrichment_v24'] = { # Updated version
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
        description="Enrich a Grundwortschatz JSON file using the CONSOLIDATED V23/V24 Gradio API."
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
    
    parser.add_argument(
        '--api_url',
        default=GRADIO_API_URL,
        help=f"URL of the running V23/V24 Gradio App (default: {GRADIO_API_URL})"
    )
    
    parser.add_argument(
        '--no-resume-errors',
        action='store_true',
        help="Do not retry words that failed with an error in the previous run."
    )
    
    parser.add_argument(
        '--reprocess-hyphenation',
        action='store_true',
        help="Force reprocessing of successful entries that are missing hyphenation data."
    )
    
    parser.add_argument(
        '--reprocess-full-data',
        action='store_true',
        help="Force reprocessing of successful entries that are missing new V24 data (e.g., expressions, hypernyms)."
    )
    
    # --- NEW ARGUMENT ---
    parser.add_argument(
        '--no-limits',
        action='store_true',
        help="Disable all hardcoded limits (e.g., for examples, synonyms, etc.)."
    )
    # --- END NEW ARGUMENT ---
    
    args = parser.parse_args()
    
    if args.verbose:
        VERBOSE = True
        print(">>> Verbose logging enabled. <<<")
    
    enrich_vocabulary(
        args.input, 
        args.output, 
        args.api_url, 
        args.no_resume_errors,
        args.reprocess_hyphenation,
        args.reprocess_full_data,
        args.no_limits  # <-- PASS NEW ARG
    )

if __name__ == "__main__":
    main()