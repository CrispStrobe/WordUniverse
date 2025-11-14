import json
import argparse
import os
import sys

# --- POS-Mapping (Kopie aus dem Hauptskript) ---
# Notwendig, um von API-Keys (z.B. 'noun') zurück auf unsere Dateitypen (z.B. 'substantiv') zu mappen

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

# Erstellt die umgekehrte Zuordnung: 'noun' -> 'substantiv'
POS_TO_WORDTYPE = {v: k for k, v in WORDTYPE_TO_POS.items()}
# Mehrdeutigkeiten auflösen (mehrere Typen mappen auf 'num')
POS_TO_WORDTYPE['num'] = 'numerale'
POS_TO_WORDTYPE['other'] = 'andere'


def korrigiere_wortarten(input_file: str, output_file: str):
    """
    Liest eine angereicherte JSON-Datei und korrigiert die Top-Level-Wortart
    basierend auf den Ergebnissen der API-Analyse.
    """
    print("="*70)
    print("✨ KORREKTURSKRIPT FÜR WORTARTEN ✨")
    print("="*70)

    # 1. Eingabedatei laden
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        print(f"✓ Eingabedatei geladen: {input_file}")
    except FileNotFoundError:
        print(f"✗ FEHLER: Eingabedatei nicht gefunden: {input_file}", file=sys.stderr)
        return
    except json.JSONDecodeError:
        print(f"✗ FEHLER: Datei ist kein gültiges JSON: {input_file}", file=sys.stderr)
        return
    except Exception as e:
        print(f"✗ FEHLER beim Laden der Datei: {e}", file=sys.stderr)
        return

    if 'vocabulary' not in data:
        print("✗ FEHLER: JSON-Struktur ungültig. 'vocabulary'-Schlüssel nicht gefunden.", file=sys.stderr)
        return

    vocabulary = data.get('vocabulary', [])
    total_words = len(vocabulary)
    corrections_made = 0
    errors_found = 0

    print(f"Prüfe {total_words} Wörter...")

    # 2. Schleife durch alle Wörter und prüfe auf Korrekturen
    for word_obj in vocabulary:
        original_word_type = word_obj.get('wordType')
        enrichment = word_obj.get('apiEnrichment', {})
        status = enrichment.get('enrichment_status')
        
        if status == 'error':
            errors_found += 1

        # Nur fortfahren, wenn die Anreicherung erfolgreich war
        if status == 'success':
            primary_pos = enrichment.get('primary_pos')
            
            if not primary_pos:
                continue

            # API-Key (z.B. 'adjective') zurückübersetzen (z.B. 'adjektiv')
            new_word_type = POS_TO_WORDTYPE.get(primary_pos)

            if new_word_type and new_word_type != 'andere':
                # Wenn der ursprüngliche Typ falsch war, korrigiere ihn
                if original_word_type != new_word_type:
                    word_obj['wordType'] = new_word_type
                    corrections_made += 1
                    print(f"  [KORRIGIERT] '{word_obj['word']}' (ID: {word_obj['id']}): '{original_word_type}' -> '{new_word_type}'")

    print("\n" + "="*70)
    print("--- ZUSAMMENFASSUNG ---")
    print(f"Wörter insgesamt:   {total_words}")
    print(f"Fehlgeschlagen (API): {errors_found}")
    print(f"Korrekturen (Wortart): {corrections_made}")

    if corrections_made == 0:
        print("\nKeine Korrekturen vorgenommen. Ausgabedatei wird nicht geschrieben.")
        print("✓ Vorgang abgeschlossen.")
        return

    # 3. Speichern der korrigierten Datei
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"\n✓ Korrigierte Datei erfolgreich gespeichert unter: {output_file}")
    except Exception as e:
        print(f"✗ FEHLER beim Speichern der Datei: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description="Korrigiert 'wordType'-Einträge in einer Grundwortschatz-JSON-Datei basierend auf apiEnrichment-Daten."
    )
    
    parser.add_argument(
        'input_file',
        help="Die zu lesende, angereicherte JSON-Datei (z.B. grundwortschatz_enriched_final.json)"
    )
    
    parser.add_argument(
        '--output',
        '-o',
        help="Die zu schreibende, korrigierte JSON-Datei. (Standard: <input>_fixed.json)"
    )
    
    args = parser.parse_args()

    output_file = args.output
    if not output_file:
        # Standard-Ausgabedateiname erstellen, z.B. "file.json" -> "file_fixed.json"
        base, ext = os.path.splitext(args.input_file)
        output_file = f"{base}_fixed{ext}"
        print(f"Keine Ausgabedatei angegeben. Verwende Standard: {output_file}")

    korrigiere_wortarten(args.input_file, output_file)

if __name__ == "__main__":
    main()