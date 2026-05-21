import pandas as pd
import numpy as np

# --- Helper functions from previous step ---

def process_L_file(filename):
    try:
        df_L = pd.read_csv(filename, delimiter=';', header=None, names=['Word', 'Forms', 'Page'])
        df_L['Page_Num'] = pd.to_numeric(df_L['Page'], errors='coerce')
        df_L_valid = df_L.dropna(subset=['Page_Num']).copy()
        df_L_valid['Word'] = df_L_valid['Word'].str.strip()
        df_L_valid['Forms'] = df_L_valid['Forms'].str.strip()
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
        df_S_valid['Article'] = df_S_valid['Article'].str.strip()
        valid_articles = ['der', 'die', 'das']
        df_S_valid['Article'] = df_S_valid['Article'].apply(lambda x: x if x in valid_articles else np.nan)
        return df_S_valid[['Article', 'Word']]
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Article', 'Word'])

# --- Level files (A/B) ---

def load_level_file(filename, level_label):
    try:
        df = pd.read_csv(filename, delimiter=',')
        df.rename(columns={'Lemma': 'Word', 'Artikel': 'Article'}, inplace=True)
        df['Source'] = level_label
        df['Article'] = df['Article'].str.strip()
        valid_articles = ['der', 'die', 'das']
        df['Article'] = df['Article'].apply(lambda x: x if x in valid_articles else np.nan)
        return df[['Source', 'Word', 'Article', 'Wortart', 'Genus', 'URL', 'nur_im_Plural']]
    except FileNotFoundError:
        print(f"Warning: File not found {filename}. Skipping.")
        return pd.DataFrame(columns=['Source', 'Word', 'Article', 'Wortart', 'Genus', 'URL', 'nur_im_Plural'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Source', 'Word', 'Article', 'Wortart', 'Genus', 'URL', 'nur_im_Plural'])

# --- Frequency list loaders ---

def load_buchmeier_freq(filename, max_words=10000):
    """
    Loads Buchmeier frequency file.
    Format: frequency [[word]] (space/tab separated)
    Takes top max_words entries.
    """
    try:
        data = []
        with open(filename, 'r', encoding='utf-8') as f:
            for rank, line in enumerate(f, start=1):
                if rank > max_words:
                    break
                parts = line.strip().split()
                if len(parts) >= 2:
                    frequency = parts[0]
                    word = parts[1].strip('[[]]')  # Remove [[ and ]]
                    data.append({'Rank': rank, 'Frequency': frequency, 'Word': word})
        
        df = pd.DataFrame(data)
        df['Source'] = 'BUCHMEIER'
        df['Word'] = df['Word'].str.strip()
        return df[['Source', 'Word', 'Rank', 'Frequency']]
    except FileNotFoundError:
        print(f"Warning: File not found {filename}. Skipping.")
        return pd.DataFrame(columns=['Source', 'Word', 'Rank', 'Frequency'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Source', 'Word', 'Rank', 'Frequency'])

def load_leeds_freq(filename, max_words=10000):
    """
    Loads Leeds frequency file.
    Format: rank frequency word (space-separated)
    Takes top max_words entries.
    """
    try:
        df = pd.read_csv(filename, sep=r'\s+', header=None, names=['Rank', 'Frequency', 'Word'])
        df = df.head(max_words)
        df['Source'] = 'LEEDS'
        df['Word'] = df['Word'].str.strip()
        return df[['Source', 'Word', 'Rank', 'Frequency']]
    except FileNotFoundError:
        print(f"Warning: File not found {filename}. Skipping.")
        return pd.DataFrame(columns=['Source', 'Word', 'Rank', 'Frequency'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Source', 'Word', 'Rank', 'Frequency'])

def load_leipzig_freq(filename, max_words=10000):
    """
    Loads Leipzig frequency file.
    Format: one word per line (rank is line number)
    Takes top max_words entries.
    """
    try:
        words = []
        with open(filename, 'r', encoding='utf-8') as f:
            for rank, line in enumerate(f, start=1):
                if rank > max_words:
                    break
                word = line.strip()
                if word:
                    words.append({'Word': word, 'Rank': rank})
        df = pd.DataFrame(words)
        df['Source'] = 'LEIPZIG'
        return df[['Source', 'Word', 'Rank']]
    except FileNotFoundError:
        print(f"Warning: File not found {filename}. Skipping.")
        return pd.DataFrame(columns=['Source', 'Word', 'Rank'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Source', 'Word', 'Rank'])

def load_hermitdave_freq(filename, max_words=10000):
    """
    Loads Hermit Dave frequency file.
    Format: word frequency (space-separated)
    Takes top max_words entries.
    """
    try:
        df = pd.read_csv(filename, sep=r'\s+', header=None, names=['Word', 'Frequency'])
        df = df.head(max_words)
        df['Rank'] = range(1, len(df) + 1)
        df['Source'] = 'HERMIT'
        df['Word'] = df['Word'].str.strip()
        return df[['Source', 'Word', 'Rank', 'Frequency']]
    except FileNotFoundError:
        print(f"Warning: File not found {filename}. Skipping.")
        return pd.DataFrame(columns=['Source', 'Word', 'Rank', 'Frequency'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Source', 'Word', 'Rank', 'Frequency'])

# --- Aggregation helper ---

def get_first_valid(series):
    """
    Finds the first non-null, non-empty-string value in a series.
    Used for merging columns during groupby.
    """
    valid_values = series.dropna().astype(str).str.strip().replace('', np.nan).dropna()
    if not valid_values.empty:
        return valid_values.iloc[0]
    return np.nan

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
    
    # Must be at least 2 characters
    if len(word) < 2:
        return False
    
    # Check if ALL characters are alphabetic (including German special chars)
    return word.isalpha()

def aggregate_word_group(group):
    """
    Aggregate a group of rows with the same word (case-insensitive).
    Priority for capitalization:
    1. Pedagogical sources (A1, A2, B1, BW1, BW3)
    2. BUCHMEIER
    3. LEEDS
    4. LEIPZIG
    5. HERMIT
    """
    result = {}
    
    pedagogical_sources = ['A1', 'A2', 'B1', 'BW1', 'BW3']
    
    # Source - join all unique
    result['Source'] = ','.join(sorted(group['Source'].dropna().astype(str).unique()))
    
    # SourceType
    result['SourceType'] = list(group['SourceType'].dropna().unique())
    
    # Word - use source priority
    word_chosen = None
    
    # Priority 1: Pedagogical sources
    for ped in pedagogical_sources:
        mask = group['Source'].astype(str) == ped
        if mask.any():
            word_chosen = group.loc[mask, 'Word'].iloc[0]
            break
    
    # Priority 2: BUCHMEIER
    if word_chosen is None:
        mask = group['Source'] == 'BUCHMEIER'
        if mask.any():
            word_chosen = group.loc[mask, 'Word'].iloc[0]
    
    # Priority 3: LEEDS
    if word_chosen is None:
        mask = group['Source'] == 'LEEDS'
        if mask.any():
            word_chosen = group.loc[mask, 'Word'].iloc[0]
    
    # Priority 4: LEIPZIG
    if word_chosen is None:
        mask = group['Source'] == 'LEIPZIG'
        if mask.any():
            word_chosen = group.loc[mask, 'Word'].iloc[0]
    
    # Priority 5: HERMIT or fall back
    if word_chosen is None:
        word_chosen = group['Word'].iloc[0]
    
    result['Word'] = word_chosen
    
    # Other fields - use get_first_valid
    result['Article'] = get_first_valid(group['Article'])
    result['Forms'] = get_first_valid(group['Forms'])
    result['Wortart'] = get_first_valid(group['Wortart'])
    result['Genus'] = get_first_valid(group['Genus'])
    result['URL'] = get_first_valid(group['URL'])
    result['nur_im_Plural'] = get_first_valid(group['nur_im_Plural'])
    
    # Frequency data for each source
    for source_name in ['BUCHMEIER', 'LEEDS', 'LEIPZIG', 'HERMIT']:
        mask = group['Source'] == source_name
        if mask.any():
            # Get rank if available
            rank_val = group.loc[mask, 'Rank'].iloc[0] if 'Rank' in group.columns else np.nan
            result[f'{source_name}_rank'] = rank_val if pd.notna(rank_val) else np.nan
            
            # Get frequency if available
            freq_val = group.loc[mask, 'Frequency'].iloc[0] if 'Frequency' in group.columns else np.nan
            result[f'{source_name}_freq'] = freq_val if pd.notna(freq_val) else np.nan
        else:
            result[f'{source_name}_rank'] = np.nan
            result[f'{source_name}_freq'] = np.nan
    
    return pd.Series(result)

# --- Main Consolidation Script ---

print("Starting consolidation...")

# 1. Process Grundwortschatz (BW) files
print("\n=== Processing Grundwortschatz files ===")
df_1L = process_L_file('Grundwortschatz1L.csv')
df_1S = process_S_file('Grundwortschatz1S.csv')
df_3L = process_L_file('Grundwortschatz3L.csv')
df_3S = process_S_file('Grundwortschatz3S.csv')

df_1_merged = pd.merge(df_1L, df_1S, on='Word', how='left')
df_1_merged['Source'] = 'BW1'
df_3_merged = pd.merge(df_3L, df_3S, on='Word', how='left')
df_3_merged['Source'] = 'BW3'

df_bw = pd.concat([df_1_merged, df_3_merged], ignore_index=True)
df_bw['Wortart'] = df_bw.get('Wortart', pd.Series(dtype='object'))
df_bw.loc[df_bw['Article'].notna(), 'Wortart'] = 'Substantiv'

# Filter pedagogical words
before_filter = len(df_bw)
df_bw = df_bw[df_bw['Word'].apply(is_valid_pedagogical_word)].copy()
print(f"  BW total: {before_filter} words (before filter), {len(df_bw)} words (after filter)")

# 2. Process Level (A/B) files
print("\n=== Processing level files (A1, A2, B1) ===")
files_to_load = [
    ('A1.csv', 'A1'),
    ('A2.csv', 'A2'),
    ('B1.csv', 'B1')
]

level_dfs = []
for fname, label in files_to_load:
    df = load_level_file(fname, label)
    before = len(df)
    df = df[df['Word'].apply(is_valid_pedagogical_word)].copy()
    print(f"  {label}: {before} words (before filter), {len(df)} words (after filter)")
    level_dfs.append(df)

df_levels = pd.concat(level_dfs, ignore_index=True)

# 3. Process frequency lists
print("\n=== Processing frequency list files ===")
df_buchmeier = load_buchmeier_freq('Buchmeier20k.txt', max_words=10000)
df_leeds = load_leeds_freq('leeds_freq.num', max_words=10000)
df_leipzig = load_leipzig_freq('top10000de_unileipzig.txt', max_words=10000)
df_hermit = load_hermitdave_freq('de_50k_hermitdave.txt', max_words=10000)

print(f"  BUCHMEIER: {len(df_buchmeier)} words loaded")
print(f"  LEEDS: {len(df_leeds)} words loaded")
print(f"  LEIPZIG: {len(df_leipzig)} words loaded")
print(f"  HERMIT: {len(df_hermit)} words loaded")

# Mark source type for later filtering
df_bw['SourceType'] = 'pedagogical'
df_levels['SourceType'] = 'pedagogical'
df_buchmeier['SourceType'] = 'frequency'
df_leeds['SourceType'] = 'frequency'
df_leipzig['SourceType'] = 'frequency'
df_hermit['SourceType'] = 'frequency'

# 4. Concatenate all data
print("\n=== Consolidating all sources ===")
cols_all = ['Source', 'Word', 'Article', 'Forms', 'Wortart', 'Genus', 'URL', 'nur_im_Plural', 'SourceType']

# Add Rank and Frequency columns (will be NaN for pedagogical sources)
for df in [df_bw, df_levels]:
    df['Rank'] = np.nan
    df['Frequency'] = np.nan

# Ensure all frequency dfs have the necessary columns
for df in [df_buchmeier, df_leeds, df_leipzig, df_hermit]:
    if 'Article' not in df.columns:
        df['Article'] = np.nan
    if 'Forms' not in df.columns:
        df['Forms'] = np.nan
    if 'Wortart' not in df.columns:
        df['Wortart'] = np.nan
    if 'Genus' not in df.columns:
        df['Genus'] = np.nan
    if 'URL' not in df.columns:
        df['URL'] = np.nan
    if 'nur_im_Plural' not in df.columns:
        df['nur_im_Plural'] = np.nan
    if 'Rank' not in df.columns:
        df['Rank'] = np.nan
    if 'Frequency' not in df.columns:
        df['Frequency'] = np.nan

cols_all_with_freq = cols_all + ['Rank', 'Frequency']
df_all = pd.concat([df_bw, df_levels, df_buchmeier, df_leeds, df_leipzig, df_hermit], 
                   ignore_index=True, sort=False)[cols_all_with_freq]

# Clean Word column
df_all['Word'] = df_all['Word'].str.strip()
df_all = df_all.dropna(subset=['Word'])
df_all = df_all[df_all['Word'] != '']

# Create lowercase version for grouping to handle case sensitivity
df_all['Word_lower'] = df_all['Word'].str.lower()

print(f"  Total rows before deduplication: {len(df_all)}")

# 5. Group by lowercase word and aggregate WITH SOURCE PRIORITY
print("\n=== Grouping by normalized (lowercase) words ===")
df_final = df_all.groupby('Word_lower').apply(aggregate_word_group).reset_index(drop=True)

print(f"  Unique words after case-insensitive grouping: {len(df_final)}")

# 6. Apply filtering logic
print("\n=== Applying filtering logic ===")

# Count how many sources each word appears in
df_final['source_count'] = df_final['Source'].apply(lambda x: len(x.split(',')) if x else 0)

# Determine if word should be kept
def should_keep_word(row):
    source_types = row['SourceType']
    source_count = row['source_count']
    
    # If word appears in pedagogical sources, always keep it (already filtered for valid chars)
    if 'pedagogical' in source_types:
        return True
    
    # If word only appears in frequency lists, require at least 2 sources
    if 'frequency' in source_types and 'pedagogical' not in source_types:
        return source_count >= 2
    
    return False

df_final['keep'] = df_final.apply(should_keep_word, axis=1)

before_filter = len(df_final)
df_final = df_final[df_final['keep']].copy()
print(f"  Words before filter: {before_filter}")
print(f"  Words after filter: {len(df_final)}")
print(f"  Words removed: {before_filter - len(df_final)}")

# Clean up helper columns
df_final = df_final.drop(['source_count', 'SourceType', 'keep'], axis=1)

# 7. Filter ALL words to be pure alphabetic, at least 2 characters
print("\n=== Filtering all words: must be ≥2 chars and alphabetic only ===")

def is_valid_word_final(word):
    """
    Final validation: word must be at least 2 characters and contain ONLY letters
    """
    if pd.isna(word) or len(str(word).strip()) < 2:
        return False
    word = str(word).strip()
    return len(word) >= 2 and word.isalpha()

before_alpha_filter = len(df_final)
df_final = df_final[df_final['Word'].apply(is_valid_word_final)].copy()
print(f"  Words before alphabetic filter: {before_alpha_filter}")
print(f"  Words after alphabetic filter: {len(df_final)}")
print(f"  Words removed: {before_alpha_filter - len(df_final)}")

# 8. Apply final rules
print("\n=== Applying business rules ===")
valid_articles = ['der', 'die', 'das']
df_final.loc[df_final['Article'].isin(valid_articles), 'Wortart'] = 'Substantiv'

# 9. Clean up and Save
final_cols = ['Source', 'Word', 'Article', 'Forms', 'Wortart', 'Genus', 'URL', 'nur_im_Plural',
              'BUCHMEIER_rank', 'BUCHMEIER_freq', 'LEEDS_rank', 'LEEDS_freq', 
              'LEIPZIG_rank', 'HERMIT_rank', 'HERMIT_freq']
df_final = df_final[final_cols]
df_final = df_final.fillna('')

output_filename = 'voc_de.csv'
df_final.to_csv(output_filename, sep=';', index=False, encoding='utf-8')

print(f"\n{'='*60}")
print(f"Successfully created '{output_filename}'.")
print(f"Total words consolidated: {len(df_final)}")
print(f"\nFirst 20 rows of the output:")
print(df_final.head(20))
print(f"\nSample of source combinations:")
print(df_final['Source'].value_counts().head(20))