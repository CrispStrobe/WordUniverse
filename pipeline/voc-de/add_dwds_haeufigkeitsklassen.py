"""Add DWDS Häufigkeitsklassen (frequency class 0-6 per lemma) to the
shipped DB. Adds the field `frequency_json.dwds: {frequenzklasse: N,
wortklasse: …}` for every DB word that matches a DWDS lemma.

Source CSV: https://www.dwds.de/lemma/csv (full DWDS lemma database)
  Columns: lemma, url, wortklasse, artikeldatum, artikeltyp, frequenzklasse
  License: Creative Commons CC BY-SA 4.0 (per DWDS lemma database page)
           Attribution: "Digitales Wörterbuch der deutschen Sprache (DWDS)"

Häufigkeitsklasse scale: 7-level
  0 = selten (rare)  …  6 = häufig (very frequent)
  "n/a" for affixes, multi-word expressions where freq cannot be reliably
  computed.

Pre-conditions:
  - /tmp/dwds_lemma.csv must exist (fetched via curl from /lemma/csv).
"""

from __future__ import annotations

import csv
import gzip
import json
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"
WORK = Path("/tmp/dbpatch/working.db")
DWDS_CSV = Path("/tmp/dwds_lemma.csv")


def load_dwds_index(csv_path: Path) -> dict[str, dict]:
    """Return {lemma_lowercased: {frequenzklasse: int, wortklasse: str}}.
    Best entry per lemma: prefer Vollartikel + non-n/a frequenzklasse.
    """
    idx: dict[str, dict] = {}
    with csv_path.open(encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            lemma = (row.get("lemma") or "").strip()
            if not lemma:
                continue
            key = lemma.lower()
            fk_raw = (row.get("frequenzklasse") or "").strip()
            try:
                fk: int | None = int(fk_raw)
            except ValueError:
                fk = None  # n/a, unknown
            wk = (row.get("wortklasse") or "").strip() or None
            entry = {"frequenzklasse": fk, "wortklasse": wk}
            existing = idx.get(key)
            if existing is None:
                idx[key] = entry
                continue
            # Prefer an entry with a numeric frequenzklasse over n/a.
            if existing["frequenzklasse"] is None and fk is not None:
                idx[key] = entry
    return idx


def main() -> int:
    if not DWDS_CSV.exists():
        print(f"ERROR: DWDS CSV not found: {DWDS_CSV}", file=sys.stderr)
        return 1
    if not DB_GZ.exists():
        print(f"ERROR: shipped DB not found: {DB_GZ}", file=sys.stderr)
        return 1

    print(f"Loading DWDS lemma index from {DWDS_CSV}")
    dwds = load_dwds_index(DWDS_CSV)
    print(f"  {len(dwds)} unique DWDS lemmas")
    fk_dist: dict = {}
    for v in dwds.values():
        fk_dist[v["frequenzklasse"]] = fk_dist.get(v["frequenzklasse"], 0) + 1
    print("  frequenzklasse distribution in DWDS:")
    for k in sorted(fk_dist.keys(), key=lambda x: (x is None, x)):
        print(f"    {k}: {fk_dist[k]}")

    WORK.parent.mkdir(parents=True, exist_ok=True)
    if WORK.exists():
        WORK.unlink()
    print(f"Decompressing {DB_GZ} -> {WORK}")
    with gzip.open(DB_GZ, "rb") as fi, WORK.open("wb") as fo:
        fo.write(fi.read())

    con = sqlite3.connect(str(WORK))
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute("SELECT id, word, lemma, frequency_json FROM words")
    rows = cur.fetchall()

    update_cur = con.cursor()
    matched = 0
    matched_with_fk = 0
    fk_buckets: dict[int, int] = {}

    for r in rows:
        try:
            freq = json.loads(r["frequency_json"]) if r["frequency_json"] else {}
        except json.JSONDecodeError:
            freq = {}
        if not isinstance(freq, dict):
            freq = {}

        word_key = (r["word"] or "").strip().lower()
        lemma_key = (r["lemma"] or "").strip().lower()
        entry = dwds.get(word_key) or dwds.get(lemma_key)
        if entry is None:
            continue

        freq["dwds"] = {
            k: v for k, v in entry.items() if v is not None
        }
        # Drop empty dict if nothing meaningful.
        if not freq["dwds"]:
            continue
        update_cur.execute(
            "UPDATE words SET frequency_json = ? WHERE id = ?",
            (json.dumps(freq, ensure_ascii=False), r["id"]),
        )
        matched += 1
        if entry["frequenzklasse"] is not None:
            matched_with_fk += 1
            fk_buckets[entry["frequenzklasse"]] = fk_buckets.get(entry["frequenzklasse"], 0) + 1

    con.commit()
    con.close()

    print(f"Tagged {matched} words with DWDS data")
    print(f"  Of those, {matched_with_fk} have a numeric frequenzklasse")
    print("  frequenzklasse distribution in matched DB words:")
    for k in sorted(fk_buckets.keys()):
        print(f"    {k}: {fk_buckets[k]}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
