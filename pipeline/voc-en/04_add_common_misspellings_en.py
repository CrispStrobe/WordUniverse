"""Attach common misspellings to grundwortschatz_en.json.

Combines two sources:
  - sources/commonly_misspelled.csv   (Wikipedia /For_machines — CC-BY-SA)
  - sources/norvig_spell_errors.csv   (Norvig — MIT code, mixed upstream data)

Both CSVs have header `misspelling,correct` (one misspelling -> one correct
per row). For each pair, looks up the correct form in the target JSON using
an inflection-aware index (word, lemma, primary_lemma, apiEnrichment
inflections); attaches `{"error": <misspelling>, "source": <SOURCE_TAG>}` to
the target entry's `commonLearnerErrors[]`. Idempotent and migration-aware:
legacy `{"wrong": …}` entries are rewritten to the canonical `{"error": …}`
shape.

Usage:
  python 04_add_common_misspellings_en.py
  python 04_add_common_misspellings_en.py --input grundwortschatz_en_enriched_v25.json
"""
import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).parent
DEFAULT_JSON = HERE / "grundwortschatz_en.json"
WIKI_CSV = HERE / "sources" / "commonly_misspelled.csv"
NORVIG_CSV = HERE / "sources" / "norvig_spell_errors.csv"

SRC_WIKI = "WIKI_MISSPELLINGS_EN"
SRC_NORVIG = "NORVIG_SPELL_ERRORS"


def load_pairs(csv_path: Path, source_tag: str) -> list[tuple[str, str, str]]:
    """Return list of (misspelling, correct, source_tag)."""
    out: list[tuple[str, str, str]] = []
    if not csv_path.exists():
        print(f"  [skip] {csv_path.name} not present", file=sys.stderr)
        return out
    with csv_path.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            mis = (row.get("misspelling") or "").strip().lower()
            cor = (row.get("correct") or "").strip().lower()
            if mis and cor and mis != cor:
                out.append((mis, cor, source_tag))
    return out


def build_inflection_index(vocabulary: list[dict]) -> dict[str, int]:
    """lowercase_form -> first vocabulary entry index that owns it."""
    idx: dict[str, int] = {}
    for i, e in enumerate(vocabulary):
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


def canonicalize_existing_cle(entry: dict) -> dict[str, str]:
    """Return {misspelling_lc: source_tag} from the entry's commonLearnerErrors.
    Handles legacy `{"wrong": …}` shape (misspelling-headword era) and the new
    `{"error": …}` shape, plus bare strings.
    """
    out: dict[str, str] = {}
    for item in entry.get("commonLearnerErrors") or []:
        if isinstance(item, str):
            out[item.lower()] = "LEGACY"
        elif isinstance(item, dict):
            mis = item.get("error") or item.get("misspelling") or item.get("form") or item.get("wrong")
            src = item.get("source") or "LEGACY"
            if mis:
                out[str(mis).lower()] = src
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=str(DEFAULT_JSON),
                    help="JSON vocab file to update in-place (default: grundwortschatz_en.json)")
    args = ap.parse_args()

    json_path = Path(args.input)
    if not json_path.exists():
        raise SystemExit(f"{json_path} not found")

    data = json.loads(json_path.read_text(encoding="utf-8"))
    voc = data["vocabulary"]
    print(f"loaded {len(voc)} entries from {json_path.name}")

    # Build inflection-aware lookup
    idx = build_inflection_index(voc)
    print(f"  inflection index has {len(idx)} keys")

    # Load misspelling pairs from both sources
    pairs: list[tuple[str, str, str]] = []
    pairs.extend(load_pairs(WIKI_CSV, SRC_WIKI))
    pairs.extend(load_pairs(NORVIG_CSV, SRC_NORVIG))
    print(f"  loaded {len(pairs)} (misspelling, correct, source) triples")

    attached_new = 0
    skipped_no_target = 0
    skipped_dup = 0
    updated_entries: set[int] = set()
    rewritten_legacy = 0

    for mis, cor, src in pairs:
        # Find target entry via inflection-aware match
        target_idx = idx.get(cor)
        if target_idx is None:
            skipped_no_target += 1
            continue
        entry = voc[target_idx]

        # Normalize existing entries to canonical shape first
        existing_map = canonicalize_existing_cle(entry)

        if mis in existing_map:
            skipped_dup += 1
            continue

        existing_map[mis] = src
        attached_new += 1
        updated_entries.add(target_idx)

    # Now rewrite every entry's commonLearnerErrors to canonical shape,
    # whether or not we added anything (gives us a free migration pass)
    for i, entry in enumerate(voc):
        cle = entry.get("commonLearnerErrors")
        if not cle:
            continue
        cmap = canonicalize_existing_cle(entry)
        canonical = [
            {"error": mis, "source": src}
            for mis, src in sorted(cmap.items())
        ]
        # Detect if we actually changed the shape
        legacy_shape = any(
            isinstance(c, dict) and "wrong" in c and "error" not in c
            for c in cle
        )
        if legacy_shape:
            rewritten_legacy += 1
        entry["commonLearnerErrors"] = canonical

    # Now re-walk attachments to make sure all new ones are reflected
    for mis, cor, src in pairs:
        target_idx = idx.get(cor)
        if target_idx is None:
            continue
        entry = voc[target_idx]
        cle = entry.get("commonLearnerErrors") or []
        if not any(isinstance(c, dict) and c.get("error") == mis for c in cle):
            cle.append({"error": mis, "source": src})
            entry["commonLearnerErrors"] = cle

    # Set tags on entries with at least one attached misspelling
    for i in updated_entries:
        e = voc[i]
        tags = set(e.get("tags") or [])
        tags.add("often_misspelled")
        tags.add("source:common_misspelled")
        e["tags"] = sorted(tags)

    # Metadata
    meta = data.setdefault("metadata", {})
    meta["common_misspellings_sources"] = [
        "Wikipedia:Lists of common misspellings/For machines (CC-BY-SA)",
        "Norvig spell-errors.txt (MIT code, mixed upstream data)",
    ]
    meta["common_misspellings_attached"] = attached_new
    meta["common_misspellings_skipped_no_target"] = skipped_no_target
    meta["common_misspellings_skipped_dup"] = skipped_dup
    meta["common_misspellings_legacy_shape_rewritten"] = rewritten_legacy

    json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print()
    print(f"Updated {len(updated_entries)} entries.")
    print(f"  attached new:           {attached_new}")
    print(f"  skipped (no target):    {skipped_no_target}")
    print(f"  skipped (already had):  {skipped_dup}")
    print(f"  legacy {{wrong:...}} → {{error:...}}: {rewritten_legacy} entries rewritten")
    return 0


if __name__ == "__main__":
    sys.exit(main())
