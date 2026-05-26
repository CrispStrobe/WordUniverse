"""Add German first names to the DE DB from open Standesamt datasets.

Sources (all freely licensed):
  Berlin   — github.com/berlin/haeufige-vornamen-berlin   MIT
  Munich   — opendata.muenchen.de/dataset/vornamen-…      DL-DE-BY 2.0 (attribution)
  Düsseldorf — opendata.duesseldorf.de/dataset/vornamen   DL-DE-Zero 2.0
  Köln     — offenedaten-koeln.de/dataset/vornamen-…      DL-DE-Zero 2.0

For each city the most recent available year is fetched (cached locally under
sources/vornamen/).  Frequencies are summed across cities; only names with
combined frequency ≥ MIN_FREQ (default 5) are written.

Each entry gets:
  word / lemma     = canonical name (as written in the source)
  partOfSpeech     = "Eigenname"
  definitions      = ["männlicher Vorname"] / ["weiblicher Vorname"] / ["Vorname"]
  sources          = ["VORNAME_STANDESAMT"]
  vorname_freq     = total occurrences across all cities/years downloaded

Idempotent: names already in the DB (by word or lemma, case-insensitive) are
skipped.  Existing entries that already have definitions are also skipped so
we do not overwrite richer Wiktionary data.

Usage:
  python add_vornamen.py [--db grundwortschatz.db] [--min-freq N]
                         [--no-compress] [--dry-run] [--redownload]
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

DEFAULT_DB   = HERE / "grundwortschatz.db"
WORK_DB      = Path("/tmp/dbpatch_vornamen/working.db")
DB_GZ        = REPO / "assets" / "grundwortschatz.db.gz"
CACHE_DIR    = HERE / "sources" / "vornamen"

DEFAULT_MIN_FREQ = 5

# ---------------------------------------------------------------------------
# Source definitions
# ---------------------------------------------------------------------------

# Each source: (key, url, city, license, parser_fn_name)
# Parser functions are defined below; referenced by name for clarity.
SOURCES = [
    # Berlin – MIT – all_names.json aggregates all 12 districts
    {
        "key":     "berlin_2023",
        "url":     "https://raw.githubusercontent.com/berlin/haeufige-vornamen-berlin/main/data/2023/all_names.json",
        "city":    "Berlin",
        "license": "MIT",
        "format":  "berlin_json",
    },
    # Munich – DL-DE-BY 2.0 (attribution)
    {
        "key":     "muenchen_2024",
        "url":     "https://opendata.muenchen.de/dataset/99ad40ec-9d7b-4a2e-87eb-9bac783fb57a/resource/9f393a00-aa64-4733-8c8c-80eabc18f95a/download/vornamen_muenchen2024.csv",
        "city":    "München",
        "license": "DL-DE-BY-2.0",
        "format":  "simple_csv",   # vorname,anzahl,geschlecht
    },
    # Düsseldorf – DL-DE-Zero 2.0 – combined file (m+w)
    {
        "key":     "duesseldorf_2024",
        "url":     "https://opendata.duesseldorf.de/sites/default/files/Vornamenstatistik_2024_insgesamt.csv",
        "city":    "Düsseldorf",
        "license": "DL-DE-Zero-2.0",
        "format":  "duesseldorf_csv",
    },
    # Köln – DL-DE-Zero 2.0
    {
        "key":     "koeln_2019_2022",
        "url":     "http://www.offenedaten-koeln.de/sites/default/files/distribution/Gesamt_Vornamen_2019-2022_0.csv",
        "city":    "Köln",
        "license": "DL-DE-Zero-2.0",
        "format":  "koeln_csv",
    },
]


# ---------------------------------------------------------------------------
# Download helper
# ---------------------------------------------------------------------------

def _fetch(url: str, dest: Path, force: bool) -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    if dest.exists() and not force:
        print(f"  [cache] {dest.name}")
        return dest
    print(f"  Downloading {dest.name} …")
    tmp = dest.with_suffix(".tmp")
    try:
        urllib.request.urlretrieve(url, tmp)
    except Exception:
        try:
            subprocess.run(["curl", "-fsSL", url, "-o", str(tmp)], check=True)
        except subprocess.CalledProcessError as e:
            if tmp.exists():
                tmp.unlink()
            raise RuntimeError(f"Download failed: {e}") from e
    tmp.rename(dest)
    return dest


# ---------------------------------------------------------------------------
# Parsers  →  yield (name, gender, count)
#   gender: "m" | "w" | None
# ---------------------------------------------------------------------------

def _sniff_sep(line: str) -> str:
    return ";" if line.count(";") > line.count(",") else ","


def parse_berlin_json(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    totals: dict[tuple[str, str], int] = defaultdict(int)
    for district, names in (data.get("common_names") or {}).items():
        for name, genders in names.items():
            for gender, positions in genders.items():
                # position "1" = first name; also count "2" (middle name)
                for pos, count in positions.items():
                    try:
                        totals[(name, gender)] += int(count)
                    except (ValueError, TypeError):
                        pass
    for (name, gender), count in totals.items():
        if re.match(r"^[A-ZÄÖÜ][a-zA-ZäöüÄÖÜß\-]+$", name):
            yield name, gender if gender in ("m", "w") else None, count


def parse_simple_csv(path: Path):
    """Munich format: vorname,anzahl,geschlecht  (comma-sep, header row)"""
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    if not lines:
        return
    sep = _sniff_sep(lines[0])
    for line in lines[1:]:
        parts = line.split(sep)
        if len(parts) < 2:
            continue
        name = parts[0].strip().strip('"')
        try:
            count = int(parts[1].strip())
        except ValueError:
            continue
        gender = parts[2].strip().lower() if len(parts) >= 3 else None
        gender = "m" if gender in ("m", "männlich", "male") else \
                 "w" if gender in ("w", "weiblich", "female") else None
        if re.match(r"^[A-ZÄÖÜ][a-zA-ZäöüÄÖÜß\-]+$", name):
            yield name, gender, count


def parse_duesseldorf_csv(path: Path):
    """Düsseldorf: semicolon-separated, columns may vary by year."""
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    if not lines:
        return
    sep = _sniff_sep(lines[0])
    header = [h.strip().lower().strip('"') for h in lines[0].split(sep)]
    # Try to find column indices flexibly
    name_col   = next((i for i, h in enumerate(header) if "name" in h or "vorname" in h), 0)
    count_col  = next((i for i, h in enumerate(header) if "anzahl" in h or "count" in h or "häuf" in h), 1)
    gender_col = next((i for i, h in enumerate(header) if "geschl" in h or "gender" in h or "sex" in h), -1)
    for line in lines[1:]:
        parts = line.split(sep)
        if len(parts) <= count_col:
            continue
        name = parts[name_col].strip().strip('"')
        try:
            count_str = parts[count_col].strip().replace(".", "").replace(",", "")
            count = int(count_str)
        except ValueError:
            continue
        gender = None
        if gender_col >= 0 and len(parts) > gender_col:
            g = parts[gender_col].strip().lower()
            gender = "m" if g in ("m", "männlich") else "w" if g in ("w", "weiblich") else None
        if re.match(r"^[A-ZÄÖÜ][a-zA-ZäöüÄÖÜß\-]+$", name):
            yield name, gender, count


def parse_koeln_csv(path: Path):
    """Köln: jahr;vorname;anzahl;geschlecht;position (semicolon)."""
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    if not lines:
        return
    sep = _sniff_sep(lines[0])
    header = [h.strip().lower().strip('"') for h in lines[0].split(sep)]
    try:
        name_col   = header.index("vorname")
        count_col  = header.index("anzahl")
        gender_col = header.index("geschlecht")
    except ValueError:
        # Fall back to positional guessing
        yield from parse_simple_csv(path)
        return
    for line in lines[1:]:
        parts = line.split(sep)
        if len(parts) <= max(name_col, count_col):
            continue
        name = parts[name_col].strip().strip('"')
        try:
            count = int(parts[count_col].strip())
        except ValueError:
            continue
        g = parts[gender_col].strip().lower() if len(parts) > gender_col else ""
        gender = "m" if g in ("m", "männlich") else "w" if g in ("w", "weiblich") else None
        if re.match(r"^[A-ZÄÖÜ][a-zA-ZäöüÄÖÜß\-]+$", name):
            yield name, gender, count


PARSERS = {
    "berlin_json":    parse_berlin_json,
    "simple_csv":     parse_simple_csv,
    "duesseldorf_csv": parse_duesseldorf_csv,
    "koeln_csv":      parse_koeln_csv,
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",          default=str(DEFAULT_DB))
    ap.add_argument("--min-freq",    type=int, default=DEFAULT_MIN_FREQ,
                    help=f"Min combined frequency to include (default {DEFAULT_MIN_FREQ})")
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--dry-run",     action="store_true")
    ap.add_argument("--redownload",  action="store_true")
    args = ap.parse_args()

    # ---- Download & parse all sources ------------------------------------ #
    freq_m:  defaultdict[str, int] = defaultdict(int)   # name → male count
    freq_w:  defaultdict[str, int] = defaultdict(int)   # name → female count

    for src in SOURCES:
        dest = CACHE_DIR / f"{src['key']}.{'json' if 'json' in src['format'] else 'csv'}"
        try:
            path = _fetch(src["url"], dest, force=args.redownload)
        except RuntimeError as e:
            print(f"  [warn] {src['city']}: {e}", file=sys.stderr)
            continue

        parser = PARSERS[src["format"]]
        n = 0
        for name, gender, count in parser(path):
            if gender == "m":
                freq_m[name] += count
            elif gender == "w":
                freq_w[name] += count
            else:
                # Unknown gender: add to both so name isn't lost
                freq_m[name] += count // 2 or 1
                freq_w[name] += count // 2 or 1
            n += 1
        print(f"  {src['city']:12s} {n:6d} name-rows parsed")

    # ---- Build unified name table ---------------------------------------- #
    all_names: set[str] = set(freq_m) | set(freq_w)
    print(f"\nUnique name forms across all sources: {len(all_names)}")

    # Compute combined totals and assign ranks (rank 1 = most frequent)
    all_totals = {
        name: freq_m.get(name, 0) + freq_w.get(name, 0)
        for name in all_names
        if freq_m.get(name, 0) + freq_w.get(name, 0) >= args.min_freq
    }
    ranked_names = sorted(all_totals, key=lambda n: all_totals[n], reverse=True)
    vorname_rank: dict[str, int] = {name: i + 1 for i, name in enumerate(ranked_names)}

    # ---- Load DB ---------------------------------------------------------- #
    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    db_words  = {r[0].lower() for r in con.execute("SELECT word FROM words")}
    db_lemmas = {(r[0] or "").lower() for r in con.execute("SELECT lemma FROM words") if r[0]}
    in_db = db_words | db_lemmas

    # ---- Determine entries to add ---------------------------------------- #
    next_id = (con.execute("SELECT MAX(id) FROM words").fetchone()[0] or 0) + 1
    new_rows: list[tuple] = []
    skipped_freq = skipped_present = 0

    for name in sorted(all_names):
        total = freq_m.get(name, 0) + freq_w.get(name, 0)
        if total < args.min_freq:
            skipped_freq += 1
            continue
        if name.lower() in in_db:
            skipped_present += 1
            continue

        m = freq_m.get(name, 0)
        w = freq_w.get(name, 0)
        if m > 0 and w == 0:
            gender_def = "männlicher Vorname"
            gender_tag = "m"
        elif w > 0 and m == 0:
            gender_def = "weiblicher Vorname"
            gender_tag = "w"
        else:
            gender_def = "Vorname"
            gender_tag = None

        enrichment = {
            "partOfSpeech": "Eigenname",
            "definitions":  [gender_def],
        }
        if gender_tag:
            enrichment["gender"] = gender_tag

        metadata = {
            "sources":      ["VORNAME_STANDESAMT"],
            "vorname_freq": total,
            "vorname_rang": vorname_rank[name],
        }

        new_rows.append((
            next_id,
            name,
            name,
            None,   # frequency_json
            json.dumps(enrichment, ensure_ascii=False),
            json.dumps(metadata,   ensure_ascii=False),
        ))
        in_db.add(name.lower())
        next_id += 1

    print(f"Names below min_freq={args.min_freq}: {skipped_freq}")
    print(f"Already in DB:        {skipped_present}")
    print(f"New entries to add:   {len(new_rows)}")
    if new_rows:
        print(f"  Sample: {[r[1] for r in new_rows[:20]]}")

    if not new_rows:
        print("Nothing to add.")
        con.close()
        return 0

    # ---- Write ------------------------------------------------------------ #
    if not args.dry_run:
        con.executemany(
            "INSERT INTO words "
            "(id, word, lemma, frequency_json, enrichment_json, metadata_json) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            new_rows,
        )
        con.commit()
        after = con.execute("SELECT COUNT(*) FROM words").fetchone()[0]
        print(f"DB entries after insert: {after}")

    con.close()

    if not args.dry_run:
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
