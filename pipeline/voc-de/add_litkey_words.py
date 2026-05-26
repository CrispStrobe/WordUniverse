"""Add missing vocabulary to the DE DB from LiTKey + curated German first name list.

Three categories of entries added:

1. LiTKey content word lemmas (POS: NN, VV*, ADJ*, ADV, ITJ)
   Source: Litkey-Tab.csv, column chl_lemma (childLex canonical form).
   Entries get pre-populated litkey_error_rate and litkey_word_features.
   Only lemmas not yet present as word or lemma in the DB are added.

2. LiTKey NE person names (manually curated subset of LiTKey NE column)
   Source: LITKEY, tag NE.  Only real recurring first/last names, not
   story characters or misspellings.

3. Curated German first name list (VORNAME_DE)
   ~200 common German first names based on GfdS statistics that may not
   appear in the LiTKey dictation texts (e.g. Benjamin, Sebastian, Sophie).
   Added with partOfSpeech=NE and definitions=["Vorname"].

Also re-adds 'ausfindig' which was removed during subtitle-corpus cleanup
(it belongs to the fixed phrase 'ausfindig machen' and is attested in many
standard German dictionaries).

Idempotent: safe to re-run, skips entries already in DB.

Usage:
  python add_litkey_words.py [--db grundwortschatz.db] [--no-compress] [--dry-run]
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import shutil
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

DEFAULT_DB = HERE / "grundwortschatz.db"
WORK_DB = Path("/tmp/dbpatch_litkey_words/working.db")
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"
LITKEY_CSV = HERE / "sources" / "Litkey-Tab.csv"

# POS tags treated as content words (STTS tagset)
CONTENT_POS = frozenset({
    "NN", "VVFIN", "VVINF", "VVPP", "VVIMP", "VVIZU",
    "ADJD", "ADJA", "ADV", "ITJ", "CARD",
})

# POS → human-readable German label (stored in enrichment_json.partOfSpeech)
POS_LABEL = {
    "NN":    "Substantiv",
    "VVFIN": "Verb", "VVINF": "Verb", "VVPP": "Verb",
    "VVIMP": "Verb", "VVIZU": "Verb",
    "ADJD":  "Adjektiv", "ADJA": "Adjektiv",
    "ADV":   "Adverb",
    "ITJ":   "Interjektion",
    "CARD":  "Zahl",
    "NE":    "Eigenname",
}

# ---------------------------------------------------------------------------
# Curated German first name list (GfdS statistics, common across decades)
# These are deliberately excluded: very short nicknames already in DB,
# and names so rare they won't appear in primary school contexts.
# ---------------------------------------------------------------------------

VORNAME_MAENNLICH = [
    "Aaron", "Adam", "Alexander", "Andreas", "Anton", "Arthur", "Axel",
    "Benjamin", "Benedikt", "Christoph", "Christian", "Daniel", "David",
    "Dominik", "Elias", "Emil", "Erik", "Fabian", "Finn", "Florian",
    "Franz", "Friedrich", "Georg", "Gregor", "Gustav", "Heinrich",
    "Helmut", "Henrik", "Jakob", "Johannes", "Jonathan", "Julian",
    "Kevin", "Konrad", "Lars", "Leon", "Leonardo", "Luca", "Lukas",
    "Manuel", "Marcel", "Markus", "Martin", "Maximilian", "Michael",
    "Moritz", "Nico", "Niklas", "Noah", "Oliver", "Patrick", "Philipp",
    "Robert", "Robin", "Sebastian", "Simon", "Stefan", "Thomas",
    "Tobias", "Valentin", "Viktor", "Wilhelm",
]

VORNAME_WEIBLICH = [
    "Alina", "Amanda", "Angela", "Anna", "Antonia", "Carla", "Charlotte",
    "Christina", "Clara", "Elena", "Elisabeth", "Ella", "Emilia", "Emma",
    "Eva", "Franziska", "Hannah", "Hanna", "Helena", "Jana", "Julia",
    "Katharina", "Kira", "Laura", "Lara", "Lea", "Lena", "Leonie",
    "Lina", "Lisa", "Luisa", "Luna", "Maria", "Marie", "Maya", "Mia",
    "Mila", "Nathalie", "Nicole", "Nina", "Nora", "Paula", "Sara",
    "Sarah", "Sina", "Sofia", "Sophia", "Stefanie", "Tina", "Ulrike",
    "Vanessa", "Victoria",
]

VORNAME_ALL = sorted(set(VORNAME_MAENNLICH + VORNAME_WEIBLICH))

# ---------------------------------------------------------------------------
# Clearly real person names from LiTKey NE column (hand-curated subset).
# Excludes misspellings (Felex, Micherel, Nicklars…), fictional story
# characters (Kipley, Wolfmeister, Palkowitz…), and noise words.
# ---------------------------------------------------------------------------

LITKEY_REAL_NAMES = {
    # High-frequency LiTKey characters (used in many dictation texts)
    "Lea", "Lars", "Dodo", "Lena", "Tom", "Max", "Leon", "Tim", "Nico",
    "Felix", "Jan", "Peter", "Lukas", "Lara", "Michael", "Momo", "Luca",
    "Otto",
    # Medium-frequency recurring names
    "Alex", "Niklas", "Ben", "Fritz", "Nina", "Niko", "Maximilian",
    "Jonas", "David", "Leo", "Hans", "Anna", "Lisa", "Bobby", "Dario",
    "Chris", "Jenny", "Till", "Dennis", "Ralf", "Luis", "Mari", "Mario",
    "Tina", "Sina", "Julia", "Paul", "Klaus", "Linda", "Thomas", "Noah",
    "Simon", "Stefan", "Tobi", "Christian", "Heinz", "Bernhard", "Frank",
    "Kati", "Rico", "Niki", "Henri", "Benny", "Kiki", "Lulu", "Maxi",
    "Susi", "Fritzi", "Nicklas", "Nikolas",
    # Surnames appearing as dictation characters
    "Müller", "Meyer", "Schulze", "Koch", "Wagner", "Becker",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _next_id(con: sqlite3.Connection) -> int:
    row = con.execute("SELECT MAX(id) FROM words").fetchone()
    return (row[0] or 0) + 1


def _in_db(word_lower: str, db_words: set[str], db_lemmas: set[str]) -> bool:
    return word_lower in db_words or word_lower in db_lemmas


def _make_row(
    row_id: int,
    word: str,
    lemma: str,
    pos_tag: str,
    sources: list[str],
    definitions: list[str] | None = None,
    litkey_meta: dict | None = None,
) -> tuple:
    enrichment = {}
    if pos_tag:
        enrichment["partOfSpeech"] = POS_LABEL.get(pos_tag, pos_tag)
    if definitions:
        enrichment["definitions"] = definitions

    metadata: dict = {"sources": sources}
    if litkey_meta:
        metadata.update(litkey_meta)

    return (
        row_id,
        word,
        lemma,
        None,   # frequency_json
        json.dumps(enrichment, ensure_ascii=False) if enrichment else None,
        json.dumps(metadata, ensure_ascii=False),
    )


# ---------------------------------------------------------------------------
# Load LiTKey statistics
# ---------------------------------------------------------------------------

def load_litkey(csv_path: Path) -> tuple[dict, dict]:
    """Return (content_lemmas, ne_names).

    content_lemmas: {lemma_lower: (canonical_lemma, pos_tag, error_rate, features)}
    ne_names: {name: count}
    """
    lemma_total:  dict[str, int]       = defaultdict(int)
    lemma_errors: dict[str, int]       = defaultdict(int)
    lemma_pos:    dict[str, str]       = {}
    lemma_canon:  dict[str, str]       = {}
    ne_names:     Counter              = Counter()

    FEAT_COLS = [
        "graph_comb", "graph_marked", "ie", "schwa_silent",
        "doubleC_syl", "doubleC_other", "doubleV", "h_length",
        "h_sep", "r_voc", "devoice_final", "g_spirant",
        "morph_bound",
    ]
    lemma_feat_sum:  dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    lemma_feat_n:    dict[str, int]            = defaultdict(int)

    with csv_path.open(encoding="utf-8", errors="replace") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            pos    = (row.get("POS")       or "").strip()
            target = (row.get("target")    or "").strip()
            lemma  = (row.get("chl_lemma") or "").strip()
            erron  = (row.get("erroneous") or "0").strip()

            if pos == "NE" and target and re.match(r"^[A-ZÄÖÜ][a-zA-ZäöüÄÖÜß]+$", target):
                ne_names[target] += 1
                continue

            if pos not in CONTENT_POS or not lemma or lemma == "NA":
                continue

            key = lemma.lower()
            lemma_total[key] += 1
            if erron == "1":
                lemma_errors[key] += 1
            lemma_pos.setdefault(key, pos)
            lemma_canon.setdefault(key, lemma)

            # Feature accumulation
            for col in FEAT_COLS:
                try:
                    v = float(row.get(col) or 0)
                    if v:
                        lemma_feat_sum[key][col] += 1
                except ValueError:
                    pass
            lemma_feat_n[key] += 1

    content_lemmas: dict = {}
    for key in lemma_total:
        total = lemma_total[key]
        errors = lemma_errors[key]
        rate = round(errors / total, 4) if total else 0.0
        feats = {
            col: 1
            for col in FEAT_COLS
            if lemma_feat_sum[key].get(col, 0) / max(lemma_feat_n[key], 1) > 0.5
        } if lemma_feat_n[key] else {}
        content_lemmas[key] = {
            "canonical": lemma_canon[key],
            "pos":       lemma_pos[key],
            "error_rate": rate,
            "features":  feats,
        }

    return content_lemmas, ne_names


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",          default=str(DEFAULT_DB))
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--dry-run",     action="store_true")
    args = ap.parse_args()

    if not LITKEY_CSV.exists():
        sys.exit(f"ERROR: {LITKEY_CSV} not found — run add_litkey_errors.py --download first")

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    print("Loading LiTKey CSV …")
    content_lemmas, ne_names = load_litkey(LITKEY_CSV)
    print(f"  content lemmas: {len(content_lemmas)}, NE forms: {len(ne_names)}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row

    db_words  = {r[0].lower() for r in con.execute("SELECT word FROM words")}
    db_lemmas_col = {(r[0] or "").lower()
                     for r in con.execute("SELECT lemma FROM words") if r[0]}
    in_db = db_words | db_lemmas_col

    new_rows: list[tuple] = []
    row_id = _next_id(con)

    # ------------------------------------------------------------------ #
    # 1. Content word lemmas from LiTKey                                  #
    # ------------------------------------------------------------------ #
    added_content = 0
    for key, info in sorted(content_lemmas.items()):
        if key in in_db:
            continue
        word = info["canonical"]
        pos  = info["pos"]
        rate = info["error_rate"]
        feats = info["features"]

        difficulty = (
            0 if rate < 0.25 else
            1 if rate < 0.50 else
            2 if rate < 0.75 else 3
        )
        litkey_meta = {
            "litkey_error_rate": rate,
            "spellingDifficulty": difficulty,
        }
        if feats:
            litkey_meta["litkey_word_features"] = feats

        new_rows.append(_make_row(
            row_id, word, word, pos,
            sources=["LITKEY"],
            litkey_meta=litkey_meta,
        ))
        in_db.add(key)
        row_id += 1
        added_content += 1

    print(f"Content lemmas to add: {added_content}")

    # ------------------------------------------------------------------ #
    # 2. LiTKey NE names (curated real names only)                       #
    # ------------------------------------------------------------------ #
    added_ne_litkey = 0
    for name in sorted(LITKEY_REAL_NAMES):
        if name.lower() in in_db:
            continue
        new_rows.append(_make_row(
            row_id, name, name, "NE",
            sources=["LITKEY"],
            definitions=["Vorname"],
        ))
        in_db.add(name.lower())
        row_id += 1
        added_ne_litkey += 1

    print(f"LiTKey NE names to add: {added_ne_litkey}")

    # ------------------------------------------------------------------ #
    # 3. Curated German first name list                                   #
    # ------------------------------------------------------------------ #
    added_vorname = 0
    for name in VORNAME_ALL:
        if name.lower() in in_db:
            continue
        new_rows.append(_make_row(
            row_id, name, name, "NE",
            sources=["VORNAME_DE"],
            definitions=["Vorname"],
        ))
        in_db.add(name.lower())
        row_id += 1
        added_vorname += 1

    print(f"Curated first names to add: {added_vorname}")

    # ------------------------------------------------------------------ #
    # 4. Restore 'ausfindig' (fixed phrase 'ausfindig machen',           #
    #    removed during subtitle-corpus cleanup)                          #
    # ------------------------------------------------------------------ #
    added_misc = 0
    MISC_RESTORE = [
        ("ausfindig", "ausfindig", "ADV", ["WIKTIONARY"],
         ["Teil der Wendung 'ausfindig machen' (= finden, ermitteln)"], None),
    ]
    for word, lemma, pos, srcs, defs, lmeta in MISC_RESTORE:
        if word.lower() not in in_db:
            new_rows.append(_make_row(row_id, word, lemma, pos,
                                      sources=srcs, definitions=defs,
                                      litkey_meta=lmeta))
            in_db.add(word.lower())
            row_id += 1
            added_misc += 1

    print(f"Misc restores: {added_misc}")

    # ------------------------------------------------------------------ #
    # Write                                                               #
    # ------------------------------------------------------------------ #
    total = len(new_rows)
    print(f"\nTotal new entries: {total}")
    if total == 0:
        print("Nothing to add — done.")
        con.close()
        return 0

    if not args.dry_run:
        con.executemany(
            "INSERT INTO words (id, word, lemma, frequency_json, enrichment_json, metadata_json) "
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
