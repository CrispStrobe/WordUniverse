# HISTORY — voc-en pipeline

Chronological record of the English vocabulary DB build. Active plan lives in
`PLAN.md`; project-level history lives in `../HISTORY.md`.

---

## 2026-05-21/22 — EN DB v1 shipped (7,878 lemmas, 8.6 MB)

Built via `11b_enrich_local.py` on Hetzner VPS (`168.119.190.252`, CX22,
4 cores / 7.6 GB RAM, all DBs on local SSD). Wall time: 2,458 s for the
enrichment run. Shipped as `assets/grundwortschatz_en.db.gz`.

### Final stats (shipped DB)

- **7,878 lemmas** (started from 10,000; reduced by folding 3,436
  misspelling-headword entries and 217 Wiktionary-marker entries into their
  correct lemmas)
- **8,062 / 7,878 success (99.2 %) — 63 no_data — 0 errors**
- **27,363 misspelling annotations** on 4,653 entries (59 % coverage)
  - Norvig-sourced: 22,157 (81 %)
  - Wikipedia-sourced: 5,206 (19 %)
- **270 dialect variants** (UK ↔ US spellings) on 157 entries
- **25,659 WordNet sense records** (OEWN) on 5,509 entries (70 %)
- 99 historical-form entries retained (`historical=True`)
- 208 uncoupled variants (`uncoupledVariant=True` — target lemma not in vocab)
- Top spelling traps by annotation count: `miscellaneous` (226), `beautiful`
  (181), `enthusiasm` (158), `guarantee`/`prejudice` (154), `immediately`
  (142), `pamphlet` (115)

### Commits

`b25dc05`, `2683458`, `1ecc8f0`, `bd36304`, `01155b3`, `4bd85dc`, `43899fa`

### Step-by-step record

1. **Wait for VPS v25 enrichment** — completed in 41 min (1,548 success / 63 no_data).
2. **Fix Wikipedia labeling bug** — renamed CSV columns to `misspelling,correct`.
3. **Add Norvig spell-errors.txt fetcher** — committed, fetches 38k pairs
   (MIT code, CC-BY-SA upstream data).
4. **Update `04_add_common_misspellings_en.py`** — dual-source (Norvig + Wikipedia),
   inflection-aware lookup, canonical shape `{"error": "...", "source": "..."}`.
5. **Apply Norvig to v25** — 24,801 new annotations attached, 837 legacy
   entries migrated.
6. **Build shipped DB v25** — `assets/grundwortschatz_en.db.gz` regenerated
   (6.2 MB, was 1.1 MB).
7. **Step 12_api_wins** — 3,291 wordType fixes, 6,966 audio paths, 7,088
   inflection arrays, 12,213 promoted-field updates. Output:
   `grundwortschatz_en_enriched_v25_consolidated.json`. Shipped DB → 6.5 MB.
8. **Step 12c — SCOWL/regional variants** — 264 American/British spelling
   variants attached across 150 entries (`color↔colour`, `organise↔organize`,
   `centre↔center`, etc.). Source: `vg/spelling-uk-vs-us` (MIT + CC-BY-4.0).
   Variants live under `spellingVariants[]` with `dialect: american|british`,
   distinct from `commonLearnerErrors[]`.
9. **Step 12d — fold Wiktionary-marker variants** — 217 misspelling-headword
   entries (`recieve`, `accomodate`, `absense`, `organize`, etc.) folded under
   their correct lemmas based on Wiktionary's "Misspelling of X" / "Alternative
   form of X" / "Obsolete form of X" marker phrases. 99 historical-form entries
   kept with `historical=True`. 202 left as `uncoupledVariant=True` (target not
   in vocab). Vocab: 8,125 → 7,908.
10. **Bug fixes (random audit)**:
    - Two-/three-pass inflection-aware index in steps 04, 12c, 12d (`word` >
      `lemma`/`primary_lemma` > inflections). Previously `idx['receive']` could
      point at `received`.
    - Step 04 filters dialect-variant pairs (`color/colour`) out of
      misspelling attachment — they live in `spellingVariants` (step 12c).
    - Step 04 preflight clears legacy `{wrong:X}` CLE entries on entries whose
      word is itself a known misspelling.
    - Step 12d single-word-def heuristic requires `often_misspelled` tag AND
      ≤2 total defs to avoid folding words like `with` under `against`.
11. **12d marker-pattern expansion (2nd audit pass)** — Added:
    `pronunciation spelling of X` (catches `comin`, `doin`, `dunno`, `fella`);
    `alternative letter-case form of X`; `US/UK/Commonwealth/Non-Oxford
    standard spelling of X` (`favorites`, `criticised`, `apologise`, `jewelry`,
    `manoeuvred`, `grey`); `Synonym of X` (only when ≤1 def or `often_misspelled`
    tag). 30 more entries folded → 7,908 → 7,878.
12. **Step 13 — WordNet expansion (OEWN)** — for 5,509 lemmas, added full
    per-synset sense records across all POS: `wordnetSenses[]` with pos,
    definition, synonyms, antonyms, hypernyms, hyponyms, holonyms, meronyms,
    plus 2-level hypernym chain. Merged into top-level fields: 13,506 new defs
    (dedup, capped 8/entry), 11,570 new synonyms, 360 new antonyms, 37,483 new
    hypernyms. Step 14 schema updated to ship `wordnetSenses[]` in
    `enrichment_json`.
13. **Final DB build** — `assets/grundwortschatz_en.db.gz` = 8.6 MB.

---

## 2026-05-24 — Post-enrichment pipeline (word stats, curriculum, grade fill)

New enrichment scripts written and run on `grundwortschatz_en.db` (7,878 entries):

14. **`add_gutenberg_examples_en.py`** — 72 pre-1928 EN PD books (Carroll, Twain,
    Stevenson, Alcott, Burnett, Nesbit, Montgomery, Kipling, Barrie, Baum,
    Grahame, Potter, MacDonald, Lang, Defoe, Swift, Sewell, et al.);
    4,305 entries enriched (54.6%), 50,030 sentences total.
    Corpus cached at `sources/gutenberg_corpus_en.db`.

15. **`add_wordfreq_en.py`** — All 7,878 entries tagged with `frequency_json`
    `{"zipf": float, "per_million": float, "frequency_band": 1-5}`.
    Uses wordfreq (Apache-2.0 + CC-BY-SA 4.0). Takes max(word, lemma) Zipf.
    Band distribution: B1=122, B2=816, B3=3207, B4=2627, B5=1106.

16. **`add_cefr_en.py`** — CEFR-J v1.5 (Tono & Negishi, TUFS; CC-BY-SA 4.0).
    3,223 entries tagged: A1=819, A2=757, B1=987, B2=660.
    Handles slash-variants (`a.m./A.M./am/AM`). CSV cached locally.

17. **`add_curriculum_en.py`** — Cambridge YLE Starters/Movers/Flyers word lists
    + DE Grundschule 3-4 English curriculum target vocabulary. All factual
    word lists (not copyrightable). 715 YLE + 237 DE curriculum matches.
    Tags: `yle_level` in `metadata_json`, `source:cambridge_yle_*` + `source:de_curriculum_en`.

18. **`add_uk_curriculum.py`** — UK DfE statutory word lists (OGL v3):
    Y1-Y2=122, Y3-Y4=100, Y5-Y6=96 matches.
    Also computes `gradeLevelEstimate` (1-6) for all 7,878 entries via
    decision tree: curriculum/CEFR cap vs. frequency baseline, min wins.
    Result distribution: 1=122, 2=1154, 3=2996, 4=250, 5=2262, 6=1094.

19. **`add_llm_examples_en.py --grade`** — running (PID 91617); checkpoint
    at `grade_results_en.jsonl`; 3,338/7,878 done at last check (~42%).
    3-word batches, ~10-25/min, 5-provider round-robin (Groq 70%, Mistral 25%,
    Nebius/Scaleway 5%; Cerebras disabled). Kill/restart safe.

### DB expansion (2026-05-24, same session)

20. **`add_missing_curriculum_en.py`** — Identified 3,661 CEFR-J/YLE/UK words absent
    from the 7,878-entry DB (hermit_dave's list skews toward unusual/hard words,
    not everyday vocabulary). Inserted with `enrichment_status='minimal'`.
    DB grew 7,878 → **11,539 entries**.
    Reran steps 15–18 with `--overwrite` on full 11,539-entry DB:
    - `frequency_json`: all 11,539 — band dist: 1=124, 2=922, 3=4424, 4=4439, 5=1630
    - `cefr_level`: 6,879 tagged (A1=1076, A2=1229, B1=2120, B2=2454)
    - YLE: Starters=216, Movers=324, Flyers=293; DE curriculum: 317
    - `gradeLevelEstimate`: all 11,539 — dist: 1=139, 2=1494, 3=4218, 4=896, 5=3698, 6=1094
    - Restarted grade fill as PID 9034 (JSONL checkpoint preserved)

21. **`enrich_minimal_en.py`** (new) — Local Wiktionary enrichment for the
    3,661 `enrichment_status='minimal'` entries. Queries
    `/Volumes/backups/code/WiktionaryEN-space/en_wiktionary_normalized.db`
    directly (1.9 GB, 1.4M EN entries). Fills definitions, inflections,
    pronunciation, examples, hyphenation. Preserves tags/sources/commonLearnerErrors.
    No OEWN (module not installed at time of writing — `wn` installed later).
    4 workers, JSONL checkpoint at `/tmp/dbpatch_wikt_minimal_en/`.

22. **`add_oewn_en.py`** (new) — SQLite-native OEWN sense expansion targeting
    entries with empty `wordnetSenses`. Covers:
    - 2,306 original entries where step 13 (JSON-based) found no OEWN senses
    - 3,661 new entries post-Wiktionary enrichment
    Runs single-threaded (wn shares a SQLite connection internally).
    ~600 lookups/s; 6k entries ≈ 10 s. `wn` installed, `oewn:2024` downloaded.

23. **`add_uk_curriculum.py` — `grade_level` sync** — Updated UPDATE statement to
    also write `grade_level = gradeLevelEstimate` (was metadata_json only).
    Fixes badly miscalibrated `grade_level` column (was grade 7 / all-1s from
    original hermit_dave CSV). Takes effect on next `--grade-only` run.

24. **Dart fixes** (2026-05-24):
    - `dictionary_database_service.dart`: injects `grade_examples` and
      `gutenberg_examples` from `metadata_json` into `apiEnrichment` dict before
      `ApiEnrichment.fromJson` — they were always null before because
      `ApiEnrichment.fromJson` read from `enrichment_json` (wrong column).
    - `vocabulary_models.dart`: added `gradeExamples`, `gutenbergExamples` to
      `ApiEnrichment`; added `gradeLevelEstimate`, `cefrLevel` to `GermanWord`.
    - `custom_licenses_registry.dart`: removed Menzel 1985 license entry (not
      used in EN pipeline); added DysList (MIT, Rauschii et al. 2014) for DE
      dyslexia error corpus.

### `build_en_enrichment.sh` (full pipeline, idempotent, updated 2026-05-24)

Steps 15a→15h → grade (×N passes) → check-all → compress:

```
15a: add_missing_curriculum_en.py    ← MUST be first
15b: add_wordfreq_en.py
15c: add_cefr_en.py
15d: add_curriculum_en.py
15e: add_uk_curriculum.py            ← now also syncs grade_level column
15f: add_gutenberg_examples_en.py    ← skip with --no-gutenberg
15g: enrich_minimal_en.py            ← skip with --no-wikt-enrich
15h: add_oewn_en.py                  ← skip with --no-oewn
16+: add_llm_examples_en.py --grade (×PASSES) → --check-all
final: compress → assets/grundwortschatz_en.db.gz
```

### Architectural decisions (locked in 2026-05-21)

| Decision | Value | Rationale |
|---|---|---|
| Canonical English variant | **UK English** | Aligns with UK Year 1–6 statutory spelling lists. US spellings carried as `commonLearnerErrors`. |
| Vocabulary size | **10k, filterable** | Match DE size. Words tagged so app can show 3k / 5k / 10k subsets. |
| Grade mapping | **UK Y1–6 primary**, CEFR + AoA-Kuperman fallback | UK Year is pedagogical primary (same role as NRW Grundwortschatz for DE). All three carried as tags. |
| Reverse translations | **Yes, where available** | DE speakers learning EN is the primary use case. |
| App shape | **Single app, both DBs bundled**, L2L × GUI matrix | L2L picker in Settings; game menu filters by `supportedL2L`. |

### Misspelling sources evaluated (do not re-evaluate)

| Source | License | Verdict |
|---|---|---|
| **Wikipedia /For_machines** | CC-BY-SA | ✅ In shipped DB |
| **Norvig spell-errors.txt** | MIT code, CC-BY-SA upstream | ✅ In shipped DB |
| Mitton birkbeck (BBK) | None stated; academic-only | ❌ License risk + extreme noise |
| Mitton holbrook (BBK) | "with permission" — not commercial | ❌ License |
| Mitton aspell (BBK) | OK | ⚠ Subset of Norvig; skip |
| github-typo-corpus (Hagiwara) | None stated | ❌ Programming-domain typos |
| Microsoft 52418 | MS Research License (research-only) | ❌ No commercial |
| Kaggle fazilbtopal/misspelled-words | MIT (uploader) — provenance unverified | ⚠ Skip |
| max-mapper/common-english-errors | None (all rights reserved) | ❌ No license |
| **SCOWL/ESDB (en-wl/wordlist)** | MIT-like (Kevin Atkinson) | ✅ Used for dialect variants (step 12c) |

### Infrastructure note

- VPS: Hetzner CX22, `168.119.190.252`, `/root/voc-enrich/` workspace
- Used `11b_enrich_local.py`, NOT the WiktionaryEN Gradio Space (deadlocks
  under SQLite cursor leakage in Gradio's queue handler)
- Two screens: `enrich-vXX` (the run) + `conceptnet` (local ConceptNet Gradio
  Space on `127.0.0.1:7862`)
