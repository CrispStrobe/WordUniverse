"""Fold Wiktionary-marked misspelling / variant / obsolete-form entries into
their target lemmas.

Step 12_restructure_misspellings only caught entries the Wiktionary enricher
returned `no_data` for. But some misspellings (e.g. `recieve`, `accomodate`)
DO have Wiktionary entries — labeled with "Misspelling of X." in the first
definition. Those survived as separate top-level entries in v25.

This step parses the first definition line for Wiktionary marker phrases:

    Misspelling of X          → CLE attached to X
    Common misspelling of X   → CLE attached to X
    Nonstandard spelling of X → CLE attached to X
    Alternative spelling of X → spellingVariants attached to X (dialect: alternate)
    Alternative form of X     → spellingVariants attached to X (dialect: alternate)
    US/UK spelling of X       → spellingVariants attached to X (dialect: american|british)
    Obsolete form of X        → kept as lemma with `historical=True`
    Obsolete spelling of X    → kept as lemma with `historical=True`
    Archaic form of X         → same
    Archaic spelling of X     → same
    Dated form of X           → same

Also catches "Mountainous." style single-word capitalized definitions that
just refer to another lemma in vocab (Wiktionary shorthand for "see X").

Folded misspelling/variant entries are removed from the top-level vocabulary.
Historical/obsolete forms stay (they're not errors, just less common).
"""
import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).parent
DEFAULT_INPUT = HERE / "grundwortschatz_en_enriched_v25_consolidated.json"

MARKER_RE = re.compile(
    r"^(misspelling|common misspelling|nonstandard spelling|nonstandard form|"
    r"alternative spelling|alternative form|alternate spelling|alternate form|"
    r"alternative letter-case form|alternate letter-case form|"
    r"eye dialect|pronunciation spelling|"
    r"us spelling|uk spelling|american spelling|british spelling|"
    r"us standard spelling|uk standard spelling|"
    r"non-oxford british english standard spelling|"
    r"commonwealth standard spelling|"
    r"obsolete form|obsolete spelling|archaic form|archaic spelling|"
    r"dated form|dated spelling|informal spelling|informal form)\s+of\s+([\w'\-]+)",
    re.IGNORECASE,
)

# "Synonym of X" is borderline — real synonyms (e.g. automobile=synonym of car)
# vs short-form lookups. Only fold when the entry has the often_misspelled tag
# OR when it's the entry's only definition.
SYNONYM_RE = re.compile(r"^synonym\s+of\s+([\w'\-]+)", re.IGNORECASE)

# Also catch "Mountainous." style: a single-word capitalized definition ending in period
SINGLE_WORD_DEF_RE = re.compile(r"^([A-Z][\w'\-]+)\.\s*$")


def categorize(marker: str) -> str:
    m = marker.lower()
    if "misspelling" in m or "nonstandard" in m or "pronunciation spelling" in m:
        return "misspelling"
    if "obsolete" in m or "archaic" in m or "dated" in m:
        return "historical"
    if "us " in m or "american" in m or "us standard" in m:
        return "variant_american"
    if ("uk " in m or "british" in m or "uk standard" in m
            or "non-oxford british english standard" in m
            or "commonwealth" in m):
        return "variant_british"
    if "alternative" in m or "alternate" in m or "eye dialect" in m or "informal" in m:
        return "variant_alternate"
    return "misspelling"  # fallback


def build_inflection_index(vocabulary, skip_indices: set):
    """Three-pass priority: word > lemma/primary_lemma > inflections. See
    matching docstring in 04_add_common_misspellings_en.py for why."""
    idx = {}
    for i, e in enumerate(vocabulary):
        if i in skip_indices:
            continue
        w = e.get("word")
        if w:
            idx.setdefault(w.lower(), i)
    for i, e in enumerate(vocabulary):
        if i in skip_indices:
            continue
        l = e.get("lemma")
        if l:
            idx.setdefault(l.lower(), i)
        ae = e.get("apiEnrichment") or {}
        if isinstance(ae, dict):
            pl = ae.get("primary_lemma")
            if pl:
                idx.setdefault(pl.lower(), i)
    for i, e in enumerate(vocabulary):
        if i in skip_indices:
            continue
        ae = e.get("apiEnrichment") or {}
        if isinstance(ae, dict):
            for inf in ae.get("inflections") or []:
                if isinstance(inf, dict) and inf.get("form_text"):
                    idx.setdefault(inf["form_text"].lower(), i)
    return idx


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=str(DEFAULT_INPUT))
    ap.add_argument("--output", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    in_path = Path(args.input)
    out_path = Path(args.output) if args.output else in_path

    data = json.loads(in_path.read_text(encoding="utf-8"))
    voc = data["vocabulary"]
    print(f"loaded {len(voc)} entries from {in_path.name}")

    # First pass: identify candidates
    candidates = []  # (index, word, category, target_word, defline)
    voc_words = {(e.get("word") or "").lower() for e in voc}

    for i, e in enumerate(voc):
        ae = e.get("apiEnrichment") or {}
        if not isinstance(ae, dict):
            continue
        defs = ae.get("definitions") or []
        if not defs:
            continue
        first = (defs[0] or "").strip()
        m = MARKER_RE.match(first)
        if m:
            marker = m.group(1)
            target = m.group(2).lower()
            candidates.append((i, e["word"], categorize(marker), target, first))
            continue
        # "Synonym of X" — only fold if it's the only def OR entry is tagged
        # as a misspelling. Otherwise legitimate synonyms (e.g. automobile)
        # get incorrectly folded.
        m = SYNONYM_RE.match(first)
        if m:
            tags = e.get("tags") or []
            is_misspell_tagged = ("often_misspelled" in tags or "source:common_misspelled" in tags)
            if len(defs) <= 1 or is_misspell_tagged:
                target = m.group(1).lower()
                entry_word = (e.get("word") or "").lower()
                if target in voc_words and target != entry_word:
                    candidates.append((i, e["word"], "misspelling", target, first))
                    continue
        # Single-word-capitalized definition (Wiktionary "see X" shorthand)
        # Only treat as variant if this entry has FEW defs total AND has the
        # often_misspelled tag (signal that the misspellings step flagged it).
        # Otherwise `with`'s first def "Against." would fold it under `against`.
        m = SINGLE_WORD_DEF_RE.match(first)
        if m and len(defs) <= 2:
            tags = e.get("tags") or []
            if "often_misspelled" not in tags and "source:common_misspelled" not in tags:
                continue
            target = m.group(1).lower()
            entry_word = (e.get("word") or "").lower()
            if target in voc_words and target != entry_word:
                candidates.append((i, e["word"], "misspelling", target, first))

    print(f"  candidates flagged: {len(candidates)}")
    by_cat = {}
    for _, _, cat, _, _ in candidates:
        by_cat[cat] = by_cat.get(cat, 0) + 1
    for cat, n in by_cat.items():
        print(f"    {cat}: {n}")
    print()

    # Build target index excluding all candidate entries (so we attach to real lemmas)
    candidate_indices = {i for i, *_ in candidates}
    idx = build_inflection_index(voc, candidate_indices)

    # Second pass: process candidates
    folded = {"misspelling": 0, "variant_american": 0, "variant_british": 0,
              "variant_alternate": 0, "historical_kept": 0, "no_target_kept": 0}
    removed_indices = set()
    cle_added = 0
    sv_added = 0

    for i, word, cat, target, defline in candidates:
        target_idx = idx.get(target)
        entry = voc[i]

        if cat == "historical":
            # Keep as standalone; just mark as historical
            entry["historical"] = True
            entry["historicalReason"] = defline
            folded["historical_kept"] += 1
            continue

        if target_idx is None:
            # Can't fold (target lemma not in vocab); leave standalone but mark
            entry["uncoupledVariant"] = True
            entry["uncoupledVariantReason"] = defline
            folded["no_target_kept"] += 1
            continue

        # Fold into target
        target_entry = voc[target_idx]
        if cat == "misspelling":
            cle = target_entry.setdefault("commonLearnerErrors", [])
            if not any(isinstance(c, dict) and (c.get("error") or "").lower() == word.lower() for c in cle):
                cle.append({
                    "error": word,
                    "source": "WIKTIONARY_MARKER",
                })
                cle_added += 1
            removed_indices.add(i)
            folded["misspelling"] += 1
        else:  # variant_*
            sv = target_entry.setdefault("spellingVariants", [])
            dialect = {
                "variant_american": "american",
                "variant_british": "british",
                "variant_alternate": "alternate",
            }[cat]
            if not any(isinstance(v, dict) and (v.get("variant") or "").lower() == word.lower() for v in sv):
                sv.append({
                    "variant": word,
                    "dialect": dialect,
                    "source": "WIKTIONARY_MARKER",
                })
                sv_added += 1
            removed_indices.add(i)
            folded[cat] += 1

    # Apply removals (reverse order)
    new_voc = [e for i, e in enumerate(voc) if i not in removed_indices]
    print(f"\nVocabulary: {len(voc)} → {len(new_voc)} ({len(removed_indices)} removed)")
    print(f"Added: {cle_added} commonLearnerErrors entries, {sv_added} spellingVariants entries")
    print(f"By category: {folded}")

    if args.dry_run:
        print("(dry run; nothing written)")
        return 0

    data["vocabulary"] = new_voc
    meta = data.setdefault("metadata", {})
    meta["wiktionary_markers_folded"] = folded
    meta["wiktionary_markers_removed_count"] = len(removed_indices)
    meta["word_count"] = len(new_voc)
    out_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nWrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
