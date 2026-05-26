#!/usr/bin/env python3
"""Add OEWN (Open English WordNet) sense data to entries that lack it.

Targets entries where enrichment_json.wordnetSenses is missing or empty.
Adds wordnetSenses[], extends definitions[], synonyms[], antonyms[],
hypernyms[] — same logic as the JSON-based 13_wordnet_expansion.py but
operating directly on the SQLite DB.

Requires: pip install wn && python -c "import wn; wn.download('oewn:2024')"

Usage:
    python3 add_oewn_en.py [--db PATH] [--workers N] [--limit N] [--no-compress]
                            [--filter-status STATUS]

    --filter-status  Only process entries with this enrichment_status (default: success).
                     Use 'any' to process all entries regardless of status.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import sys
import time
from pathlib import Path

import wn as _wn

HERE = Path(__file__).parent
SRC_DB_DEFAULT = HERE / "grundwortschatz_en.db"
WORK_DIR = Path("/tmp/dbpatch_oewn_en")
WORK_DB = WORK_DIR / "working.db"
CKPT = WORK_DIR / "oewn_results.jsonl"

MAX_DEFS = 8

POS_LABEL = {
    "n": "noun", "v": "verb", "a": "adjective",
    "s": "adjective", "r": "adverb", "t": "particle",
}

# wn uses a module-level SQLite connection — not thread-safe.
# Run single-threaded; ~30-40 lookups/s after warmup → 6k entries ≈ 3 min.
_WN_EN: _wn.Wordnet | None = None


def get_wn_en() -> _wn.Wordnet:
    global _WN_EN
    if _WN_EN is None:
        _WN_EN = _wn.Wordnet("oewn:2024")
    return _WN_EN


def get_lemmas(synsets, exclude_lc: str | None = None) -> list[str]:
    out: set[str] = set()
    for s in synsets:
        try:
            for l in s.lemmas():
                if exclude_lc and l.lower() == exclude_lc:
                    continue
                out.add(l)
        except Exception:
            pass
    return sorted(out)


def get_antonyms(sense) -> list[str]:
    out: set[str] = set()
    try:
        for ant in sense.get_related("antonym"):
            try:
                out.add(ant.word().lemma())
            except Exception:
                pass
    except Exception:
        pass
    return sorted(out)


def get_hypernym_chain(synset, depth: int = 2) -> list[list[str]]:
    chain: list[list[str]] = []
    current = [synset]
    for _ in range(depth):
        next_level = []
        level_lemmas: set[str] = set()
        for s in current:
            try:
                for parent in s.hypernyms():
                    next_level.append(parent)
                    for l in parent.lemmas():
                        level_lemmas.add(l)
            except Exception:
                pass
        if not next_level:
            break
        chain.append(sorted(level_lemmas))
        current = next_level
    return chain


def expand_word(word: str) -> dict:
    """Return OEWN expansion data for a word."""
    wn_en = get_wn_en()
    word_lc = word.lower()
    senses_out = []
    all_syn: set[str] = set()
    all_ant: set[str] = set()
    all_hyp: set[str] = set()
    all_defs: list[str] = []

    try:
        senses = wn_en.senses(word_lc)
    except Exception:
        return {}

    for sense in senses:
        try:
            synset = sense.synset()
            pos_label = POS_LABEL.get(synset.pos, synset.pos)
            definition = (synset.definition() or "").strip()
            synonyms = get_lemmas([synset], exclude_lc=word_lc)
            antonyms = get_antonyms(sense)
            hyps = get_lemmas(synset.hypernyms())
            hypo = get_lemmas(synset.hyponyms())
            holo = get_lemmas(synset.holonyms())
            mero = get_lemmas(synset.meronyms())
            hyp_chain = get_hypernym_chain(synset, depth=2)
            senses_out.append({
                "pos": pos_label,
                "definition": definition,
                "synonyms": synonyms,
                "antonyms": antonyms,
                "hypernyms": hyps,
                "hyponyms": hypo,
                "holonyms": holo,
                "meronyms": mero,
                "hypernymChain": hyp_chain,
            })
            all_syn.update(synonyms)
            all_ant.update(antonyms)
            all_hyp.update(hyps)
            if definition:
                all_defs.append(definition)
        except Exception:
            continue

    if not senses_out:
        return {}

    return {
        "senses": senses_out,
        "all_synonyms": sorted(all_syn),
        "all_antonyms": sorted(all_ant),
        "all_hypernyms": sorted(all_hyp),
        "all_definitions": all_defs,
    }


def merge_defs(existing: list, from_wn: list) -> list:
    seen_lc = {(d or "").strip().lower() for d in existing if isinstance(d, str)}
    out = list(existing)
    for d in from_wn:
        d_clean = (d or "").strip()
        if not d_clean or d_clean.lower() in seen_lc:
            continue
        seen_lc.add(d_clean.lower())
        out.append(d_clean)
        if len(out) >= MAX_DEFS:
            break
    return out


def merge_list(existing: list, new: list) -> list:
    seen = {(x or "").lower() for x in existing if isinstance(x, str)}
    out = list(existing)
    for n in new:
        if n.lower() not in seen:
            seen.add(n.lower())
            out.append(n)
    return out


def process_entry(row_id: int, word: str, enrich_json: str) -> tuple[int, str, str, str]:
    """Return (row_id, word, status, updated_enrichment_json)."""
    try:
        enrichment = json.loads(enrich_json) if enrich_json else {}
    except json.JSONDecodeError:
        enrichment = {}

    exp = expand_word(word)
    if not exp:
        return row_id, word, "no_data", json.dumps(enrichment, ensure_ascii=False)

    enrichment["wordnetSenses"] = exp["senses"]
    enrichment["definitions"] = merge_defs(
        enrichment.get("definitions") or [], exp["all_definitions"]
    )
    enrichment["synonyms"] = merge_list(
        enrichment.get("synonyms") or [], exp["all_synonyms"]
    )
    enrichment["antonyms"] = merge_list(
        enrichment.get("antonyms") or [], exp["all_antonyms"]
    )

    existing_hyp = enrichment.get("hypernyms") or []
    existing_hyp_words = {
        (x.get("hypernym_word") if isinstance(x, dict) else x or "").lower()
        for x in existing_hyp
    }
    for h in exp["all_hypernyms"]:
        if h.lower() not in existing_hyp_words:
            existing_hyp.append({"hypernym_word": h, "source": "OEWN"})
            existing_hyp_words.add(h.lower())
    if existing_hyp:
        enrichment["hypernyms"] = existing_hyp

    return row_id, word, "success", json.dumps(enrichment, ensure_ascii=False)


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
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(SRC_DB_DEFAULT))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--filter-status", default="success",
                    help="Only process entries with this enrichment_status, or 'any'")
    ap.add_argument("--apply-only", action="store_true")
    args = ap.parse_args()

    src = Path(args.db)
    if not src.exists():
        print(f"ERROR: {src} not found"); return 1

    WORK_DIR.mkdir(parents=True, exist_ok=True)

    if not WORK_DB.exists() or src.stat().st_mtime > WORK_DB.stat().st_mtime:
        print(f"Copying {src.name} → {WORK_DB} …")
        shutil.copy2(src, WORK_DB)
    else:
        print(f"Resuming with existing {WORK_DB}")

    if args.apply_only:
        n = apply_checkpoint(WORK_DB)
        print(f"Applied {n} records.")
        shutil.copy2(WORK_DB, src)
        return 0

    done_ids = load_checkpoint()
    print(f"Checkpoint: {len(done_ids)} already done")

    db_conn = sqlite3.connect(str(WORK_DB))
    db_conn.row_factory = sqlite3.Row

    if args.filter_status == "any":
        status_clause = ""
        params: list = []
    else:
        status_clause = "WHERE json_extract(enrichment_json, '$.enrichment_status') = ?"
        params = [args.filter_status]

    rows = db_conn.execute(
        f"SELECT id, word, enrichment_json FROM words {status_clause}", params
    ).fetchall()
    db_conn.close()

    # Filter: skip entries that already have wordnetSenses populated
    targets = []
    for r in rows:
        if r["id"] in done_ids:
            continue
        try:
            ej = json.loads(r["enrichment_json"] or "{}")
            wns = ej.get("wordnetSenses")
            if isinstance(wns, list) and len(wns) > 0:
                continue  # already has OEWN data
        except json.JSONDecodeError:
            pass
        targets.append((r["id"], r["word"], r["enrichment_json"]))

    print(f"Entries to expand: {len(targets)} (have status={args.filter_status!r} + empty wordnetSenses)")

    if args.limit:
        targets = targets[: args.limit]

    if not targets:
        print("Nothing to do.")
        n = apply_checkpoint(WORK_DB)
        print(f"Applied {n} checkpoint records.")
        shutil.copy2(WORK_DB, src)
        _maybe_compress(src, args)
        return 0

    print("Pre-warming OEWN…", flush=True)
    get_wn_en()
    print("Ready.", flush=True)

    success = no_data = errors = 0
    t_start = time.time()

    with CKPT.open("a") as ckpt_f:
        for processed, task in enumerate(targets, 1):
            row_id, word, status, ej = process_entry(*task)

            if status == "success":
                success += 1
            elif status == "no_data":
                no_data += 1
            else:
                errors += 1

            ckpt_f.write(
                json.dumps({"id": row_id, "word": word, "enrichment_json": ej},
                           ensure_ascii=False) + "\n"
            )
            ckpt_f.flush()

            if processed % 500 == 0 or processed == len(targets):
                elapsed = time.time() - t_start
                rate = processed / elapsed if elapsed else 0
                eta = (len(targets) - processed) / rate if rate else 0
                print(
                    f"  [{processed}/{len(targets)}] "
                    f"succ={success} nd={no_data} err={errors} | "
                    f"{rate:.0f}/s ETA={eta/60:.1f}min",
                    flush=True,
                )

    n = apply_checkpoint(WORK_DB)
    print(f"Applied {n} checkpoint records.")
    shutil.copy2(WORK_DB, src)
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
