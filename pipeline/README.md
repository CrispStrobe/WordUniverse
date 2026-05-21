# Word Universe — Build Pipeline

This directory holds the **reproducible build pipeline** for the Word Universe
(Wort‑Universum) vocabulary databases, plus the related ConceptNet semantic
graph the enrichment depends on.

It exists because the Flutter app's `assets/grundwortschatz.db.gz` is a frozen
compiled blob — without this directory, nobody could rebuild it.

## What ships today

- **`assets/grundwortschatz.db.gz`** — German DB. 10,450 words, grades 1–6,
  27,587 English translations, 24,471 examples, FTS5 search, Wiktionary +
  ConceptNet + OdeNet + OpenThesaurus enrichment. Built by the 14‑step
  pipeline summarised below.

## What we plan to add

- **`assets/grundwortschatz_en.db.gz`** — English DB at DE parity. Backbone
  exists on HF; laptop‑side pipeline planned. See [PLAN.md](PLAN.md) §2.
- An **all‑languages** ConceptNet normalized SQLite (current ship is a
  curated 11‑language subset). See [PLAN.md](PLAN.md) §3.

## Documents in this folder

| Doc | Read it when |
|---|---|
| [HISTORY.md](HISTORY.md) | You want the chronological narrative — what was built when, what pivoted, where the work happened (laptop, VPS_2, VPS_3, HF Spaces). |
| [PLAN.md](PLAN.md) | You want to **rebuild** the DE DB, **port** to English, or **expand** ConceptNet. Step‑by‑step, with open decisions called out. |
| [LEARNINGS.md](LEARNINGS.md) | You're starting a similar pipeline and want to avoid the mistakes we already made. |

## The three pipelines documented here

### 1. `voc-de` — German vocabulary (shipped)

14 numbered steps that take ~15 pedagogical/frequency wordlists →
spaCy‑enriched CSV → JSON → HF API enrichment → SQLite + FTS5 → gzipped
sqflite‑ready DB. See [PLAN.md §1](PLAN.md#1-rebuild-the-de-db-shipped).

The scripts live in the project backup at
`/Volumes/backups/code/voc/lib/features/games/data/` (they were intentionally
deleted from the current repo in commit `8364f26` to shrink the Flutter
bundle). PLAN.md describes how to restore the canonical set.

### 2. `voc-en` — English vocabulary (planned)

A mirror of the DE pipeline. The hard part is already done:
`cstr/WiktionaryEN` (HF Space) plus `cstr/en-wiktionary-sqlite-all` (HF
dataset) cover the lexical backbone. What's left is consolidation,
laptop‑side enrichment, and the sqflite ship build. See
[PLAN.md §2](PLAN.md#2-build-the-en-db-at-de-parity).

### 3. `conceptnet-normalized-multi` (semantic graph)

The ConceptNet DB that the WiktionaryDE / WiktionaryEN spaces query when
enriching each headword. Currently ships **11 languages**
(`en, fr, it, de, es, ar, fa, grc, he, la, hbo`). Users have requested all
languages; the original build script is lost but the un‑normalized 23.6 GB
source survives on HF, and the rebuild recipe is in
[PLAN.md §3](PLAN.md#3-rebuild-conceptnet-for-all-languages).

## External services this pipeline depends on

All HF artifacts live under the **`cstr`** namespace on Hugging Face — *not*
`CrispStrobe`; that namespace has only legacy unrelated content. The
references to `CrispStrobe/spacy-de` in old Dart files are stale.

| Resource | Type | Role |
|---|---|---|
| `cstr/WiktionaryDE` | Gradio Space | `/analyze_word` — wraps Wiktionary + DWDSmor + HanTa + IWNLP + OdeNet + ConceptNet for DE |
| `cstr/WiktionaryEN` | Gradio Space | English equivalent — wraps Wiktionary + HanTa + Stanza + NLTK + TextBlob + OEWN + OpenBLP + ConceptNet |
| `cstr/nlp-de` | Gradio Space | Multi‑endpoint: morphology, grammar check, inflections, thesaurus, comprehensive analysis (spaCy + LanguageTool + OdeNet + pattern.de) |
| `cstr/spacy_de` | Gradio Space | Legacy spaCy‑only (superseded by `nlp-de`) |
| `cstr/word_enc_de` | Gradio Space | Earlier consolidation experiment (PAUSED) |
| `cstr/conceptnet_normalized` | Gradio Space | Queries `cstr/conceptnet-normalized-multi`; currently RUNNING |
| `cstr/conceptnet_db` | Gradio Space | Older runtime against the un‑normalized DB |
| `cstr/de-wiktionary-extracted` / `-extracted-full` | HF dataset | Raw `wiktextract` JSONL (DE) |
| `cstr/de-wiktionary-sqlite` / `-normalized` / `-full` / `-semantic` | HF dataset | Normalized DE SQLite ladder (970k entries, 3.1M senses) |
| `cstr/en-wiktionary-extracted` / `-all` | HF dataset | Raw `wiktextract` JSONL (EN) |
| `cstr/en-wiktionary-sqlite-full` / `-all` | HF dataset | Normalized EN SQLite (1.24M entries) |
| `cstr/conceptnet-de-indexed` | HF dataset | 23.6 GB un‑normalized full‑language ConceptNet SQLite |
| `cstr/conceptnet-normalized-multi` | HF dataset | 1.78 GB normalized 11‑language SQLite (shipped) |

## Where the work happened

- **Laptop** (`/Users/christianstrobele/code/voc/`) — steps 01–14 of the DE
  pipeline, run interactively.
- **VPS_2** (`91.107.213.126`, hostname `ubuntu-2gb-fsn1-1`, Hetzner fsn1) —
  hosts `/root/run_wiktionary_extract.sh`: pulled
  `dewiktionary-latest-pages-articles.xml.bz2` from Wikimedia dumps, ran
  `wiktextract` (clone of `tatuylonen/wiktextract`), pushed the result as
  `cstr/de-wiktionary-extracted`. **⚠️ The HF token is in
  `~/.bash_history` in plaintext** — see [LEARNINGS.md](LEARNINGS.md)
  for the rotation recipe.
- **VPS_3** (`135.181.205.133`) — **suspected** host of the ConceptNet
  normalize‑and‑filter run, but auth currently failing with the password in
  `.env`. The build script for `cstr/conceptnet-normalized-multi` is the
  one missing artifact from this audit; if it survives anywhere, it
  survives there.
- **VPS_1** (`185.144.70.11`) — audited, only hosts the `ev3.crispstro.be`
  reverse‑proxy / nginx work, **not** part of this pipeline.
- **HF Spaces hardware** — runs everything tagged "Gradio Space" above.
  Spaces sleep when idle; first request after sleep takes ~30 s while the
  container warms.

## Quick‑start commands (read PLAN.md before running)

```sh
# Rebuild the DE DB end‑to‑end (assuming you've restored scripts from backup)
cd pipeline/voc-de
python 01_consolidate_wordlists_csv.py
python 02_enrich_with_spacy_csv.py
python 03_conv_csv_to_json.py
python 04_add_nrw_data.py
python filter_voc.py                # LLM child‑safety filter
python 05_phoneme_enricher.py
python 06_generate_grapheme_variants.py
python 11_reprocess_full_wikidict.py  # V24 superset; replaces all 07_* variants
python 12_api_wins_3.py
python 13_fix_genders_manually.py
python 13b_enrich_with_openthesaurus.py
python 14_convert_db_to_sqflite.py
gzip -9 grundwortschatz.db -c > ../../assets/grundwortschatz.db.gz
```

Wall time on a recent laptop: ~3–8 h depending on HF Space warmup and
`/analyze_word` latency.

## Status of this audit

| Question | Answer |
|---|---|
| Is the DE pipeline reproducible today? | **Yes** — scripts survive in the backup folder, all HF artifacts are accessible, see PLAN.md §1. |
| Is the EN backbone in place? | **Yes** — `cstr/WiktionaryEN` is RUNNING, EN Wiktionary SQLite is on HF. |
| Is the EN pipeline written? | **No** — needs ~2 weeks of porting. See PLAN.md §2. |
| Is the ConceptNet build script recoverable? | **Probably not** — but the rebuild recipe in PLAN.md §3 reproduces the schema. |
