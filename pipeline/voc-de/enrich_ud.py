#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Consolidated UD German Grammar Extractor
=========================================

Extracts multiple grammatical features from UD German treebanks to enrich
the grundwortschatz database with corpus-based grammar information.

Features:
- Verb case government (bare objects: Akk/Dat/Gen)
- Prepositional objects (Verb + Prep + Case) - separated by case
- Preposition case requirements
- Adjective declension patterns
- Nominalizations
- Always selects the 5 shortest example sentences

Usage:
    python extract_ud.py \\
        --grundwortschatz grundwortschatz_with_errors.json \\
        --ud-dirs UD_German-GSD UD_German-HDT \\
        --output grundwortschatz_enriched_ud.json \\
        --max-examples 5 \\
        --min-count 3
"""

import argparse
import json
import sys
from collections import defaultdict, Counter
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set
import re

try:
    from conllu import parse_incr
except ImportError:
    sys.stderr.write("ERROR: Please install conllu: pip install conllu\n")
    sys.exit(1)

# ============================================================================
# CONSTANTS
# ============================================================================

VERB_UPOS = {"VERB"}  # Only main verbs, not AUX
NOUN_UPOS = {"NOUN", "PROPN"}
ADJ_UPOS = {"ADJ"}
ADP_UPOS = {"ADP"}

# Dependency relations
OBJ_LIKE = {"obj", "iobj"}  # Core objects
POTENTIAL_GENITIVE_REL = {"nmod"}
PREPOSITIONAL_OBJ = {"obl"}  # Prepositional objects

# Case mapping
CASE_MAP = {
    "Acc": "akkusativ",
    "Dat": "dativ",
    "Gen": "genitiv",
    "Nom": "nominativ",
}

# Gender mapping
GENDER_MAP = {
    "Masc": "maskulin",
    "Fem": "feminin",
    "Neut": "neutrum",
}

# Number mapping
NUMBER_MAP = {
    "Sing": "singular",
    "Plur": "plural",
}

# Motion verbs (for Wechselpräpositionen context)
MOTION_VERBS = {
    "gehen", "laufen", "rennen", "fahren", "fliegen", "reisen",
    "kommen", "bringen", "tragen", "legen", "stellen", "setzen",
    "hängen", "werfen", "schicken", "schieben", "ziehen", "springen",
    "fallen", "steigen", "klettern", "schwimmen", "tauchen"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def normalize_lemma(lemma: str) -> str:
    """Normalize lemma to match grundwortschatz format."""
    if not lemma or lemma == "_":
        return ""
    # Remove reflexive particles
    lemma = re.sub(r'\s*\(sich\)$', '', lemma)
    # Remove leading/trailing whitespace
    lemma = lemma.strip().lower()
    # Replace multiple spaces
    lemma = re.sub(r'\s+', ' ', lemma)
    return lemma


def token_case(token) -> Optional[str]:
    """Extract Case feature from token."""
    feats = token.get("feats") or {}
    case_val = feats.get("Case")
    if isinstance(case_val, list):
        return case_val[0] if case_val else None
    return case_val


def token_gender(token) -> Optional[str]:
    """Extract Gender feature from token."""
    feats = token.get("feats") or {}
    gender = feats.get("Gender")
    if isinstance(gender, list):
        return gender[0] if gender else None
    return gender


def token_number(token) -> Optional[str]:
    """Extract Number feature from token."""
    feats = token.get("feats") or {}
    number = feats.get("Number")
    if isinstance(number, list):
        return number[0] if number else None
    return number


def sent_text(sentence) -> str:
    """Get sentence text, prefer metadata."""
    sent_meta = sentence.metadata or {}
    if "text" in sent_meta and sent_meta["text"]:
        text = sent_meta["text"].strip()
        # Remove multiple spaces
        text = re.sub(r'\s+', ' ', text)
        return text
    # Reconstruct from forms
    forms = []
    for tok in sentence:
        if isinstance(tok.get("id"), int):
            form = tok.get("form", "")
            if form:
                forms.append(form)
    return " ".join(forms)


def sent_length(text: str) -> int:
    """Count words in sentence (for sorting by length)."""
    return len(text.split())


def get_head_token(token, sentence):
    """Get the head token of a given token."""
    head_id = token.get("head")
    if not head_id:
        return None
    if isinstance(head_id, int) and 1 <= head_id <= len(sentence):
        return sentence[head_id - 1]
    return None


def get_children(token, sentence) -> List:
    """Get all children of a token."""
    token_id = token.get("id")
    if not isinstance(token_id, int):
        return []
    children = []
    for tok in sentence:
        if isinstance(tok.get("id"), int) and tok.get("head") == token_id:
            children.append(tok)
    return children


def has_adp_child(token, sentence) -> bool:
    """Check if token has an ADP (preposition) child."""
    children = get_children(token, sentence)
    return any(child.get("upos") == "ADP" and child.get("deprel") == "case" 
               for child in children)


def is_valid_sentence(text: str) -> bool:
    """Check if sentence is valid (not too long, not URL-heavy, etc.)."""
    if len(text) > 1000:  # Skip extremely long sentences
        return False
    if text.count("http") > 2:  # Skip sentences with many URLs
        return False
    if text.count("@") > 2:  # Skip email-heavy text
        return False
    return True


# ============================================================================
# EXTRACTOR CLASSES
# ============================================================================

class VerbCaseGovernmentExtractor:
    """Extract verb case government (bare objects only)."""
    
    def __init__(self, max_examples: int = 5):
        self.max_examples = max_examples
        # lemma -> case -> list of examples
        self.data = defaultdict(lambda: defaultdict(list))
    
    def process_sentence(self, sentence, source: str, sent_idx: int):
        """Process one sentence for verb case government."""
        text = sent_text(sentence)
        if not is_valid_sentence(text):
            return
        
        length = sent_length(text)
        
        for tok in sentence:
            if not isinstance(tok.get("id"), int):
                continue
            
            deprel = tok.get("deprel")
            if deprel not in OBJ_LIKE and deprel not in POTENTIAL_GENITIVE_REL:
                continue
            
            # Get verb head
            head_tok = get_head_token(tok, sentence)
            if not head_tok or head_tok.get("upos") not in VERB_UPOS:
                continue
            
            # Check if it's a bare object (no preposition)
            if has_adp_child(tok, sentence):
                continue
            
            case_ud = token_case(tok)
            if not case_ud or case_ud not in CASE_MAP:
                continue
            
            # Genitive only via nmod (and must be direct dependency)
            if deprel in POTENTIAL_GENITIVE_REL and case_ud != "Gen":
                continue
            
            verb_lemma = normalize_lemma(head_tok.get("lemma", ""))
            if not verb_lemma or verb_lemma == "--":
                continue
            
            case_name = CASE_MAP[case_ud]
            
            # Store example
            self.data[verb_lemma][case_name].append({
                "text": text,
                "length": length,
                "source": source,
                "sent_index": sent_idx
            })
    
    def get_results(self, min_count: int = 3) -> Dict:
        """Get results for all verbs, keeping only shortest examples."""
        results = {}
        
        for lemma, case_data in self.data.items():
            # Calculate total and counts
            all_examples = []
            counts = Counter()
            
            for case_name, examples in case_data.items():
                counts[case_name] = len(examples)
                all_examples.extend(examples)
            
            total = sum(counts.values())
            if total < min_count:
                continue
            
            # Calculate proportions
            props = {k: v / total for k, v in counts.items()}
            dominant = max(counts, key=counts.get)
            
            # Sort each case's examples by length and keep shortest
            examples_by_case = {}
            for case_name, examples in case_data.items():
                sorted_examples = sorted(examples, key=lambda x: x["length"])
                examples_by_case[case_name] = sorted_examples[:self.max_examples]
            
            results[lemma] = {
                "case_government": {
                    "counts": dict(counts),
                    "total": total,
                    "proportions": {k: round(v, 4) for k, v in props.items()},
                    "dominant_case": dominant,
                    "confidence": round(props[dominant], 4),
                    "examples": examples_by_case
                }
            }
        
        return results


class PrepositionalObjectExtractor:
    """Extract prepositional objects (Verb + Prep + Case) - separated by case."""
    
    def __init__(self, max_examples: int = 5):
        self.max_examples = max_examples
        # verb_lemma -> prep -> case -> list of examples
        self.data = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    
    def process_sentence(self, sentence, source: str, sent_idx: int):
        """Process one sentence for prepositional objects."""
        text = sent_text(sentence)
        if not is_valid_sentence(text):
            return
        
        length = sent_length(text)
        
        for tok in sentence:
            if not isinstance(tok.get("id"), int):
                continue
            
            deprel = tok.get("deprel")
            if deprel not in PREPOSITIONAL_OBJ:
                continue
            
            # Must have verb head
            head_tok = get_head_token(tok, sentence)
            if not head_tok or head_tok.get("upos") not in VERB_UPOS:
                continue
            
            # Find the preposition child
            prep_tok = None
            for child in get_children(tok, sentence):
                if child.get("deprel") == "case" and child.get("upos") in ADP_UPOS:
                    prep_tok = child
                    break
            
            if not prep_tok:
                continue
            
            case_ud = token_case(tok)
            if not case_ud or case_ud not in CASE_MAP:
                continue
            
            verb_lemma = normalize_lemma(head_tok.get("lemma", ""))
            prep_lemma = normalize_lemma(prep_tok.get("lemma", ""))
            
            if not verb_lemma or not prep_lemma or verb_lemma == "--" or prep_lemma == "--":
                continue
            
            case_name = CASE_MAP[case_ud]
            
            # Check if governing verb is motion verb (for context)
            is_motion = verb_lemma in MOTION_VERBS
            
            # Store example under verb -> prep -> case
            self.data[verb_lemma][prep_lemma][case_name].append({
                "text": text,
                "length": length,
                "motion_verb": is_motion,
                "source": source,
                "sent_index": sent_idx
            })
    
    def get_results(self, min_count: int = 2) -> Dict:
        """Get results for all verb+prep combinations, separated by case."""
        results = {}
        
        for verb_lemma, prep_data in self.data.items():
            prep_objects = {}
            
            for prep_lemma, case_data in prep_data.items():
                # Check if this prep appears with multiple cases (Wechselpräposition)
                cases_found = list(case_data.keys())
                is_wechsel = len(cases_found) > 1
                
                for case_name, examples in case_data.items():
                    if len(examples) < min_count:
                        continue
                    
                    # Sort by length and keep shortest
                    sorted_examples = sorted(examples, key=lambda x: x["length"])
                    shortest = sorted_examples[:self.max_examples]
                    
                    # Create key: prep+case for Wechselpräpositionen, otherwise just prep
                    if is_wechsel:
                        key = f"{prep_lemma}+{case_name}"
                    else:
                        key = prep_lemma
                    
                    prep_objects[key] = {
                        "preposition": prep_lemma,
                        "case": case_name,
                        "count": len(examples),
                        "examples": shortest,
                        "is_wechselpraposition": is_wechsel,
                        "all_cases": cases_found if is_wechsel else [case_name]
                    }
            
            if prep_objects:
                if verb_lemma not in results:
                    results[verb_lemma] = {}
                results[verb_lemma]["prepositional_objects"] = prep_objects
        
        return results


class PrepositionCaseExtractor:
    """Extract general preposition case requirements."""
    
    def __init__(self, max_examples: int = 5):
        self.max_examples = max_examples
        # prep -> case -> list of examples
        self.data = defaultdict(lambda: defaultdict(list))
    
    def process_sentence(self, sentence, source: str, sent_idx: int):
        """Process one sentence for preposition cases."""
        text = sent_text(sentence)
        if not is_valid_sentence(text):
            return
        
        length = sent_length(text)
        
        for tok in sentence:
            if not isinstance(tok.get("id"), int):
                continue
            
            if tok.get("upos") not in ADP_UPOS:
                continue
            
            if tok.get("deprel") != "case":
                continue
            
            # Get the noun it governs
            head_tok = get_head_token(tok, sentence)
            if not head_tok:
                continue
            
            case_ud = token_case(head_tok)
            if not case_ud or case_ud not in CASE_MAP:
                continue
            
            prep_lemma = normalize_lemma(tok.get("lemma", ""))
            if not prep_lemma or prep_lemma == "--":
                continue
            
            case_name = CASE_MAP[case_ud]
            
            # Check if the governing verb is a motion verb
            is_motion = False
            verb_head = get_head_token(head_tok, sentence)
            if verb_head and verb_head.get("upos") in VERB_UPOS:
                verb_lemma = normalize_lemma(verb_head.get("lemma", ""))
                is_motion = verb_lemma in MOTION_VERBS
            
            # Store example
            self.data[prep_lemma][case_name].append({
                "text": text,
                "length": length,
                "motion_context": is_motion,
                "source": source,
                "sent_index": sent_idx
            })
    
    def get_results(self, min_count: int = 10) -> Dict:
        """Get results for all prepositions."""
        results = {}
        
        for prep, case_data in self.data.items():
            # Calculate totals
            all_examples = []
            counts = Counter()
            
            for case_name, examples in case_data.items():
                counts[case_name] = len(examples)
                all_examples.extend(examples)
            
            total = sum(counts.values())
            if total < min_count:
                continue
            
            # Sort examples by length for each case
            cases = {}
            for case_name, examples in case_data.items():
                if len(examples) < 2:
                    continue
                
                sorted_examples = sorted(examples, key=lambda x: x["length"])
                shortest = sorted_examples[:self.max_examples]
                
                cases[case_name] = {
                    "count": len(examples),
                    "proportion": round(len(examples) / total, 4),
                    "examples": shortest
                }
            
            if not cases:
                continue
            
            # Determine if Wechselpräposition
            dominant_case = max(cases, key=lambda k: cases[k]["count"])
            max_prop = max(cases[k]["proportion"] for k in cases)
            is_wechsel = len(cases) > 1 and max_prop < 0.90
            
            results[prep] = {
                "cases": cases,
                "total_count": total,
                "dominant_case": dominant_case,
                "is_wechselpraposition": is_wechsel,
                "case_distribution": {k: cases[k]["proportion"] for k in cases}
            }
        
        return results


class AdjectiveDeclensionExtractor:
    """Extract adjective declension examples."""
    
    def __init__(self, max_examples: int = 5):
        self.max_examples = max_examples
        # adj_lemma -> list of examples
        self.data = defaultdict(list)
    
    def process_sentence(self, sentence, source: str, sent_idx: int):
        """Process one sentence for adjective declensions."""
        text = sent_text(sentence)
        if not is_valid_sentence(text):
            return
        
        length = sent_length(text)
        
        for tok in sentence:
            if not isinstance(tok.get("id"), int):
                continue
            
            if tok.get("upos") not in ADJ_UPOS:
                continue
            
            deprel = tok.get("deprel")
            if deprel != "amod":  # Attributive adjectives only
                continue
            
            # Get the noun it modifies
            head_tok = get_head_token(tok, sentence)
            if not head_tok or head_tok.get("upos") not in NOUN_UPOS:
                continue
            
            adj_lemma = normalize_lemma(tok.get("lemma", ""))
            if not adj_lemma or adj_lemma == "--":
                continue
            
            # Try to get case from adjective, fall back to noun
            case_ud = token_case(tok)
            if not case_ud:
                case_ud = token_case(head_tok)
            
            gender_ud = token_gender(tok)
            if not gender_ud:
                gender_ud = token_gender(head_tok)
            
            number_ud = token_number(tok)
            if not number_ud:
                number_ud = token_number(head_tok)
            
            case_name = CASE_MAP.get(case_ud) if case_ud else "unknown"
            gender_name = GENDER_MAP.get(gender_ud) if gender_ud else "unknown"
            number_name = NUMBER_MAP.get(number_ud) if number_ud else "unknown"
            
            # Check if there's a determiner
            has_det = False
            for sibling in sentence:
                if (isinstance(sibling.get("id"), int) and 
                    sibling.get("head") == head_tok.get("id") and
                    sibling.get("deprel") == "det"):
                    has_det = True
                    break
            
            # Store example
            self.data[adj_lemma].append({
                "text": text,
                "length": length,
                "adj_form": tok.get("form", ""),
                "noun": head_tok.get("form", ""),
                "case": case_name,
                "gender": gender_name,
                "number": number_name,
                "has_determiner": has_det,
                "source": source,
                "sent_index": sent_idx
            })
    
    def get_results(self, min_count: int = 1) -> Dict:
        """Get results for all adjectives."""
        results = {}
        
        for adj_lemma, examples in self.data.items():
            if len(examples) < min_count:
                continue
            
            # Sort by length and keep shortest
            sorted_examples = sorted(examples, key=lambda x: x["length"])
            shortest = sorted_examples[:self.max_examples]
            
            results[adj_lemma] = {
                "declension_examples": shortest,
                "total_examples": len(examples)
            }
        
        return results


class NominalizationExtractor:
    """Extract nominalized verbs and adjectives."""
    
    def __init__(self, max_examples: int = 5):
        self.max_examples = max_examples
        # base_lemma -> list of examples
        self.nominalizations = defaultdict(list)
    
    def process_sentence(self, sentence, source: str, sent_idx: int):
        """Process one sentence for nominalizations."""
        text = sent_text(sentence)
        if not is_valid_sentence(text):
            return
        
        length = sent_length(text)
        
        for tok in sentence:
            if not isinstance(tok.get("id"), int):
                continue
            
            if tok.get("upos") not in NOUN_UPOS:
                continue
            
            form = tok.get("form", "")
            lemma = tok.get("lemma", "")
            
            if not form or not lemma or lemma == "--":
                continue
            
            # Heuristic: capitalized verb infinitives (das Laufen, das Schwimmen)
            is_nominalized = False
            base_lemma = None
            nom_type = None
            
            # Check for infinitive nominalization
            if lemma.endswith("en") and form[0].isupper() and len(lemma) > 2:
                # Additional check: should have a determiner
                has_det = False
                for sibling in sentence:
                    if (isinstance(sibling.get("id"), int) and 
                        sibling.get("head") == tok.get("id") and
                        sibling.get("deprel") == "det"):
                        has_det = True
                        break
                
                if has_det:
                    is_nominalized = True
                    base_lemma = lemma.lower()
                    nom_type = "infinitive"
            
            if not is_nominalized:
                continue
            
            # Store example
            self.nominalizations[base_lemma].append({
                "text": text,
                "length": length,
                "nominalized_form": form,
                "type": nom_type,
                "source": source,
                "sent_index": sent_idx
            })
    
    def get_results(self, min_count: int = 1) -> Dict:
        """Get results for nominalizations."""
        results = {}
        
        for lemma, examples in self.nominalizations.items():
            if len(examples) < min_count:
                continue
            
            # Sort by length and keep shortest
            sorted_examples = sorted(examples, key=lambda x: x["length"])
            shortest = sorted_examples[:self.max_examples]
            
            results[lemma] = {
                "nominalization_examples": shortest,
                "can_be_nominalized": True
            }
        
        return results


# ============================================================================
# MAIN PROCESSING
# ============================================================================

def process_ud_directory(ud_dir: Path, extractors: dict, corpus_name: str):
    """Process all .conllu files in a UD directory."""
    conllu_files = sorted(list(ud_dir.glob("*.conllu")))
    
    if not conllu_files:
        sys.stderr.write(f"Warning: No .conllu files found in {ud_dir}\n")
        return
    
    print(f"\n📂 Processing {corpus_name}: {len(conllu_files)} file(s)", file=sys.stderr)
    
    for conllu_path in conllu_files:
        file_name = conllu_path.name
        source = f"{corpus_name}/{file_name}"
        
        print(f"  📄 {file_name}...", end="", file=sys.stderr, flush=True)
        
        sent_count = 0
        try:
            with conllu_path.open("r", encoding="utf-8") as f:
                for sent_idx, sentence in enumerate(parse_incr(f), start=1):
                    try:
                        for extractor in extractors.values():
                            extractor.process_sentence(sentence, source, sent_idx)
                        sent_count += 1
                    except Exception as e:
                        # Skip problematic sentences
                        continue
        except Exception as e:
            print(f" ERROR: {e}", file=sys.stderr)
            continue
        
        print(f" {sent_count} sentences", file=sys.stderr)


def merge_results(all_results: List[Dict]) -> Dict:
    """Merge results from multiple extractors into one dict per lemma."""
    merged = {}
    
    for results in all_results:
        for lemma, data in results.items():
            if lemma not in merged:
                merged[lemma] = {}
            merged[lemma].update(data)
    
    return merged


def enrich_grundwortschatz(grundwortschatz_data: Dict, grammar_data: Dict) -> Tuple[Dict, Counter]:
    """Enrich grundwortschatz entries with grammar data."""
    enrichment_stats = Counter()
    
    # Extract vocabulary list
    vocabulary = grundwortschatz_data.get("vocabulary", [])
    enriched_vocabulary = []
    
    for entry in vocabulary:
        lemma = normalize_lemma(entry.get("lemma", ""))
        
        if lemma and lemma in grammar_data:
            entry["grammar"] = grammar_data[lemma]
            enrichment_stats["enriched"] += 1
            
            # Count what types of enrichment
            if "case_government" in grammar_data[lemma]:
                enrichment_stats["case_government"] += 1
            if "prepositional_objects" in grammar_data[lemma]:
                enrichment_stats["prepositional_objects"] += 1
            if "declension_examples" in grammar_data[lemma]:
                enrichment_stats["declension_examples"] += 1
            if "nominalization_examples" in grammar_data[lemma]:
                enrichment_stats["nominalization"] += 1
        else:
            enrichment_stats["not_enriched"] += 1
        
        enriched_vocabulary.append(entry)
    
    # Reconstruct the full structure
    enriched_data = {
        "metadata": grundwortschatz_data.get("metadata", {}),
        "vocabulary": enriched_vocabulary
    }
    
    # Update metadata with enrichment info
    enriched_data["metadata"]["grammar_enrichment"] = {
        "enriched_entries": enrichment_stats["enriched"],
        "total_entries": len(vocabulary),
        "enrichment_rate": round(enrichment_stats["enriched"] / len(vocabulary), 4) if vocabulary else 0,
        "features": {
            "case_government": enrichment_stats["case_government"],
            "prepositional_objects": enrichment_stats["prepositional_objects"],
            "declension_examples": enrichment_stats["declension_examples"],
            "nominalizations": enrichment_stats["nominalization"]
        }
    }
    
    return enriched_data, enrichment_stats


def main():
    parser = argparse.ArgumentParser(
        description="Extract grammar features from UD German corpora",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage
  python extract_ud.py \\
      --grundwortschatz grundwortschatz_with_errors.json \\
      --ud-dirs UD_German-GSD UD_German-HDT \\
      --output grundwortschatz_enriched_ud.json
  
  # With separate preposition reference
  python extract_ud.py \\
      --grundwortschatz grundwortschatz_with_errors.json \\
      --ud-dirs UD_German-GSD UD_German-HDT \\
      --output grundwortschatz_enriched_ud.json \\
      --prep-output prepositions_reference.json \\
      --max-examples 10 \\
      --min-count 2
        """
    )
    parser.add_argument(
        "--grundwortschatz",
        required=True,
        help="Input grundwortschatz JSON file"
    )
    parser.add_argument(
        "--ud-dirs",
        nargs="+",
        required=True,
        help="UD directory paths (e.g., UD_German-GSD UD_German-HDT)"
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output enriched JSON file"
    )
    parser.add_argument(
        "--max-examples",
        type=int,
        default=5,
        help="Maximum number of example sentences per feature (default: 5)"
    )
    parser.add_argument(
        "--min-count",
        type=int,
        default=3,
        help="Minimum count to include a feature (default: 3)"
    )
    parser.add_argument(
        "--prep-output",
        help="Optional: separate output file for preposition reference data"
    )
    
    args = parser.parse_args()
    
    # Load grundwortschatz
    print(f"📖 Loading grundwortschatz from {args.grundwortschatz}", file=sys.stderr)
    try:
        with open(args.grundwortschatz, "r", encoding="utf-8") as f:
            grundwortschatz_data = json.load(f)
    except Exception as e:
        sys.stderr.write(f"ERROR: Cannot load grundwortschatz: {e}\n")
        sys.exit(1)
    
    # Handle both old format (list) and new format (dict with metadata + vocabulary)
    if isinstance(grundwortschatz_data, list):
        # Old format: convert to new format
        grundwortschatz_data = {
            "metadata": {
                "description": "Grundwortschatz",
                "total_words": len(grundwortschatz_data)
            },
            "vocabulary": grundwortschatz_data
        }
    
    vocabulary = grundwortschatz_data.get("vocabulary", [])
    print(f"   Loaded {len(vocabulary)} entries", file=sys.stderr)
    
    # Initialize extractors
    extractors = {
        "verb_case": VerbCaseGovernmentExtractor(args.max_examples),
        "prep_obj": PrepositionalObjectExtractor(args.max_examples),
        "prep_case": PrepositionCaseExtractor(args.max_examples),
        "adj_decl": AdjectiveDeclensionExtractor(args.max_examples),
        "nominal": NominalizationExtractor(args.max_examples),
    }
    
    # Process each UD directory
    for ud_dir_str in args.ud_dirs:
        ud_dir = Path(ud_dir_str)
        if not ud_dir.exists():
            sys.stderr.write(f"Warning: Directory not found: {ud_dir_str}\n")
            continue
        
        corpus_name = ud_dir.name.replace("UD_German-", "")
        process_ud_directory(ud_dir, extractors, corpus_name)
    
    # Get results from each extractor
    print("\n📊 Collecting results...", file=sys.stderr)
    
    verb_case_results = extractors["verb_case"].get_results(args.min_count)
    print(f"   Verb case government: {len(verb_case_results)} verbs", file=sys.stderr)
    
    prep_obj_results = extractors["prep_obj"].get_results(2)
    print(f"   Prepositional objects: {len(prep_obj_results)} verbs", file=sys.stderr)
    
    prep_case_results = extractors["prep_case"].get_results(10)
    print(f"   Preposition cases: {len(prep_case_results)} prepositions", file=sys.stderr)
    
    adj_decl_results = extractors["adj_decl"].get_results(1)
    print(f"   Adjective declensions: {len(adj_decl_results)} adjectives", file=sys.stderr)
    
    nominal_results = extractors["nominal"].get_results(1)
    print(f"   Nominalizations: {len(nominal_results)} forms", file=sys.stderr)
    
    # Merge results
    all_grammar_data = merge_results([
        verb_case_results,
        prep_obj_results,
        adj_decl_results,
        nominal_results
    ])
    
    # Enrich grundwortschatz
    print("\n🔗 Enriching grundwortschatz...", file=sys.stderr)
    enriched_data, stats = enrich_grundwortschatz(grundwortschatz_data, all_grammar_data)
    
    print(f"   Enriched: {stats['enriched']} entries", file=sys.stderr)
    print(f"   - Case government: {stats['case_government']}", file=sys.stderr)
    print(f"   - Prepositional objects: {stats['prepositional_objects']}", file=sys.stderr)
    print(f"   - Declension examples: {stats['declension_examples']}", file=sys.stderr)
    print(f"   - Nominalizations: {stats['nominalization']}", file=sys.stderr)
    print(f"   Not enriched: {stats['not_enriched']} entries", file=sys.stderr)
    
    # Save enriched grundwortschatz
    print(f"\n💾 Writing enriched data to {args.output}", file=sys.stderr)
    try:
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(enriched_data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        sys.stderr.write(f"ERROR: Cannot write output: {e}\n")
        sys.exit(1)
    
    # Optionally save separate preposition data
    if args.prep_output:
        print(f"💾 Writing preposition reference to {args.prep_output}", file=sys.stderr)
        try:
            with open(args.prep_output, "w", encoding="utf-8") as f:
                json.dump(prep_case_results, f, ensure_ascii=False, indent=2)
        except Exception as e:
            sys.stderr.write(f"ERROR: Cannot write prep output: {e}\n")
    
    print("\n✅ Done!", file=sys.stderr)
    print(f"\n📈 Enrichment Summary:", file=sys.stderr)
    print(f"   Enriched: {stats['enriched']} / {len(vocabulary)} entries "
          f"({100*stats['enriched']/len(vocabulary):.1f}%)", file=sys.stderr)
    print(f"   Case government: {stats['case_government']} verbs", file=sys.stderr)
    print(f"   Prepositional objects: {stats['prepositional_objects']} verbs", file=sys.stderr)
    print(f"   Declension examples: {stats['declension_examples']} adjectives", file=sys.stderr)
    print(f"   Nominalizations: {stats['nominalization']} forms", file=sys.stderr)


if __name__ == "__main__":
    main()