# `pipeline/voc-de/` — German vocabulary build scripts

Restored from `/Volumes/backups/code/voc/lib/features/games/data/`.
**7.6 MB total.** Run the scripts from inside this directory — they
hardcode bare filenames (`Grundwortschatz1L.csv` etc), so `cwd` matters.

## Canonical pipeline (the one that built the shipped DB)

```
01_consolidate_wordlists_csv.py   →  voc_de.csv
02_enrich_with_spacy_csv.py       →  voc_de_enriched.csv
03_conv_csv_to_json.py            →  grundwortschatz.json
04_add_nrw_data.py                →  grundwortschatz_merged.json     (needs output_nested.json from conv_xls.py)
filter_voc.py                     →  grundwortschatz_safe.json       (child‑safety LLM filter; needs API keys)
03a_fix_grades.py                 →  grundwortschatz_safe_grades_fixed.json
05_phoneme_enricher.py            →  …_phonemized.json               (hardcodes /opt/homebrew espeak — patch for Linux)
06_generate_grapheme_variants.py  →  …_with_grapheme_variations.json
11_reprocess_full_wikidict.py     →  …_v24.json                      (calls cstr/WiktionaryDE — supersedes all 07_*)
08_fix_word_types.py              →  …_fixed.json
12_api_wins_3.py                  →  …_v24_consolidated.json         (use _3 only; _1/_2 corrupt genus)
13_fix_genders_manually.py        →  overwrites in place
13b_enrich_with_openthesaurus.py  →  …_v24_with_thesaurus.json       (needs openthesaurus_dump.sql)
14_convert_db_to_sqflite.py       →  grundwortschatz.db
```

See [/pipeline/PLAN.md §1](../PLAN.md#1-rebuild-the-de-db-shipped) for the
full step table with notes on what to skip, what version of each
alternate to pick, and the filename‑drift chain.

## Source files (inputs)

| File | Used by | What it is |
|---|---|---|
| `Grundwortschatz1L.csv` / `1S` / `3L` / `3S` | 01 | NRW Grundwortschatz, Klasse 1 + 3, Lang‑ + Kurzform |
| `A1.csv`/`.json`, `A2.*`, `B1.*` | 01 | CEFR sets |
| `111_NRW_Merkwörter.txt` | 01, 04 | NRW: words to memorize |
| `422_NRW_Nachdenkwörter.txt` | 01, 04 | NRW: words requiring rule reasoning |
| `100Fehler.csv` / `200Fehler.csv` / `300Fehler.csv` | 01 | Real children's misspellings |
| `400Fehler.txt` | 01 | Larger generated error set |
| `532Strategien.csv` | 01 | Spelling strategy mapping |
| `739Leo.csv` | 01 | Leo.org corpus |
| `Buchmeier20k.txt` | 01 | Children's book frequency |
| `de_50k_hermitdave.txt` | 01 | HermitDave frequency |
| `top10000de.txt`, `top10000de_unileipzig.txt` | 01 | Leipzig / generic top‑10k |
| `leeds_freq.num` | 01 | Leeds DE corpus |
| `hamburg.txt` | 01 | Hamburg list (small) |
| `wortliste-grundwortschatz-nrw.xlsx` | conv_xls.py → output_nested.json | NRW authoritative Excel |
| `YOUR_FILE.xlsx` | conv_xls.py | placeholder name (un‑renamed by historical accident) — same content as `wortliste-grundwortschatz-nrw.xlsx` |
| `output_nested.json` | 04 | Output of conv_xls.py |
| `grapheme.json` | 06 | IPA→grapheme mapping table |
| `verb_government.json` / `verb_government_hdt.json` | (Dart enricher) | UD‑derived verb government / preposition case stats |

External (must be downloaded manually):

- **OpenThesaurus dump** — https://www.openthesaurus.de/about/download
  → save as `openthesaurus_dump.sql` next to `13b_*.py`.

## Utility scripts (not in the numbered ladder)

| Script | Role |
|---|---|
| `conv_xls.py` | Excel → `output_nested.json` (run before 04) |
| `check_conflicts.py` | Diagnostic: catches NRW pedagogical words wrongly rejected by `filter_voc.py` |
| `analyze_mysql_dump.py` | Schema explorer used while writing `13b_*` |
| `extract.py`, `extract_ud.py`, `enrich_ud.py` | UD German treebank → `verb_government*.json` |
| `frequencies.py`, `word_types.py`, `fix_json.py` | One‑off diagnostics |
| `test_google_api.py`, `test_grecy.py`, `test_phonemizer.py` | Experiments (probably TTS / Greek spaCy / phonemizer probe) |
| `inflection_enricher.dart` | Old (V21) Dart‑side enricher — replaced by `11_reprocess_full_wikidict.py` |

## VPS‑side scripts

These ran on `91.107.213.126` (VPS_2) and `135.181.205.133` (VPS_3 suspected), not locally:

- `wikt-en.sh` — full EN Wiktionary extraction (`enwiktionary-latest-pages-articles.xml.bz2` → `wiktextract` → `cstr/en-wiktionary-extracted-all`). Multi‑hour CPU job.
- `norm_all_6_en.py` — turns the raw JSONL into the normalized SQLite (`cstr/en-wiktionary-sqlite-all`). ~30 tables.
- `normalize_wiktionary.py` — the DE equivalent (raw JSONL → `cstr/de-wiktionary-sqlite-full`).

Keep them here because they're part of the same pipeline story, but
don't try to run them on a laptop — see
[/pipeline/HISTORY.md §2025‑11‑08](../HISTORY.md#2025-11-08--de-wiktionary-pipeline-starts-on-vps_2)
for the VPS bash‑history details and
[/pipeline/LEARNINGS.md §14](../LEARNINGS.md#14-the-mythical-do-it-on-the-laptop-estimate-is-always-wrong)
for why.

## `archive/` — superseded files

Kept for git‑style lineage; **don't run these**:

- `*_old.py` — predecessors of `01`, `conv_to_json`, `enrich`,
  `phoneme_enricher`, `generate_grapheme_variants`.
- `consolidate.py`, `cons5.py`, `cons5a.py` — early drafts of `01`.
- `voc_de_old.csv`, `voc_de_enriched_old.csv` — earlier‑run outputs.
- `readme_pipeline.STALE.md` — the 2025‑10 3‑step description that was
  obsolete by 2025‑11‑19 (it describes voc_de.csv → enriched → JSON →
  inflection_enricher, ignoring all of 04 through 14). Kept so future
  readers see what *not* to follow.

## Iterations that are NOT in `archive/`

The following alternate versions stay at top level because PLAN.md
references them by name when explaining the ship‑path:

- `07_enrich_wikt.py` (V22), `07_enrich_hf.py`, `07_enrich_hf_with_hyphenation.py` (V23) — all superseded by `11_reprocess_full_wikidict.py` (V24 superset). Kept for historical reference.
- `10_only_english.py` (operates on V23), `10_english_only_2.py` (operates on V24 — use this).
- `12_api_wins.py`, `12_api_wins_2.py`, `12_api_wins_3.py` — **`_3` is the ship version.** `_1` and `_2` would corrupt genus.
- `09_build_db.py` — first‑pass SQLite builder used for diagnostics; final ship‑DB comes from `14_convert_db_to_sqflite.py`.

## Intermediate outputs left in place

`voc_de.csv`, `voc_de_enriched.csv`, `voc_de_phonemized.csv`,
`data.json`, `output_nested.json`,
`grundwortschatz_safe_removed.txt` — kept as **reference snapshots**
from the last successful build. A fresh run will overwrite them; keep
them in version control nonetheless so changes show as a diff.

## Run‑order tldr

```sh
cd pipeline/voc-de
python conv_xls.py                      # excel → output_nested.json (run once)
python 01_consolidate_wordlists_csv.py  # → voc_de.csv
python 02_enrich_with_spacy_csv.py      # → voc_de_enriched.csv
python 03_conv_csv_to_json.py           # → grundwortschatz.json
python 04_add_nrw_data.py               # → grundwortschatz_merged.json
python filter_voc.py grundwortschatz_merged.json grundwortschatz_safe.json
python 03a_fix_grades.py                # → …_grades_fixed.json
python 05_phoneme_enricher.py
python 06_generate_grapheme_variants.py
python 11_reprocess_full_wikidict.py    # ← slow; warm cstr/WiktionaryDE first
python 08_fix_word_types.py
python 12_api_wins_3.py                 # ← USE _3
python 13_fix_genders_manually.py
# Download openthesaurus_dump.sql first
python 13b_enrich_with_openthesaurus.py
python 14_convert_db_to_sqflite.py      # → grundwortschatz.db
gzip -9 grundwortschatz.db -c > ../../assets/grundwortschatz.db.gz
```

You'll be **renaming files between steps** (see PLAN.md §1
filename‑drift caveat). Total: ~3–8 h end‑to‑end on a laptop.
