"""Tag EN DB entries with CEFR level from CEFR-J vocabulary profile.

Source: CEFR-J Vocabulary Profile v1.5 (Tono & Negishi, Tokyo University of Foreign Studies)
  https://github.com/openlanguageprofiles/olp-en-cefrj
  License: CC-BY-SA 4.0 — commercial use allowed, share-alike required.

Adds to metadata_json:
  {"cefr_level": "A1", "tags": [..., "source:cefr_j"], ...}

Usage:
  python add_cefr_en.py [--db grundwortschatz_en.db] [--no-compress] [--dry-run]
"""

from __future__ import annotations

import argparse
import csv
import gzip
import io
import json
import shutil
import sqlite3
import ssl
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DEFAULT_DB = HERE / "grundwortschatz_en.db"
WORK_DB    = Path("/tmp/dbpatch_cefr_en/working.db")
DB_GZ      = REPO / "assets" / "grundwortschatz_en.db.gz"
CACHE_DIR  = HERE / "sources"
CACHE_FILE = CACHE_DIR / "cefrj-vocabulary-profile-1.5.csv"

CEFRJ_URL = (
    "https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj"
    "/master/cefrj-vocabulary-profile-1.5.csv"
)

CEFR_ORDER = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}


def _ssl_ctx() -> ssl.SSLContext:
    """Return an SSL context, falling back to certifi or unverified on macOS."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        pass
    ctx = ssl.create_default_context()
    try:
        ctx.load_default_certs()
    except Exception:
        pass
    return ctx


def download_cefrj() -> bytes:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    if CACHE_FILE.exists():
        print(f"Using cached CEFR-J CSV: {CACHE_FILE}")
        return CACHE_FILE.read_bytes()
    print(f"Downloading CEFR-J CSV from {CEFRJ_URL} …")
    req = urllib.request.Request(CEFRJ_URL, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=30, context=_ssl_ctx()) as r:
            data = r.read()
    except ssl.SSLCertVerificationError:
        # macOS Python without certificates installed — skip verification
        ctx = ssl._create_unverified_context()
        with urllib.request.urlopen(req, timeout=30, context=ctx) as r:
            data = r.read()
    CACHE_FILE.write_bytes(data)
    print(f"  Saved {len(data)//1024} KB → {CACHE_FILE}")
    return data


def load_cefrj(data: bytes) -> dict[str, str]:
    """Return {headword_lower: cefr_level} keeping the lowest level per word."""
    text = data.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))
    result: dict[str, str] = {}
    for row in reader:
        headword = (row.get("headword") or row.get("word") or "").strip()
        level = (row.get("CEFR") or row.get("cefr") or row.get("level") or "").strip().upper()
        if not headword or not level:
            continue
        # Handle slash-variants like "a.m./A.M./am/AM"
        for v in headword.split("/"):
            v_lower = v.strip().lower()
            if not v_lower:
                continue
            existing = result.get(v_lower)
            if existing is None or CEFR_ORDER.get(level, 99) < CEFR_ORDER.get(existing, 99):
                result[v_lower] = level
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",          default=str(DEFAULT_DB))
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--dry-run",     action="store_true")
    ap.add_argument("--overwrite",   action="store_true",
                    help="Re-tag even if cefr_level already set in metadata_json")
    args = ap.parse_args()

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    cefrj_data = download_cefrj()
    cefrj = load_cefrj(cefrj_data)
    print(f"CEFR-J entries loaded: {len(cefrj)}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row

    rows = con.execute(
        "SELECT id, word, lemma, metadata_json FROM words"
    ).fetchall()
    rows = [dict(r) for r in rows]
    print(f"Loaded {len(rows)} DB entries")

    updated = 0
    skipped = 0
    not_found = 0
    level_counts: dict[str, int] = {}

    for r in rows:
        meta = json.loads(r["metadata_json"] or "{}")

        if not args.overwrite and meta.get("cefr_level"):
            skipped += 1
            continue

        word  = (r.get("word")  or "").strip().lower()
        lemma = (r.get("lemma") or "").strip().lower()

        level = cefrj.get(word) or (cefrj.get(lemma) if lemma and lemma != word else None)

        if not level:
            not_found += 1
            continue

        meta["cefr_level"] = level
        level_counts[level] = level_counts.get(level, 0) + 1

        tags: list[str] = meta.get("tags") or []
        if "source:cefr_j" not in tags:
            tags = list(tags) + ["source:cefr_j"]
            meta["tags"] = tags

        if not args.dry_run:
            con.execute(
                "UPDATE words SET metadata_json = ? WHERE id = ?",
                (json.dumps(meta, ensure_ascii=False), r["id"]),
            )
        updated += 1

    if not args.dry_run:
        con.commit()
    con.close()

    print(f"Tagged:    {updated}")
    print(f"Skipped (already tagged): {skipped}")
    print(f"Not found in CEFR-J: {not_found}")
    print("Level distribution:")
    for lvl in ["A1", "A2", "B1", "B2", "C1", "C2"]:
        c = level_counts.get(lvl, 0)
        if c:
            print(f"  {lvl}: {c}")

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
