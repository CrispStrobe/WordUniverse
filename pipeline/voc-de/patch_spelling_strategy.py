"""Apply the science-grounded spelling-strategy classifier to the DE DB.

Recomputes, for every non-Vorname content word, the principle-based tags from
`spelling_strategy_classifier.py` (see SPELLING_STRATEGY_SPEC.md):

  enrichment_json.spellingStrategy        list  (7-category detailed view)
  enrichment_json.spellingStrategyPrimary str
  enrichment_json.spellingExplanation     str   (NEW — per-word, German)
  enrichment_json.spellingStrategySource  = "principle_based_v3"

It REMOVES the obsolete dual-taxonomy fields from the worksheet-fitted version
(spellingPatterns / spellingPatternsPrimary / spellingPatternsThome*) so the DB
carries only the current, consistent scheme. The `nrwLinguisticFeatures`
provenance field (if present) is left untouched.

Skips Vornamen (blank word_type + VORNAME source). Idempotent.

Usage:
  python3 patch_spelling_strategy.py --dry-run
  python3 patch_spelling_strategy.py
"""
from __future__ import annotations

import argparse
import json
import sqlite3
from collections import Counter
from pathlib import Path

from spelling_strategy_classifier import classify
from spelling_db_features import features_from_row

HERE = Path(__file__).parent
DEFAULT_DB = HERE / "grundwortschatz.db"

OBSOLETE_FIELDS = (
    "spellingPatterns", "spellingPatternsPrimary",
    "spellingPatternsThome", "spellingPatternsThomePrimary",
)


def is_vorname(word_type, metadata_json) -> bool:
    if word_type and str(word_type).strip():
        return False
    return bool(metadata_json and "VORNAME" in metadata_json)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DEFAULT_DB))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    con = sqlite3.connect(args.db)
    cur = con.cursor()
    cur.execute("SELECT id, word, word_type, article, enrichment_json, "
                "metadata_json FROM words")
    rows = cur.fetchall()

    recompute = skip_vorname = skip_other = 0
    primary = Counter()
    updates = []
    samples = []

    for wid, word, wt, art, ej, mj in rows:
        enrich = json.loads(ej) if ej else {}
        if not isinstance(enrich, dict):
            enrich = {}
        if is_vorname(wt, mj):
            skip_vorname += 1
            continue
        if not (wt and str(wt).strip()):
            skip_other += 1
            continue

        c = classify(features_from_row(word, wt, art, ej, mj))
        enrich["spellingStrategy"] = c.detailed
        enrich["spellingStrategyPrimary"] = c.detailed_primary
        enrich["spellingExplanation"] = c.explanation
        enrich["spellingStrategySource"] = "principle_based_v3"
        for f in OBSOLETE_FIELDS:
            enrich.pop(f, None)

        recompute += 1
        primary[c.detailed_primary] += 1
        if len(samples) < 12:
            samples.append((word, c.detailed_primary, c.detailed))
        updates.append((json.dumps(enrich, ensure_ascii=False), wid))

    print(f"Rows scanned        : {len(rows)}")
    print(f"  recompute         : {recompute}")
    print(f"  skip Vornamen     : {skip_vorname}")
    print(f"  skip other-blank  : {skip_other}")
    print("  primary distribution:")
    tot = sum(primary.values())
    for k, n in primary.most_common():
        print(f"      {k:16s} {n:6d}  ({100*n/tot:5.1f}%)")
    print("  samples:")
    for w, p, d in samples:
        print(f"      {w:16s} {p:16s} {d}")

    if args.dry_run:
        print("\n[dry-run] no writes performed.")
        con.close()
        return
    cur.executemany("UPDATE words SET enrichment_json=? WHERE id=?", updates)
    con.commit()
    con.close()
    print(f"\n✅ Wrote {len(updates)} updated rows to {args.db}")


if __name__ == "__main__":
    main()
