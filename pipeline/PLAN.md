# PLAN — Reproduce voc-de, build voc-en, expand ConceptNet

## Priority order (decided 2026-05-21)

1. **§1 — DE DB safe rebuild** — produce a feature-complete (≥ current
   shipped DB) German DB using only **100 % safely-licensed** data.
2. **§2 — EN DB at DE parity** — port the cleaned pipeline to English.
3. **§3 — CC-BY-SA App Store / Play Store compliance** — half-day
   pre-submission checklist; gate on §1+§2 outputs.
4. **§4 — ConceptNet all-languages expansion** — deferred until §1–§3
   ship.

The rest is reference / enrichment / cleanup material:

- §5 — Reproducibility recipe for the **historical** DE DB (the "as-is"
  baseline; useful for diff against §1 output).
- §6 — Algorithmic spelling-pattern classifier (ongoing improvement).
- §7 — Additional free-licensed data sources to add over time.
- §8 — Housekeeping (rotate leaked HF token, etc.).
- §9 — Open decisions still pending.

---

## 1. DE DB safe rebuild ✅ **fully complete 2026-05-25**

Completed via in-place patching + post-build enrichment passes. Full record in
`pipeline/HISTORY.md → 2026-05-21` and `pipeline/voc-de/README.md`.

**Final state (2026-05-25):**
- Asset: `assets/grundwortschatz.db.gz` — **24 MB** (148 MB uncompressed)
- 13,040 entries (2,150 Vornamen + 10,890 regular)
- 10,890 entries with word_type (2,150 Vornamen intentionally blank)
- grade_examples: **10,876/10,890 = 99%** (14 very hard words failed all LLM attempts)
- 2,401 entries with commonMistakes (LiTKey errors)
- 3,487 entries with litkey_profiles (spelling difficulty data)
- check pass: 1,944 entries corrected

**Post-build patchers run (2026-05-21 → 2026-05-25):**
- `add_gutenberg_examples.py` — Gutenberg corpus sentence extraction
- `add_llm_examples.py --grade --workers 3` — per-grade LLM examples (3 passes + retry)
- `add_llm_examples.py --check --workers 3` — grammar/gap correction (1,944 entries)
- `add_litkey_errors.py` — LiTKey commonMistakes (2,401 entries; 2026-05-24)
- `add_litkey_profiles.py` — LiTKey spelling difficulty profiles (3,487 entries; 2026-05-24)
- `add_vornamen.py` — 2,109 German first names from Standesamt tables
- `patch_vorname_rang.py` — frequency ranking for all Vornamen
- word_type backfill — 885 LITKEY entries got word_type from enrichment_json.partOfSpeech

**Key fixes applied during enrichment (both DE + EN scripts):**
- `response_format={"type":"json_object"}` in `llm.call()` for `mode=="fill"` — fixes Llama-3.3-70B malformed JSON
- `GRADE_MAX_WORDS` raised for DE: `{1:10,2:10,3:14,4:14,5:18,6:18}` — German sentences are naturally longer
- Exclude Groq/Cohere: `env GROQ_API_KEY="" COHERE_API_KEY=""` — rate-limit constantly, produce bad output

---

## 2. Build the EN DB at DE parity ✅ **fully complete 2026-05-26**

Full pipeline record in `pipeline/voc-en/HISTORY.md`.

### Final state (2026-05-26)

- Asset: `assets/grundwortschatz_en.db.gz` — **17 MB** (92 MB uncompressed)
- **11,539 entries** — success=7,815 / minimal→success=3,658 / no_data=66

| Layer | Status |
|---|---|
| Wiktionary enrichment (defs, IPA, inflections) | ✅ 11,486/11,539 (99%) — via VPS `168.119.190.252` |
| OEWN WordNet sense expansion | ✅ 9,186 entries (79%) |
| Common learner errors (Norvig + Wikipedia) | ✅ 27,363 annotations |
| Dialect spelling variants (SCOWL UK↔US) | ✅ 270 variants |
| Frequency bands (wordfreq) | ✅ all 11,539 |
| CEFR-J level tags | ✅ 6,879 entries |
| Cambridge YLE + UK DfE statutory lists | ✅ |
| gradeLevelEstimate + grade_level column | ✅ synced via `add_uk_curriculum.py --grade-only` |
| Gutenberg example sentences | ✅ 6,274 entries (54%) |
| Grade-differentiated examples (LLM) | ✅ 11,481/11,539 (99%) |
| LLM check-all (grammar/gap correction) | ✅ 10,692/11,481 corrected |

### `enrich_minimal_en.py` — VPS run note

Originally ran locally (external USB drive, 0.1/s = 16h ETA). Killed and re-run on
VPS `168.119.190.252` where Wiktionary DB is on NVMe (1.4/s, completed in 27 min).
Script path on VPS: `/root/voc-enrich/voc-en-minimal/enrich_minimal_en.py`
Wiktionary DB on VPS: `/root/voc-enrich/en_wiktionary_normalized_all.db`

### Game UI — completed 2026-05-26

- ✅ L2L picker in Settings (already existed, working)
- ✅ DE-only games (`großschreib`, `großstadt`, `verbTrenner`, `wortbaumeister`) hidden for L2L=en via `supportedLearningLanguages`
- ✅ `wortbaumeister` fixed from `['de','en']` → `['de']` (it teaches German compound nouns)
- ✅ ARB strings added for L2L picker section (`learningLanguage`, `learningLanguageDesc`)
- ✅ ARB strings added for all DE-only game card titles/descriptions (`grossschreibDescription`, `grossstadtCardTitle/Desc`, `wortbaumeisterCardTitle/Desc`, `verbtrennerCardTitle/Desc`)
- ✅ WordSort + WordTypeWhirl hint text localised — EN words now get English feedback

- ✅ `SpellingSpotterGame` — EN-only game using `commonLearnerErrors` data (8,314 words); 4-option MCQ, grade-filtered, with context sentences

- ✅ **L10n / a11y pass (2026-05-27)** — All hardcoded DE/EN ternaries replaced with ARB keys
  across 12 game screens. Semantics labels added to verbtrenner (back, level, score, progress,
  combo). Word type names, onboarding bodies, empty states, karteikasten box labels,
  word-of-the-day card, onboarding overlay buttons, debug snackbar all localised.
  ~150 new ARB keys. `_isDE` getter removed from 5 files where fully unused.

### Remaining (deferred)

- New EN-only games needing pipeline data first: `phrasal_verbs` (need phrasal verb DB data); `homophones` (need homophone pairs)
- HF dataset export updated: `pipeline/voc-en/hf_export/` — 11,539 words + 18,642 examples (re-run 2026-05-26)

### Architectural decisions (locked in)

| Decision | Value | Rationale |
|---|---|---|
| Canonical variant | UK English | Aligns with UK Year 1–6 statutory spelling lists; US spellings carried as `commonLearnerErrors` |
| Vocabulary size | ~11.5k, filterable | CEFR-J A1-B2 + YLE + UK curriculum superset; tags control app subsets |
| Grade mapping | UK Y1–6 primary, CEFR + freq fallback | Same role as NRW Grundwortschatz for DE |
| Misspellings | `commonLearnerErrors[]` under correct lemma only | Matches DE; never standalone entries |
| Wiktionary enrichment | `enrich_minimal_en.py` locally (external drive) or VPS | 1.9 GB Wiktionary DB at `/Volumes/backups/code/WiktionaryEN-space/` |
| OEWN enrichment | `add_oewn_en.py` single-threaded | wn not thread-safe; ~600/s; 6k entries ≈ 10s |
| grade_examples storage | `metadata_json.grade_examples` | Mirrors `gutenberg_examples`; injected by Dart service before `ApiEnrichment.fromJson` |
| App shape | Single app, both DBs bundled; L2L × GUI matrix | L2L picker in Settings (deferred game UI work) |

---

## 3. Rebuild ConceptNet for all languages

**Goal:** produce `cstr/conceptnet-normalized-all` (sibling to the existing
11‑language `cstr/conceptnet-normalized-multi`) — same schema, every
language ConceptNet covers (~370).

The 11‑language subset stays in place for backward compatibility (external
consumers, e.g. `enc-app_5b.py`, still query it via the Gradio Space).

### The lost script

The script that took
`cstr/conceptnet-de-indexed/conceptnet-de-indexed.db` (23.6 GB,
all‑languages, un‑normalized) →
`cstr/conceptnet-normalized-multi/conceptnet_normalized.db` (1.78 GB,
11 languages, integer‑keyed) **does not survive** anywhere on the
laptop, in `/Volumes/backups/code`, in either HF dataset repo, or in
either Gradio Space repo. Suspected location: `/tmp/` on VPS_3
(`135.181.205.133`), which we cannot currently authenticate to.

### Target schema (inferred from `conceptnet_app_1.py`)

```sql
CREATE TABLE node_norm (
  node_pk   INTEGER PRIMARY KEY,
  node_url  TEXT UNIQUE NOT NULL,    -- http://conceptnet.io/c/{lang}/{term}[/...]
  language  TEXT NOT NULL            -- redundant w/ node_url prefix, but cheap & useful
);
CREATE TABLE rel_norm (
  rel_pk    INTEGER PRIMARY KEY,
  rel_url   TEXT UNIQUE NOT NULL     -- http://conceptnet.io/r/{Relation}
);
CREATE TABLE edge_norm (
  start_fk  INTEGER NOT NULL REFERENCES node_norm(node_pk),
  end_fk    INTEGER NOT NULL REFERENCES node_norm(node_pk),
  rel_fk    INTEGER NOT NULL REFERENCES rel_norm(rel_pk),
  weight    REAL    NOT NULL
);
CREATE INDEX ix_edge_start_rel ON edge_norm(start_fk, rel_fk);
CREATE INDEX ix_edge_end_rel   ON edge_norm(end_fk,   rel_fk);
```

Approx sizes: `node_norm` ~28 M rows, `rel_norm` ~50 rows, `edge_norm`
~34 M rows un‑filtered.

### Rebuild recipe

```python
# 0. Setup
from huggingface_hub import hf_hub_download, HfApi
import sqlite3, os

# 1. Pull the 23.6 GB un-normalized source
src = hf_hub_download(
    repo_id="cstr/conceptnet-de-indexed",
    filename="conceptnet-de-indexed.db",
    repo_type="dataset",
)
# Note: filename says "de" but it contains all languages — the name
# is historic. Verify with: SELECT DISTINCT language FROM node LIMIT 20

# 2. Open both DBs
out = "conceptnet_normalized_all.db"
con_out = sqlite3.connect(out)
con_out.execute("ATTACH DATABASE ? AS src", (src,))
con_out.executescript("""
  PRAGMA journal_mode = WAL;
  PRAGMA synchronous   = NORMAL;
  PRAGMA cache_size    = -1000000;   -- 1 GB
  PRAGMA temp_store    = MEMORY;
""")
con_out.executescript("""
  CREATE TABLE rel_norm(
    rel_pk INTEGER PRIMARY KEY, rel_url TEXT UNIQUE NOT NULL);
  CREATE TABLE node_norm(
    node_pk INTEGER PRIMARY KEY, node_url TEXT NOT NULL, language TEXT NOT NULL);
  CREATE TABLE edge_norm(
    start_fk INTEGER NOT NULL, end_fk INTEGER NOT NULL,
    rel_fk   INTEGER NOT NULL, weight REAL NOT NULL);
""")

# 3. Populate rel_norm (~50 rows)
con_out.execute(
  "INSERT INTO rel_norm(rel_url) SELECT DISTINCT id FROM src.relation"
)

# 4. Populate node_norm (~28M rows; keep ALL languages)
con_out.execute(
  "INSERT INTO node_norm(node_url, language) "
  "SELECT id, language FROM src.node"
)
con_out.execute("CREATE UNIQUE INDEX ix_node_url ON node_norm(node_url)")

# 5. Populate edge_norm in batches (single statement OOMs)
N = 500_000
src_cur = con_out.execute("SELECT COUNT(*) FROM src.edge").fetchone()[0]
for offset in range(0, src_cur, N):
    con_out.execute("""
      INSERT INTO edge_norm(start_fk, end_fk, rel_fk, weight)
      SELECT n1.node_pk, n2.node_pk, r.rel_pk, e.weight
      FROM (SELECT * FROM src.edge LIMIT ? OFFSET ?) e
      JOIN node_norm n1 ON n1.node_url = e.start_id
      JOIN node_norm n2 ON n2.node_url = e.end_id
      JOIN rel_norm  r  ON r.rel_url  = e.rel_id
    """, (N, offset))
    con_out.commit()
    print(f"edge_norm: {min(offset+N, src_cur):,}/{src_cur:,}")

# 6. Indexes
con_out.executescript("""
  CREATE INDEX ix_edge_start_rel ON edge_norm(start_fk, rel_fk);
  CREATE INDEX ix_edge_end_rel   ON edge_norm(end_fk,   rel_fk);
""")

# 7. Vacuum + analyze
con_out.execute("VACUUM")
con_out.execute("ANALYZE")
con_out.close()

# 8. Push
HfApi().upload_file(
    path_or_fileobj=out,
    path_in_repo="conceptnet_normalized_all.db",
    repo_id="cstr/conceptnet-normalized-all",
    repo_type="dataset",
)
```

**Expected output size: ~6–8 GB.** (The 11‑language subset is 1.78 GB; the
full set scales ~4× since most edges are EN/FR/IT/DE/ES + the long tail of
~370 languages adds a few hundred MB.)

**Hardware:** 32 GB RAM machine with ≥60 GB free SSD (source + dest + WAL
+ temp space). Single‑VPS run preferred — `cstr/conceptnet-de-indexed` is
hosted in `eu-west-1`; downloading to a Hetzner box is fast (10–15 min)
vs ~1 h to a laptop on residential connection. Wall time 4–10 h
dominated by the 34 M‑row join.

**Alternative source:** for ConceptNet 5.8 (newer) instead of 5.7,
download `https://zenodo.org/record/3739540/files/conceptnet-raw-data-5.8.zip`
and run the upstream Snakefile (`/Users/christianstrobele/code/conceptnet5/Snakefile`).
~10 GB raw, ~6 h build to assertions CSV, then run the same normalize
pipeline. Recommend deferring — 5.7 is current and well‑indexed.

### Runtime app update

Once the new dataset is up, two‑line change to
`conceptnet_app_1.py`:

```python
NORMALIZED_REPO_ID = "cstr/conceptnet-normalized-all"  # was -multi
NORMALIZED_DB_FILE = "conceptnet_normalized_all.db"

# Drop or repopulate TARGET_LANGUAGES — easiest:
# pull distinct languages from node_norm at startup so the dropdown
# reflects the full set.
```

Deploy as a sibling Space `cstr/conceptnet_normalized_all` so the
existing 11‑lang Space keeps serving.

---

## 4. Housekeeping

### 4.1 Rotate the leaked HF token

`hf_***REDACTED***` was committed to VPS_2
(`/root/.bash_history`) in plaintext via `export HF_TOKEN=...` and `./run_wiktionary_extract.sh`. Anyone who reads that file gets the token. **Token value redacted from these docs 2026-05-29; still present in git history — rotation on HF is the real fix.**

Recovery:

1. Visit `https://huggingface.co/settings/tokens`, revoke the token.
2. Issue two new tokens:
   - A **write‑scoped** token, used only locally for `push_to_hub`, kept in `~/.config/huggingface/token` (per HF CLI default), never in env or bash_history.
   - A **read‑only** token for the Gradio Spaces, set as a Space secret in the HF UI — never inline in code.
3. Wipe `/root/.bash_history` on VPS_2: `cat /dev/null > ~/.bash_history && history -c && exit` (re‑login).
4. Update `/Users/christianstrobele/code/.env` and any scripts referencing the token.

### 4.2 Pick a canonical build VPS

VPS_2 is committed to wiktionary work and that's fine. ConceptNet rebuilds
benefit from more RAM and disk than VPS_2 has — recommend doing the
rebuild on **VPS_3 if we can get back in**, otherwise on the user's
desktop. Either way, after the run, `rsync` the script and a build log
back to `pipeline/conceptnet/build/` and commit. **No more lost scripts.**

### 4.3 Restore the voc-de scripts to the working repo

Copy `/Volumes/backups/code/voc/lib/features/games/data/*.py` →
`pipeline/voc-de/` and commit. Don't put them back into
`lib/features/games/data/` (they'll get re‑deleted next time someone
shrinks the Flutter bundle).

A `.gitignore` carve‑out: ignore intermediate JSON outputs but commit the
scripts and source CSVs/TXTs that the pipeline reads.

---

## 5. Open decisions

These block forward progress. EN port decisions resolved 2026-05-21 and
moved to `pipeline/voc-en/HISTORY.md → Architectural decisions`.

### ConceptNet (§3)

5. **Replace or sibling**? The 11‑lang `conceptnet-normalized-multi` has external consumers (`enc-app_5b.py` etc).
   - **Sibling** (new `-all` repo) — safer, costs one extra HF dataset slot.
   - Replace — cleaner if no external consumers were ever published.
   - Recommendation: **sibling** unless you can prove no one is using `-multi`.

6. **ConceptNet 5.7 vs 5.8**? `cnn_app_2.py` pulled 5.7; the README of `conceptnet-de-indexed` says "5.5". The upstream stable is 5.7.
   - 5.7 — matches what's on HF, no re‑extract needed.
   - 5.8 — newer, but requires running the upstream Snakefile fresh (~6 h CPU job).
   - Recommendation: **5.7** for v1 of the all‑languages build. Defer 5.8.

### Housekeeping (§4)

7. **Rotate the HF token now**? — recommended yes, before any other work.
8. **Try VPS_3 with updated credentials**? — only path to recovering the lost normalize script.

---

## 6. Algorithmic spelling-strategy classifier (FRESCH and beyond)

`04b_derive_fresch_categories.py` (just added) bootstraps the FRESCH
tagging by **mechanically mapping NRW xlsx linguistic feature tags →
FRESCH categories**. It covers the ~533 NRW Grundwortschatz words.

Two limitations to fix in a v2 classifier:

### 6.1 Coverage — extend beyond NRW (~10k words)

Current state: 533 words tagged from NRW features; the remaining ~9.5k
words in the consolidated vocabulary fall through to a heuristic
fallback based on surface regex (doubled consonants → Weiterschwingen,
b/d/g final → Ableiten, prefixes → Wortbausteine, etc.).

The fallback is good for 80 % of cases but misses:
- Auslautverhärtung that only fires after derivation (`Hand` → `Hände`)
- Umlauting that crosses derived forms (`fahren` → `fährt`)
- Compound boundaries that aren't visible without morphological
  analysis (`Haustür` = `Haus` + `Tür`)
- Words where the orthographic pattern is regular but the *learner-error
  rate* would justify a Merkwort tag

**v2 should layer:**
1. **spaCy morphology** (already in step 02) — gives lemma + POS + features
2. **`enrichment_json.inflections`** from `cstr/WiktionaryDE` — full
   inflection table for verbs / nouns / adjectives → derive Ableiten /
   Umlautung candidates
3. **`enrichment_json.hyphenation`** — Wortbausteine = ≥2 syllables
   with a clear morpheme boundary (e.g. `Auto-bahn`, `un-glaublich`)
4. **CMU-equivalent IPA from step 05** — Mitsprechen = strict phoneme-
   grapheme regular mapping; deviation flags it for one of the other
   strategies
5. **Frequency-based Merkwort detection** — top-N most-common
   function words are Merkwörter by definition (already captured in NRW
   but extend to non-NRW frequency-top words)

### 6.2 Pedagogical primary-strategy pick

Current state: multi-label (1–5 tags per word). Validation against the
old curated 532Strategien.csv showed 6.2 % exact agreement, with most
divergence from us over-tagging.

The teacher‑facing app should expose **one primary strategy per word**
plus the others as secondary tags. Priority order based on FRESCH
didactics:

```
Großschreibung (if applies)
  → then prefer one of: Merken > Weiterschwingen > Ableiten
     > Wortbausteine > Mitsprechen
```

Reason: Großschreibung is an orthogonal capitalization rule; among the
sound/letter strategies, Merken (irregular) is the highest-leverage
single label, then Weiterschwingen (doubled-consonant rule), etc.,
falling back to Mitsprechen (regular sound-it-out) as the default.

Implementation: add a `--mode primary` flag to
`04b_derive_fresch_categories.py` that picks the single highest-priority
tag per word, alongside the existing multi-label list. The DB stores
both: `apiEnrichment.spellingStrategy` (list) and
`apiEnrichment.spellingStrategyPrimary` (single).

### 6.3 Tuning targets

- **Cut Ableiten over-application** (precision 5.2 %): only fire when
  the lemma ends in b/d/g/s/v *and* the spaCy inflection table shows a
  voiced-consonant alternation, OR when an Umlaut appears in the
  inflection table.
- **Improve Merken recall** (currently 41 %): add irregular-spelling
  detection from the grapheme-variant generator in step 06.
- **Improve Wortbausteine recall** (currently 33 %): use Wiktionary
  hyphenation field, not just regex prefixes.

### 6.4 Legal posture for FRESCH labels

The category names `Mitsprechen / Weiterschwingen / Ableiten / Merken /
Wortbausteine / Großschreibung` are **common German pedagogical terms**.
Under German Urheberrecht and EU copyright doctrine:

- Ideas, methods, and pedagogical concepts are **not copyrightable**;
  only specific expressions are.
- The individual category names are not trademarks — they're general
  vocabulary.
- The acronym "FRESCH" (Freiburger Rechtschreibschule) is likely
  registered as a Wortmarke by AOL/Persen, but that only restricts using
  "FRESCH" *as a brand identifier*. It does NOT restrict the method or
  the underlying terms.
- The proprietary part is the specific *curated wordlist* AOL/Persen
  publishes — we don't ship that; our derivation is from NRW's xlsx.

So labelling words with `weiterschwingen` etc. is fully allowed.
The about-text should say "FRESCH-style spelling strategies" or
"applies the FRESCH categorisation" — nominative fair use of the method
name — rather than implying brand endorsement.

### 6.5 Carry both taxonomies (decided 2026-05-21, implemented)

`04b_derive_spelling_patterns.py` now emits **three parallel views** of
the same NRW-derived data per word:

1. **6-category detailed view** (kid-facing default)
   ```
   klangtreu / doppelkonsonant / verwandt / merkwort / morphem / grossschreibung
   ```
   Neutral German linguistic-pattern names. Fine-grained: distinguishes
   doubled consonants (`doppelkonsonant`) from morphological derivation
   (`verwandt`) from morpheme composition (`morphem`).

2. **5-category Thomé view** (academic / teacher view)
   ```
   basisgraphem / orthographem / morphem / merkwort / grossschreibung
   ```
   Aligned with Günther Thomé's *Basiskonzept Rechtschreiben* framework
   and consistent with German Schriftlinguistik orthodoxy
   (phonematisches / morphematisches / orthographisches Prinzip).
   Coarser: `orthographem` covers all orthographic exceptions (doubled
   consonants + Dehnungs-h + ck/tz/sp/st + dialectal markers);
   `morphem` covers both morphological derivation AND composition.

3. **Raw NRW feature paths** (provenance / debugging)
   The dotted-path identifiers from the original NRW xlsx columns
   (`orthografisches und silbisches Prinzip.Doppelkonsonanten.tt` etc.)
   for transparency about how each tag was derived.

Per-word shape in `apiEnrichment`:

```jsonc
"apiEnrichment": {
  // 6-category detailed view (kid-facing)
  "spellingStrategy": ["doppelkonsonant", "grossschreibung"],
  "spellingStrategyPrimary": "grossschreibung",

  // 5-category Thomé view (academic / teacher view)
  "spellingPatternsThome": ["grossschreibung", "orthographem"],
  "spellingPatternsThomePrimary": "grossschreibung",

  // Provenance
  "spellingStrategySource": "nrw_derived",   // or "fallback_heuristic"
  "nrwLinguisticFeatures": [
    "orthografisches und silbisches Prinzip.Doppelkonsonanten.tt",
    "zusätzliche Filter.Wortart.Nomen"
  ]
}
```

Mapping between schemes (strict bucketing, used for fallback-heuristic
words outside the NRW Grundwortschatz):

| 6-cat detailed | → | 5-cat Thomé |
|---|---|---|
| klangtreu | → | basisgraphem |
| doppelkonsonant | → | orthographem |
| verwandt | → | morphem |
| merkwort | → | merkwort |
| morphem | → | morphem |
| grossschreibung | → | grossschreibung |

For NRW-derived words, the 5-cat Thomé view picks up MORE features than
the strict bucketing alone — `orthographem` also fires on `Dehnungs-h`,
`ck`, `tz`, `sp/st` features that the 6-cat doesn't currently cover (a
gap to close as part of §6.1 coverage extension).

**App-side surface**: by default games and the home screen surface the
6-cat detailed view (kid-friendly tags). Parent-dashboard /
teacher-view can switch to the 5-cat Thomé view for academic
transparency. The raw NRW paths stay hidden in the DB; they're for
debugging and future-tooling.

Total cost: ~30–40 % more bytes per NRW-tagged entry (~1–2 KB per word
that has all four fields populated). Acceptable given the DB is ~120 MB
uncompressed.

### 6.6 Validation harness

Keep `532Strategien.csv` from the backup as a **gold-standard test
fixture** (not as a build input). Add `tests/test_fresch_classifier.py`:
target agreement ≥ 50 % exact, ≥ 80 % subset/superset on the 304
overlapping words. (We're at 6.2 % exact / ~85 % superset today.)

---

## 7. Additional free-licensed data sources to integrate

Catalogued by free-license suitability for a commercial app.

### Priority 1 — clear license, high pedagogical value

| Source | URL | License | What it adds | Effort |
|---|---|---|---|---|
| **Tatoeba DE** | https://tatoeba.org/eng/downloads | CC-BY 2.0 FR | ~200k+ German example sentences, many tagged for difficulty / native-speaker-confirmed. Per-word indexing trivial. Replaces / augments sparse Wiktionary examples. | 0.5 day |
| **Wiktionary "Verzeichnis:Deutsch/Fehlschreibungen"** | https://de.wiktionary.org/wiki/Verzeichnis:Deutsch/Fehlschreibungen | CC-BY-SA 4.0 | Clean replacement for the Tacke/Menzel `100/300/400 Fehler` list. | 0.5 day |
| **Wikipedia "Liste häufiger Rechtschreibfehler"** | https://de.wikipedia.org/wiki/Wikipedia:Liste_h%C3%A4ufiger_Rechtschreibfehler | CC-BY-SA 4.0 | Same role as above; complementary coverage. | (combined with above) |
| **Bundesländer Grundwortschätze (Hessen, BW, RLP, Bayern, Sachsen, S-H)** | gov ministries, see LICENSES.md | Public administrative material, attribution typical | Per-Bundesland tags. Widens grade coverage; lets teachers filter by their state. ~500–870 words each, 70-80 % overlap with NRW but the diff is pedagogically interesting. | 1 day total |
| **DWDS Häufigkeitsklassen** | https://www.dwds.de/d/api | CC-BY-SA via DWDS terms | log-frequency band (1–25) per headword. More pedagogically useful than raw rank. | 0.25 day |
| **Wiktionary "Liste falscher Freunde"** (DE↔EN) | https://de.wiktionary.org/wiki/Verzeichnis:Deutsch/Falsche_Freunde | CC-BY-SA 4.0 | False-friend warnings for the EN learning-mode (when DE-speaker is learning EN, or vice versa). | 0.5 day |

### Priority 2 — useful, license caveats to verify

| Source | License | Notes |
|---|---|---|
| **DWDS Wortprofil API** | CC-BY-SA via DWDS | Per-headword typical collocations. Could power a "passendes Wort" game mode. Per-request API; would batch the 10k words. |
| **LanguageTool DE rule patterns** | LGPL on the codebase; rule data are structured facts | Extract just the headwords each rule fires on → "this word commonly involves rule X" tag. |
| **Hunspell DE affix file** | LGPL/MPL on the dictionary | Systematic plural/conjugation fallback when API enrichment misses. |
| **OPUS DE corpora** (Books, EUbookshop, Wikipedia, etc) | Per-corpus, mostly CC-BY-SA | Additional frequency signals. Diminishing returns over HermitDave + Leipzig. Skip for v1. |

### Priority 3 — skip (NC clauses / academic-only)

| Source | Issue |
|---|---|
| MERLIN Corpus (CEFR-leveled German learner texts) | CC-BY-NC-SA — NC blocks commercial |
| GermaNet (academic German WordNet) | €200 academic + NC for commercial — OdeNet covers it already (free CC-BY-SA equivalent) |
| Tüba-D/Z, deWaC, Falko Korpus | Academic-only / NC |
| CELEX2 | Paid commercial license |
| MERLIN, KOLAS, DGS-Korpus | NC clauses |

### Deferred — license verification needed

| Source | URL | License status | Notes |
|---|---|---|---|
| **childLex** (Schroeder et al., HU Berlin) | https://childlex.de + https://osf.io/tqgjs | **GNU GPL-3.0** per the OSF project page (verified via OSF API 2026-05-21). The earlier "research-only NC" framing was stale. GPL-3.0 permits commercial use; integration would cascade the shipped DB's license CC-BY-SA-4.0 → GPL-3.0 (these are one-way compatible per Creative Commons' 2015 v4-compatible decision). App code stays proprietary either way. | Strategic call: integrating cascades the DB license. Worth doing for the grade-band accuracy boost (childLex norms cover ages 6–8 / 9–10 / 11–12 — natural fit for Klassen 1-6 grade-band signal). |

### Recommended integration order

If we ship the next DE DB rebuild with one fresh source per week:

1. **Tatoeba DE** — visible UX improvement (better example sentences)
2. **Wiktionary Fehlschreibungen + Wikipedia common misspellings** — clean replacement for Tacke
3. **Bundesländer Grundwortschätze (start with Hessen + BW)** — adds curricular tags
4. **DWDS Häufigkeitsklassen** — cheap small win

That's about **2–4 days of focused work** for a materially upgraded DE DB.

---

## 8. Pre-launch: CC-BY-SA compliance for App Store / Play Store release

**Triggering event**: the moment we submit to Apple App Store or Google
Play, the app reaches a meaningfully wider audience and the CC-BY-SA
obligations on the shipped DB become operationally important. The current
Vercel deployment is technically already a "distribution", but exposure
is low. **All of the below should be done before the first store
submission.**

### 8.1 Why the DB is CC-BY-SA 4.0

`assets/grundwortschatz.db.gz` inherits CC-BY-SA from upstream content:

| Upstream | What it contributes |
|---|---|
| **Wiktionary (DE/EN)** | Definitions, IPA, inflections, examples, etymology, syn/ant, hyper/hypo/mero/holo (~all enrichment_json content) |
| **ConceptNet 5.x** | Semantic relations under enrichment_json.conceptnet |
| **OpenThesaurus** | Synonym/hypernym/hyponym closure |
| **OdeNet** | DE WordNet sense data |
| **HermitDave / OpenSubtitles** | Frequency rank fields |
| **Wikipedia commonly-misspelled** | (planned) commonLearnerErrors seed |

The Flutter app code itself stays proprietary — only the DB blob is
CC-BY-SA. Same legal model as Wikipedia/Britannica mobile apps.

### 8.2 What CC-BY-SA 4.0 actually requires (concretely)

| Requirement | How we satisfy it |
|---|---|
| **Attribution** | In-app Settings → Licenses screen (already wired up via `LicenseRegistry.addLicense` for every CC-BY-* source). Visible link from Settings. ✅ |
| **ShareAlike** | The DB must be redistributable under CC-BY-SA. **Action**: upload `assets/grundwortschatz.db.gz` as an HF dataset (e.g. `cstr/grundwortschatz-voc-de`) marked CC-BY-SA 4.0, link to it from the in-app license screen. Not required to make easy — just possible. |
| **Indicate changes** | Per-source license entries already note "Changes made: …" (filter to 10k, NRW grade tags merged in, etc.). ✅ |
| **No additional restrictions** | App EULA must not forbid extracting / redistributing the DB. Currently no EULA — when one is added (App Store-required), explicitly exempt the DB. |
| **Notice of license** | Add a one-line statement at the top of the License screen and in the public-facing README: *"The vocabulary database is licensed under CC BY-SA 4.0. The application code is proprietary."* |

### 8.3 Pre-submission checklist (~half-day of work)

- [ ] Upload `assets/grundwortschatz.db.gz` to new HF dataset
      `cstr/grundwortschatz-voc-de`. Include in the dataset README:
      - CC-BY-SA 4.0 statement
      - Full attribution list (same as in-app License screen)
      - "Changes made" section: filtering to 10k, NRW grade tag merge,
        spelling-pattern derivation (own derivation from NRW xlsx), etc.
      - Citation: how to credit the dataset
- [ ] Same for `cstr/grundwortschatz-voc-en` when EN ships.
- [ ] Add top-of-screen line to in-app License screen: *"Vocabulary
      database licensed under CC BY-SA 4.0 — `cstr/grundwortschatz-voc-de`
      on Hugging Face"* with tap-to-open link.
- [ ] Add `DATA_LICENSE.md` to repo root explaining the dual-license
      stance (app code proprietary, DB blob CC-BY-SA).
- [ ] Repo README: add a one-paragraph note linking to DATA_LICENSE.md.
- [ ] Verify the soon-to-be-written App Store EULA does NOT contain
      clauses that restrict reverse-engineering / extracting the DB.

### 8.4 What we are NOT required to publish

- Flutter app source code (stays proprietary)
- Build pipeline scripts (`pipeline/voc-de/*.py`) — these are public
  on the repo now for convenience and transparency, but CC-BY-SA does
  not require it
- Custom assets (fonts, images, sounds — they have their own licenses)

### 8.5 Things that are nice-to-have but optional

- **Public build provenance**: making the pipeline repo public makes
  any future CC-BY-SA challenge easier to refute. We're already on
  `github.com/CrispStrobe/words-universe` — confirm if it's currently
  public or private and decide.
- **Per-language DB sub-licensing notes**: if the EN DB ends up using
  sources with stricter NC-flavoured terms (e.g. if we accidentally
  pull in childLex before clarifying its license), we'd need to
  document that separately. Currently EN port avoids all NC content.

### 8.6 Current exposure (Vercel) — effectively zero

The Vercel URL is **shared only with a small number of friends** and
**not publicly surfaced anywhere**. There is therefore essentially no
public CC-BY-SA distribution event to worry about today. The §8.3
checklist is the **pre-store-submission** task list, not a "do it now"
emergency.

That said, since the Vercel URL is unauthenticated, treat anything
shipped there as one accidental link-share away from being public. The
§8.3 work is cheap (~half a day); doing it before the next visible
share is the safer default.

---

## TL;DR

- DE rebuild: scripts + sources survive in backup → **fully reproducible** in 3–8 h.
- EN port: **nearly complete** — 11,539 entries, grade fill running (PID 9034), post-fill sequence ready in `pipeline/voc-en/PLAN.md`.
- ConceptNet expansion: ~½ day code + 4–10 h compute → **~6–8 GB** all-languages DB sibling.
- Spelling-pattern classifier v2: extend beyond NRW + primary-pick + dual taxonomy (§6) — ~2 days.
- 7 additional free-licensed data sources to add (§7).
- **CC-BY-SA compliance pre-store-submission (§8) — half-day, must be done before App Store.**
- One leaked credential to rotate.
