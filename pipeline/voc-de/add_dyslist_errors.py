"""Populate commonMistakes[] in the DE DB from the DysList German dyslexia corpus.

DysList (Rauschii/DysListGerman, Zenodo DOI: 10.5281/zenodo.809801) is a
publicly available corpus of ~1,020 annotated spelling errors produced by
German children with diagnosed dyslexia (ages 6–15). License: MIT.

For each (Error_Word, Correct_Word) pair in the corpus we look up
Correct_Word in the vocabulary and attach Error_Word to
metadata_json.commonMistakes with source tag DYSLIST.

This is complementary to LiTKey (typical children) — dyslexic error patterns
are distinct and surface different confusables (mirror-letter reversals,
phonetic substitutions specific to dyslexia).

Error_Type values in the corpus:
  omission       — letter dropped
  addition       — extra letter inserted
  substitution   — letter replaced
  multierror     — multiple simultaneous changes
  capital_letter — wrong capitalisation of first letter

All error types are included: capital_letter errors are relevant for German
since nouns must be capitalised and this is a documented dyslexic difficulty.

Idempotent: re-running will not duplicate DYSLIST entries.

Usage:
  python add_dyslist_errors.py [--db grundwortschatz.db] [--no-compress]
  python add_dyslist_errors.py --download   # download only, then exit
  python add_dyslist_errors.py --redownload # force re-download
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import shutil
import sqlite3
import subprocess
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

DEFAULT_DB = HERE / "grundwortschatz.db"
WORK_DB = Path("/tmp/dbpatch_dyslist/working.db")
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"

CSV_URL = ("https://raw.githubusercontent.com/Rauschii/DysListGerman"
           "/master/German_Annotation_V028.csv")
CSV_LOCAL = HERE / "sources" / "DysList_German_Annotation.csv"

SOURCE_TAG = "DYSLIST"


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

def download_csv(force: bool = False) -> Path:
    CSV_LOCAL.parent.mkdir(parents=True, exist_ok=True)
    if CSV_LOCAL.exists() and not force:
        print(f"  [skip] {CSV_LOCAL.name} already present "
              f"({CSV_LOCAL.stat().st_size // 1024} KB)")
        return CSV_LOCAL
    print(f"Downloading {CSV_URL} …")
    tmp = CSV_LOCAL.with_suffix(".tmp")
    try:
        urllib.request.urlretrieve(CSV_URL, tmp)
    except Exception:
        # macOS Python 3.11 often lacks system CA bundle; fall back to curl
        try:
            subprocess.run(
                ["curl", "-fsSL", CSV_URL, "-o", str(tmp)],
                check=True,
            )
        except subprocess.CalledProcessError as exc:
            if tmp.exists():
                tmp.unlink()
            raise RuntimeError(f"Download failed via curl: {exc}") from exc
    tmp.rename(CSV_LOCAL)
    print(f"  saved to {CSV_LOCAL} ({CSV_LOCAL.stat().st_size // 1024} KB)")
    return CSV_LOCAL


# ---------------------------------------------------------------------------
# Parse DysList CSV
# ---------------------------------------------------------------------------

def load_dyslist_pairs(csv_path: Path) -> dict[str, set[str]]:
    """Return {correct_lower: {error_lower, …}}.

    Both forms are lowercased for index lookup. Pairs where error == correct
    (after lowercasing) are dropped. The corpus uses semicolon as delimiter.
    """
    target_to_errors: dict[str, set[str]] = {}
    skipped = 0
    total = 0

    with csv_path.open(encoding="utf-8", newline="", errors="replace") as fh:
        reader = csv.DictReader(fh, delimiter=";")
        for row in reader:
            total += 1
            correct = (row.get("Correct_Word") or "").strip()
            error = (row.get("Error_Word") or "").strip()

            if not correct or not error or correct == "-" or error == "-":
                skipped += 1
                continue

            correct_l = correct.lower()
            error_l = error.lower()
            if correct_l == error_l:
                skipped += 1
                continue

            target_to_errors.setdefault(correct_l, set()).add(error_l)

    unique_pairs = sum(len(v) for v in target_to_errors.values())
    print(f"  parsed {total} rows → {unique_pairs} unique (error, correct) pairs "
          f"across {len(target_to_errors)} distinct correct forms; {skipped} rows skipped")
    return target_to_errors


# ---------------------------------------------------------------------------
# Inflection-aware index
# ---------------------------------------------------------------------------

def build_index(rows: list[sqlite3.Row]) -> dict[str, int]:
    idx: dict[str, int] = {}
    for i, r in enumerate(rows):
        w = (r["word"] or "").strip()
        if w:
            idx.setdefault(w.lower(), i)
    for i, r in enumerate(rows):
        lm = (r["lemma"] or "").strip()
        if lm:
            idx.setdefault(lm.lower(), i)
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
    ap.add_argument("--db", default=str(DEFAULT_DB))
    ap.add_argument("--download", action="store_true",
                    help="Download CSV only, then exit")
    ap.add_argument("--redownload", action="store_true",
                    help="Force re-download even if CSV already present")
    ap.add_argument("--no-compress", action="store_true")
    args = ap.parse_args()

    csv_path = download_csv(force=args.redownload)
    if args.download:
        return 0

    print("Parsing DysList CSV …")
    target_to_errors = load_dyslist_pairs(csv_path)

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
    rows = con.execute("SELECT id, word, lemma, metadata_json FROM words").fetchall()
    print(f"Loaded {len(rows)} DB entries")

    idx = build_index(rows)
    print(f"  inflection index has {len(idx)} keys")

    # Accumulate all errors per row index before writing
    row_to_errors: dict[int, set[str]] = {}
    skipped_no_target = 0
    for correct_l, errors in target_to_errors.items():
        i = idx.get(correct_l)
        if i is None:
            skipped_no_target += 1
            continue
        row_to_errors.setdefault(i, set()).update(errors)

    updated = 0
    new_annotations = 0
    row_list = [dict(r) for r in rows]

    for i, new_errors in row_to_errors.items():
        r = row_list[i]
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except (json.JSONDecodeError, TypeError):
            meta = {}

        existing: set[str] = set()
        for cm in meta.get("commonMistakes") or []:
            if isinstance(cm, str):
                existing.add(cm.lower())

        truly_new = new_errors - existing
        if not truly_new:
            continue

        meta["commonMistakes"] = sorted(existing | truly_new)

        sources = list(meta.get("sources") or [])
        if SOURCE_TAG not in sources:
            sources.append(SOURCE_TAG)
            meta["sources"] = sources

        con.execute(
            "UPDATE words SET metadata_json = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), r["id"]),
        )
        new_annotations += len(truly_new)
        updated += 1

    con.commit()
    con.close()

    print()
    print(f"Updated {updated} entries with DysList errors.")
    print(f"  new misspelling annotations: {new_annotations}")
    print(f"  correct forms not in vocab:  {skipped_no_target}")

    print(f"Copying {WORK_DB} → {src_db}")
    shutil.copy2(WORK_DB, src_db)

    if not args.no_compress:
        if DB_GZ.exists():
            print(f"Compressing {src_db} → {DB_GZ}")
            with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
                shutil.copyfileobj(fi, fo)
            print(f"  {DB_GZ.stat().st_size // 1024} KB written")
        else:
            print(f"  [warn] {DB_GZ} not found", file=sys.stderr)

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
