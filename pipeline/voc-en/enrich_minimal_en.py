#!/usr/bin/env python3
"""Wiktionary enrichment for entries with enrichment_status='minimal'.

Reads grundwortschatz_en.db (SQLite, table 'words') and queries
en_wiktionary_normalized.db for each minimal entry, then writes
definitions/inflections/pronunciation/examples/hyphenation back to
enrichment_json.  Skips OEWN and ConceptNet (not available locally).

Preserves existing fields: tags, sources, commonLearnerErrors,
spellingVariants, inflectionData, grade_examples, gutenberg_examples.

Uses a JSONL checkpoint for crash-safe resume.

Usage:
    python3 enrich_minimal_en.py [--db PATH] [--workers N] [--limit N]
                                  [--no-compress] [--apply-only]
"""
from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import sys
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).parent
SRC_DB_DEFAULT = HERE / "grundwortschatz_en.db"
WIKT_DB_PATH = "/Volumes/backups/code/WiktionaryEN-space/en_wiktionary_normalized.db"
WORK_DIR = Path("/tmp/dbpatch_wikt_minimal_en")
WORK_DB = WORK_DIR / "working.db"
CKPT = WORK_DIR / "wikt_minimal_results.jsonl"

_PRESERVE_KEYS = (
    "wordnetSenses", "commonLearnerErrors", "spellingVariants",
    "inflectionData", "tags", "sources",
)
# grade_examples and gutenberg_examples live in metadata_json — untouched by this script.

POS_KEY_MAP = {
    "noun": "noun", "name": "noun", "proper noun": "noun",
    "verb": "verb",
    "adj": "adjective", "adjective": "adjective",
    "adv": "adverb", "adverb": "adverb",
    "intj": "interjection", "interjection": "interjection",
    "conj": "conjunction", "prep": "preposition",
    "pron": "pronoun", "det": "determiner",
    "num": "numeral", "particle": "particle",
}


def pos_key(pos: str | None) -> str:
    if not pos:
        return "other"
    return POS_KEY_MAP.get(pos.strip().lower(), pos.strip().lower())


# ── Wiktionary lookups ───────────────────────────────────────────────────────

_FORM_TITLES = ("Inflected form", "verb form", "noun form",
                "adjective form", "Comparative", "Superlative")


def find_all_entries(wikt_conn: sqlite3.Connection, word: str) -> list[int]:
    search = list({word, word.lower(), word.title()})
    ph = ", ".join("?" for _ in search)
    found: set[int] = set()

    rows = wikt_conn.execute(
        f"SELECT id, pos_title FROM entries WHERE word IN ({ph}) AND lang = 'English'",
        search,
    ).fetchall()
    parent_lemmas: set[str] = set()
    for row_id, pos_title in rows:
        found.add(row_id)
        if any(ft in (pos_title or "") for ft in _FORM_TITLES):
            for (form_of,) in wikt_conn.execute(
                "SELECT form_of FROM senses WHERE entry_id = ?", (row_id,)
            ).fetchall():
                try:
                    fdata = json.loads(form_of) if form_of else []
                except json.JSONDecodeError:
                    fdata = []
                if isinstance(fdata, list) and fdata:
                    parent = fdata[0].get("word") if isinstance(fdata[0], dict) else None
                    if parent:
                        parent_lemmas.add(parent)

    for (row_id,) in wikt_conn.execute(
        f"""SELECT DISTINCT e.id FROM forms f JOIN entries e ON f.entry_id = e.id
            WHERE f.form_text IN ({ph}) AND e.lang = 'English'
            AND f.id NOT IN (
                SELECT ft.form_id FROM form_tags ft JOIN tags t ON ft.tag_id = t.id
                WHERE t.tag IN ('variant', 'auxiliary')
            )""",
        search,
    ).fetchall():
        found.add(row_id)

    for pl in parent_lemmas:
        for (row_id,) in wikt_conn.execute(
            "SELECT id FROM entries WHERE word = ? AND lang = 'English'", (pl,)
        ).fetchall():
            found.add(row_id)

    return sorted(found)


def build_report(entry_id: int) -> dict:
    """Open a fresh read-only connection per call to avoid cursor contention."""
    conn = sqlite3.connect(f"file:{WIKT_DB_PATH}?mode=ro", uri=True, timeout=10)
    conn.row_factory = sqlite3.Row
    try:
        head = conn.execute(
            "SELECT word, title, redirect, pos, pos_title, lang, etymology_text "
            "FROM entries WHERE id = ?",
            (entry_id,),
        ).fetchone()
        if not head:
            return {}
        rep = {
            "entry_id": entry_id,
            "word": head["word"], "pos": head["pos"],
            "pos_title": head["pos_title"], "lang": head["lang"],
            "lemma": head["word"],
        }

        senses_q = conn.execute(
            """SELECT s.id, s.sense_index,
                 (SELECT GROUP_CONCAT(g.gloss_text, '; ') FROM glosses g WHERE g.sense_id = s.id),
                 (SELECT GROUP_CONCAT(t.tag, ', ') FROM sense_tags st
                  JOIN tags t ON st.tag_id = t.id WHERE st.sense_id = s.id),
                 (SELECT GROUP_CONCAT(top.topic, ', ') FROM sense_topics stop
                  JOIN topics top ON stop.topic_id = top.id WHERE stop.sense_id = s.id)
               FROM senses s WHERE s.entry_id = ? ORDER BY s.id""",
            (entry_id,),
        ).fetchall()
        senses = []
        for s in senses_q:
            ex = conn.execute(
                "SELECT text, ref FROM examples WHERE sense_id = ?", (s[0],)
            ).fetchall()
            senses.append({
                "sense_id": s[0], "sense_index": s[1], "glosses": s[2],
                "tags": s[3], "topics": s[4],
                "examples": [{"text": e[0], "ref": e[1]} for e in ex],
            })
        rep["senses"] = senses

        forms_q = conn.execute(
            """SELECT f.form_text, f.sense_index,
                (SELECT GROUP_CONCAT(t.tag, ', ') FROM form_tags ft
                 JOIN tags t ON ft.tag_id = t.id WHERE ft.form_id = f.id)
               FROM forms f WHERE f.entry_id = ? GROUP BY f.id ORDER BY f.id""",
            (entry_id,),
        ).fetchall()
        rep["forms"] = [
            {"form_text": f[0], "sense_index": f[1], "tags": f[2]} for f in forms_q
        ]

        def fetch_list(table: str, cols: list[str]) -> list[dict]:
            col_sql = ", ".join(cols)
            try:
                rows = conn.execute(
                    f"SELECT {col_sql} FROM {table} WHERE entry_id = ?", (entry_id,)
                ).fetchall()
            except sqlite3.OperationalError:
                return []
            return [dict(zip(cols, r)) for r in rows]

        rep["pronunciation"] = fetch_list("sounds", ["ipa", "audio"])
        rep["hyphenation"] = [
            r[0] for r in conn.execute(
                "SELECT hyphenation FROM hyphenations WHERE entry_id = ?", (entry_id,)
            ).fetchall()
            if r[0]
        ]
        return rep
    finally:
        try:
            conn.close()
        except Exception:
            pass


def build_enrichment_wikt(reports: list[dict], word: str, existing_pos: str | None) -> dict:
    """Build enrichment from Wiktionary only (no OEWN, no ConceptNet).

    Tries to pick the report whose POS matches existing_pos (from CEFR-J).
    """
    if not reports:
        return {"enrichment_status": "no_data"}

    # Prefer report matching the pre-existing POS hint, else take first.
    primary = reports[0]
    if existing_pos:
        for r in reports:
            if pos_key(r.get("pos")) == existing_pos:
                primary = r
                break

    primary_pos = pos_key(primary.get("pos"))
    primary_lemma = primary.get("lemma") or word

    definitions = [
        s["glosses"] for s in primary.get("senses", []) if s.get("glosses")
    ]

    examples = []
    for s in primary.get("senses", []):
        for ex in s.get("examples", []):
            if ex.get("text"):
                examples.append({
                    "text": ex["text"],
                    "ref": ex.get("ref"),
                    "author": None, "title": None, "year": None,
                })

    return {
        "enrichment_status": "success",
        "primary_pos": primary_pos,
        "primary_lemma": primary_lemma,
        "definitions": definitions[:5],
        "inflections": (primary.get("forms") or [])[:20],
        "pronunciation": [
            p for p in primary.get("pronunciation", []) if p.get("ipa") or p.get("audio")
        ],
        "examples": examples[:3],
        "hyphenation": primary.get("hyphenation", []),
        "expressions": [],
        "proverbs": [],
        "entryNotes": [],
        "hypernyms": [],
        "hyponyms": [],
        "holonyms": [],
        "meronyms": [],
        "coordinateTerms": [],
        "synonyms": [],
        "antonyms": [],
        "conceptnet": [],
        "wiktionary_translations": [],
        "wiktionary_derived_terms": [],
        "wiktionary_related_terms": [],
        "alternative_analyses": [
            {"pos": pos_key(r.get("pos")), "lemma": r.get("lemma"), "definition": ""}
            for r in reports[1:5]
        ],
    }


def enrich_word(word: str, existing_pos: str | None) -> tuple[str, dict]:
    """Return (status, enrichment_dict). Opens its own Wiktionary connections."""
    wikt_conn = sqlite3.connect(f"file:{WIKT_DB_PATH}?mode=ro", uri=True, timeout=10)
    wikt_conn.row_factory = sqlite3.Row
    try:
        entry_ids = find_all_entries(wikt_conn, word)
    finally:
        wikt_conn.close()

    if not entry_ids:
        return "no_data", {"enrichment_status": "no_data"}

    reports: list[dict] = []
    for eid in entry_ids[:10]:
        try:
            rep = build_report(eid)
            if rep:
                reports.append(rep)
        except Exception:
            pass

    if not reports:
        return "no_data", {"enrichment_status": "no_data"}

    return "success", build_enrichment_wikt(reports, word, existing_pos)


# ── Checkpoint helpers ────────────────────────────────────────────────────────

def load_checkpoint() -> set[int]:
    done: set[int] = set()
    if not CKPT.exists():
        return done
    with CKPT.open() as f:
        for line in f:
            try:
                done.add(json.loads(line)["id"])
            except (json.JSONDecodeError, KeyError):
                pass
    return done


def apply_checkpoint(db_path: Path) -> int:
    if not CKPT.exists():
        return 0
    conn = sqlite3.connect(str(db_path))
    applied = 0
    with CKPT.open() as f:
        for line in f:
            try:
                rec = json.loads(line)
                conn.execute(
                    "UPDATE words SET enrichment_json = ? WHERE id = ?",
                    (rec["enrichment_json"], rec["id"]),
                )
                applied += 1
            except (json.JSONDecodeError, KeyError, sqlite3.Error):
                pass
    conn.commit()
    conn.close()
    return applied


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description="Enrich minimal entries via local Wiktionary DB")
    ap.add_argument("--db", default=str(SRC_DB_DEFAULT))
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--apply-only", action="store_true",
                    help="Apply existing checkpoint to DB and exit")
    args = ap.parse_args()

    src = Path(args.db)
    if not src.exists():
        print(f"ERROR: {src} not found"); return 1
    if not Path(WIKT_DB_PATH).exists():
        print(f"ERROR: Wiktionary DB not found: {WIKT_DB_PATH}"); return 1

    WORK_DIR.mkdir(parents=True, exist_ok=True)

    # Setup working DB (mtime-based resume: src newer → fresh copy)
    if not WORK_DB.exists() or src.stat().st_mtime > WORK_DB.stat().st_mtime:
        print(f"Copying {src.name} → {WORK_DB} …")
        shutil.copy2(src, WORK_DB)
    else:
        print(f"Resuming with existing {WORK_DB}")

    if args.apply_only:
        n = apply_checkpoint(WORK_DB)
        print(f"Applied {n} checkpoint records.")
        shutil.copy2(WORK_DB, src)
        print(f"Copied back to {src}")
        return 0

    done_ids = load_checkpoint()
    print(f"Checkpoint: {len(done_ids)} already done")

    # Fetch minimal entries
    db_conn = sqlite3.connect(str(WORK_DB))
    db_conn.row_factory = sqlite3.Row
    rows = db_conn.execute(
        "SELECT id, word, enrichment_json FROM words "
        "WHERE json_extract(enrichment_json, '$.enrichment_status') = 'minimal'"
    ).fetchall()
    db_conn.close()

    targets = [
        (r["id"], r["word"], r["enrichment_json"])
        for r in rows
        if r["id"] not in done_ids
    ]
    total_minimal = len(rows) + len(done_ids - {r["id"] for r in rows})
    print(f"Minimal entries: {len(rows) + len(done_ids)} total | "
          f"{len(done_ids)} done | {len(targets)} remaining")

    if args.limit:
        targets = targets[: args.limit]
        print(f"  limiting to first {args.limit}")

    if not targets:
        print("Nothing to process — applying checkpoint and copying back.")
        n = apply_checkpoint(WORK_DB)
        print(f"Applied {n} checkpoint records.")
        shutil.copy2(WORK_DB, src)
        _maybe_compress(src, args)
        return 0

    success = no_data = errors = processed = 0
    t_start = time.time()

    def process_one(task: tuple) -> tuple:
        row_id, word, existing_json = task
        try:
            existing = json.loads(existing_json) if existing_json else {}
        except json.JSONDecodeError:
            existing = {}
        existing_pos = existing.get("primary_pos")
        try:
            status, new_enrichment = enrich_word(word, existing_pos)
            # Merge: fill enrichment fields, preserve curriculum metadata
            merged = {**new_enrichment}
            for key in _PRESERVE_KEYS:
                if key in existing:
                    merged[key] = existing[key]
            return row_id, word, status, merged
        except Exception as e:
            return row_id, word, "error", {
                "enrichment_status": "error",
                "error_message": str(e),
                "traceback": traceback.format_exc(),
            }

    with CKPT.open("a") as ckpt_f:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {pool.submit(process_one, t): t for t in targets}
            for fut in as_completed(futures):
                row_id, word, status, enrichment = fut.result()
                if status == "success":
                    success += 1
                elif status == "no_data":
                    no_data += 1
                else:
                    errors += 1
                processed += 1

                rec = json.dumps(
                    {"id": row_id, "word": word,
                     "enrichment_json": json.dumps(enrichment, ensure_ascii=False)},
                    ensure_ascii=False,
                )
                ckpt_f.write(rec + "\n")
                ckpt_f.flush()

                if processed % 100 == 0 or processed == len(targets):
                    elapsed = time.time() - t_start
                    rate = processed / elapsed if elapsed else 0
                    eta = (len(targets) - processed) / rate if rate else 0
                    print(
                        f"  [{processed}/{len(targets)}] "
                        f"succ={success} nd={no_data} err={errors} | "
                        f"{rate:.1f}/s ETA={eta/60:.1f}min",
                        flush=True,
                    )

    n = apply_checkpoint(WORK_DB)
    print(f"Applied {n} checkpoint records to working DB.")

    print(f"Copying {WORK_DB} → {src}")
    shutil.copy2(WORK_DB, src)

    if not args.no_compress:
        _maybe_compress(src, args)

    elapsed = time.time() - t_start
    print(f"\nDone in {elapsed:.0f}s — success={success}, no_data={no_data}, errors={errors}")
    return 0


def _maybe_compress(src: Path, args) -> None:
    if args.no_compress:
        return
    import gzip
    assets_gz = src.parent.parent.parent / "assets" / "grundwortschatz_en.db.gz"
    with open(src, "rb") as fi, gzip.open(assets_gz, "wb", compresslevel=6) as fo:
        shutil.copyfileobj(fi, fo)
    print(f"Compressed → {assets_gz} ({assets_gz.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    sys.exit(main())
