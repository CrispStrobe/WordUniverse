"""Add a `SCHLESWIG_HOLSTEIN` source-attribution token AND per-word
`schleswig_holsteinCategories` (orthographic-pattern + theme labels)
to every DB word that appears in the SH Rechtschreib-Grundwortschatz.

Source PDF ("Ebbe, Krabbe, Flut und Seepferdchen", Juni 2023):
  https://www.schleswig-holstein.de/DE/landesregierung/ministerien-behoerden/III/Service/Broschueren/Bildung/grundwortschatz.pdf?__blob=publicationFile&v=3

Publisher: Ministerium für Allgemeine und Berufliche Bildung,
           Wissenschaft, Forschung und Kultur,
           Brunswiker Straße 16-22, 24105 Kiel
           Mitwirkung: EUF, IQSH
           Autorinnen: Prof. Dr. Johanna Fay, Tanja Šutalo

Per the Impressum: "Der schleswig-holsteinische Rechtschreib-Grundwortschatz
wurde mit Zustimmung der Schulbehörde Hamburg in Anlehnung an den
Hamburger Basiswortschatz erstellt." SH's publication is the redistribution
path — amtliches Werk per §5 UrhG via SH Ministerium.

The wordlist proper is on pages 14-24, organized into 14 numbered
categories with sub-sections (Offene Silben, Silbengelenke, Komposita,
Affixe, Stammkonstanz, Merkwörter, Funktionswörter, Wortarten,
Themen-Wortschätze für Klassenraum/Essen/Familie/etc).

Pre-conditions:
  - /tmp/bl_audit/sh_p14_24.txt must exist (pdftotext -layout -f 14 -l 24).
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
SH_TXT = Path("/tmp/bl_audit/sh_p14_24.txt")
OUT_LIST = REPO / "pipeline" / "voc-de" / "sources" / "schleswig_holstein_grundwortschatz.txt"
OUT_CATS = REPO / "pipeline" / "voc-de" / "sources" / "schleswig_holstein_grundwortschatz_categories.json"

TOKEN = "SCHLESWIG_HOLSTEIN"
META_KEY = "schleswig_holsteinCategories"


PARENS_RE = re.compile(r"\(([^)]+)\)")
NUMBERED_SECTION_RE = re.compile(r"^\s*(\d+)\.\s+(.+)$")
LETTERED_SUBSECTION_RE = re.compile(r"^\s*([a-z])\.\s+(.+)$")
ROMAN_SUBSECTION_RE = re.compile(r"^\s*(i+|iv|v|vi|vii)\.\s+(.+)$", re.IGNORECASE)


def parse_tokens(text: str) -> list[str]:
    out: list[str] = []
    s = text
    s = re.sub(r"<[^>]*>", "", s)
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


def extract() -> dict[str, list[str]]:
    if not SH_TXT.exists():
        raise SystemExit(f"SH extract not found: {SH_TXT}")
    lines = SH_TXT.read_text(encoding="utf-8").splitlines()
    word_cats: dict[str, set[str]] = {}
    original_case: dict[str, str] = {}

    section_name: str | None = None
    subsection: str | None = None  # "a", "b", …
    subsection_title: str | None = None
    deep_section: str | None = None  # "i", "ii", …
    deep_title: str | None = None
    affix_label: str | None = None  # "ab-", "an-", "-chen", etc.

    def current_category() -> str | None:
        parts = []
        if section_name:
            parts.append(section_name)
        if subsection_title:
            parts.append(subsection_title)
        if deep_title:
            parts.append(deep_title)
        return " · ".join(parts) if parts else None

    for raw in lines:
        s = raw.strip()
        if not s:
            continue
        # Drop page-number footers.
        if s.isdigit():
            continue

        # Numbered top-level section: "1. Offene Silben"
        m = NUMBERED_SECTION_RE.match(s)
        if m:
            section_name = m.group(2).strip()
            subsection = subsection_title = None
            deep_section = deep_title = None
            affix_label = None
            continue

        # Lettered subsection: "a. Wörter mit einfachen…"
        m = LETTERED_SUBSECTION_RE.match(s)
        if m:
            subsection = m.group(1)
            subsection_title = m.group(2).strip()
            deep_section = deep_title = None
            affix_label = None
            continue

        # Roman numeral deep subsection (used under Affixe): "i. Trennbare Verben"
        m = ROMAN_SUBSECTION_RE.match(s)
        if m:
            deep_section = m.group(1).lower()
            deep_title = m.group(2).strip()
            continue

        # Affix-table entry: "ab-   ablesen, abholen, …"
        # Pattern: short token ending in '-' (or starting with '-') followed by examples.
        m = re.match(r"^([a-zäöüß]+-|\-[a-zäöüß]+)\s+(.+)$", s)
        if m and section_name and "Affixe" in section_name:
            affix_label = m.group(1)
            body = m.group(2)
            cat = current_category()
            if cat:
                cat = f"{cat} · {affix_label}"
            for tok in parse_tokens(body):
                key = tok.lower()
                if cat:
                    word_cats.setdefault(key, set()).add(cat)
                original_case.setdefault(key, tok)
            continue

        # Body line (no header pattern).
        cat = current_category()
        if not cat:
            continue
        for tok in parse_tokens(s):
            key = tok.lower()
            word_cats.setdefault(key, set()).add(cat)
            original_case.setdefault(key, tok)

    return {original_case[k]: sorted(cats) for k, cats in word_cats.items()}


def main() -> int:
    word_to_cats = extract()
    print(f"Extracted {len(word_to_cats)} unique SH Grundwortschatz lemmas")
    OUT_LIST.parent.mkdir(parents=True, exist_ok=True)
    OUT_LIST.write_text("\n".join(word_to_cats.keys()) + "\n", encoding="utf-8")
    OUT_CATS.write_text(
        json.dumps(word_to_cats, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    distinct_cats = sorted({c for cats in word_to_cats.values() for c in cats})
    print(f"  {len(distinct_cats)} distinct SH categories")

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
    print(f"  SH lemmas not present in DB at all: {miss_in_db}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
