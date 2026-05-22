"""Attach British/American spelling variants from vg/spelling-uk-vs-us.

Source: https://github.com/vg/spelling-uk-vs-us (MIT code, CC-BY-4.0 content)
File:   sources/uk_us_spelling.json — 1,737 [UK, US] pairs

For each (uk_form, us_form) pair, if any vocab entry has either form as its
word/lemma/inflection-form, attach a `spellingVariants[]` entry pointing to
the other form. These are VALID alternates (not errors) — distinct from
`commonLearnerErrors[]`.

Shape:
    {"variant": "colour", "dialect": "british", "source": "VG_UK_US_SPELLING"}

If BOTH forms exist as separate top-level lemmas, cross-reference each.
The app can then surface "color (US) ↔ colour (UK)" as legitimate alternates
rather than marking either as wrong.

Usage:
    python 12c_add_spelling_variants.py --input <enriched.json>
    python 12c_add_spelling_variants.py --input v25_consolidated.json --output v25_with_variants.json
"""
import argparse
import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).parent
DEFAULT_INPUT = HERE / "grundwortschatz_en_enriched_v25_consolidated.json"
UKUS_SOURCE = HERE / "sources" / "uk_us_spelling.json"

SOURCE_TAG = "VG_UK_US_SPELLING"


def build_inflection_index(vocabulary: list[dict]) -> dict[str, int]:
    """Three-pass priority order:
      1. own `word` (headword) — the entry IS this form
      2. own `lemma` / `primary_lemma` — the entry inflects to this form
      3. inflections — the entry can be inflected as this form
    Needed because e.g. the `received` entry has primary_lemma='receive' AND
    the `receive` entry has word='receive'; without passing word first,
    idx['receive'] would point at received.
    """
    idx: dict[str, int] = {}
    for i, e in enumerate(vocabulary):
        w = e.get("word")
        if w:
            idx.setdefault(w.lower(), i)
    for i, e in enumerate(vocabulary):
        l = e.get("lemma")
        if l:
            idx.setdefault(l.lower(), i)
        ae = e.get("apiEnrichment") or {}
        if isinstance(ae, dict):
            pl = ae.get("primary_lemma")
            if pl:
                idx.setdefault(pl.lower(), i)
    for i, e in enumerate(vocabulary):
        ae = e.get("apiEnrichment") or {}
        if isinstance(ae, dict):
            for infl in ae.get("inflections") or []:
                if isinstance(infl, dict):
                    ft = infl.get("form_text")
                    if ft:
                        idx.setdefault(ft.lower(), i)
    return idx


def add_variant(entry: dict, variant_form: str, dialect: str) -> bool:
    """Idempotently attach a variant to the entry. Returns True if added."""
    existing = entry.setdefault("spellingVariants", [])
    variant_lc = variant_form.lower()
    for v in existing:
        if isinstance(v, dict) and (v.get("variant") or "").lower() == variant_lc:
            return False
    existing.append({
        "variant": variant_form,
        "dialect": dialect,
        "source": SOURCE_TAG,
    })
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=str(DEFAULT_INPUT))
    ap.add_argument("--output", default=None,
                    help="Defaults to overwriting --input")
    args = ap.parse_args()

    in_path = Path(args.input)
    out_path = Path(args.output) if args.output else in_path

    if not in_path.exists():
        raise SystemExit(f"{in_path} not found")
    if not UKUS_SOURCE.exists():
        raise SystemExit(f"{UKUS_SOURCE} not found — fetch the source first")

    data = json.loads(in_path.read_text(encoding="utf-8"))
    voc = data["vocabulary"]
    print(f"loaded {len(voc)} entries from {in_path.name}")

    idx = build_inflection_index(voc)
    print(f"  inflection-aware index has {len(idx)} keys")

    ukus = json.loads(UKUS_SOURCE.read_text(encoding="utf-8"))
    pairs = ukus["data"]
    print(f"  {len(pairs)} (uk, us) pairs to consider")

    attached_to_uk = 0   # uk-form entry got US variant
    attached_to_us = 0   # us-form entry got UK variant
    cross_referenced = 0 # both exist; both got each other
    only_uk_in_vocab = 0
    only_us_in_vocab = 0
    neither_in_vocab = 0

    for uk_form, us_form in pairs:
        uk_lc = uk_form.lower()
        us_lc = us_form.lower()
        uk_idx = idx.get(uk_lc)
        us_idx = idx.get(us_lc)

        if uk_idx is not None and us_idx is not None:
            if uk_idx != us_idx:
                # Two separate entries — cross-reference
                if add_variant(voc[uk_idx], us_form, "american"):
                    attached_to_uk += 1
                if add_variant(voc[us_idx], uk_form, "british"):
                    attached_to_us += 1
                cross_referenced += 1
            else:
                # Both forms map to the same entry (typically because one is
                # the canonical word/lemma and the other is a cross-listed
                # alternative spelling in the Wiktionary inflections). Attach
                # the non-canonical side as a variant.
                entry = voc[uk_idx]
                canonical_lc = (entry.get("word") or entry.get("lemma") or "").lower()
                if canonical_lc == uk_lc:
                    # entry's canonical is the UK form → attach US as american
                    if add_variant(entry, us_form, "american"):
                        attached_to_uk += 1
                        only_uk_in_vocab += 1
                elif canonical_lc == us_lc:
                    if add_variant(entry, uk_form, "british"):
                        attached_to_us += 1
                        only_us_in_vocab += 1
                else:
                    # Canonical is some third form (a stem the inflections
                    # roll up to). Attach both UK and US as named variants.
                    if add_variant(entry, uk_form, "british"):
                        attached_to_us += 1
                    if add_variant(entry, us_form, "american"):
                        attached_to_uk += 1
        elif uk_idx is not None:
            if add_variant(voc[uk_idx], us_form, "american"):
                attached_to_uk += 1
            only_uk_in_vocab += 1
        elif us_idx is not None:
            if add_variant(voc[us_idx], uk_form, "british"):
                attached_to_us += 1
            only_us_in_vocab += 1
        else:
            neither_in_vocab += 1

    # Metadata
    meta = data.setdefault("metadata", {})
    meta["spelling_variants_source"] = "vg/spelling-uk-vs-us (MIT code, CC-BY-4.0 content)"
    meta["spelling_variants_added_to_uk_form"] = attached_to_uk
    meta["spelling_variants_added_to_us_form"] = attached_to_us
    meta["spelling_variants_cross_referenced_pairs"] = cross_referenced

    out_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print()
    print(f"Wrote {out_path.name}")
    print(f"  attached to UK-form entries:    {attached_to_uk}")
    print(f"  attached to US-form entries:    {attached_to_us}")
    print(f"  cross-referenced pairs (both):  {cross_referenced}")
    print(f"  only UK in vocab:               {only_uk_in_vocab}")
    print(f"  only US in vocab:               {only_us_in_vocab}")
    print(f"  neither in vocab:               {neither_in_vocab}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
