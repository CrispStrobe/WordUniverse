"""Consolidate WiktionaryEN API enrichment into top-level app fields.

Conservative rule: API data fills missing or obviously API-owned fields; it
does not overwrite non-empty user/pipeline fields except for promoted V24
collections that are sourced from the API sweep.
"""
import argparse
import json
from pathlib import Path

POS_TO_WORDTYPE = {
    "noun": "noun",
    "verb": "verb",
    "adjective": "adjective",
    "adj": "adjective",
    "adverb": "adverb",
    "adv": "adverb",
    "pron": "pronoun",
    "det": "article",
    "adp": "preposition",
    "conj": "conjunction",
    "part": "particle",
    "num": "numeral",
    "intj": "interjection",
    "other": "andere",
}

PROMOTED_FIELDS = {
    "hyphenation": "hyphenation",
    "expressions": "expressions",
    "proverbs": "proverbs",
    "entryNotes": "entryNotes",
    "hypernyms": "hypernyms",
    "hyponyms": "hyponyms",
    "holonyms": "holonyms",
    "meronyms": "meronyms",
    "coordinateTerms": "coordinateTerms",
}


def first_audio(pronunciation):
    for item in pronunciation or []:
        if isinstance(item, dict):
            for key in ["mp3_url", "audio", "audio_url"]:
                if item.get(key):
                    return item[key]
    return None


def clean_terms(raw, key):
    out = []
    for item in raw or []:
        if isinstance(item, str):
            out.append(item)
        elif isinstance(item, dict) and item.get(key):
            out.append(item[key])
    return sorted(set(out))


def consolidate(input_path, output_path):
    data = json.loads(input_path.read_text(encoding="utf-8"))
    stats = {
        "word_type": 0,
        "lemma": 0,
        "audio": 0,
        "translations": 0,
        "inflections": 0,
        "derived": 0,
        "related": 0,
        "promoted": 0,
    }

    for entry in data.get("vocabulary", []):
        enrichment = entry.get("apiEnrichment") or {}
        if enrichment.get("enrichment_status") != "success":
            continue

        api_word_type = POS_TO_WORDTYPE.get(enrichment.get("primary_pos"))
        if api_word_type and api_word_type != "andere" and entry.get("wordType") != api_word_type:
            entry["wordType"] = api_word_type
            stats["word_type"] += 1

        if not entry.get("lemma") and enrichment.get("primary_lemma"):
            entry["lemma"] = enrichment["primary_lemma"]
            stats["lemma"] += 1

        audio = first_audio(enrichment.get("pronunciation"))
        if audio and entry.get("audioPath") != audio:
            entry["audioPath"] = audio
            stats["audio"] += 1

        if enrichment.get("wiktionary_translations") is not None:
            entry["translations"] = enrichment.get("wiktionary_translations") or []
            stats["translations"] += 1

        if enrichment.get("inflections"):
            entry["wiktionaryInflections"] = enrichment["inflections"]
            entry["inflectionData"] = enrichment["inflections"]
            stats["inflections"] += 1

        derived = clean_terms(enrichment.get("wiktionary_derived_terms"), "derived_word")
        if derived:
            entry["derivedTerms"] = derived
            stats["derived"] += 1

        related = clean_terms(enrichment.get("wiktionary_related_terms"), "related_word")
        if related:
            entry["relatedTerms"] = related
            stats["related"] += 1

        for api_key, target_key in PROMOTED_FIELDS.items():
            value = enrichment.get(api_key)
            if value:
                entry[target_key] = value
                stats["promoted"] += 1

        # English has no grammatical gender. Keep schema-compatible nulls.
        entry["genus"] = None

    data.setdefault("metadata", {})["api_wins_en"] = stats
    output_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {output_path}")
    print(stats)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_file", type=Path)
    parser.add_argument("--output", "-o", type=Path)
    args = parser.parse_args()
    output = args.output or args.input_file.with_name(
        args.input_file.stem + "_consolidated.json"
    )
    consolidate(args.input_file, output)


if __name__ == "__main__":
    main()
