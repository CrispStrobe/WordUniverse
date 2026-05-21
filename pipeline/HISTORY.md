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
`hf_REDACTED_ROTATED_TOKEN`. Rotate it (see LEARNINGS.md).

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
