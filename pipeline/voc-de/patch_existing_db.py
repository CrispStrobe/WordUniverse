"""Patch the shipped assets/grundwortschatz.db.gz in place.

Adds the following fields to enrichment_json (top-level) for every word:
  - spellingStrategy           (6-cat detailed labels, sorted list)
  - spellingStrategyPrimary    (single primary detailed label)
  - spellingPatterns           (5-cat broad labels, sorted list)
  - spellingPatternsPrimary    (single primary broad label)
  - spellingStrategySource     ("nrw_derived" | "fallback_heuristic")
  - nrwLinguisticFeatures      (raw NRW xlsx feature paths; only when nrw_derived)
  - commonLearnerErrors        (Wikipedia "Häufige Falschschreibungen" pairs; only when applicable)

Reads:
  - assets/grundwortschatz.db.gz (decompressed to /tmp/dbpatch/working.db)
  - pipeline/voc-de/output_nested.json
  - pipeline/voc-de/sources/de_wiki_misspellings.csv

Writes:
  - assets/grundwortschatz.db.gz (gzip -9 of the patched DB)
"""

from __future__ import annotations

import csv
import gzip
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"
WORK = Path("/tmp/dbpatch/working.db")
NRW = REPO / "pipeline" / "voc-de" / "output_nested.json"
PATTERNS_PY = REPO / "pipeline" / "voc-de" / "04b_derive_spelling_patterns.py"
MISSPELLINGS = REPO / "pipeline" / "voc-de" / "sources" / "de_wiki_misspellings.csv"

WIKI_MISSPELLING_SOURCE = "wiki_haeufige_falschschreibungen"


def import_patterns_module():
    spec = importlib.util.spec_from_file_location("p04b", PATTERNS_PY)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load patterns module from {PATTERNS_PY}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_nrw_index(path: Path) -> dict[str, dict]:
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    idx: dict[str, dict] = {}
    for entry in data:
        art = entry.get("Artikel") if isinstance(entry, dict) else None
        w = art.get("_value") if isinstance(art, dict) else None
        if isinstance(w, str):
            idx[w.strip().lower()] = entry
    return idx


def build_misspellings_index(path: Path) -> dict[str, list[str]]:
    idx: dict[str, list[str]] = {}
    if not path.exists():
        return idx
    with path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            correct = (row.get("correct") or "").strip()
            wrong = (row.get("wrong") or "").strip()
            if correct and wrong:
                idx.setdefault(correct.lower(), []).append(wrong)
    return idx


def main() -> int:
    if not DB_GZ.exists():
        print(f"ERROR: shipped DB not found: {DB_GZ}", file=sys.stderr)
        return 1

    p04b = import_patterns_module()

    WORK.parent.mkdir(parents=True, exist_ok=True)
    if not WORK.exists():
        print(f"Decompressing {DB_GZ} -> {WORK}")
        with gzip.open(DB_GZ, "rb") as fi, WORK.open("wb") as fo:
            fo.write(fi.read())
    else:
        print(f"Reusing existing working copy at {WORK}")

    nrw_idx = build_nrw_index(NRW)
    print(f"NRW index entries: {len(nrw_idx)}")

    miss_idx = build_misspellings_index(MISSPELLINGS)
    print(f"Wikipedia misspelling lemmas: {len(miss_idx)}")

    con = sqlite3.connect(str(WORK))
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute(
        "SELECT id, word, lemma, word_type, article, enrichment_json FROM words"
    )
    rows = cur.fetchall()
    print(f"Loaded {len(rows)} words")

    updated = 0
    nrw_hits = 0
    fallback_hits = 0
    miss_added = 0

    update_cur = con.cursor()

    for r in rows:
        if r["enrichment_json"]:
            try:
                enr = json.loads(r["enrichment_json"])
                if not isinstance(enr, dict):
                    enr = {}
            except json.JSONDecodeError:
                enr = {}
        else:
            enr = {}

        word = r["word"] or ""
        lemma = r["lemma"] or ""
        word_type = r["word_type"]
        article = r["article"]

        word_key = word.strip().lower()
        lemma_key = lemma.strip().lower()
        nrw_entry = nrw_idx.get(word_key) or nrw_idx.get(lemma_key)

        if nrw_entry is not None:
            detailed, thome, raw_paths = p04b.nrw_features_to_patterns(nrw_entry)
            source = "nrw_derived"
            nrw_hits += 1
        else:
            detailed = p04b.fallback_categories(word, lemma, word_type, article)
            thome = p04b.detailed_to_thome(detailed)
            raw_paths = []
            source = "fallback_heuristic"
            fallback_hits += 1

        enr["spellingStrategy"] = sorted(detailed)
        enr["spellingStrategyPrimary"] = p04b.pick_primary_detailed(detailed)
        enr["spellingPatterns"] = sorted(thome)
        enr["spellingPatternsPrimary"] = p04b.pick_primary_thome(thome)
        enr["spellingStrategySource"] = source
        if raw_paths:
            enr["nrwLinguisticFeatures"] = sorted(set(raw_paths))

        wrongs = miss_idx.get(word_key) or miss_idx.get(lemma_key)
        if wrongs:
            existing = enr.get("commonLearnerErrors")
            if not isinstance(existing, list):
                existing = []
            existing_errors = {
                e.get("error") for e in existing if isinstance(e, dict)
            }
            added_any = False
            for w in wrongs:
                if w not in existing_errors:
                    existing.append({"error": w, "source": WIKI_MISSPELLING_SOURCE})
                    existing_errors.add(w)
                    added_any = True
            enr["commonLearnerErrors"] = existing
            if added_any:
                miss_added += 1

        update_cur.execute(
            "UPDATE words SET enrichment_json = ? WHERE id = ?",
            (json.dumps(enr, ensure_ascii=False), r["id"]),
        )
        updated += 1

    con.commit()
    con.close()

    print(
        f"Updated: {updated}  NRW-derived: {nrw_hits}  fallback: {fallback_hits}  "
        f"misspellings-added: {miss_added}"
    )

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
