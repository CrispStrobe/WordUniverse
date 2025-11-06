Wortschatz Data Pipeline

This directory contains the scripts necessary to build the final grundwortschatz.json file from the raw voc_de.csv.

It is critical to run these scripts in the correct order.

The Pipeline

Step 1: Clean & Enrich CSV (enrich_data.py)

This script performs local cleaning and enrichment.

Input: voc_de.csv (The raw CSV file, not included here)

Action:

Loads the raw CSV.

Uses the spaCy library to get morphological data (Lemma, Case, Number, etc.).

Crucially, it fixes data. It uses the Article column (e.g., "der") as the "source of truth" to correct the Genus (e.g., to "mask.").

Output: voc_de_enriched.csv

To Run:

# Assumes you have pandas and spacy installed:
# pip install pandas spacy
# python -m spacy download de_core_news_sm

python enrich_data.py


Step 2: Convert to JSON (convert_to_json.py)

This script converts the clean CSV into the app-ready JSON format.

Input: voc_de_enriched.csv (from Step 1)

Action:

Reads the clean CSV.

Converts each row into the final JSON object structure.

Adds all necessary app-specific fields as placeholders (e.g., plural: null, inflectionData: null, categories: []).

Output: lib/features/games/data/grundwortschatz.json

To Run:

python convert_to_json.py


After this step, the JSON file is valid and can be used by the app, but it's missing inflection data.

Step 3: Populate Inflections (inflection_enricher.dart)

This script is the final, long-running step. It calls an external API to get detailed inflection data and intelligently merges it.

Input: lib/features/games/data/grundwortschatz.json (from Step 2)

Action:

Creates a timestamped backup of the JSON file.

Scans the file for words that are missing inflectionData.

Calls the NLP API for each word.

Validates: It checks the API's gender against the genus from Step 1. If they conflict, it rejects the API data to maintain consistency.

Populates: If the data is valid, it adds it to inflectionData AND parses it to fill other top-level fields like plural.

Saves progress in batches atomically. It's safe to stop and restart.

Output: lib/features/games/data/grundwortschatz.json (now with inflection data).

To Run:

# Make sure 'http' and 'path' packages are in your dev_dependencies
# in pubspec.yaml

dart run inflection_enricher.dart


This completes the pipeline, giving you a clean, consistent, and richly-populated JSON file.