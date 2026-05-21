"""Add childLex age-graded lexical norms to the shipped DB.

childLex provides lexical norms for German computed from a 10M-token
corpus of children's literature, broken down into three age groups:
  Age 1: ages 6–8  → Klasse 1–2
  Age 2: ages 9–10 → Klasse 3–4
  Age 3: ages 11–12 → Klasse 5–6

For each DB lemma we add the normalized frequency (occurrences per
million) per age group to `frequency_json.childlex`:
  {
    "age1_freq_norm": 583.334,   # Kl 1-2 freq
    "age2_freq_norm": 612.110,   # Kl 3-4 freq
    "age3_freq_norm": 678.450    # Kl 5-6 freq
  }

This is the algorithmic basis for grade-band estimation: a word that
appears frequently in Age 1 texts is appropriate for early grades; a
word only appearing in Age 3 is more appropriate for Klasse 5-6.

Source: childLex 0.17.01, Schroeder, Würzner, Heister, Geyken & Kliegl
        (2015), Behavior Research Methods. Available on OSF:
        https://osf.io/tqgjs

License: **GNU GPL-3.0** per the OSF project metadata. Integrating
childLex cascades the shipped DB's license CC-BY-SA-4.0 → GPL-3.0
(one-way compatible per the Creative Commons v4-compatible decision).
App code stays under its own license.

Pre-conditions:
  - /tmp/childlex/Age{1,2,3}_utf8.dat must exist (iconv Latin-1 → UTF-8
    of the OSF .dat files).

File format: TSV, 63 columns. Key columns for us:
  - col 60 (1-based): lemma  (quoted string)
  - col 63 (1-based): lemma.freq.norm  (float, occurrences per million,
                                          or "NA")
  - col 3 (1-based):  pos    (Stuttgart-Tübingen tagset)

All type rows for the same lemma share the same lemma.freq.norm, so we
take any one row per (lemma, pos) pair.
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
CHILDLEX_DIR = Path("/tmp/childlex")

AGE_FILES = {
    "age1": CHILDLEX_DIR / "Age1_utf8.dat",
    "age2": CHILDLEX_DIR / "Age2_utf8.dat",
    "age3": CHILDLEX_DIR / "Age3_utf8.dat",
}

LEMMA_COL_IDX = 59  # 0-based: column 60 in 1-based
FREQ_NORM_COL_IDX = 62
POS_COL_IDX = 2


def parse_quoted(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s.startswith('"') and s.endswith('"'):
        return s[1:-1]
    return s


def parse_float_or_none(s: str) -> float | None:
    s = s.strip().strip('"')
    if not s or s == "NA":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def load_age(path: Path) -> dict[str, float]:
    """Return {lemma_lowercased: lemma.freq.norm}.

    A lemma may appear in multiple type rows; all share the same
    lemma.freq.norm so we just take the first numeric value we see.
    """
    out: dict[str, float] = {}
    with path.open(encoding="utf-8", newline="") as f:
        header = f.readline()  # skip header
        for line in f:
            cols = line.rstrip("\r\n").split("\t")
            if len(cols) <= FREQ_NORM_COL_IDX:
                continue
            lemma = parse_quoted(cols[LEMMA_COL_IDX]).strip()
            if not lemma:
                continue
            freq = parse_float_or_none(cols[FREQ_NORM_COL_IDX])
            if freq is None:
                continue
            key = lemma.lower()
            # Keep the FIRST numeric value seen — they all match per the
            # paper.
            out.setdefault(key, freq)
    return out


def main() -> int:
    for age, path in AGE_FILES.items():
        if not path.exists():
            print(f"ERROR: missing {path}", file=sys.stderr)
            return 1
    if not DB_GZ.exists():
        print(f"ERROR: shipped DB not found: {DB_GZ}", file=sys.stderr)
        return 1

    print("Loading childLex age tables …")
    indices: dict[str, dict[str, float]] = {}
    for age, path in AGE_FILES.items():
        idx = load_age(path)
        indices[age] = idx
        print(f"  {age}: {len(idx)} unique lemmas")

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
    matched_count = 0
    age_match = {"age1": 0, "age2": 0, "age3": 0}
    only_age3 = 0  # word only present in Age 3 (oldest grade band) — signals Kl 5-6 word
    only_age1 = 0  # word only present in Age 1 — early-grade specific
    db_lemmas: set[str] = set()

    for r in rows:
        try:
            freq = json.loads(r["frequency_json"]) if r["frequency_json"] else {}
        except json.JSONDecodeError:
            freq = {}
        if not isinstance(freq, dict):
            freq = {}

        word_key = (r["word"] or "").strip().lower()
        lemma_key = (r["lemma"] or "").strip().lower()
        for k in (word_key, lemma_key):
            if k:
                db_lemmas.add(k)

        childlex_entry: dict[str, float] = {}
        for age, idx in indices.items():
            val = idx.get(word_key) or idx.get(lemma_key)
            if val is not None:
                childlex_entry[f"{age}_freq_norm"] = val
                age_match[age] += 1

        if not childlex_entry:
            continue

        ages_present = [a for a in ("age1", "age2", "age3")
                        if f"{a}_freq_norm" in childlex_entry]
        if ages_present == ["age3"]:
            only_age3 += 1
        elif ages_present == ["age1"]:
            only_age1 += 1

        freq["childlex"] = childlex_entry
        update_cur.execute(
            "UPDATE words SET frequency_json = ? WHERE id = ?",
            (json.dumps(freq, ensure_ascii=False), r["id"]),
        )
        matched_count += 1

    con.commit()
    con.close()

    print(f"Tagged {matched_count} words with childLex data")
    for age, n in age_match.items():
        print(f"  matched in {age}: {n}")
    print(f"  appears ONLY in age3 (Kl 5-6 specific):  {only_age3}")
    print(f"  appears ONLY in age1 (early-grade specific): {only_age1}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
