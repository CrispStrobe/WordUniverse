"""Derive spelling-pattern categories from the NRW Grundwortschatz feature
taxonomy and attach them to the consolidated vocabulary JSON.

The category names used here (klangtreu / doppelkonsonant / verwandt /
merkwort / morphem / grossschreibung) are neutral German linguistic-pattern
labels. They describe the *linguistic feature* each word's spelling rests
on; they are NOT borrowed from any branded pedagogical method. Pedagogically
they cover the same ground as several published German spelling-strategy
methods, but the labels here are independent and the derivation rules
are our own.

We apply the categorization **algorithmically** to the NRW linguistic-
feature flags that the official NRW Grundwortschatz xlsx already contains
— produced for us by `conv_xls.py` as `output_nested.json`.

This makes the spelling-pattern categorization **our own derivation** from
a clean source: NRW Ministerium für Schule und Bildung — German educational
public administrative material. No third-party curated wordlist is
consumed.

Mapping (NRW xlsx feature → spelling-pattern category):

  klangtreu         ← phonematisches Prinzip.mehrteilige Basisgrapheme.*
                      (Diphthonge ei/eu/au, Konsonanten ch/sch/ng/pf, ie, …)
                      and phonematisches Prinzip.Reduktionsendung.*
                      — sound‑it‑out patterns once known.
                      Also the **default** when no other category applies.

  doppelkonsonant   ← orthografisches und silbisches Prinzip.
                      Orthographeme.Doppelkonsonanten.* (any double
                      consonant: ss/ll/nn/tt/ck/mm/pp/tz/…)
                      and mögliche dialektale Hürden.kurzes u / kurzes i.

  verwandt          ← morphematisches Prinzip.Auslautverhärtung.*
                      (b/p, d/t, g/k devoicing — find a related form
                      to hear the underlying consonant) and
                      morphematisches Prinzip.Umlautung.* (ä, ö, ü, äu).

  merkwort          ← Artikel.häufig gebrauchte (Funktions‑)Merkwörter
                      (the explicit Merkwort flag in the NRW xlsx).

  morphem           ← morphematisches Prinzip.Präfixe.* (ver/vor/ge/…),
                      morphematisches Prinzip.Auslautverhärtung.Komposita
                      (compound‑word case), and orthografisches und
                      silbisches Prinzip.silbentrennendes -h.

  grossschreibung   ← Artikel.der|die|das present OR
                      zusätzliche Filter.Wortart.Nomen present.

Input:
  output_nested.json           (533 NRW entries with feature flags, from conv_xls.py)
  grundwortschatz_merged.json  (the merged JSON after step 04)

Output:
  grundwortschatz_merged_with_patterns.json
  pattern_coverage_report.txt  (diagnostic: per‑category counts)

Adds these fields to each vocab entry's apiEnrichment:
  • spellingStrategy           — multi-label list, kid-facing
  • spellingStrategyPrimary    — single primary label, kid-facing
  • spellingStrategySource     — "nrw_derived" | "fallback_heuristic"
  • nrwLinguisticFeatures      — list of raw NRW feature paths
                                 (only present for NRW-derived entries;
                                 provided for transparency / academic view
                                 per PLAN.md §6.5)

Words outside the NRW Grundwortschatz get a heuristic fallback based on
surface morphology (capitalization → grossschreibung, doubled consonants
in lemma → doppelkonsonant, etc.).
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
OUTPUT = HERE / "grundwortschatz_merged_with_patterns.json"
REPORT = HERE / "pattern_coverage_report.txt"

# ─── Two parallel taxonomies (see pipeline/PLAN.md §6.5) ───────────────
# Both bucketings derive from the SAME NRW xlsx feature taxonomy. We
# ship both per-word: the detailed view (6 categories, kid-facing) and
# the broad view (5 categories, research-supported).

# ── 6-category detailed view (kid-facing default) ──
# Neutral German linguistic-pattern names. No FRESCH-branded terminology.
KLANGTREU = "klangtreu"             # regular phoneme-grapheme (sound-it-out)
DOPPELKONSONANT = "doppelkonsonant" # doubled-consonant pattern
VERWANDT = "verwandt"               # related-word derivation (Auslautverhärtung, Umlautung)
MERKWORT = "merkwort"               # memorize as a special case
MORPHEM = "morphem"                 # word components: prefixes + compounds
GROSSSCHREIBUNG = "grossschreibung" # capitalization

PRIMARY_PRIORITY_DETAILED = [
    GROSSSCHREIBUNG,
    MERKWORT,
    DOPPELKONSONANT,
    VERWANDT,
    MORPHEM,
    KLANGTREU,
]

# ── 5-category broad view (teacher / research view) ──
# Every German word's spelling rests on one of basisgraphem (regular
# grapheme-phoneme, ~65% of words use only Basisgrapheme), orthographem
# (orthographic exception — covers more than just doubled consonants;
# also Dehnungs-h, ck/tz/sp/st, etc.), or morphem (morphology-based:
# covers BOTH related-word derivation AND compound/prefix). Plus two
# cross-cutting flags: merkwort (irregular, rote memorize) and
# grossschreibung (capitalization).
BASISGRAPHEM = "basisgraphem"   # regular grapheme-phoneme
ORTHOGRAPHEM = "orthographem"   # orthographic exception (broader than doppelkonsonant)
MORPHEM_BROAD = "morphem"       # any morphological reasoning (derivation + composition)
# MERKWORT, GROSSSCHREIBUNG are shared between schemes (same token, same
# meaning — capitalization and rote-memorize cross both taxonomies).

PRIMARY_PRIORITY_THOME = [
    GROSSSCHREIBUNG,
    MERKWORT,
    ORTHOGRAPHEM,
    MORPHEM_BROAD,
    BASISGRAPHEM,
]

def pick_primary_detailed(cats: set[str]) -> str:
    """Pick the single highest-priority detailed (6-category) label."""
    for c in PRIMARY_PRIORITY_DETAILED:
        if c in cats:
            return c
    return KLANGTREU

def pick_primary_thome(cats: set[str]) -> str:
    """Pick the single highest-priority broad (5-category) label."""
    for c in PRIMARY_PRIORITY_THOME:
        if c in cats:
            return c
    return BASISGRAPHEM

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
# NRW feature → spelling-pattern category mapping
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

def nrw_features_to_patterns(entry: dict) -> tuple[set[str], set[str], list[str]]:
    """Return (detailed_cats, thome_cats, raw_nrw_paths) for one NRW entry.

    detailed_cats — 6-category fine-grained labels (klangtreu /
                    doppelkonsonant / verwandt / merkwort / morphem /
                    grossschreibung)
    thome_cats    — 5-category Thomé-aligned labels (basisgraphem /
                    orthographem / morphem / merkwort / grossschreibung)
    raw_nrw_paths — unmapped NRW xlsx feature paths (for transparency)
    """
    paths = list(_collect_x_paths(entry))
    detailed: set[str] = set()
    thome: set[str] = set()

    for p in paths:
        # --- grossschreibung (shared) ---
        if (p.startswith("Artikel.der") or p.startswith("Artikel.die")
                or p.startswith("Artikel.das")
                or "zusätzliche Filter.Wortart.Nomen" in p):
            detailed.add(GROSSSCHREIBUNG)
            thome.add(GROSSSCHREIBUNG)
        # --- merkwort (shared) ---
        if "häufig gebrauchte" in p and "Merkwörter" in p:
            detailed.add(MERKWORT)
            thome.add(MERKWORT)
        # --- 6-cat: morphem (prefixes, compounds, syllable-h) ---
        if "morphematisches Prinzip.Präfixe" in p:
            detailed.add(MORPHEM)
        if "Komposita" in p:
            detailed.add(MORPHEM)
        if "silbentrennendes -h" in p:
            detailed.add(MORPHEM)
        # --- 6-cat: verwandt (related-word derivation) ---
        if ("morphematisches Prinzip.Auslautverhärtung" in p
                and "Komposita" not in p):
            detailed.add(VERWANDT)
        if "morphematisches Prinzip.Umlautung" in p:
            detailed.add(VERWANDT)
        # --- 6-cat: doppelkonsonant (doubled consonants + short vowels) ---
        if "Doppelkonsonanten" in p:
            detailed.add(DOPPELKONSONANT)
        if "mögliche dialektale Hürden.kurzes u" in p:
            detailed.add(DOPPELKONSONANT)
        if "mögliche dialektale Hürden.kurzes i" in p:
            detailed.add(DOPPELKONSONANT)
        # --- 6-cat: klangtreu (regular phonology) ---
        if ("phonematisches Prinzip.mehrteilige Basisgrapheme" in p
                or "phonematisches Prinzip.Reduktionsendung" in p):
            detailed.add(KLANGTREU)
        # --- 5-cat (Thomé): orthographem — orthographic exceptions (broader) ---
        # Covers everything under orthografisches und silbisches Prinzip,
        # plus dialectal-hurdle markers (short vowels signaled
        # orthographically). Broader than 6-cat doppelkonsonant.
        if ("orthografisches und silbisches Prinzip" in p
                or "mögliche dialektale Hürden" in p):
            thome.add(ORTHOGRAPHEM)
        # --- 5-cat (Thomé): morphem — any morphological reasoning ---
        # Both derivation (Auslautverhärtung, Umlautung) and composition
        # (Präfixe, Komposita) collapse into one broad category.
        if "morphematisches Prinzip" in p:
            thome.add(MORPHEM_BROAD)
        # --- 5-cat (Thomé): basisgraphem — regular phonology ---
        # Thomé's term for the regular grapheme-phoneme correspondence
        # that ~65% of German words rely on exclusively.
        if "phonematisches Prinzip" in p:
            thome.add(BASISGRAPHEM)

    # Defaults: if nothing matched (word is in NRW list but lacks any
    # feature tag — purely regular phonology), fall back to the
    # "regular sound-it-out" default in each scheme.
    if not detailed:
        detailed.add(KLANGTREU)
    if not thome:
        thome.add(BASISGRAPHEM)

    return detailed, thome, paths

# ---------------------------------------------------------------------------
# Mapping from 6-cat detailed → 5-cat Thomé (used for fallback path)
# ---------------------------------------------------------------------------
# Strict bucketing: every detailed category collapses to exactly one
# Thomé category. Used when we don't have NRW xlsx feature data (i.e.
# words outside the NRW Grundwortschatz, derived via surface heuristics).
DETAILED_TO_THOME = {
    KLANGTREU: BASISGRAPHEM,
    DOPPELKONSONANT: ORTHOGRAPHEM,
    VERWANDT: MORPHEM_BROAD,
    MERKWORT: MERKWORT,
    MORPHEM: MORPHEM_BROAD,
    GROSSSCHREIBUNG: GROSSSCHREIBUNG,
}

def detailed_to_thome(detailed: set[str]) -> set[str]:
    """Derive 5-cat Thomé tags from 6-cat detailed tags (strict bucketing)."""
    return {DETAILED_TO_THOME[c] for c in detailed if c in DETAILED_TO_THOME}

# ---------------------------------------------------------------------------
# Heuristic fallback for words NOT in NRW Grundwortschatz
# ---------------------------------------------------------------------------

def fallback_categories(word: str, lemma: str, word_type: str | None,
                        article: str | None) -> set[str]:
    """Rough 6-cat categorization for words outside the NRW Grundwortschatz,
    based on surface features of the lemma. Not as accurate as NRW-derived,
    but keeps coverage > 0 for the whole vocabulary. The Thomé 5-cat
    bucketing is then derived from this via DETAILED_TO_THOME."""
    cats: set[str] = set()
    target = lemma or word

    # Großschreibung — substantiv or article present
    if (word_type and "substantiv" in (word_type or "").lower()
            or article in ("der", "die", "das")):
        cats.add(GROSSSCHREIBUNG)

    # doppelkonsonant — doubled consonant in the spelling
    if RE_DOUBLED_CONSONANT.search(target):
        cats.add(DOPPELKONSONANT)

    # verwandt — final voiced→voiceless letter (devoicing candidates) OR umlaut
    if RE_AUSLAUTVERHAERTUNG.search(target) or RE_UMLAUT.search(target):
        cats.add(VERWANDT)

    # morphem — common German prefix
    if RE_PRAEFIX.match(target):
        cats.add(MORPHEM)

    # klangtreu — has a multi-letter base grapheme
    for digraph in ("sch", "ch", "ng", "pf", "ie", "ei", "eu", "au"):
        if digraph in target.lower():
            cats.add(KLANGTREU)
            break

    # No signal at all — default to klangtreu (regular sound-it-out)
    if not cats:
        cats.add(KLANGTREU)

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
    source_dist = Counter()             # 'nrw_derived' / 'fallback_heuristic'
    detailed_cat_dist = Counter()       # per 6-cat label, # of words carrying it
    detailed_primary_dist = Counter()   # per primary 6-cat label
    thome_cat_dist = Counter()          # per 5-cat Thomé label, # of words carrying it
    thome_primary_dist = Counter()      # per primary 5-cat Thomé label
    multi_label_dist = Counter()        # how many detailed-scheme labels per word
    unmapped_features: Counter = Counter()  # NRW paths that didn't trigger any tag — for tuning

    for entry in vocab:
        word = entry.get("word") or entry.get("Word") or ""
        lemma = entry.get("lemma") or entry.get("Lemma") or word
        word_type = entry.get("wordType") or entry.get("Wortart") or ""
        article = entry.get("article") or entry.get("Article") or None

        nrw_entry = nrw_idx.get(normalize(word)) or nrw_idx.get(normalize(lemma))
        raw_nrw_paths: list[str] = []
        if nrw_entry is not None:
            detailed, thome, raw_nrw_paths = nrw_features_to_patterns(nrw_entry)
            source_dist["nrw_derived"] += 1
            # Record which NRW paths didn't map (diagnostic)
            for p in raw_nrw_paths:
                if not any(marker in p for marker in (
                    "Artikel.der", "Artikel.die", "Artikel.das",
                    "Wortart.Nomen", "Merkwörter", "Präfixe", "Komposita",
                    "Auslautverhärtung", "Umlautung", "Doppelkonsonanten",
                    "kurzes u", "kurzes i", "mehrteilige Basisgrapheme",
                    "Reduktionsendung", "silbentrennendes -h",
                    "orthografisches und silbisches Prinzip",
                    "phonematisches Prinzip", "morphematisches Prinzip",
                )):
                    unmapped_features[p] += 1
        else:
            detailed = fallback_categories(word, lemma, word_type, article)
            thome = detailed_to_thome(detailed)
            source_dist["fallback_heuristic"] += 1

        sorted_detailed = sorted(detailed)
        sorted_thome = sorted(thome)
        primary_detailed = pick_primary_detailed(detailed)
        primary_thome = pick_primary_thome(thome)

        # Write into apiEnrichment (create if missing; never clobber other
        # apiEnrichment fields). We ship two parallel taxonomies: the
        # kid-facing detailed 6-category view AND the research-aligned
        # 5-category broad view. Both derive from the same NRW xlsx; both
        # share grossschreibung + merkwort.
        api = entry.get("apiEnrichment")
        if not isinstance(api, dict):
            api = {}
        # 6-category detailed view (kid-facing default)
        api["spellingStrategy"] = sorted_detailed
        api["spellingStrategyPrimary"] = primary_detailed
        # 5-category broad view (academic / teacher view)
        api["spellingPatterns"] = sorted_thome
        api["spellingPatternsPrimary"] = primary_thome
        # Provenance
        api["spellingStrategySource"] = (
            "nrw_derived" if nrw_entry is not None else "fallback_heuristic"
        )
        # Raw NRW feature paths (transparency, only when available)
        if raw_nrw_paths:
            api["nrwLinguisticFeatures"] = sorted(raw_nrw_paths)
        entry["apiEnrichment"] = api

        for c in sorted_detailed:
            detailed_cat_dist[c] += 1
        for c in sorted_thome:
            thome_cat_dist[c] += 1
        detailed_primary_dist[primary_detailed] += 1
        thome_primary_dist[primary_thome] += 1
        multi_label_dist[len(sorted_detailed)] += 1

    # Write output
    out = merged if isinstance(merged, dict) else {"vocabulary": vocab}
    if isinstance(out, dict):
        meta = out.setdefault("metadata", {})
        if not isinstance(meta, dict):
            meta = {}
            out["metadata"] = meta
        meta["pattern_derivation"] = (
            "Categories applied algorithmically from NRW Grundwortschatz "
            "feature taxonomy. Own derivation; no third-party curated wordlist "
            "publication consumed. See 04b_derive_spelling_patterns.py."
        )

    with OUTPUT.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"\nWrote {OUTPUT.name}")

    # Coverage report
    lines = []
    lines.append("Spelling-pattern derivation coverage report")
    lines.append("=" * 60)
    lines.append("")
    lines.append("Source of categorization per word:")
    for k, n in source_dist.most_common():
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {k:25s} {n:>5d}  ({pct:5.1f} %)")
    lines.append("")
    lines.append("─── 6-category detailed view (kid-facing) ───")
    lines.append("Words carrying each detailed category (multi-label):")
    for c in [KLANGTREU, DOPPELKONSONANT, VERWANDT, MERKWORT,
              MORPHEM, GROSSSCHREIBUNG]:
        n = detailed_cat_dist.get(c, 0)
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {c:18s} {n:>5d}  ({pct:5.1f} %)")
    lines.append("")
    lines.append("Primary detailed category (single label per word):")
    for c in [KLANGTREU, DOPPELKONSONANT, VERWANDT, MERKWORT,
              MORPHEM, GROSSSCHREIBUNG]:
        n = detailed_primary_dist.get(c, 0)
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {c:18s} {n:>5d}  ({pct:5.1f} %)")
    lines.append("")
    lines.append("─── 5-category Thomé view (academic / teacher) ───")
    lines.append("Words carrying each Thomé category (multi-label):")
    for c in [BASISGRAPHEM, ORTHOGRAPHEM, MORPHEM_BROAD, MERKWORT,
              GROSSSCHREIBUNG]:
        n = thome_cat_dist.get(c, 0)
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {c:18s} {n:>5d}  ({pct:5.1f} %)")
    lines.append("")
    lines.append("Primary Thomé category (single label per word):")
    for c in [BASISGRAPHEM, ORTHOGRAPHEM, MORPHEM_BROAD, MERKWORT,
              GROSSSCHREIBUNG]:
        n = thome_primary_dist.get(c, 0)
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {c:18s} {n:>5d}  ({pct:5.1f} %)")
    lines.append("")
    lines.append("Multi-label distribution (detailed categories per word):")
    for k in sorted(multi_label_dist):
        n = multi_label_dist[k]
        pct = 100.0 * n / max(len(vocab), 1)
        lines.append(f"  {k} categor{'y' if k == 1 else 'ies'}: "
                     f"{n:>5d} words  ({pct:5.1f} %)")
    if unmapped_features:
        lines.append("")
        lines.append("NRW feature paths that did NOT trigger any spelling-pattern category")
        lines.append("(tuning hints — these flags weren't recognized by the mapper):")
        for path, n in unmapped_features.most_common(20):
            lines.append(f"  {n:>4d}  {path}")

    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {REPORT.name}")
    print("\n".join(lines[:40]))

if __name__ == "__main__":
    main()
