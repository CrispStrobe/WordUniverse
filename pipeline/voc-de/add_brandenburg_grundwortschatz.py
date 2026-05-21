"""Add a `BRANDENBURG` source-attribution token to every DB word that
appears in the Brandenburger Grundwortschatz (LISUM 2024, CC-BY-SA 4.0).

Source PDF: Grundwortschatz für die Grundschule in Brandenburg
            (LISUM, Ludwigsfelde 2024, gültig ab 1. August 2024)
  https://bildungsserver.berlin-brandenburg.de/fileadmin/bbb/unterricht/faecher/sprachen/deutsch/Schulinterne_Fachplaene_und_Planungshilfen/Grundwortschatz_Planungshilfe_Rechtschreiben_2024-08-09.pdf

License: explicit Creative Commons CC BY-SA 4.0
  "Soweit nicht abweichend gekennzeichnet zur Nachnutzung freigegeben
   unter der Creative Commons Lizenz CC BY-SA 4.0"

Brandenburg 2024 uses the same publisher (LISUM Berlin-Brandenburg),
same author team, and same Impressum format as the Berlin 2024 list.
The wordlist sections mirror Berlin's structure exactly:
  - Alphabetische Ordnung der Häufigkeitswörter
  - Grundwortschatz für die Jahrgangsstufen 1 und 2
  - Grundwortschatz für die Jahrgangsstufen 3 und 4

Pre-conditions:
  - /tmp/bl_audit/bb2024.txt must exist (pdftotext -layout of bb2024.pdf).

Outputs:
  - assets/grundwortschatz.db.gz (in-place re-compressed)
  - pipeline/voc-de/sources/brandenburg_grundwortschatz.txt
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
BB_TXT = Path("/tmp/bl_audit/bb2024.txt")
OUT_LIST = REPO / "pipeline" / "voc-de" / "sources" / "brandenburg_grundwortschatz.txt"

TOKEN = "BRANDENBURG"

ARTICLES = {"der", "die", "das"}

# Section line ranges determined empirically from bb2024.txt.
SECTIONS = [
    ("Häufigkeitswörter",                     839, 878),
    ("Grundwortschatz Jahrgangsstufen 1 + 2", 879, 1053),
    ("Grundwortschatz Jahrgangsstufen 3 + 4", 1054, 1248),
]


def parse_entry(line: str) -> str | None:
    s = line.strip()
    if not s:
        return None
    s = re.sub(r"\s*\([^)]*\)\s*$", "", s).strip()
    if not s:
        return None
    s = re.sub(r",\s*(der|die|das)\s*$", "", s).strip()
    if len(s) == 1 and s.isalpha():
        return None
    if s.startswith("Grundwortschatz für") or s.startswith("Planungshilfe"):
        return None
    if "Jahrgangsstufen" in s or "Häufigkeitswörter" in s:
        return None
    if re.fullmatch(r"\d+", s):
        return None
    parts = s.split()
    if parts and parts[0].lower() in ARTICLES:
        parts = parts[1:]
    if not parts:
        return None
    return parts[0]


def extract_lemmas(text_path: Path) -> list[str]:
    if not text_path.exists():
        raise SystemExit(f"Brandenburg extract not found: {text_path}")
    lines = text_path.read_text(encoding="utf-8").splitlines()
    lemmas: list[str] = []
    seen: set[str] = set()
    for label, lo, hi in SECTIONS:
        for ln in lines[lo - 1 : hi]:
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
    lemmas = extract_lemmas(BB_TXT)
    print(f"Extracted {len(lemmas)} unique Brandenburg Grundwortschatz lemmas")
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
    became_first_source = 0
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
    print(f"  Became first source-tag for word: {became_first_source}")
    print(f"  Brandenburg lemmas not present in DB at all: {miss_in_db}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
