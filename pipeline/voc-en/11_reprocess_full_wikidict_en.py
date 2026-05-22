"""Enrich EN vocabulary through the cstr/WiktionaryEN Gradio API.

This is the English mirror of voc-de/11_reprocess_full_wikidict.py, trimmed to
the language-agnostic fields the app already understands. It is resumable and
supports --limit for smoke tests.
"""
import argparse
import json
import time
import traceback
from pathlib import Path

from gradio_client import Client

try:
    from tqdm import tqdm
except ImportError:
    def tqdm(iterable, **kwargs):
        return iterable

HERE = Path(__file__).parent
INPUT_JSON = HERE / "grundwortschatz_en.json"
OUTPUT_JSON = HERE / "grundwortschatz_en_enriched_v24.json"
CHECKPOINT_FILE = HERE / "enrichment_checkpoint_en_v24.json"
GRADIO_API_URL = "cstr/WiktionaryEN"
DELAY_BETWEEN_CALLS = 0.5
CHECKPOINT_INTERVAL = 25
TOP_N_SEMANTICS = 5

WORDTYPE_TO_POS = {
    "noun": "noun",
    "verb": "verb",
    "adjective": "adjective",
    "adverb": "adverb",
    "pronoun": "pron",
    "article": "det",
    "preposition": "adp",
    "conjunction": "conj",
    "particle": "part",
    "numeral": "num",
    "interjection": "intj",
    "andere": "other",
}


def load_data(input_path, output_path):
    if output_path.exists():
        try:
            return json.loads(output_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"Could not parse {output_path.name}; loading clean input.")
    return json.loads(input_path.read_text(encoding="utf-8"))


def load_checkpoint(vocabulary, retry_errors):
    processed = set()
    if CHECKPOINT_FILE.exists():
        checkpoint = json.loads(CHECKPOINT_FILE.read_text(encoding="utf-8"))
        processed.update(checkpoint.get("processed_words", []))

    for entry in vocabulary:
        status = (entry.get("apiEnrichment") or {}).get("enrichment_status")
        if status == "error" and retry_errors and entry.get("id"):
            processed.discard(entry["id"])
            continue
        if status in {"success", "no_data"} or (status == "error" and not retry_errors):
            if entry.get("id"):
                processed.add(entry["id"])
    return processed


def save_checkpoint(processed):
    CHECKPOINT_FILE.write_text(
        json.dumps({"processed_words": sorted(processed)}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def first_primary_entry(analysis, primary_pos):
    if isinstance(analysis.get(primary_pos), list) and analysis[primary_pos]:
        return primary_pos, analysis[primary_pos][0]
    for pos, entries in analysis.items():
        if isinstance(entries, list) and entries:
            return pos, entries[0]
    return None, None


def limited(items, limit, no_limits):
    if not isinstance(items, list):
        return []
    return items if no_limits or limit is None else items[:limit]


def build_enrichment(api_response, primary_pos, no_limits=False):
    analysis = api_response.get("analysis") or {}
    primary_pos_key, primary_entry = first_primary_entry(analysis, primary_pos)
    if not primary_entry:
        return {"enrichment_status": "no_data"}

    semantics = primary_entry.get("semantics_combined") or primary_entry.get("semantics") or {}
    wikt_meta = primary_entry.get("wiktionary_metadata") or {}
    wikt_senses = semantics.get("wiktionary_senses") or []
    wordnet_senses = semantics.get("wordnet_senses") or semantics.get("oewn_senses") or []

    definitions = [s.get("definition") for s in wikt_senses if isinstance(s, dict) and s.get("definition")]
    if not definitions:
        definitions = [
            s.get("definition")
            for s in wordnet_senses
            if isinstance(s, dict) and s.get("definition")
        ]

    synonyms = set()
    antonyms = set()
    for item in semantics.get("wiktionary_synonyms") or []:
        if isinstance(item, dict) and item.get("synonym_word"):
            synonyms.add(item["synonym_word"])
        elif isinstance(item, str):
            synonyms.add(item)
    for item in semantics.get("wiktionary_antonyms") or []:
        if isinstance(item, dict) and item.get("antonym_word"):
            antonyms.add(item["antonym_word"])
        elif isinstance(item, str):
            antonyms.add(item)
    for sense in wordnet_senses:
        if isinstance(sense, dict):
            synonyms.update(sense.get("synonyms") or [])
            antonyms.update(sense.get("antonyms") or [])

    conceptnet = []
    for rel in limited(semantics.get("conceptnet_relations") or [], 10, no_limits):
        if isinstance(rel, dict):
            conceptnet.append({
                "relation": rel.get("relation"),
                "target": rel.get("other_node") or rel.get("target"),
                "weight": rel.get("weight"),
            })

    pronunciation = [
        p for p in wikt_meta.get("pronunciation", [])
        if isinstance(p, dict) and (p.get("ipa") or p.get("audio"))
    ]

    enrichment = {
        "enrichment_status": "success",
        "primary_pos": primary_pos_key,
        "primary_lemma": semantics.get("lemma"),
        "definitions": definitions,
        "inflections": limited(
            (primary_entry.get("inflections_wiktionary") or {}).get("forms_list") or [],
            20,
            no_limits,
        ),
        "pronunciation": pronunciation,
        "examples": limited(wikt_meta.get("examples") or [], 3, no_limits),
        "hyphenation": wikt_meta.get("hyphenation") or [],
        "expressions": wikt_meta.get("expressions") or [],
        "proverbs": wikt_meta.get("proverbs") or [],
        "entryNotes": wikt_meta.get("entry_notes") or [],
        "hypernyms": wikt_meta.get("hypernyms") or [],
        "hyponyms": wikt_meta.get("hyponyms") or [],
        "holonyms": wikt_meta.get("holonyms") or [],
        "meronyms": wikt_meta.get("meronyms") or [],
        "coordinateTerms": wikt_meta.get("coordinate_terms") or [],
        "synonyms": limited(sorted(synonyms), 10, no_limits),
        "antonyms": limited(sorted(antonyms), 5, no_limits),
        "conceptnet": conceptnet,
        "wiktionary_translations": semantics.get("wiktionary_translations") or [],
        "wiktionary_derived_terms": semantics.get("wiktionary_derived_terms") or [],
        "wiktionary_related_terms": semantics.get("wiktionary_related_terms") or [],
        "alternative_analyses": [],
    }

    for pos, entries in analysis.items():
        if pos == primary_pos_key or not isinstance(entries, list) or not entries:
            continue
        alt_sem = entries[0].get("semantics_combined") or entries[0].get("semantics") or {}
        alt_senses = alt_sem.get("wiktionary_senses") or alt_sem.get("wordnet_senses") or []
        alt_def = alt_senses[0].get("definition") if alt_senses and isinstance(alt_senses[0], dict) else None
        enrichment["alternative_analyses"].append({
            "pos": pos,
            "lemma": alt_sem.get("lemma"),
            "definition": alt_def,
        })

    if not definitions and not enrichment["inflections"] and not enrichment["hyphenation"]:
        enrichment["enrichment_status"] = "no_data"
    return enrichment


def enrich(args):
    data = load_data(args.input, args.output)
    vocabulary = data.get("vocabulary", [])
    processed = load_checkpoint(vocabulary, retry_errors=args.retry_errors)

    client = Client(args.api_url)
    print("Connected to " + getattr(client, "src", args.api_url))

    target = vocabulary
    if args.limit:
        target = [entry for entry in vocabulary if entry.get("id") not in processed][:args.limit]
        target_ids = {entry.get("id") for entry in target}
    else:
        target_ids = None

    success_count = 0
    error_count = 0
    for index, entry in enumerate(tqdm(vocabulary, desc="Enriching")):
        word_id = entry.get("id")
        if not word_id or word_id in processed:
            continue
        if target_ids is not None and word_id not in target_ids:
            continue

        word = entry.get("word", "")
        primary_pos = WORDTYPE_TO_POS.get(entry.get("wordType"), "other")
        try:
            result = client.predict(
                word=word,
                top_n=0 if args.no_limits else TOP_N_SEMANTICS,
                engine="wiktionary",
                api_name="/analyze_word",
            )
            if isinstance(result, (list, tuple)) and len(result) >= 2:
                result = result[1]
            entry["apiEnrichment"] = build_enrichment(result, primary_pos, args.no_limits)
            processed.add(word_id)
            if entry["apiEnrichment"].get("enrichment_status") == "success":
                success_count += 1
            time.sleep(DELAY_BETWEEN_CALLS)
        except Exception as exc:
            error_count += 1
            entry["apiEnrichment"] = {
                "enrichment_status": "error",
                "error_message": str(exc),
                "traceback": traceback.format_exc(),
            }
            if not args.retry_errors:
                processed.add(word_id)

        if (index + 1) % CHECKPOINT_INTERVAL == 0:
            save_checkpoint(processed)
            args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    data.setdefault("metadata", {})["enrichment_v24_en"] = {
        "enriched_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "processed_words": len(processed),
        "successes_this_run": success_count,
        "errors_this_run": error_count,
    }
    save_checkpoint(processed)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved {args.output}")
    print(f"Successes this run: {success_count}; errors this run: {error_count}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=INPUT_JSON)
    parser.add_argument("--output", type=Path, default=OUTPUT_JSON)
    parser.add_argument("--api-url", default=GRADIO_API_URL)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--retry-errors", action="store_true")
    parser.add_argument("--no-limits", action="store_true")
    args = parser.parse_args()
    enrich(args)


if __name__ == "__main__":
    main()
