#!/usr/bin/env python3
"""Restructure: misspellings as attached learner-errors, not top-level lemmas.

Before: each Wikipedia-misspelling has its own vocab entry, with the CORRECT
spelling buried in `commonLearnerErrors[0].wrong` (confusing field name).

After: each correct lemma is a top-level entry; the misspellings live in its
`commonLearnerErrors[]` list as `{"error": "abondon", "source": "..."}`.
Matches the DE DB pattern.

For target lemmas that exist in vocab (by word/lemma OR inflection-form match),
the misspellings get folded in. For target lemmas NOT in vocab, a new entry is
created (to be enriched in a later 11b pass).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).parent
SOURCE = HERE / "grundwortschatz_en_enriched_v24.json"
TARGET = HERE / "grundwortschatz_en_enriched_v25.json"


def load() -> dict[str, Any]:
    with SOURCE.open() as f:
        return json.load(f)


def build_inflection_index(voc: list) -> dict[str, int]:
    """Map lowercased form -> entry index. Covers word, lemma, primary_lemma,
    and inflections[].form_text from apiEnrichment."""
    idx: dict[str, int] = {}
    for i, e in enumerate(voc):
        for k in (e.get("word"), e.get("lemma")):
            if k:
                idx.setdefault(k.lower(), i)
        ae = e.get("apiEnrichment") or {}
        if isinstance(ae, dict):
            pl = ae.get("primary_lemma")
            if pl:
                idx.setdefault(pl.lower(), i)
            for infl in ae.get("inflections") or []:
                if isinstance(infl, dict):
                    ft = infl.get("form_text")
                    if ft:
                        idx.setdefault(ft.lower(), i)
    return idx


def is_misspelling_entry(e: dict) -> bool:
    """A misspelling entry: no_data enrichment + commonLearnerErrors set."""
    ae = e.get("apiEnrichment") or {}
    if not isinstance(ae, dict):
        return False
    if ae.get("enrichment_status") != "no_data":
        return False
    cle = e.get("commonLearnerErrors") or []
    return bool(cle)


def main() -> int:
    print(f"Loading {SOURCE.name}…")
    d = load()
    voc = d["vocabulary"]
    print(f"  loaded {len(voc)} entries")

    idx = build_inflection_index(voc)
    print(f"  inflection-aware index has {len(idx)} keys")

    # First pass: collect every misspelling -> correct mapping
    misspellings_by_target: dict[str, list[dict]] = {}
    indices_to_remove: set[int] = set()
    bad_entries = 0
    for i, e in enumerate(voc):
        if not is_misspelling_entry(e):
            continue
        cle = e["commonLearnerErrors"][0]
        correct_raw = cle.get("wrong")  # this is the CORRECT form (misnamed)
        source = cle.get("source") or "WIKI_MISSPELLINGS_EN"
        if not correct_raw:
            bad_entries += 1
            continue
        correct = correct_raw.strip()
        # Store the misspelling for attachment under correct (case-preserved)
        misspellings_by_target.setdefault(correct, []).append(
            {"error": e["word"], "source": source}
        )
        indices_to_remove.add(i)
    print(f"  misspelling-headword entries: {len(indices_to_remove)} "
          f"(bad/missing-correct: {bad_entries})")
    print(f"  unique correct targets: {len(misspellings_by_target)}")

    # Second pass: classify targets as in-vocab vs new
    in_vocab_targets = 0  # by exact word/lemma/inflection match
    new_targets: dict[str, list[dict]] = {}
    for correct, errs in misspellings_by_target.items():
        if correct.lower() in idx:
            target_idx = idx[correct.lower()]
            entry = voc[target_idx]
            existing = entry.get("commonLearnerErrors") or []
            existing_misspells = {
                (c.get("error") or "").lower()
                for c in existing
                if isinstance(c, dict)
            }
            for err in errs:
                if err["error"].lower() not in existing_misspells:
                    existing.append(err)
            entry["commonLearnerErrors"] = existing
            in_vocab_targets += 1
        else:
            new_targets[correct] = errs
    print(f"  → attached to existing vocab: {in_vocab_targets} targets")
    print(f"  → need new vocab entries:     {len(new_targets)} targets")

    # Third pass: remove old misspelling top-level entries (reverse order)
    for i in sorted(indices_to_remove, reverse=True):
        del voc[i]
    print(f"  removed {len(indices_to_remove)} misspelling-headword entries")
    print(f"  vocab is now {len(voc)} entries (before adding new lemmas)")

    # Fourth pass: add new lemma entries for unmatched correct targets
    # Determine starting numeric id
    max_idnum = 0
    for e in voc:
        eid = e.get("id") or ""
        if eid.startswith("word_en_"):
            try:
                n = int(eid.split("_")[-1])
                if n > max_idnum:
                    max_idnum = n
            except ValueError:
                pass

    schema_keys_seed = None
    for e in voc:
        if e.get("apiEnrichment", {}).get("enrichment_status") == "success":
            schema_keys_seed = list(e.keys())
            break
    if not schema_keys_seed:
        schema_keys_seed = list(voc[0].keys())

    added = 0
    for j, (correct, errs) in enumerate(sorted(new_targets.items())):
        new_id = f"word_en_{max_idnum + 1 + j:05d}"
        new_entry: dict = {
            "id": new_id,
            "word": correct,
            "lemma": correct,
            "wordType": "noun",       # placeholder; refined by enrichment if available
            "article": None,
            "genus": None,
            "gradeLevel": 7,           # default for derived/extended vocab
            "gradeReason": "derived_from_misspelling_target",
            "tags": ["default", "derived_from_misspelling_target"],
            "morphology": {},
            "frequencyData": {},
            "pronunciation": {},
            "graphemeVariants": [],
            "apiEnrichment": None,    # pending — picked up by 11b on next run
            "commonLearnerErrors": list(errs),
            "translations": [],
            "inflectionData": {},
            "definitions": [],
            "examples": [],
            "ipaPhoneme": None,
        }
        # Ensure every schema key exists (preserve existing keys we know about)
        for k in schema_keys_seed:
            if k not in new_entry:
                new_entry[k] = None
        voc.append(new_entry)
        added += 1
    print(f"  added {added} new lemma entries (need enrichment)")
    print(f"  final vocab size: {len(voc)}")

    # Update metadata
    meta = d.setdefault("metadata", {})
    meta["restructure_version"] = "v25_misspellings_attached"
    meta["word_count"] = len(voc)
    prev = meta.get("source_step", "")
    meta["source_step"] = f"{prev} -> 12_restructure_misspellings"

    # Save
    with TARGET.open("w") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    print(f"\nWrote {TARGET.name} ({TARGET.stat().st_size / 1e6:.1f} MB)")

    # Coverage report
    needs_enrich = sum(1 for e in voc if (e.get("apiEnrichment") or {}).get("enrichment_status") != "success")
    print(f"  entries needing enrichment in v25: {needs_enrich}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
