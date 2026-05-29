#!/usr/bin/env python3
"""Fill the EN vocabulary DB's `translations` table with EN→DE translations.

The shipped `grundwortschatz_en.db` had an EMPTY `translations` table; German
learners of English benefit from a DE gloss per word. Source: the normalized
English Wiktionary DB (CC-BY-SA 4.0 — same license as the EN DB, already
attributed), which carries ~156k EN→DE translation rows.

For each vocabulary word we collect its German translations from Wiktionary,
clean + frequency-rank + dedupe them, and cap to MAX_PER_WORD. Stored in the
existing `translations(word_id, lang_code, translation)` table (lang_code='de').

Usage:
  python3 add_translations_en.py --load [--compress]
"""
from __future__ import annotations

import argparse
import collections
import gzip
import re
import shutil
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SRC_DB = HERE / "grundwortschatz_en.db"
DB_GZ = REPO / "assets" / "grundwortschatz_en.db.gz"
WIKT_DB = "/Volumes/backups/code/WiktionaryEN-space/en_wiktionary_normalized.db"

MAX_PER_WORD = 4
MAX_WORDS = 4   # drop phrase-like translations longer than this
MIN_ZIPF = 2.7  # drop ultra-rare/dialectal German forms (Huus, lauffe) when
                # wordfreq is available — but the top-count translation is always kept

try:
    from wordfreq import zipf_frequency as _zipf  # type: ignore
    _HAVE_WORDFREQ = True
except ImportError:
    _HAVE_WORDFREQ = False

    def _zipf(_w, _lang):  # fallback: no frequency signal
        return 0.0


def _clean(t: str) -> str | None:
    t = (t or "").strip()
    if not t:
        return None
    # drop wiki markup / links / parentheticals / obvious non-glosses
    if any(c in t for c in ("[", "]", "{", "}", "http", "|")):
        return None
    t = re.sub(r"\s*\([^)]*\)", "", t).strip()  # strip "(...)" notes
    if not t or len(t.split()) > MAX_WORDS:
        return None
    return t


def load(compress: bool, wikt_db: str) -> int:
    if not Path(wikt_db).exists():
        sys.exit(f"Wiktionary DB not found: {wikt_db}")
    if not SRC_DB.exists():
        sys.exit(f"DB not found: {SRC_DB}")

    voc = sqlite3.connect(SRC_DB)
    word_id = {}
    for wid, w in voc.execute("SELECT id, word FROM words"):
        word_id.setdefault(w.lower(), wid)  # first id wins
    print(f"vocab words: {len(word_id)}")

    # Collect translations per vocab word, counting frequency for ranking.
    wikt = sqlite3.connect(f"file:{wikt_db}?mode=ro", uri=True)
    counts: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    scanned = 0
    for ew, de in wikt.execute(
        "SELECT e.word, t.word FROM translations t "
        "JOIN entries e ON e.id = t.entry_id "
        "WHERE t.lang_code = 'de' AND e.lang_code = 'en'"
    ):
        scanned += 1
        if not ew:
            continue
        key = ew.lower()
        if key not in word_id:
            continue
        g = _clean(de)
        if g:
            counts[key][g] += 1
    wikt.close()
    print(f"scanned {scanned:,} EN→DE rows; {len(counts)} vocab words matched")

    # Rebuild only the de translations (idempotent); keep any non-de rows.
    voc.execute("DELETE FROM translations WHERE lang_code = 'de'")
    inserted = words_filled = 0
    for key, ctr in counts.items():
        # rank by (Wiktionary occurrence count, German frequency), both desc
        ranked = sorted(ctr.items(),
                        key=lambda kv: (-kv[1], -_zipf(kv[0], "de"), kv[0]))
        top_count = ranked[0][1]
        # The correct primary translation repeats across senses (Haus×3); rare
        # wrong-sense translations appear once (Kind/Mutter/Vater for "house").
        # Keep the top, plus others only if they recur AND aren't ultra-rare.
        recur = max(2, round(top_count * 0.4))
        chosen = []
        for i, (g, cnt) in enumerate(ranked):
            keep = i == 0 or (cnt >= recur
                              and (not _HAVE_WORDFREQ or _zipf(g, "de") >= MIN_ZIPF))
            if keep:
                chosen.append(g)
            if len(chosen) >= MAX_PER_WORD:
                break
        if not chosen:
            continue
        words_filled += 1
        for g in chosen:
            voc.execute(
                "INSERT INTO translations(word_id, lang_code, translation) "
                "VALUES (?, 'de', ?)", (word_id[key], g))
            inserted += 1
    voc.commit()
    total = voc.execute("SELECT COUNT(*) FROM translations WHERE lang_code='de'").fetchone()[0]
    voc.close()
    print(f"inserted {inserted} DE translations across {words_filled} words "
          f"(table now has {total} de rows)")

    if compress:
        print(f"compressing → {DB_GZ}")
        with SRC_DB.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
            shutil.copyfileobj(fi, fo)
        print(f"  {DB_GZ.stat().st_size // 1024} KB written")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Fill EN DB translations (EN→DE) from Wiktionary")
    ap.add_argument("--load", action="store_true")
    ap.add_argument("--compress", action="store_true")
    ap.add_argument("--wikt", default=WIKT_DB)
    args = ap.parse_args()
    if args.load:
        return load(args.compress, args.wikt)
    ap.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
