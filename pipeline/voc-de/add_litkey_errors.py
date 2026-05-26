"""Populate commonMistakes[] in the DE DB from the LiTKey corpus.

LiTKey (Literacy and Key Competencies) is a freely available CC-BY-SA 4.0
corpus of German primary-school children's writing errors (grades 2–4, 37k+
annotated error tokens). See: https://www.linguistics.rub.de/litkeycorpus/

For each DB lemma we attach the unique child misspellings found in LiTKey
to `metadata_json.commonMistakes` (array of strings) and add "LITKEY" to
`metadata_json.sources`.

The LiTKey-Tab.csv uses a tab-separated format. Relevant columns:
  orig        — child's spelling (possibly erroneous)
  target      — correct target form
  erroneous   — 1 if the token is an error, 0 if correct
  error_level — error category (PG/SL/MO/SN)
  grade       — school grade (2, 3, 4)
  chl_lemma   — childLex base form (may differ from target for inflected forms)

We only process rows where erroneous==1. For each (orig, target) pair we look
up the vocabulary entry via a three-pass inflection-aware index:
  1. word (headword, case-insensitive)
  2. lemma column
  3. wiktionaryInflections[].form_text values from metadata_json

Idempotent: running the script again will not add duplicates and will not
clobber existing LITKEY entries.

Usage:
  python add_litkey_errors.py [--db grundwortschatz.db] [--no-compress]
  python add_litkey_errors.py --download   # only download the CSV, then exit

The CSV is ~44 MB. Downloaded to ./sources/Litkey-Tab.csv on first run and
reused on subsequent runs (pass --redownload to force a fresh fetch).
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import shutil
import sqlite3
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

DEFAULT_DB = HERE / "grundwortschatz.db"
WORK_DB = Path("/tmp/dbpatch_litkey/working.db")
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"

CSV_URL = "https://www.linguistics.rub.de/litkeycorpus/corpus/Litkey-Tab.csv"
CSV_LOCAL = HERE / "sources" / "Litkey-Tab.csv"

SOURCE_TAG = "LITKEY"


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

def download_csv(force: bool = False) -> Path:
    CSV_LOCAL.parent.mkdir(parents=True, exist_ok=True)
    if CSV_LOCAL.exists() and not force:
        print(f"  [skip] {CSV_LOCAL.name} already present ({CSV_LOCAL.stat().st_size // 1024} KB)")
        return CSV_LOCAL
    print(f"Downloading {CSV_URL} …")
    tmp = CSV_LOCAL.with_suffix(".tmp")
    try:
        urllib.request.urlretrieve(CSV_URL, tmp)
        tmp.rename(CSV_LOCAL)
    except Exception as exc:
        if tmp.exists():
            tmp.unlink()
        raise RuntimeError(f"Download failed: {exc}") from exc
    print(f"  saved to {CSV_LOCAL} ({CSV_LOCAL.stat().st_size // 1024} KB)")
    return CSV_LOCAL


# ---------------------------------------------------------------------------
# Parse LiTKey CSV
# ---------------------------------------------------------------------------

def load_litkey_pairs(csv_path: Path) -> dict[str, set[str]]:
    """Return {target_lower: {orig_lower, …}} for rows where erroneous==1.

    Normalisation: both target and orig are lowercased; trailing whitespace
    stripped. Pairs where orig == target (sometimes present for cleaned-up
    near-matches) are dropped.
    """
    target_to_origs: dict[str, set[str]] = {}
    skipped = 0
    total = 0
    with csv_path.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            total += 1
            try:
                erroneous = int(row.get("erroneous", "0") or "0")
            except ValueError:
                skipped += 1
                continue
            if erroneous != 1:
                continue
            orig = (row.get("orig") or "").strip()
            target = (row.get("target") or "").strip()
            if not orig or not target:
                skipped += 1
                continue
            orig_l = orig.lower()
            target_l = target.lower()
            if orig_l == target_l:
                continue
            target_to_origs.setdefault(target_l, set()).add(orig_l)
    print(f"  parsed {total} rows → "
          f"{sum(len(v) for v in target_to_origs.values())} unique (orig, target) pairs "
          f"across {len(target_to_origs)} distinct targets; {skipped} rows skipped")
    return target_to_origs


# ---------------------------------------------------------------------------
# Build inflection-aware index from the DB
# ---------------------------------------------------------------------------

def build_index(rows: list[sqlite3.Row]) -> dict[str, int]:
    """lowercase_form → index into rows list.

    Three-pass priority:
      1. word column (exact headword)
      2. lemma column
      3. wiktionaryInflections[].form_text values in metadata_json
    """
    idx: dict[str, int] = {}

    # Pass 1: headword
    for i, r in enumerate(rows):
        w = (r["word"] or "").strip()
        if w:
            idx.setdefault(w.lower(), i)

    # Pass 2: lemma column
    for i, r in enumerate(rows):
        lm = (r["lemma"] or "").strip()
        if lm:
            idx.setdefault(lm.lower(), i)

    # Pass 3: Wiktionary inflections stored in metadata_json
    for i, r in enumerate(rows):
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except (json.JSONDecodeError, TypeError):
            meta = {}
        for infl in meta.get("wiktionaryInflections") or []:
            if isinstance(infl, dict):
                ft = (infl.get("form_text") or "").strip()
                if ft:
                    idx.setdefault(ft.lower(), i)

    return idx


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", default=str(DEFAULT_DB),
                    help="Source SQLite DB (default: grundwortschatz.db)")
    ap.add_argument("--download", action="store_true",
                    help="Download CSV only, then exit")
    ap.add_argument("--redownload", action="store_true",
                    help="Force re-download of Litkey-Tab.csv even if present")
    ap.add_argument("--no-compress", action="store_true",
                    help="Skip recompressing to assets/grundwortschatz.db.gz")
    args = ap.parse_args()

    # Download CSV
    csv_path = download_csv(force=args.redownload)
    if args.download:
        return 0

    # Parse
    print("Parsing LiTKey CSV …")
    target_to_origs = load_litkey_pairs(csv_path)

    # Prepare working copy of DB
    src_db = Path(args.db)
    if not src_db.exists():
        print(f"ERROR: DB not found: {src_db}", file=sys.stderr)
        return 1

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    print(f"Copying {src_db} → {WORK_DB}")
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute("SELECT id, word, lemma, metadata_json FROM words")
    rows = cur.fetchall()
    print(f"Loaded {len(rows)} DB entries")

    # Build index
    print("Building inflection-aware index …")
    idx = build_index(rows)
    print(f"  index has {len(idx)} keys")

    # Accumulate all origs per row index before writing — multiple target
    # forms can map to the same headword entry via the inflection index, so
    # we must merge them all before issuing a single UPDATE per row.
    row_to_origs: dict[int, set[str]] = {}
    skipped_no_target = 0

    for target_l, origs in target_to_origs.items():
        i = idx.get(target_l)
        if i is None:
            skipped_no_target += 1
            continue
        row_to_origs.setdefault(i, set()).update(origs)

    update_cur = con.cursor()
    updated = 0
    new_annotations = 0
    row_list = [dict(r) for r in rows]

    for i, new_origs_set in row_to_origs.items():
        r = row_list[i]
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except (json.JSONDecodeError, TypeError):
            meta = {}

        existing: set[str] = set()
        for cm in meta.get("commonMistakes") or []:
            if isinstance(cm, str):
                existing.add(cm.lower())

        truly_new = new_origs_set - existing
        if not truly_new:
            continue

        combined = sorted(existing | truly_new)
        meta["commonMistakes"] = combined

        sources = list(meta.get("sources") or [])
        if SOURCE_TAG not in sources:
            sources.append(SOURCE_TAG)
            meta["sources"] = sources

        update_cur.execute(
            "UPDATE words SET metadata_json = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), r["id"]),
        )
        new_annotations += len(truly_new)
        updated += 1

    con.commit()
    con.close()

    print()
    print(f"Updated {updated} entries with LiTKey misspellings.")
    print(f"  new misspelling annotations:  {new_annotations}")
    print(f"  targets not in vocab:         {skipped_no_target}")

    # Copy back to pipeline DB
    print(f"Copying {WORK_DB} → {src_db}")
    shutil.copy2(WORK_DB, src_db)

    # Recompress to assets/
    if not args.no_compress:
        if DB_GZ.exists():
            print(f"Compressing {src_db} → {DB_GZ}")
            with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
                shutil.copyfileobj(fi, fo)
            print(f"  {DB_GZ.stat().st_size // 1024} KB written")
        else:
            print(f"  [warn] {DB_GZ} not found — skipping asset compression", file=sys.stderr)

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
