"""Convert voc_en_enriched.csv → grundwortschatz_en.json.

Mirror of pipeline/voc-de/03_conv_csv_to_json.py. Key differences:

- Grade cascade is UK Y1-6 (primary) → CEFR → AoA-Kuperman → frequency fallback,
  matching the locked-in decision in pipeline/PLAN.md §2.
- No grammatical `genus`; `article` is nullable (filled only for nouns).
- `wordType` is already canonical English (set in step 02).
- All source signals are preserved as tags so the app can offer
  Core-3k / Extended-5k / Full-10k subsets without rebuilding.

Input:  voc_en_enriched.csv (from step 02)
Output: grundwortschatz_en.json
"""
import json
import sys
from pathlib import Path

try:
    import pandas as pd
except ImportError:
    print("Missing pandas. Install with: pip install pandas")
    sys.exit(1)

HERE = Path(__file__).parent
INPUT = HERE / "voc_en_enriched.csv"
OUTPUT = HERE / "grundwortschatz_en.json"

CEFR_TO_GRADE = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}


def aoa_to_grade(aoa: float) -> int:
    """Bucket Kuperman AoA → grade 1..6."""
    if aoa <= 6:
        return 1
    if aoa <= 8:
        return 2
    if aoa <= 10:
        return 3
    if aoa <= 13:
        return 4
    if aoa <= 16:
        return 5
    return 6


def freq_rank_to_grade(rank: float) -> int:
    """Last-resort grade from SUBTLEX rank."""
    if rank <= 500:
        return 3
    if rank <= 2000:
        return 4
    if rank <= 8000:
        return 5
    return 6


def assign_grade(row: pd.Series) -> tuple[int, str]:
    """Return (grade_1_6, reason_tag) for a single row."""
    # 1) UK Year 1-6 statutory list — primary
    uk = row.get("UK_year")
    if pd.notna(uk):
        try:
            y = int(uk)
            if 1 <= y <= 6:
                return y, "uk_y" + str(y)
        except (ValueError, TypeError):
            pass
    # 2) CEFR (Oxford / EVP)
    cefr = row.get("CEFR")
    if isinstance(cefr, str) and cefr in CEFR_TO_GRADE:
        return CEFR_TO_GRADE[cefr], "cefr_" + cefr.lower()
    # 3) Dolch sight-word band (G1-G3 mostly)
    dolch = row.get("Dolch_band")
    if isinstance(dolch, str) and dolch:
        if "grade_3" in dolch:
            return 3, "dolch_g3"
        if "grade_2" in dolch:
            return 2, "dolch_g2"
        if "grade_1" in dolch or "primer" in dolch or "pre_primer" in dolch:
            return 1, "dolch_g1"
    # 4) AoA-Kuperman bucket
    aoa = row.get("AoA")
    if pd.notna(aoa):
        try:
            return aoa_to_grade(float(aoa)), f"aoa_{float(aoa):.1f}"
        except (ValueError, TypeError):
            pass
    # 5) Fry band — 100 words per band, 1..10
    fry = row.get("Fry_band")
    if pd.notna(fry):
        try:
            band = int(float(fry))
            # Bands 1-3 → G1, 4-6 → G2, 7-9 → G3, 10 → G4
            if band <= 3:
                return 1, f"fry_b{band}"
            if band <= 6:
                return 2, f"fry_b{band}"
            if band <= 9:
                return 3, f"fry_b{band}"
            return 4, f"fry_b{band}"
        except (ValueError, TypeError):
            pass
    # 6) SUBTLEX rank fallback
    rank = row.get("SUBTLEX_rank")
    if pd.notna(rank):
        try:
            return freq_rank_to_grade(float(rank)), f"subtlex_rank_{int(rank)}"
        except (ValueError, TypeError):
            pass
    # 7) HermitDave rank fallback
    rank = row.get("HermitDave_rank")
    if pd.notna(rank):
        try:
            return freq_rank_to_grade(float(rank)), f"hermit_rank_{int(rank)}"
        except (ValueError, TypeError):
            pass
    return 5, "default"


def build_tags(row: pd.Series, grade_reason: str) -> list[str]:
    """Build the tags list — carried forward so the app can do subset filtering."""
    tags = [grade_reason]
    sources = row.get("Sources")
    if isinstance(sources, str) and sources:
        for s in sources.split(","):
            s = s.strip().lower()
            if s:
                tags.append("source:" + s)
    cefr = row.get("CEFR")
    if isinstance(cefr, str) and cefr in CEFR_TO_GRADE:
        tags.append("cefr:" + cefr.lower())
    uk = row.get("UK_year")
    if pd.notna(uk):
        try:
            tags.append(f"uk_year:{int(uk)}")
        except (ValueError, TypeError):
            pass
    if row.get("IsCommonMisspelling"):
        tags.append("often_misspelled")
    return sorted(set(tags))


def build_frequency_data(row: pd.Series) -> dict:
    """Mirror of DE 03's frequencyData but with EN-specific sources."""
    out = {}
    if pd.notna(row.get("SUBTLEX_rank")):
        try:
            out["subtlex_rank"] = int(row["SUBTLEX_rank"])
        except (ValueError, TypeError):
            pass
    if pd.notna(row.get("SUBTLEX_freq")):
        try:
            out["subtlex_freq_per_million"] = float(row["SUBTLEX_freq"])
        except (ValueError, TypeError):
            pass
    if pd.notna(row.get("HermitDave_rank")):
        try:
            out["hermit_rank"] = int(row["HermitDave_rank"])
        except (ValueError, TypeError):
            pass
    if pd.notna(row.get("HermitDave_freq")):
        try:
            out["hermit_freq"] = int(row["HermitDave_freq"])
        except (ValueError, TypeError):
            pass
    if pd.notna(row.get("AoA")):
        try:
            out["aoa_kuperman"] = float(row["AoA"])
        except (ValueError, TypeError):
            pass
    # averageRank — simple average of available ranks (lower = more frequent)
    ranks = [v for k, v in out.items() if k.endswith("_rank")]
    if ranks:
        out["average_rank"] = sum(ranks) / len(ranks)
    return out


def main():
    if not INPUT.exists():
        print(f"Input not found: {INPUT}")
        print("Run 02_enrich_with_spacy_en.py first.")
        sys.exit(1)

    df = pd.read_csv(INPUT)
    print(f"Loaded {len(df)} rows from {INPUT.name}")

    vocab = []
    for i, row in df.iterrows():
        word = str(row["Word"]).strip().lower()
        if not word:
            continue
        grade, reason = assign_grade(row)
        tags = build_tags(row, reason)
        freq = build_frequency_data(row)

        word_type = row.get("WordType") if pd.notna(row.get("WordType")) else "andere"
        article = row.get("DefaultArticle")
        article = article if isinstance(article, str) and article else None

        entry = {
            "id": f"word_en_{i:05d}",
            "word": word,
            "lemma": row["Lemma"] if pd.notna(row.get("Lemma")) else word,
            "wordType": word_type,
            "article": article,        # nullable; only set for nouns
            "genus": None,             # always None for EN
            "gradeLevel": grade,
            "gradeReason": reason,
            "tags": tags,
            "morphology": row["Morphology"] if pd.notna(row.get("Morphology")) else "",
            "frequencyData": freq,
            # Placeholders to be populated by later pipeline steps:
            "pronunciation": None,             # step 05
            "graphemeVariants": [],            # step 06
            "apiEnrichment": None,             # step 11
            "commonLearnerErrors": [],         # step 11 / common misspellings
            "translations": [],                # step 11 (EN->DE per the locked-in mirror use case)
            "inflectionData": None,            # step 11
            "definitions": [],                 # step 11
            "examples": [],                    # step 11
        }
        vocab.append(entry)

    # Sort by grade then alphabetical for deterministic output
    vocab.sort(key=lambda e: (e["gradeLevel"], e["word"]))
    # Re-issue stable IDs after sort so they're predictable
    for i, e in enumerate(vocab):
        e["id"] = f"word_en_{i:05d}"

    payload = {
        "metadata": {
            "language": "en",
            "variant": "uk",
            "schema_version": 1,
            "source_step": "03_conv_csv_to_json_en.py",
            "word_count": len(vocab),
        },
        "vocabulary": vocab,
    }

    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2),
                      encoding="utf-8")
    print(f"\nWrote {len(vocab)} entries to {OUTPUT.name}")

    # Per-grade distribution
    print("\n=== Grade distribution ===")
    by_grade = {}
    for e in vocab:
        by_grade[e["gradeLevel"]] = by_grade.get(e["gradeLevel"], 0) + 1
    for g in sorted(by_grade):
        n = by_grade[g]
        pct = 100.0 * n / len(vocab)
        print(f"  G{g}: {n:>6d}  ({pct:5.1f} %)")

    # Per-grade-reason distribution (sanity-check the cascade)
    print("\n=== Grade-assignment-reason distribution ===")
    by_reason = {}
    for e in vocab:
        # bucket reasons by their prefix
        prefix = e["gradeReason"].split("_")[0]
        by_reason[prefix] = by_reason.get(prefix, 0) + 1
    for r in sorted(by_reason, key=lambda k: -by_reason[k]):
        n = by_reason[r]
        pct = 100.0 * n / len(vocab)
        print(f"  {r:20s} {n:>6d}  ({pct:5.1f} %)")


if __name__ == "__main__":
    main()
