#!/usr/bin/env python3
"""
Simple Checker for Pedagogical Vocabulary Conflicts

This script loads all "pedagogical" source files (Grundwortschatz, A1/A2/B1, etc.)
and checks if any of their words are present in the `KNOWN_INAPPROPRIATE`
manual filter list.

This helps identify ambiguous words (like "Strich") that are in
educational lists but also in the filter.
"""

import pandas as pd
import numpy as np
import re
import os
import sys
from typing import Set, Dict

# --- 1. Manual Filter List from VocabularyFilter ---

KNOWN_INAPPROPRIATE_ALL = {
    'ficken', 'fick', 'gefickt', 'scheiße', 'scheisse', 'scheiss',
    'arsch', 'arschloch', 'schwanz', 'schwanzlutscher', 'fotze', 
    'wichser', 'wichsen', 'hurensohn', 'nutte', 'hure', 'puff',
    'verdammt', 'verfickt', 'beschissen', 'bumsen', 'vögeln',
    'blödmann', 'drecksack', 'scheißkerl', 'pisser', 'pissen',
    'pimmel', 'möse', 'titten', 'titte', 'arschgeige',
    'kacke', 'kacken', 'scheiß', 'wixer', 'drecksau',
    'mistkerl', 'fotzen', 'votze', 'vögelt', 
    'onanieren', 'masturbieren', 'orgasmus',
    'vergewaltigt', 'hinrichtung',
    'kokain', 'nazis', 'flittchen', 'droge',
    'verfickte', 'verflucht',
    'Arsch','Arschloch','Blödmann','Drecksack','Droge','Drogen','Fick','Flittchen','Hinrichtung','Hure','Hurensohn','Kacke','Kokain','Mistkerl','Nazis','Nutte','Scheiss','Scheisse','Scheiß','Scheiße','Scheißkerl','Schwanz','Schwanzlutscher','Titten','Verdammt','Wichser','abhauen','abschaum','affäre','alkohol','alkoholiker','ammenhai','anmachen','anschläge','antisemitismus','arschlöcher','asozial','ausgezogen','ausziehen','bastard','bastarde','behindert','behinderte','bescheuert','beschissen','beschissene','beschissenen','beschissener','besoffen','betrunken','bh','bier','biest','blasen','blut','blöd','blöde','blöden','blödes','blödsinn','bombardieren','brust','brutal','brüste','bud','bude','bulle','bullen','bullshit','bumsen','busen','bürgerkrieg','casino','colt','dealer','dekolleté','depp','diarrhö','dicke','disko','diskriminierung','doof','dreckige','dreckigen','dreckiger','dreckskerl','drohungen','dumm','dumme','dummkopf','durchgeknallt','durchsuchungsbefehl','einbrechen','einbruch','einfaltspinsel','entführung','ermorden','ermordet','ermordung','erpressung','erregen','erschieß','erschießen','erschlagen','erschossen','erstochen','feigling','ficken','folter','foltern','freier','fresse','fuck','gauner','gefickt','gehasst','geil','geisel','geißeln','geschrei','gewalt','gewehre','gin','griesgram','hasardeur','haß','heroin','hingerichtet','hitler','huren','höschen','idiot','idioten','ira','irrer','junkie','kannibale','killer','klugscheißer','knast','kneipe','koks','kommunisten','krüppel','körperverletzung','köter','leck','leiche','lesbisch','loser','lynchen','marihuana','massaker','mieser','mischpoke','miststück','mißbrauch','mord','morde','mordes','muschi','nackt','nackte','narr','nationalismus','nationalsozialismus','nigger','nutten','patrouille','penis','penner','pinkeln','pissen','pistole','pistolen','po','pogrom','poker','pornos','prostituierte','pussy','rasse','rassismus','rauchen','raucher','raucherin','rauchst','sack','sau','scheiden','scheißegal','scheißen','scheißer','schieß','schießerei','schiss','schlampe','schlampen','schnaps','schuss','schwachkopf','schwachsinn','schwuchtel','schwul','schwänze','selbstmord','sex','sexualität','sexuell','sexuelle','sexuellen','sexy','shit','skandal','sklave','sklaven','spinner','spinnt','sprengstoff','spritzen','stöhnen','suchtmittel','söldner','sünde','sünden','tabak','tequila','terror','terrorist','terroristen','todes','todesstrafe','trottel','tussi','tödlichen','töte','tötest','tötet','tötete','umbringen','umgebracht','umzubringen','unterhose','unterwäsche','vagina','verarschen','verarscht','verdammte','verdammten','verdammter','verdammtes','verfickte','verflucht','verfluchte','verfluchten','verführen','vergewaltigt','vergewaltigung','verknallt','verpiss','verprügeln','verprügelt','versauen','versaut','vollidiot','vögeln','waffe','waffen','weiber','weichei','wein','whiskey','whisky','wodka','wurscht','zigarette','zigaretten','zigarre','zuhälter','zuschlagen','ärsche'
} 
# This list has been "cleaned" by removing 42 words that were
# found in the pedagogical sources (A1, B1, spelling lists, etc.)
# to prevent false positives.
KNOWN_INAPPROPRIATE = {
            'ficken', 'fick', 'gefickt', 'scheiße', 'scheisse', 'scheiss',
            'arsch', 'arschloch', 'schwanz', 'schwanzlutscher', 'fotze', 
            'wichser', 'wichsen', 'hurensohn', 'nutte', 'hure', 'puff',
            'verdammt', 'verfickt', 'beschissen', 'bumsen', 'vögeln',
            'blödmann', 'drecksack', 'scheißkerl', 'pisser', 'pissen',
            'pimmel', 'möse', 'titten', 'titte', 'arschgeige',
            'kacke', 'kacken', 'scheiß', 'wixer', 'drecksau',
            'mistkerl', 'fotzen', 'votze', 'vögelt', 
            'onanieren', 'masturbieren', 'orgasmus',
            # Additional from AI filtering
            'vergewaltigt', 'hinrichtung',
            'kokain', 'nazis', 'flittchen',
            'verfickte', 'verflucht',
            'Arsch','Arschloch','Blödmann','Drecksack','Fick','Flittchen','Hinrichtung','Hure','Hurensohn','Kacke','Kokain','Mistkerl','Nazis','Nutte','Scheiss','Scheisse','Scheiß','Scheiße','Scheißkerl','Schwanz','Schwanzlutscher','Titten','Verdammt','Wichser','abhauen','abschaum','affäre','alkoholiker','anschläge','antisemitismus','arschlöcher','ausgezogen','bastard','bastarde','behindert','behinderte','bescheuert','beschissen','beschissene','beschissenen','beschissener','besoffen','bh','biest','blasen','blut','blöden','blödes','blödsinn','brutal','brüste','bud','bude','bulle','bullen','bullshit','busen','bürgerkrieg','casino','colt','dealer','depp','dicke','diskriminierung','dreckige','dreckigen','dreckiger','dreckskerl','drohungen','dummkopf','durchgeknallt','durchsuchungsbefehl','entführung','ermorden','ermordet','ermordung','erpressung','erregen','erschieß','erschießen','erschlagen','erschossen','erstochen','feigling','folter','foltern','freier','fresse','fuck','gauner','gefickt','gehasst','geil','gin','heroin','hingerichtet','hitler','huren','höschen','idiot','idioten','ira','irrer','junkie','killer','klugscheißer','knast','koks','kommunisten','krüppel','körperverletzung','köter','leck','leiche','lesbisch','marihuana','massaker','mieser','miststück','mißbrauch','mord','morde','mordes','muschi','nackt','nackte','narr','nationalismus','nationalsozialismus','nigger','nutten','patrouille','penis','penner','pinkeln','pistole','pistolen','po','poker','pornos','prostituierte','pussy','rasse','rassismus','rauchst','sau','scheißegal','scheißen','scheißer','schieß','schießerei','schiss','schlampe','schlampen','schnaps','schuss','schwachkopf','schwachsinn','schwuchtel','schwul','schwänze','selbstmord','sex','sexualität','sexuell','sexuelle','sexuellen','sexy','shit','skandal','sklave','sklaven','spinner','spinnt','sprengstoff','stöhnen','söldner','sünde','sünden','tabak','tequila','terror','terrorist','terroristen','todes','todesstrafe','trottel','tussi','tödlichen','töte','tötest','tötet','tötete','umbringen','umgebracht','umzubringen','unterhose','unterwäsche','vagina','verarschen','verarscht','verdammte','verdammten','verdammter','verdammtes','verfickte','verflucht','verfluchte','verfluchten','verführen','vergewaltigung','verknallt','verpiss','verprügeln','verprügelt','versauen','versaut','vollidiot','weiber','weichei','whiskey','whisky','wodka','zigarre','zuhälter','zuschlagen','ärsche'
        }

# --- 2. Loaders from Consolidation Script ---

def process_L_file(filename):
    try:
        df_L = pd.read_csv(filename, delimiter=';', header=None, names=['Word', 'Forms', 'Page'])
        df_L_valid = df_L.dropna(subset=['Word']).copy()
        df_L_valid['Word'] = df_L_valid['Word'].str.strip()
        return df_L_valid[['Word', 'Forms']]
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Word', 'Forms'])

def process_S_file(filename):
    try:
        df_S = pd.read_csv(filename, delimiter=';', header=None, names=['Article', 'Word', 'Notes'])
        df_S_valid = df_S.dropna(subset=['Word']).copy()
        df_S_valid = df_S_valid[df_S_valid['Notes'] != 'Meine Notizen']
        df_S_valid['Word'] = df_S_valid['Word'].str.strip()
        return df_S_valid[['Article', 'Word']]
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Article', 'Word'])

def load_level_file(filename, level_label):
    try:
        df = pd.read_csv(filename, delimiter=',')
        df.rename(columns={'Lemma': 'Word', 'Artikel': 'Article'}, inplace=True)
        return df[['Word', 'Article']]
    except FileNotFoundError:
        # Silently skip if not found, as we check later
        return pd.DataFrame(columns=['Word', 'Article'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Word', 'Article'])

def load_plain_txt_list(filename, source_label):
    try:
        words = []
        with open(filename, 'r', encoding='utf-8') as f:
            for line in f:
                cleaned_line = re.sub(r'\[.*?\]', '', line)
                cleaned_line = re.sub(r'\(.*?\)', '', cleaned_line)
                word = cleaned_line.strip()
                if word:
                    words.append({'Word': word})
        df = pd.DataFrame(words)
        return df[['Word']]
    except FileNotFoundError:
        return pd.DataFrame(columns=['Word'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Word'])

def load_fehler_csv(filename, source_label, col_name):
    try:
        try:
            df = pd.read_csv(filename, delimiter=',')
        except pd.errors.ParserError:
             df = pd.read_csv(filename, delimiter=';')
             
        if col_name not in df.columns:
             # Try semicolon if comma failed to find column
             df = pd.read_csv(filename, delimiter=';')
             if col_name not in df.columns:
                 print(f"Error: Column '{col_name}' not found in {filename} with ',' or ';' delimiter.")
                 return pd.DataFrame(columns=['Source', 'Word'])

        df = df[[col_name]].dropna()
        df = df.assign(Word=df[col_name].str.split('/')).explode('Word')
        df['Word'] = df['Word'].str.strip()
        return df[['Word']]
    except FileNotFoundError:
        return pd.DataFrame(columns=['Word'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Word'])

def load_leo_csv(filename, source_label):
    try:
        df = pd.read_csv(filename, delimiter=',', usecols=['Wort'])
        df = df.dropna(subset=['Wort'])
        df['Word_Raw'] = df['Wort'].str.strip()
        
        data = []
        valid_articles = ['der', 'die', 'das']
        
        for word_raw in df['Word_Raw']:
            parts = word_raw.split()
            word = word_raw
            
            if len(parts) > 1 and parts[0] in valid_articles:
                word = ' '.join(parts[1:])
            
            data.append({'Word': word})
        
        df_processed = pd.DataFrame(data)
        return df_processed[['Word']]
    except FileNotFoundError:
        return pd.DataFrame(columns=['Word'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Word'])

def is_valid_pedagogical_word(word):
    """
    Check if word is valid for pedagogical sources:
    - At least 2 characters
    - ONLY alphabetic characters (including German umlauts and ß)
    - NO numbers, NO special characters, NO hyphens, NO parentheses, NO spaces
    """
    if pd.isna(word) or len(str(word).strip()) < 2:
        return False
    
    word = str(word).strip()
    
    if len(word) < 2:
        return False
    
    return word.isalpha()

# --- 3. Main Checker Logic ---

def check_pedagogical_sources(filter_list: Set[str]):
    """
    Loads all pedagogical sources and checks them against the filter list.
    """
    print("Starting check of pedagogical sources against manual filter...")
    
    # Define all pedagogical sources as per the consolidation script
    sources_to_check = [
        # BW1
        {'func': process_L_file, 'args': ('Grundwortschatz1L.csv',), 'col': 'Word', 'label': 'BW1'},
        {'func': process_S_file, 'args': ('Grundwortschatz1S.csv',), 'col': 'Word', 'label': 'BW1'},
        # BW3
        {'func': process_L_file, 'args': ('Grundwortschatz3L.csv',), 'col': 'Word', 'label': 'BW3'},
        {'func': process_S_file, 'args': ('Grundwortschatz3S.csv',), 'col': 'Word', 'label': 'BW3'},
        # Levels
        {'func': load_level_file, 'args': ('A1.csv', 'A1'), 'col': 'Word', 'label': 'A1'},
        {'func': load_level_file, 'args': ('A2.csv', 'A2'), 'col': 'Word', 'label': 'A2'},
        {'func': load_level_file, 'args': ('B1.csv', 'B1'), 'col': 'Word', 'label': 'B1'},
        # New Pedagogical
        {'func': load_leo_csv, 'args': ('739Leo.csv', 'LEO739'), 'col': 'Word', 'label': 'LEO739'},
        {'func': load_plain_txt_list, 'args': ('400Fehler.txt', 'FEHLER400'), 'col': 'Word', 'label': 'FEHLER400'},
        {'func': load_fehler_csv, 'args': ('200Fehler.csv', 'FEHLER200', 'RICHTIG'), 'col': 'Word', 'label': 'FEHLER200'},
        {'func': load_fehler_csv, 'args': ('100Fehler.csv', 'FEHLER100', 'Übungswort'), 'col': 'Word', 'label': 'FEHLER100'},
        {'func': load_fehler_csv, 'args': ('300Fehler.csv', 'FEHLER300', 'Übungswort'), 'col': 'Word', 'label': 'FEHLER300'},
        {'func': load_plain_txt_list, 'args': ('422_NRW_Nachdenkwörter.txt', 'NRW422'), 'col': 'Word', 'label': 'NRW422'},
        {'func': load_plain_txt_list, 'args': ('111_NRW_Merkwörter.txt', 'NRW111'), 'col': 'Word', 'label': 'NRW111'},
    ]
    
    conflicts: Dict[str, Dict] = {} # { "word_lower": {"original": "Word", "sources": set()} }
    files_found_count = 0
    
    for source in sources_to_check:
        filepath = source['args'][0]
        if not os.path.exists(filepath):
            # We don't need to warn for every single file
            continue
        
        files_found_count += 1
        print(f"Checking {filepath} (Source: {source['label']})...")
        try:
            # Load the data
            df = source['func'](*source['args'])
            if df.empty:
                continue
                
            # Get the raw words
            words = df[source['col']].tolist()
            
            for word in words:
                # Apply the SAME pre-filter as the consolidation script
                if is_valid_pedagogical_word(word):
                    word_lower = str(word).lower()
                    
                    # Check for conflict
                    if word_lower in filter_list:
                        if word_lower not in conflicts:
                            conflicts[word_lower] = {"original": str(word), "sources": set()}
                        conflicts[word_lower]["sources"].add(source['label'])
                        
        except Exception as e:
            print(f"Error processing {filepath}: {e}")

    # --- 4. Report Results ---
    print("\n" + "="*60)
    print("Check Complete.")
    
    if files_found_count == 0:
        print("Error: No source files found. Make sure you run this script in the same directory as:")
        print("- Grundwortschatz1L.csv, A1.csv, 739Leo.csv, 400Fehler.txt, etc.")
        sys.exit(1)
    
    if not conflicts:
        print("🟢 SUCCESS: No conflicts found.")
        print("No words from the pedagogical lists were found in the manual filter.")
    else:
        print(f"🔴 CONFLICTS FOUND: {len(conflicts)} words from pedagogical lists are in the manual filter:")
        print("-" * 60)
        for word_lower, data in sorted(conflicts.items()):
            sources = ", ".join(sorted(data['sources']))
            print(f"  - {word_lower:20} (Original: \"{data['original']}\")")
            print(f"    Found in: {sources}")
        print("-" * 60)
        print("Review these words. They might be ambiguous (like 'Strich') or true negatives.")
    print("="*60)

if __name__ == "__main__":
    # Lowercase the filter list once for faster lookups
    filter_set_lower = {w.lower() for w in KNOWN_INAPPROPRIATE}
    check_pedagogical_sources(filter_set_lower)