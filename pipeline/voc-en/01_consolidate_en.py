"""Consolidate EN wordlists into a single voc_en.csv.

Mirror of pipeline/voc-de/01_consolidate_wordlists_csv.py but adapted for the
English sources. No grammatical gender / article column. Priority chain:

  UK Y1-6 statutory > Oxford 3000/5000 > EVP CEFR > Dolch 220 > Fry 1000
  > SUBTLEX-US > HermitDave en_50k > (commonly_misspelled, low priority)

Each word carries every source it appeared in as a comma-separated `Sources`
field, so step 03 can do the grade cascade and the app can do subset
filtering at display time.

Missing source files are skipped with a warning rather than aborting the run.

Output: voc_en.csv with columns:
  Word, Sources, SourceType, UK_year, CEFR, AoA, Dolch_band, Fry_band,
  SUBTLEX_rank, SUBTLEX_freq, HermitDave_rank, HermitDave_freq,
  IsCommonMisspelling
"""
import os
import re
import sys
from pathlib import Path

try:
    import pandas as pd
    import numpy as np
except ImportError:
    print("Missing pandas/numpy. Install with: pip install pandas numpy")
    sys.exit(1)

SRC = Path(__file__).parent / "sources"
OUT = Path(__file__).parent / "voc_en.csv"

# ---------------------------------------------------------------------------
# Validity filter — drop garbage early
# ---------------------------------------------------------------------------

_WORD_RE = re.compile(r"^[a-zA-Z][a-zA-Z'\-]*$")

def is_valid(word) -> bool:
    """Letters + optional apostrophe/hyphen, ≥2 chars total, not whitespace."""
    if not isinstance(word, str):
        return False
    w = word.strip()
    if len(w) < 2:
        return False
    return bool(_WORD_RE.match(w))

def norm(word: str) -> str:
    return word.strip().lower()

# ---------------------------------------------------------------------------
# Loaders — each returns a DataFrame with 'Source' + 'Word' + signal columns
# ---------------------------------------------------------------------------

def _warn_missing(path: Path) -> bool:
    if not path.exists():
        print(f"  [warn] {path.name} not found in sources/ — skipping")
        return True
    return False

def load_uk_y1_y6(path: Path) -> pd.DataFrame:
    """UK National Curriculum statutory spelling lists.
    Expected columns: word, year (year in 1..6)."""
    if _warn_missing(path):
        return pd.DataFrame(columns=["Source", "Word", "UK_year"])
    df = pd.read_csv(path)
    df.columns = [c.strip().lower() for c in df.columns]
    if "word" not in df.columns:
        print(f"  [warn] {path.name} missing 'word' column — skipping")
        return pd.DataFrame(columns=["Source", "Word", "UK_year"])
    df["Word"] = df["word"].astype(str).map(norm)
    df["UK_year"] = pd.to_numeric(df.get("year"), errors="coerce")
    df = df[df["Word"].apply(is_valid)].copy()
    df["Source"] = "UK_Y" + df["UK_year"].astype("Int64").astype(str)
    return df[["Source", "Word", "UK_year"]].reset_index(drop=True)

def load_oxford(path: Path, label: str) -> pd.DataFrame:
    """Oxford 3000 or 5000. Expected cols: word, cefr."""
    if _warn_missing(path):
        return pd.DataFrame(columns=["Source", "Word", "CEFR"])
    df = pd.read_csv(path)
    df.columns = [c.strip().lower() for c in df.columns]
    df["Word"] = df["word"].astype(str).map(norm)
    df["CEFR"] = df.get("cefr", pd.Series(dtype="object")).astype(str).str.upper().str.strip()
    df = df[df["Word"].apply(is_valid)].copy()
    df["Source"] = label
    return df[["Source", "Word", "CEFR"]].reset_index(drop=True)

def load_evp(path: Path) -> pd.DataFrame:
    """English Vocabulary Profile CEFR list. Expected: word, cefr."""
    if _warn_missing(path):
        return pd.DataFrame(columns=["Source", "Word", "CEFR"])
    df = pd.read_csv(path)
    df.columns = [c.strip().lower() for c in df.columns]
    df["Word"] = df["word"].astype(str).map(norm)
    df["CEFR"] = df.get("cefr", pd.Series(dtype="object")).astype(str).str.upper().str.strip()
    df = df[df["Word"].apply(is_valid)].copy()
    df["Source"] = "EVP"
    return df[["Source", "Word", "CEFR"]].reset_index(drop=True)

def load_dolch(path: Path) -> pd.DataFrame:
    """Dolch 220. Expected: word, dolch_band, grade_hint."""
    if _warn_missing(path):
        return pd.DataFrame(columns=["Source", "Word", "Dolch_band"])
    df = pd.read_csv(path)
    df.columns = [c.strip().lower() for c in df.columns]
    df["Word"] = df["word"].astype(str).map(norm)
    df["Dolch_band"] = df.get("dolch_band", pd.Series(dtype="object"))
    df = df[df["Word"].apply(is_valid)].copy()
    df["Source"] = "DOLCH"
    return df[["Source", "Word", "Dolch_band"]].reset_index(drop=True)

def load_fry(path: Path) -> pd.DataFrame:
    """Fry 1000 or freq-top-1000 stand-in.
    Two acceptable formats:
      a) CSV with cols 'word,band' (true Fry, band in 1..10)
      b) plain text, one word per line (the freq-top-1000 stand-in;
         we synthesize bands as floor(rank/100)+1)
    """
    if _warn_missing(path):
        return pd.DataFrame(columns=["Source", "Word", "Fry_band"])
    # Try CSV first
    try:
        df = pd.read_csv(path)
        df.columns = [c.strip().lower() for c in df.columns]
        if "word" in df.columns and "band" in df.columns:
            df["Word"] = df["word"].astype(str).map(norm)
            df["Fry_band"] = pd.to_numeric(df["band"], errors="coerce")
            df = df[df["Word"].apply(is_valid)].copy()
            df["Source"] = "FRY"
            return df[["Source", "Word", "Fry_band"]].reset_index(drop=True)
    except Exception:
        pass
    # Fall back to plain text
    lines = path.read_text(encoding="utf-8").splitlines()
    rows = []
    for rank, line in enumerate(lines, start=1):
        w = norm(line.strip())
        if is_valid(w):
            band = min((rank - 1) // 100 + 1, 10)
            rows.append({"Source": "FRY", "Word": w, "Fry_band": band})
    return pd.DataFrame(rows)

def load_subtlex(path: Path) -> pd.DataFrame:
    """SUBTLEX-US. Tolerant of column naming:
      word | Word
      freq_count | FREQcount | freq
      freq_per_million | SUBTLWF | freq_per_million
      aoa | AoA | aoa_mean
    """
    if _warn_missing(path):
        return pd.DataFrame(columns=["Source", "Word", "SUBTLEX_freq", "AoA"])
    # Try common separators
    df = None
    for sep in [",", "\t", ";"]:
        try:
            df = pd.read_csv(path, sep=sep)
            if len(df.columns) >= 2:
                break
        except Exception:
            df = None
    if df is None:
        print(f"  [warn] could not parse {path.name}")
        return pd.DataFrame(columns=["Source", "Word", "SUBTLEX_freq", "AoA"])
    df.columns = [c.strip().lower() for c in df.columns]
    word_col = next((c for c in df.columns if c in ("word", "lemma", "spelling")), None)
    if not word_col:
        print(f"  [warn] {path.name} has no word column")
        return pd.DataFrame(columns=["Source", "Word", "SUBTLEX_freq", "AoA"])
    freq_col = next((c for c in df.columns
                     if c in ("freq_per_million", "subtlwf", "fpmw", "freq")), None)
    aoa_col = next((c for c in df.columns
                    if c in ("aoa", "aoa_mean", "rating.mean")), None)
    df["Word"] = df[word_col].astype(str).map(norm)
    df["SUBTLEX_freq"] = pd.to_numeric(df.get(freq_col), errors="coerce")
    df["AoA"] = pd.to_numeric(df.get(aoa_col), errors="coerce")
    df = df[df["Word"].apply(is_valid)].copy()
    df = df.sort_values("SUBTLEX_freq", ascending=False).head(30000)
    df["Source"] = "SUBTLEX"
    df["SUBTLEX_rank"] = range(1, len(df) + 1)
    return df[["Source", "Word", "SUBTLEX_rank", "SUBTLEX_freq", "AoA"]].reset_index(drop=True)

def load_aoa_kuperman(path: Path) -> pd.DataFrame:
    """Standalone AoA table (when AoA isn't already in subtlex)."""
    if _warn_missing(path):
        return pd.DataFrame(columns=["Source", "Word", "AoA"])
    df = pd.read_csv(path)
    df.columns = [c.strip().lower() for c in df.columns]
    word_col = next((c for c in df.columns if c in ("word", "lemma")), None)
    aoa_col = next((c for c in df.columns
                    if c in ("aoa_mean", "rating.mean", "aoa")), None)
    if not word_col or not aoa_col:
        print(f"  [warn] {path.name} missing word/aoa columns")
        return pd.DataFrame(columns=["Source", "Word", "AoA"])
    df["Word"] = df[word_col].astype(str).map(norm)
    df["AoA"] = pd.to_numeric(df[aoa_col], errors="coerce")
    df = df[df["Word"].apply(is_valid)].copy()
    df["Source"] = "AOA_KUPERMAN"
    return df[["Source", "Word", "AoA"]].reset_index(drop=True)

def load_hermitdave(path: Path, top_n: int = 10000) -> pd.DataFrame:
    """HermitDave en_50k.txt — 'word count' per line, sorted by frequency."""
    if _warn_missing(path):
        return pd.DataFrame(columns=["Source", "Word", "HermitDave_rank",
                                     "HermitDave_freq"])
    rows = []
    with path.open(encoding="utf-8") as fh:
        for rank, line in enumerate(fh, start=1):
            if rank > top_n:
                break
            parts = line.split()
            if len(parts) < 2:
                continue
            w = norm(parts[0])
            try:
                freq = int(parts[1])
            except ValueError:
                continue
            if is_valid(w):
                rows.append({
                    "Source": "HERMIT",
                    "Word": w,
                    "HermitDave_rank": rank,
                    "HermitDave_freq": freq,
                })
    return pd.DataFrame(rows)

def load_misspellings(path: Path) -> pd.DataFrame:
    """Commonly misspelled — adds CORRECT words to vocab pool (errors are
    stored separately for the spelling game's distractor pool; that's the
    next step's job, not this one). Cols: correct, wrong."""
    if _warn_missing(path):
        return pd.DataFrame(columns=["Source", "Word"])
    df = pd.read_csv(path)
    df.columns = [c.strip().lower() for c in df.columns]
    if "correct" not in df.columns:
        print(f"  [warn] {path.name} missing 'correct' column")
        return pd.DataFrame(columns=["Source", "Word"])
    df["Word"] = df["correct"].astype(str).map(norm)
    df = df[df["Word"].apply(is_valid)].copy()
    df["Source"] = "COMMON_MISSPELLED"
    return df[["Source", "Word"]].drop_duplicates(subset=["Word"]).reset_index(drop=True)

# ---------------------------------------------------------------------------
# Consolidation
# ---------------------------------------------------------------------------

def consolidate() -> pd.DataFrame:
    print("=== Loading EN sources ===")
    print("\n--- pedagogical (highest priority) ---")
    df_uk = load_uk_y1_y6(SRC / "uk_y1_y6_statutory.csv")
    df_ox3 = load_oxford(SRC / "oxford_3000.csv", "OXFORD3K")
    df_ox5 = load_oxford(SRC / "oxford_5000.csv", "OXFORD5K")
    df_evp = load_evp(SRC / "evp_cefr.csv")
    df_dolch = load_dolch(SRC / "dolch_220.csv")
    df_fry = load_fry(SRC / "fry_1000.csv")
    if df_fry.empty:
        df_fry = load_fry(SRC / "fry_top1000_freq.txt")

    print("\n--- frequency ---")
    df_subtlex = load_subtlex(SRC / "subtlex_us.csv")
    df_aoa = load_aoa_kuperman(SRC / "aoa_kuperman.csv")
    df_hermit = load_hermitdave(SRC / "en_50k_hermitdave.txt", top_n=10000)

    print("\n--- common misspellings (low priority) ---")
    df_misspelled = load_misspellings(SRC / "commonly_misspelled.csv")

    # Tag each pool with whether it's a "pedagogical" or "frequency" source.
    # This is used later for diagnostics; the priority chain in step 03 uses
    # the explicit Source labels.
    pedagogical = [df_uk, df_ox3, df_ox5, df_evp, df_dolch, df_fry, df_misspelled]
    frequency = [df_subtlex, df_aoa, df_hermit]

    for df in pedagogical:
        df["SourceType"] = "pedagogical"
    for df in frequency:
        df["SourceType"] = "frequency"

    # Per-source loaded count summary
    print("\n--- loaded counts ---")
    for name, df in [
        ("UK_Y1_Y6", df_uk),
        ("OXFORD3K", df_ox3),
        ("OXFORD5K", df_ox5),
        ("EVP", df_evp),
        ("DOLCH", df_dolch),
        ("FRY", df_fry),
        ("SUBTLEX", df_subtlex),
        ("AOA_KUPERMAN", df_aoa),
        ("HERMIT", df_hermit),
        ("COMMON_MISSPELLED", df_misspelled),
    ]:
        print(f"  {name:20s} {len(df):>7d} rows")

    # ---- Stack everything ----
    print("\n=== Stacking + collating per-word ===")
    big = pd.concat(pedagogical + frequency, ignore_index=True, sort=False)
    # Add columns that may be missing across frames so concat-result has them all
    expected_cols = ["Source", "SourceType", "Word", "UK_year", "CEFR",
                     "Dolch_band", "Fry_band", "SUBTLEX_rank",
                     "SUBTLEX_freq", "AoA", "HermitDave_rank",
                     "HermitDave_freq"]
    for c in expected_cols:
        if c not in big.columns:
            big[c] = pd.NA

    # ---- Group by Word, fold all signals together ----
    def collate(group: pd.DataFrame) -> pd.Series:
        sources = sorted(set(group["Source"].dropna().astype(str)))
        sourcetypes = sorted(set(group["SourceType"].dropna().astype(str)))

        def first_non_null(col):
            vals = group[col].dropna()
            return vals.iloc[0] if len(vals) else pd.NA

        # Pick "best" (i.e. lowest=earliest=easiest) CEFR if multiple sources disagree
        cefr_vals = [c for c in group["CEFR"].dropna().astype(str)
                     if c in {"A1", "A2", "B1", "B2", "C1", "C2"}]
        cefr_best = min(cefr_vals) if cefr_vals else pd.NA

        return pd.Series({
            "Sources": ",".join(sources),
            "SourceType": ",".join(sourcetypes),
            "UK_year": first_non_null("UK_year"),
            "CEFR": cefr_best,
            "Dolch_band": first_non_null("Dolch_band"),
            "Fry_band": first_non_null("Fry_band"),
            "SUBTLEX_rank": first_non_null("SUBTLEX_rank"),
            "SUBTLEX_freq": first_non_null("SUBTLEX_freq"),
            "AoA": first_non_null("AoA"),
            "HermitDave_rank": first_non_null("HermitDave_rank"),
            "HermitDave_freq": first_non_null("HermitDave_freq"),
            "IsCommonMisspelling": int("COMMON_MISSPELLED" in sources),
        })

    grouped = big.groupby("Word", sort=True, as_index=True).apply(
        collate, include_groups=False)
    grouped = grouped.reset_index()

    print(f"  unique words: {len(grouped)}")

    # ---- Optional cap. Step 03's grade cascade may want a target size. ----
    # We don't truncate here; step 03 will respect the size via filtering on
    # source membership. Just sort by a stable signal for inspection.
    grouped = grouped.sort_values(
        by=["UK_year", "CEFR", "SUBTLEX_rank", "HermitDave_rank"],
        ascending=[True, True, True, True],
        na_position="last",
    ).reset_index(drop=True)

    return grouped


def main():
    print(f"Sources dir: {SRC}")
    print(f"Output:      {OUT}")
    df = consolidate()
    df.to_csv(OUT, index=False)
    print(f"\nWrote {len(df)} rows to {OUT.name}")
    # Quick per-source coverage report
    print("\n=== Coverage by source (% of unique words) ===")
    for col, label in [
        ("UK_year", "UK Y1-6"),
        ("CEFR", "CEFR (any of Oxford/EVP)"),
        ("Dolch_band", "Dolch"),
        ("Fry_band", "Fry"),
        ("SUBTLEX_rank", "SUBTLEX-US"),
        ("AoA", "AoA-Kuperman"),
        ("HermitDave_rank", "HermitDave"),
        ("IsCommonMisspelling", "commonly misspelled"),
    ]:
        n = df[col].notna().sum() if df[col].dtype != int else int((df[col] != 0).sum())
        pct = 100.0 * n / max(len(df), 1)
        print(f"  {label:30s} {n:>6d}  ({pct:5.1f} %)")


if __name__ == "__main__":
    main()
