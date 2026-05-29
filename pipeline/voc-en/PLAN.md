# voc-en Pipeline Plan & State

Last updated: 2026-05-26.

## Current DB state ✅ COMPLETE

| Field | Value |
|---|---|
| File | `pipeline/voc-en/grundwortschatz_en.db` |
| Asset | `assets/grundwortschatz_en.db.gz` — **~18 MB** (includes `phrasal_verbs` table, 2026-05-29) |
| Entries | **11,539** words (7,815 success + 3,658 minimal→enriched + 66 no_data) + 400 phrasal verbs |
| `enrichment_status='minimal'` | **0** — all enriched via VPS run 2026-05-26 |
| `definitions` | 11,486 (99%) |
| `grade_examples` | 11,481 (99%) |
| `gutenberg_examples` | 6,274 (54%) |
| `wordnetSenses` | 9,186 (79%) |
| `grade_level` column | ✅ synced from `gradeLevelEstimate` |

## Key schema notes

- Table: `words` (not `vocabulary`)
- `grade_examples`, `gutenberg_examples`, `gradeLevelEstimate`, `cefr_level` → **`metadata_json`**
- Wiktionary enrichment, `wordnetSenses`, `commonLearnerErrors`, `spellingVariants` → **`enrichment_json`**
- Dart: `dictionary_database_service.dart` injects `grade_examples`/`gutenberg_examples` from `metadata_json` into `apiEnrichment` dict before `ApiEnrichment.fromJson` (fixed 2026-05-24)

## Enrichment pipeline — completed steps (chronological)

```
15a: add_missing_curriculum_en.py     ✅ +3,661 minimal entries
15b: add_wordfreq_en.py               ✅ frequency_json all 11,539
15c: add_cefr_en.py                   ✅ 6,879 CEFR-J tags
15d: add_curriculum_en.py             ✅ YLE + DE curriculum tags
15e: add_uk_curriculum.py             ✅ UK Y1-Y6 + gradeLevelEstimate + grade_level
15f: add_gutenberg_examples_en.py     ✅ 6,274 entries (72 books)
15g: enrich_minimal_en.py             ✅ 3,658 entries — run on VPS 168.119.190.252 (NVMe, 1.4/s)
15h: add_oewn_en.py                   ✅ 9,186 OEWN senses
15i: add_llm_examples_en.py --grade   ✅ 11,481/11,539 (99%)
15j: add_llm_examples_en.py --check-all ✅ 10,692 corrected
```

## Pipeline scripts (all idempotent)

| Script | What it does | Output field |
|---|---|---|
| `add_missing_curriculum_en.py` | Insert CEFR-J A1-B2 / YLE / UK words absent from DB — **run first** | new rows, `enrichment_status='minimal'` |
| `add_wordfreq_en.py` | wordfreq Zipf/per_million/band | `frequency_json` |
| `add_cefr_en.py` | CEFR-J v1.5 level tags (auto-downloads CSV) | `metadata_json.cefr_level` |
| `add_curriculum_en.py` | Cambridge YLE + DE Grundschule tags | `metadata_json.yle_level`, tags |
| `add_uk_curriculum.py` | UK DfE Y1-Y6 tags + gradeLevelEstimate + **syncs `grade_level` column** | `metadata_json.gradeLevelEstimate`, `grade_level` |
| `add_gutenberg_examples_en.py` | EN Gutenberg sentences (72 books, ~50k sentences; books cached in `sources/gutenberg_en/`) | `metadata_json.gutenberg_examples` |
| `enrich_minimal_en.py` | Wiktionary definitions/inflections/pronunciation for `minimal` entries; 4 workers; JSONL checkpoint at `/tmp/dbpatch_wikt_minimal_en/` | `enrichment_json.*`, status→success/no_data |
| `add_oewn_en.py` | OEWN sense expansion for entries with empty `wordnetSenses`; single-threaded (~600/s) | `enrichment_json.wordnetSenses` |
| `add_llm_examples_en.py --grade` | LLM grade-differentiated example sentences; JSONL checkpoint `grade_results_en.jsonl` | `metadata_json.grade_examples` |
| `add_llm_examples_en.py --check-all` | Fix partial/empty grade entries | `metadata_json.grade_examples` |

## LLM enrichment notes (for re-runs)

- Exclude Groq/Cohere: `env GROQ_API_KEY="" COHERE_API_KEY=""` — both produce truncated/malformed JSON
- `response_format={"type":"json_object"}` added to `llm.call()` for `mode=="fill"` — fixes Llama-3.3-70B `}}}` bug
- GRADE_BATCH=1 (EN script) — keeps JSON output small enough for Nemo/Nemo-equivalent models
- Checkpoint pattern: kill anytime, restart from same dir — JSONL is the source of truth

## `enrich_minimal_en.py` — VPS run

Local external drive (USB HDD): 0.1/s — 16h ETA — not viable.
VPS `168.119.190.252`: 1.4/s on NVMe — completed in 27 min.

```bash
# Upload (one-time)
scp enrich_minimal_en.py grundwortschatz_en.db root@168.119.190.252:/root/voc-enrich/voc-en-minimal/
scp /tmp/dbpatch_wikt_minimal_en/wikt_minimal_results.jsonl root@168.119.190.252:/tmp/dbpatch_wikt_minimal_en/
# Edit WIKT_DB_PATH → /root/voc-enrich/en_wiktionary_normalized_all.db on VPS

# Run
ssh root@168.119.190.252 "cd /root/voc-enrich/voc-en-minimal && nohup python3 enrich_minimal_en.py --db grundwortschatz_en.db --workers 4 --no-compress > /tmp/enrich_minimal_vps.log 2>&1 &"

# Download
scp root@168.119.190.252:/root/voc-enrich/voc-en-minimal/grundwortschatz_en.db .
```

## Game UI — DONE

- [x] L2L (language-to-learn) picker in Settings; menu filters by `supportedLearningLanguages`
- [x] `großschreib` / `großstadt` etc. hidden for `L2L=en` (DE-only)
- [x] EN-only games shipped:
  - `homophone_drill` + `confusable_drill` (hardcoded catalogue)
  - **`phrasal_verb_power` (#46)** + **`phrasal_verb_match` (#47)** — backed by the
    `phrasal_verbs` table (see `add_phrasal_verbs_en.py` + HISTORY 2026-05-29).
    398/400 LLM-graded, content-filtered for K-6, deduped.
- [x] ARB strings (EN+DE) for all new game labels + L2L picker
</content>
</invoke>