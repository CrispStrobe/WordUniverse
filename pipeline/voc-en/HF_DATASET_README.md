---
license: cc-by-sa-4.0
language:
- en
task_categories:
- text-classification
- token-classification
size_categories:
- 10K<n<100K
tags:
- english
- vocabulary
- spelling
- primary-school
- uk-curriculum
- cefr
- wiktionary
- openwordnet
- wordfreq
- education
- lexical-database
pretty_name: WortUniversum — English primary-school vocabulary with multi-source enrichment
configs:
- config_name: default
  data_files:
  - split: words
    path: words.parquet
  - split: translations
    path: translations.parquet
  - split: examples
    path: examples.parquet
  - split: phrasal_verbs
    path: phrasal_verbs.parquet
  - split: false_friends
    path: false_friends.parquet
---

# WortUniversum English Vocabulary Database

> **Status: published** at
> [`cstr/grundwortschatz-voc-en`](https://huggingface.co/datasets/cstr/grundwortschatz-voc-en)
> (CC-BY-SA 4.0). The shipped app asset is `assets/grundwortschatz_en.db.gz` in
> the [WortUniversum / words-universe](https://github.com/CrispStrobe/words-universe)
> repository; this dataset is its CC-BY-SA 4.0 re-distribution form. Rebuild +
> re-push with `pipeline/build_hf_datasets.py --upload`.

## Dataset summary

A UK-English lexical database of **11,539 lemmas** covering primary-school
vocabulary (CEFR-J A1–B2, YLE Starters/Movers/Flyers, UK Year 1–6 statutory
lists), with multi-source enrichment per word:

- Wiktionary definitions, IPA pronunciation, inflections, examples
- Open English WordNet (OEWN) sense records: synonyms, antonyms, hypernyms, hyponyms
- wordfreq Zipf score, occurrences-per-million, frequency band (1–5)
- CEFR-J v1.5 level tags (A1–B2) for 6,879 entries
- Cambridge YLE Starters / Movers / Flyers vocabulary tags (833 entries)
- UK DfE statutory spelling lists: Year 1–2, 3–4, 5–6 (318 entries)
- Curriculum-derived `gradeLevelEstimate` (1–6) for all entries
- 27,363 common learner error pairs on 4,653 entries (Norvig + Wikipedia)
- 264 UK ↔ US dialect spelling variants across 150 entries (SCOWL)
- Grade-differentiated example sentences (LLM-generated, all 6 grades)
- Project Gutenberg example sentences from 72 public-domain EN books
- SQLite FTS5 search index compatible with the app runtime

The vocabulary is a superset of curriculum targets; tags control which subset
the app surfaces per user level.

## Languages

- **en** (English) — primary; all lemma, definition, enrichment, and example content
- **de** (German) — translations (empty in current artifact; added by future pipeline step)

## Dataset structure

The dataset ships as a SQLite database (`grundwortschatz_en.db.gz`).
The Parquet companion files (`words.parquet`, `translations.parquet`,
`examples.parquet`) are produced by the export script; see *Loading* below.

### Table: `words`

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Surrogate key |
| `original_id` | TEXT UNIQUE | Stable build identifier (word + pos slug) |
| `word` | TEXT | English surface form (UK spelling canonical) |
| `lemma` | TEXT | Lemma |
| `article` | TEXT | `a` / `an` hint for nouns, nullable |
| `genus` | TEXT | Always NULL (English has no grammatical genus) |
| `word_type` | TEXT | POS token: `noun`, `verb`, `adjective`, `adverb`, etc. |
| `grade_level` | INTEGER | 1–6 grade estimate (synced from `gradeLevelEstimate`) |
| `audio_path` | TEXT | Audio URL/path, nullable |
| `frequency_json` | TEXT JSON | `{"zipf": float, "per_million": float, "frequency_band": 1–5}` |
| `enrichment_json` | TEXT JSON | Wiktionary data, OEWN senses, misspellings, variants, tags |
| `metadata_json` | TEXT JSON | CEFR level, grade examples, Gutenberg examples, curriculum sources |

#### `enrichment_json` shape

```jsonc
{
  "enrichment_status": "success" | "minimal" | "no_data",
  "definitions": ["..."],
  "pronunciation": {"ipa": "...", "audio": "..."},
  "inflections": [...],
  "examples": [...],
  "synonyms": [...],
  "antonyms": [...],
  "hypernyms": [...],
  "hyponyms": [...],
  "wordnetSenses": [...],          // OEWN per-synset records
  "commonLearnerErrors": [         // common misspellings
    {"error": "recieve", "source": "norvig"},
    {"error": "recieve", "source": "wikipedia"}
  ],
  "spellingVariants": [            // UK / US dialect variants
    {"variant": "color", "dialect": "american"},
    {"variant": "colour", "dialect": "british"}
  ],
  "tags": ["source:uk_y1_y2", "source:cambridge_yle_starters", ...],
  "sources": [...]
}
```

#### `metadata_json` shape

```jsonc
{
  "cefr_level": "A1" | "A2" | "B1" | "B2",
  "yle_level": "starters" | "movers" | "flyers",
  "gradeLevelEstimate": 1,          // 1–6 (UK Year grade equivalent)
  "gutenberg_examples": ["..."],    // up to 5 Gutenberg sentences
  "grade_examples": {               // LLM-generated per-grade examples
    "1": ["...", "..."],
    "2": [...], "3": [...], "4": [...], "5": [...], "6": [...]
  },
  "tags": ["source:uk_y3_y4", ...],
  "sources": [...]
}
```

### Table: `translations`

Empty in the current artifact (no DE translations step for EN words).
Schema: `id, word_id, lang_code, translation`.

### Table: `examples`

18,642 sentences from Wiktionary and Project Gutenberg example extraction.
Schema: `id, word_id, sentence`.

### Table: `phrasal_verbs`

400 English phrasal verbs (added 2026-05-29) powering the in-app phrasal-verb
games. Source: Wiktionary "English phrasal verbs" categories (CC BY-SA 4.0) +
LLM grade-leveled example sentences. Content-filtered for a K-6 audience.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `word_id` | INTEGER FK → `words.id` | the base verb's row |
| `phrasal` | TEXT | e.g. `give up` |
| `base_verb` / `particle` | TEXT | `give` / `up` |
| `meaning` | TEXT | short kid-friendly definition |
| `senses_json` | TEXT (JSON) | up to 3 Wiktionary glosses |
| `distractors_json` | TEXT (JSON) | wrong particles (real PVs of the same base verb) |
| `examples_json` | TEXT (JSON) | `{"1":[…],…,"6":[…]}` grade-leveled sentences (398/400) |
| `wiktionary_examples_json` | TEXT (JSON) | CC-BY-SA fallback sentences |
| `grade_band` | INTEGER | 3–6 |
| `base_zipf` | REAL | base-verb frequency (ranking signal) |
| `source` / `license` | TEXT | `wiktionary` / `CC-BY-SA-4.0` |

## gradeLevelEstimate decision tree

Priority: lowest cap wins.

1. `source:uk_y1_y2` or `source:cambridge_yle_starters` → cap ≤ 2
2. `source:uk_y3_y4` or `source:cambridge_yle_movers` → cap ≤ 3
3. `source:uk_y5_y6` or `source:cambridge_yle_flyers` → cap ≤ 4
4. CEFR A1 → cap ≤ 2; A2 → ≤ 3; B1 → ≤ 4; B2 → ≤ 5
5. Frequency band baseline: band1→1, band2→2, band3→3, band4→5, band5→6
6. Result: `min(cap, freq_baseline)`. Stored in both `metadata_json.gradeLevelEstimate`
   and the `grade_level` column.

## Loading

Export the SQLite asset to Parquet with:

```sh
cd pipeline/voc-en
python3 export_to_parquet.py --db grundwortschatz_en.db
```

This writes `hf_export/words.parquet`, `hf_export/translations.parquet`, and
`hf_export/examples.parquet`.

Load with pandas:

```python
import pandas as pd
words = pd.read_parquet("words.parquet")
```

Load with DuckDB:

```python
import duckdb
conn = duckdb.connect()
conn.execute("SELECT word, grade_level, frequency_json FROM 'words.parquet' LIMIT 10").fetchdf()
```

## Citation

If you use this dataset in research, please cite the primary upstream sources:

- **Wiktionary**: https://www.wiktionary.org/ (CC BY-SA 4.0)
- **OEWN**: McCrae et al., Open English WordNet 2024, https://en-word.net/ (CC BY 4.0)
- **CEFR-J**: Tono, Y. & Negishi, M. (2012). CEFR-J Wordlist, TUFS (CC BY-SA 4.0)
- **wordfreq**: Speer, R. (2023). wordfreq, Luminoso Technologies (Apache-2.0 + CC BY-SA 4.0)

## Source attribution

| Source | License | What it contributes |
|---|---|---|
| **Wiktionary EN** | CC BY-SA 4.0 | Definitions, IPA, inflections, examples |
| **Open English WordNet (oewn:2024)** | CC BY 4.0 | Sense records, synonyms, hypernyms |
| **wordfreq** (Luminoso) | Apache-2.0 + CC BY-SA 4.0 | `frequency_json` (Zipf, per_million, band) |
| **CEFR-J v1.5** (Tono & Negishi, TUFS) | CC BY-SA 4.0 | `cefr_level` tags |
| **Cambridge YLE word lists** | Factual (not copyrightable) | `yle_level` tags |
| **UK DfE statutory spelling lists** | OGL v3 — commercial OK | `source:uk_y*` tags, grade signal |
| **Project Gutenberg texts** (72 books) | Public domain (pre-1928) | Gutenberg example sentences |
| **Norvig spell-errors.txt** | MIT code + CC BY-SA data | `commonLearnerErrors` |
| **Wikipedia common misspellings** | CC BY-SA 4.0 | `commonLearnerErrors` |
| **SCOWL / en-wl** (Kevin Atkinson) | MIT-like permissive | `spellingVariants` (UK↔US) |

## License

**Effective license: CC BY-SA 4.0.**

The dominant copyleft inputs are CC BY-SA 4.0 (Wiktionary, wordfreq, CEFR-J,
Wikipedia/Norvig misspellings). OGL v3.0, public-domain (Gutenberg), and
CC BY 4.0 (OEWN) sources are all compatible with redistribution under CC BY-SA 4.0.

The Flutter application code is under a separate proprietary license.
CC BY-SA on the shipped data does not affect the application source code —
it only applies when redistributing derivative data works.

Changes made from upstream sources: filtered to ~11.5k lemmas covering
UK primary-school curriculum; data reshaped into normalized SQLite schema;
grade-level estimates computed from multi-source decision tree; common
learner errors deduplicated and attributed per source.
