"""Add lemma + POS + morphology to voc_en.csv via spaCy en_core_web_sm.

Mirror of pipeline/voc-de/02_enrich_with_spacy_csv.py.

Differences from DE:
- No grammatical gender (`Genus`) or article column to reconcile.
- POS tags are spaCy's Universal POS tags (NOUN, VERB, ADJ, ADV, …) — not
  German Wortart strings. Step 03 maps these to the canonical
  `word_type` enum the app uses.
- We don't try to disambiguate noun-vs-verb for words like "run" / "walk"
  here; that's hand-curated in step 13_fix_word_types_manually.

Input:  voc_en.csv
Output: voc_en_enriched.csv
"""
import sys
from pathlib import Path

try:
    import pandas as pd
except ImportError:
    print("Missing pandas. Install with: pip install pandas")
    sys.exit(1)

try:
    import spacy
except ImportError:
    print("Missing spacy. Install with: pip install spacy")
    sys.exit(1)

HERE = Path(__file__).parent
INPUT = HERE / "voc_en.csv"
OUTPUT = HERE / "voc_en_enriched.csv"

# Map spaCy Universal POS → canonical app token. Anything not in this map
# falls through as "andere" (other), matching the DE pipeline's convention.
SPACY_UPOS_TO_CANONICAL = {
    "NOUN": "noun",
    "PROPN": "noun",          # proper noun — collapsed to noun for the app
    "VERB": "verb",
    "AUX": "verb",
    "ADJ": "adjective",
    "ADV": "adverb",
    "PRON": "pronoun",
    "DET": "article",         # the/a/an + this/that/some
    "ADP": "preposition",
    "CCONJ": "conjunction",
    "SCONJ": "conjunction",
    "NUM": "numeral",
    "PART": "particle",
    "INTJ": "interjection",
    "X": "andere",
    "SYM": "andere",
    "PUNCT": "andere",
}

ARTICLE_DETERMINERS = {"the", "a", "an"}


def enrich(input_csv: Path, output_csv: Path):
    if not input_csv.exists():
        print(f"Input not found: {input_csv}")
        print("Run 01_consolidate_en.py first.")
        sys.exit(1)

    df = pd.read_csv(input_csv)
    print(f"Loaded {len(df)} rows from {input_csv.name}")

    print("Loading spaCy model en_core_web_sm…")
    try:
        nlp = spacy.load("en_core_web_sm")
    except OSError:
        print("Model not installed. Run: python -m spacy download en_core_web_sm")
        sys.exit(1)

    # Disable pipeline components we don't need (parser, NER) for speed.
    # Keep tagger + lemmatizer + attribute_ruler + morphologizer.
    keep = {"tagger", "lemmatizer", "attribute_ruler", "morphologizer"}
    for name in list(nlp.pipe_names):
        if name not in keep:
            nlp.disable_pipe(name)

    print(f"Active spaCy components: {nlp.pipe_names}")

    lemmas = []
    upos_list = []
    canonical_pos = []
    morphologies = []
    initial_sounds = []

    # Run nlp.pipe over the raw word column for speed
    words = df["Word"].astype(str).tolist()
    for word, doc in zip(words, nlp.pipe(words, batch_size=200)):
        # Each "doc" is typically 1-2 tokens since these are single words.
        # We pick the first content token.
        if len(doc) == 0:
            lemmas.append(word)
            upos_list.append("X")
            canonical_pos.append("andere")
            morphologies.append("")
            initial_sounds.append("consonant")
            continue
        tok = doc[0]
        lemmas.append(tok.lemma_.lower() if tok.lemma_ else word.lower())
        upos = tok.pos_ or "X"
        upos_list.append(upos)
        canonical_pos.append(SPACY_UPOS_TO_CANONICAL.get(upos, "andere"))
        morph = str(tok.morph) if tok.morph else ""
        morphologies.append(morph)
        # For nouns, classify initial sound for the indefinite-article rule
        # (a vs an). Vowel-letter is a decent heuristic for v1; step 12 can
        # refine using the IPA from step 05.
        first = word.strip().lower()[:1]
        initial_sounds.append("vowel" if first in "aeiou" else "consonant")

    df["Lemma"] = lemmas
    df["UPOS"] = upos_list
    df["WordType"] = canonical_pos
    df["Morphology"] = morphologies
    df["InitialSound"] = initial_sounds

    # For nouns, propose a default article based on initial sound.
    # the/a/an are determiners; nouns themselves don't carry an article column
    # in DE either — we surface this only as a usage hint in enrichment_json.
    df["DefaultArticle"] = df.apply(
        lambda r: ("an" if r["WordType"] == "noun" and r["InitialSound"] == "vowel"
                   else "a" if r["WordType"] == "noun" else None),
        axis=1,
    )

    df.to_csv(output_csv, index=False)
    print(f"\nWrote {len(df)} rows to {output_csv.name}")

    # Quick POS distribution
    print("\n=== POS distribution ===")
    dist = df["WordType"].value_counts()
    for pos, n in dist.items():
        pct = 100.0 * n / len(df)
        print(f"  {pos:20s} {n:>6d}  ({pct:5.1f} %)")


def main():
    enrich(INPUT, OUTPUT)


if __name__ == "__main__":
    main()
