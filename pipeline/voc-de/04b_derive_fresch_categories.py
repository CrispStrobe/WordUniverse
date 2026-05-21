"""Derive FRESCH spelling-strategy categories from the NRW Grundwortschatz
feature taxonomy and attach them to the consolidated vocabulary JSON.

This replaces the historical `532Strategien.csv` source (which overlaid
FRESCH categories on the NRW wordlist via an unidentified third source).
Instead we apply the FRESCH categorization **algorithmically** to the
NRW linguistic-feature flags that the official NRW Grundwortschatz xlsx
*already* contains — produced for us by `conv_xls.py` as
`output_nested.json`.

This makes the FRESCH categorization **our own derivation** from a clean
source (NRW Ministerium für Schule und Bildung — German educational
public administrative material). No third-party FRESCH publication is
consumed.

Pedagogical mapping (NRW feature → FRESCH category):

  Mitsprechen         ← phonematisches Prinzip.mehrteilige Basisgrapheme.*
                        (Diphthonge ei/eu/au, Konsonanten ch/sch/ng/pf,
                         ie, …) — sound‑it‑out patterns once known.
                        Also the **default** when no other category applies.

  Weiterschwingen     ← orthografisches und silbisches Prinzip.
                        Orthographeme.Doppelkonsonanten.* (any double
                        consonant: ss/ll/nn/tt/ck/mm/pp/tz/…). Also
                        kurzes u / kurzes i dialectal markers.

  Ableiten            ← morphematisches Prinzip.Auslautverhärtung.*
                        (b/p, d/t, g/k devoicing) and
                        morphematisches Prinzip.Umlautung.* (ä, ö, ü, äu).

  Merken              ← Artikel.häufig gebrauchte (Funktions‑)Merkwörter
                        (the explicit Merkwort flag), and the default
                        fallback for words with no other pattern marker.

  Wortbausteine       ← morphematisches Prinzip.Präfixe.* (ver/vor/ge/…),
                        morphematisches Prinzip.Auslautverhärtung.Komposita
                        (compound‑word case), and any word that spaCy
                        morphology flags as compound (handled in step 02).

  Großschreibung      ← Artikel.der|die|das present OR
                        zusätzliche Filter.Wortart.Nomen present.

Input:
  output_nested.json           (533 NRW entries with feature flags, from conv_xls.py)
  grundwortschatz_merged.json  (the merged JSON after step 04)

Output:
  grundwortschatz_merged_with_fresch.json
  fresch_coverage_report.txt   (diagnostic: per‑category counts)

Adds field `apiEnrichment.spellingStrategy` = ["mitsprechen", "weiterschwingen", …]
to every entry that has a matching NRW headword. Multi-label per word
(matches the original 532Strategien shape).

Words not in the NRW Grundwortschatz get a heuristic fallback based on
morphology (capitalization → Großschreibung, doubled consonants in lemma →
Weiterschwingen, etc.).
"""
from __future__ import annotations

import json
import sys
import re
from pathlib import Path
from collections import Counter

HERE = Path(__file__).parent
INPUT_NRW = HERE / "output_nested.json"
INPUT_MERGED = HERE / "grundwortschatz_merged.json"
OUTPUT = HERE / "grundwortschatz_merged_with_fresch.json"
REPORT = HERE / "fresch_coverage_report.txt"

# FRESCH canonical category tokens (matches the historical 532Strategien shape)
MITSPRECHEN = "mitsprechen"
WEITERSCHWINGEN = "weiterschwingen"
ABLEITEN = "ableiten"
MERKEN = "merken"
WORTBAUSTEINE = "wortbausteine"
GROSSSCHREIBUNG = "grossschreibung"

# Priority order for picking the single primary strategy per word.
# Grossschreibung wins when it applies (highest pedagogical leverage —
# capitalization is the orthogonal rule with the largest "if you know it,
# you avoid the error" payoff). Among the sound/letter strategies,
# Merken > Weiterschwingen > Ableiten > Wortbausteine > Mitsprechen, where
# Mitsprechen is the default for words with no special pattern.
PRIMARY_PRIORITY = [
    GROSSSCHREIBUNG,
    MERKEN,
    WEITERSCHWINGEN,
    ABLEITEN,
    WORTBAUSTEINE,
    MITSPRECHEN,
]

def pick_primary(cats: set[str]) -> str:
    """Pick the single highest-priority FRESCH category for the primary
    label per §6.2 / §6.5 of pipeline/PLAN.md."""
    for c in PRIMARY_PRIORITY:
        if c in cats:
            return c
    return MITSPRECHEN  # safety net; never reached if cats non-empty

# Regex helpers for the heuristic fallback (words not in NRW xlsx)
RE_DOUBLED_CONSONANT = re.compile(r"([bcdfghjklmnpqrstvwxyz])\1", re.IGNORECASE)
RE_AUSLAUTVERHAERTUNG = re.compile(r"[bdg]$", re.IGNORECASE)
RE_UMLAUT = re.compile(r"[äöüÄÖÜ]")
RE_DEHNUNGS_H = re.compile(r"[aeiouAEIOU]h[aeiouAEIOU]", re.IGNORECASE)
RE_PRAEFIX = re.compile(
    r"^(ver|vor|ge|be|ent|er|emp|miss|un|zer|ab|an|auf|aus|durch|ein|"
    r"hin|her|nach|über|um|unter|zu|zwischen)", re.IGNORECASE
)

# ---------------------------------------------------------------------------
# NRW feature → FRESCH category mapping
# ---------------------------------------------------------------------------

def _collect_x_paths(obj, prefix=""):
    """Walk an NRW entry's nested dict; yield every dotted path that has value 'x'."""
    if not isinstance(obj, dict):
        return
    for k, v in obj.items():
        # normalise keys (NRW has some newlines and stray whitespace inside keys)
        key = " ".join(k.replace("\n", " ").split())
        new_prefix = f"{prefix}.{key}" if prefix else key
        if v == "x":
            yield new_prefix
        elif isinstance(v, dict):
            yield from _collect_x_paths(v, new_prefix)

def _extract_word(entry: dict) -> str | None:
    """Find the headword inside an NRW entry. NRW puts it at
    entry['Artikel']['_value']."""
    art = entry.get("Artikel")
    if isinstance(art, dict):
        v = art.get("_value")
        if isinstance(v, str):
            return v.strip()
    return None

def nrw_features_to_fresch(entry: dict) -> tuple[set[str], list[str]]:
    """Return (fresch_categories, raw_nrw_paths) for one NRW entry."""
    paths = list(_collect_x_paths(entry))
    cats: set[str] = set()

    for p in paths:
        # --- Großschreibung ---
        if (p.startswith("Artikel.der") or p.startswith("Artikel.die")
                or p.startswith("Artikel.das")
                or "zusätzliche Filter.Wortart.Nomen" in p):
            cats.add(GROSSSCHREIBUNG)
        # --- Merken ---
        if "häufig gebrauchte" in p and "Merkwörter" in p:
            cats.add(MERKEN)
        # --- Wortbausteine: prefixes, compounds ---
        if "morphematisches Prinzip.Präfixe" in p:
            cats.add(WORTBAUSTEINE)
        if "Komposita" in p:
            cats.add(WORTBAUSTEINE)
        # --- Ableiten: Auslautverhärtung + Umlautung ---
        if ("morphematisches Prinzip.Auslautverhärtung" in p
                and "Komposita" not in p):
            cats.add(ABLEITEN)
        if "morphematisches Prinzip.Umlautung" in p:
            cats.add(ABLEITEN)
        # --- Weiterschwingen: Doppelkonsonanten ---
        if "Doppelkonsonanten" in p:
            cats.add(WEITERSCHWINGEN)
        if "mögliche dialektale Hürden.kurzes u" in p:
            cats.add(WEITERSCHWINGEN)
        if "mögliche dialektale Hürden.kurzes i" in p:
            cats.add(WEITERSCHWINGEN)
        # --- Mitsprechen: mehrteilige Basisgrapheme + Reduktionsendung ---
        if ("phonematisches Prinzip.mehrteilige Basisgrapheme" in p
                or "phonematisches Prinzip.Reduktionsendung" in p):
            cats.add(MITSPRECHEN)
        # --- Wortbausteine: silbentrennendes -h is a syllable-boundary marker ---
        if "silbentrennendes -h" in p:
            cats.add(WORTBAUSTEINE)

    # If nothing matched (e.g. the word is in the NRW list but has no
    # feature tag — purely regular phonology), fall back to Mitsprechen
    # (the "regular sound-it-out" default).
    if not cats:
        cats.add(MITSPRECHEN)

    return cats, paths

# ---------------------------------------------------------------------------
# Heuristic fallback for words NOT in NRW Grundwortschatz
# ---------------------------------------------------------------------------

def fallback_categories(word: str, lemma: str, word_type: str | None,
                        article: str | None) -> set[str]:
    """Rough FRESCH tagging for words outside the NRW Grundwortschatz, based
    on surface features of the lemma. Not as accurate as NRW-derived, but
    keeps coverage > 0 for the whole vocabulary."""
    cats: set[str] = set()
    target = lemma or word

    # Großschreibung — substantiv or article present
    if (word_type and "substantiv" in (word_type or "").lower()
            or article in ("der", "die", "das")):
        cats.add(GROSSSCHREIBUNG)

    # Weiterschwingen — doubled consonant in the spelling
    if RE_DOUBLED_CONSONANT.search(target):
        cats.add(WEITERSCHWINGEN)

    # Ableiten — final voiced→voiceless letter (devoicing candidates) OR umlaut
    if RE_AUSLAUTVERHAERTUNG.search(target) or RE_UMLAUT.search(target):
        cats.add(ABLEITEN)

    # Wortbausteine — common German prefix
    if RE_PRAEFIX.match(target):
        cats.add(WORTBAUSTEINE)

    # Mitsprechen — has a multi-letter base grapheme
    for digraph in ("sch", "ch", "ng", "pf", "ie", "ei", "eu", "au"):
        if digraph in target.lower():
            cats.add(MITSPRECHEN)
            break

    # No signal at all — default to Mitsprechen (regular sound-it-out)
    if not cats:
        cats.add(MITSPRECHEN)

    return cats

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def normalize(word: str) -> str:
    return word.strip().lower() if isinstance(word, str) else ""

def load_nrw_index(path: Path) -> dict[str, dict]:
    """Build a word → NRW entry lookup."""
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    idx: dict[str, dict] = {}
    for entry in data:
        w = _extract_word(entry)
        if w:
            idx[normalize(w)] = entry
    return idx

def main():
    if not INPUT_NRW.exists():
        print(f"NRW data not found: {INPUT_NRW}")
        print("Run conv_xls.py first (wortliste-grundwortschatz-nrw.xlsx → output_nested.json)")
        sys.exit(1)
    if not INPUT_MERGED.exists():
        print(f"Merged vocabulary not found: {INPUT_MERGED}")
        print("Run 04_add_nrw_data.py first.")
        sys.exit(1)

    print(f"Loading NRW features: {INPUT_NRW}")
    nrw_idx = load_nrw_index(INPUT_NRW)
    print(f"  {len(nrw_idx)} NRW headwords indexed")

    print(f"Loading merged vocabulary: {INPUT_MERGED}")
    with INPUT_MERGED.open(encoding="utf-8") as f:
        merged = json.load(f)

    # The merged JSON wraps the list under 'vocabulary' (matching DE step 03's
    # schema). Support both list-and-wrapped shapes.
    vocab = merged["vocabulary"] if isinstance(merged, dict) and "vocabulary" in merged else merged
    if not isinstance(vocab, list):
        print(f"Unexpected JSON shape: {type(vocab)}")
        sys.exit(1)
    print(f"  {len(vocab)} vocabulary entries")

    # Apply mapping
    source_dist = Counter()       # 'nrw_derived' / 'fallback_heuristic'
    cat_dist = Counter()          # per FRESCH category, how many words carry it
    primary_dist = Counter()      # per primary FRESCH category
    multi_label_dist = Counter()  # how many strategies per word
    unmapped_features: Counter = Counter()  # NRW feature paths that didn't trigger any category — for tuning

    for entry in vocab:
        word = entry.get("word") or entry.get("Word") or ""
        lemma = entry.get("lemma") or entry.get("Lemma") or word
        word_type = entry.get("wordType") or entry.get("Wortart") or ""
        article = entry.get("article") or entry.get("Article") or None

        nrw_entry = nrw_idx.get(normalize(word)) or nrw_idx.get(normalize(lemma))
        raw_nrw_paths: list[str] = []
        if nrw_entry is not None:
            cats, raw_nrw_paths = nrw_features_to_fresch(nrw_entry)
            source_dist["nrw_derived"] += 1
            # Record which NRW paths didn't map (diagnostic)
            for p in raw_nrw_paths:
                if not any(marker in p for marker in (
                    "Artikel.der", "Artikel.die", "Artikel.das",
                    "Wortart.Nomen", "Merkwörter", "Präfixe", "Komposita",
                    "Auslautverhärtung", "Umlautung", "Doppelkonsonanten",
                    "kurzes u", "kurzes i", "mehrteilige Basisgrapheme",
                    "Reduktionsendung", "silbentrennendes -h",
                )):
                    unmapped_features[p] += 1
        else:
            cats = fallback_categories(word, lemma, word_type, article)
            source_dist["fallback_heuristic"] += 1

        sorted_cats = sorted(cats)
        primary = pick_primary(cats)

        # Write into apiEnrichment (create if missing; never clobber other
        # apiEnrichment fields). Per PLAN.md §6.5, we ship both the
        # kid-friendly FRESCH labels AND the raw NRW linguistic feature
        # paths (when available) so the DB is transparent about provenance.
        api = entry.get("apiEnrichment")
        if not isinstance(api, dict):
            api = {}
        api["spellingStrategy"] = sorted_cats              # multi-label, kid-facing
        api["spellingStrategyPrimary"] = primary           # single, kid-facing
        api["spellingStrategySource"] = (
            "nrw_derived" if nrw_entry is not None else "fallback_heuristic"
        )
        if raw_nrw_paths:
            api["nrwLinguisticFeatures"] = sorted(raw_nrw_paths)
        entry["apiEnrichment"] = api

        for c in sorted_cats:
            cat_dist[c] += 1
        primary_dist[primary] += 1
        multi_label_dist[len(sorted_cats)] += 1

    # Write output
    out = merged if isinstance(merged, dict) else {"vocabulary": vocab}
    if isinstance(out, dict):
        meta = out.setdefault("metadata", {})
        if not isinstance(meta, dict):
            meta = {}
            out["metadata"] = meta
        meta["fresch_derivation"] = (
            "Categories applied algorithmically from NRW Grundwortschatz "
            "feature taxonomy. Own derivation; no third-party FRESCH "
            "publication consumed. See 04b_derive_fresch_categories.py."
        )

    with OUTPUT.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"\nWrote {OUTPUT.name}")

    # Coverage report
    lines = []
    lines.append("FRESCH derivation coverage report")
    lines.append("=" * 60)
    lines.append("")
    lines.append("Source of categorization per word:")
    for k, n in source_dist.most_common():
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {k:25s} {n:>5d}  ({pct:5.1f} %)")
    lines.append("")
    lines.append("Words carrying each FRESCH category (multi-label):")
    for c in [MITSPRECHEN, WEITERSCHWINGEN, ABLEITEN, MERKEN,
              WORTBAUSTEINE, GROSSSCHREIBUNG]:
        n = cat_dist.get(c, 0)
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {c:18s} {n:>5d}  ({pct:5.1f} %)")
    lines.append("")
    lines.append("Primary FRESCH category (single label, kid-facing):")
    for c in [MITSPRECHEN, WEITERSCHWINGEN, ABLEITEN, MERKEN,
              WORTBAUSTEINE, GROSSSCHREIBUNG]:
        n = primary_dist.get(c, 0)
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {c:18s} {n:>5d}  ({pct:5.1f} %)")
    lines.append("")
    lines.append("Multi-label distribution (categories per word):")
    for k in sorted(multi_label_dist):
        n = multi_label_dist[k]
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {k} categor{'y' if k == 1 else 'ies'}: "
                     f"{n:>5d} words  ({pct:5.1f} %)")
    if unmapped_features:
        lines.append("")
        lines.append("NRW feature paths that did NOT trigger any FRESCH category")
        lines.append("(tuning hints — these flags weren't recognized by the mapper):")
        for path, n in unmapped_features.most_common(20):
            lines.append(f"  {n:>4d}  {path}")

    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {REPORT.name}")
    print("\n".join(lines[:40]))

if __name__ == "__main__":
    main()
