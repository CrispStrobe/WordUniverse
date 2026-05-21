"""Add a `RHEINLAND_PFALZ` source-attribution token AND per-word
`rheinland_pfalzCategories` (orthographic-pattern labels) to every DB
word that appears in the Grundwortschatz Rheinland-Pfalz.

Source PDF (full handreichung):
  https://static.bildung-rp.de/pl-materialien/Allgemein/RP-07956534_GWS_BM_2021.pdf

Publisher: Ministerium für Bildung, Mittlere Bleiche 61, 55116 Mainz
           (direct state ministry, August 2021, verbindlich seit Schuljahr 2022/23)
License:   © Ministerium für Bildung 2021 — amtliches Werk per §5 UrhG

Per the Impressum: "Überarbeitete Fassung der Handreichung zum
Grundwortschatz Hessen (Wiesbaden, März 2020), mit freundlicher
Genehmigung des Hessischen Kultusministeriums." The wordlist content is
largely the Hessen list; categories use the same nomenclature
(Lautgetreue Einsilber / Wörter mit Doppelkonsonanz / etc.).

Body wordlist runs lines 5690–6215 in /tmp/bl_audit/rp.txt.
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
RP_TXT = Path("/tmp/bl_audit/rp.txt")
OUT_LIST = REPO / "pipeline" / "voc-de" / "sources" / "rheinland_pfalz_grundwortschatz.txt"
OUT_CATS = REPO / "pipeline" / "voc-de" / "sources" / "rheinland_pfalz_grundwortschatz_categories.json"

TOKEN = "RHEINLAND_PFALZ"
META_KEY = "rheinland_pfalzCategories"

WORDLIST_START = 5690
WORDLIST_END = 6215


PARENS_RE = re.compile(r"\(([^)]+)\)")


def is_real_header(line: str) -> bool:
    s = line.strip()
    if not s or s.isdigit():
        return False
    keywords = (
        "Wörter mit", "Wörter auf", "Wörter ", "Funktionswörter",
        "Merkwörter", "Monatsnamen", "Fremdwörter", "Lautgetreue",
        "Einsilbige lautgetreue", "Mehrsilbige", "Komplexe Wörter",
        "Ableitbare Wörter", "Orthografische", "Merkschreibungen",
    )
    return any(s.startswith(k) for k in keywords)


def parse_tokens(line: str) -> list[str]:
    out: list[str] = []
    s = PARENS_RE.sub(r", \1,", line)
    for p in [p.strip() for p in s.split(",")]:
        if not p:
            continue
        for sub in re.split(r"\s+[–-]\s+", p):
            tok = sub.strip()
            if not tok:
                continue
            tok = tok.rstrip("+*").strip()
            tok = tok.strip(".;:!?")
            if " " in tok:
                tok = tok.split()[0]
            if tok and len(tok) >= 2 and not tok[0].isdigit():
                out.append(tok)
    return out


def extract(text_path: Path) -> dict[str, list[str]]:
    if not text_path.exists():
        raise SystemExit(f"RLP extract not found: {text_path}")
    lines = text_path.read_text(encoding="utf-8").splitlines()
    body = lines[WORDLIST_START - 1 : WORDLIST_END]
    word_cats: dict[str, set[str]] = {}
    original_case: dict[str, str] = {}
    current_cat: str | None = None
    for raw in body:
        stripped = raw.strip()
        if not stripped:
            continue
        if is_real_header(raw):
            current_cat = stripped
            continue
        if current_cat is None:
            continue
        for tok in parse_tokens(raw):
            key = tok.lower()
            word_cats.setdefault(key, set()).add(current_cat)
            original_case.setdefault(key, tok)
    return {original_case[k]: sorted(cats) for k, cats in word_cats.items()}


def main() -> int:
    word_to_cats = extract(RP_TXT)
    print(f"Extracted {len(word_to_cats)} unique RLP lemmas")
    OUT_LIST.parent.mkdir(parents=True, exist_ok=True)
    OUT_LIST.write_text("\n".join(word_to_cats.keys()) + "\n", encoding="utf-8")
    OUT_CATS.write_text(
        json.dumps(word_to_cats, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    distinct_cats = sorted({c for cats in word_to_cats.values() for c in cats})
    print(f"  {len(distinct_cats)} distinct RLP orthographic categories")

    if not DB_GZ.exists():
        print(f"ERROR: shipped DB not found: {DB_GZ}", file=sys.stderr)
        return 1
    WORK.parent.mkdir(parents=True, exist_ok=True)
    if WORK.exists():
        WORK.unlink()
    print(f"Decompressing {DB_GZ} -> {WORK}")
    with gzip.open(DB_GZ, "rb") as fi, WORK.open("wb") as fo:
        fo.write(fi.read())

    cats_lookup: dict[str, list[str]] = {
        k.lower(): v for k, v in word_to_cats.items()
    }

    con = sqlite3.connect(str(WORK))
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute("SELECT id, word, lemma, metadata_json FROM words")
    rows = cur.fetchall()

    update_cur = con.cursor()
    tagged_count = 0
    cat_added_count = 0
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

        cats = cats_lookup.get(word_key) or cats_lookup.get(lemma_key)
        if not cats:
            continue

        srcs = meta.get("sources")
        if not isinstance(srcs, list):
            srcs = []
        token_added = False
        if TOKEN not in srcs:
            if not srcs:
                became_first_source += 1
            srcs.append(TOKEN)
            meta["sources"] = srcs
            token_added = True

        existing = meta.get(META_KEY)
        if not isinstance(existing, list):
            existing = []
        merged = sorted(set(existing) | set(cats))
        category_changed = merged != existing
        if category_changed:
            meta[META_KEY] = merged
            cat_added_count += 1

        if token_added or category_changed:
            update_cur.execute(
                "UPDATE words SET metadata_json = ? WHERE id = ?",
                (json.dumps(meta, ensure_ascii=False), r["id"]),
            )
            tagged_count += 1

    con.commit()
    con.close()

    miss_in_db = sum(1 for l in cats_lookup if l not in db_lemmas)
    print(f"Updated {tagged_count} word rows")
    print(f"  Category field newly set/extended on: {cat_added_count}")
    print(f"  Became first source-tag for word: {became_first_source}")
    print(f"  RLP lemmas not present in DB at all: {miss_in_db}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
