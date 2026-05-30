# HISTORY — How the voc DB and ConceptNet explorer got built

Chronological reconstruction from file timestamps in the backup folder,
git commits in the working repo, VPS bash history, and HF dataset
creation dates. Date format: YYYY‑MM‑DD. Timezone is local
(Europe/Berlin) where ascertainable.

## 2025‑10‑25 — Seed sources collected

First wave of pedagogical wordlists added to
`/Volumes/backups/code/voc/lib/features/games/data/`:

- **NRW Grundwortschatz** Klasse 1 + Klasse 3, Langform + Kurzform —
  `Grundwortschatz1L.csv`, `Grundwortschatz1S.csv`,
  `Grundwortschatz3L.csv`, `Grundwortschatz3S.csv`. These are the
  pedagogical core: words German primary schoolers in North
  Rhine‑Westphalia are expected to master per grade.
- **CEFR sets** — `A1.csv`/`.json`, `A2.csv`/`.json`, `B1.csv`/`.json`.
- First `consolidate.py` written — merges them into a unified candidate
  pool.

## 2025‑10‑26 — Greek spaCy experiment

`test_grecy.py` appears (probably a grcy / classical Greek spaCy probe).
Not part of the voc pipeline but a sign the user was scoping wider
language coverage.

## 2025‑11‑03 — First DE corpus + phonemization

- `voc_de_old.csv` (pre‑pipeline DE words),
  `voc_de_phonemized.csv` (espeak‑ng phonemization probe), `grapheme.json`
  (mapping table), `test_phonemizer.py`.
- `phoneme_enricher_old.py` and `generate_grapheme_variants_old.py` —
  predecessors of pipeline steps 05 and 06.

## 2025‑11‑04 — Pattern‑de Space scaffolding

In `/Volumes/backups/code/pattern-de/`: first prototypes of single‑service
HF Spaces, one per German NLP backend:

- `languagetool-app.py`, `nlp-app.py`, `odenet-app.py`, `pattern-app.py`,
  `spacy-app.py`.

These were later consolidated into `cstr/WiktionaryDE` (one Gradio space
that dispatches across all backends).

## 2025‑11‑06 — ConceptNet pivot

- `conceptnet_checker.py` runs against `api.conceptnet.io` — every
  request returns 502 (`conceptnet_test_results.json` records all the
  failures). The public API is dead/unreliable.
- **Pivot** to a local SQLite approach.
- `ccn_app.py` → first attempt downloads `ysenarath/conceptnet-sqlite`
  (`data/conceptnet-v5.7.0.db`), filters to German, uploads to
  `cstr/conceptnet-de-indexed`.
- `cnn_app_2.py` → resumable version with `indexing_progress.json`.
  This is **the only surviving build script that touches the
  un‑normalized DB.** Output: `cstr/conceptnet-de-indexed` (23.6 GB,
  all‑languages).

## 2025‑11‑07 — ConceptNet normalize step

- HF dataset `cstr/conceptnet-normalized-multi` (1.78 GB, 11 languages:
  `en, fr, it, de, es, ar, fa, grc, he, la, hbo`) created.
- The Gradio runtime `cstr/conceptnet_normalized` (= the contents of
  `/Users/christianstrobele/code/conceptnet_app_1.py`) starts serving
  against it.
- **The normalize‑and‑filter build script that produced this DB does
  not survive** in any of the audited locations
  (`/Users/christianstrobele/code`, `/Volumes/backups/code`, the HF
  dataset repo itself, or the Space repo). The schema is
  `node_norm / rel_norm / edge_norm` (full URLs in `node_url`,
  integer FK in `edge_norm`); see PLAN.md §3 for the rebuild recipe.
- Strong suspicion: the script ran in a tmp dir on **VPS_3
  (135.181.205.133)**, was never `rsync`'d back, and was lost when the
  tmp dir was cleared. VPS_3 currently refuses the `.env` password —
  needs updated credentials before we can confirm.

## 2025‑11‑08 — DE Wiktionary pipeline starts on VPS_2

On **VPS_2 (`91.107.213.126`)**, `/root/run_wiktionary_extract.sh` is
created (5,844 bytes, dated Nov 7 actually — `mtime` on the file is
Nov 7 although bash_history shows execution on Nov 8). It:

1. Downloads `dewiktionary-latest-pages-articles.xml.bz2` from
   `dumps.wikimedia.org`.
2. Clones `tatuylonen/wiktextract` and pip‑installs editable in a venv.
3. Runs `python -m wiktextract.wiktwords --all --edition de
   --language-name German --out de-wiktionary.jsonl`.
4. Loads the JSONL with `datasets.load_dataset` and `push_to_hub`'s to
   `cstr/de-wiktionary-extracted`.

Bash history shows it ran twice (once edited in between). The working
tree `/tmp/wiktionary_extract/` was wiped after the run. **The HF token
is committed to `/root/.bash_history` in plaintext** —
`hf_***REDACTED***` (rotate on HF — token previously written here in full). See LEARNINGS.md.

Locally, pattern‑de Space iterates: `de-wiktionary.py`, `enc-app.py`,
`nlp-app_2.py`, test scripts `test4..test9.py`, `test_iwnlp*.py`,
`wt1.py`, `upload_wiktionary_json.py`. The single‑service spaces are
being unified.

## 2025‑11‑09 — Pattern‑de iterations

`enc-app_2.py`, `_3.py`, `_4.py`, `enrich_wikt.py`. The unified
encyclopedia‑style endpoint is taking shape.

## 2025‑11‑10 — Pattern‑de stabilizes

`enc-app_5.py`, `enc-app_5b.py`, `test_dwdsmor.py`. `5b` is the version
that becomes `cstr/WiktionaryDE`'s `/analyze_word`. From here on, the
voc pipeline calls a single HF endpoint instead of N single‑service
ones.

## 2025‑11‑11 — First wave of voc pipeline scripts

Massive commit of pipeline files into
`/Volumes/backups/code/voc/lib/features/games/data/`:

- `02_enrich_with_spacy_csv.py`, `05_phoneme_enricher.py`,
  `06_generate_grapheme_variants.py`, `07_enrich_wikt.py`,
  `08_fix_word_types.py`, `09_build_db.py`.
- Source files: `de-wiktionary.jsonl` (placeholder; truly populated on
  VPS_2 + HF), `de_50k_hermitdave.txt`, `top10000de.txt`,
  `top10000de_unileipzig.txt`, `Buchmeier20k.txt`, `hamburg.txt`,
  `verb_government.json`, `verb_government_hdt.json`.
- Utilities: `cons5.py`, `cons5a.py`, `consolidate.py` (drafts),
  `enrich_old.py`, `enrich_ud.py`, `extract.py`, `extract_ud.py`,
  `frequencies.py`, `phoneme_enricher_old.py`, `word_types.py`,
  `fix_json.py`, `data.json`, `output_nested.json`, `conv_to_json_old.py`.
- `inflection_enricher.dart` + `snake.dart` (the latter unrelated).
- The (now stale) `readme_pipeline.md` describing a 3‑step pipeline —
  ignore it.

First end‑to‑end DB build attempted.

## 2025‑11‑12 — NRW Merk‑/Nachdenkwörter

- `111_NRW_Merkwörter.txt` — words children must memorize (irregular
  spellings).
- `422_NRW_Nachdenkwörter.txt` — words requiring rule‑based reasoning.

These feed the grade‑level assignment and the spelling‑game distractor
generator.

## 2025‑11‑14 — Pipeline refactor

The numbered pipeline takes its final shape:

- `01_consolidate_wordlists_csv.py` rewritten (older draft saved as
  `_old.py`). Priority dedup chain:
  `pedagogical > Buchmeier > Leeds > Leipzig > HermitDave`.
- `04_add_nrw_data.py` — merges NRW Excel data into the JSON, including
  spelling rules.
- Error CSVs: `100Fehler.csv`, `200Fehler.csv`, `300Fehler.csv`,
  `400Fehler.txt`. (`100/200/300` are real children's misspellings;
  `400` is a larger generated set.)
- `532Strategien.csv` — spelling strategy mapping.
- `739Leo.csv` — Leo.org corpus (different frequency band than Leipzig).
- `wortliste-grundwortschatz-nrw.xlsx` + `conv_xls.py` — the
  authoritative NRW Excel + the converter.
- `YOUR_FILE.xlsx` — historical artifact (looks like a placeholder name
  that never got renamed).

## 2025‑11‑15 — HF enrichment integration

- `03_conv_csv_to_json.py` — final CSV→JSON converter with grade
  assignment.
- `03a_fix_grades.py` — re‑applies grade logic with refined source
  weights (NRW111=2, NRW422=2, LEO739=3).
- `07_enrich_hf.py` — the **first** Gradio call to
  `cstr/WiktionaryDE /analyze_word`. Engine = `wiktionary`, server‑side
  fallback chain to DWDSmor/HanTa/IWNLP.
- `07_enrich_hf_with_hyphenation.py` — V23 superset adding
  `hyphenation` and unwrapping `synonym_word`/`antonym_word` dict
  shapes.
- `filter_voc.py` — **child‑safety LLM filter**. Profanity/inappropriate
  detection via Groq/Together/OpenRouter fallback (keys in
  `/Users/christianstrobele/code/.env`). Output: `grundwortschatz_safe.json`.
- `check_conflicts.py` — diagnostic catching false positives where the
  profanity filter rejected a pedagogical NRW word.
- `test_google_api.py` — experiment (probably TTS).

## 2025‑11‑16 — English filter

- `10_only_english.py` — German→English translation filter (despite the
  name, it does **not** build an English vocabulary; it trims the
  multilingual `wiktionary_translations` array to keep only
  `lang_code=='en'`).
- `normalize_wiktionary.py` — utility used on VPS side to turn the raw
  wiktextract JSONL into the normalized SQLite that powers
  `cstr/WiktionaryDE`.

## 2025‑11‑17 — V24 reprocess

- `11_reprocess_full_wikidict.py` — re‑runs the Gradio Space against the
  **whole** vocabulary with `--no-limits` and the V24 field set:
  hyphenation, expressions, proverbs, entryNotes, hypernyms, hyponyms,
  holonyms, meronyms, coordinate_terms, derived_terms, related_terms,
  translations. This is a **superset of step 07** — for a fresh
  rebuild, skip 07 and go straight to 11.
- `10_english_only_2.py` — same intent as `10_only_english.py`, pointed
  at the V24 file rather than V23.
- `12_api_wins.py` + `_2.py` — first attempts at the API‑wins
  consolidation pattern (let API‑derived fields override locally
  inferred ones, but conservatively — only fill empty fields).

## 2025‑11‑18 — English Wiktionary normalization

- `norm_all_6_en.py` — VPS‑side script that pulls
  `cstr/en-wiktionary-extracted-all` from HF and builds a normalized
  SQLite (~30 tables) with all the same shapes as
  `de-wiktionary-sqlite-full`. Optionally pushes to
  `cstr/en-wiktionary-sqlite-all`.
- `wikt-en.sh` — full VPS bash equivalent of
  `run_wiktionary_extract.sh` but for the English dump
  (`enwiktionary-latest-pages-articles.xml.bz2`, ~10 GB; multi‑hour
  CPU job). Pushes `cstr/en-wiktionary-extracted-all`.

## 2025‑11‑19 — Final polish

- `12_api_wins_3.py` — **the shipped version**. Handles a `tags` field
  as either list or string, logs conflicts, never overwrites an
  existing genus.
- `13_fix_genders_manually.py` — hand‑curated `MANUAL_FIXES` dict (~95
  nouns where the v12 conflict log showed existing data was wrong).
  Auto‑backs up.
- `13b_enrich_with_openthesaurus.py` — parses the OpenThesaurus MySQL
  dump for synonyms / hypernyms / hyponyms / associations, attaches as
  `apiEnrichment.openThesaurus`. **OpenThesaurus dump must be
  downloaded manually** from `openthesaurus.de`.
- `14_convert_db_to_sqflite.py` — final ship‑DB. Flattens to the
  four‑table schema (`words` with JSON blobs + `translations` +
  `examples` + FTS5 `search_index`).
- `analyze_mysql_dump.py` — schema explorer used while writing 13b.

## Some time after Nov 19, 2025 — The Great Compression

Commit `8364f26` *"fix: responsive ui and compress database"* on the
voc main branch:

- The final SQLite is compressed to
  `assets/grundwortschatz.db.gz`.
- The Flutter bundle drops from ~140 MB to ~30 MB (DB compresses ~4×).
- **The entire `lib/features/games/data/` build directory is deleted
  from the working repo**, including all 14 numbered scripts, all
  source CSVs, and `readme_pipeline.md`. The deletion is intentional —
  build inputs and intermediates don't belong in a shipped Flutter
  bundle. They survive only in `/Volumes/backups/code/voc/`.

Subsequent commits (`0aa1e6b`, `fa44a12`, current `main`) are post‑build
app work (a11y, streak fire tap, version bump, etc.) — not pipeline.

## 2026-05-21 — DE DB v1.2.x ship-ready rebuild via in-place patches

A single intensive session moved the shipped DB from "feature-complete
v1.1 with mixed-attribution issues" to "v1.2.x — every word
attributed, multi-corpus frequency, algorithmic grade-band, ready for
HF dataset upload". 17 commits between `1f0c72b` and `aaa39ee`. All
patches operate in-place on `assets/grundwortschatz.db.gz`; no full
pipeline re-run was needed.

Summary of what landed (in chronological order):

| Commit | What |
|---|---|
| `f47bb8f` | Dual-taxonomy spelling-pattern fields (`spellingStrategy` 6-cat detailed + `spellingPatterns` 5-cat broad), Wikipedia "Häufige Falschschreibungen" misspellings, deleted misnamed `extract_exercises.dart` duplicate. Pubspec → 1.2.0. |
| `2581d38` | Stripped residual `LEO739` source-attribution token from 731 words (Leoschule Lünen list, no formal license). 38 became sourceless; 33 of those later rescued by Bundesländer integration. |
| `d02f979` | Berliner Grundwortschatz (LISUM 2024, **CC-BY-SA 4.0 explicit**) → 1339 word attributions. |
| `39709c4` | Hessischer Grundwortschatz (Hess. KuMi, §5 UrhG amtliches Werk) → 1599 attributions. |
| `a83c181` | Brandenburger Grundwortschatz (LISUM 2024, **CC-BY-SA 4.0 explicit**) → 1342 attributions. |
| `8c3a70d` | Hessen enrichment — added 53 orthographic-pattern categories per word (`hessenCategories`). |
| `bc4e8d3` | Rheinland-Pfalz Grundwortschatz (Min. Bildung Mainz, §5 UrhG, RLP-adapted Hessen list with Hessen permission) → 1378 attributions + 40 categories. |
| `9429c98` | Niedersachsen Orientierungswortschatz (Nds. KuMi 2015, §5 UrhG) → 1455 attributions. |
| `907ce85` | Bayern Grundwortschatz (ISB Bayern, §5 UrhG) → 1087 attributions + 43 fine-grained orthographem-level categories. |
| `cc70030` | Schleswig-Holstein Rechtschreib-Grundwortschatz (SH MinBuB / IQSH 2023, §5 UrhG via SH redistribution path) → 633 attributions + 59 hierarchical categories. |
| `e791ae9` | DWDS Lemma-Datenbank Häufigkeitsklassen (DWDS / BBAW, **CC-BY-SA 4.0**) → 8844 words tagged with 7-level frequenzklasse 0-6 + Wortklasse. |
| `b6d084d` | **childLex** age-graded lexical norms (Schroeder et al. 2015, **GPL-3.0**) → 9307 words tagged with age1/age2/age3 freq norms. **License cascade**: composite DB now ships as GPL-3.0 (per CC's 2015 v4-compatible decision, CC-BY-SA-4.0 → GPL-3.0 is one-way compatible). App code stays under its own license. |
| `99cbd3d` | Draft HF dataset README at `pipeline/voc-de/HF_DATASET_README.md` ready for `cstr/grundwortschatz-voc-de` upload. |
| `0f2e497` | App-side `LicenseRegistry` entries for all 9 new sources + composite-license posture statement + dynamic `applicationVersion` via `package_info_plus`. |
| `c7631ec` | Algorithmic `metadata_json.gradeLevelEstimate` (1-6) + `gradeLevelEstimateSource` per word — combines NRW-authoritative for Kl 1-4, childLex age-band presence for refinement, DWDS frequenzklasse as fallback. |
| `aaa39ee` | Parquet companion files for HF upload — `words.parquet`, `translations.parquet`, `examples.parquet` at `pipeline/voc-de/hf_export/` + the `export_to_parquet.py` regenerator script. |

### Skipped this session (with rationale)

- **Hamburg Basiswortschatz** — netzbar.de Impressum is all-rights-reserved. Not safe to integrate without written permission from `netzbar.de` (the commercial contractor) or Schulbehörde Hamburg directly.
- **Sachsen** — only Klasse 1 PDF found at cms.sachsen.schule; PDF metadata shows "Schicker PC" as creator, fileadmin/user_upload/ path suggests user-contributed content, publisher authority unclear. Per Blumenthal 2020 Sachsen has only "häufigste 100 Wörter" anyway.
- **Mecklenburg-Vorpommern** — Blumenthal-cited URL (bildung-mv.de/downloads/Handreichung-Mindestwortschatz.pdf) is 404, not in Wayback Machine, regierung-mv.de press-release URL returns only the announcement PDF (not the handreichung itself). Defer until the file resurfaces.
- **Re-extract NDS with categories** — present extraction is lemma-only; two-column PDF layout makes header-to-word association ambiguous, queued as future work.

### Provenance / new dependencies

`pipeline/voc-de/` gained 12 new scripts in this session:

- `patch_existing_db.py` (orig 9bb2fa, polished here) — dual taxonomy + misspellings
- `strip_leo_attribution.py`
- `add_berlin_grundwortschatz.py` / `add_brandenburg_grundwortschatz.py`
- `add_hessen_grundwortschatz.py` (with categories) / `add_rheinland_pfalz_grundwortschatz.py`
- `add_niedersachsen_orientierungswortschatz.py`
- `add_bayern_grundwortschatz.py` / `add_schleswig_holstein_grundwortschatz.py`
- `add_dwds_haeufigkeitsklassen.py`
- `add_childlex_norms.py`
- `compute_grade_level_estimate.py`
- `export_to_parquet.py`

All scripts are idempotent: re-running on the patched DB will detect
already-tagged words and skip them (no duplicate tokens, no
double-attribution).

## 2026-05-22 — EN DB v1 shipped; DE graphematicVariants wiring fixed

### EN DB v1 shipped (`assets/grundwortschatz_en.db.gz`, 8.6 MB)

Full record in `pipeline/voc-en/HISTORY.md`. Summary:

- **7,878 lemmas**, 99.2 % enriched via `11b_enrich_local.py` on VPS
- **27,363 misspelling annotations** (Norvig + Wikipedia) on 59 % of entries
- **270 dialect variants** (UK ↔ US) via SCOWL step 12c
- **25,659 OEWN WordNet sense records** on 70 % of entries
- Steps 12_api_wins, 12c (SCOWL), 12d (Wiktionary-marker fold), 13 (WordNet)
  all completed in this session. Step 14 final DB build shipped.
- Architectural decisions locked in: UK English canonical, 10k filterable,
  UK Y1–6 grade mapping, single app with both DBs bundled (L2L × GUI matrix).

### DE — graphematicVariants wiring fix

`graphematicVariants` were correctly written into `enrichment_json` by
pipeline step 15 (`15_patch_graphematic_variants.py`) for 5,514 of 10,450
words, but `_mapRowToGermanWord` in
`lib/core/services/dictionary_database_service.dart` never exposed them to
`GermanWord.fromJson` — the field lived under `wordMap['apiEnrichment']` but
`fromJson` read `json['graphematicVariants']` from the top level (populated
only from `metadata_json` spread). One-line collection-if fix promotes the
field from `apiEnrichment` to the top level of `wordMap`.

The remaining 4,936 words have no variants in `enrichment_json` at all
(no matching DE grapheme-confusion rules and no wiki misspellings) — correct
behaviour, not a bug.

### DE — FEHLER* source tags purged + Menzel license removed

674 words had `FEHLER100`/`FEHLER200`/`FEHLER300`/`FEHLER400` in
`metadata_json.sources`. These tags referenced Tacke-derived content
(Menzel 1985) that was never actually shipped as misspelling data
(only influenced word inclusion). Tags stripped via SQLite UPDATE,
`commonMistakes` was null for all 10,450 DE words. Remaining 174
LIKE '%FEHLER%' hits after strip are German compound words containing
`-fehler` (Abbildungsfehler etc.) — not tags. Menzel `LicenseRegistry`
block removed from `lib/core/services/custom_licenses_registry.dart`.

### DE — LiTKey corpus integrated (CC-BY-SA 4.0)

Two new pipeline patcher scripts added under `pipeline/voc-de/`:

**`add_litkey_errors.py`** — downloads `Litkey-Tab.csv` (44 MB, CC-BY-SA
4.0, Müller et al. 2021, RUB Bochum), extracts `(orig, target)` pairs
where `erroneous==1`, and populates `commonMistakes[]` in `metadata_json`
via an inflection-aware index. Result: **1,923 entries annotated with
8,035 misspelling strings** (source tag `LITKEY`). Corpus covers grades
2–4 primary school German children's writing.

**`add_litkey_profiles.py`** — aggregates per-lemma statistics from
the full corpus (all 212,505 tokens, not just errors):
- `litkey_error_rate` (float 0.0–1.0) — empirical misspelling frequency
- `litkey_error_profile` (dict) — fraction of errors per category:
  `devoice_final`, `h_length`, `h_sep`, `schwa_silent`, `ie`,
  `doubleC_syl`, `doubleC_other`, `graph_marked`, `morph_bound`, etc.
  (maps 1:1 to NRW morphematisches Prinzip categories already in DB)
- `litkey_grade_first_correct` (int 2/3/4 or null) — grade at which
  correct tokens first appear (mastery indicator)
- `spellingDifficulty` recomputed from error rate (enum index 0–3):
  `<0.25` easy, `<0.50` medium, `<0.75` hard, `≥0.75` expert

Result: **2,906 entries updated**, **1,652 `spellingDifficulty` values
changed** from heuristic-0 to empirical values. Shipped DB → 20 MB
(up from ~7 MB; wordnet data in EN is the driver there).

LiTKey license entry added to `custom_licenses_registry.dart`
(entry `9h-extra14b`). CC-BY-SA 4.0 is compatible with the existing
DB posture (GPL-3.0 via childLex is the effective license).

---

## 2026-05-24 — EN DB expansion + post-enrichment infrastructure

### EN DB: curriculum coverage gap filled (7,878 → 11,539 entries)

`add_missing_curriculum_en.py` identified 3,661 CEFR-J A1-B2 / YLE /
UK statutory words absent from the original hermit_dave-based 7,878-entry
DB. Inserted with `enrichment_status='minimal'`. All post-pipeline scripts
re-run with `--overwrite` on the expanded DB.

Final enrichment_status: success=7,815 / minimal=3,661 / no_data=63.

### EN DB: metadata enrichment (full 11,539 entries)

- **wordfreq** (Apache-2.0 + CC-BY-SA 4.0) — Zipf, per_million, band 1–5 for all 11,539
- **CEFR-J v1.5** (CC-BY-SA 4.0) — level tags for 6,879 entries
- **Cambridge YLE** (factual) — Starters=216, Movers=324, Flyers=293
- **UK DfE statutory lists** (OGL v3) — Y1-Y2=139, Y3-Y4=≈100, Y5-Y6=≈96
- **gradeLevelEstimate** (1–6) — computed via decision tree for all 11,539
- **grade_level column** synced from gradeLevelEstimate (was miscalibrated)

### EN DB: new post-build patcher scripts

- **`enrich_minimal_en.py`** — Wiktionary defs/inflections/pronunciation
  for the 3,661 `minimal` entries; queries local Wiktionary DB at
  `/Volumes/backups/code/WiktionaryEN-space/en_wiktionary_normalized.db`;
  4 workers; JSONL checkpoint; mtime-based resume.

- **`add_oewn_en.py`** — OEWN sense expansion for entries with empty
  `wordnetSenses`; single-threaded (wn not thread-safe); ~600 lookups/s;
  `--filter-status any` to cover both success and no_data entries.

### EN DB: grade fill running

`add_llm_examples_en.py --grade` running as PID 9034 (5,917/11,539
at session end). After completion, run the post-fill sequence in
`pipeline/voc-en/PLAN.md`.

### Dart fixes

- **`dictionary_database_service.dart`**: injects `grade_examples` and
  `gutenberg_examples` from `metadata_json` into `apiEnrichment` before
  `ApiEnrichment.fromJson` (were always null before).
- **`vocabulary_models.dart`**: `gradeExamples`, `gutenbergExamples` added
  to `ApiEnrichment`; `gradeLevelEstimate`, `cefrLevel` added to `GermanWord`.

### License registry updates (custom_licenses_registry.dart)

Added: OEWN (CC-BY 4.0), wordfreq (Apache-2.0 + CC-BY-SA 4.0),
CEFR-J v1.5 (CC-BY-SA 4.0), Cambridge YLE (factual), UK DfE statutory
lists (OGL v3), Norvig spell-errors.txt (MIT + CC-BY-SA), Project
Gutenberg (public domain), SCOWL spelling variants (MIT-like).
Removed: duplicate UK statutory lists entry (9f vs 9r).

### Pipeline gitignores

Added `pipeline/voc-en/.gitignore` and `pipeline/voc-de/.gitignore`
to exclude large build artifacts (DBs, JSON dumps, Parquet exports,
Gutenberg text caches) while tracking scripts and source data.

### DE DB: LiTKey error annotations applied

`add_litkey_errors.py` (newly imported from `~/code/wiktionary/`) applied
against `Litkey-Tab.csv` (212,505 rows, already downloaded). Updated 383
entries with 999 new `metadata_json.commonMistakes` annotations. Total
entries with commonMistakes: 2,401. The LiTKey corpus (CC-BY-SA 4.0,
Rauschii et al., grades 2–4, 37k+ annotated tokens) provides empirical
child misspellings rather than sourced error lists.

### DE DB: word_type backfill for LITKEY entries

885 non-Vorname entries inserted by `add_litkey_words.py` had blank
`word_type`. Applied inline Python patch mapping
`enrichment_json.partOfSpeech` → lowercase `word_type` column:
Substantiv→substantiv, Verb→verb, Adjektiv→adjektiv, Adverb→adverb,
Eigenname/Interjektion→andere, Zahl→numerale. The remaining 2,150 blank
entries are Vornamen (intentionally blank; `partOfSpeech="Eigenname"` in
`enrichment_json`). Total with word_type: 10,890 / 13,040.

### DE DB: LiTKey spelling difficulty profiles

`add_litkey_profiles.py` (newly imported) computed per-lemma spelling
difficulty profiles from `Litkey-Tab.csv` and stored in `metadata_json`:
- `litkey_error_rate`: fraction of child writing tokens that were
  misspellings (0.0–1.0)
- `litkey_error_profile`: error-type breakdown (graph_comb, ie, doubleC,
  h_length, Auslautverhärtung, morph_bound, etc.)
- `litkey_grade_first_correct`: lowest grade where children spelled it right
- `litkey_word_features`: phonological properties of the word itself
- `litkey_orth_neighbourhood`: childLex bigram_sum + old20 metrics
- `spellingDifficulty`: recomputed from error_rate (0=easy … 3=expert)

Updated 3,487 entries. spellingDifficulty recalibrated for 61 of them.

### DE DB: grade fill for 261 missing entries (running)

`add_llm_examples.py --grade` started for 261 entries with no
`grade_examples` at all (all have `grade_level` IS NULL or grades 1-6).
Providers: Groq, Mistral, Nebius (Cerebras disabled). Checkpoint at
`pipeline/voc-de/grade_results.jsonl`.

### Fix: `response_format={"type": "json_object"}` for LLM grade fill

Diagnosed root cause of ~98% parse failures in both DE and EN grade fills:
Nebius/Scaleway/Mistral Llama-3.3-70B outputs `}}}` instead of `]}}` at
the end of JSON (missing `]` for grade-6 array). `parse_json()`'s
`rfind('}')` fallback cannot repair malformed JSON.

**Fix:** Added `response_format={"type": "json_object"}` to
`prov["client"].chat.completions.create()` when `mode == "fill"` in both
`add_llm_examples_en.py` (~line 258) and `add_llm_examples.py` (~line 265).
Failure rate dropped from ~98% → ~1%.

Also excluded Groq and Cohere by clearing their env vars
(`GROQ_API_KEY="" COHERE_API_KEY=""`) — both rate-limit aggressively and
produce malformed output anyway. Active providers: Nebius, Scaleway, Mistral.

### DE DB: check pass running (994/~2,343)

`add_llm_examples.py --check` restarted (PID 54479) with response_format
fix. Checkpoint `check_results.jsonl` at 994 entries (up from 241 at
start of day). Groq/Cohere excluded.

### EN DB: grade fill running (7,112/11,539 = 62%)

`add_llm_examples_en.py --grade` restarted (PID 53732) with response_format
fix. Checkpoint `grade_results_en.jsonl` at 7,112. Groq/Cohere excluded.
Wiktionary DB confirmed accessible (`enrich_minimal_en.py --limit 3`
returned 3/3 successes).

---

## 2026-05-25 — DE DB complete; EN DB enrichment continued

### DE DB: grade fill + check pass complete

- `add_llm_examples.py --grade` (PID 11066): 141/155 entries filled (91%).
  Fix applied: `GRADE_MAX_WORDS` raised from `{1:6,2:6,3:9,4:9,5:12,6:12}`
  to `{1:10,2:10,3:14,4:14,5:18,6:18}` — German sentences for grades 1-2
  are naturally 8-10 words; old 6-word limit rejected all Llama-3.3-70B output.
- `add_llm_examples.py --check` (PID 54479): 1,944 entries corrected,
  21,240 sentences stored. 0% invalid rate (response_format fix effective).
- **Final coverage: 10,876/10,890 = 99%** non-Vorname entries with grade_examples.
  14 very hard words (all LLM attempts rejected by _valid_grade_block) remain.
- Compressed: `assets/grundwortschatz.db.gz` **148 MB → 24 MB**. ✅

### EN DB: grade fill + check-all complete

- `add_llm_examples_en.py --grade` (PID 53732): **4,578 entries updated**, 52,912
  sentences stored. 11,481/11,539 (99%) final coverage.
- `add_llm_examples_en.py --check-all` (PID 13204): **10,692/11,481 corrected**
  (93% success, 756 null = function words / hard cases where LLM gave up).
  Provider stats: Nebius 0% bad, Scaleway 0% bad, Mistral 0% bad.

### EN DB: Gutenberg, uk_curriculum, OEWN

- `add_gutenberg_examples_en.py`: **2,018 entries updated** (now 6,274 total, 54%).
- `add_uk_curriculum.py --grade-only`: grade_level column synced for all 11,539.
- `add_oewn_en.py --filter-status any`: **3,600 new OEWN senses** added
  (9,186 total, 79%); 2,430 no_data; ran in 30s.

---

## 2026-05-26 — EN DB: Wiktionary enrichment for minimal entries via VPS; EN shipped

### Problem: `enrich_minimal_en.py` too slow locally

Local external USB drive: 0.1/s → 16h ETA for 3,658 remaining entries. Killed
after overnight run at 1,300/3,658 (35%). Checkpoint preserved in
`/tmp/dbpatch_wikt_minimal_en/wikt_minimal_results.jsonl` (1,386 entries).

### Solution: VPS `168.119.190.252` (Hetzner)

VPS already had `en_wiktionary_normalized_all.db` (2.0 GB) on NVMe from
the original EN enrichment run. Uploaded patched script + DB + checkpoint,
ran with 4 workers → **1.4/s, completed in 27 min**.

```
success=2272 new + 1386 checkpoint = 3658 total enriched
no_data=3 (words not in English Wiktionary)
errors=0
```

All 3,661 `enrichment_status='minimal'` entries now have definitions,
inflections, pronunciation. Status updated to success/no_data.

### EN DB final stats (assets/grundwortschatz_en.db.gz)

| Field | Value |
|---|---|
| Total entries | **11,539** |
| definitions | 11,486 (99%) |
| grade_examples | 11,481 (99%) |
| wordnetSenses | 9,186 (79%) |
| gutenberg_examples | 6,274 (54%) |
| enrichment_status minimal | **0** — fully enriched |
| Compressed | **92 MB → 17 MB** ✅ |

---

## 2026-05-27 — App l10n / a11y pass (games + UI)

Full systematic pass replacing all hardcoded DE/EN strings in game screens
with l10n ARB keys and Semantics labels.

### ARB keys added (app_en.arb + app_de.arb)

Over two sessions (~150 new keys total), covering:

- `wordOfTheDay`, `pronounce`, `tapToPractise`, `gradeLabel`, section headers
  (`sectionDefinitions/Examples/Synonyms/Antonyms`), `didYouKnow`, `practiceNow`
- Karteikasten: `karteikasten`, `karteikastenCardMoved`, `boxLabel`, `boxLabelCurrent`,
  `moveCard`, `boxEmptyMastered/Default`
- Game onboarding bodies: synonym, cloze, antonym, hypernym, sri_review, definition_quiz,
  sentence_completion, spelling_spotter, conjugation_drill, syllable_count, word_class_flash
- Game empty states: `noSynonymData`, `noClozeSentences`, `noHypernymData`, `noDefinitionData`,
  `noSpellingData`, `noSyllableData`, `noWordClassData`
- Semantics accessibility labels: `semanticsBack`, `semanticsScore({n})`,
  `semanticsProgress({done},{total})`, `semanticsCombo({n})`
- Word type names: `wordTypeNoun/Verb/Adjective/Adverb`
- Achievement keys: `achievementGrade2–6Title/Desc`
- Misc: `skip`, `gotIt`, `next`, `debugModeEnabled`, `gameLvlBadge`

### Files modified

- `lib/l10n/app_en.arb` + `lib/l10n/app_de.arb` — ~150 new keys
- `lib/generated/l10n.dart` — regenerated
- `lib/features/games/screens/` — 12 game screens localised:
  synonym_flash, cloze_flash, antonym_flash, hypernym_flash, sri_review,
  definition_quiz, sentence_completion, spelling_spotter, conjugation_drill,
  karteikasten, syllable_count, word_class_flash
- `lib/features/games/screens/verbtrenner_game.dart` — Semantics labels
- `lib/features/games/screens/parent_dashboard_screen.dart` — hardcoded fallback removed
- `lib/features/home/widgets/word_of_the_day_card.dart` — full l10n
- `lib/shared/widgets/onboarding_overlay.dart` — Skip/Got it/Next localised
- `lib/features/home/screens/home_screen.dart` — debug snackbar localised
- `lib/features/achievements/screens/achievements_screen.dart` — grade_2–6 achievements

### Clean-ups

- `_isDE` getter removed from synonym_flash, cloze_flash, antonym_flash, syllable_count,
  word_class_flash (fully unused after ternary replacements)
- Orphaned `final isDE = _isDE;` locals removed from antonym_flash, hypernym_flash,
  definition_quiz, sentence_completion

---

## 2026-05-29 — Phrasal-verb games + ConceptNet normalizer rebuilt

### EN phrasal verbs + two games (#46, #47)

Added a `phrasal_verbs` table to `grundwortschatz_en.db` (400 verbs from
Wiktionary's "English phrasal verbs" categories, CC-BY-SA) and two EN-only
games on top of it: **Phrasal Verb Power** (pick the particle) and **Phrasal
Verb Match** (pick the meaning). 398/400 LLM grade-leveled (nebius/scaleway/
groq/openrouter), content-filtered for K-6 (`kill`/`do in` excluded), deduped.
Pipeline: `pipeline/voc-en/add_phrasal_verbs_en.py`. Full detail in
`pipeline/voc-en/HISTORY.md → 2026-05-29`. App at `pubspec` 1.3.0; `flutter
build web` passes with the EN asset bundled; full test suite 452/452.

### ConceptNet normalizer rebuilt (the lost §3 script)

Materialized `pipeline/conceptnet/build_normalized.py` — the normalizer that
turns `cstr/conceptnet-de-indexed.db` (23.6 GB) → `conceptnet_normalized_all.db`.
Runs on an **8 GB VPS** (binding constraint is disk ~60-70 GB, not RAM):
256 MB cache, `temp_store=FILE` for the big index sorts, keyset paging,
WAL+checkpoint resume. Verified end-to-end on a synthetic source; not yet run
on the real dump. ConceptNet expansion remains optional (relations are already
in the shipped voc DBs).

### HF token "leak" re-assessed → non-issue

The `hf_…` token flagged in earlier docs was re-assessed: repo is private,
bash_history is on our own VPS, `.env` is local — no third-party exposure.
The "leaked, rotate now" framing was overcautious; value redacted from the
working-tree docs, rotation is optional hygiene.

### Spelling-strategy classifier — re-grounded on the orthographic principles (§6)

> A first cut of this classifier (2026-05-29, intra-day) was fit to an NRW
> classroom worksheet (`532Strategien.csv`) and is **fully superseded** by the
> science-grounded version below. The worksheet was found to be linguistically
> inconsistent (it split identical cases like `Tasse` vs `Puppe` and mis-filed
> rule-governed words as exceptions), so it was demoted from gold standard to an
> advisory smell test. The superseding work and its files are described here;
> the worksheet-era scripts were removed.

A cited deep-research pass (Eisenberg & Fuhrhop, Maas, Gallmann, Schmidt/Fuhrhop,
the amtliches Regelwerk, Günther Thomé) re-grounded the classifier on the
**orthographic principles of German**. Spec + citations:
`pipeline/voc-de/SPELLING_STRATEGY_SPEC.md`. New files in `pipeline/voc-de/`:

- `spelling_strategy_classifier.py` — pure classifier, **7 categories**
  (adds `dehnung` for long-vowel marking) + a **per-word German explanation**
  per word (e.g. „Verlängere: Mann → Männer"), with a category-template
  fallback. Key science decisions: doubling is the Thomé function-based reading
  (all short-vowel doublings = `doppelkonsonant`, `Tasse` = `Mann`), reversing
  the earlier wrong "intervocalic → klangtreu"; `verwandt` = Auslautverhärtung
  (Stammkonstanz); `merkwort` narrowed to genuine etymological exceptions
  (v→[f], ch→[k]); silbentrennendes-h is rule-governed, not a Merkwort.
- `spelling_db_features.py` — DB-row → feature extractor.
- `spelling_strategy_gold.csv` — a 54-word **literature-sourced** exemplar gold
  (each word cites its scholarly source); replaces the worksheet as ground
  truth. `validate_spelling.py` reports **100% primary / 100% set-exact**.
- `test_spelling_strategy.py` — 15 regression tests.
- `patch_spelling_strategy.py` — re-tagged all 10,890 non-Vorname words;
  writes `spellingStrategy` / `spellingStrategyPrimary` / `spellingExplanation`
  / `spellingStrategySource="principle_based_v3"`; drops the obsolete
  dual-taxonomy fields; `nrwLinguisticFeatures` provenance kept.

Full-DB primary distribution: grossschreibung 27%, klangtreu 21%,
doppelkonsonant 20%, morphem 12%, dehnung 11%, verwandt 5%, merkwort 3%
(the old worksheet-fit over-assigned grossschreibung at 49%).

App side: `spellingExplanation` added to `ApiEnrichment` (flows through the DB
service automatically); `SpellingStrategyBadge` gained the `dehnung` chip and
now shows the per-word explanation as its tooltip. Asset recompressed
(`grundwortschatz.db.gz`, ~26 MB, integrity ok). All Flutter tests pass; analyze
clean. Regression-guarded by `test_spelling_strategy.py` (pipeline) +
`test/features/games/spelling_strategy_test.dart` (25 tests, app).

**Noun compounds (2026-05-30):** `morphem` extended to detect noun compounds by
splitting the lemma into two known DB stems (modifier ≥4 + ≥4-char or curated
3-char head, Fugenelement-aware); the explanation names the parts
(„zusammengesetzt: Haus + Tür"). +491 net-new `morphem` nouns; precision held
(simplex `Kamerad`/`Inserat`/`Feinden` no longer false-split). Residual cosmetic
noise: a few proper-noun splits (`Dortmund`) and imperfect parts on inflected
heads (`Nachnamen`) — category correct. DB re-tagged + asset re-shipped; 18
pipeline tests + gold (now 58 words, 100% exact). Remaining documented
limitation: Umlaut-Stammkonstanz is explanation-only, not auto-tagged.

---

## Tail — what isn't dated

- The `top10000en.txt`, `top1000en.txt`, `top1000fr.txt` at the project
  root: undated frequency wordlists, dropped in as future seeds for an
  EN/FR port that hasn't been built yet.
- `enrich_nlpde.dart` and `test_nlp_de_3.dart` at the project root:
  the Dart‑side enrichment client (an alternative path that calls
  `cstr/nlp-de` instead of `cstr/WiktionaryDE`). Used historically but
  superseded by the Python `11_reprocess_full_wikidict.py` path for the
  shipped V24 build.
- `fix_vocab_1.py` and `extract_exercises.py` at the project root: small
  post‑hoc patch utilities (clean `nurImPlural` flag, strip
  identity‑error entries, extract grammar exercises).
