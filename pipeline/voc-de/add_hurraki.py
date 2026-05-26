"""Fetch Hurraki (Leichte Sprache) definitions for DB entries.

Hurraki (hurraki.de) is a freely editable dictionary written in Simple German
(Leichte Sprache). License: CC BY-SA (articles).

For each DB entry the script tries:
  1. https://hurraki.de/wiki/{word}         (capitalised)
  2. https://hurraki.de/wiki/{lemma}        (if different)

On a hit the first paragraph of the article is extracted (before any ==section==
header) and stored as:
  enrichment_json.hurraki_definition  = ["Ein Hund ist ein Haustier."]

definitions[] is updated so the Hurraki sentence appears first (existing
Wiktionary definitions are appended after it), so the Dart layer automatically
shows the simple definition without code changes.

"HURRAKI" is added to metadata_json.sources.

Progress is checkpointed to sources/hurraki_cache.json so the run can be
interrupted and resumed.  Words marked "not_found" in the cache are not
re-fetched.

Skips:
  - Entries already with hurraki_definition
  - Proper nouns (partOfSpeech == "Eigenname")
  - Entries sourced only from subtitle corpora (BUCHMEIER/HERMIT)
    with no Wiktionary/LITKEY backing

Usage:
  python add_hurraki.py [--db grundwortschatz.db] [--no-compress]
                        [--dry-run] [--limit N] [--workers N]
                        [--delay SECONDS]
"""

from __future__ import annotations

import argparse
import gzip
import html as html_mod
import json
import re
import shutil
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from threading import Lock

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

DEFAULT_DB  = HERE / "grundwortschatz.db"
WORK_DB     = Path("/tmp/dbpatch_hurraki/working.db")
DB_GZ       = REPO / "assets" / "grundwortschatz.db.gz"
CACHE_FILE  = HERE / "sources" / "hurraki_cache.json"

BASE_URL    = "https://hurraki.de/wiki/{}"
HEADERS     = {
    "User-Agent":      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                       "AppleWebKit/537.36 (KHTML, like Gecko) "
                       "Chrome/120.0.0.0 Safari/537.36",
    "Accept":          "text/html,application/xhtml+xml",
    "Accept-Language": "de-DE,de;q=0.9",
}
SOURCE_TAG  = "HURRAKI"

# Leichte Sprache uses · as a compound-word splitter — remove it
_RE_MIDDOT  = re.compile(r"·")
# Strip remaining HTML tags
_RE_TAGS    = re.compile(r"<[^>]+>")
# Section heading signal (== … ==)
_RE_SECTION = re.compile(r'<h[23456]', re.I)
# Content div
_RE_CONTENT = re.compile(
    r'<div[^>]+(?:id="mw-content-text"|class="[^"]*mw-parser-output[^"]*")[^>]*>'
    r'(.*)',
    re.S | re.I,
)
_RE_PARA    = re.compile(r'<p>(.*?)</p>', re.S | re.I)

# Sources that confirm a word is real German vocabulary
GOOD_SOURCES = frozenset({
    "WIKTIONARY", "B1", "LITKEY", "CHILDLEX", "DWDS",
    "LEEDS", "LEIPZIG", "VORNAME_STANDESAMT", "VORNAME_DE",
})
SUBTITLE_ONLY = frozenset({"BUCHMEIER", "HERMIT"})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _clean(text: str) -> str:
    text = _RE_MIDDOT.sub("", text)
    text = _RE_TAGS.sub("", text)
    text = html_mod.unescape(text)
    return " ".join(text.split())


def _first_paragraph(html_body: str) -> str | None:
    """Extract the first <p> before any section heading."""
    m = _RE_CONTENT.search(html_body)
    content = m.group(1) if m else html_body

    # Truncate at first section heading
    sec = _RE_SECTION.search(content)
    if sec:
        content = content[:sec.start()]

    for m in _RE_PARA.finditer(content):
        text = _clean(m.group(1))
        if len(text) >= 10:
            # Take first sentence only
            sent = text.split(".")[0].strip()
            if sent:
                return sent + "."
    return None


def _fetch_definition(slug: str) -> str | None:
    """Fetch Hurraki page for slug, return first sentence or None."""
    url = BASE_URL.format(urllib.parse.quote(slug, safe=""))
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise
    except urllib.error.URLError:
        return None

    if "noarticletext" in body:
        return None

    return _first_paragraph(body)


def _to_slug(word: str) -> str:
    """Capitalise first letter (MediaWiki convention), replace spaces."""
    if not word:
        return word
    return word[0].upper() + word[1:]


# ---------------------------------------------------------------------------
# Candidate selection
# ---------------------------------------------------------------------------

def _is_candidate(row: dict) -> bool:
    try:
        meta   = json.loads(row.get("metadata_json") or "{}")
        enrich = json.loads(row.get("enrichment_json") or "{}")
    except (json.JSONDecodeError, TypeError):
        return False

    # Already done
    if enrich.get("hurraki_definition"):
        return False

    # Skip proper nouns (first names, place names)
    pos = enrich.get("partOfSpeech", "")
    if pos in ("Eigenname", "NE"):
        return False

    # Skip subtitle-corpus-only entries with no real definition
    srcs = set(meta.get("sources") or [])
    real_srcs = srcs - SUBTITLE_ONLY - {"LLM_GENERATED", "TATOEBA", "LITKEY",
                                        "DYSLIST", "VORNAME_STANDESAMT", "VORNAME_DE"}
    has_def   = bool(enrich.get("definitions") or enrich.get("senses"))
    if not real_srcs and not has_def:
        return False

    return True


# ---------------------------------------------------------------------------
# Cache (persisted between runs)
# ---------------------------------------------------------------------------

class Cache:
    def __init__(self, path: Path) -> None:
        self._path = path
        self._lock = Lock()
        if path.exists():
            self._data: dict[str, str | None] = json.loads(path.read_text())
        else:
            self._data = {}

    def get(self, key: str) -> tuple[bool, str | None]:
        """Returns (found_in_cache, value)."""
        with self._lock:
            if key in self._data:
                return True, self._data[key]
            return False, None

    def set(self, key: str, value: str | None) -> None:
        with self._lock:
            self._data[key] = value

    def flush(self) -> None:
        with self._lock:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            self._path.write_text(json.dumps(self._data, ensure_ascii=False, indent=2))


# ---------------------------------------------------------------------------
# Worker
# ---------------------------------------------------------------------------

_rate_lock = Lock()

def _lookup(row: dict, cache: Cache, delay: float) -> tuple[int, str | None]:
    """Return (row_id, definition_or_None). Tries word then lemma slug."""
    row_id = row["id"]
    word   = (row.get("word")  or "").strip()
    lemma  = (row.get("lemma") or "").strip()

    slugs: list[str] = []
    s1 = _to_slug(word)
    if s1:
        slugs.append(s1)
    s2 = _to_slug(lemma)
    if s2 and s2 != s1:
        slugs.append(s2)

    for slug in slugs:
        cached, val = cache.get(slug)
        if cached:
            if val:
                return row_id, val
            continue  # cached as not_found

        # Rate-limit: one request at a time per delay window
        with _rate_lock:
            time.sleep(delay)

        try:
            defn = _fetch_definition(slug)
        except Exception as e:
            print(f"  [err] {slug}: {e}", file=sys.stderr)
            defn = None

        cache.set(slug, defn)
        if defn:
            return row_id, defn

    return row_id, None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",          default=str(DEFAULT_DB))
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--dry-run",     action="store_true")
    ap.add_argument("--limit",       type=int, default=None,
                    help="Process at most N candidates (for testing)")
    ap.add_argument("--workers",         type=int, default=2,
                    help="Parallel HTTP workers (default 2)")
    ap.add_argument("--delay",           type=float, default=0.5,
                    help="Seconds between requests per worker (default 0.5)")
    ap.add_argument("--from-cache-only", action="store_true",
                    help="Apply cached hits to DB without making any HTTP requests")
    args = ap.parse_args()

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row
    raw = con.execute(
        "SELECT id, word, lemma, enrichment_json, metadata_json FROM words"
    ).fetchall()
    rows = [dict(r) for r in raw]
    print(f"Loaded {len(rows)} DB entries")

    candidates = [r for r in rows if _is_candidate(r)]
    if args.limit:
        candidates = candidates[:args.limit]
    print(f"Candidates (skip Eigenname + subtitle-only): {len(candidates)}")

    cache = Cache(CACHE_FILE)
    already_cached = sum(1 for r in candidates
                         if cache.get(_to_slug(r.get("word","")))[0])
    print(f"Already in cache: {already_cached}")

    # ---- Fetch ----------------------------------------------------------- #
    results: dict[int, str] = {}   # row_id → definition

    if args.from_cache_only:
        print("Cache-only mode — no HTTP requests.")
        hits = 0
        for r in candidates:
            row_id = r["id"]
            word   = (r.get("word")  or "").strip()
            lemma  = (r.get("lemma") or "").strip()
            defn = None
            for slug in dict.fromkeys(filter(None, [_to_slug(word), _to_slug(lemma)])):
                found, val = cache.get(slug)
                if found and val:
                    defn = val
                    break
            if defn:
                results[row_id] = defn
                hits += 1
        print(f"Cache hits applied: {hits} / {len(candidates)} candidates")
    else:
        print(f"Fetching with {args.workers} workers, {args.delay}s delay …")
        try:
            with ThreadPoolExecutor(max_workers=args.workers) as pool:
                futures = {
                    pool.submit(_lookup, r, cache, args.delay): r
                    for r in candidates
                }
                done = 0
                hits = 0
                for fut in as_completed(futures):
                    row_id, defn = fut.result()
                    done += 1
                    if defn:
                        results[row_id] = defn
                        hits += 1
                    if done % 100 == 0 or done == len(candidates):
                        print(f"  {done}/{len(candidates)} fetched, {hits} hits")
                        cache.flush()
        except KeyboardInterrupt:
            print("\nInterrupted — saving cache …")
        finally:
            cache.flush()

    print(f"\nHurraki hits: {hits} / {len(candidates)} candidates")

    if not results:
        print("No new definitions found.")
        con.close()
        return 0

    # ---- Write ----------------------------------------------------------- #
    row_by_id = {r["id"]: r for r in rows}
    updated = 0

    for row_id, defn in results.items():
        r = row_by_id[row_id]
        try:
            enrich = json.loads(r.get("enrichment_json") or "{}")
            meta   = json.loads(r.get("metadata_json")   or "{}")
        except (json.JSONDecodeError, TypeError):
            enrich, meta = {}, {}

        # Store separately for the Dart easy-mode display
        enrich["hurraki_definition"] = [defn]

        # Prepend Hurraki to definitions[] so it becomes the primary definition
        existing = [d for d in (enrich.get("definitions") or []) if d != defn]
        enrich["definitions"] = [defn] + existing

        # Tag source
        srcs = list(meta.get("sources") or [])
        if SOURCE_TAG not in srcs:
            srcs.append(SOURCE_TAG)
            meta["sources"] = srcs

        if not args.dry_run:
            con.execute(
                "UPDATE words SET enrichment_json=?, metadata_json=? WHERE id=?",
                (json.dumps(enrich, ensure_ascii=False),
                 json.dumps(meta,   ensure_ascii=False),
                 row_id),
            )
        updated += 1

    if not args.dry_run:
        con.commit()

    print(f"Updated {updated} entries with Hurraki definitions")

    con.close()

    if not args.dry_run and updated > 0:
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
