"""Fetch the freely-redistributable EN source wordlists into sources/.

Auto-fetches:
- Dolch 220 sight words (public domain, multiple mirrors)
- Fry 1000 instant words (public domain)
- HermitDave en_50k frequency list (CC-BY-SA)
- CMU Pronouncing Dictionary (BSD-style)
- Wikipedia "Lists of common misspellings" (CC-BY-SA)

Prints manual instructions for the sources that need login/scraping/PDF:
- Oxford 3000 / Oxford 5000
- English Vocabulary Profile (CEFR)
- UK Year 1-6 statutory spelling lists
- SUBTLEX-US (Brysbaert)
- AoA-Kuperman 2012

See README.md for details and target filenames.
"""
import os
import sys
import urllib.request
import urllib.error
import re
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
    # The "/For machines" subpage is the canonical flat list; format is one
    # line per entry: "correct->wrong1,wrong2,..."
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
    # Parse lines of form "correct->wrong1, wrong2, wrong3"
    rows = ["correct,wrong"]
    pattern = re.compile(r"^([A-Za-z][A-Za-z'\-]*)->(.+)$")
    n_pairs = 0
    for line in wikitext.splitlines():
        line = line.strip()
        m = pattern.match(line)
        if not m:
            continue
        correct = m.group(1).lower()
        wrongs = [w.strip().lower() for w in m.group(2).split(",")]
        for w in wrongs:
            if w and re.match(r"^[a-z'\-]+$", w):
                rows.append(f"{correct},{w}")
                n_pairs += 1
    if n_pairs == 0:
        print(f"  !! parsed 0 pairs; format may have changed")
        return
    dst.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"  wrote {n_pairs} correct-wrong pairs to {dst.name}")

# ---------------------------------------------------------------------------
# Manual sources — print instructions only
# ---------------------------------------------------------------------------

def print_manual_instructions():
    print("\n" + "=" * 70)
    print("MANUAL DOWNLOADS — place these in sources/ before running step 01")
    print("=" * 70)
    manual = [
        ("uk_y1_y6_statutory.csv",
         "UK National Curriculum English Programmes of Study (DfE), "
         "Appendix 1 word lists. Cols: word,year (year in 1-6).",
         "https://www.gov.uk/government/publications/"
         "national-curriculum-in-england-english-programmes-of-study"),
        ("oxford_3000.csv",
         "Oxford 3000 with CEFR levels. Cols: word,cefr (cefr in A1-C2).",
         "https://www.oxfordlearnersdictionaries.com/wordlists/oxford3000-5000"),
        ("oxford_5000.csv",
         "Oxford 5000 with CEFR levels. Cols: word,cefr.",
         "(same source as Oxford 3000)"),
        ("evp_cefr.csv",
         "English Vocabulary Profile (CEFR-aligned). Cols: word,cefr.",
         "https://www.englishprofile.org/ (free institutional sign-up)"),
        ("subtlex_us.csv",
         "SUBTLEX-US with frequency and AoA. Cols: word,freq_count,freq_per_million,aoa.",
         "https://www.ugent.be/pp/experimentele-psychologie/en/research/documents/subtlexus"),
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
    fetch_hermitdave_en_50k()
    fetch_cmudict()
    write_dolch()
    fetch_fry()
    import urllib.parse  # imported here to keep top imports clean if scrape skipped
    fetch_common_misspellings()
    print_manual_instructions()
    print("\nDone. After all sources are present, run: python 01_consolidate_en.py")

if __name__ == "__main__":
    import urllib.parse
    main()
