"""Populate frequency_json for every EN DB entry using wordfreq.

Adds to the frequency_json column:
  {"zipf": 5.22, "per_million": 16.5, "frequency_band": 2}

Zipf scale (Brysbaert): log10(occurrences per billion words).
  ≥ 6.0 → band 1 (ultra-high: the, be, have, …)
  ≥ 5.0 → band 2 (high: book, walk, happy, …)
  ≥ 4.0 → band 3 (medium: abrupt, cautious, …)
  ≥ 3.0 → band 4 (low: abstruse, …)
   < 3.0 → band 5 (rare / proper names / misspellings)

wordfreq is Apache-2.0 (code) + CC-BY-SA 4.0 (data).
Commercial use allowed; attribute and share-alike for the derived DB.

Usage:
  pip install wordfreq
  python add_wordfreq_en.py [--db grundwortschatz_en.db] [--no-compress] [--dry-run]
"""

from __future__ import annotations

import argparse
import gzip
import json
import shutil
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DEFAULT_DB = HERE / "grundwortschatz_en.db"
WORK_DB    = Path("/tmp/dbpatch_wordfreq_en/working.db")
DB_GZ      = REPO / "assets" / "grundwortschatz_en.db.gz"

ZIPF_BANDS = [
    (6.0, 1),
    (5.0, 2),
    (4.0, 3),
    (3.0, 4),
]


def zipf_band(z: float) -> int:
    for threshold, band in ZIPF_BANDS:
        if z >= threshold:
            return band
    return 5


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",          default=str(DEFAULT_DB))
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--dry-run",     action="store_true")
    ap.add_argument("--overwrite",   action="store_true",
                    help="Re-compute even if frequency_json already set")
    args = ap.parse_args()

    try:
        from wordfreq import zipf_frequency, word_frequency
    except ImportError:
        sys.exit("ERROR: wordfreq not installed — pip install wordfreq")

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row

    rows = con.execute(
        "SELECT id, word, lemma, frequency_json FROM words"
    ).fetchall()
    rows = [dict(r) for r in rows]
    print(f"Loaded {len(rows)} entries")

    if not args.overwrite:
        rows = [r for r in rows if not r.get("frequency_json")]
    print(f"Entries to process: {len(rows)}")

    updated = 0
    band_counts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}

    for r in rows:
        word = (r.get("word") or "").strip()
        lemma = (r.get("lemma") or "").strip()

        # Use lemma frequency if word is inflected and has a higher score
        z_word  = zipf_frequency(word,  "en") if word  else 0.0
        z_lemma = zipf_frequency(lemma, "en") if lemma and lemma != word else 0.0
        z = max(z_word, z_lemma)

        per_million = round(word_frequency(word, "en") * 1_000_000, 4) if word else 0.0

        freq_data = {
            "zipf": round(z, 3),
            "per_million": per_million,
            "frequency_band": zipf_band(z),
        }
        band_counts[zipf_band(z)] += 1

        if not args.dry_run:
            con.execute(
                "UPDATE words SET frequency_json = ? WHERE id = ?",
                (json.dumps(freq_data), r["id"]),
            )
        updated += 1

    if not args.dry_run:
        con.commit()

    print(f"Updated {updated} entries")
    print("Band distribution:")
    for b, c in sorted(band_counts.items()):
        label = {1:"≥6.0 ultra-high", 2:"≥5.0 high", 3:"≥4.0 medium",
                 4:"≥3.0 low", 5:"<3.0 rare"}[b]
        print(f"  Band {b} ({label}): {c}")

    con.close()

    if not args.dry_run:
        print(f"Copying {WORK_DB} → {src_db}")
        shutil.copy2(WORK_DB, src_db)
        if not args.no_compress and DB_GZ.exists():
            print(f"Compressing → {DB_GZ}")
            with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
                shutil.copyfileobj(fi, fo)
            print(f"  {DB_GZ.stat().st_size // 1024} KB")

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
