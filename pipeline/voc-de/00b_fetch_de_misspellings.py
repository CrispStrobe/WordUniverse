"""Fetch German commonly-misspelled-words pairs from Wikipedia and
Wiktionary, both CC-BY-SA 4.0. Replaces the educational-use-only Tacke
materials (`100Fehler.csv` / `300Fehler.csv` / `400Fehler.txt`) with a
fully open-licensed source.

Outputs:
  sources/de_wiki_misspellings.csv      columns: correct,wrong

This feeds the `commonLearnerErrors` field in the consolidated
vocabulary. The pipeline previously consumed the Tacke headwords from
`100Fehler.csv` / `300Fehler.csv` / `400Fehler.txt` via
`01_consolidate_wordlists_csv.py`'s `load_fehler_csv` / `load_plain_txt_list`
loaders. After this run, edit `01_consolidate_wordlists_csv.py` to load
`de_wiki_misspellings.csv` instead (column: `correct`).

Sources:
  - https://de.wikipedia.org/wiki/Wikipedia:Liste_h%C3%A4ufiger_Rechtschreibfehler
    (machine-friendly subpages: "/.*Maschinell.*" and "/.../Übersicht")
  - https://de.wiktionary.org/wiki/Verzeichnis:Deutsch/Fehlschreibungen
    (each entry is a Wiktionary page tagged with the correct form via
    `{{Falschschreibung|<correct>}}` template; the page title IS the
    misspelling).

License: CC-BY-SA 4.0 (Wikipedia / Wiktionary content). Attribution and
ShareAlike apply. See pipeline/LICENSES.md.
"""
from __future__ import annotations
import re
import sys
import json
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path

UA = ("Mozilla/5.0 (compatible; voc-pipeline/1.0; "
      "+https://github.com/CrispStrobe/words-universe)")

HERE = Path(__file__).parent
SRC_DIR = HERE / "sources"
SRC_DIR.mkdir(exist_ok=True)
OUTPUT = SRC_DIR / "de_wiki_misspellings.csv"

WIKI_API_DE = "https://de.wikipedia.org/w/api.php"
WIKT_API_DE = "https://de.wiktionary.org/w/api.php"

# ---------------------------------------------------------------------------
# Wikipedia: "Liste häufiger Rechtschreibfehler" — has machine-friendly subpage
# ---------------------------------------------------------------------------

# Canonical pages with CC-BY-SA German misspelling data.
# Discovered 2026-05-21:
#   - the legacy "Liste häufiger Rechtschreibfehler" was deleted/renamed
#   - the live successor is "Wikipedia:Häufige Falschschreibungen"
#   - "Benutzer:Aka/Fehlerlisten/viele Tippfehler" (and subpages) are
#     much larger; they're maintained by user Aka for the autocorrect bot.
WIKI_PAGES = [
    "Wikipedia:Häufige Falschschreibungen",
    "Benutzer:Aka/Fehlerlisten/viele Tippfehler",
]


def fetch_wiki_pagetext(api_url: str, title: str) -> str | None:
    """Fetch the wikitext source of a single page via MediaWiki API.
    Pass the title in plain Unicode; urlencode handles UTF-8 encoding."""
    params = {
        "action": "parse",
        "page": title,
        "prop": "wikitext",
        "format": "json",
    }
    url = f"{api_url}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        if "parse" not in data:
            print(f"  [warn] no 'parse' in response for {title}: "
                  f"{data.get('error', {}).get('code')}")
            return None
        return data["parse"]["wikitext"]["*"]
    except (urllib.error.HTTPError, urllib.error.URLError, KeyError) as e:
        print(f"  [warn] fetch failed for {title}: {e}")
        return None


def parse_wikipedia_haeufige_falschschreibungen(wikitext: str
                                                ) -> list[tuple[str, str]]:
    """Parser for "Wikipedia:Häufige Falschschreibungen".

    The page is a bulleted list with rows of the form
      * [[Wrong]] > [[Correct]] (Google stats, optional notes)
      * [[Wrong1]], [[Wrong2]] > [[Correct]] (...)
      * [[Wrong]] > [[Correct1]]/[[Correct2]] (...)   (rare)

    Wiki link forms supported:
      [[Page]]              → Page
      [[Page|Display]]      → Page   (the canonical, not the display)
      [[Page (BKS)|Display]] → Page (BKS)
    """
    pairs: list[tuple[str, str]] = []

    def extract_links(s: str) -> list[str]:
        """Return the canonical (left-of-pipe) target of every [[...]] in s."""
        return [m.group(1).strip()
                for m in re.finditer(r"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]", s)]

    # We want only lines starting with "*" (list items) that contain ">"
    # (the wrong-to-correct separator). Skip the rest.
    line_re = re.compile(r"^\*\s*(.+?)\s*>\s*(.+?)\s*$", re.MULTILINE)
    for m in line_re.finditer(wikitext):
        lhs_raw = m.group(1)  # one or more wrong forms, comma-separated
        rhs_raw = m.group(2)  # one or more correct forms, slash-separated

        # Strip trailing "(Google stats…)" parenthetical and any footnotes
        # so we don't accidentally grab links inside notes.
        rhs_raw = re.split(r"\s*\(", rhs_raw, maxsplit=1)[0]
        rhs_raw = re.split(r"\s*<ref", rhs_raw, maxsplit=1)[0]

        wrongs = extract_links(lhs_raw)
        corrects = extract_links(rhs_raw)
        if not wrongs or not corrects:
            continue

        # Each wrong pairs with the FIRST correct (canonical target). Rare
        # multi-correct lines (Slam-Poetry / Slampoetry) — keep the first.
        correct = corrects[0]
        for wrong in wrongs:
            # Keep only sane single-word (or hyphen-compound) tokens
            if (re.fullmatch(r"[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-]{1,40}", wrong)
                    and re.fullmatch(
                        r"[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-]{1,40}", correct)
                    and wrong.lower() != correct.lower()):
                pairs.append((correct, wrong))

    return list({(c, w) for c, w in pairs})


def fetch_wikipedia_pairs() -> list[tuple[str, str]]:
    print("Fetching from de.wikipedia.org…")
    all_pairs: list[tuple[str, str]] = []
    # Primary source: curated "Häufige Falschschreibungen" wikitable.
    title = "Wikipedia:Häufige Falschschreibungen"
    print(f"  - {title}")
    text = fetch_wiki_pagetext(WIKI_API_DE, title)
    if text:
        new = parse_wikipedia_haeufige_falschschreibungen(text)
        print(f"    parsed {len(new)} pairs from wikitable")
        all_pairs.extend(new)
    return all_pairs


# ---------------------------------------------------------------------------
# Wiktionary: "Verzeichnis:Deutsch/Fehlschreibungen"
# Each Fehlschreibung is a page that uses {{Falschschreibung|<correct>}}
# (or {{Falschschreibung|<correct>|<correct2>}}).
# We pull the category members, then for each member, fetch the page
# and extract the correct form from the template.
# ---------------------------------------------------------------------------

WIKT_CATEGORY = "Kategorie:Falschschreibung_(Deutsch)"
RE_FALSCHSCHREIBUNG = re.compile(
    r"\{\{Falschschreibung\|([^|}\n]+)", flags=re.IGNORECASE
)


def fetch_wiktionary_category_members(api_url: str, category: str,
                                      limit_total: int = 5000
                                      ) -> list[str]:
    """List all page titles in the given category, paginated."""
    titles: list[str] = []
    cmcontinue: str | None = None
    while len(titles) < limit_total:
        params = {
            "action": "query",
            "list": "categorymembers",
            "cmtitle": category,
            "cmlimit": "500",
            "cmtype": "page",
            "format": "json",
        }
        if cmcontinue:
            params["cmcontinue"] = cmcontinue
        url = f"{api_url}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.HTTPError, urllib.error.URLError) as e:
            print(f"  [warn] category-members fetch failed: {e}")
            break
        members = data.get("query", {}).get("categorymembers", [])
        titles.extend(m["title"] for m in members)
        cont = data.get("continue", {}).get("cmcontinue")
        if not cont:
            break
        cmcontinue = cont
    return titles


def fetch_wiktionary_pairs(max_pages: int = 3000) -> list[tuple[str, str]]:
    """For each page in the Falschschreibung-DE category, extract the
    {{Falschschreibung|<correct>}} template's correct form. The page
    title is the misspelling."""
    print("Fetching from de.wiktionary.org…")
    titles = fetch_wiktionary_category_members(
        WIKT_API_DE, WIKT_CATEGORY, limit_total=max_pages
    )
    print(f"  category members: {len(titles)}")
    pairs: list[tuple[str, str]] = []

    # Batch-fetch page wikitext (50 titles per request — MediaWiki cap)
    for i in range(0, len(titles), 50):
        batch = titles[i : i + 50]
        params = {
            "action": "query",
            "titles": "|".join(batch),
            "prop": "revisions",
            "rvprop": "content",
            "rvslots": "main",
            "format": "json",
        }
        url = f"{WIKT_API_DE}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.HTTPError, urllib.error.URLError) as e:
            print(f"  [warn] batch {i // 50} fetch failed: {e}")
            continue
        pages = data.get("query", {}).get("pages", {}).values()
        for page in pages:
            wrong = page.get("title", "")
            revs = page.get("revisions", [])
            if not revs:
                continue
            content = (
                revs[0].get("slots", {}).get("main", {}).get("*")
                or revs[0].get("*", "")
            )
            m = RE_FALSCHSCHREIBUNG.search(content)
            if not m:
                continue
            correct = m.group(1).strip()
            if (re.fullmatch(r"[A-Za-zÄÖÜäöüß\-']{2,40}", wrong)
                    and re.fullmatch(r"[A-Za-zÄÖÜäöüß\-']{2,40}", correct)):
                pairs.append((correct, wrong))
        # progress ping every 10 batches
        if (i // 50) % 10 == 0:
            print(f"  processed {min(i + 50, len(titles))}/{len(titles)} pages")

    return pairs


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    wp = fetch_wikipedia_pairs()
    print(f"Wikipedia total: {len(wp)} (correct, wrong) pairs")
    wt = fetch_wiktionary_pairs()
    print(f"Wiktionary total: {len(wt)} (correct, wrong) pairs")

    # Combine + dedup
    combined = set(wp) | set(wt)
    # Sort for deterministic output
    rows = sorted(combined, key=lambda kv: (kv[0].lower(), kv[1].lower()))

    OUTPUT.parent.mkdir(exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8") as f:
        f.write("correct,wrong\n")
        for correct, wrong in rows:
            # CSV-safe: no commas/quotes expected in single words, but be defensive
            c = correct.replace(",", "").replace('"', "")
            w = wrong.replace(",", "").replace('"', "")
            f.write(f"{c},{w}\n")

    print(f"\nWrote {len(rows)} unique pairs to {OUTPUT}")
    print(f"  ({len(set(c for c, _ in rows))} distinct correct headwords)")
    print(f"  ({len(set(w for _, w in rows))} distinct misspellings)")


if __name__ == "__main__":
    main()
