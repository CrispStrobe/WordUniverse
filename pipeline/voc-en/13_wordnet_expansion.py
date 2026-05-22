"""Expand each vocab entry with full WordNet (OEWN) sense data.

Step 11b extracted OEWN data per the primary POS only. This step walks ALL
synsets for each lemma across all POS and adds:
- wordnetSenses[] under apiEnrichment: list of per-synset records with
  pos, definition, synonyms, antonyms, hypernyms, hyponyms (and hypernym chain
  going up 2 levels for game classification)
- Definitions are appended to apiEnrichment.definitions if there are fewer
  than 5 already, deduplicated case-insensitively against existing ones.
- Synonyms and antonyms are merged into apiEnrichment.synonyms / antonyms
  (deduplicated).

Adds no top-level fields outside apiEnrichment. The app reads
enrichment_json.wordnetSenses for game logic.

Usage:
    python 13_wordnet_expansion.py --input grundwortschatz_en_enriched_v25_consolidated.json
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import wn

HERE = Path(__file__).parent
DEFAULT_INPUT = HERE / "grundwortschatz_en_enriched_v25_consolidated.json"

POS_LABEL = {
    "n": "noun", "v": "verb", "a": "adjective",
    "s": "adjective", "r": "adverb", "t": "particle",
}

MAX_DEFS_PER_ENTRY = 8  # don't bloat; combined Wiktionary + WordNet capped


def get_lemmas(synsets, exclude_lc: str | None = None) -> list[str]:
    out: set[str] = set()
    for s in synsets:
        try:
            for l in s.lemmas():
                if exclude_lc and l.lower() == exclude_lc:
                    continue
                out.add(l)
        except Exception:
            continue
    return sorted(out)


def get_antonyms(sense) -> list[str]:
    out: set[str] = set()
    try:
        for ant_sense in sense.get_related("antonym"):
            try:
                out.add(ant_sense.word().lemma())
            except Exception:
                pass
    except Exception:
        pass
    return sorted(out)


def get_hypernym_chain(synset, depth: int = 2) -> list[list[str]]:
    """Walk up hypernyms `depth` levels; return list of [parent_lemma, ...]
    per level (level 0 = immediate parents)."""
    chain: list[list[str]] = []
    current = [synset]
    for _ in range(depth):
        next_level: list = []
        level_lemmas: set[str] = set()
        for s in current:
            try:
                for parent in s.hypernyms():
                    next_level.append(parent)
                    for l in parent.lemmas():
                        level_lemmas.add(l)
            except Exception:
                continue
        if not next_level:
            break
        chain.append(sorted(level_lemmas))
        current = next_level
    return chain


def expand_entry(wn_en, word: str) -> dict:
    """Return {'senses': [...], 'all_synonyms': [...], 'all_antonyms': [...],
                'all_hypernyms': [...], 'all_definitions': [...]}"""
    word_lc = word.lower()
    senses_out = []
    all_syn: set[str] = set()
    all_ant: set[str] = set()
    all_hyp: set[str] = set()
    all_defs: list[str] = []

    try:
        senses = wn_en.senses(word_lc)
    except Exception:
        return {"senses": [], "all_synonyms": [], "all_antonyms": [],
                "all_hypernyms": [], "all_definitions": []}

    for sense in senses:
        try:
            synset = sense.synset()
            pos_tag = synset.pos
            pos_label = POS_LABEL.get(pos_tag, pos_tag)
            definition = (synset.definition() or "").strip()
            synonyms = get_lemmas([synset], exclude_lc=word_lc)
            antonyms = get_antonyms(sense)
            hyps = get_lemmas(synset.hypernyms())
            hypo = get_lemmas(synset.hyponyms())
            holo = get_lemmas(synset.holonyms())
            mero = get_lemmas(synset.meronyms())
            hyp_chain = get_hypernym_chain(synset, depth=2)
            senses_out.append({
                "pos": pos_label,
                "definition": definition,
                "synonyms": synonyms,
                "antonyms": antonyms,
                "hypernyms": hyps,
                "hyponyms": hypo,
                "holonyms": holo,
                "meronyms": mero,
                "hypernymChain": hyp_chain,
            })
            all_syn.update(synonyms)
            all_ant.update(antonyms)
            all_hyp.update(hyps)
            if definition:
                all_defs.append(definition)
        except Exception:
            continue

    return {
        "senses": senses_out,
        "all_synonyms": sorted(all_syn),
        "all_antonyms": sorted(all_ant),
        "all_hypernyms": sorted(all_hyp),
        "all_definitions": all_defs,
    }


def merge_definitions(existing: list[str], from_wn: list[str], cap: int) -> list[str]:
    """Append WordNet defs to existing Wiktionary defs, dedup case-insensitive,
    cap at MAX_DEFS_PER_ENTRY."""
    seen_lc = {(d or "").strip().lower() for d in existing if isinstance(d, str)}
    out = list(existing)
    for d in from_wn:
        d_clean = (d or "").strip()
        if not d_clean:
            continue
        key = d_clean.lower()
        if key in seen_lc:
            continue
        seen_lc.add(key)
        out.append(d_clean)
        if len(out) >= cap:
            break
    return out


def merge_lists(existing, new: list[str]) -> list[str]:
    existing = existing or []
    seen = {(x or "").lower() for x in existing if isinstance(x, str)}
    out = list(existing)
    for n in new:
        if n.lower() not in seen:
            seen.add(n.lower())
            out.append(n)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=str(DEFAULT_INPUT))
    ap.add_argument("--output", default=None)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    in_path = Path(args.input)
    out_path = Path(args.output) if args.output else in_path

    print(f"Loading {in_path.name}…")
    data = json.loads(in_path.read_text(encoding="utf-8"))
    voc = data["vocabulary"]
    print(f"  {len(voc)} entries")

    print("Loading OEWN…")
    wn_en = wn.Wordnet("oewn:2024")

    targets = [e for e in voc
               if isinstance(e.get("apiEnrichment"), dict)
               and e["apiEnrichment"].get("enrichment_status") == "success"]
    if args.limit:
        targets = targets[:args.limit]
    print(f"  {len(targets)} entries to expand")

    t_start = time.time()
    expanded = 0
    senses_total = 0
    defs_added = 0
    syn_added = 0
    ant_added = 0
    hyp_added = 0

    for i, e in enumerate(targets, 1):
        word = e.get("word") or ""
        if not word:
            continue
        ae = e["apiEnrichment"]
        expanded_data = expand_entry(wn_en, word)
        if not expanded_data["senses"]:
            continue
        ae["wordnetSenses"] = expanded_data["senses"]
        senses_total += len(expanded_data["senses"])

        existing_defs = ae.get("definitions") or []
        new_defs = merge_definitions(existing_defs, expanded_data["all_definitions"], MAX_DEFS_PER_ENTRY)
        if len(new_defs) > len(existing_defs):
            defs_added += len(new_defs) - len(existing_defs)
        ae["definitions"] = new_defs

        prev_syn = ae.get("synonyms") or []
        merged_syn = merge_lists(prev_syn, expanded_data["all_synonyms"])
        if len(merged_syn) > len(prev_syn):
            syn_added += len(merged_syn) - len(prev_syn)
        ae["synonyms"] = merged_syn

        prev_ant = ae.get("antonyms") or []
        merged_ant = merge_lists(prev_ant, expanded_data["all_antonyms"])
        if len(merged_ant) > len(prev_ant):
            ant_added += len(merged_ant) - len(prev_ant)
        ae["antonyms"] = merged_ant

        # Merge hypernyms: existing is list of {"hypernym_word": str} dicts
        existing_hyp = ae.get("hypernyms") or []
        existing_hyp_words = {
            (x.get("hypernym_word") if isinstance(x, dict) else x or "").lower()
            for x in existing_hyp
        }
        for h in expanded_data["all_hypernyms"]:
            if h.lower() not in existing_hyp_words:
                existing_hyp.append({"hypernym_word": h, "source": "OEWN"})
                existing_hyp_words.add(h.lower())
                hyp_added += 1
        if existing_hyp:
            ae["hypernyms"] = existing_hyp

        expanded += 1
        if i % 500 == 0:
            elapsed = time.time() - t_start
            rate = i / elapsed
            eta = (len(targets) - i) / rate
            print(f"  [{i}/{len(targets)}] {word!r} | rate={rate:.0f}/s "
                  f"| ETA={eta:.0f}s | senses_total={senses_total}")

    elapsed = time.time() - t_start
    print()
    print(f"Done in {elapsed:.1f}s")
    print(f"  entries expanded:        {expanded}")
    print(f"  total wordnet senses:    {senses_total}")
    print(f"  new defs appended:       {defs_added}")
    print(f"  new synonyms added:      {syn_added}")
    print(f"  new antonyms added:      {ant_added}")
    print(f"  new hypernyms added:     {hyp_added}")

    data.setdefault("metadata", {})["wordnet_expansion"] = {
        "expanded": expanded,
        "senses_total": senses_total,
        "defs_added": defs_added,
        "synonyms_added": syn_added,
        "antonyms_added": ant_added,
        "hypernyms_added": hyp_added,
    }

    out_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nWrote {out_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
