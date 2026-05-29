"""Validate the spelling-strategy classifier against the principle-based gold
(`spelling_strategy_gold.csv`, literature-sourced — see SPELLING_STRATEGY_SPEC.md).

Unlike the old worksheet harness, the gold here is internally consistent and
tagged by the orthographic principles, so we measure EXACT agreement (the
classifier is meant to operationalize the same rules that tagged the gold):

  • primary-exact : predicted primary == gold primary
  • set-exact     : predicted detailed set == gold set
  • mismatches are printed with the word's features for inspection

Usage: python3 validate_spelling.py [--db grundwortschatz.db] [--show-expl]
"""
from __future__ import annotations

import argparse
import csv
import sqlite3
from pathlib import Path

from spelling_strategy_classifier import classify
from spelling_db_features import features_from_row

HERE = Path(__file__).parent
GOLD = HERE / "spelling_strategy_gold.csv"
DEFAULT_DB = HERE / "grundwortschatz.db"


def load_gold():
    rows = []
    with GOLD.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows.append((r["word"].strip(), r["primary"].strip(),
                         set(r["all"].split()), r.get("note", "")))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DEFAULT_DB))
    ap.add_argument("--show-expl", action="store_true")
    args = ap.parse_args()

    gold = load_gold()
    con = sqlite3.connect(args.db)
    cur = con.cursor()

    n = prim_ok = set_ok = missing = 0
    mismatches = []
    for word, gprim, gset, note in gold:
        cur.execute("SELECT word, word_type, article, enrichment_json, metadata_json "
                    "FROM words WHERE word=? COLLATE NOCASE LIMIT 1", (word,))
        row = cur.fetchone()
        if not row:
            missing += 1
            mismatches.append((word, "—", "(not in DB)", gprim,
                               " ".join(sorted(gset)), note, ""))
            continue
        n += 1
        c = classify(features_from_row(*row))
        pset = set(c.detailed)
        p_ok = c.detailed_primary == gprim
        s_ok = pset == gset
        prim_ok += p_ok
        set_ok += s_ok
        if not (p_ok and s_ok):
            mismatches.append((word, c.detailed_primary, " ".join(sorted(pset)),
                               gprim, " ".join(sorted(gset)), note, c.explanation))
        elif args.show_expl:
            print(f"  ✓ {word:14s} [{c.detailed_primary}] {c.explanation}")
    con.close()

    print(f"\n=== spelling-strategy validation (n={n}, missing={missing}) ===")
    print(f"  primary-exact : {prim_ok}/{n}  ({100*prim_ok/n:.1f}%)")
    print(f"  set-exact     : {set_ok}/{n}  ({100*set_ok/n:.1f}%)")
    if mismatches:
        print(f"\n  {len(mismatches)} mismatch(es):")
        for w, pp, ps, gp, gs, note, expl in mismatches:
            print(f"    {w:14s} pred=[{pp:16s} | {ps:34s}]")
            print(f"    {'':14s} gold=[{gp:16s} | {gs:34s}]  ({note})")
            if args.show_expl and expl:
                print(f"    {'':14s} expl: {expl}")


if __name__ == "__main__":
    main()
