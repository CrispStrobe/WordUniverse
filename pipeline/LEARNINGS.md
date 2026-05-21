# LEARNINGS — pitfalls from the voc-de + ConceptNet build, things to do differently

These are lessons the retrace surfaced. They're framed as advice for the
EN port and the all‑languages ConceptNet rebuild, but most generalize to
any data pipeline that mixes laptop, VPS, and HF Space work.

---

## 1. Keep build scripts out of `lib/`

**What happened:** the 14 numbered pipeline scripts originally lived in
`lib/features/games/data/`. Commit `8364f26` *("fix: responsive ui and
compress database")* deleted that whole directory to shrink the Flutter
bundle. The scripts only survived because of the `/Volumes/backups/code/`
snapshot.

**Lesson:** build inputs, build outputs, and build scripts do not belong
under `lib/` — Flutter packages everything under `lib/` into the app
bundle, so anything you don't ship is wasted bytes and pressure to delete.
Put pipeline code in a sibling top‑level directory (`pipeline/`,
`build_tools/`, etc.) and add an explicit `.gitattributes` `export-ignore`
if you ship via `git archive`. This repo's new home for them is
[/pipeline/](.).

---

## 2. Name files by step number, not version

**What happened:** the file‑rename chain looked like

```
grundwortschatz.json
  → grundwortschatz_safe.json
  → grundwortschatz_safe_enriched_v22a.json
  → grundwortschatz_safe_enriched_v23.json
  → grundwortschatz_safe_enriched_v24.json
  → grundwortschatz_v24_consolidated.json
  → grundwortschatz_v24_with_thesaurus.json
  → grundwortschatz.db
```

Scripts do **not** rename outputs to match the next step's hardcoded input
filename. You have to manually rename between steps. The version suffixes
encoded *implementation history* (v22a, v23, v24) rather than *pipeline
position*. A reader can't tell from a filename whether the file is the
input or output of step 11.

**Lesson:** name intermediates by their *position* in the pipeline:

```
00_raw.csv
01_consolidated.csv
02_spacy_enriched.csv
03_json.json
04_nrw_merged.json
05_safety_filtered.json
06_phonemized.json
07_grapheme_variants.json
08_api_enriched.json
09_word_types_fixed.json
10_translations_pruned.json
11_v24_enriched.json
12_api_wins_applied.json
13_genders_corrected.json
13b_openthesaurus.json
14_ready_for_db.json
```

Each script writes the next number; readers know exactly where they are.

---

## 3. Version your build scripts in‑repo, even if they run remotely

**What happened:** the script that turned `cstr/conceptnet-de-indexed.db`
(23.6 GB) → `cstr/conceptnet-normalized-multi/conceptnet_normalized.db`
(1.78 GB, 11 langs) is **gone**. Best guess: it ran in `/tmp` on VPS_3,
was never `rsync`'d back, and was lost when the tmp dir got cleared.

We have the inputs (still on HF), the runtime (in the Gradio Space), and
the schema (inferred from the runtime), so a rebuild is feasible. But it
cost a couple hours of forensics. If the runtime hadn't also encoded the
schema implicitly, the loss would have been total.

**Lesson:** the build step lives in the same repo as the runtime, even if
the build is run on a different machine. `git push` after every
non‑trivial change. For the next ConceptNet rebuild, the script lands in
`pipeline/conceptnet/build_normalized.py`, gets a docstring with the
expected runtime/RAM/disk, and a log of `time` output + commit SHA goes
into `pipeline/conceptnet/runs/YYYY-MM-DD.log`.

---

## 4. Don't expose secrets in shell history

**What happened:** on VPS_2, the wiktionary extraction was kicked off via

```sh
export HF_USERNAME="cstr"
export HF_TOKEN="hf_JOPe...EaN"
./run_wiktionary_extract.sh
```

That left the token in plaintext in `/root/.bash_history`, where the VPS
audit found it. Anyone with read access to that file (compromise, backup
exfiltration, screen‑share, etc.) gets the token.

**Lesson:**

- Don't `export` secrets in interactive shells. Use a file: HF CLI reads
  `~/.config/huggingface/token` by default; `chmod 600` it.
- If you must use env vars, prefix the command:
  `HF_TOKEN=$(cat ~/.hf.token) ./run.sh` — then the literal value never
  hits history.
- Or disable history during the session: `set +o history` first.
- Treat any tokens that *might* have leaked as compromised. Rotate.
  See PLAN.md §4.1.

---

## 5. For data pipelines, prefer downloaded snapshots over live APIs

**What happened:** on 2025‑11‑06 we tried to enrich vocabulary via
`api.conceptnet.io`. Every request returned 502. Wasted half a day before
pivoting to a local SQLite mirror (`ysenarath/conceptnet-sqlite`).

**Lesson:** if your pipeline is going to call an external service for
every word in a 10k vocab, get a snapshot of the underlying data first.
ConceptNet, Wiktionary, WordNet, OpenThesaurus — all of these publish
dumps. Live APIs are for ad‑hoc queries and for users; build pipelines
need reproducibility, and reproducibility means a frozen snapshot you can
re‑run against.

The HF dataset pattern we ended up using (`cstr/de-wiktionary-extracted`,
`cstr/conceptnet-de-indexed`) is exactly this — and it's free
infrastructure. Push the snapshot, version it with `revision=`, and your
build is reproducible across machines.

---

## 6. Filename‑naming the alternates is a footgun

**What happened:** the backup folder has

- `07_enrich_hf.py` *and* `07_enrich_hf_with_hyphenation.py` *and*
  `07_enrich_wikt.py`
- `10_only_english.py` *and* `10_english_only_2.py`
- `12_api_wins.py` *and* `_2.py` *and* `_3.py`
- `01_consolidate_wordlists_csv.py` *and* `_old.py`
- many `*_old.py` files

The user's actual ship‑path uses `12_api_wins_3.py` and skips 07 entirely
(11 is a superset of 07). Nothing in the filenames tells you that.

**Lesson:** when iterating, *rename forward* — delete or `mv` to
`archive/` instead of leaving `_2`, `_3`, `_old` clutter:

```
pipeline/voc-de/
├── 12_api_wins.py              # the current one
├── archive/
│   ├── 12_api_wins.v1.py        # earlier
│   └── 12_api_wins.v2.py
```

Or use git: each iteration is a commit, `git log -p` shows the history.
You don't need filename history if you have git history.

---

## 7. Hardcoded macOS paths break reproducibility

**What happened:** `05_phoneme_enricher.py` hardcodes
`/opt/homebrew/lib/libespeak-ng.dylib`. On Linux that's not a path, on
Intel macOS the prefix is `/usr/local`. The script is silently
unportable.

**Lesson:** env‑sensitive paths come from a config file or env var, never
inlined. For espeak specifically, prefer the `EspeakWrapper.set_library`
fallback chain or `os.environ.get('PHONEMIZER_ESPEAK_LIBRARY')`.

---

## 8. "API wins" is the right default for enrichment merges

**What happened:** when an API returns data that conflicts with locally
derived data (genus from the article column vs genus from spaCy vs genus
from Wiktionary), the question is which one wins. `12_api_wins_3.py`
ended up with this rule:

- **Empty local field, API has data:** fill from API.
- **Non‑empty local field, API agrees:** no‑op.
- **Non‑empty local field, API disagrees:** **keep local, log the
  conflict** to `12_conflicts.log`.

We then ran `13_fix_genders_manually.py` to review the conflict log and
hand‑correct ~95 genders.

**Lesson:** this is the right pattern. Don't blindly overwrite local data
with API data — APIs make mistakes too, especially Wiktionary on rare
inflected forms. Conflicts are signal, not noise. Log them, review them
in a second pass.

For EN: same pattern. Keep `12_api_wins_en.py` conservative, log a
`12_conflicts_en.log`, expect a `13_fix_word_types_manually.py` pass.

---

## 9. The "child‑safety filter" is a real step, not optional

**What happened:** `filter_voc.py` runs an LLM (Groq/Together/OpenRouter
fallback) over every candidate word and rejects vulgar/inappropriate
ones. The output is `grundwortschatz_safe.json`. Without this step, the
frequency‑based wordlists (especially `de_50k_hermitdave.txt` derived
from subtitle corpora) include slurs, body parts, and other content
unsuitable for a primary‑school audience.

`check_conflicts.py` catches the inverse: pedagogical NRW words that the
profanity filter wrongly rejected (false positives). Both passes are
needed.

**Lesson:** for any kids' learning app, budget for a safety filter as a
first‑class pipeline step. Don't underestimate the volume — DE rejected
~3% of candidate words; EN frequency corpora (SUBTLEX‑US is from movie
subtitles, which contain plenty of strong language) will reject closer
to 5–8%.

---

## 10. HF Spaces sleep — warm before you batch

**What happened:** the V24 reprocess (step 11) calls
`cstr/WiktionaryDE /analyze_word` ~10k times. On the first request after
the Space has been idle for >24 h, the container takes 30–60 s to wake.
If your loop has no per‑request timeout retries, you lose the first
batch.

**Lesson:** before a big batch:

```python
# warmup ping
client = Client("cstr/WiktionaryDE")
client.predict("Hund", api_name="/analyze_word")  # discard result
```

And give each call a generous timeout + retry: 30 s connect, 60 s read,
3 retries with exponential backoff. The Space itself is reliable once
warm; the cold start is the only failure mode worth coding around.

For EN, `cstr/WiktionaryEN` was RUNNING at audit time, but the same
caveat applies after any sleep.

---

## 11. Match the schema across languages from day one

**What happened:** the DE schema has `article` (`der`/`die`/`das`) and
`genus` (`Masculine`/`Feminine`/`Neuter`) columns that are meaningless
for EN. We have to decide whether to drop, nullify, or repurpose them
before EN ships. Late schema decisions are migration headaches.

**Lesson:** the schema should be *language‑agnostic* from v1, even if
only DE uses every column. Concretely:

- `article` — nullable. EN uses `a`/`an`/`the`. FR will use `le`/`la`.
- `genus` — nullable. EN/JA/KO/TR set NULL. FR/IT/ES use it.
- `word_type` — canonicalize to a fixed English vocabulary
  (`noun`/`verb`/`adjective`/...). DE currently stores
  `substantiv`/`adjektiv`; translate at build time (step 14) and keep
  the original under `metadata.original_word_type`.

This is the decision the EN port forces us to confront and it's better
to do once than thrice.

---

## 12. Stale READMEs are worse than no README

**What happened:** `readme_pipeline.md` in the backup describes a
3‑step pipeline (enrich → JSON → inflection_enricher.dart). The actual
pipeline is 14 steps. A reader following the README would build a
2025‑10 vintage DB without any of the V24 enrichment, the safety
filter, the OpenThesaurus integration, or the NRW spelling data.

**Lesson:** kill READMEs that lose currency. If you can't keep a README
in sync, delete it and let people grep the directory. Or — better —
keep the README as a table of contents to scripts, not a reproduction
of their docstrings. The script docstrings are closer to the code and
update with it; the README has no such gravity.

This repo's [PLAN.md](PLAN.md) is structured to *index* the scripts, not
to mirror them. If a script's behavior changes, you only have to update
its docstring; PLAN.md still points to the right file.

---

## 13. The HF dataset is your real artifact, not the local DB

**What happened:** users of `cstr/WiktionaryDE` query
`cstr/de-wiktionary-sqlite-full`, not your laptop's copy. Users of
`cstr/conceptnet_normalized` query `cstr/conceptnet-normalized-multi`.
The voc app ships `assets/grundwortschatz.db.gz`. Three artifacts, three
HF repos, three release surfaces.

**Lesson:** for each artifact: (a) the HF repo name is part of the
contract — don't rename casually; (b) bump revisions explicitly
(`revision="v2"` rather than overwriting `main`); (c) keep the build
script + a build log alongside the artifact (committed in‑repo, *and*
uploaded to the HF repo's `build/` folder for self‑containment).

For the all‑languages ConceptNet rebuild, this means
`cstr/conceptnet-normalized-all` gets `conceptnet_normalized_all.db` +
`build_normalized_all.py` + `README.md` + `build.log`. Self‑documenting.

---

## 14. The mythical "do it on the laptop" estimate is always wrong

**What happened:** the wiktionary dump was ~1.2 GB compressed, ~10 GB
uncompressed, with `wiktextract` processing taking ~3 h on the VPS.
There's no world where you'd want to run that on a MacBook (battery,
heat, network drops). Same with the conceptnet 23.6 GB → 1.78 GB
normalize.

**Lesson:** when a step needs >2 GB of RAM, >30 GB of disk, or >2 h of
wall time, it's a VPS step. Plan for it: spin up a Hetzner box ($5 buys
you 4 GB / 80 GB), `rsync` the inputs, run, `rsync` the outputs back,
commit. This is what VPS_2 was for; the only mistake was leaving the
script there instead of in the repo.

---

## 15. Multi‑source consolidation = multi‑source tag carriage

**What happened:** DE words got assigned a `gradeLevel` 1–6 from
overlapping sources (NRW1, NRW3, NRW111, NRW422, A1, A2, B1, Leo, …).
The grade is a single integer in the DB. We lose the information about
*which* source it came from after step 03a.

**Lesson:** carry source tags forward. EN will do this from the start
(see PLAN.md §2 — `tags`, `cefr`, `uk_year`, `aoa_kuperman` all
co‑exist). The benefit: future product asks like "show me only the UK
statutory Y3 list" are trivial joins instead of rebuilds.

---

## Summary — the EN port + ConceptNet expansion checklist

Before writing `01_consolidate_en.py`:

- [ ] Move scripts to `pipeline/voc-en/`, *never* `lib/`.
- [ ] Number filenames by pipeline position only (no `_v24`, `_old`).
- [ ] Commit *every* iteration; use `archive/` not `_old` filenames.
- [ ] HF token: rotate the leaked one, use `~/.config/huggingface/token`.
- [ ] Schema: keep `article` nullable, `genus` NULL for EN, canonical
      `word_type` in English.
- [ ] Each word carries `tags`, `cefr`, `uk_year`, `aoa_kuperman` — not
      just a flattened `grade_level`.
- [ ] HF Space warmup ping before the V24 batch.
- [ ] Child‑safety filter is a first‑class step.
- [ ] "API wins" pattern is conservative — log conflicts, second pass to
      review.
- [ ] After the run: commit the build script *and* the build log.
- [ ] No hardcoded `/opt/homebrew` paths.

Before writing the all‑languages ConceptNet rebuild:

- [ ] Run on a 32 GB / ≥60 GB SSD box. VPS_3 if accessible, else local
      desktop.
- [ ] Output to a *sibling* dataset (`cstr/conceptnet-normalized-all`),
      not a replacement.
- [ ] Upload the build script alongside the DB.
- [ ] Stick with ConceptNet 5.7 for v1. Defer 5.8 to a later upgrade.
