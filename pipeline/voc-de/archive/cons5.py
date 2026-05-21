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
    """
    Loads an A1, A2, or B1 file.
    These files are assumed to be comma-delimited.
    """
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

# --- NEW: Frequency list loaders ---

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
        return df[['Source', 'Word']]
    except FileNotFoundError:
        print(f"Warning: File not found {filename}. Skipping.")
        return pd.DataFrame(columns=['Source', 'Word'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Source', 'Word'])

def load_leipzig_freq(filename, max_words=10000):
    """
    Loads Leipzig frequency file.
    Format: one word per line
    Takes top max_words entries.
    """
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            words = [line.strip() for line in f if line.strip()]
        words = words[:max_words]
        df = pd.DataFrame({'Word': words, 'Source': 'LEIPZIG'})
        return df[['Source', 'Word']]
    except FileNotFoundError:
        print(f"Warning: File not found {filename}. Skipping.")
        return pd.DataFrame(columns=['Source', 'Word'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Source', 'Word'])

def load_hermitdave_freq(filename, max_words=10000):
    """
    Loads Hermit Dave frequency file.
    Format: word frequency (space-separated)
    Takes top max_words entries.
    """
    try:
        df = pd.read_csv(filename, sep=r'\s+', header=None, names=['Word', 'Frequency'])
        df = df.head(max_words)
        df['Source'] = 'HERMIT'
        df['Word'] = df['Word'].str.strip()
        return df[['Source', 'Word']]
    except FileNotFoundError:
        print(f"Warning: File not found {filename}. Skipping.")
        return pd.DataFrame(columns=['Source', 'Word'])
    except Exception as e:
        print(f"Error processing {filename}: {e}")
        return pd.DataFrame(columns=['Source', 'Word'])

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

# --- Main Consolidation Script ---

print("Starting consolidation...")

# 1. Process Grundwortschatz (BW) files
print("Processing Grundwortschatz files...")
df_1L = process_L_file('Grundwortschatz1L.csv')
df_1S = process_S_file('Grundwortschatz1S.csv')
df_3L = process_L_file('Grundwortschatz3L.csv')
df_3S = process_S_file('Grundwortschatz3S.csv')

df_1_merged = pd.merge(df_1L, df_1S, on='Word', how='left')
df_1_merged['Source'] = 'BW1'
df_3_merged = pd.merge(df_3L, df_3S, on='Word', how='left')
df_3_merged['Source'] = 'BW3'

df_bw = pd.concat([df_1_merged, df_3_merged], ignore_index=True)
df_bw['Wortart'] = np.nan
df_bw.loc[df_bw['Article'].notna(), 'Wortart'] = 'Substantiv'

# 2. Process Level (A/B) files
print("Processing level files (A1, A2, B1)...")
files_to_load = [
    ('A1.csv', 'A1'),
    ('A2.csv', 'A2'),
    ('B1.csv', 'B1')
]

level_dfs = [load_level_file(f, lbl) for f, lbl in files_to_load]
df_levels = pd.concat(level_dfs, ignore_index=True)

# 3. Process frequency lists (NEW)
print("Processing frequency list files...")
df_leeds = load_leeds_freq('leeds_freq.num', max_words=10000)
df_leipzig = load_leipzig_freq('top10000de_unileipzig.txt', max_words=10000)
df_hermit = load_hermitdave_freq('de_50k_hermitdave.txt', max_words=10000)

df_freq = pd.concat([df_leeds, df_leipzig, df_hermit], ignore_index=True)

# 4. Concatenate all data
print("Consolidating all sources...")
cols_all = ['Source', 'Word', 'Article', 'Forms', 'Wortart', 'Genus', 'URL', 'nur_im_Plural']
df_all = pd.concat([df_bw, df_levels, df_freq], ignore_index=True, sort=False)[cols_all]

# Clean Word column
df_all['Word'] = df_all['Word'].str.strip()
df_all = df_all.dropna(subset=['Word'])
df_all = df_all[df_all['Word'] != '']

# 5. Group and aggregate
print("Grouping and aggregating data...")
agg_funcs = {
    'Source': lambda x: ','.join(sorted(x.dropna().astype(str).unique())),
    'Article': get_first_valid,
    'Forms': get_first_valid,
    'Wortart': get_first_valid,
    'Genus': get_first_valid,
    'URL': get_first_valid,
    'nur_im_Plural': get_first_valid
}

df_final = df_all.groupby('Word', as_index=False).agg(agg_funcs)

# 6. Apply final rules
print("Applying business rules...")
valid_articles = ['der', 'die', 'das']
df_final.loc[df_final['Article'].isin(valid_articles), 'Wortart'] = 'Substantiv'

# 7. Clean up and Save
final_cols = ['Source', 'Word', 'Article', 'Forms', 'Wortart', 'Genus', 'URL', 'nur_im_Plural']
df_final = df_final[final_cols]
df_final = df_final.fillna('')

output_filename = 'voc_de.csv'
df_final.to_csv(output_filename, sep=';', index=False, encoding='utf-8')

print(f"\nSuccessfully created '{output_filename}'.")
print(f"Total words consolidated: {len(df_final)}")
print(f"\nSource breakdown:")
source_counts = df_final['Source'].value_counts()
for source, count in source_counts.items():
    print(f"  {source}: {count} words")
print("\nFirst 10 rows of the output:")
print(df_final.head(10))
