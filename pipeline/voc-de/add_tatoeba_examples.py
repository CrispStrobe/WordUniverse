"""Add child-friendly example sentences from Tatoeba to the DE DB.

Tatoeba is a free collection of sentences and translations.
  License: CC-BY 2.0
  Download: https://downloads.tatoeba.org/exports/per_language/deu/

For each vocabulary entry we select up to MAX_PER_WORD short German sentences
from Tatoeba in which the word (or one of its Wiktionary inflections) appears
as an exact token. Sentences are stored as metadata_json.tatoeba_examples
(list of strings). The Dart layer (GermanWord.fromJson) already prefers
tatoeba_examples over Wiktionary examples when both are present (see
dictionary_database_service.dart).

Sentence quality filters applied:
  - ≤ MAX_WORDS words (default 15) — keeps sentences short and readable
  - No URLs (http/www)
  - No sentences that are mostly punctuation or symbols
  - No sentences starting with a quote/citation marker
  - Prefer sentences where the target word appears early (word position ÷ length)
  - Deduplicated per entry

The deu_sentences.tsv.bz2 file (~50 MB compressed, ~3–5 M sentences) is
downloaded once to sources/ and reused on subsequent runs.

Usage:
  python add_tatoeba_examples.py [--db grundwortschatz.db] [--no-compress]
  python add_tatoeba_examples.py --download          # download only
  python add_tatoeba_examples.py --redownload        # force re-download
  python add_tatoeba_examples.py --max-words 12      # stricter length filter
  python add_tatoeba_examples.py --max-per-word 5    # more examples per word
"""

from __future__ import annotations

import argparse
import bz2
import gzip
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

DEFAULT_DB = HERE / "grundwortschatz.db"
WORK_DB = Path("/tmp/dbpatch_tatoeba/working.db")
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"

SENTENCES_URL = ("https://downloads.tatoeba.org/exports/per_language/deu/"
                 "deu_sentences.tsv.bz2")
SENTENCES_LOCAL = HERE / "sources" / "tatoeba_deu_sentences.tsv.bz2"

SOURCE_TAG = "TATOEBA"
DEFAULT_MAX_WORDS = 15
DEFAULT_MAX_PER_WORD = 3

_RE_URL = re.compile(r"https?://|www\.", re.I)
_RE_JUNK = re.compile(r"^[\W\d]+$")
_STRIP_CHARS = ".,;:!?\"'„“”»«’‘()[]{}"


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

def download_sentences(force: bool = False) -> Path:
    SENTENCES_LOCAL.parent.mkdir(parents=True, exist_ok=True)
    if SENTENCES_LOCAL.exists() and not force:
        size_mb = SENTENCES_LOCAL.stat().st_size / 1_048_576
        print(f"  [skip] {SENTENCES_LOCAL.name} already present ({size_mb:.1f} MB)")
        return SENTENCES_LOCAL
    print(f"Downloading {SENTENCES_URL} …")
    tmp = SENTENCES_LOCAL.with_suffix(".tmp")
    try:
        urllib.request.urlretrieve(SENTENCES_URL, tmp)
    except Exception:
        try:
            subprocess.run(["curl", "-fsSL", SENTENCES_URL, "-o", str(tmp)],
                           check=True)
        except subprocess.CalledProcessError as exc:
            if tmp.exists():
                tmp.unlink()
            raise RuntimeError(f"Download failed: {exc}") from exc
    tmp.rename(SENTENCES_LOCAL)
    size_mb = SENTENCES_LOCAL.stat().st_size / 1_048_576
    print(f"  saved ({size_mb:.1f} MB compressed)")
    return SENTENCES_LOCAL


# ---------------------------------------------------------------------------
# Vocabulary index
# ---------------------------------------------------------------------------

def build_vocab_index(rows: list[sqlite3.Row]) -> dict[str, list[int]]:
    """Return {token_lower: [row_indices]} — one token can map to many rows.

    Three-pass priority exactly like the LiTKey scripts:
      1. headword
      2. lemma
      3. wiktionaryInflections[].form_text values
    """
    # token_lower → set of row indices
    idx: dict[str, set[int]] = defaultdict(set)

    for i, r in enumerate(rows):
        w = (r["word"] or "").strip()
        if w:
            idx[w.lower()].add(i)

    for i, r in enumerate(rows):
        lm = (r["lemma"] or "").strip()
        if lm:
            idx[lm.lower()].add(i)

    for i, r in enumerate(rows):
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except (json.JSONDecodeError, TypeError):
            meta = {}
        for infl in meta.get("wiktionaryInflections") or []:
            if isinstance(infl, dict):
                ft = (infl.get("form_text") or "").strip()
                # skip multi-word or very short inflection strings
                if ft and " " not in ft and len(ft) > 1:
                    idx[ft.lower()].add(i)

    return {k: sorted(v) for k, v in idx.items()}


# ---------------------------------------------------------------------------
# Sentence quality filter
# ---------------------------------------------------------------------------

def is_usable(text: str, max_words: int) -> bool:
    if _RE_URL.search(text):
        return False
    # reject parenthetical-heavy sentences (often citations)
    if text.count("(") + text.count("[") > 1:
        return False
    words = text.split()
    if len(words) < 2 or len(words) > max_words:
        return False
    if _RE_JUNK.match(text):
        return False
    # reject sentences that start with a quotation/citation marker
    if text[0] in ('"', "'", "„", "«", "»", "‟", "❝"):
        return False
    return True


def score_sentence(text: str, token: str) -> float:
    """Lower score = better (shorter and token appears early)."""
    words = text.split()
    n = len(words)
    words_lower = [w.lower().strip(_STRIP_CHARS) for w in words]
    try:
        pos = words_lower.index(token.lower())
    except ValueError:
        pos = n
    # blend of length and token position (earlier = better)
    return n + pos / max(n, 1)


# ---------------------------------------------------------------------------
# Parse sentences and match to vocab
# ---------------------------------------------------------------------------

def collect_sentences(
    tsv_bz2: Path,
    vocab_index: dict[str, list[int]],
    max_words: int,
    max_per_word: int,
) -> dict[int, list[tuple[float, str]]]:
    """Return {row_idx: [(score, sentence), …]} — up to max_per_word+buffer."""

    # We keep a small candidate buffer per row (2× max_per_word) and prune later
    buffer_size = max_per_word * 2
    candidates: dict[int, list[tuple[float, str]]] = defaultdict(list)

    # Build a fast set of all tokens we care about
    all_tokens: set[str] = set(vocab_index.keys())

    print(f"  vocab index: {len(all_tokens)} unique tokens")

    n_sentences = 0
    n_matched = 0

    with bz2.open(tsv_bz2, "rt", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            parts = line.split("\t")
            # per-language file format: id \t lang \t text  (3 cols)
            # fallback: id \t text  (2 cols)
            if len(parts) == 3:
                text = parts[2]
            elif len(parts) == 2:
                text = parts[1]
            else:
                continue

            if not is_usable(text, max_words):
                continue

            n_sentences += 1
            words_lower = {
                w.lower().strip(_STRIP_CHARS)
                for w in text.split()
            }
            matches = words_lower & all_tokens
            if not matches:
                continue

            n_matched += 1
            for token in matches:
                for row_idx in vocab_index[token]:
                    score = score_sentence(text, token)
                    bucket = candidates[row_idx]
                    bucket.append((score, text))
                    # Prune bucket to avoid unbounded memory growth
                    if len(bucket) > buffer_size * 4:
                        bucket.sort(key=lambda x: x[0])
                        candidates[row_idx] = bucket[:buffer_size]

    print(f"  processed {n_sentences} usable sentences; "
          f"{n_matched} matched at least one vocab token")
    return candidates


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", default=str(DEFAULT_DB))
    ap.add_argument("--download", action="store_true")
    ap.add_argument("--redownload", action="store_true")
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--max-words", type=int, default=DEFAULT_MAX_WORDS,
                    help=f"Max words per sentence (default {DEFAULT_MAX_WORDS})")
    ap.add_argument("--max-per-word", type=int, default=DEFAULT_MAX_PER_WORD,
                    help=f"Max sentences stored per word (default {DEFAULT_MAX_PER_WORD})")
    args = ap.parse_args()

    tsv_bz2 = download_sentences(force=args.redownload)
    if args.download:
        return 0

    src_db = Path(args.db)
    if not src_db.exists():
        print(f"ERROR: DB not found: {src_db}", file=sys.stderr)
        return 1

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    print(f"Copying {src_db} → {WORK_DB}")
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row
    rows = con.execute("SELECT id, word, lemma, metadata_json FROM words").fetchall()
    print(f"Loaded {len(rows)} DB entries")

    print("Building vocab token index …")
    vocab_index = build_vocab_index(rows)

    print(f"Scanning Tatoeba sentences "
          f"(max_words={args.max_words}, max_per_word={args.max_per_word}) …")
    candidates = collect_sentences(tsv_bz2, vocab_index,
                                   args.max_words, args.max_per_word)

    # Write best sentences per entry
    updated = 0
    total_sentences_stored = 0
    row_list = [dict(r) for r in rows]

    for row_idx, scored in candidates.items():
        # Sort by score, deduplicate text, take top N
        scored.sort(key=lambda x: x[0])
        seen: set[str] = set()
        best: list[str] = []
        for _, text in scored:
            if text not in seen:
                seen.add(text)
                best.append(text)
            if len(best) >= args.max_per_word:
                break
        if not best:
            continue

        r = row_list[row_idx]
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except (json.JSONDecodeError, TypeError):
            meta = {}

        meta["tatoeba_examples"] = best
        sources = list(meta.get("sources") or [])
        if SOURCE_TAG not in sources:
            sources.append(SOURCE_TAG)
            meta["sources"] = sources

        con.execute(
            "UPDATE words SET metadata_json = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), r["id"]),
        )
        updated += 1
        total_sentences_stored += len(best)

    con.commit()
    con.close()

    print()
    print(f"Updated {updated} entries with Tatoeba examples.")
    print(f"  total sentences stored: {total_sentences_stored}")
    print(f"  avg per entry: {total_sentences_stored / max(updated, 1):.1f}")
    print(f"  entries with no Tatoeba match: {len(rows) - updated}")

    print(f"Copying {WORK_DB} → {src_db}")
    shutil.copy2(WORK_DB, src_db)

    if not args.no_compress:
        if DB_GZ.exists():
            print(f"Compressing {src_db} → {DB_GZ}")
            with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
                shutil.copyfileobj(fi, fo)
            print(f"  {DB_GZ.stat().st_size // 1024} KB written")
        else:
            print(f"  [warn] {DB_GZ} not found", file=sys.stderr)

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
