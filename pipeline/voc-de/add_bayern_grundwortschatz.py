"""Add a `BAYERN` source-attribution token AND per-word
`bayernCategories` (Bayern orthographic-pattern labels) to every DB
word that appears in the Bayerische Grundwortschatz.

Source PDFs (ISB Bayern, Ergänzende Informationen zum LehrplanPLUS):
  https://www.lehrplanplus.bayern.de/sixcms/media.php/71/5_Grundwortschatz%201_2.pdf
  https://www.lehrplanplus.bayern.de/sixcms/media.php/71/6_Grundwortschatz%203_4.pdf

Publisher: Staatsinstitut für Schulqualität und Bildungsforschung (ISB),
           München — state agency under the Bayerisches Staatsministerium
           für Unterricht und Kultus.
License posture: amtliches Werk per §5 UrhG.

Bayern uses TWO line formats for category headers:
  1. Standalone-line header followed by body lines (like Hessen):
       Nutzung des phonologischen und des silbischen Prinzips
       Wörter beim Schreiben in Silben gegliedert mitsprechen
       Aufgabe, Auge, Auto, ...
  2. Same-line header + body, colon-separated:
       Wörter mit <er>:  Bruder, Feder, Fenster, Schwester, Winter

We handle both.
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
BY12_TXT = Path("/tmp/bl_audit/by12.txt")
BY34_TXT = Path("/tmp/bl_audit/by34.txt")
OUT_LIST = REPO / "pipeline" / "voc-de" / "sources" / "bayern_grundwortschatz.txt"
OUT_CATS = REPO / "pipeline" / "voc-de" / "sources" / "bayern_grundwortschatz_categories.json"

TOKEN = "BAYERN"
META_KEY = "bayernCategories"


PARENS_RE = re.compile(r"\(([^)]+)\)")


def is_header_only(line: str) -> bool:
    """A standalone header line (no body): no comma in left part, but
    note Bayern doesn't always require this; we use keyword start."""
    s = line.strip()
    if not s or s.isdigit():
        return False
    if "," in s:
        return False
    keywords = (
        "Nutzung", "Verbindung", "Wörter beim",
        "Verschiedenheit", "Silbenaufbau", "Schreibungen",
        "Wörter aus", "Wörter mit", "regelhafte",
        "nicht-regelhafte", "Umlautung", "Verhärtungen",
        "Verhärtung", "Flexions-", "Flektierte",
    )
    return any(s.startswith(k) for k in keywords)


def looks_like_body_line(line: str) -> bool:
    s = line.strip()
    if not s:
        return False
    return ("," in s) or (":" in s and len(s) > 5)


def parse_tokens(text: str) -> list[str]:
    """Parse a body fragment into individual lemma tokens."""
    out: list[str] = []
    # Strip leading category prefix like "Wörter mit <ß>:" so only the body
    # gets tokenized.
    s = text
    # Drop angle-bracketed orthographem markers — <er>, <Sp>, <ß>, etc.
    s = re.sub(r"<[^>]*>", "", s)
    # Drop slash IPA markers like /ks/, /aɪ/.
    s = re.sub(r"/[^/]+/", "", s)
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
            if tok.endswith("-"):
                continue
            if " " in tok:
                tok = tok.split()[0]
            if not tok or len(tok) < 2:
                continue
            if tok[0].isdigit():
                continue
            out.append(tok)
    return out


def extract_from_file(text_path: Path) -> dict[str, set[str]]:
    """Returns {lemma_lowercased: {categories}}."""
    if not text_path.exists():
        raise SystemExit(f"Bayern extract not found: {text_path}")
    lines = text_path.read_text(encoding="utf-8").splitlines()
    word_cats: dict[str, set[str]] = {}
    original_case: dict[str, str] = {}
    current_cat: str | None = None
    for raw in lines:
        s = raw.strip()
        if not s:
            continue
        # Same-line header + body: "Wörter mit <er>: Bruder, …"
        if ":" in s and any(s.startswith(k) for k in (
            "Wörter mit", "Wörter aus", "Wörter beim",
            "Nutzung", "Verschiedenheit", "Silbenaufbau",
            "Umlautung", "Verhärtungen", "Verhärtung",
            "Flexions", "Flektierte",
            "<", "regelhafte", "nicht-regelhafte",
            "Dehnungs", "Doppelvokal",
        )):
            head, _, body = s.partition(":")
            current_cat = head.strip()
            for tok in parse_tokens(body):
                key = tok.lower()
                word_cats.setdefault(key, set()).add(current_cat)
                original_case.setdefault(key, tok)
            continue
        if is_header_only(s):
            current_cat = s
            continue
        if current_cat is None:
            continue
        if not looks_like_body_line(s):
            continue
        for tok in parse_tokens(s):
            key = tok.lower()
            word_cats.setdefault(key, set()).add(current_cat)
            original_case.setdefault(key, tok)
    return {original_case[k]: sorted(cats) for k, cats in word_cats.items()}


def extract() -> dict[str, list[str]]:
    """Union the categories from both Bayern PDFs."""
    a = extract_from_file(BY12_TXT)
    b = extract_from_file(BY34_TXT)
    out: dict[str, set[str]] = {}
    orig_case: dict[str, str] = {}
    for w, cats in {**a, **b}.items():
        out.setdefault(w.lower(), set()).update(cats)
        orig_case.setdefault(w.lower(), w)
    # Re-merge a + b properly (the dict-merge above loses cats from `a` for
    # any key present in `b`).
    out.clear()
    for src in (a, b):
        for w, cats in src.items():
            out.setdefault(w.lower(), set()).update(cats)
            orig_case.setdefault(w.lower(), w)
    return {orig_case[k]: sorted(cats) for k, cats in out.items()}


def main() -> int:
    word_to_cats = extract()
    print(f"Extracted {len(word_to_cats)} unique Bayern lemmas")
    OUT_LIST.parent.mkdir(parents=True, exist_ok=True)
    OUT_LIST.write_text("\n".join(word_to_cats.keys()) + "\n", encoding="utf-8")
    OUT_CATS.write_text(
        json.dumps(word_to_cats, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    distinct_cats = sorted({c for cats in word_to_cats.values() for c in cats})
    print(f"  {len(distinct_cats)} distinct Bayern orthographic categories")

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
    print(f"  Bayern lemmas not present in DB at all: {miss_in_db}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
