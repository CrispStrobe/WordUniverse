"""Diagnostic: characterise the ~36% non-clean FRESCH cases (PLAN §6).

For every gold word the v2 classifier does NOT get "clean" on, print:
  word | gold tokens | predicted set | failure mode | the feature inputs
that drove the decision (ipa / inflections / hyphenation / doubling).

Failure modes:
  UNDER  — a gold requirement was not covered (missed a category)
  OVER   — predicted a category no gold requirement accepts
  BOTH   — under-covered AND over-tagged

Then it buckets the UNDER misses by which gold category was missed and prints
a per-bucket sample so we can see whether a *principled* (non-overfitting)
signal exists to recover them.

Usage:  python3 analyze_fresch_misses.py [--db grundwortschatz.db]
"""
from __future__ import annotations

import argparse
import json
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path

from fresch_classifier_v2 import (
    classify, KLANGTREU, DOPPELKONSONANT, VERWANDT, MERKWORT, MORPHEM,
    GROSSSCHREIBUNG,
)
from fresch_db_features import features_from_row
from validate_fresch import load_gold, FRESCH_TO_ACCEPT, score

HERE = Path(__file__).parent
DEFAULT_DB = HERE / "grundwortschatz.db"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DEFAULT_DB))
    ap.add_argument("--show", type=int, default=10,
                    help="rows to print per UNDER bucket")
    args = ap.parse_args()

    gold = load_gold()
    con = sqlite3.connect(args.db)
    cur = con.cursor()

    under_buckets: dict[str, list] = defaultdict(list)
    over_buckets: dict[str, list] = defaultdict(list)
    mode_counter = Counter()
    nonclean = []

    for word, toks in gold:
        cur.execute(
            "SELECT word, word_type, article, enrichment_json, metadata_json "
            "FROM words WHERE word=? COLLATE NOCASE LIMIT 1", (word,))
        row = cur.fetchone()
        if not row:
            continue
        w, wt, art, ej, mj = row
        feats = features_from_row(w, wt, art, ej, mj)
        c = classify(feats)
        pred = set(c.detailed)
        s = score(pred, toks)
        if s["clean"]:
            continue

        accept_union = set().union(*(FRESCH_TO_ACCEPT[t] for t in toks))
        under = [t for t in toks if not (FRESCH_TO_ACCEPT[t] & pred)]
        over = [cat for cat in pred if cat not in accept_union]
        mode = ("BOTH" if under and over else
                "UNDER" if under else "OVER")
        mode_counter[mode] += 1

        enrich = json.loads(ej) if ej else {}
        info = {
            "word": w,
            "gold": " ".join(toks),
            "pred": " ".join(sorted(pred)),
            "primary": c.detailed_primary,
            "ipa": feats.ipa or "",
            "infl": feats.inflected_forms[:6],
            "hyph": feats.hyphenation,
            "ler": feats.litkey_error_rate,
        }
        nonclean.append((mode, under, over, info))
        for t in under:
            under_buckets[t].append(info)
        for cat in over:
            over_buckets[cat].append(info)

    con.close()

    print(f"\nNon-clean cases: {len(nonclean)}/389")
    print(f"  modes: {dict(mode_counter)}")

    print("\n========== UNDER-COVERED gold categories ==========")
    for t in sorted(under_buckets, key=lambda k: -len(under_buckets[k])):
        rows = under_buckets[t]
        print(f"\n### gold '{t}' missed  ({len(rows)} words) — accepts {sorted(FRESCH_TO_ACCEPT[t])}")
        for info in rows[: args.show]:
            print(f"  {info['word']:18s} gold=[{info['gold']:28s}] pred=[{info['pred']:28s}]")
            print(f"      ipa={info['ipa']!r:30s} hyph={info['hyph']} infl={info['infl']} ler={info['ler']}")

    print("\n========== OVER-TAGGED predicted categories ==========")
    for cat in sorted(over_buckets, key=lambda k: -len(over_buckets[k])):
        rows = over_buckets[cat]
        print(f"\n### predicted '{cat}' rejected by gold  ({len(rows)} words)")
        for info in rows[: args.show]:
            print(f"  {info['word']:18s} gold=[{info['gold']:28s}] pred=[{info['pred']:28s}]")


if __name__ == "__main__":
    main()
