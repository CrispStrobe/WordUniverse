# voc-en Pipeline Plan & State

Last updated: 2026-05-22.

This document captures decisions and state for the **English vocabulary data
pipeline**. The project-level `/PLAN.md` covers app-side concerns (different
scope).

## Current state (as of 2026-05-22)

### Vocabulary versions
- **v24** (intermediate): 6,514 enriched + 3,486 `no_data` (misspellings as top-level entries — the legacy bug)
- **v25** (current, in production via VPS):
  - 8,125 entries total (was 10,000; reduced by removing 3,436 misspelling-headword entries that are now `commonLearnerErrors` under their correct lemmas)
  - At time of writing: 7,253 success / 61 no_data / 811 pending enrichment
  - VPS Hetzner CX22 finishing the remaining ~800 entries; ETA ~10 min

### Throughput observed
- Mac (local SSD copy): ~4 s/word post-warmup
- VPS Hetzner CX22 (4 cores, 7.6 GB RAM, all DBs on local SSD): ~1 s/word with warm cache
- Bottleneck on Mac was the 2 GB Wiktionary SQLite on slow external drive (`/Volumes/backups`, ~36 MB/s)

## Pipeline ladder

```
00_fetch_sources.py            — UK curriculum, hermitdave 50k, CMU dict, Dolch, Fry, Wikipedia misspellings
01_consolidate_en.py           — merges sources into one CSV
02_enrich_with_spacy_en.py     — POS, lemma, morphology via spaCy
03_conv_csv_to_json_en.py      — CSV → grundwortschatz_en.json
04_add_common_misspellings_en.py  — attaches Wiki misspellings ⚠ has labeling bug — see Pending
05_phoneme_enricher_en.py      — IPA + phonemes
06_generate_grapheme_variants_en.py — orthographic variants
11_reprocess_full_wikidict_en.py   — DEPRECATED: drove the Gradio Space which deadlocks
11b_enrich_local.py            — REPLACEMENT: standalone enricher (local Wiktionary SQLite + wn + local ConceptNet)
12_restructure_misspellings.py — promotes misspellings to commonLearnerErrors[] under correct lemmas  ✓ done
12_api_wins_en.py              — pending: lift API-derived plural/lemma/audio
13_*                            — pending: hand-curated POS edge cases + WordNet enrichment
14_convert_db_to_sqflite_en.py — pending: ship as assets/grundwortschatz_en.db.gz
```

## Architectural decisions (durable)

### Misspellings architecture
- Misspellings live as `commonLearnerErrors[]` under the **correct lemma's** vocab entry. They are never standalone top-level entries.
- Canonical shape: `{"error": "abondon", "source": "WIKI_MISSPELLINGS_EN"}`.
- This matches the DE pattern. Wikipedia `/For_machines` page is the authoritative source.

### Enrichment runs on VPS
- Hetzner CX22 (`168.119.190.252`, root SSH key), Falkenstein
- `/root/voc-enrich/` workspace, 4 GB DBs on local SSD
- Two screens: `enrich-vXX` (the run) + `conceptnet` (local ConceptNet Gradio Space on 127.0.0.1:7862)
- Use `11b_enrich_local.py`, NOT the WiktionaryEN Gradio Space — the latter deadlocks under SQLite cursor leakage in Gradio's queue handler.

### Why fresh connection per build_report
The shared `WIKTIONARY_CONN` in the old Gradio Space accumulates per-request cursor state. Even with `check_same_thread=False`, Python sqlite3's per-connection mutex + cursor leakage between requests block subsequent queries. `11b_enrich_local.py` opens a fresh connection per `build_report` call; <2 ms overhead.

## Misspelling sources evaluated (do not re-evaluate)

| Source | License | Pairs | Verdict |
|---|---|---|---|
| **Wikipedia /For_machines** | CC-BY-SA | 4,545 | ✅ Already in |
| **Norvig spell-errors.txt** | MIT code, CC-BY-SA upstream data | ~7k overlap | ✅ Add (~500 net-new); pending integration |
| Mitton birkbeck (BBK) | None stated; academic-only by convention | 36k | ❌ License risk + extreme noise (children's tests) |
| Mitton holbrook (BBK) | "with permission" — not commercial | 1.8k | ❌ License |
| Mitton aspell (BBK) | OK | 531 | ⚠ Subset of Norvig; skip |
| github-typo-corpus (Hagiwara) | None stated | many | ❌ Programming-domain typos; wrong audience |
| Microsoft 52418 | MS Research License (research-only) | many | ❌ No commercial |
| Kaggle fazilbtopal/misspelled-words | MIT (uploader) — provenance unverified | ~3k | ⚠ Skip — unknown provenance |
| max-mapper/common-english-errors | None (all rights reserved) | <300 useful | ❌ No license |
| **SCOWL/ESDB (en-wl/wordlist)** | MIT-like (Kevin Atkinson) | 50k+ words | ❓ Different category — regional variants, not misspellings. Separate workstream |

## Pending work (in order)

### Immediate (this session)
1. **Wait for VPS v25 enrichment to finish** (~10 min ETA). Pull v25 back to Mac.
2. **Fix labeling bug** in `00_fetch_sources.py`:
   - The Wikipedia /For_machines page format is `MISSPELLING -> CORRECT[, CORRECT2, …]`, NOT `correct->wrong` as the comment claims
   - CSV header `correct,wrong` is wrong; should be `misspelling,correct`
   - Rename `correct`/`wrongs` variables to `misspelling`/`corrects`
3. **Add Norvig spell-errors.txt fetcher** to `00_fetch_sources.py`:
   - URL: `https://norvig.com/ngrams/spell-errors.txt`
   - Format: `right: wrong1, wrong2, …` (REVERSED from Wikipedia)
   - Output: `sources/norvig_spell_errors.csv` with header `misspelling,correct`
4. **Update `04_add_common_misspellings_en.py`**:
   - Use the corrected column names
   - Merge BOTH `commonly_misspelled.csv` (Wiki) AND `norvig_spell_errors.csv` (Norvig)
   - Write `commonLearnerErrors[]` with canonical `{"error": …, "source": …}` shape
5. **Verify v25 already uses canonical shape**: it should, since `12_restructure_misspellings.py` already produced `{"error": …, "source": …}`. Just confirm.
6. **Apply Norvig misspellings to v25**: for each Norvig pair where the correct form exists in vocab, attach the misspelling under its `commonLearnerErrors[]`. Skip duplicates.
7. **Commit** with clean message.

### Next session
1. **SCOWL/ESDB integration** (new step, e.g. `12c_add_spelling_variants.py`):
   - Pull SCOWL data (Atkinson MIT-like license)
   - Identify British/American/Canadian/Australian variant pairs (color↔colour, organize↔organise)
   - Attach as `spellingVariants: [{"variant": "colour", "dialect": "british"}]` — distinct from `commonLearnerErrors` because these are VALID alternates
2. **Step 12_api_wins_en.py**: lift API-derived plural/lemma/audio
3. **Step 13_***: hand-curated POS edge cases + WordNet enrichment
4. **Step 14_convert_db_to_sqflite_en.py**: build `assets/grundwortschatz_en.db.gz`

### Known issues to address later
- **VPS workspace cleanup**: `/root/voc-enrich/` retains 4 GB (Wiktionary 2 GB + ConceptNet 1.7 GB + venv). Free with `rm -rf /root/voc-enrich/` when voc-en pipeline is done.
- **WiktionaryEN Gradio Space** (`/Volumes/backups/code/WiktionaryEN-space/`): deadlocks; kept for reference but don't use it. The official upstream cstr/WiktionaryEN Space on HF works the same way and presumably has the same deadlock on the same hardware; we haven't tested.

## Commands cheat sheet

### Monitor VPS run
```sh
ssh root@168.119.190.252 'tail -20 /root/voc-enrich/enrich_v25.log'
ssh root@168.119.190.252 'screen -r enrich-v25'   # attach (ctrl+a d to detach)
```

### Pull result file back
```sh
rsync -avz root@168.119.190.252:/root/voc-enrich/grundwortschatz_en_enriched_v25.json \
  /Users/christianstrobele/code/voc/pipeline/voc-en/
```

### Push updated script to VPS
```sh
rsync -avz /Users/christianstrobele/code/voc/pipeline/voc-en/11b_enrich_local.py \
  root@168.119.190.252:/root/voc-enrich/
```

### Re-launch enrichment on VPS
```sh
ssh root@168.119.190.252 '
  cd /root/voc-enrich
  screen -dmS enrich-vXX bash -c "source .venv/bin/activate && python3 -u 11b_enrich_local.py --input grundwortschatz_en_enriched_vXX.json 2>&1 | tee -a enrich_vXX.log; exec bash"
'
```
