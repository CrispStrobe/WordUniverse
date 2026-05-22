"""Fetch the freely-redistributable EN source wordlists into sources/.

Auto-fetches:
- UK National Curriculum Appendix 1 spelling lists (OGL v3.0)
- Dolch 220 sight words (public domain, multiple mirrors)
- Fry 1000 instant words (public domain)
- HermitDave en_50k frequency list (CC-BY-SA)
- CMU Pronouncing Dictionary (BSD-style)
- Wikipedia "Lists of common misspellings" (CC-BY-SA)

Prints manual instructions for the sources that need login/scraping/PDF:
- AoA-Kuperman 2012

See README.md for details and target filenames.
"""
import os
import sys
import urllib.request
import urllib.error
import re
import csv
from pathlib import Path

SRC = Path(__file__).parent / "sources"
SRC.mkdir(exist_ok=True)

# ---------------------------------------------------------------------------
# small download helper
# ---------------------------------------------------------------------------

UA = "Mozilla/5.0 (compatible; voc-pipeline/1.0; +https://github.com/CrispStrobe/voc)"

def fetch(url: str, dst: Path, *, max_mb: int = 50, force: bool = False) -> bool:
    """Download url -> dst with a User-Agent. Skip if dst exists and not force.
    Returns True on success."""
    if dst.exists() and not force:
        size_kb = dst.stat().st_size // 1024
        print(f"  [skip] {dst.name} already present ({size_kb} KB)")
        return True
    print(f"  [get ] {url}")
    print(f"         -> {dst}")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read(max_mb * 1024 * 1024 + 1)
        if len(data) > max_mb * 1024 * 1024:
            print(f"         !! exceeded {max_mb} MB cap, aborting")
            return False
        dst.write_bytes(data)
        print(f"         ok ({len(data) // 1024} KB)")
        return True
    except urllib.error.URLError as e:
        print(f"         !! failed: {e}")
        return False
    except Exception as e:
        print(f"         !! error: {e}")
        return False

# ---------------------------------------------------------------------------
# 1. HermitDave en_50k frequency list (CC-BY-SA)
# ---------------------------------------------------------------------------

def fetch_hermitdave_en_50k():
    print("\n=== HermitDave en_50k ===")
    url = ("https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/"
           "content/2018/en/en_50k.txt")
    fetch(url, SRC / "en_50k_hermitdave.txt")

# ---------------------------------------------------------------------------
# 2. CMU Pronouncing Dictionary
# ---------------------------------------------------------------------------

def fetch_cmudict():
    print("\n=== CMU Pronouncing Dictionary ===")
    url = "https://raw.githubusercontent.com/cmusphinx/cmudict/master/cmudict.dict"
    fetch(url, SRC / "cmudict.txt")

# ---------------------------------------------------------------------------
# 3. UK National Curriculum Appendix 1 (OGL v3.0)
# ---------------------------------------------------------------------------

UK_APPENDIX_URL = (
    "https://assets.publishing.service.gov.uk/government/uploads/system/"
    "uploads/attachment_data/file/239784/English_Appendix_1_-_Spelling.pdf"
)

# Curated from the Department for Education Appendix 1 PDF. Years 1 and 2 use
# common-exception words from the appendix; years 3/4 and 5/6 use the statutory
# word lists. We keep the source PDF beside the CSV for provenance.
UK_YEAR_WORDS = {
    1: """
        the a do to today of said says are were was is his has i you your they
        be he me she we no go so by my here there where love come some one once
        ask friend school put push pull full house our
    """,
    2: """
        door floor poor because find kind mind behind child children wild climb
        most only both old cold gold hold told every everybody even great break
        steak pretty beautiful after fast last past father class grass pass
        plant path bath hour move prove improve sure sugar eye could should
        would who whole any many clothes busy people water again half money mr
        mrs parents christmas
    """,
    3: """
        accident accidentally actual actually address answer appear arrive
        believe bicycle breath breathe build busy business calendar caught
        centre century certain circle complete consider continue decide describe
        different difficult disappear early earth eight eighth enough exercise
        experience experiment extreme famous favourite february forward forwards
        fruit grammar group guard guide heard heart height history imagine
        increase important interest island knowledge learn length library
        material medicine mention minute natural naughty notice occasion
        occasionally often opposite ordinary particular peculiar perhaps popular
        position possession possess possible potatoes pressure probably promise
        purpose quarter question recent regular reign remember sentence separate
        special straight strange strength suppose surprise therefore though
        although thought through various weight woman women
    """,
    4: """
        accident accidentally actual actually address answer appear arrive
        believe bicycle breath breathe build busy business calendar caught
        centre century certain circle complete consider continue decide describe
        different difficult disappear early earth eight eighth enough exercise
        experience experiment extreme famous favourite february forward forwards
        fruit grammar group guard guide heard heart height history imagine
        increase important interest island knowledge learn length library
        material medicine mention minute natural naughty notice occasion
        occasionally often opposite ordinary particular peculiar perhaps popular
        position possession possess possible potatoes pressure probably promise
        purpose quarter question recent regular reign remember sentence separate
        special straight strange strength suppose surprise therefore though
        although thought through various weight woman women
    """,
    5: """
        accommodate accompany according achieve aggressive amateur ancient
        apparent appreciate attached available average awkward bargain bruise
        category cemetery committee communicate community competition conscience
        conscious controversy convenience correspond criticise curiosity definite
        desperate determined develop dictionary disastrous embarrass environment
        equip equipped equipment especially exaggerate excellent existence
        explanation familiar foreign forty frequently government guarantee
        harass hindrance identity immediate immediately individual interfere
        interrupt language leisure lightning marvellous mischievous muscle
        necessary neighbour nuisance occupy occur opportunity parliament persuade
        physical prejudice privilege profession programme pronunciation queue
        recognise recommend relevant restaurant rhyme rhythm sacrifice secretary
        shoulder signature sincere sincerely soldier stomach sufficient suggest
        symbol system temperature thorough twelfth variety vegetable vehicle yacht
    """,
    6: """
        accommodate accompany according achieve aggressive amateur ancient
        apparent appreciate attached available average awkward bargain bruise
        category cemetery committee communicate community competition conscience
        conscious controversy convenience correspond criticise curiosity definite
        desperate determined develop dictionary disastrous embarrass environment
        equip equipped equipment especially exaggerate excellent existence
        explanation familiar foreign forty frequently government guarantee
        harass hindrance identity immediate immediately individual interfere
        interrupt language leisure lightning marvellous mischievous muscle
        necessary neighbour nuisance occupy occur opportunity parliament persuade
        physical prejudice privilege profession programme pronunciation queue
        recognise recommend relevant restaurant rhyme rhythm sacrifice secretary
        shoulder signature sincere sincerely soldier stomach sufficient suggest
        symbol system temperature thorough twelfth variety vegetable vehicle yacht
    """,
}

def write_uk_curriculum():
    print("\n=== UK National Curriculum Appendix 1 (OGL v3.0) ===")
    pdf = SRC / "uk_english_appendix_1_spelling.pdf"
    fetch(UK_APPENDIX_URL, pdf)
    out = SRC / "uk_y1_y6_statutory.csv"
    if out.exists():
        print(f"  [skip] {out.name} already present")
        return

    rows = []
    seen = set()
    for year, blob in UK_YEAR_WORDS.items():
        for word in re.findall(r"[a-z]+", blob.lower()):
            key = (word, year)
            if key not in seen:
                rows.append({"word": word, "year": year})
                seen.add(key)

    with out.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["word", "year"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"  wrote {len(rows)} rows to {out.name}")

# ---------------------------------------------------------------------------
# 3. Dolch 220 sight words (public domain)
# ---------------------------------------------------------------------------

# Embedded directly — public domain, fewer than 250 short tokens. Avoids the
# risk of any single upstream mirror disappearing.
DOLCH_BY_GRADE = {
    "pre_primer": [
        "a", "and", "away", "big", "blue", "can", "come", "down", "find",
        "for", "funny", "go", "help", "here", "I", "in", "is", "it", "jump",
        "little", "look", "make", "me", "my", "not", "one", "play", "red",
        "run", "said", "see", "the", "three", "to", "two", "up", "we",
        "where", "yellow", "you",
    ],
    "primer": [
        "all", "am", "are", "at", "ate", "be", "black", "brown", "but",
        "came", "did", "do", "eat", "four", "get", "good", "have", "he",
        "into", "like", "must", "new", "no", "now", "on", "our", "out",
        "please", "pretty", "ran", "ride", "saw", "say", "she", "so",
        "soon", "that", "there", "they", "this", "too", "under", "want",
        "was", "well", "went", "what", "white", "who", "will", "with", "yes",
    ],
    "grade_1": [
        "after", "again", "an", "any", "as", "ask", "by", "could", "every",
        "fly", "from", "give", "going", "had", "has", "her", "him", "his",
        "how", "just", "know", "let", "live", "may", "of", "old", "once",
        "open", "over", "put", "round", "some", "stop", "take", "thank",
        "them", "then", "think", "walk", "were", "when",
    ],
    "grade_2": [
        "always", "around", "because", "been", "before", "best", "both",
        "buy", "call", "cold", "does", "don't", "fast", "first", "five",
        "found", "gave", "goes", "green", "its", "made", "many", "off",
        "or", "pull", "read", "right", "sing", "sit", "sleep", "tell",
        "their", "these", "those", "upon", "us", "use", "very", "wash",
        "which", "why", "wish", "work", "would", "write", "your",
    ],
    "grade_3": [
        "about", "better", "bring", "carry", "clean", "cut", "done", "draw",
        "drink", "eight", "fall", "far", "full", "got", "grow", "hold",
        "hot", "hurt", "if", "keep", "kind", "laugh", "light", "long",
        "much", "myself", "never", "only", "own", "pick", "seven", "shall",
        "show", "six", "small", "start", "ten", "today", "together", "try",
        "warm",
    ],
}

GRADE_NUMERIC = {
    "pre_primer": 1,  # K
    "primer": 1,      # K-1
    "grade_1": 1,
    "grade_2": 2,
    "grade_3": 3,
}

def write_dolch():
    print("\n=== Dolch 220 sight words (embedded, public domain) ===")
    out = SRC / "dolch_220.csv"
    if out.exists():
        print(f"  [skip] {out.name} already present")
        return
    rows = ["word,dolch_band,grade_hint"]
    for band, words in DOLCH_BY_GRADE.items():
        g = GRADE_NUMERIC[band]
        for w in words:
            rows.append(f"{w},{band},{g}")
    out.write_text("\n".join(rows) + "\n", encoding="utf-8")
    n = sum(len(v) for v in DOLCH_BY_GRADE.values())
    print(f"  wrote {n} rows to {out.name}")

# ---------------------------------------------------------------------------
# 4. Fry 1000 — public domain (frequency-ranked sight words, 10 bands of 100)
# ---------------------------------------------------------------------------

# The Fry list has many community mirrors. We try a couple of GitHub raw
# sources first, fall back to a clear instruction.
FRY_MIRROR_URLS = [
    "https://raw.githubusercontent.com/first20hours/google-10000-english/"
    "master/google-10000-english-usa-no-swears.txt",  # not exactly Fry, but a clean top-1000 sub-list
]

def fetch_fry():
    print("\n=== Fry 1000 (approx, via clean top-10k mirror) ===")
    # Note: the strict Fry-1000 ordering differs from frequency-based top-1000;
    # we use the cleaner top-1000-from-frequency as a stand-in for v1.
    # If you want true Fry, replace sources/fry_1000.csv manually.
    dst = SRC / "fry_top1000_freq.txt"
    if dst.exists():
        print(f"  [skip] {dst.name} already present")
        return
    for url in FRY_MIRROR_URLS:
        ok = fetch(url, dst)
        if ok:
            # Trim to top 1000
            lines = dst.read_text(encoding="utf-8").splitlines()
            top1000 = lines[:1000]
            dst.write_text("\n".join(top1000) + "\n", encoding="utf-8")
            print(f"  trimmed to top 1000 lines")
            return
    print("  !! no mirror worked; obtain Fry 1000 manually as sources/fry_1000.csv (cols: word,band)")

# ---------------------------------------------------------------------------
# 5. Wikipedia "Lists of common misspellings" — scrape via API
# ---------------------------------------------------------------------------

WIKI_API = "https://en.wikipedia.org/w/api.php"
# The wiki has pages like "Wikipedia:Lists of common misspellings/For machines"
# which is a flat list of correct->wrong mappings.

def fetch_common_misspellings():
    print("\n=== Wikipedia commonly misspelled words ===")
    dst = SRC / "commonly_misspelled.csv"
    if dst.exists():
        print(f"  [skip] {dst.name} already present")
        return
    # The "/For machines" subpage is the canonical flat list. The Wikipedia
    # format is "MISSPELLING->CORRECT1,CORRECT2,...", i.e. the left side of
    # the arrow is the typo and the right side is the accepted correction(s).
    title = "Wikipedia:Lists_of_common_misspellings/For_machines"
    url = (f"{WIKI_API}?action=parse&page={urllib.parse.quote(title)}"
           f"&prop=wikitext&format=json")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=60) as resp:
            import json
            data = json.loads(resp.read().decode("utf-8"))
        wikitext = data["parse"]["wikitext"]["*"]
    except Exception as e:
        print(f"  !! fetch failed: {e}")
        print(f"  fallback: download manually and save as {dst}")
        return
    rows = ["misspelling,correct"]
    pattern = re.compile(r"^([A-Za-z][A-Za-z'\-]*)->(.+)$")
    n_pairs = 0
    for line in wikitext.splitlines():
        line = line.strip()
        m = pattern.match(line)
        if not m:
            continue
        misspelling = m.group(1).lower()
        corrects = [c.strip().lower() for c in m.group(2).split(",")]
        for c in corrects:
            if c and re.match(r"^[a-z'\-]+$", c):
                rows.append(f"{misspelling},{c}")
                n_pairs += 1
    if n_pairs == 0:
        print(f"  !! parsed 0 pairs; format may have changed")
        return
    dst.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"  wrote {n_pairs} misspelling->correct pairs to {dst.name}")


# ---------------------------------------------------------------------------
# 6. Norvig spell-errors.txt — MIT code, CC-BY-SA/PD upstream data
# ---------------------------------------------------------------------------

def fetch_norvig_spell_errors():
    """Norvig's spell-errors.txt: 'right: wrong1, wrong2, ...' per line.
    Right side of colon is the CORRECT word; left of the comma-separated list
    are the misspellings. See https://norvig.com/ngrams/.
    """
    print("\n=== Norvig spell-errors ===")
    dst = SRC / "norvig_spell_errors.csv"
    if dst.exists():
        print(f"  [skip] {dst.name} already present")
        return
    src_path = SRC / "norvig_spell_errors.txt"
    if not fetch("https://norvig.com/ngrams/spell-errors.txt", src_path):
        return
    rows = ["misspelling,correct"]
    n_pairs = 0
    for line in src_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        correct, wrongs = line.split(":", 1)
        correct = correct.strip().lower()
        if not re.match(r"^[a-z'\-]+$", correct):
            continue
        for w in wrongs.split(","):
            w = w.strip().lower()
            # Norvig may encode frequency as "wrong*N"; drop the count
            w = re.sub(r"\*\d+$", "", w)
            if w and re.match(r"^[a-z'\-]+$", w) and w != correct:
                rows.append(f"{w},{correct}")
                n_pairs += 1
    if n_pairs == 0:
        print(f"  !! parsed 0 pairs from norvig file; format may have changed")
        return
    dst.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"  wrote {n_pairs} misspelling->correct pairs to {dst.name}")

# ---------------------------------------------------------------------------
# Manual sources — print instructions only
# ---------------------------------------------------------------------------

def print_manual_instructions():
    print("\n" + "=" * 70)
    print("OPTIONAL MANUAL DOWNLOADS — place these in sources/ before running step 01")
    print("=" * 70)
    manual = [
        ("aoa_kuperman.csv",
         "Kuperman et al 2012 age-of-acquisition norms. Cols: word,aoa_mean,aoa_sd.",
         "http://crr.ugent.be/archives/806"),
    ]
    for fname, desc, url in manual:
        path = SRC / fname
        status = "PRESENT" if path.exists() else "MISSING"
        print(f"\n  [{status}] sources/{fname}")
        print(f"     {desc}")
        print(f"     URL: {url}")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print(f"Target directory: {SRC}")
    write_uk_curriculum()
    fetch_hermitdave_en_50k()
    fetch_cmudict()
    write_dolch()
    fetch_fry()
    import urllib.parse  # imported here to keep top imports clean if scrape skipped
    fetch_common_misspellings()
    fetch_norvig_spell_errors()
    print_manual_instructions()
    print("\nDone. After all sources are present, run: python 01_consolidate_en.py")

if __name__ == "__main__":
    import urllib.parse
    main()
