"""Validation harness for the spelling-strategy classifier (PLAN §6.6).

Compares classifier output against the curated gold fixture
`532Strategien.csv` (389 rated words, FRESCH terminology). It reports both
the current shipped tags (baseline) and the v2 classifier, under a
*scheme-aware* metric.

Why scheme-aware: the FRESCH gold and our 6-category scheme partition the
spelling space differently. FRESCH's "Weiterschwingen" (swing/extend the
word) covers BOTH our `doppelkonsonant` (short-vowel doubling) AND our
`verwandt` (Auslautverhärtung — extend to a related form to hear the
ending). So a gold "Weiterschwingen" is satisfied if the classifier emits
EITHER `doppelkonsonant` or `verwandt`. Demanding raw set-equality against
FRESCH would punish a linguistically-correct split, so we measure:

  • coverage  — fraction of gold requirements the prediction satisfies (recall)
  • precision — fraction of predicted cats that some gold requirement accepts
  • clean     — coverage==1 AND precision==1 (no under- and no over-tagging)
  • primary   — does the predicted primary category match a gold token

Usage:
  python3 validate_fresch.py                 # baseline + v2 on the DB
  python3 validate_fresch.py --db other.db
"""
from __future__ import annotations

import argparse
import csv
import json
import sqlite3
from collections import Counter
from pathlib import Path

from fresch_classifier_v2 import (
    classify, KLANGTREU, DOPPELKONSONANT, VERWANDT, MERKWORT, MORPHEM,
    GROSSSCHREIBUNG,
)
from fresch_db_features import features_from_row

HERE = Path(__file__).parent
GOLD = HERE / "532Strategien.csv"
DEFAULT_DB = HERE / "grundwortschatz.db"

# FRESCH token → set of acceptable predicted detailed categories ("one-of").
FRESCH_TO_ACCEPT = {
    "Mitsprechen":     {KLANGTREU},
    "Weiterschwingen": {DOPPELKONSONANT, VERWANDT},   # swing covers both
    "Ableiten":        {VERWANDT},
    "Wortbausteine":   {MORPHEM},
    "Merken":          {MERKWORT},
    "Großschreibung":  {GROSSSCHREIBUNG},
}
# token → the single category we treat as its primary representative
FRESCH_PRIMARY = {
    "Mitsprechen": KLANGTREU, "Weiterschwingen": DOPPELKONSONANT,
    "Ableiten": VERWANDT, "Wortbausteine": MORPHEM, "Merken": MERKWORT,
    "Großschreibung": GROSSSCHREIBUNG,
}


def load_gold() -> list[tuple[str, list[str]]]:
    """Return (word, [FRESCH tokens]) for each rated gold row."""
    rows = []
    with GOLD.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            s = r["Strategie"].strip()
            if s in ("", "--"):
                continue
            toks = [t for t in s.split() if t in FRESCH_TO_ACCEPT]
            if toks:
                rows.append((r["Wort"].strip(), toks))
    return rows


def score(pred: set[str], gold_toks: list[str]) -> dict:
    """Scheme-aware comparison of one prediction against gold tokens."""
    reqs = [FRESCH_TO_ACCEPT[t] for t in gold_toks]
    accept_union = set().union(*reqs) if reqs else set()
    covered = sum(1 for req in reqs if req & pred)
    coverage = covered / len(reqs) if reqs else 1.0
    justified = sum(1 for c in pred if c in accept_union)
    precision = justified / len(pred) if pred else 1.0
    return {
        "coverage": coverage,
        "precision": precision,
        "clean": coverage == 1.0 and precision == 1.0,
        "full_cover": coverage == 1.0,
        "no_overtag": precision == 1.0,
    }


def primary_match(primary: str, gold_toks: list[str]) -> bool:
    accept = set().union(*(FRESCH_TO_ACCEPT[t] for t in gold_toks))
    return primary in accept


def evaluate(name: str, predictions: dict[str, tuple[set[str], str]],
             gold: list[tuple[str, list[str]]]) -> None:
    n = 0
    agg = Counter()
    cov_sum = prec_sum = 0.0
    # per-category precision/recall (treating Weiterschwingen as dk+verwandt)
    cat_tp = Counter(); cat_fp = Counter(); cat_fn = Counter()
    primary_hits = 0
    missing = 0
    for word, toks in gold:
        if word not in predictions:
            missing += 1
            continue
        pred, primary = predictions[word]
        n += 1
        s = score(pred, toks)
        cov_sum += s["coverage"]; prec_sum += s["precision"]
        agg["clean"] += s["clean"]
        agg["full_cover"] += s["full_cover"]
        agg["no_overtag"] += s["no_overtag"]
        if primary_match(primary, toks):
            primary_hits += 1
        # per-cat
        accept_union = set().union(*(FRESCH_TO_ACCEPT[t] for t in toks))
        for c in pred:
            if c in accept_union:
                cat_tp[c] += 1
            else:
                cat_fp[c] += 1
        for req in (FRESCH_TO_ACCEPT[t] for t in toks):
            if not (req & pred):
                # under-covered requirement — attribute fn to each accept cat
                for c in req:
                    cat_fn[c] += 1

    print(f"\n=== {name}  (n={n}, missing-from-db={missing}) ===")
    print(f"  clean (no under/over-tag) : {agg['clean']:>4}/{n}  ({100*agg['clean']/n:5.1f} %)")
    print(f"  full coverage (no under)  : {agg['full_cover']:>4}/{n}  ({100*agg['full_cover']/n:5.1f} %)")
    print(f"  no over-tag (subset)      : {agg['no_overtag']:>4}/{n}  ({100*agg['no_overtag']/n:5.1f} %)")
    print(f"  mean coverage (recall)    : {100*cov_sum/n:5.1f} %")
    print(f"  mean precision            : {100*prec_sum/n:5.1f} %")
    print(f"  primary-category match    : {primary_hits:>4}/{n}  ({100*primary_hits/n:5.1f} %)")
    print("  per-category  (P / R):")
    for c in (KLANGTREU, DOPPELKONSONANT, VERWANDT, MERKWORT, MORPHEM, GROSSSCHREIBUNG):
        tp, fp, fn = cat_tp[c], cat_fp[c], cat_fn[c]
        p = tp / (tp + fp) if (tp + fp) else float("nan")
        r = tp / (tp + fn) if (tp + fn) else float("nan")
        print(f"    {c:16s}  P={p*100:5.1f}%  R={r*100:5.1f}%   (tp={tp} fp={fp} fn={fn})")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DEFAULT_DB))
    args = ap.parse_args()

    gold = load_gold()
    print(f"Loaded gold: {len(gold)} rated words from {GOLD.name}")

    con = sqlite3.connect(args.db)
    cur = con.cursor()

    baseline: dict[str, tuple[set[str], str]] = {}
    v2: dict[str, tuple[set[str], str]] = {}
    for word, _ in gold:
        cur.execute(
            "SELECT word, word_type, article, enrichment_json, metadata_json "
            "FROM words WHERE word=? COLLATE NOCASE LIMIT 1", (word,))
        row = cur.fetchone()
        if not row:
            continue
        w, wt, art, ej, mj = row
        enrich = json.loads(ej) if ej else {}
        # baseline: current shipped tags
        b_detailed = set(enrich.get("spellingStrategy") or [])
        b_primary = enrich.get("spellingStrategyPrimary") or (
            sorted(b_detailed)[0] if b_detailed else "")
        if b_detailed:
            baseline[word] = (b_detailed, b_primary)
        # v2: recompute
        feats = features_from_row(w, wt, art, ej, mj)
        c = classify(feats)
        v2[word] = (set(c.detailed), c.detailed_primary)
    con.close()

    evaluate("BASELINE (shipped spellingStrategy)", baseline, gold)
    evaluate("V2 classifier", v2, gold)


if __name__ == "__main__":
    main()
