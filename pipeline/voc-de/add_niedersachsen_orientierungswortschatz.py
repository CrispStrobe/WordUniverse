"""Add a `NIEDERSACHSEN` source-attribution token to every DB word that
appears in the Orientierungswortschatz Niedersachsen.

Source PDF (Materialien für einen kompetenzorientierten Unterricht im
Primarbereich — Orthografie, 2015):
  https://cuvo.nibis.de/index.php?p=download&upload=116
  alt URL: https://www.nibis.de/uploads/redpaul/files/2016-02-25_orthografie_handreichung_korr6c.pdf

Publisher: Niedersächsisches Kultusministerium, Schiffgraben 12,
           30159 Hannover (2015). Free PDF from Niedersächsischer
           Bildungsserver (NiBiS). Public administrative material per §5
           UrhG. One embedded illustration on p. ~115 carries a
           "© 2013 Cornelsen Schulverlage GmbH" notice; we do not
           reproduce the illustration, only the headword lists.

NDS structure note: the Orientierungswortschatz is embedded as word-list
tables within the 172-page pedagogical handreichung, not as a separate
compact wordlist file. We extract by heuristic — any line that looks
like a comma-separated wordlist gets its tokens collected as candidate
lemmas. Category preservation is deferred to a future session because
the two-column PDF layout makes header-association ambiguous.

Outputs:
  - assets/grundwortschatz.db.gz (in-place re-compressed)
  - pipeline/voc-de/sources/niedersachsen_orientierungswortschatz.txt
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
NDS_TXT = Path("/tmp/nds_orth.txt")
OUT_LIST = REPO / "pipeline" / "voc-de" / "sources" / "niedersachsen_orientierungswortschatz.txt"

TOKEN = "NIEDERSACHSEN"

# The Orientierungswortschatz content begins around line 2089 (Chapter 4).
# "Literatur" heading is at line 7476 → stop just before.
WORDLIST_START = 2089
WORDLIST_END = 7475


PARENS_RE = re.compile(r"\(([^)]+)\)")
WORDLIKE_RE = re.compile(r"^[A-ZÄÖÜa-zäöüß][\wäöüÄÖÜß\-]*$")


def looks_like_wordlist_line(line: str) -> bool:
    """A wordlist line: has multiple commas, mostly word-like tokens,
    and length < ~95 chars (right-column commentary makes lines longer)."""
    s = line.strip()
    if not s:
        return False
    if s.count(",") < 2:
        return False
    if len(s) > 120:
        return False
    # First 80 chars (left column) should look word-rich.
    left = s[:80]
    parts = [p.strip() for p in left.split(",")]
    word_parts = sum(
        1 for p in parts if p and WORDLIKE_RE.match(p.split()[0] if p else "")
    )
    return word_parts >= 3


def strip_right_column(line: str) -> str:
    """The two-column PDF layout collapses to: '<left-col words>     <right-col commentary>'.
    Truncate at the first run of 5+ spaces — that's the column gap."""
    parts = re.split(r"\s{5,}", line, maxsplit=1)
    return parts[0]


def parse_tokens(line: str) -> list[str]:
    out: list[str] = []
    # Strip right-column commentary first.
    s = strip_right_column(line)
    # Promote parenthesized alternatives to tokens.
    s = PARENS_RE.sub(r", \1,", s)
    for p in [p.strip() for p in s.split(",")]:
        if not p:
            continue
        for sub in re.split(r"\s+[–-]\s+", p):
            tok = sub.strip()
            if not tok:
                continue
            tok = tok.rstrip("+*").strip()
            tok = tok.strip(".;:!?")
            # Some words wrap mid-line like "ha-" continuing as "ben"
            # → ends with "-": treat as fragment, skip.
            if tok.endswith("-"):
                continue
            if " " in tok:
                tok = tok.split()[0]
            if not tok or len(tok) < 2:
                continue
            if tok[0].isdigit():
                continue
            # Drop tokens with angle brackets like <a> or <ck>.
            if "<" in tok or ">" in tok or "/" in tok:
                continue
            out.append(tok)
    return out


def extract_lemmas(text_path: Path) -> list[str]:
    if not text_path.exists():
        raise SystemExit(f"NDS extract not found: {text_path}")
    lines = text_path.read_text(encoding="utf-8").splitlines()
    body = lines[WORDLIST_START - 1 : WORDLIST_END]
    lemmas: list[str] = []
    seen: set[str] = set()
    for raw in body:
        if not looks_like_wordlist_line(raw):
            continue
        for tok in parse_tokens(raw):
            key = tok.lower()
            if key in seen:
                continue
            seen.add(key)
            lemmas.append(tok)
    return lemmas


def main() -> int:
    lemmas = extract_lemmas(NDS_TXT)
    print(f"Extracted {len(lemmas)} unique NDS Orientierungswortschatz lemmas")
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
    print(f"  NDS lemmas not present in DB at all: {miss_in_db}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
