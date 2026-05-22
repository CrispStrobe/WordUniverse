"""In-place patch for the shipped DE DB: populate `graphematicVariants` in
each entry's enrichment_json so the Flutter `space_word_rescue_game` can
recognize common misspellings.

The full DE pipeline (00..14) needs `grundwortschatz_phonemized.json` from
step 05 as input to step 06 — that intermediate file isn't in the repo, and
the source JSON used to build the shipped DB is uncommitted/lost. Rather
than reconstruct the entire pipeline, this script generates variants
algorithmically from each word's ipaPhoneme and writes them directly into
the shipped DB.

Variant generation: a small rule set per German grapheme-phoneme confusion
(extracted from pipeline/voc-de/06_generate_grapheme_variants.py and DE
common misspelling patterns). For each rule, if the word matches a position
where the rule applies, generate a variant by substituting.

Combines with Wikipedia misspellings (from sources/de_wiki_misspellings.csv):
when a specific (correct, wrong) pair is known, the wrong form is added as
a variant with probability=100.
"""
from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import shutil
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parent.parent

DEFAULT_DB = HERE / "grundwortschatz_en_enriched_v24.db"  # placeholder
SHIPPED_GZ = ROOT / "assets" / "grundwortschatz.db.gz"

# Common DE grapheme confusion rules: (regex_pattern, replacement, probability)
# Probability is a hint about how often this misspelling occurs (1-100).
# Patterns are applied case-insensitively but preserve case in output.
DE_RULES = [
    # Doubled consonants ↔ single
    (r"mm", "m", 30),
    (r"nn", "n", 30),
    (r"ll", "l", 30),
    (r"tt", "t", 30),
    (r"ss", "s", 25),
    (r"ff", "f", 25),
    (r"pp", "p", 20),
    (r"rr", "r", 25),
    # ß ↔ ss
    (r"ß", "ss", 40),
    (r"(?<=[aeiouäöü])ss(?![aeiouäöü])", "ß", 25),  # heuristic
    # ie ↔ ih ↔ i (long-i confusion)
    (r"ie", "ih", 15),
    (r"ie", "i", 15),
    # ph ↔ f
    (r"ph", "f", 20),
    (r"(?<=[aeiouäöü])f(?=[aeiouäöü])", "ph", 5),
    # th ↔ t (older German spelling)
    (r"th", "t", 10),
    # v ↔ f / w ↔ v (foreign loans)
    (r"^V", "F", 10),
    (r"^W", "V", 5),
    # h-Dehnung dropped
    (r"ah", "a", 10),
    (r"eh", "e", 10),
    (r"oh", "o", 10),
    (r"uh", "u", 10),
    # ck ↔ kk ↔ k
    (r"ck", "kk", 5),
    (r"ck", "k", 5),
    # tz ↔ z ↔ zz
    (r"tz", "z", 10),
    (r"tz", "zz", 5),
    # Umlauts ↔ digraphs
    (r"ä", "ae", 10),
    (r"ö", "oe", 10),
    (r"ü", "ue", 10),
    (r"ae", "ä", 5),
    (r"oe", "ö", 5),
    (r"ue", "ü", 5),
    # eu ↔ äu (etymological)
    (r"eu", "äu", 15),
    (r"äu", "eu", 10),
]


def generate_variants(word: str, max_variants: int = 8) -> list[dict]:
    """Apply DE_RULES to `word` and return variants matching the schema
    {"spelling": str, "probability": float, "rule": str}."""
    variants: list[dict] = []
    seen: set[str] = {word.lower()}
    for pattern, repl, prob in DE_RULES:
        try:
            for m in re.finditer(pattern, word, flags=re.IGNORECASE):
                start, end = m.span()
                # Build the variant by replacing this match preserving case
                original = m.group()
                # If original was uppercase first, capitalize repl appropriately
                if original and original[0].isupper() and repl and repl[0].islower():
                    actual_repl = repl[0].upper() + repl[1:]
                else:
                    actual_repl = repl
                variant = word[:start] + actual_repl + word[end:]
                key = variant.lower()
                if key not in seen and variant != word:
                    seen.add(key)
                    variants.append({
                        "spelling": variant,
                        "probability": float(prob),
                        "rule": f"{pattern}>{repl}",
                    })
                    if len(variants) >= max_variants:
                        return variants
        except re.error:
            continue
    return variants


def load_wiki_misspellings(csv_path: Path) -> dict[str, list[str]]:
    """Return {correct.lower(): [wrong, wrong, ...]} from CSV."""
    out: dict[str, list[str]] = {}
    if not csv_path.exists():
        return out
    with csv_path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            c = (row.get("correct") or "").strip()
            w = (row.get("wrong") or "").strip()
            if c and w:
                out.setdefault(c.lower(), []).append(w)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(HERE / "grundwortschatz.db"),
                    help="DE DB to patch (will be modified in place)")
    ap.add_argument("--from-gz", action="store_true",
                    help="Start by decompressing assets/grundwortschatz.db.gz")
    args = ap.parse_args()

    db_path = Path(args.db)
    if args.from_gz:
        print(f"Decompressing {SHIPPED_GZ.name} → {db_path}")
        with gzip.open(SHIPPED_GZ, "rb") as fin, db_path.open("wb") as fout:
            shutil.copyfileobj(fin, fout)
    if not db_path.exists():
        raise SystemExit(f"DB not found: {db_path}")

    print(f"Loading wiki misspellings from sources/de_wiki_misspellings.csv …")
    wiki_misspell = load_wiki_misspellings(HERE / "sources" / "de_wiki_misspellings.csv")
    print(f"  {len(wiki_misspell)} entries with known misspellings")

    print(f"Patching {db_path} …")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    n_total = 0
    n_updated = 0
    n_variants_total = 0
    n_with_wiki_pair = 0

    rows = cur.execute("SELECT id, word, enrichment_json FROM words").fetchall()
    for row_id, word, ej in rows:
        n_total += 1
        if not word:
            continue
        ej_obj = json.loads(ej) if ej else {}

        # Skip if already has graphematicVariants (idempotent)
        if ej_obj.get("graphematicVariants"):
            continue

        algo_variants = generate_variants(word, max_variants=6)
        wiki_misspells = wiki_misspell.get(word.lower(), [])
        wiki_variants = [
            {"spelling": w, "probability": 100.0, "rule": "wiki_haeufige_falschschreibungen"}
            for w in wiki_misspells
        ]

        combined = wiki_variants + algo_variants
        # Dedup by spelling.lower()
        seen: set[str] = set()
        deduped: list[dict] = []
        for v in combined:
            k = v["spelling"].lower()
            if k in seen:
                continue
            seen.add(k)
            deduped.append(v)

        if deduped:
            ej_obj["graphematicVariants"] = deduped
            cur.execute(
                "UPDATE words SET enrichment_json = ? WHERE id = ?",
                (json.dumps(ej_obj, ensure_ascii=False), row_id),
            )
            n_updated += 1
            n_variants_total += len(deduped)
            if wiki_variants:
                n_with_wiki_pair += 1

    conn.commit()
    conn.close()

    print(f"Done.")
    print(f"  total entries:           {n_total}")
    print(f"  updated:                 {n_updated}")
    print(f"  total variants written:  {n_variants_total}")
    print(f"  with wiki misspell pair: {n_with_wiki_pair}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
