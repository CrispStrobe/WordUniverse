"""Extract example sentences for DB words from Project Gutenberg German children's books.

Source: https://www.gutenberg.org/ebooks/bookshelf/376 — all books are public domain
(pre-1927) and freely usable without restriction.

For each DB word, sentences containing that word (whole-word, case-insensitive) are
collected from the corpus.  Up to MAX_PER_WORD sentences are stored in
  metadata_json.gutenberg_examples = ["Satz1", "Satz2", …]

Sentence requirements:
  - 5–25 words
  - Contains the DB word or lemma as a whole word (regex \\b match)
  - No URLs, chapter/verse headings, or Gutenberg header/footer noise
  - Not a duplicate of an already-stored sentence

Books are cached under sources/gutenberg/ and only downloaded once.

Usage:
  python add_gutenberg_examples.py [--db grundwortschatz.db] [--no-compress]
                                    [--dry-run] [--max-per-word N] [--limit-books N]
                                    [--redownload] [--build-corpus-db]
                                    [--push-to-hf HF_REPO_ID]

HF upload example:
  python add_gutenberg_examples.py --build-corpus-db \\
      --push-to-hf CrispStrobe/german-childrens-lit-sentences
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

# macOS ships with an outdated cert bundle; Gutenberg uses a valid cert so
# we create a context that loads the system's CA store.
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

DEFAULT_DB    = HERE / "grundwortschatz.db"
WORK_DB       = Path("/tmp/dbpatch_gutenberg/working.db")
DB_GZ         = REPO / "assets" / "grundwortschatz.db.gz"
CACHE_DIR     = HERE / "sources" / "gutenberg"

MAX_PER_WORD  = 50
MAX_PER_BOOK  = 5
MIN_WORDS     = 5
MAX_WORDS     = 25

HEADERS = {
    "User-Agent": "Mozilla/5.0 (compatible; VocPipeline/1.0; +https://github.com/example/voc)",
    "Accept": "text/plain",
}

# All 80 books from https://www.gutenberg.org/ebooks/bookshelf/376
# Verified by paging through all 4 pages of the shelf. All German-language,
# all pre-1927, all public domain.
BOOK_IDS = [
    # --- Gutenberg DE Kinderbuch shelf (bookshelf/376) ---
    # NOTE: IDs 20051, 20050, 21798, 20684, 21148, 21149 are LibriVox audio-only
    # recordings with no plain text on Gutenberg. Replaced/covered below.

    # --- Page 1 (1–25) ---
    # 20051 / 20050: Grimm audio → use 77905 (Deutsche Märchen, text ed. 1921)
    77905,  # Deutsche Märchen — Jacob & Wilhelm Grimm (text, 1921 ed.)
    27220,  # Himmelsvolk — Waldemar Bonsels
    19636,  # Bildergeschichten — Wilhelm Busch
    24571,  # Der Struwwelpeter — Heinrich Hoffmann
    23787,  # Märchen-Sammlung — Ludwig Bechstein
    # 21798: Winnetou I — audio-only on Gutenberg, no text version available; omitted
    39619,  # Trotzkopf als Grossmutter — Suze La Chapelle-Roobol
    23393,  # Japanische Märchen
    22570,  # Wo Gritlis Kinder hingekommen sind — Johanna Spyri
    21021,  # Die Biene Maja und ihre Abenteuer — Waldemar Bonsels
    22516,  # Ehstnische Märchen. Zweite Hälfte — Kreutzwald
    38972,  # Eskimomärchen
    22209,  # Siegfried, der Held — Rudolf Herzog
    22413,  # Alaeddin und die Wunderlampe — Curt Moreck
    17161,  # Max und Moritz — Wilhelm Busch (covers 21148 + 21149 audio eds.)
    25722,  # Leben und Schicksale des Katers Rosaurus — Amalie Winter
    # 20684: Mondfahrt audio → 31204 (Märchenspiel text) already in list below
    27206,  # Neugesammelte Volkssagen aus dem Lande Baden
    19778,  # Alice's Abenteuer im Wunderland — Carroll (tr. Zimmermann)
    31114,  # Wunderbare Reise des kleinen Nils Holgersson — Lagerlöf (tr.)
    31281,  # 500 Rätsel und Rätselscherze — Joseph Frick
    30165,  # Die Abenteuer Tom Sawyers — Twain (German tr.)
    19790,  # Der Schimmelreiter — Theodor Storm
    19163,  # Märchen für Kinder — H. C. Andersen
    # --- Page 2 (26–50) ---
    6341,   # Nachtstücke — E. T. A. Hoffmann
    7500,   # Heidis Lehr- und Wanderjahre — Johanna Spyri
    35794,  # Märchen und Erzählungen für Anfänger. Erster Teil
    17362,  # Der Goldene Topf — E. T. A. Hoffmann
    31309,  # Der Trotzkopf — Emmy von Rhoden
    37940,  # Rübezahl — Rosalie Koch
    13732,  # Das liebe Nest — Paula Dehmel
    14221,  # Aladdin und die Wunderlampe — Ludwig Fulda
    4501,   # Gockel, Hinkel und Gackeleia — Clemens Brentano
    21658,  # Ehstnische Märchen — Friedrich Reinhold Kreutzwald
    6640,   # Märchen-Almanach 1828 — Wilhelm Hauff
    6638,   # Märchen-Almanach 1826 — Wilhelm Hauff
    30084,  # Norwegische Volksmährchen vol. 2 — Asbjørnsen & Moe
    25530,  # Die Nymphe des Brunnens — Johann Karl August Musäus
    9200,   # Klein Zaches, genannt Zinnober — E. T. A. Hoffmann
    19733,  # Das kleine Dummerle — Agnes Sapper
    32034,  # König Nußknacker und der arme Reinhold — Heinrich Hoffmann
    7512,   # Heidi kann brauchen, was es gelernt hat — Johanna Spyri
    6641,   # Märchen und Sagen — Ernst Moritz Arndt
    31204,  # Peterchens Mondfahrt: Ein Märchenspiel — Gerdt von Bassewitz
    31459,  # Onkel Tom's Hütte Bd. 1 — Harriet Beecher Stowe (German tr.)
    8392,   # Hin und Her: Ein Buch für die Kinder — Henry H. Fick
    9859,   # Vom This, der doch etwas wird — Johanna Spyri
    37202,  # Kasperle auf Burg Himmelhoch — Josephine Siebe
    # --- Page 3 (51–75) ---
    20780,  # Heimatlos — Johanna Spyri
    7511,   # Heidis Lehr- und Wanderjahre (alt. ed.) — Johanna Spyri
    28279,  # Woher die Kindlein kommen — Hans Hoppeler
    24413,  # Tante Toni und ihre Bande — Alberta von Brochowska
    6639,   # Märchen-Almanach 1827 — Wilhelm Hauff
    29796,  # Norwegische Volksmährchen vol. 1 — Asbjørnsen & Moe
    36813,  # Kasperle auf Reisen — Josephine Siebe
    40327,  # Rübezahl — Rudolf Reichhardt
    9861,   # Was die Großmutter gelehrt hat — Johanna Spyri
    9860,   # Moni der Geißbub — Johanna Spyri
    2322,   # Hans Huckebein — Wilhelm Busch
    9158,   # Fabeln und Erzählungen — Gotthold Ephraim Lessing
    31213,  # Schlupps, der Handwerksbursch — Clara Berg
    6724,   # Kater Martinchen — Ernst Moritz Arndt
    7888,   # Wie Wiselis Weg gefunden wird — Johanna Spyri
    9375,   # Ausgewählte Fabeln — Gotthold Ephraim Lessing
    19971,  # Hansi — Ida Frohnmeyer
    19716,  # Hundert neue Rätsel — Angela Döring
    2380,   # Das Märchen von dem Myrtenfräulein — Clemens Brentano
    13451,  # Der Mann im Mond — Wilhelm Hauff
    8917,   # Von Kindern und Katzen — Theodor Storm
    8923,   # Die Regentrude — Theodor Storm
    8915,   # Hinzelmeier — Theodor Storm
    8919,   # Pole Poppenspäler — Theodor Storm
    # --- Page 4 (76–80) ---
    # 21148 / 21149: Max und Moritz audio → 17161 already covers it above
    19789,  # Der kleine Häwelmann — Theodor Storm
    19791,  # Der Struwwelpeter (alt. ed.) — Heinrich Hoffmann
    19792,  # Der Struwwelpeter (alt. ed. 2) — Heinrich Hoffmann
]

ALL_IDS = list(dict.fromkeys(BOOK_IDS))  # deduplicate, preserve order

# ---------------------------------------------------------------------------
# German sentence splitter
# ---------------------------------------------------------------------------

# German abbreviations that end with a period but are NOT sentence ends
_ABBREVS = frozenset({
    "Dr", "Prof", "Hr", "Fr", "Hrn", "Frn", "St", "Str", "evtl", "usw",
    "bzw", "z.B", "d.h", "u.a", "etc", "ca", "Nr", "Bd", "Abs", "Jan",
    "Feb", "Mär", "Apr", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez",
    "Kap", "S", "Abb", "Tab", "Sp", "vgl",
})
_RE_ABBREV = re.compile(
    r"\b(" + "|".join(re.escape(a) for a in _ABBREVS) + r")\.",
    re.IGNORECASE,
)

# Split on sentence-ending punctuation followed by whitespace + uppercase or digit
_RE_SENT_SPLIT = re.compile(r'(?<=[.!?…»"\'»])\s+(?=[A-ZÄÖÜ\"\'])')

# Noise patterns — skip sentences matching these
_RE_NOISE = [
    re.compile(r'https?://'),
    re.compile(r'www\.'),
    re.compile(r'Project Gutenberg', re.I),
    re.compile(r'^\s*[IVXivx]+\.?\s+'),        # Roman numeral headings
    re.compile(r'^\s*Kapitel\b', re.I),         # chapter headings
    re.compile(r'^\s*\d+\.\s*$'),               # bare number lines
    re.compile(r'[*_]'),                         # Markdown / underscore emphasis
    re.compile(r'\[.*?\]'),                      # editorial notes [Footnote...]
    re.compile(r'@'),
    re.compile(r'^\s*[A-ZÄÖÜ][^.!?]*:\s+\d'),  # "Kapitel: Text 61 VII." patterns
    re.compile(r'\d{2,}'),                       # sentences with multi-digit numbers
    re.compile(r'Mark\b'),                       # old currency references
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
    """Split German prose into sentences."""
    # Protect known abbreviations by replacing their period temporarily
    protected = _RE_ABBREV.sub(lambda m: m.group(0).replace(".", "\x00"), text)

    # Split
    raw = _RE_SENT_SPLIT.split(protected)

    # Restore and clean
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

    # Try several URL patterns Gutenberg uses
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
            # Try utf-8, fall back to latin-1
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
                    help="Also write all clean sentences to sources/gutenberg_corpus.db")
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
    # (multiple entries may share a lowercase form)
    word_index: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        w = (r.get("word") or "").strip().lower()
        l = (r.get("lemma") or "").strip().lower()
        if w:
            word_index[w].append(r)
        if l and l != w:
            word_index[l].append(r)

    # Regex per word (whole-word, case-insensitive) — built lazily
    word_re: dict[str, re.Pattern] = {}
    def get_re(w: str) -> re.Pattern:
        if w not in word_re:
            word_re[w] = re.compile(r'\b' + re.escape(w) + r'\b', re.IGNORECASE)
        return word_re[w]

    # Collect sentences per row_id
    collected: dict[int, list[str]] = defaultdict(list)

    book_ids = ALL_IDS[:args.limit_books] if args.limit_books else ALL_IDS
    print(f"Processing {len(book_ids)} books …")

    # Optional standalone corpus DB
    corpus_con: sqlite3.Connection | None = None
    if args.build_corpus_db:
        corpus_path = HERE / "sources" / "gutenberg_corpus.db"
        corpus_con = sqlite3.connect(str(corpus_path))
        corpus_con.execute("""
            CREATE TABLE IF NOT EXISTS books (
                book_id   INTEGER PRIMARY KEY,
                title     TEXT,
                author    TEXT,
                language  TEXT DEFAULT 'de',
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

        # Extract metadata from raw header before stripping
        raw_header = text[:3000]
        text = strip_gutenberg_wrapper(text)
        sents = split_sentences(text)
        usable = [s for s in sents
                  if is_clean(s)
                  and MIN_WORDS <= len(s.split()) <= MAX_WORDS]

        if corpus_con is not None:
            # Extract title/author from Gutenberg header
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
        book_count: dict[int, int] = {}  # per-book sentence count per word
        for sent in usable:
            # Quality filter for learner-facing examples:
            # keep only short sentences without commas (corpus DB is unaffected)
            if len(sent.split()) > args.max_example_words or "," in sent:
                continue
            sent_lower = sent.lower()
            # Find which DB words appear in this sentence
            for word_lc, entry_list in word_index.items():
                if len(word_lc) < 4:
                    continue  # skip very short forms (articles, prepositions)
                if word_lc not in sent_lower:
                    continue  # fast pre-filter
                if not get_re(word_lc).search(sent):
                    continue  # whole-word check
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
        time.sleep(0.3)  # polite delay between book downloads

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

    # ---- HF upload ------------------------------------------------------- #
    if args.push_to_hf:
        _push_corpus_to_hf(
            HERE / "sources" / "gutenberg_corpus.db",
            args.push_to_hf,
        )

    print("Done.")
    return 0


def _push_corpus_to_hf(corpus_path: Path, repo_id: str) -> None:
    """Upload complete corpus DB (SQLite + Parquet) to Hugging Face Datasets.

    The SQLite file is uploaded as-is so anyone can download it and run
    arbitrary SQL queries against the full sentence corpus.  The Parquet
    export enables native HF datasets / streaming access.
    """
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
    wc_min, wc_max, wc_mean = int(df["word_count"].min()), int(df["word_count"].max()), df["word_count"].mean()
    print(f"  {n_sents:,} sentences, {n_books} books")

    # Parquet for HF native access
    parquet_path = corpus_path.with_suffix(".parquet")
    df.to_parquet(parquet_path, index=False)
    print(f"  Parquet: {parquet_path.stat().st_size // 1024} KB")

    # README — prefer the hand-written one next to this script
    readme_path = corpus_path.parent / "gutenberg_README.md"
    if readme_path.exists():
        readme_bytes = readme_path.read_bytes()
        print(f"  README: {readme_path.name}")
    else:
        # Minimal fallback
        readme_bytes = f"""\
---
language: [de]
license: other
license_name: public-domain
pretty_name: German Children's Literature Sentences (Project Gutenberg)
tags: [german, kinderbuch, gutenberg, sentences]
---

# German Children's Literature Sentences

{n_sents:,} sentences from {n_books} German-language children's books on
[Project Gutenberg](https://www.gutenberg.org/ebooks/bookshelf/376),
all pre-1927, public domain.

## Files

| File | Description |
|---|---|
| `gutenberg_corpus.db` | Complete SQLite DB — books + sentences tables |
| `data/sentences.parquet` | Same data as Parquet for HF datasets / streaming |

## Quick start (SQLite)

```python
import urllib.request, sqlite3
urllib.request.urlretrieve(
    "https://huggingface.co/datasets/{repo_id}/resolve/main/gutenberg_corpus.db",
    "gutenberg_corpus.db")
con = sqlite3.connect("gutenberg_corpus.db")
# find sentences containing a word
rows = con.execute(
    "SELECT sentence FROM sentences WHERE sentence LIKE ?", ("%Hund%",)
).fetchall()
```

## Stats

- **Sentences**: {n_sents:,}
- **Books**: {n_books}
- **Word count**: {wc_min}–{wc_max} (mean {wc_mean:.1f})
""".encode()

    api = HfApi()
    api.create_repo(repo_id=repo_id, repo_type="dataset", exist_ok=True)

    # Upload SQLite DB (primary artifact — full queryable corpus)
    print("  Uploading gutenberg_corpus.db …")
    api.upload_file(
        path_or_fileobj=str(corpus_path),
        path_in_repo="gutenberg_corpus.db",
        repo_id=repo_id,
        repo_type="dataset",
    )

    # Upload Parquet
    print("  Uploading sentences.parquet …")
    api.upload_file(
        path_or_fileobj=str(parquet_path),
        path_in_repo="data/sentences.parquet",
        repo_id=repo_id,
        repo_type="dataset",
    )

    # Upload README
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
