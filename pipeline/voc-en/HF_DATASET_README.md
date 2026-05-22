---
license: cc-by-sa-4.0
language:
- en
- de
task_categories:
- text-classification
- token-classification
- translation
size_categories:
- 10K<n<100K
tags:
- english
- vocabulary
- spelling
- primary-school
- uk-curriculum
- wiktionary
- conceptnet
- cmudict
- education
- lexical-database
pretty_name: WortUniversum — English primary-school vocabulary with spelling enrichment
configs:
- config_name: default
  data_files:
  - split: words
    path: words.parquet
  - split: translations
    path: translations.parquet
  - split: examples
    path: examples.parquet
---

# WortUniversum English Vocabulary Database

Status: **draft** for an eventual Hugging Face Datasets upload as
`cstr/grundwortschatz-voc-en`. The shipped app asset is
`assets/grundwortschatz_en.db.gz`.

## Dataset Summary

A UK-English vocabulary database for spelling and word games, built to mirror
the German `voc-de` schema. The current base build contains **10,000 English
words** with:

- UK Year 1-6 curriculum source tags from the Department for Education
  Appendix 1 spelling lists
- Dolch sight-word and Fry-style frequency-band tags
- HermitDave/OpenSubtitles frequency rank and count signals
- Wikipedia-derived common misspelling pairs in `commonLearnerErrors`
- CMUdict ARPAbet, IPA, and X-SAMPA pronunciation where available
- generated English spelling/grapheme variants for distractor generation
- SQLite FTS5 search index compatible with the app runtime

The full WiktionaryEN enrichment sweep is implemented but not yet complete for
the base artifact. Once run, the same schema will carry definitions, examples,
translations, inflections, ConceptNet relations, and WordNet-derived semantic
signals.

## Tables

### `words`

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Surrogate key |
| `original_id` | TEXT UNIQUE | Stable build identifier |
| `word` | TEXT | English surface form |
| `lemma` | TEXT | Lemma |
| `article` | TEXT | `a` / `an` for noun usage hints, nullable |
| `genus` | TEXT | Always NULL for English |
| `word_type` | TEXT | Canonical POS token |
| `grade_level` | INTEGER | 1-6 grade estimate |
| `audio_path` | TEXT | Optional audio URL/path |
| `frequency_json` | TEXT JSON | Frequency, rank, and AoA-style signals |
| `enrichment_json` | TEXT JSON | Tags, misspellings, pronunciation, variants, and API enrichment |
| `metadata_json` | TEXT JSON | Build metadata and source attribution |

### `translations`

EN -> DE translations from WiktionaryEN enrichment. Empty in the current base
artifact until the full step 11 sweep is completed.

### `examples`

Example sentences from WiktionaryEN enrichment. Empty in the current base
artifact until the full step 11 sweep is completed.

## Loading

The SQLite asset can be exported to Parquet with:

```sh
cd pipeline/voc-en
python export_to_parquet.py
```

This writes `hf_export/words.parquet`, `hf_export/translations.parquet`, and
`hf_export/examples.parquet`.

## Source Attribution

| Source | License | Used for |
|---|---|---|
| EN Wiktionary | CC-BY-SA 4.0 | Optional step 11 definitions, examples, inflections, translations |
| ConceptNet 5 | CC-BY-SA 4.0 | Optional step 11 semantic relations |
| Open English WordNet | CC-BY 4.0 | Optional step 11 semantic relations |
| HermitDave FrequencyWords / OpenSubtitles 2018 | CC-BY-SA 4.0 | Frequency ranks/counts |
| UK Department for Education Appendix 1 | Open Government Licence v3.0 | UK Year 1-6 spelling/curriculum signal |
| Dolch 220 sight words | Public domain | Early sight-word signal |
| Fry-style top-1000 frequency list | Public domain / MIT mirror | Sight-word frequency bands |
| Wikipedia Lists of common misspellings | CC-BY-SA 4.0 | `commonLearnerErrors` |
| CMU Pronouncing Dictionary | BSD-style permissive | ARPAbet / IPA / X-SAMPA pronunciation |

## License

Current base artifact: **CC-BY-SA-4.0-compatible composite posture**. The
dominant copyleft input is CC-BY-SA 4.0 (Wiktionary/ConceptNet/Wikipedia and
HermitDave/OpenSubtitles). OGL v3.0, public-domain, BSD-style, and CC-BY 4.0
inputs are compatible with redistribution with attribution.

If a future English source with a stronger copyleft license is added, update
this dataset card and the in-app license registry before shipping.
