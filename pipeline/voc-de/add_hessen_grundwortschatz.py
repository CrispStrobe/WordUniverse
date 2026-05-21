"""Add a `HESSEN` source-attribution token to every DB word that appears
in the Hessischer Grundwortschatz.

Source PDF (Wörterliste, separate compact wordlist):
  https://kultus.hessen.de/sites/kultus.hessen.de/files/2022-09/woerterliste_aus_der_handreichung_zum_grundwortschatz_hessen.pdf

Publisher: Hessisches Kultusministerium, Luisenplatz 10, 65185 Wiesbaden
           (direct state ministry, public administrative material per §5 UrhG;
           verbindlich für hessische Grundschulen seit Schuljahr 2021/22).

The wordlist is organized by orthographic phenomena (Lautgetreue Einsilber,
-e, -en, …; Funktionswörter; Wörter mit Doppelkonsonanz; Wörter mit
Auslautverhärtung; etc.). Tokens are comma-separated within each
paragraph. Pattern handling:

  - "Bad – Bäder"        → both "Bad" and "Bäder"
  - "lassen – lässt"     → both "lassen" and "lässt"
  - "(nichts)"           → "nichts"
  - "dein+"              → "dein"   (the '+' marks function-word variants)
  - section headers (Capitalized lines not containing ',') are skipped

Pre-conditions:
  - /tmp/bl_audit/he.txt must exist (pdftotext -layout of he.pdf).

Outputs:
  - assets/grundwortschatz.db.gz (in-place re-compressed)
  - pipeline/voc-de/sources/hessen_grundwortschatz.txt
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
HE_TXT = Path("/tmp/bl_audit/he.txt")
OUT_LIST = REPO / "pipeline" / "voc-de" / "sources" / "hessen_grundwortschatz.txt"

TOKEN = "HESSEN"


def is_section_header(line: str) -> bool:
    s = line.strip()
    if not s:
        return True
    # Section headers don't contain commas and don't have lowercase
    # words followed by punctuation in the body sense. Heuristic: a
    # line with NO commas is treated as a header. Body lines virtually
    # always contain commas (it's a comma-separated wordlist).
    if "," not in s:
        return True
    return False


PARENS_RE = re.compile(r"\(([^)]+)\)")


def parse_tokens(line: str) -> list[str]:
    """Parse a body line into individual lemma tokens.

    Handles:
      - comma separation
      - "X – Y" pairs (em-dash with surrounding spaces) → both X and Y
      - parenthetical alternatives "(nichts)" → "nichts"
      - trailing '+' markers
    """
    out: list[str] = []
    # First convert "(X)" → ", X," so they get treated as separate tokens.
    s = PARENS_RE.sub(r", \1,", line)
    # Split on commas.
    parts = [p.strip() for p in s.split(",")]
    for p in parts:
        if not p:
            continue
        # Split on em-dash patterns (Bad – Bäder).
        # Also handle hyphen-minus surrounded by spaces.
        for sub in re.split(r"\s+[–-]\s+", p):
            tok = sub.strip()
            if not tok:
                continue
            tok = tok.rstrip("+").strip()
            tok = tok.strip(".;:!?")
            # Drop multi-token entries — should be rare here; if it
            # still has internal whitespace, take the first word as the
            # lemma candidate.
            if " " in tok:
                tok = tok.split()[0]
            if tok and len(tok) >= 2 and not tok[0].isdigit():
                out.append(tok)
    return out


def extract_lemmas(text_path: Path) -> list[str]:
    if not text_path.exists():
        raise SystemExit(f"Hessen extract not found: {text_path}")
    lines = text_path.read_text(encoding="utf-8").splitlines()
    lemmas: list[str] = []
    seen: set[str] = set()
    for raw in lines:
        if is_section_header(raw):
            continue
        for tok in parse_tokens(raw):
            key = tok.lower()
            if key in seen:
                continue
            seen.add(key)
            lemmas.append(tok)
    return lemmas


def main() -> int:
    lemmas = extract_lemmas(HE_TXT)
    print(f"Extracted {len(lemmas)} unique Hessen Grundwortschatz lemmas")
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
    print(f"  Hessen lemmas not present in DB at all: {miss_in_db}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
