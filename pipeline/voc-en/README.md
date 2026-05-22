# `pipeline/voc-en/` — English vocabulary build (in progress)

Mirror of `pipeline/voc-de/` but pedagogically aligned with **UK
English** (Year 1–6 statutory spelling lists are the school‑grade
analogue of NRW Grundwortschatz). See [/pipeline/PLAN.md
§2](../PLAN.md#2-build-the-en-db-at-de-parity) for the locked‑in
decisions and the full step ladder.

## Status

Base build runnable — steps 00–06, 11–12, and a base step 14 are written.
Steps 00–06 and 14 have been run for the shipped base artifact; step 11 has
been smoke-tested with a six-word WiktionaryEN run. Steps 07–10 and 13 are
not yet ported; see `../PLAN.md §2` for the full parity ladder.

| Step | File | State |
|---|---|---|
| 00 | `00_fetch_sources.py` | written |
| 01 | `01_consolidate_en.py` | written |
| 02 | `02_enrich_with_spacy_en.py` | written |
| 03 | `03_conv_csv_to_json_en.py` | written |
| 04 | `04_add_common_misspellings_en.py` | written |
| 05 | `05_phoneme_enricher_en.py` | written |
| 06 | `06_generate_grapheme_variants_en.py` | written |
| 07–10 | (not yet) | planned |
| 11 | `11_reprocess_full_wikidict_en.py` | written; smoke-tested with `--limit` |
| 12 | `12_api_wins_en.py` | written |
| 13 | (not yet) | planned |
| 14 | `14_convert_db_to_sqflite_en.py` | base builder written |

## Quick start

```sh
cd pipeline/voc-en
python 00_fetch_sources.py          # downloads UK Appendix 1, Dolch, Fry, HermitDave, CMU dict, Wikipedia misspellings
python 01_consolidate_en.py         # → voc_en.csv
python -m spacy download en_core_web_sm  # one-time
python 02_enrich_with_spacy_en.py   # → voc_en_enriched.csv
python 03_conv_csv_to_json_en.py    # → grundwortschatz_en.json
python 04_add_common_misspellings_en.py
python 05_phoneme_enricher_en.py
python 06_generate_grapheme_variants_en.py
python 14_convert_db_to_sqflite_en.py
gzip -9 -c grundwortschatz_en.db > ../../assets/grundwortschatz_en.db.gz
```

For the slow WiktionaryEN enrichment sweep:

```sh
python 11_reprocess_full_wikidict_en.py --limit 25     # smoke / incremental
python 11_reprocess_full_wikidict_en.py --no-limits    # full run
python 12_api_wins_en.py grundwortschatz_en_enriched_v24.json
python 14_convert_db_to_sqflite_en.py \
  --input grundwortschatz_en_enriched_v24_consolidated.json \
  --output grundwortschatz_en_enriched_v24_consolidated.db
```

The full step 11 run is network-bound and expected to take many hours.

## Sources (10 expected inputs in `sources/`)

### Pedagogical / curriculum (highest dedup priority)

| File | Source | What it is | How to obtain |
|---|---|---|---|
| `sources/uk_y1_y6_statutory.csv` | UK National Curriculum English Programmes of Study (DfE) — Open Government Licence v3.0 | Common-exception words for Y1/Y2 and statutory spelling lists for Y3/Y4 and Y5/Y6 — the EN analogue of NRW Grundwortschatz; **the primary pedagogical signal** | **auto-generated** by `00_fetch_sources.py`; the official Appendix 1 PDF is downloaded beside it as provenance |
| `sources/dolch_220.csv` | Dolch 220 sight words (Edward Dolch, 1948) — **public domain** | Foundational sight‑words for K–G3 | **auto‑fetched** by `00_fetch_sources.py` (embedded list, public domain) |
| `sources/fry_top1000_freq.txt` | Frequency‑based stand‑in for Fry 1000 (curated top‑1000 mirror) — public domain / MIT | Frequency‑ranked sight words split into 10 bands of 100 | **auto‑fetched** by `00_fetch_sources.py` |

**Removed** (NOT redistributable in a commercial app — see [/pipeline/LICENSES.md](../LICENSES.md#-not-safe--removed-from-en-scaffolding)):

- **Oxford 3000 / Oxford 5000** — © Oxford University Press, proprietary
- **English Vocabulary Profile (EVP)** — Cambridge University Press, commercial license required
- **SUBTLEX‑US** (Brysbaert) — academic / non‑commercial use only

The EN port relies on the UK Y1–6 statutory list as the pedagogical primary
(directly equivalent to NRW Grundwortschatz for DE), plus Dolch + Fry for
sight‑word coverage, plus the Wiktionary‑derived lexical backbone via
`cstr/WiktionaryEN`.

### Frequency (lower priority — fills gaps after pedagogical pass)

| File | Source | License | How to obtain |
|---|---|---|---|
| `sources/en_50k_hermitdave.txt` | HermitDave FrequencyWords (EN top 50k) — derived from OpenSubtitles 2018 | CC‑BY‑SA 4.0 | **auto‑fetched** by `00_fetch_sources.py` |
| `sources/aoa_kuperman.csv` | Kuperman, Stadthagen‑Gonzalez & Brysbaert (2012) age‑of‑acquisition norms | Springer supplementary data — typically reusable for derivative facts (the AoA numbers themselves are scientific measurements) | Optional for v1. Download from `http://crr.ugent.be/archives/806`, save first sheet as CSV with `word,aoa_mean,aoa_sd` |
| `sources/google_1gram_en.tsv` (optional) | Google Books 1‑gram | Skip for v1 — HermitDave is enough |

### Spelling errors / common misspellings

| File | Source | How to obtain |
|---|---|---|
| `sources/commonly_misspelled.csv` | Wikipedia "Lists of common misspellings" | **auto‑fetched** by `00_fetch_sources.py`; attached to `commonLearnerErrors` by step 04 |
| `sources/birkbeck_errors.csv` (optional) | Birkbeck Spelling Error Corpus (Mitton) | `https://www.dcs.bbk.ac.uk/~ROGER/corpora.html` — download `holbrook.dat`, parse to `wrong,correct` CSV. Skip for v1. |

### Pronunciation

| File | Source | How to obtain |
|---|---|---|
| `sources/cmudict.txt` | CMU Pronouncing Dictionary | **auto‑fetched** by `00_fetch_sources.py` |

### Age of Acquisition (grade‑mapping fallback)

| File | Source | How to obtain |
|---|---|---|
| `sources/aoa_kuperman.csv` | Kuperman, Stadthagen‑Gonzalez & Brysbaert (2012) | Download supplementary Excel from `http://crr.ugent.be/archives/806`, save first sheet as CSV with `word,aoa_mean,aoa_sd` |

## Grade‑mapping cascade (UK Y1–6 primary)

For each word, `03_conv_csv_to_json_en.py` assigns a single integer
`grade_level` 1–6 using this fallback chain:

1. **UK Year 1–6 statutory** — if word appears in the UK list, use that year directly (Y1→G1, Y2→G2, …, Y6→G6).
2. **CEFR** — A1→G1, A2→G2, B1→G3, B2→G4, C1→G5, C2→G6, if a safe licensed CEFR source is added later.
3. **AoA‑Kuperman** — bucketed: ≤6→G1, 7–8→G2, 9–10→G3, 11–13→G4, 14–16→G5, 17+→G6.
4. **Frequency rank** (last resort) — top‑500 → G3, 501–2000 → G4, 2001–8000 → G5, else G6.

All four signals are also carried forward as **tags** (`uk_y2_statutory`,
`cefr_a2`, `aoa_8.4`, `hermit_rank_750`) so the app can filter at
display time (Core 3k / Extended 5k / Full 10k).

## Schema differences vs voc-de

| Column | DE | EN | Why |
|---|---|---|---|
| `article` | `der`/`die`/`das` | nullable; `a`/`an`/`the` filled for nouns at step 12 | EN has no grammatical gender; article is a usage hint |
| `genus` | `Masculine`/`Feminine`/`Neuter` | always NULL | EN has no grammatical gender |
| `word_type` | German tokens (`substantiv`, `adjektiv`, …) | English tokens (`noun`, `verb`, …) | step 14 canonicalizes both DBs to English tokens |
| `enrichment_json.phrasalVerb` | not used | `{particle, meaning, examples}` for EN phrasal verbs | EN equivalent of DE separable verbs |
| `enrichment_json.spellingRule` | NRW rule tag | UK spelling‑rule tag (silent‑e, magic‑e, doubled‑consonant, …) | different orthographic systems |
| `enrichment_json.capitalizationCategory` | DE: all nouns capitalized | EN: `proper`/`common` | EN only capitalizes proper nouns |
| `translations` | DE→EN (kept by step 10) | EN→DE (kept by step 10's EN mirror, when available) | mirror use case |

## Run‑order tldr (for the steps that exist)

```sh
cd pipeline/voc-en

# 0. Fetch easy sources, get instructions for the rest
python 00_fetch_sources.py

# 1-3. (only after all sources are in sources/)
python 01_consolidate_en.py
python 02_enrich_with_spacy_en.py    # needs en_core_web_sm
python 03_conv_csv_to_json_en.py
```

## Open items

- `04_add_uk_spelling_rules_en.py` — still needed as a richer NRW analogue, attaches UK spelling‑rule tags + statutory year. Current `04_add_common_misspellings_en.py` only attaches Wikipedia misspellings.
- `05_phoneme_enricher_en.py` — implemented with local CMUdict join (ARPAbet + IPA + X-SAMPA)
- `06_generate_grapheme_variants_en.py` — implemented with conservative EN pattern substitutions (digraphs, silent letters, vowel teams, suffix confusions)
- `07/11 — enrich via cstr/WiktionaryEN` — step 11 implemented as resumable `cstr/WiktionaryEN` sweep; 07 can stay skipped like DE's superseded 07 variants
- `08_fix_word_types_en.py` — same as DE 08, EN POS set
- `12_api_wins_en.py` — implemented; conservative promotion, no genus
- `13_fix_word_types_manually.py` — hand‑curated POS for noun/verb ambiguities (run, walk, break)
- `13b_enrich_with_wordnet.py` — may collapse into 11 since OEWN is already inside `cstr/WiktionaryEN`
- `14_convert_db_to_sqflite_en.py` — base builder exists; extend as needed once V24 EN enrichment fields are finalized
