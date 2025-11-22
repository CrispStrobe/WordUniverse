import json
import argparse
import os
import sys

# --- Mappings ---
WORDTYPE_TO_POS = {
    'substantiv': 'noun', 'verb': 'verb', 'adjektiv': 'adjective',
    'adverb': 'adverb', 'artikel': 'det', 'pronomen': 'pron',
    'praeposition': 'adp', 'konjunktion': 'conj', 'partikel': 'part',
    'numerale': 'num', 'kardinalzahlwort': 'num', 'ordinalzahlwort': 'num',
    'affix': 'affix', 'mehrwortausdruck': 'phrase', 'andere': 'other'
}
POS_TO_WORDTYPE = {v: k for k, v in WORDTYPE_TO_POS.items()}
POS_TO_WORDTYPE['num'] = 'numerale'
POS_TO_WORDTYPE['other'] = 'andere'

GENDER_MAP = {
    'der': {'genus': 'mask.', 'article': 'der'},
    'die': {'genus': 'fem.', 'article': 'die'},
    'das': {'genus': 'neut.', 'article': 'das'},
}

def parse_tags(tags_entry):
    if isinstance(tags_entry, list):
        return tags_entry
    if isinstance(tags_entry, str):
        return [t.strip() for t in tags_entry.split(',')]
    return []

def find_gender_and_plural_strict(target_word, inflections):
    found_article = None
    found_plural = None
    
    if not inflections:
        return None, None

    target_lower = target_word.strip().lower()

    for form in inflections:
        tags = parse_tags(form.get('tags'))
        form_text = form.get('form_text', '').strip()
        
        if not form_text:
            continue

        form_lower = form_text.lower()
        
        # --- 1. Singular Nominative (Gender/Article) ---
        if not found_article and 'nominative' in tags and 'singular' in tags:
            parts = form_lower.split()
            if len(parts) >= 2:
                article_candidate = parts[0]
                noun_candidate = parts[-1] 
                
                # STRICT MATCH CHECK
                if noun_candidate == target_lower:
                    if article_candidate in ['der', 'die', 'das']:
                        found_article = article_candidate

        # --- 2. Nominative Plural ---
        if not found_plural and 'nominative' in tags and 'plural' in tags:
            parts = form_text.split()
            found_plural = parts[-1]

        if found_article and found_plural:
            break

    return found_article, found_plural

def log_change(word, field, old_val, new_val, verbose):
    """ Only prints if verbose is True """
    if not verbose:
        return
    old_str = str(old_val)
    new_str = str(new_val)
    if len(old_str) > 40: old_str = old_str[:37] + "..."
    if len(new_str) > 40: new_str = new_str[:37] + "..."
    print(f"  📝 [{word}] {field}: {old_str} -> {new_str}")

def log_conflict(word, field, current_val, api_val):
    """ Always prints, regardless of verbose flag """
    print(f"  ⚠️  [{word}] CONFLICT {field}: Current='{current_val}' vs API='{api_val}' (Kept Current)")

def konsolidiere_eintraege(input_file: str, output_file: str, verbose: bool):
    print("="*80)
    print(f"✨ KONSOLIDIERUNGS-SKRIPT v31 (Mode: {'Verbose' if verbose else 'Quiet'}) ✨")
    print("="*80)

    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        print(f"✓ Eingabedatei geladen: {input_file}\n")
    except Exception as e:
        print(f"✗ FEHLER beim Laden der Datei: {e}", file=sys.stderr)
        return

    vocabulary = data.get('vocabulary', [])
    
    stats = {
        'wordType': 0, 'lemma': 0, 'audio': 0, 'cleanup': 0, 
        'genus': 0, 'article': 0, 'plural': 0, 'v24_data': 0, 'conflicts': 0
    }
    total_changes = 0

    for word_obj in vocabulary:
        word_str = word_obj.get('word', 'UNKNOWN')
        changes_made_to_word = False
        
        enrichment = word_obj.get('apiEnrichment', {})
        status = enrichment.get('enrichment_status')
        
        if status != 'success':
            continue

        # --- 1. Update Word Type ---
        original_word_type = word_obj.get('wordType')
        api_pos = enrichment.get('primary_pos')
        new_word_type = POS_TO_WORDTYPE.get(api_pos)

        if new_word_type and new_word_type != 'andere':
            if original_word_type != new_word_type:
                log_change(word_str, "WordType", original_word_type, new_word_type, verbose)
                word_obj['wordType'] = new_word_type
                stats['wordType'] += 1
                changes_made_to_word = True
        else:
            new_word_type = original_word_type 

        # --- 2. Update Lemma (Conservative) ---
        current_lemma = word_obj.get('lemma')
        if not current_lemma:
            api_lemma = enrichment.get('primary_lemma')
            if api_lemma:
                log_change(word_str, "Lemma (Was Missing)", current_lemma, api_lemma, verbose)
                word_obj['lemma'] = api_lemma
                stats['lemma'] += 1
                changes_made_to_word = True

        # --- 3. Update Audio (Never Logged) ---
        api_pron = enrichment.get('pronunciation', [])
        if api_pron:
            mp3_url = next((p.get('mp3_url') for p in api_pron if p.get('mp3_url')), None)
            if mp3_url and word_obj.get('audioPath') != mp3_url:
                # We do NOT call log_change here to keep output clean
                word_obj['audioPath'] = mp3_url
                stats['audio'] += 1
                changes_made_to_word = True

        # --- 4. Update Genus & Plural (SAFE) ---
        cleaned_up = False
        if new_word_type == 'substantiv':
            found_article, found_plural = find_gender_and_plural_strict(
                word_str, 
                enrichment.get('inflections', [])
            )
            
            # A) GENDER / ARTICLE
            if found_article:
                new_genus = GENDER_MAP[found_article]['genus']
                new_article_field = GENDER_MAP[found_article]['article']
                
                # Check Genus Conflict
                current_genus = word_obj.get('genus')
                if current_genus and current_genus != new_genus:
                    log_conflict(word_str, "Genus", current_genus, new_genus)
                    stats['conflicts'] += 1
                elif not current_genus:
                    log_change(word_str, "Genus", current_genus, new_genus, verbose)
                    word_obj['genus'] = new_genus
                    stats['genus'] += 1
                    changes_made_to_word = True

                # Check Article Conflict
                current_article = word_obj.get('article')
                if current_article and current_article != new_article_field:
                    log_conflict(word_str, "Article", current_article, new_article_field)
                    stats['conflicts'] += 1
                elif not current_article:
                    log_change(word_str, "Article", current_article, new_article_field, verbose)
                    word_obj['article'] = new_article_field
                    stats['article'] += 1
                    changes_made_to_word = True

            # B) PLURAL
            api_lemma_str = enrichment.get('primary_lemma', '')
            is_expansion_risk = (' ' in api_lemma_str) and (word_str not in api_lemma_str)

            if found_plural and not is_expansion_risk:
                if word_obj.get('plural') != found_plural:
                    log_change(word_str, "Plural", word_obj.get('plural'), found_plural, verbose)
                    word_obj['plural'] = found_plural
                    stats['plural'] += 1
                    changes_made_to_word = True

        else: # Cleanup for non-nouns
            if word_obj.get('article') is not None:
                word_obj['article'] = None; cleaned_up = True
            if word_obj.get('genus') is not None:
                word_obj['genus'] = None; cleaned_up = True
            if word_obj.get('plural') is not None:
                word_obj['plural'] = None; cleaned_up = True
            if word_obj.get('nurImPlural') == True:
                word_obj['nurImPlural'] = False; cleaned_up = True
        
        if new_word_type != 'verb':
            if word_obj.get('verbFormSpacy') is not None:
                word_obj['verbFormSpacy'] = None; cleaned_up = True
        
        if cleaned_up:
            stats['cleanup'] += 1
            changes_made_to_word = True

        # --- 5. Data Promotion ---
        promoted_count = 0
        field_map = {
            'hyphenation': 'hyphenation',
            'expressions': 'expressions',
            'proverbs': 'proverbs',
            'entry_notes': 'entryNotes',          
            'hypernyms': 'hypernyms',
            'hyponyms': 'hyponyms',
            'holonyms': 'holonyms',
            'meronyms': 'meronyms',
            'coordinate_terms': 'coordinateTerms' 
        }
        
        if 'inflections' in enrichment and word_obj.get('wiktionaryInflections') != enrichment['inflections']:
            log_change(word_str, "New Field: wiktionaryInflections", "...", "Updated", verbose)
            word_obj['wiktionaryInflections'] = enrichment['inflections']
            promoted_count += 1
            changes_made_to_word = True
            
        if 'wiktionary_translations' in enrichment and word_obj.get('translations') != enrichment['wiktionary_translations']:
             log_change(word_str, "New Field: translations", "...", "Updated", verbose)
             word_obj['translations'] = enrichment['wiktionary_translations']
             promoted_count += 1
             changes_made_to_word = True

        derived_raw = enrichment.get('wiktionary_derived_terms', [])
        derived_clean = [t['derived_word'] for t in derived_raw if isinstance(t, dict) and 'derived_word' in t]
        if derived_clean and word_obj.get('derivedTerms') != derived_clean:
            log_change(word_str, "New Field: derivedTerms", "...", str(len(derived_clean)) + " items", verbose)
            word_obj['derivedTerms'] = derived_clean
            promoted_count += 1
            changes_made_to_word = True

        related_raw = enrichment.get('wiktionary_related_terms', [])
        related_clean = [t['related_word'] for t in related_raw if isinstance(t, dict) and 'related_word' in t]
        if related_clean and word_obj.get('relatedTerms') != related_clean:
            log_change(word_str, "New Field: relatedTerms", "...", str(len(related_clean)) + " items", verbose)
            word_obj['relatedTerms'] = related_clean
            promoted_count += 1
            changes_made_to_word = True

        for api_key, target_key in field_map.items():
            if api_key in enrichment:
                val = enrichment[api_key]
                if val and word_obj.get(target_key) != val:
                    log_change(word_str, f"New Field: {target_key}", "...", "Updated", verbose)
                    word_obj[target_key] = val
                    promoted_count += 1
                    changes_made_to_word = True
        
        if promoted_count > 0:
            stats['v24_data'] += promoted_count

        if changes_made_to_word:
            total_changes += 1

    print("\n" + "="*80)
    print("--- ZUSAMMENFASSUNG ---")
    print(f"Wörter bearbeitet:    {total_changes}")
    print(f"Genus Updates:        {stats['genus']}")
    print(f"Artikel Updates:      {stats['article']}")
    print(f"Plural Updates:       {stats['plural']}")
    print(f"Lemma Updates:        {stats['lemma']}")
    print(f"Audio Updates:        {stats['audio']} (Not logged)")
    print(f"Data Promoted:        {stats['v24_data']}")
    print(f"⚠️ Konflikte (Ignored): {stats['conflicts']}")

    if total_changes > 0:
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            print(f"\n✓ Datei gespeichert: {output_file}")
        except Exception as e:
            print(f"✗ FEHLER beim Speichern: {e}")
    else:
        print("Keine Änderungen.")

def main():
    parser = argparse.ArgumentParser(description="Enrich JSON with Wiktionary data.")
    parser.add_argument('input_file', help="Input JSON file")
    parser.add_argument('--output', '-o', help="Output JSON file")
    parser.add_argument('-v', '--verbose', action='store_true', help="Show detailed logs for every change (except audio)")
    
    args = parser.parse_args()

    output_file = args.output if args.output else args.input_file.replace('.json', '_consolidated.json')
    konsolidiere_eintraege(args.input_file, output_file, args.verbose)

if __name__ == "__main__":
    main()