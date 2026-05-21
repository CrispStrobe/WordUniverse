#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Extract verb → case government statistics from UD German treebanks (.conllu)
and emit a JSON file.

Usage:
  python extract_verb_government.py \
      --input path/to/de_gsd-ud-train.conllu path/to/de_gsd-ud-dev.conllu \
      --output verb_government.json \
      --min-count 3

What it does:
- Parses sentences
- For each verb lemma, looks for bare objects (obj, iobj) and certain nmod dependents
- Reads the Case feature (Acc/Dat/Gen) on those dependents
- Tallies counts and keeps up to N example sentences per case
- Emits per-lemma stats with proportions

Limitations:
- Heuristic: counts nmod with Case=Gen as potential genitive objects (rare, can be possessive noise).
- Ignores prepositional objects (obl or nmod governed by ADP) to avoid conflating prepositions with verb government.
- Lemma normalization is basic (lowercasing).
"""

import argparse
import json
import sys
from collections import defaultdict, Counter
from pathlib import Path

try:
    from conllu import parse_incr
except ImportError:
    sys.stderr.write("Please install conllu: pip install conllu\n")
    sys.exit(1)

# UD tags and features helpers

VERB_UPOS = {"VERB", "AUX"}  # Keep AUX if you want to capture modal-led objects; can restrict to {"VERB"}
OBJ_LIKE = {"obj", "iobj"}   # Core object relations
# Genitive complements can appear as nmod in UD; we treat only genitive nmod directly attached to the verb.
POTENTIAL_GENITIVE_REL = {"nmod"}

# Case mapping from UD to our canonical names
CASE_MAP = {
    "Acc": "akkusativ",
    "Dat": "dativ",
    "Gen": "genitiv",
    # "Nom": "nominativ",  # Not a governed object case for our purpose
}

# How many example sentences to store per lemma+case
MAX_EXAMPLES_PER_CASE = 3


def token_case(token):
    """Return UD Case feature string like 'Acc', 'Dat', 'Gen' or None."""
    feats = token.get("feats") or {}
    case_val = feats.get("Case")
    if isinstance(case_val, list):
        # conllu lib might parse multi-valued feature as list
        return case_val[0] if case_val else None
    return case_val


def is_child_of_verb(token, sentence):
    """Check if token's head is a verb (by UPOS)."""
    head_id = token.get("head")
    if not head_id:
        return False
    # sentence tokens have "id" from 1..n (ints) for words
    if isinstance(head_id, int) and 1 <= head_id <= len(sentence):
        head_tok = sentence[head_id - 1]
        return head_tok.get("upos") in VERB_UPOS
    return False


def get_head_lemma(token, sentence):
    head_id = token.get("head")
    if not head_id:
        return None
    if isinstance(head_id, int) and 1 <= head_id <= len(sentence):
        head_tok = sentence[head_id - 1]
        return (head_tok.get("lemma") or "").lower(), head_tok
    return None


def sent_text(sentence):
    """Prefer the sent-level text if provided; else reconstruct from forms."""
    sent_meta = sentence.metadata or {}
    if "text" in sent_meta and sent_meta["text"]:
        return sent_meta["text"]
    # Reconstruct: simple join of FORM; ignores spaces around punctuation for simplicity
    forms = [tok.get("form") for tok in sentence if isinstance(tok.get("id"), int)]
    return " ".join(forms)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", nargs="+", required=True, help="UD .conllu file(s)")
    ap.add_argument("--output", required=True, help="Output JSON file path")
    ap.add_argument("--min-count", type=int, default=1, help="Minimum total governed-case count to include a verb")
    ap.add_argument("--keep-aux", action="store_true", help="Include AUX as heads (default True).")
    ap.add_argument("--max-examples", type=int, default=MAX_EXAMPLES_PER_CASE, help="Examples per case to store")
    args = ap.parse_args()

    # If --keep-aux not set, restrict to VERB only
    global VERB_UPOS
    if not args.keep_aux:
        VERB_UPOS = {"VERB"}

    MAX_EXAMPLES = max(0, args.max_examples)

    # Data structures
    counts = defaultdict(lambda: Counter())           # lemma -> Counter({'akkusativ': n, ...})
    totals = Counter()                                # lemma -> total count
    examples = defaultdict(lambda: defaultdict(list)) # lemma -> case -> [example strings]
    evidence_ids = defaultdict(lambda: defaultdict(list)) # lemma -> case -> [(file, sent_idx)]

    # Process each file
    for in_path in args.input:
        path = Path(in_path)
        if not path.exists():
            sys.stderr.write(f"Warning: file not found: {in_path}\n")
            continue
        with path.open("r", encoding="utf-8") as f:
            for sent_idx, sentence in enumerate(parse_incr(f), start=1):
                # For each token that could be an object-like dependent, check its head
                for tok in sentence:
                    if not isinstance(tok.get("id"), int):
                        continue  # skip multiword tokens and empty nodes
                    deprel = tok.get("deprel")
                    if deprel not in OBJ_LIKE and deprel not in POTENTIAL_GENITIVE_REL:
                        continue

                    # Must be directly attached to a verb head
                    head_info = get_head_lemma(tok, sentence)
                    if not head_info:
                        continue
                    head_lemma, head_tok = head_info
                    if head_tok.get("upos") not in VERB_UPOS:
                        continue

                    case_ud = token_case(tok)
                    if not case_ud:
                        continue
                    if case_ud not in CASE_MAP:
                        continue

                    # Heuristic: treat only obj/iobj for Acc/Dat; allow nmod only when Gen
                    if deprel in POTENTIAL_GENITIVE_REL and case_ud != "Gen":
                        continue

                    case_name = CASE_MAP[case_ud]
                    counts[head_lemma][case_name] += 1
                    totals[head_lemma] += 1

                    # Capture example sentence text (limit)
                    if MAX_EXAMPLES > 0 and len(examples[head_lemma][case_name]) < MAX_EXAMPLES:
                        txt = sent_text(sentence)
                        examples[head_lemma][case_name].append(txt)
                        evidence_ids[head_lemma][case_name].append((str(path.name), sent_idx))

    # Build output
    out_records = []
    for lemma, cdict in counts.items():
        total = totals[lemma]
        if total < args.min_count:
            continue
        # proportions
        props = {k: v / total for k, v in cdict.items()}
        # simple confidence: 1 - entropy-like dispersion (crude)
        # conf = max proportion (dominance)
        dominance = max(props.values()) if props else 0.0
        # Prepare examples
        case_examples = {}
        for k, exs in examples[lemma].items():
            case_examples[k] = [
                {
                    "text": ex,
                    "source": evidence_ids[lemma][k][i][0],
                    "sent_index": evidence_ids[lemma][k][i][1],
                }
                for i, ex in enumerate(exs)
            ]

        out_records.append({
            "lemma": lemma,
            "counts": dict(cdict),
            "total": total,
            "proportions": {k: round(v, 4) for k, v in props.items()},
            "dominant_case": max(cdict, key=cdict.get),
            "dominance": round(dominance, 4),
            "examples": case_examples,
            "notes": "Bare-case objects only; genitive via nmod; excludes prepositional objects."
        })

    # Sort by lemma for determinism
    out_records.sort(key=lambda r: r["lemma"])

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(out_records, f, ensure_ascii=False, indent=2)

    sys.stderr.write(f"Wrote {len(out_records)} verb entries to {out_path}\n")


if __name__ == "__main__":
    main()