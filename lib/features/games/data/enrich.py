import pandas as pd
import spacy
import sys
import os

# --- Handle optional tqdm import ---
try:
    from tqdm import tqdm
    print("Note: 'tqdm' library found. Progress bar will be shown.")
except ImportError:
    print("Note: 'tqdm' library not found. Progress bar will not be shown.", file=sys.stderr)
    def tqdm(iterable, **kwargs):
        return iterable

# --- Mappings ---
SPACY_POS_MAP = {
    "NOUN": "Substantiv", "PROPN": "Substantiv", "VERB": "Verb", "ADJ": "Adjektiv",
    "ADV": "Adverb", "ADP": "Präposition", "AUX": "Verb", "CONJ": "Konjunktion",
    "CCONJ": "Konjunktion", "SCONJ": "Konjunktion", "DET": "Artikel",
    "PRON": "Pronomen", "PART": "Partikel", "PUNCT": "Satzzeichen",
    "NUM": "Numerale", "SYM": "Symbol", "X": "Andere",
}
# Map spaCy's gender strings to our terms
SPACY_GENDER_MAP = {"Masc": "mask.", "Fem": "fem.", "Neut": "neut."}
# Map definite articles to gender (highest priority source)
ARTICLE_TO_GENUS = {"der": "mask.", "die": "fem.", "das": "neut."}

# Define which spaCy POS tags are *allowed* to have a gender.
ALLOWED_GENDER_POS = {'NOUN', 'PROPN', 'PRON', 'DET', 'ADP'}

# Define user's custom Wortart types that should NOT have gender
CLEANUP_WORTART = {
    'Adjektiv', 'Adverb', 'Verb', 'Affix', 'Konjunktion', 'Präposition',
    'Partikel', 'Numerale', 'Satzzeichen', 'Interjektion',
    'Kardinalzahlwort', 'Ordinalzahlwort'
}

# --- New Helper Function ---
def get_morph_feature(token_morph, feature_name, mapping=None):
    """
    Gets a feature from spaCy's morph analysis, handles list results,
    applies an optional mapping, and returns a sorted, joined string.
    e.g., (morph, 'Gender', {'Masc': 'mask.'}) -> 'mask./neut.'
    """
    feature_list = token_morph.get(feature_name)
    if feature_list:
        if mapping:
            # Apply mapping, defaulting to the original value if not in map
            features = [mapping.get(f, f) for f in feature_list]
        else:
            features = feature_list
        # Return a sorted, unique, /-separated string
        return '/'.join(sorted(list(set(features))))
    return ''
# --- End Helper Function ---

def enrich_data(input_file='voc_de.csv', output_file='voc_de_enriched.csv'):
    """
    Loads the consolidated CSV and enriches it using spaCy, applying
    a priority-based logic to fill and *correct* data.
    """
    
    # --- 1. Load spaCy Model ---
    print("Loading spaCy model 'de_core_news_sm'...")
    try:
        nlp = spacy.load("de_core_news_sm", disable=['parser', 'ner'])
        print("spaCy model loaded successfully.")
    except IOError:
        print("Error: spaCy model 'de_core_news_sm' not found.", file=sys.stderr)
        print("Please run: python -m spacy download de_core_news_sm", file=sys.stderr)
        sys.exit(1)

    # --- 2. Load Input CSV ---
    try:
        df = pd.read_csv(input_file, delimiter=';')
        print(f"Successfully loaded '{input_file}'. Found {len(df)} entries.")
    except FileNotFoundError:
        print(f"Error: Input file '{input_file}' not found.", file=sys.stderr)
        print(f"Current directory: {os.getcwd()}", file=sys.stderr)
        sys.exit(1)
    
    # --- 3. Prepare DataFrame ---
    df = df.fillna('')
    
    # **NEW** Define all morphological columns we want to add
    morph_cols = ['Case_spacy', 'Number_spacy', 'Degree_spacy', 'PronType_spacy', 'VerbForm_spacy']
    
    # Define the base columns in order
    base_cols = [
        'Source', 'Word', 'Lemma_spacy', 'Article', 'Forms', 
        'Wortart', 'Genus', 'URL', 'nur_im_Plural'
    ]
    
    # Combine for the final, ordered list
    final_cols = base_cols + morph_cols

    # Add any missing columns from the *input* file for robustness
    for col in final_cols:
        if col not in df.columns:
            print(f"Warning: Column '{col}' not found. Adding it as empty.")
            df[col] = ''
            
    # --- 4. Process all words with nlp.pipe for speed ---
    print(f"Processing {len(df)} words with spaCy (this may take a moment)...")
    words = df['Word'].astype(str)
    docs = list(tqdm(nlp.pipe(words), total=len(df)))
    print("spaCy processing complete. Applying enrichment and correction rules...")

    enriched_rows = []

    # --- 5. Iterate, Enrich, and Correct ---
    for (index, row), doc in tqdm(zip(df.iterrows(), docs), total=len(df)):
        
        token = doc[0] if len(doc) > 0 else None
        
        # --- Step 1: Get base analysis from spaCy ("Linguistic Truth") ---
        spacy_pos_tag = ''
        spacy_wortart = ''
        spacy_lemma = ''
        # **NEW** Initialize all morph features
        spacy_genus = ''
        spacy_case = ''
        spacy_number = ''
        spacy_degree = ''
        spacy_prontype = ''
        spacy_verbform = ''

        if token:
            spacy_pos_tag = token.pos_
            spacy_wortart = SPACY_POS_MAP.get(spacy_pos_tag, spacy_pos_tag)
            spacy_lemma = token.lemma_
            
            # **NEW** Use the helper function for all morph features
            spacy_genus = get_morph_feature(token.morph, 'Gender', SPACY_GENDER_MAP)
            spacy_case = get_morph_feature(token.morph, 'Case')
            spacy_number = get_morph_feature(token.morph, 'Number')
            spacy_degree = get_morph_feature(token.morph, 'Degree')
            spacy_prontype = get_morph_feature(token.morph, 'PronType')
            spacy_verbform = get_morph_feature(token.morph, 'VerbForm')

        # --- Step 2: Get all data from the manual CSV row ("User Hint") ---
        final_word = row['Word']
        final_article = row['Article']
        final_wortart = row['Wortart']
        final_genus = row['Genus']
        final_lemma = spacy_lemma
        
        # **NEW** Set final morph vars. Since user has no source, we just use spaCy's
        final_case = spacy_case
        final_number = spacy_number
        final_degree = spacy_degree
        final_prontype = spacy_prontype
        final_verbform = spacy_verbform

        # --- Step 3: Clean the Article Column ---
        if final_article not in ARTICLE_TO_GENUS:
            final_article = '' # Force-clear the invalid entry

        # --- Step 4: Decide Final Wortart (Enrich & Correct) ---
        if final_article in ARTICLE_TO_GENUS:
            final_wortart = 'Substantiv'
        elif not final_wortart:
            final_wortart = spacy_wortart
        # else: keep the manual wortart (e.g. 'Mehrwortausdruck', 'Pronomen', etc.)
        
        # --- Step 5: Decide Final Genus (Enrich & Correct) ---
        if final_article in ARTICLE_TO_GENUS:
            final_genus = ARTICLE_TO_GENUS[final_article]
        elif final_wortart in ['Mehrwortausdruck', 'Affix']:
            final_genus = row['Genus'] # Keep the (potentially wrong) manual entry
        elif spacy_genus:
            final_genus = spacy_genus
        # else: fall back to the manual entry (already set in final_genus)

        # --- Step 6: Final Cleanup ---
        if final_wortart in CLEANUP_WORTART:
            final_genus = ''
        elif token and (spacy_pos_tag not in ALLOWED_GENDER_POS) and (final_wortart not in ['Mehrwortausdruck']):
             final_genus = ''

        # Handle lemma for multi-word expressions
        if final_wortart in ['Mehrwortausdruck', 'Affix']:
            final_lemma = final_word  # The word itself is the lemma

        # --- Append the final, corrected row ---
        enriched_rows.append({
            'Source': row['Source'],
            'Word': final_word,
            'Lemma_spacy': final_lemma,
            'Article': final_article,
            'Forms': row['Forms'],
            'Wortart': final_wortart,
            'Genus': final_genus,
            'URL': row['URL'],
            'nur_im_Plural': row['nur_im_Plural'],
            # **NEW** Add all the new morphological fields
            'Case_spacy': final_case,
            'Number_spacy': final_number,
            'Degree_spacy': final_degree,
            'PronType_spacy': final_prontype,
            'VerbForm_spacy': final_verbform
        })

    # --- 7. Create new DataFrame and Save ---
    df_enriched = pd.DataFrame(enriched_rows)
    # Re-order columns to the final desired format
    df_enriched = df_enriched[final_cols]
    
    df_enriched.to_csv(output_file, sep=';', index=False, encoding='utf-8')
    
    print(f"\nSuccessfully enriched and corrected data.")
    print(f"Saved {len(df_enriched)} entries to '{output_file}'.")
    print("\n--- First 10 Rows of Corrected Data: ---")
    print(df_enriched.head(10).to_string())
    print("\n--- Last 10 Rows of Corrected Data (showing Umlaute): ---")
    print(df_enriched.tail(10).to_string())

# --- Main execution ---
if __name__ == "__main__":
    enrich_data(input_file='voc_de.csv', output_file='voc_de_enriched.csv')