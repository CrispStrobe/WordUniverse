import json
import shutil
import os

# ==============================================================================
# 🛠️ MANUAL FIX LIST (Derived from Audit of 233 Conflicts)
# ==============================================================================
# This list contains ONLY the words where the Current data was WRONG 
# and the API was RIGHT (or Standard German dictates a change).
# Words like "Bier", "Steuer", "Leiter" are excluded because 'Kept Current' was correct for them.

MANUAL_FIXES = {
    # Word: (New Genus, New Article)
    "Angesicht": ("neut.", "das"),
    "Billard": ("neut.", "das"),
    "Bowle": ("fem.", "die"),
    "Chrysantheme": ("fem.", "die"),
    "Clementine": ("fem.", "die"),
    "Code": ("mask.", "der"),
    "County": ("neut.", "das"),
    "Dekolleté": ("neut.", "das"),
    "Delta": ("neut.", "das"),
    "Diebstahl": ("mask.", "der"),
    "Ehrgeiz": ("mask.", "der"),
    "Eifersucht": ("fem.", "die"),
    "Einfaltspinsel": ("mask.", "der"),
    "Epikureer": ("mask.", "der"),
    "Falle": ("fem.", "die"),
    "Farm": ("fem.", "die"),
    "Fass": ("neut.", "das"),
    "Fee": ("fem.", "die"),
    "Finsternis": ("fem.", "die"),
    "Fitness": ("fem.", "die"),
    "Furnier": ("neut.", "das"),
    "Gasse": ("fem.", "die"),
    "Gegenmittel": ("neut.", "das"),
    "Genick": ("neut.", "das"),
    "Genie": ("neut.", "das"),
    "Geruch": ("mask.", "der"),
    "Gewehr": ("neut.", "das"),
    "Graupel": ("fem.", "die"), # 'der' exists, but 'die' is standard
    "Hüfte": ("fem.", "die"),
    "Hündchen": ("neut.", "das"),
    "Joghurt": ("mask.", "der"), # Standard German preferred
    "Jury": ("fem.", "die"),
    "Kehle": ("fem.", "die"),
    "Kinn": ("neut.", "das"),
    "Klient": ("mask.", "der"),
    "Knabe": ("mask.", "der"),
    "Kram": ("mask.", "der"),
    "Köder": ("mask.", "der"),
    "Maul": ("neut.", "das"),
    "Metropolis": ("fem.", "die"),
    "Monster": ("neut.", "das"),
    "Mädel": ("neut.", "das"),
    "Orbit": ("mask.", "der"),
    "Pack": ("neut.", "das"),
    "Papierkram": ("mask.", "der"),
    "Pfannkuchen": ("mask.", "der"),
    "Pfeife": ("fem.", "die"),
    "Pfingsten": ("neut.", "das"),
    "Piepsen": ("neut.", "das"),
    "Pinnwand": ("fem.", "die"),
    "Plastik": ("neut.", "das"), # Assuming material, not sculpture
    "Privatsphäre": ("fem.", "die"),
    "Pudding": ("mask.", "der"),
    "Quarantäne": ("fem.", "die"),
    "Ranch": ("fem.", "die"),
    "Reling": ("fem.", "die"),
    "Renommee": ("neut.", "das"),
    "Rentier": ("neut.", "das"),
    "Revolver": ("mask.", "der"),
    "Safe": ("mask.", "der"),
    "Schlamassel": ("mask.", "der"),
    "Schrei": ("mask.", "der"),
    "Schublade": ("fem.", "die"),
    "Schwammerl": ("neut.", "das"),
    "Schütze": ("mask.", "der"),
    "Seil": ("neut.", "das"),
    "Silber": ("neut.", "das"),
    "Silvester": ("mask.", "der"), # Standard German
    "Solo": ("neut.", "das"),
    "Sorte": ("fem.", "die"),
    "Spion": ("mask.", "der"),
    "Stamm": ("mask.", "der"),
    "Stirn": ("fem.", "die"),
    "Stracciatella": ("neut.", "das"),
    "Strophe": ("fem.", "die"),
    "Stückchen": ("neut.", "das"),
    "Summer": ("mask.", "der"), # Buzzer
    "Tank": ("mask.", "der"),
    "Telefonnummer": ("fem.", "die"),
    "Terabyte": ("neut.", "das"),
    "Tinte": ("fem.", "die"),
    "Treffer": ("mask.", "der"),
    "Tschüs": ("neut.", "das"), # das Tschüs (noun)
    "Tugend": ("fem.", "die"),
    "Turnier": ("neut.", "das"),
    "Ursprung": ("mask.", "der"),
    "Verlass": ("mask.", "der"),
    "Verwandte": ("mask.", "der"), # Generic singular
    "Volltreffer": ("mask.", "der"),
    "Wermut": ("mask.", "der"),
    "Wildnis": ("fem.", "die"),
    "Wohnwagen": ("mask.", "der"), # The specific example you noted
    "Wrack": ("neut.", "das"),
    "Zwerg": ("mask.", "der"),
    "Ärmel": ("mask.", "der"),
}

def apply_manual_fixes(input_file):
    print("="*80)
    print("✨ MANUAL CONFLICT RESOLVER ✨")
    print("="*80)

    # Create backup
    backup_file = input_file.replace('.json', '_backup.json')
    shutil.copy(input_file, backup_file)
    print(f"✓ Backup created: {backup_file}")

    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print(f"✗ Error loading file: {e}")
        return

    vocabulary = data.get('vocabulary', [])
    fixed_count = 0
    
    print(f"\nChecking {len(vocabulary)} words against {len(MANUAL_FIXES)} manual fixes...\n")

    for word_obj in vocabulary:
        word = word_obj.get('word')
        
        if word in MANUAL_FIXES:
            new_genus, new_article = MANUAL_FIXES[word]
            old_genus = word_obj.get('genus', 'N/A')
            old_article = word_obj.get('article', 'N/A')

            # Only apply if it's actually different
            if old_genus != new_genus or old_article != new_article:
                word_obj['genus'] = new_genus
                word_obj['article'] = new_article
                
                print(f"  🔧 Fixed [{word}]:")
                print(f"     Old: {old_article} {word} ({old_genus})")
                print(f"     New: {new_article} {word} ({new_genus})")
                fixed_count += 1

    print("-" * 80)
    print(f"SUMMARY: Fixed {fixed_count} incorrect entries.")
    print("-" * 80)

    if fixed_count > 0:
        with open(input_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"✓ Changes saved to: {input_file}")
    else:
        print("No changes needed.")

if __name__ == "__main__":
    # Hardcoded input filename based on your prompt
    target_file = "grundwortschatz_safe_enriched_v24_consolidated.json"
    
    if not os.path.exists(target_file):
        # Fallback to the previous version if consolidated doesn't exist yet
        target_file = "grundwortschatz_safe_enriched_v24.json"

    if os.path.exists(target_file):
        apply_manual_fixes(target_file)
    else:
        print(f"✗ File not found: {target_file}")