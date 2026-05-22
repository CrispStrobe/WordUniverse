#!/usr/bin/env python3
"""Local-only enrichment for voc-en, bypassing the Gradio Space.

Reads /Volumes/backups/code/WiktionaryEN-space/en_wiktionary_normalized.db
directly + uses wn (OEWN) directly + calls the local ConceptNet mirror
at http://127.0.0.1:7862 via gradio_client. Avoids the deadlock that the
Wiktionary Gradio Space hits inside its handler-thread context.

Output: in-place update of grundwortschatz_en_enriched_v24.json with
apiEnrichment.enrichment_status = "success" | "no_data" | "error" per
word, matching the schema produced by 11_reprocess_full_wikidict_en.py.

Run:
    cd /Users/christianstrobele/code/voc
    /Users/christianstrobele/miniconda3/bin/python pipeline/voc-en/11b_enrich_local.py
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import threading
import time
import traceback
from pathlib import Path

# Reuse caches across the whole run.
WIKT_DB_PATH = "/Users/christianstrobele/code/voc/.local-data/en_wiktionary_normalized.db"
CONCEPTNET_URL = "http://127.0.0.1:7862/"

CONCEPTNET_RELATIONS = [
    "RelatedTo", "IsA", "PartOf", "HasA", "UsedFor", "CapableOf",
    "AtLocation", "Synonym", "Antonym", "Causes", "HasProperty",
    "MadeOf", "HasSubevent", "DerivedFrom", "SimilarTo",
]

# Pos remap (from Wiktionary's POS tags to our canonical pos keys).
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

HERE = Path(__file__).parent
INPUT_JSON = HERE / "grundwortschatz_en.json"
TARGET_JSON = HERE / "grundwortschatz_en_enriched_v24.json"
CHECKPOINT_INTERVAL = 50


# ============================================================================
# Wiktionary SQLite queries (lifted from WiktionaryEN-space/app.py)
# ============================================================================

def pos_key(pos: str | None) -> str:
    if not pos:
        return "other"
    p = pos.strip().lower()
    return POS_KEY_MAP.get(p, p)


def find_all_entries(conn: sqlite3.Connection, word: str) -> list[int]:
    """Return list of entry IDs matching `word` in English."""
    search = list({word, word.lower(), word.title()})
    ph = ", ".join("?" for _ in search)
    found: set[int] = set()
    form_titles = ("Inflected form", "verb form", "noun form",
                   "adjective form", "Comparative", "Superlative")

    lemma_q = conn.execute(
        f"SELECT id, pos_title FROM entries WHERE word IN ({ph}) AND lang = 'English'",
        search,
    ).fetchall()
    parent_lemmas: set[str] = set()
    for row in lemma_q:
        found.add(row[0])
        pt = row[1] or ""
        if any(ft in pt for ft in form_titles):
            for fr in conn.execute(
                "SELECT form_of FROM senses WHERE entry_id = ?", (row[0],)
            ).fetchall():
                try:
                    fdata = json.loads(fr[0]) if fr[0] else []
                except json.JSONDecodeError:
                    fdata = []
                if isinstance(fdata, list) and fdata:
                    parent = fdata[0].get("word") if isinstance(fdata[0], dict) else None
                    if parent:
                        parent_lemmas.add(parent)

    form_q = conn.execute(
        f"""SELECT DISTINCT e.id FROM forms f JOIN entries e ON f.entry_id = e.id
            WHERE f.form_text IN ({ph}) AND e.lang = 'English'
            AND f.id NOT IN (
                SELECT ft.form_id FROM form_tags ft JOIN tags t ON ft.tag_id = t.id
                WHERE t.tag IN ('variant', 'auxiliary')
            )""",
        search,
    ).fetchall()
    for row in form_q:
        found.add(row[0])

    for pl in parent_lemmas:
        for row in conn.execute(
            "SELECT id FROM entries WHERE word = ? AND lang = 'English'", (pl,)
        ).fetchall():
            found.add(row[0])
    return sorted(found)


def build_report(conn: sqlite3.Connection, entry_id: int) -> dict:
    """Return a per-entry report mirroring the Space's
    `_wiktionary_build_report_for_entry`.
    NOTE: ignores the passed conn; opens its own fresh connection. The
    shared conn from find_all_entries somehow blocks subsequent queries
    in this process context (reproducible across both Gradio Space and
    standalone scripts). Fresh connections avoid the issue.
    """
    conn = sqlite3.connect(f"file:{WIKT_DB_PATH}?mode=ro", uri=True, timeout=5)
    conn.row_factory = sqlite3.Row
    head = conn.execute(
        "SELECT word, title, redirect, pos, pos_title, lang, etymology_text FROM entries WHERE id = ?",
        (entry_id,),
    ).fetchone()
    if not head:
        return {}
    rep = {
        "entry_id": entry_id,
        "word": head[0], "title": head[1], "redirect": head[2],
        "pos": head[3], "pos_title": head[4], "lang": head[5],
        "etymology_text": head[6],
        "lemma": head[0],
    }

    senses_q = conn.execute(
        """SELECT s.id, s.sense_index,
             (SELECT GROUP_CONCAT(g.gloss_text, '; ') FROM glosses g WHERE g.sense_id = s.id),
             (SELECT GROUP_CONCAT(t.tag, ', ') FROM sense_tags st JOIN tags t ON st.tag_id = t.id WHERE st.sense_id = s.id),
             (SELECT GROUP_CONCAT(top.topic, ', ') FROM sense_topics stop JOIN topics top ON stop.topic_id = top.id WHERE stop.sense_id = s.id)
           FROM senses s WHERE s.entry_id = ? ORDER BY s.id""",
        (entry_id,),
    ).fetchall()
    senses = []
    for s in senses_q:
        ex = conn.execute("SELECT text, ref FROM examples WHERE sense_id = ?", (s[0],)).fetchall()
        senses.append({
            "sense_id": s[0], "sense_index": s[1], "glosses": s[2],
            "tags": s[3], "topics": s[4],
            "examples": [{"text": e[0], "ref": e[1]} for e in ex],
        })
    rep["senses"] = senses

    forms_q = conn.execute(
        """SELECT f.form_text, f.sense_index,
            (SELECT GROUP_CONCAT(t.tag, ', ') FROM form_tags ft JOIN tags t ON ft.tag_id = t.id WHERE ft.form_id = f.id)
           FROM forms f WHERE f.entry_id = ? GROUP BY f.id ORDER BY f.id""",
        (entry_id,),
    ).fetchall()
    rep["forms"] = [{"form_text": f[0], "sense_index": f[1], "tags": f[2]} for f in forms_q]

    # Pronunciations, expressions, etc. — fetch in bulk.
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
        ).fetchall() if r[0]
    ]
    try:
        conn.close()
    except Exception:
        pass
    return rep


# ============================================================================
# OEWN (wn) helpers — direct, no worker queue
# ============================================================================

import wn

_WN_EN = None  # global singleton
_OEWN_CACHE: dict[str, dict[str, list[dict]]] = {}
_OEWN_LOCK = threading.Lock()


def get_wn_en() -> wn.Wordnet:
    global _WN_EN
    if _WN_EN is None:
        _WN_EN = wn.Wordnet("oewn:2024")
    return _WN_EN


def oewn_senses_by_pos(word: str) -> dict[str, list[dict]]:
    """Return {pos_key: [sense_dict, ...]}, cached per lowercase word."""
    key = (word or "").lower()
    with _OEWN_LOCK:
        if key in _OEWN_CACHE:
            return _OEWN_CACHE[key]
    wn_en = get_wn_en()
    senses_by_pos: dict[str, list[dict]] = {
        "noun": [], "verb": [], "adjective": [], "adverb": [],
    }
    try:
        for sense in wn_en.senses(key):
            synset = sense.synset()
            pt = synset.pos
            def get_lemmas(synsets, remove_self=False):
                out: set[str] = set()
                for s in synsets:
                    for l in s.lemmas():
                        if not (remove_self and l == key):
                            out.add(l)
                return sorted(out)
            antonyms: set[str] = set()
            try:
                for ant in sense.get_related("antonym"):
                    antonyms.add(ant.word().lemma())
            except Exception:
                pass
            info = {
                "pos": pt,
                "definition": synset.definition() or "No definition available.",
                "synonyms": get_lemmas([synset], remove_self=True),
                "antonyms": sorted(antonyms),
                "hypernyms (is a type of)": get_lemmas(synset.hypernyms()),
                "hyponyms (examples are)": get_lemmas(synset.hyponyms()),
                "holonyms (is part of)": get_lemmas(synset.holonyms()),
                "meronyms (has parts)": get_lemmas(synset.meronyms()),
            }
            target = {"n": "noun", "v": "verb", "a": "adjective",
                      "s": "adjective", "r": "adverb"}.get(pt)
            if target:
                senses_by_pos[target].append(info)
    except Exception as e:
        print(f"[WARN] OEWN lookup failed for {word!r}: {e}", flush=True)
    with _OEWN_LOCK:
        _OEWN_CACHE[key] = senses_by_pos
    return senses_by_pos


# ============================================================================
# ConceptNet (local Gradio mirror) helpers
# ============================================================================

_CN_CLIENT = None
_CN_CACHE: dict[str, list[dict]] = {}
_CN_LOCK = threading.Lock()


def get_cn_client():
    global _CN_CLIENT
    if _CN_CLIENT is None:
        from gradio_client import Client
        _CN_CLIENT = Client(CONCEPTNET_URL, verbose=False)
    return _CN_CLIENT


_CN_LINE_PATTERN = re.compile(r"-\s*(.+?)\s+(\w+)\s+→\s+(.+?)\s+\`\[([\d.]+)\]\`")


def conceptnet_relations(word: str) -> list[dict]:
    key = (word or "").lower()
    with _CN_LOCK:
        if key in _CN_CACHE:
            return _CN_CACHE[key]
    if not key:
        return []
    try:
        client = get_cn_client()
        md = client.predict(
            word=key, lang="en", selected_relations=CONCEPTNET_RELATIONS,
            api_name="/get_semantic_profile",
        )
    except Exception as e:
        print(f"[WARN] ConceptNet error for {word!r}: {e}", flush=True)
        with _CN_LOCK:
            _CN_CACHE[key] = []
        return []
    relations: list[dict] = []
    current = None
    for line in (md or "").splitlines():
        ln = line.strip()
        if ln.startswith("## "):
            current = ln[3:].strip()
            continue
        if current and ln.startswith("- "):
            m = _CN_LINE_PATTERN.search(ln)
            if not m:
                continue
            node1, rel, node2, weight = m.group(1).strip("* "), m.group(2), m.group(3).strip("* "), float(m.group(4))
            if node1.lower() == key:
                other, direction = node2, "->"
            elif node2.lower() == key:
                other, direction = node1, "<-"
            else:
                continue
            relations.append({
                "relation": rel, "target": other, "other_node": other,
                "weight": weight, "direction": direction,
            })
    relations.sort(key=lambda r: -r["weight"])
    with _CN_LOCK:
        _CN_CACHE[key] = relations
    return relations


# ============================================================================
# Build enrichment from per-word data
# ============================================================================

def build_enrichment(reports: list[dict], word: str) -> dict:
    """Combine Wiktionary reports + OEWN + ConceptNet into apiEnrichment."""
    if not reports:
        return {"enrichment_status": "no_data"}

    # Pick primary entry (lowest priority_score = best match).
    primary = reports[0]
    primary_pos_key = pos_key(primary.get("pos"))
    primary_lemma = primary.get("lemma") or word

    # Definitions from senses
    definitions = [
        s["glosses"] for s in primary.get("senses", [])
        if s.get("glosses")
    ]

    # OEWN supplement
    oewn = oewn_senses_by_pos(primary_lemma)
    oewn_for_pos = oewn.get(primary_pos_key, [])
    if not definitions:
        definitions = [s["definition"] for s in oewn_for_pos if s.get("definition")]

    synonyms: set[str] = set()
    antonyms: set[str] = set()
    for s in oewn_for_pos:
        synonyms.update(s.get("synonyms") or [])
        antonyms.update(s.get("antonyms") or [])

    # Examples from senses
    examples = []
    for s in primary.get("senses", []):
        for ex in s.get("examples", []):
            if ex.get("text"):
                examples.append({
                    "text": ex.get("text"),
                    "ref": ex.get("ref"),
                    "author": None, "title": None, "year": None,
                })
    examples = examples[:3]

    # ConceptNet
    cn_rels = conceptnet_relations(primary_lemma)[:10]

    enrichment = {
        "enrichment_status": "success",
        "primary_pos": primary_pos_key,
        "primary_lemma": primary_lemma,
        "definitions": definitions[:5],
        "inflections": (primary.get("forms") or [])[:20],
        "pronunciation": [
            p for p in primary.get("pronunciation", []) if p.get("ipa") or p.get("audio")
        ],
        "examples": examples,
        "hyphenation": primary.get("hyphenation", []),
        "expressions": [],
        "proverbs": [],
        "entryNotes": [],
        "hypernyms": [{"hypernym_word": l} for l in (oewn_for_pos[0].get("hypernyms (is a type of)") if oewn_for_pos else [])][:10],
        "hyponyms": [{"hyponym_word": l} for l in (oewn_for_pos[0].get("hyponyms (examples are)") if oewn_for_pos else [])][:10],
        "holonyms": [{"holonym_word": l} for l in (oewn_for_pos[0].get("holonyms (is part of)") if oewn_for_pos else [])][:10],
        "meronyms": [{"meronym_word": l} for l in (oewn_for_pos[0].get("meronyms (has parts)") if oewn_for_pos else [])][:10],
        "coordinateTerms": [],
        "synonyms": sorted(synonyms),
        "antonyms": sorted(antonyms),
        "conceptnet": [
            {"relation": r["relation"], "target": r["target"], "weight": r["weight"]}
            for r in cn_rels
        ],
        "wiktionary_translations": [],
        "wiktionary_derived_terms": [],
        "wiktionary_related_terms": [],
        "alternative_analyses": [
            {"pos": pos_key(r.get("pos")), "lemma": r.get("lemma"), "definition": ""}
            for r in reports[1:5]
        ],
    }
    return enrichment


# ============================================================================
# Main loop
# ============================================================================

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="Process at most N untouched entries (0=all)")
    ap.add_argument("--retry-errors", action="store_true", help="Re-process entries that previously errored")
    ap.add_argument("--input", default=str(TARGET_JSON), help="JSON to load/update")
    args = ap.parse_args()

    inp = Path(args.input)
    if not inp.exists():
        print(f"ERROR: {inp} not found")
        return 1

    with inp.open("r") as f:
        data = json.load(f)
    voc = data["vocabulary"]
    print(f"Loaded {len(voc)} vocabulary entries")

    def needs_enrich(e):
        ae = e.get("apiEnrichment") or {}
        if not isinstance(ae, dict):
            return True
        status = ae.get("enrichment_status")
        if status == "success":
            return False
        if status == "error" and not args.retry_errors:
            return False
        return True

    targets = [e for e in voc if needs_enrich(e)]
    print(f"  {len(targets)} entries need enrichment "
          f"({sum(1 for e in voc if (e.get('apiEnrichment') or {}).get('enrichment_status') == 'success')} already done)")

    if args.limit:
        targets = targets[:args.limit]
        print(f"  limiting to first {args.limit}")

    print(f"Opening Wiktionary DB: {WIKT_DB_PATH}")
    conn = sqlite3.connect(f"file:{WIKT_DB_PATH}?mode=ro", uri=True, timeout=5)
    conn.row_factory = sqlite3.Row
    print(f"Pre-warming OEWN…")
    get_wn_en()
    print(f"Pre-warming ConceptNet client to {CONCEPTNET_URL}…")
    get_cn_client()
    print("Ready. Beginning enrichment.")

    success = 0
    no_data = 0
    errors = 0
    t_start = time.time()

    for idx, entry in enumerate(targets, 1):
        word = entry.get("word") or ""
        if not word:
            continue
        try:
            t0 = time.time()
            entry_ids = find_all_entries(conn, word)
            if not entry_ids:
                entry["apiEnrichment"] = {"enrichment_status": "no_data"}
                no_data += 1
            else:
                reports = []
                for eid in entry_ids[:10]:  # cap at 10 entries per word
                    try:
                        rep = build_report(conn, eid)
                        if rep:
                            reports.append(rep)
                    except Exception as e:
                        print(f"  [build_report ERR {eid}] {e}", flush=True)
                if not reports:
                    entry["apiEnrichment"] = {"enrichment_status": "no_data"}
                    no_data += 1
                else:
                    entry["apiEnrichment"] = build_enrichment(reports, word)
                    success += 1
            elapsed = time.time() - t0
            if idx % 5 == 0 or elapsed > 5:
                rate = idx / (time.time() - t_start) if t_start else 0
                eta = (len(targets) - idx) / rate if rate else 0
                print(f"  [{idx}/{len(targets)}] {word!r} took {elapsed:.2f}s "
                      f"(succ={success} nd={no_data} err={errors} | "
                      f"rate={rate:.1f}/s ETA={eta/60:.1f}min)", flush=True)
        except Exception as e:
            entry["apiEnrichment"] = {
                "enrichment_status": "error",
                "error_message": str(e),
                "traceback": traceback.format_exc(),
            }
            errors += 1
            print(f"  [{idx}/{len(targets)}] ERR {word!r}: {e}", flush=True)

        if idx % CHECKPOINT_INTERVAL == 0:
            with inp.open("w") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f"  checkpoint @ {idx}", flush=True)

    # Final save
    with inp.open("w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    elapsed = time.time() - t_start
    print(f"\nDone in {elapsed:.1f}s. success={success}, no_data={no_data}, errors={errors}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
