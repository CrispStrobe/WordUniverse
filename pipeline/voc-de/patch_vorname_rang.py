"""Backfill vorname_rang into existing VORNAME_STANDESAMT entries.

Ranks are computed from the vorname_freq already stored in the DB
(rank 1 = highest combined count across all Standesamt sources).
Also sets vorname_rang for VORNAME_DE entries relative to the same ranking
if the name appears in the Standesamt data.

Usage:
  python patch_vorname_rang.py [--db grundwortschatz.db] [--no-compress] [--dry-run]
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

DEFAULT_DB = HERE / "grundwortschatz.db"
WORK_DB    = Path("/tmp/dbpatch_vorname_rang/working.db")
DB_GZ      = REPO / "assets" / "grundwortschatz.db.gz"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",          default=str(DEFAULT_DB))
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--dry-run",     action="store_true")
    args = ap.parse_args()

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row

    # Load all VORNAME_STANDESAMT entries with their stored freq
    rows = con.execute(
        "SELECT id, word, metadata_json FROM words "
        "WHERE metadata_json LIKE '%VORNAME_STANDESAMT%'"
    ).fetchall()
    print(f"VORNAME_STANDESAMT entries: {len(rows)}")

    # Sort by freq descending to assign rank
    parsed: list[tuple[int, str, dict]] = []
    for r in rows:
        try:
            meta = json.loads(r["metadata_json"] or "{}")
        except (json.JSONDecodeError, TypeError):
            meta = {}
        parsed.append((r["id"], r["word"], meta))

    parsed.sort(key=lambda t: t[2].get("vorname_freq", 0), reverse=True)

    updates: list[tuple[str, int]] = []
    for rank, (row_id, word, meta) in enumerate(parsed, start=1):
        if meta.get("vorname_rang") == rank:
            continue  # already correct
        meta["vorname_rang"] = rank
        updates.append((json.dumps(meta, ensure_ascii=False), row_id))

    print(f"Entries to update: {len(updates)}")
    if args.dry_run:
        for js, rid in updates[:10]:
            m = json.loads(js)
            print(f"  id={rid}  rang={m['vorname_rang']}  freq={m.get('vorname_freq')}")
        print("  (dry-run — no changes written)")
        con.close()
        return 0

    con.executemany(
        "UPDATE words SET metadata_json=? WHERE id=?",
        updates,
    )
    con.commit()
    print(f"Updated {len(updates)} entries with vorname_rang")
    con.close()

    print(f"Copying {WORK_DB} → {src_db}")
    shutil.copy2(WORK_DB, src_db)
    if not args.no_compress and DB_GZ.exists():
        print(f"Compressing → {DB_GZ}")
        with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
            shutil.copyfileobj(fi, fo)
        print(f"  {DB_GZ.stat().st_size // 1024} KB written")

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
