"""Add a `BERLIN` source-attribution token to every DB word that appears
in the Berliner Grundwortschatz (LISUM 2024, CC-BY-SA 4.0).

Source PDF:
  https://www.berlin.de/sen/bildung/schule/bildungswege/grundschule/berliner-grundwortschatz.pdf

Publisher: Landesinstitut für Schule und Medien Berlin-Brandenburg (LISUM),
           Ludwigsfelde 2024.
License:   Creative Commons CC BY-SA 4.0
           https://creativecommons.org/licenses/by-sa/4.0/legalcode.de

Sections extracted:
  - Alphabetische Ordnung der Häufigkeitswörter (~100 function words)
  - Grundwortschatz für die Jahrgangsstufen 1 und 2
  - Grundwortschatz für die Jahrgangsstufen 3 und 4

Pre-conditions:
  - /tmp/bl_audit/be.txt must already exist (pdftotext -layout of the PDF).
  - assets/grundwortschatz.db.gz must be the current shipped DB.

Outputs:
  - assets/grundwortschatz.db.gz (in-place re-compressed)
  - pipeline/voc-de/sources/berlin_grundwortschatz.txt (extracted lemma list,
    for transparency and future re-runs)
"""

from __future__ import annotations

import gzip
import json
import re
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"
WORK = Path("/tmp/dbpatch/working.db")
BE_TXT = Path("/tmp/bl_audit/be.txt")
OUT_LIST = REPO / "pipeline" / "voc-de" / "sources" / "berlin_grundwortschatz.txt"

TOKEN = "BERLIN"

ARTICLES = {"der", "die", "das"}

# Lines that span the wordlist sections in the extracted text.
# Determined empirically from `be.txt` (LISUM 2024 PDF, pdftotext -layout).
# section header → (start_line, end_line)  (inclusive, 1-based)
SECTIONS = [
    ("Häufigkeitswörter",                     849, 887),
    ("Grundwortschatz Jahrgangsstufen 1 + 2", 889, 1067),
    ("Grundwortschatz Jahrgangsstufen 3 + 4", 1068, 1264),
]


def parse_entry(line: str) -> str | None:
    """Parse a single wordlist line into a lemma.

    Handles:
      - "der Apfel (Äpfel)"          → "Apfel"
      - "aufwachen (wacht auf, …)"   → "aufwachen"
      - "Zeit, die"                  → "Zeit"
      - "in (ins)"                   → "in"
      - "aber"                       → "aber"

    Returns None if the line is a section header, page number, or
    column letter (A, B, C, …).
    """
    s = line.strip()
    if not s:
        return None
    # Drop trailing parenthetical inflections.
    s = re.sub(r"\s*\([^)]*\)\s*$", "", s).strip()
    if not s:
        return None
    # Drop trailing ", die/der/das".
    s = re.sub(r",\s*(der|die|das)\s*$", "", s).strip()
    # Skip single-letter section markers (A, B, C, …).
    if len(s) == 1 and s.isalpha():
        return None
    # Skip lines that are obviously page-footer junk.
    if s.startswith("Grundwortschatz für") or s.startswith("Planungshilfe"):
        return None
    if "Jahrgangsstufen" in s or "Häufigkeitswörter" in s:
        return None
    if re.fullmatch(r"\d+", s):
        return None
    # Split off leading article.
    parts = s.split()
    if parts and parts[0].lower() in ARTICLES:
        parts = parts[1:]
    if not parts:
        return None
    lemma = " ".join(parts).strip()
    # Sanity bound — single-token lemmas are typical; if multiword
    # something is off, keep first content token only.
    if len(parts) > 1:
        # likely a stray "in (ins)" type case where parens got stripped
        # already — keep parts[0].
        lemma = parts[0]
    return lemma if lemma else None


def extract_lemmas(text_path: Path) -> list[str]:
    if not text_path.exists():
        raise SystemExit(f"Berlin extract not found: {text_path}")
    lines = text_path.read_text(encoding="utf-8").splitlines()
    lemmas: list[str] = []
    seen: set[str] = set()
    for label, lo, hi in SECTIONS:
        for ln in lines[lo - 1 : hi]:
            # Some lines hold multiple columns separated by 2+ spaces
            # in the layout-preserved text — split on 2+ spaces.
            for cell in re.split(r"\s{2,}", ln):
                lemma = parse_entry(cell)
                if not lemma:
                    continue
                key = lemma.lower()
                if key in seen:
                    continue
                seen.add(key)
                lemmas.append(lemma)
    return lemmas


def main() -> int:
    lemmas = extract_lemmas(BE_TXT)
    print(f"Extracted {len(lemmas)} unique Berlin Grundwortschatz lemmas")
    OUT_LIST.parent.mkdir(parents=True, exist_ok=True)
    OUT_LIST.write_text("\n".join(lemmas) + "\n", encoding="utf-8")
    print(f"Wrote lemma list -> {OUT_LIST}")

    if not DB_GZ.exists():
        print(f"ERROR: shipped DB not found: {DB_GZ}", file=sys.stderr)
        return 1
    WORK.parent.mkdir(parents=True, exist_ok=True)
    if WORK.exists():
        WORK.unlink()
    print(f"Decompressing {DB_GZ} -> {WORK}")
    with gzip.open(DB_GZ, "rb") as fi, WORK.open("wb") as fo:
        fo.write(fi.read())

    lemma_set = {l.lower() for l in lemmas}

    con = sqlite3.connect(str(WORK))
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute("SELECT id, word, lemma, metadata_json FROM words")
    rows = cur.fetchall()

    update_cur = con.cursor()
    matched = 0
    already_had = 0
    became_first_source = 0
    miss_in_db = 0

    db_lemmas: set[str] = set()
    for r in rows:
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except json.JSONDecodeError:
            meta = {}
        if not isinstance(meta, dict):
            meta = {}

        word_key = (r["word"] or "").strip().lower()
        lemma_key = (r["lemma"] or "").strip().lower()
        for k in (word_key, lemma_key):
            if k:
                db_lemmas.add(k)
        if not (word_key in lemma_set or lemma_key in lemma_set):
            continue

        srcs = meta.get("sources")
        if not isinstance(srcs, list):
            srcs = []
        if TOKEN in srcs:
            already_had += 1
            continue
        if not srcs:
            became_first_source += 1
        srcs.append(TOKEN)
        meta["sources"] = srcs
        update_cur.execute(
            "UPDATE words SET metadata_json = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), r["id"]),
        )
        matched += 1

    con.commit()
    con.close()

    miss_in_db = sum(1 for l in lemma_set if l not in db_lemmas)
    print(f"Tagged {matched} words with '{TOKEN}'")
    print(f"  Already had token (no-op): {already_had}")
    print(f"  Became first source-tag for word: {became_first_source}")
    print(f"  Berlin lemmas not present in DB at all: {miss_in_db}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
