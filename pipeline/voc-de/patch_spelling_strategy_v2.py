"""Apply the v2 spelling-strategy classifier to the shipped DE DB (PLAN §6).

Recomputes `spellingStrategy` / `spellingStrategyPrimary` / `spellingPatterns`
/ `spellingPatternsPrimary` in `enrichment_json` using the principled v2
classifier (`fresch_classifier_v2.py`), which reads the rich enrichment
already present in each row (hyphenation, inflections, IPA, litkey error
rate) instead of the crude v1 surface-regex fallback.

Scope (idempotent — safe to re-run):
  • RECOMPUTE every non-Vorname content word with v2. This includes the
    ~463 words that were 'nrw_derived' in v1: measured against the gold
    (validate_fresch.py), v2 beats the v1 NRW-feature mapping even on those
    words (clean 14.3%→51.9%, primary 58.6%→82.3%) — the v1 lossy step was
    mapping NRW xlsx flags to categories, which v2 sidesteps by reading the
    word's own hyphenation / inflections / IPA. The authoritative
    `nrwLinguisticFeatures` provenance field is PRESERVED untouched.
  • All recomputed words get spellingStrategySource = 'v2_derived'.
  • SKIP Vornamen (blank word_type) — proper names get no spelling strategy
    (consistent with the existing DB).

Validated against `532Strategien.csv` (PLAN §6.6): see `validate_fresch.py`.

Usage:
  python3 patch_spelling_strategy_v2.py --dry-run     # report, no writes
  python3 patch_spelling_strategy_v2.py               # apply in place
  python3 patch_spelling_strategy_v2.py --db path.db
"""
from __future__ import annotations

import argparse
import json
import sqlite3
from collections import Counter
from pathlib import Path

from fresch_classifier_v2 import classify
from fresch_db_features import features_from_row

HERE = Path(__file__).parent
DEFAULT_DB = HERE / "grundwortschatz.db"


def is_vorname(word_type, metadata_json) -> bool:
    if word_type and str(word_type).strip():
        return False
    # blank word_type + VORNAME source = proper name (intentionally untagged)
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

    recompute = from_nrw = skip_vorname = skip_other = 0
    before_primary = Counter()
    after_primary = Counter()
    changed_primary = 0
    sample_changes = []
    updates = []

    for wid, word, wt, art, ej, mj in rows:
        enrich = json.loads(ej) if ej else {}
        if not isinstance(enrich, dict):
            enrich = {}
        src = enrich.get("spellingStrategySource")
        if src == "nrw_derived":
            from_nrw += 1

        if is_vorname(wt, mj):
            skip_vorname += 1
            continue
        if not (wt and str(wt).strip()):
            # blank word_type but not a recognised Vorname — skip to be safe
            skip_other += 1
            continue

        old_primary = enrich.get("spellingStrategyPrimary")
        feats = features_from_row(word, wt, art, ej, mj)
        c = classify(feats)

        enrich["spellingStrategy"] = c.detailed
        enrich["spellingStrategyPrimary"] = c.detailed_primary
        enrich["spellingPatterns"] = c.thome
        enrich["spellingPatternsPrimary"] = c.thome_primary
        enrich["spellingStrategySource"] = "v2_derived"

        recompute += 1
        before_primary[old_primary] += 1
        after_primary[c.detailed_primary] += 1
        if old_primary != c.detailed_primary:
            changed_primary += 1
            if len(sample_changes) < 15:
                sample_changes.append(
                    (word, old_primary, c.detailed_primary, c.detailed))
        updates.append((json.dumps(enrich, ensure_ascii=False), wid))

    print(f"Rows scanned          : {len(rows)}")
    print(f"  recompute (v2)      : {recompute}  (of which {from_nrw} were nrw_derived; nrwLinguisticFeatures kept)")
    print(f"  skip Vornamen       : {skip_vorname}")
    print(f"  skip other-blank-wt : {skip_other}")
    print(f"  primary changed     : {changed_primary} / {recompute}")

    def dist(c: Counter, total: int):
        for k in ("klangtreu", "doppelkonsonant", "verwandt", "merkwort",
                  "morphem", "grossschreibung", None):
            n = c.get(k, 0)
            if n:
                print(f"      {str(k):16s} {n:>6}  ({100*n/total:5.1f}%)")

    tot = sum(after_primary.values())
    print("\n  primary distribution BEFORE (recomputed + nrw):")
    dist(before_primary, tot)
    print("  primary distribution AFTER:")
    dist(after_primary, tot)

    print("\n  sample primary changes (old → new):")
    for w, o, n, d in sample_changes:
        print(f"      {w:16s} {str(o):16s} → {n:16s} {d}")

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
