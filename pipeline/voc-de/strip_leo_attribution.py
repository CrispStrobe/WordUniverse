"""Remove the 'LEO739' source-attribution token from every word's
metadata_json.sources array in the shipped DB.

Rationale: the Leoschule Lünen wordlist (`739Leo.csv`) carries no formal
license. The pipeline already drops it from future builds. This script
also strips the residual attribution token from the currently-shipped DB.

The 38 words whose ONLY source was LEO739 keep their entries but end up
with an empty `sources` array, which the app's source-filter treats as
"no source match" — they remain visible in unfiltered queries.

Reads / writes:
  - assets/grundwortschatz.db.gz (decompressed to /tmp/dbpatch/working.db)
"""

from __future__ import annotations

import gzip
import json
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"
WORK = Path("/tmp/dbpatch/working.db")
TOKEN = "LEO739"


def main() -> int:
    if not DB_GZ.exists():
        print(f"ERROR: shipped DB not found: {DB_GZ}", file=sys.stderr)
        return 1

    WORK.parent.mkdir(parents=True, exist_ok=True)
    if WORK.exists():
        WORK.unlink()
    print(f"Decompressing {DB_GZ} -> {WORK}")
    with gzip.open(DB_GZ, "rb") as fi, WORK.open("wb") as fo:
        fo.write(fi.read())

    con = sqlite3.connect(str(WORK))
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute(
        "SELECT id, metadata_json FROM words "
        "WHERE metadata_json LIKE ?",
        (f"%{TOKEN}%",),
    )
    rows = cur.fetchall()
    print(f"Found {len(rows)} candidate rows with substring '{TOKEN}'")

    update_cur = con.cursor()
    updated = 0
    became_empty = 0

    for r in rows:
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except json.JSONDecodeError:
            continue
        if not isinstance(meta, dict):
            continue
        srcs = meta.get("sources")
        if not isinstance(srcs, list) or TOKEN not in srcs:
            continue

        new_srcs = [s for s in srcs if s != TOKEN]
        meta["sources"] = new_srcs
        update_cur.execute(
            "UPDATE words SET metadata_json = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), r["id"]),
        )
        updated += 1
        if not new_srcs:
            became_empty += 1

    con.commit()

    cur.execute(
        "SELECT count(*) FROM words WHERE metadata_json LIKE ?",
        (f"%{TOKEN}%",),
    )
    remaining = cur.fetchone()[0]
    con.close()

    print(f"Stripped '{TOKEN}' from {updated} rows.")
    print(f"  Of those, {became_empty} rows now have an empty sources array.")
    print(f"  Rows still containing '{TOKEN}' substring: {remaining}")
    if remaining:
        print("WARNING: substring still present in some rows.", file=sys.stderr)
        return 2

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
