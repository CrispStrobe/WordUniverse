"""Add a `HESSEN` source-attribution token AND a per-word
`hessenCategories` list (orthographic-pattern labels from the Hessen
Wörterliste, e.g. "Lautgetreue Einsilber", "Wörter mit Dehnungs-h",
"Funktionswörter mit Doppelkonsonanz", etc.) to every DB word that
appears in the Hessischer Grundwortschatz.

Source PDF (Wörterliste, separate compact wordlist):
  https://kultus.hessen.de/sites/kultus.hessen.de/files/2022-09/woerterliste_aus_der_handreichung_zum_grundwortschatz_hessen.pdf

Publisher: Hessisches Kultusministerium, Luisenplatz 10, 65185 Wiesbaden
           (direct state ministry, public administrative material per §5 UrhG;
           verbindlich für hessische Grundschulen seit Schuljahr 2021/22).

The wordlist is organized by orthographic phenomena. Each line of the
extracted text is either:
  - a section header (no commas) — captured as the current category, OR
  - a comma-separated list of lemmas belonging to that category.

Per-word output to metadata_json:
  - sources                gets "HESSEN" appended
  - hessenCategories       set to the sorted list of Hessen categories
                           the word appears under (one word can appear
                           in multiple categories, e.g. "Funktionswörter
                           mit Doppelkonsonanz" + "Wörter mit Doppelkonsonanz")

Outputs:
  - assets/grundwortschatz.db.gz (in-place re-compressed)
  - pipeline/voc-de/sources/hessen_grundwortschatz.txt
  - pipeline/voc-de/sources/hessen_grundwortschatz_categories.json
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
OUT_CATS = REPO / "pipeline" / "voc-de" / "sources" / "hessen_grundwortschatz_categories.json"

TOKEN = "HESSEN"
META_KEY = "hessenCategories"

# Lines to skip as document framing (non-wordlist prose).
SKIP_PREFIXES = ("Hessisches Kultusministerium", "Wörterliste aus")

PARENS_RE = re.compile(r"\(([^)]+)\)")


def is_section_header(line: str) -> bool:
    s = line.strip()
    if not s:
        return True
    # Headers don't contain commas. Body lines virtually always do.
    return "," not in s


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


def is_real_header(line: str) -> bool:
    """A header line: starts with one of the canonical pedagogical
    keywords (even if it contains commas in subordinate clauses). Body
    lemma lines never start with these keywords."""
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


def extract(text_path: Path) -> dict[str, list[str]]:
    """Return {lemma (original case): [category, …]} for the Hessen wordlist."""
    if not text_path.exists():
        raise SystemExit(f"Hessen extract not found: {text_path}")
    lines = text_path.read_text(encoding="utf-8").splitlines()
    word_cats: dict[str, set[str]] = {}
    original_case: dict[str, str] = {}
    current_cat: str | None = None
    for raw in lines:
        stripped = raw.strip()
        if not stripped:
            continue
        if any(stripped.startswith(p) for p in SKIP_PREFIXES):
            continue
        if is_real_header(raw):
            current_cat = stripped
            continue
        # Skip pure-noise lines (numbers, single words that aren't real headers).
        if "," not in stripped:
            continue
        if current_cat is None:
            continue
        for tok in parse_tokens(raw):
            key = tok.lower()
            word_cats.setdefault(key, set()).add(current_cat)
            original_case.setdefault(key, tok)
    return {original_case[k]: sorted(cats) for k, cats in word_cats.items()}


def main() -> int:
    word_to_cats = extract(HE_TXT)
    print(f"Extracted {len(word_to_cats)} unique Hessen lemmas")
    OUT_LIST.parent.mkdir(parents=True, exist_ok=True)
    OUT_LIST.write_text("\n".join(word_to_cats.keys()) + "\n", encoding="utf-8")
    OUT_CATS.write_text(
        json.dumps(word_to_cats, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    distinct_cats = sorted({c for cats in word_to_cats.values() for c in cats})
    print(f"  {len(distinct_cats)} distinct Hessen orthographic categories:")
    for c in distinct_cats:
        print(f"    • {c}")
    print(f"Wrote lemma list -> {OUT_LIST}")
    print(f"Wrote category mapping -> {OUT_CATS}")

    if not DB_GZ.exists():
        print(f"ERROR: shipped DB not found: {DB_GZ}", file=sys.stderr)
        return 1
    WORK.parent.mkdir(parents=True, exist_ok=True)
    if WORK.exists():
        WORK.unlink()
    print(f"Decompressing {DB_GZ} -> {WORK}")
    with gzip.open(DB_GZ, "rb") as fi, WORK.open("wb") as fo:
        fo.write(fi.read())

    # Build lower-cased lookup: lemma -> categories
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

        # Ensure token in sources.
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

        # Merge categories (idempotent: union with any existing).
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
    print(f"  Hessen lemmas not present in DB at all: {miss_in_db}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
