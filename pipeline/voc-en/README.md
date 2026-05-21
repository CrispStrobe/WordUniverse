# `pipeline/voc-en/` — English vocabulary build (in progress)

Mirror of `pipeline/voc-de/` but pedagogically aligned with **UK
English** (Year 1–6 statutory spelling lists are the school‑grade
analogue of NRW Grundwortschatz). See [/pipeline/PLAN.md
§2](../PLAN.md#2-build-the-en-db-at-de-parity) for the locked‑in
decisions and the full step ladder.

## Status

Scaffolding only — steps 00–03 are written but unrun. Steps 04–14
are not yet ported; see `../PLAN.md §2` for the planned ladder.

| Step | File | State |
|---|---|---|
| 00 | `00_fetch_sources.py` | written |
| 01 | `01_consolidate_en.py` | written |
| 02 | `02_enrich_with_spacy_en.py` | written |
| 03 | `03_conv_csv_to_json_en.py` | written |
| 04–14 | (not yet) | planned |

## Quick start

```sh
cd pipeline/voc-en
python 00_fetch_sources.py          # downloads Dolch, Fry, HermitDave, CMU dict, Wikipedia misspellings
                                    # prints manual instructions for Oxford 3000/5000, EVP, UK Y1-6, SUBTLEX-US, AoA-Kuperman
# … obtain the manual sources, drop them into sources/ with the filenames the script expects …
python 01_consolidate_en.py         # → voc_en.csv
python -m spacy download en_core_web_sm  # one-time
python 02_enrich_with_spacy_en.py   # → voc_en_enriched.csv
python 03_conv_csv_to_json_en.py    # → grundwortschatz_en.json
```

After 03, follow the DE pipeline ladder from step 04 onward
(NRW‑equivalent merge, safety filter, phonemize, grapheme variants,
`cstr/WiktionaryEN` enrichment, API‑wins, WordNet, build DB) — those
scripts still need to be ported.

## Sources (10 expected inputs in `sources/`)

### Pedagogical / curriculum (highest dedup priority)

| File | Source | What it is | How to obtain |
|---|---|---|---|
| `sources/uk_y1_y6_statutory.csv` | UK National Curriculum English Programmes of Study (DfE) — Open Government Licence v3.0 | The statutory spelling lists for Years 1–6 — the EN analogue of NRW Grundwortschatz; **the primary pedagogical signal** | Download the appendix PDF from `https://www.gov.uk/government/publications/national-curriculum-in-england-english-programmes-of-study`, extract Appendix 1 (Year 1–2 / 3–4 / 5–6 word lists), save as CSV with columns `word,year` |
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
| `sources/aoa_kuperman.csv` | Kuperman, Stadthagen‑Gonzalez & Brysbaert (2012) age‑of‑acquisition norms | Springer supplementary data — typically reusable for derivative facts (the AoA numbers themselves are scientific measurements) | Download from `http://crr.ugent.be/archives/806`, save first sheet as CSV with `word,aoa_mean,aoa_sd` |
| `sources/google_1gram_en.tsv` (optional) | Google Books 1‑gram | Skip for v1 — HermitDave is enough |

### Spelling errors / common misspellings

| File | Source | How to obtain |
|---|---|---|
| `sources/commonly_misspelled.csv` | Wikipedia "Lists of common misspellings" | **auto‑fetched** by `00_fetch_sources.py` |
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
2. **CEFR** — A1→G1, A2→G2, B1→G3, B2→G4, C1→G5, C2→G6. Sources: EVP, Oxford 3000/5000.
3. **AoA‑Kuperman** — bucketed: ≤6→G1, 7–8→G2, 9–10→G3, 11–13→G4, 14–16→G5, 17+→G6.
4. **Frequency rank** (last resort) — top‑500 → G3, 501–2000 → G4, 2001–8000 → G5, else G6.

All four signals are also carried forward as **tags** (`uk_y2_statutory`,
`cefr_a2`, `aoa_8.4`, `subtlex_rank_750`) so the app can filter at
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

- `04_add_uk_spelling_rules_en.py` — needs writing (NRW analogue, attaches UK spelling‑rule tags + statutory year)
- `05_phoneme_enricher_en.py` — clone of DE 05 with `language='en-us'` (or CMU dict join)
- `06_generate_grapheme_variants_en.py` — needs an EN `grapheme.json` (digraphs sh/ch/th/ph/ck/qu, silent letters, vowel teams)
- `07/11 — enrich via cstr/WiktionaryEN` — clone DE 11, swap `gradio_client` target
- `08_fix_word_types_en.py` — same as DE 08, EN POS set
- `12_api_wins_en.py` — same conservative pattern, no genus
- `13_fix_word_types_manually.py` — hand‑curated POS for noun/verb ambiguities (run, walk, break)
- `13b_enrich_with_wordnet.py` — may collapse into 11 since OEWN is already inside `cstr/WiktionaryEN`
- `14_convert_db_to_sqflite_en.py` — clone of DE 14, output `grundwortschatz_en.db`
