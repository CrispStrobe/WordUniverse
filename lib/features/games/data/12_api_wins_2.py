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

# Mapping für Genus/Artikel
GENDER_MAP = {
    'Masculine': {'genus': 'mask.', 'article': 'der'},
    'Feminine': {'genus': 'fem.', 'article': 'die'},
    'Neuter': {'genus': 'neut.', 'article': 'das'},
}

def find_wiktionary_plural(inflections: list) -> str | None:
    """Sucht in der Wiktionary-Infektionsliste nach dem Nominativ Plural."""
    if not inflections:
        return None
        
    for form in inflections:
        tags = form.get('tags')
        # Sicherstellen, dass 'tags' eine Liste oder ein String ist
        if isinstance(tags, str):
            if 'nominative' in tags and 'plural' in tags:
                form_text = form.get('form_text')
                if form_text:
                    parts = form_text.split()
                    return parts[-1]
        elif isinstance(tags, list):
             if 'nominative' in tags and 'plural' in tags:
                form_text = form.get('form_text')
                if form_text:
                    parts = form_text.split()
                    return parts[-1]
    return None

def update_gender_fields(word_obj: dict, api_gender: str, corrections: dict):
    """Hilfsfunktion zur Korrektur von Genus und Artikel."""
    if api_gender in GENDER_MAP:
        new_genus = GENDER_MAP[api_gender]['genus']
        new_article = GENDER_MAP[api_gender]['article']
        changed = False

        if word_obj.get('genus') != new_genus:
            word_obj['genus'] = new_genus
            corrections['genus'] += 1
            changed = True
            
        if word_obj.get('article') != new_article:
            word_obj['article'] = new_article
            corrections['article'] += 1
            changed = True
        
        return changed
    return False

def konsolidiere_eintraege(input_file: str, output_file: str):
    """
    (ROBUST V24)
    Liest und konsolidiert die Top-Level-Einträge basierend auf 'apiEnrichment'.
    - KORRIGIERT Wortart, Lemma, Genus, Plural, Audio
    - ENTFERNT logische Fehler (z.B. nurImPlural bei Verben)
    - PROMOTET V24-Daten (z.B. expressions, hypernyms) auf Top-Level
    - ENTFERNT fehlerhafte Beispiel-Korrektur
    """
    print("="*70)
    print("✨ KONSOLIDIERUNGS-SKRIPT v24 (Robust) ✨")
    print("="*70)

    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        print(f"✓ Eingabedatei geladen: {input_file}")
    except FileNotFoundError:
        print(f"✗ FEHLER: Eingabedatei nicht gefunden: {input_file}", file=sys.stderr)
        return
    except json.JSONDecodeError as e:
        print(f"✗ FEHLER: Datei ist kein gültiges JSON: {input_file}", file=sys.stderr)
        print(f"  Details: {e}")
        return
    except Exception as e:
        print(f"✗ FEHLER beim Laden der Datei: {e}", file=sys.stderr)
        return

    if 'vocabulary' not in data:
        print("✗ FEHLER: JSON-Struktur ungültig. 'vocabulary'-Schlüssel nicht gefunden.", file=sys.stderr)
        return

    vocabulary = data.get('vocabulary', [])
    total_words = len(vocabulary)
    
    # 'examples' entfernt, 'lemma' und 'v24_data' hinzugefügt
    corrections = {
        'wordType': 0, 'lemma': 0, 'audio': 0, 'cleanup': 0, 
        'genus': 0, 'article': 0, 'plural': 0, 'v24_data': 0
    }
    errors_found = 0
    total_changes = 0

    print(f"Prüfe und konsolidiere {total_words} Wörter...")

    for word_obj in vocabulary:
        word_str = word_obj.get('word', 'N/A')
        changes_made_to_word = False
        
        enrichment = word_obj.get('apiEnrichment', {})
        status = enrichment.get('enrichment_status')
        
        if status == 'error':
            errors_found += 1
            continue
        if status != 'success':
            continue

        # --- SCHRITT 1: Wortart (KORREKT) ---
        original_word_type = word_obj.get('wordType')
        api_pos = enrichment.get('primary_pos')
        new_word_type = POS_TO_WORDTYPE.get(api_pos)

        if new_word_type and new_word_type != 'andere':
            if original_word_type != new_word_type:
                word_obj['wordType'] = new_word_type
                corrections['wordType'] += 1
                changes_made_to_word = True
        else:
            new_word_type = original_word_type 

        # --- SCHRITT 2: Lemma (RE-AKTIVIERT) ---
        # Vertraut darauf, dass die Gradio-API jetzt korrekte Lemmata liefert.
        original_lemma = word_obj.get('lemma')
        api_lemma = enrichment.get('primary_lemma')
        if api_lemma and original_lemma != api_lemma:
            word_obj['lemma'] = api_lemma
            corrections['lemma'] += 1
            changes_made_to_word = True
            print(f"  [FIX-LEMMA]   '{word_str}': '{original_lemma}' -> '{api_lemma}'")

        # --- SCHRITT 3: Beispielsätze (ENTFERNT) ---
        # Dieser Schritt war fehlerhaft. Er hat List<Map> in ein List<String> Feld
        # kopiert, was zu einem Dart-Typenkonflikt führt.
        # Das Dart-Modell `GermanWord.fromJson` behandelt dies bereits korrekt.

        # --- SCHRITT 4: Audio-Pfad (KORREKT) ---
        api_pron = enrichment.get('pronunciation', [])
        if api_pron:
            # Priorisiert mp3_url, wie es das Dart-Modell tut
            mp3_url = next((p.get('mp3_url') for p in api_pron if p.get('mp3_url')), None)
            if mp3_url and word_obj.get('audioPath') != mp3_url:
                word_obj['audioPath'] = mp3_url
                corrections['audio'] += 1
                changes_made_to_word = True

        # --- SCHRITT 5: Logisches Aufräumen (KORREKT) ---
        cleaned_up = False
        if new_word_type == 'substantiv':
            inf_pattern = enrichment.get('inflections_pattern')
            if inf_pattern and inf_pattern.get('gender'):
                if update_gender_fields(word_obj, inf_pattern['gender'], corrections):
                    changes_made_to_word = True

            wikt_plural = find_wiktionary_plural(enrichment.get('inflections'))
            if wikt_plural and word_obj.get('plural') != wikt_plural:
                word_obj['plural'] = wikt_plural
                corrections['plural'] += 1
                changes_made_to_word = True

        else: # Wort ist KEIN Substantiv
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
            corrections['cleanup'] += 1
            changes_made_to_word = True

        # --- SCHRITT 6: V24-Daten auf Top-Level promoten (NEU & WICHTIG) ---
        # Dies spiegelt die Logik des Dart-Modells `GermanWord.fromJson` wider
        # und stellt sicher, dass das finale JSON vollständig konsolidiert ist.
        
        v24_data_promoted_count = 0

        # Felder, die direkt kopiert werden können (List<String> oder List<Map>)
        direct_copy_fields = [
            'hyphenation', 'expressions', 'proverbs', 'entryNotes',
            'hypernyms', 'hyponyms', 'holonyms', 'meronyms', 'coordinateTerms'
        ]
        
        # Sonderfall: 'inflections' -> 'wiktionaryInflections'
        if 'inflections' in enrichment and word_obj.get('wiktionaryInflections') != enrichment['inflections']:
            word_obj['wiktionaryInflections'] = enrichment['inflections']
            v24_data_promoted_count += 1
            changes_made_to_word = True
            
        # Sonderfall: 'wiktionary_translations' -> 'translations'
        if 'wiktionary_translations' in enrichment and word_obj.get('translations') != enrichment['wiktionary_translations']:
             word_obj['translations'] = enrichment['wiktionary_translations']
             v24_data_promoted_count += 1
             changes_made_to_word = True

        # Sonderfall: `wiktionary_derived_terms` (List<Map>) muss zu `derivedTerms` (List<String>) geparst werden
        derived_raw = enrichment.get('wiktionary_derived_terms', [])
        derived_clean = [t['derived_word'] for t in derived_raw if isinstance(t, dict) and 'derived_word' in t]
        if word_obj.get('derivedTerms') != derived_clean:
            word_obj['derivedTerms'] = derived_clean
            v24_data_promoted_count += 1
            changes_made_to_word = True

        # Sonderfall: `wiktionary_related_terms` (List<Map>) muss zu `relatedTerms` (List<String>) geparst werden
        related_raw = enrichment.get('wiktionary_related_terms', [])
        related_clean = [t['related_word'] for t in related_raw if isinstance(t, dict) and 'related_word' in t]
        if word_obj.get('relatedTerms') != related_clean:
            word_obj['relatedTerms'] = related_clean
            v24_data_promoted_count += 1
            changes_made_to_word = True

        # Restliche Felder direkt kopieren
        for field in direct_copy_fields:
            if field in enrichment and word_obj.get(field) != enrichment[field]:
                word_obj[field] = enrichment[field]
                v24_data_promoted_count += 1
                changes_made_to_word = True
        
        if v24_data_promoted_count > 0:
            corrections['v24_data'] += v24_data_promoted_count
        # --- ENDE SCHRITT 6 ---

        if changes_made_to_word:
            total_changes += 1

    print("\n" + "="*70)
    print("--- KONSOLIDIERUNGS-ZUSAMMENFASSUNG (v24 Robust) ---")
    print(f"Wörter insgesamt:         {total_words}")
    print(f"Fehlgeschlagen (API):     {errors_found}")
    print(f"Wörter mit Änderungen:    {total_changes}")
    print("---")
    print(f"Korrekturen (Wortart):    {corrections['wordType']}")
    print(f"Korrekturen (Lemma):      {corrections['lemma']}")
    print(f"Korrekturen (Genus):      {corrections['genus']}")
    print(f"Korrekturen (Artikel):    {corrections['article']}")
    print(f"Korrekturen (Plural):     {corrections['plural']}")
    print(f"Korrekturen (Audio):      {corrections['audio']}")
    print(f"Korrekturen (Cleanup):    {corrections['cleanup']}")
    print(f"Korrekturen (V24-Daten):  {corrections['v24_data']}")

    if total_changes == 0:
        print("\nKeine Änderungen vorgenommen. Ausgabedatei wird nicht geschrieben.")
        print("✓ Vorgang abgeschlossen.")
        return

    # 3. Speichern der korrigierten Datei
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"\n✓ Konsolidierte Datei erfolgreich gespeichert unter: {output_file}")
    except Exception as e:
        print(f"✗ FEHLER beim Speichern der Datei: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description="Konsolidiert Top-Level-Felder in einer Grundwortschatz-JSON-Datei basierend auf apiEnrichment-Daten."
    )
    parser.add_argument(
        'input_file',
        help="Die zu lesende, angereicherte JSON-Datei (z.B. grundwortschatz_enriched_final.json)"
    )
    parser.add_argument(
        '--output',
        '-o',
        help="Die zu schreibende, konsolidierte JSON-Datei. (Standard: <input>_consolidated.json)"
    )
    
    args = parser.parse_args()

    output_file = args.output
    if not output_file:
        base, ext = os.path.splitext(args.input_file)
        output_file = f"{base}_consolidated{ext}"
        print(f"Keine Ausgabedatei angegeben. Verwende Standard: {output_file}")

    konsolidiere_eintraege(args.input_file, output_file)

if __name__ == "__main__":
    main()