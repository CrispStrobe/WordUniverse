"""Extract example sentences for DB words from Project Gutenberg English children's books.

All books are public domain (pre-1928 US publication date) and freely usable.

For each DB word, sentences containing that word (whole-word, case-insensitive) are
collected from the corpus.  Up to MAX_PER_WORD sentences are stored in
  metadata_json.gutenberg_examples = ["Sent1", "Sent2", …]

Sentence requirements:
  - 5–25 words
  - Contains the DB word or lemma as a whole word (regex \\b match)
  - No URLs, chapter/verse headings, or Gutenberg header/footer noise
  - Not a duplicate of an already-stored sentence

Books are cached under sources/gutenberg/ and only downloaded once.

Usage:
  python add_gutenberg_examples_en.py [--db grundwortschatz_en.db] [--no-compress]
                                       [--dry-run] [--max-per-word N] [--limit-books N]
                                       [--redownload] [--build-corpus-db]
                                       [--push-to-hf HF_REPO_ID]

HF upload example:
  python add_gutenberg_examples_en.py --build-corpus-db \\
      --push-to-hf CrispStrobe/english-childrens-lit-sentences
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import shutil
import sqlite3
import sys
import time
import ssl
import urllib.request
import urllib.error
from collections import defaultdict

try:
    import certifi
    _SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    _SSL_CTX = ssl.create_default_context()
    _SSL_CTX.check_hostname = False
    _SSL_CTX.verify_mode = ssl.CERT_NONE
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

DEFAULT_DB    = HERE / "grundwortschatz_en.db"
WORK_DB       = Path("/tmp/dbpatch_gutenberg_en/working.db")
DB_GZ         = REPO / "assets" / "grundwortschatz_en.db.gz"
CACHE_DIR     = HERE / "sources" / "gutenberg_en"

MAX_PER_WORD  = 50
MAX_PER_BOOK  = 5
MIN_WORDS     = 5
MAX_WORDS     = 25

HEADERS = {
    "User-Agent": "Mozilla/5.0 (compatible; VocPipeline/1.0; +https://github.com/example/voc)",
    "Accept": "text/plain",
}

# English-language children's books from Project Gutenberg, all pre-1928 (US PD).
BOOK_IDS = [
    # --- Lewis Carroll ---
    11,     # Alice's Adventures in Wonderland (1865)
    12,     # Through the Looking-Glass (1871)

    # --- Mark Twain ---
    74,     # The Adventures of Tom Sawyer (1876)
    76,     # Adventures of Huckleberry Finn (1884)
    1837,   # The Prince and the Pauper (1881)
    245,    # A Connecticut Yankee in King Arthur's Court (1889)

    # --- Robert Louis Stevenson ---
    120,    # Treasure Island (1883)
    421,    # Kidnapped (1886)
    623,    # The Black Arrow (1888)
    19722,  # A Child's Garden of Verses (1885)

    # --- Louisa May Alcott ---
    514,    # Little Women (1868)
    1029,   # Little Men (1871)
    2726,   # Eight Cousins (1875)
    3677,   # Jo's Boys (1886)

    # --- Frances Hodgson Burnett ---
    17396,  # The Secret Garden (1911)
    146,    # A Little Princess (1905)
    479,    # Little Lord Fauntleroy (1886)

    # --- E. Nesbit ---
    7429,   # Five Children and It (1902)
    1874,   # The Railway Children (1906)
    877,    # The Story of the Treasure Seekers (1899)
    770,    # The Wouldbegoods (1901)

    # --- L. M. Montgomery ---
    45,     # Anne of Green Gables (1908)
    47,     # Anne of Avonlea (1909)
    51,     # Anne of the Island (1915)

    # --- Rudyard Kipling ---
    236,    # The Jungle Book (1894)
    35997,  # The Second Jungle Book (1895)
    2781,   # Just So Stories (1902)
    2226,   # Kim (1901)

    # --- J. M. Barrie ---
    16,     # Peter Pan in Kensington Gardens (1906)
    26654,  # Peter and Wendy (1911)

    # --- L. Frank Baum (Oz) ---
    55,     # The Wonderful Wizard of Oz (1900)
    33,     # Dorothy and the Wizard in Oz (1908)
    420,    # The Road to Oz (1909)
    517,    # The Emerald City of Oz (1910)
    486,    # The Patchwork Girl of Oz (1913)

    # --- Kenneth Grahame ---
    289,    # The Wind in the Willows (1908)

    # --- Beatrix Potter ---
    14838,  # The Tale of Peter Rabbit (1902)
    14874,  # The Tale of Squirrel Nutkin (1903)
    14970,  # The Tale of Benjamin Bunny (1904)
    15023,  # The Tale of Mrs. Tiggy-Winkle (1905)

    # --- George MacDonald ---
    339,    # The Princess and the Goblin (1872)
    225,    # At the Back of the North Wind (1871)
    583,    # The Light Princess and Other Fairy Tales (1864)

    # --- Andrew Lang (Fairy Books) ---
    503,    # The Blue Fairy Book (1889)
    540,    # The Red Fairy Book (1890)
    558,    # The Green Fairy Book (1892)
    569,    # The Yellow Fairy Book (1894)
    590,    # The Pink Fairy Book (1897)
    25033,  # The Olive Fairy Book (1907)

    # --- Charles Kingsley ---
    1018,   # The Water Babies (1863)

    # --- Anna Sewell ---
    271,    # Black Beauty (1877)

    # --- Mary Mapes Dodge ---
    764,    # Hans Brinker, or The Silver Skates (1865)

    # --- Susan Coolidge ---
    2198,   # What Katy Did (1872)
    2687,   # What Katy Did at School (1873)

    # --- Kate Douglas Wiggin ---
    1164,   # Rebecca of Sunnybrook Farm (1903)

    # --- Gene Stratton-Porter ---
    2290,   # A Girl of the Limberlost (1909)
    2291,   # Freckles (1904)

    # --- Howard Pyle ---
    3697,   # Men of Iron (1892)
    2896,   # Otto of the Silver Hand (1888)

    # --- Nathaniel Hawthorne ---
    5133,   # A Wonder Book for Girls and Boys (1851)
    1021,   # Tanglewood Tales (1853)

    # --- Daniel Defoe ---
    521,    # Robinson Crusoe (1719)

    # --- Jonathan Swift ---
    829,    # Gulliver's Travels (1726)

    # --- H. C. Andersen (English translations) ---
    27200,  # Andersen's Fairy Tales (various translators)
    1597,   # Fairy Tales and Other Stories (translated)

    # --- Classic adventure / historical fiction ---
    3800,   # Treasure of the Sierra Madre (1927) - B. Traven -- skip, not really children's
    # Use these instead:
    6131,   # The Swiss Family Robinson (Wyss, English tr., 1812/1820)
    35,     # The Adventures of Sherlock Holmes (1892) — Conan Doyle, accessible prose
    834,    # The Great Adventures of Sherlock Holmes (stories)

    # --- School and adventure stories ---
    2368,   # Black Finn — Twain extra
    2923,   # The Legend of Sleepy Hollow — Washington Irving (1820)
    13,     # The Song of Hiawatha — Longfellow (1855)
]

ALL_IDS = list(dict.fromkeys(BOOK_IDS))  # deduplicate, preserve order

# ---------------------------------------------------------------------------
# English sentence splitter
# ---------------------------------------------------------------------------

# English abbreviations that end with a period but are NOT sentence ends
_ABBREVS = frozenset({
    "Mr", "Mrs", "Ms", "Dr", "Prof", "Rev", "St", "Jr", "Sr", "Sgt", "Cpl",
    "Lt", "Capt", "Maj", "Gen", "Col", "Pvt", "Cpl", "Pfc", "Spc",
    "Jan", "Feb", "Mar", "Apr", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
    "No", "Vol", "pp", "p", "ed", "eds", "cf", "vs", "etc", "viz", "i.e", "e.g",
    "ca", "approx", "est",
})
_RE_ABBREV = re.compile(
    r"\b(" + "|".join(re.escape(a) for a in sorted(_ABBREVS, key=len, reverse=True)) + r")\.",
    re.IGNORECASE,
)

# Split on sentence-ending punctuation followed by whitespace + uppercase
_RE_SENT_SPLIT = re.compile(r'(?<=[.!?…"\'»])\s+(?=[A-Z"\'])')

# Noise patterns — skip sentences matching these
_RE_NOISE = [
    re.compile(r'https?://'),
    re.compile(r'www\.'),
    re.compile(r'Project Gutenberg', re.I),
    re.compile(r'^\s*[IVXivx]+\.?\s+'),          # Roman numeral headings at start
    re.compile(r'\bCHAPTER\b'),                   # chapter headings anywhere in sentence
    re.compile(r'^\s*\d+\.\s*$'),                 # bare number lines
    re.compile(r'[*_]'),                           # Markdown / underscore emphasis
    re.compile(r'\[.*?\]'),                        # editorial notes [Footnote...]
    re.compile(r'@'),
    re.compile(r'^\s*[A-Z][^.!?]*:\s+\d'),        # "Chapter: Text 61 VII." patterns
    re.compile(r'\d{2,}'),                         # sentences with multi-digit numbers
    re.compile(r'\bshillings?\b|\bpence\b|\bpounds?\b sterling', re.I),  # old currency
    re.compile(r'^\s*(?:THE END|FINIS|APPENDIX|INDEX|PREFACE|CONTENTS)\s*$', re.I),
    re.compile(r'PRODUCED BY|TRANSCRIBED BY|PROOFREAD BY', re.I),
    re.compile(r'\.—'),                            # Gutenberg heading separator (Word.—Word)
]

# Gutenberg header/footer delimiters
_RE_START = re.compile(r'\*\*\*\s*START OF (THE|THIS) PROJECT GUTENBERG', re.I)
_RE_END   = re.compile(r'\*\*\*\s*END OF (THE|THIS) PROJECT GUTENBERG',   re.I)


def strip_gutenberg_wrapper(text: str) -> str:
    """Remove Gutenberg license header and footer."""
    start = _RE_START.search(text)
    if start:
        text = text[start.end():]
    end = _RE_END.search(text)
    if end:
        text = text[:end.start()]
    return text


def split_sentences(text: str) -> list[str]:
    """Split English prose into sentences."""
    protected = _RE_ABBREV.sub(lambda m: m.group(0).replace(".", "\x00"), text)
    raw = _RE_SENT_SPLIT.split(protected)
    sents = []
    for s in raw:
        s = s.replace("\x00", ".").strip()
        s = re.sub(r'\s+', ' ', s)
        sents.append(s)
    return sents


def is_clean(sent: str) -> bool:
    for pat in _RE_NOISE:
        if pat.search(sent):
            return False
    return True


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

def _fetch_book(book_id: int, force: bool) -> str | None:
    """Return plain text of book, or None on failure. Caches locally."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cached = CACHE_DIR / f"{book_id}.txt"

    if cached.exists() and not force:
        return cached.read_text(encoding="utf-8", errors="replace")

    urls = [
        f"https://www.gutenberg.org/files/{book_id}/{book_id}-0.txt",
        f"https://www.gutenberg.org/files/{book_id}/{book_id}.txt",
        f"https://www.gutenberg.org/cache/epub/{book_id}/pg{book_id}.txt",
    ]
    for url in urls:
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=30, context=_SSL_CTX) as resp:
                raw = resp.read()
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = raw.decode("latin-1")
            cached.write_text(text, encoding="utf-8")
            return text
        except urllib.error.HTTPError as e:
            if e.code == 404:
                continue
            print(f"  [warn] {book_id} HTTP {e.code}: {url}", file=sys.stderr)
        except Exception as e:
            print(f"  [warn] {book_id}: {e}", file=sys.stderr)
        time.sleep(0.5)

    return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",           default=str(DEFAULT_DB))
    ap.add_argument("--no-compress",  action="store_true")
    ap.add_argument("--dry-run",      action="store_true")
    ap.add_argument("--max-per-word", type=int, default=MAX_PER_WORD)
    ap.add_argument("--max-per-book", type=int, default=MAX_PER_BOOK,
                    help="Max sentences per word taken from any single book")
    ap.add_argument("--max-example-words", type=int, default=15,
                    help="Max words in a sentence for it to be stored as a word example "
                         "(corpus DB is not affected); sentences with commas are also skipped")
    ap.add_argument("--limit-books",  type=int, default=None,
                    help="Process only the first N books (for testing)")
    ap.add_argument("--redownload",      action="store_true")
    ap.add_argument("--build-corpus-db", action="store_true",
                    help="Also write all clean sentences to sources/gutenberg_corpus_en.db")
    ap.add_argument("--push-to-hf",      default=None, metavar="REPO_ID",
                    help="Push corpus DB to Hugging Face as a dataset (implies --build-corpus-db). "
                         "Requires HF_TOKEN env var or huggingface-cli login.")
    args = ap.parse_args()
    if args.push_to_hf:
        args.build_corpus_db = True

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    # ---- Load DB ---------------------------------------------------------- #
    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row

    rows = con.execute(
        "SELECT id, word, lemma, metadata_json FROM words"
    ).fetchall()
    rows = [dict(r) for r in rows]
    print(f"Loaded {len(rows)} DB entries")

    # Build lookup: lowercase form → list of row dicts
    word_index: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        w = (r.get("word") or "").strip().lower()
        l = (r.get("lemma") or "").strip().lower()
        if w:
            word_index[w].append(r)
        if l and l != w:
            word_index[l].append(r)

    word_re: dict[str, re.Pattern] = {}
    def get_re(w: str) -> re.Pattern:
        if w not in word_re:
            word_re[w] = re.compile(r'\b' + re.escape(w) + r'\b', re.IGNORECASE)
        return word_re[w]

    collected: dict[int, list[str]] = defaultdict(list)

    book_ids = ALL_IDS[:args.limit_books] if args.limit_books else ALL_IDS
    print(f"Processing {len(book_ids)} books …")

    corpus_con: sqlite3.Connection | None = None
    if args.build_corpus_db:
        corpus_path = HERE / "sources" / "gutenberg_corpus_en.db"
        corpus_con = sqlite3.connect(str(corpus_path))
        corpus_con.execute("""
            CREATE TABLE IF NOT EXISTS books (
                book_id   INTEGER PRIMARY KEY,
                title     TEXT,
                author    TEXT,
                language  TEXT DEFAULT 'en',
                license   TEXT DEFAULT 'public domain'
            )
        """)
        corpus_con.execute("""
            CREATE TABLE IF NOT EXISTS sentences (
                id         INTEGER PRIMARY KEY,
                book_id    INTEGER NOT NULL REFERENCES books(book_id),
                sentence   TEXT    NOT NULL,
                word_count INTEGER NOT NULL
            )
        """)
        corpus_con.execute("CREATE INDEX IF NOT EXISTS idx_sent ON sentences(sentence)")
        corpus_con.commit()
        print(f"  Corpus DB: {corpus_path}")

    for book_id in book_ids:
        print(f"  Book {book_id} …", end=" ", flush=True)
        text = _fetch_book(book_id, force=args.redownload)
        if not text:
            print("not found")
            continue

        raw_header = text[:3000]
        text = strip_gutenberg_wrapper(text)
        sents = split_sentences(text)
        usable = [s for s in sents
                  if is_clean(s)
                  and MIN_WORDS <= len(s.split()) <= MAX_WORDS]

        if corpus_con is not None:
            header = raw_header
            title_m  = re.search(r'Title:\s*(.+)', header)
            author_m = re.search(r'Author:\s*(.+)', header)
            corpus_con.execute(
                "INSERT OR IGNORE INTO books (book_id, title, author) VALUES (?,?,?)",
                (book_id,
                 title_m.group(1).strip()  if title_m  else None,
                 author_m.group(1).strip() if author_m else None),
            )
            corpus_con.executemany(
                "INSERT OR IGNORE INTO sentences (book_id, sentence, word_count) VALUES (?,?,?)",
                [(book_id, s, len(s.split())) for s in usable],
            )
            corpus_con.commit()

        hits = 0
        book_count: dict[int, int] = {}
        for sent in usable:
            if len(sent.split()) > args.max_example_words or "," in sent:
                continue
            sent_lower = sent.lower()
            for word_lc, entry_list in word_index.items():
                if len(word_lc) < 4:
                    continue  # skip very short forms (articles, prepositions)
                if word_lc not in sent_lower:
                    continue
                if not get_re(word_lc).search(sent):
                    continue
                for r in entry_list:
                    row_id = r["id"]
                    bucket = collected[row_id]
                    if (len(bucket) < args.max_per_word
                            and book_count.get(row_id, 0) < args.max_per_book
                            and sent not in bucket):
                        bucket.append(sent)
                        book_count[row_id] = book_count.get(row_id, 0) + 1
                        hits += 1
        print(f"{len(usable)} sentences, {hits} hits")
        time.sleep(0.3)

    if corpus_con is not None:
        total_corpus = corpus_con.execute("SELECT COUNT(*) FROM sentences").fetchone()[0]
        print(f"  Corpus DB total sentences: {total_corpus}")
        corpus_con.close()

    print(f"\nWords with Gutenberg examples: {sum(1 for v in collected.values() if v)}")
    total_sents = sum(len(v) for v in collected.values())
    print(f"Total sentences collected: {total_sents}")

    if not collected or args.dry_run:
        if args.dry_run:
            row_by_id = {r["id"]: r for r in rows}
            for row_id, sents in list(collected.items())[:5]:
                entry = row_by_id.get(row_id)
                word = entry["word"] if entry else f"id={row_id}"
                print(f"\n  {word}:")
                for s in sents:
                    print(f"    {s}")
        print("Done (dry-run)." if args.dry_run else "Nothing to write.")
        con.close()
        return 0

    # ---- Write ----------------------------------------------------------- #
    updated = 0
    row_by_id = {r["id"]: r for r in rows}

    for row_id, sents in collected.items():
        if not sents:
            continue
        r = row_by_id.get(row_id)
        if not r:
            continue
        try:
            meta = json.loads(r.get("metadata_json") or "{}")
        except (json.JSONDecodeError, TypeError):
            meta = {}

        existing = meta.get("gutenberg_examples") or []
        new_sents = [s for s in sents if s not in existing]
        if not new_sents:
            continue

        meta["gutenberg_examples"] = (existing + new_sents)[:args.max_per_word]
        srcs = list(meta.get("sources") or [])
        if "GUTENBERG" not in srcs:
            srcs.append("GUTENBERG")
            meta["sources"] = srcs

        con.execute(
            "UPDATE words SET metadata_json = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), row_id),
        )
        updated += 1

    con.commit()
    print(f"Updated {updated} entries with Gutenberg examples")

    con.close()

    print(f"Copying {WORK_DB} → {src_db}")
    shutil.copy2(WORK_DB, src_db)
    if not args.no_compress and DB_GZ.exists():
        print(f"Compressing → {DB_GZ}")
        with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
            shutil.copyfileobj(fi, fo)
        print(f"  {DB_GZ.stat().st_size // 1024} KB written")

    if args.push_to_hf:
        _push_corpus_to_hf(
            HERE / "sources" / "gutenberg_corpus_en.db",
            args.push_to_hf,
        )

    print("Done.")
    return 0


def _push_corpus_to_hf(corpus_path: Path, repo_id: str) -> None:
    """Upload complete corpus DB (SQLite + Parquet) to Hugging Face Datasets."""
    try:
        import pandas as pd
    except ImportError:
        print("ERROR: pandas not installed — pip install pandas pyarrow", file=sys.stderr)
        return
    try:
        from huggingface_hub import HfApi
    except ImportError:
        print("ERROR: huggingface_hub not installed — pip install huggingface-hub",
              file=sys.stderr)
        return

    print(f"\nPushing corpus → Hugging Face: {repo_id}")
    con = sqlite3.connect(str(corpus_path))

    df = pd.read_sql_query("""
        SELECT s.id, s.book_id, b.title, b.author, b.language, b.license,
               s.sentence, s.word_count
        FROM sentences s
        LEFT JOIN books b USING (book_id)
        ORDER BY s.book_id, s.id
    """, con)
    con.close()

    n_sents = len(df)
    n_books = df["book_id"].nunique()
    wc_min, wc_max = int(df["word_count"].min()), int(df["word_count"].max())
    wc_mean = df["word_count"].mean()
    print(f"  {n_sents:,} sentences, {n_books} books")

    parquet_path = corpus_path.with_suffix(".parquet")
    df.to_parquet(parquet_path, index=False)
    print(f"  Parquet: {parquet_path.stat().st_size // 1024} KB")

    readme_path = corpus_path.parent / "gutenberg_en_README.md"
    if readme_path.exists():
        readme_bytes = readme_path.read_bytes()
        print(f"  README: {readme_path.name}")
    else:
        readme_bytes = f"""\
---
language: [en]
license: other
license_name: public-domain
pretty_name: English Children's Literature Sentences (Project Gutenberg)
tags: [english, childrens-literature, gutenberg, sentences]
---

# English Children's Literature Sentences

{n_sents:,} sentences from {n_books} English-language children's books on
[Project Gutenberg](https://www.gutenberg.org/), all pre-1928 US publication date,
public domain.

## Files

| File | Description |
|---|---|
| `gutenberg_corpus_en.db` | Complete SQLite DB — books + sentences tables |
| `data/sentences.parquet` | Same data as Parquet for HF datasets / streaming |

## Quick start (SQLite)

```python
import urllib.request, sqlite3
urllib.request.urlretrieve(
    "https://huggingface.co/datasets/{repo_id}/resolve/main/gutenberg_corpus_en.db",
    "gutenberg_corpus_en.db")
con = sqlite3.connect("gutenberg_corpus_en.db")
rows = con.execute(
    "SELECT sentence FROM sentences WHERE sentence LIKE ?", ("%beautiful%",)
).fetchall()
```

## Stats

- **Sentences**: {n_sents:,}
- **Books**: {n_books}
- **Word count**: {wc_min}–{wc_max} (mean {wc_mean:.1f})
""".encode()

    api = HfApi()
    api.create_repo(repo_id=repo_id, repo_type="dataset", exist_ok=True)

    print("  Uploading gutenberg_corpus_en.db …")
    api.upload_file(
        path_or_fileobj=str(corpus_path),
        path_in_repo="gutenberg_corpus_en.db",
        repo_id=repo_id,
        repo_type="dataset",
    )

    print("  Uploading sentences.parquet …")
    api.upload_file(
        path_or_fileobj=str(parquet_path),
        path_in_repo="data/sentences.parquet",
        repo_id=repo_id,
        repo_type="dataset",
    )

    print("  Uploading README.md …")
    api.upload_file(
        path_or_fileobj=readme_bytes,
        path_in_repo="README.md",
        repo_id=repo_id,
        repo_type="dataset",
    )

    print(f"  Done → https://huggingface.co/datasets/{repo_id}")


if __name__ == "__main__":
    sys.exit(main())
