# PLAN — Reproduce voc-de, build voc-en, expand ConceptNet

## Status map (updated 2026-05-29)

The DB build is done; what remains is optional/forward-looking.

| § | Topic | Status |
|---|---|---|
| §1 | DE DB safe rebuild | ✅ done → HISTORY |
| §2 | EN DB at DE parity (+ games) | ✅ done → HISTORY |
| §3 | ConceptNet all-languages expansion | ⬚ **optional/independent** — doesn't gate the app (relations already in the shipped DBs); script ready (`pipeline/conceptnet/`), runs on 8 GB; run when wanted |
| §4 | Housekeeping (token / scripts / build box) | ✅ resolved → HISTORY |
| §5 | Open decisions | ✅ resolved (ConceptNet sibling-vs-replace + 5.7 still apply *when* §3 runs) |
| §6 | Algorithmic spelling-strategy classifier (FRESCH) | ⬚ ongoing improvement |
| §7 | Additional free-licensed data sources | ✅ Priority-1 integrated + EN→DE translations + False Friends game (#48); remaining Priority-2 sources assessed & **deferred** (low value — see Remaining work) |
| §8 | Copyleft App/Play Store compliance (DE GPL-3.0 / EN CC-BY-SA-4.0) | ⬚ **pre-launch checklist** — gate before first store submission |

### Remaining work (2026-05-29) — shipped DBs + app are done

Two high-value enrichments were done this session; the rest were **assessed and
deferred** (low payoff / high effort — gap sizes below). Nothing blocks the app.

**✅ Done this session**
- **Wiktionary EN→DE translations** — filled the EN DB's empty `translations`
  table (0 → 9,317 across 8,112 words). `add_translations_en.py`. CC-BY-SA.
- **False Friends game** (#48, EN-only) — `false_friends_game.dart` on the
  shipped `false_friends` data (62 pairs).
- **Wortfalle — German confusables drill** (#49, DE-only) — `wortfalle_game.dart`,
  **35** curated confusion pairs (das/dass, Lärche/Lerche, fast/fasst, Mine/Miene, …) with embedded
  sentences (self-contained). Realizes the "LanguageTool confusables" idea via
  a curated catalogue. 37/40 pair-words already in the DE DB (missing:
  Laib, Stiel, Waise — game doesn't need them; optional vocab add later).

**Assessed & deferred** (autonomous-doable but low value / high effort — build only on request)

| Item | § | Why deferred | License |
|---|---|---|---|
| Hunspell DE inflection fallback | §7 | only ~930 content words (7%) lack inflections; German affix expansion is fragile + lower quality than the existing Wiktionary/DWDSmor inflections | GPL-2/3 ✅ |
| LanguageTool "rule X" tags | §7 | ✅ **realized as Wortfalle** (35 pairs). Mined `de/confusion_sets.txt` via a subagent → curated out the statistical/OCR noise → kept 15 clean pairs + agent-written German sentences/glosses. Further expansion possible but diminishing returns. | LGPL-2.1 ✅ |
| Wikidata Lexemes | §7 | overlaps what now exists (DE+EN translations, ~93% inflections); heavy (SPARQL/dumps) | CC0 ✅ |
| Tatoeba EN examples | §7 | EN already has 99% grade examples + Gutenberg + Wiktionary examples — redundant | CC-BY 2.0 ✅ |
| FRESCH classifier v2 | §6 | v1 ships; this is an accuracy/coverage refinement — heavy heuristic project | — |
| DWDS Wortprofil collocations | §7 | separate product — verify `dwds.de/wortprofil` license first | ⚠️ verify |

**Needs you (external)**

| Item | § | Who |
|---|---|---|
| ConceptNet all-languages rebuild — script ready (`pipeline/conceptnet/`) | §3 | you — VPS + ~60–70 GB disk, 4–10 h |
| HF dataset upload — `voc-de` (GPL-3.0) + `voc-en` (CC-BY-SA-4.0) | §8 | you — HF account |
| Device / visual QA of the games | — | you |
| Store-submission compliance final pass | §8 | you (pre-launch) |

---

## 1. DE DB safe rebuild ✅ **complete** → see HISTORY

Shipped `assets/grundwortschatz.db.gz` (13,040 entries, 24 MB). Full record:
`pipeline/HISTORY.md` (2026-05-21 → 2026-05-25), `pipeline/voc-de/README.md`.

## 2. EN DB at DE parity ✅ **complete** → see HISTORY

Shipped `assets/grundwortschatz_en.db.gz` (11,539 words + 400 phrasal verbs,
~18 MB). Game UI, l10n/a11y, and the two phrasal-verb games are done. Full
record: `pipeline/voc-en/HISTORY.md` and `pipeline/HISTORY.md`
(2026-05-26/27/29).

---

## 3. Rebuild ConceptNet for all languages

**Goal:** produce `cstr/conceptnet-normalized-all` (sibling to the existing
11‑language `cstr/conceptnet-normalized-multi`) — same schema, every
language ConceptNet covers (~370).

The 11‑language subset stays in place for backward compatibility (external
consumers, e.g. `enc-app_5b.py`, still query it via the Gradio Space).

### The lost script → rebuilt 2026-05-29

A runnable, resumable, 8 GB-friendly reimplementation now lives at
**`pipeline/conceptnet/build_normalized.py`** (see `pipeline/conceptnet/README.md`).
It encodes the recipe below plus the low-memory tweaks (keyset paging,
`temp_store=FILE`, WAL+checkpoint resume). Verified end-to-end on a synthetic
source; not yet run on the real 23.6 GB dump. The recipe below is kept as the
spec.

The original script that took
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

**Hardware:** the binding constraint is **disk (~60–70 GB free** for source
23.6 GB + dest ~8 GB + index/VACUUM temp), **not RAM** — the recipe is a
batched disk-based SQLite pipeline, not an in-memory job. Single‑VPS run
preferred — `cstr/conceptnet-de-indexed` is hosted in `eu-west-1`; downloading
to a Hetzner box is fast (10–15 min) vs ~1 h to a laptop on residential
connection. Wall time 4–10 h dominated by the 34 M‑row join + index sorts.

> **Runs fine on an 8 GB VPS** (the earlier "32 GB" was conservative
> boilerplate, not derived from this batched recipe). Apply these deltas:
> - `PRAGMA cache_size = -262144;` (256 MB, not 1 GB) — pure RAM page cache.
> - `PRAGMA temp_store = FILE;` and point `SQLITE_TMPDIR` at the big disk —
>   **the real fix**: creating `ix_node_url` (28 M rows) and the two
>   `edge_norm` indexes (34 M rows) runs an external merge sort that would OOM
>   with `temp_store = MEMORY` but spills to disk in bounded RAM with `FILE`.
> - `PRAGMA journal_mode = OFF;` for the one-shot build (no WAL growth, fastest;
>   it's reproducible so crash-safety is moot).
> - Replace `LIMIT ? OFFSET ?` edge paging with keyset paging
>   (`WHERE e.rowid > ? ORDER BY e.rowid LIMIT ?`) — `OFFSET` is O(n²) over
>   34 M rows (a speed fix, not memory).
> - Run `VACUUM`/`ANALYZE` last; `VACUUM` needs ~dest-size free disk for its
>   temp copy (already covered by the 60–70 GB budget), little RAM.
>
> Peak RAM ≈ `cache_size` + a modest working set → comfortably under 8 GB.
> Disk and wall-time are unchanged.

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

### 4.1 HF token — ✅ resolved (non-issue)

Re-assessed 2026-05-29: no real exposure (private repo, own-VPS bash_history,
local `.env`). Value redacted from docs; rotation is optional hygiene. See
`pipeline/HISTORY.md → 2026-05-29`.

### 4.2 Canonical build VPS — mostly moot

The ConceptNet normalizer is no longer lost (rebuilt at
`pipeline/conceptnet/build_normalized.py`) and now **runs on an 8 GB VPS** —
the extra RAM that motivated "use VPS_3" isn't needed. Just keep ≥60-70 GB
free disk; the script writes its own build log to `pipeline/conceptnet/runs/`.

### 4.3 voc-de scripts in the repo — ✅ done

72 `pipeline/voc-de/*.py` scripts are committed; the `.gitignore` carve-out
(ignore intermediate JSON, keep scripts + source CSVs/TXTs) is in place.

---

## 5. Open decisions

Nothing here blocks the app (the DBs shipped). These are the calls to make
*if/when* the optional §3 ConceptNet rebuild is run. EN port decisions were
resolved 2026-05-21 (see `pipeline/voc-en/HISTORY.md → Architectural decisions`).

### ConceptNet (§3)

5. **Replace or sibling**? The 11‑lang `conceptnet-normalized-multi` has external consumers (`enc-app_5b.py` etc).
   - **Sibling** (new `-all` repo) — safer, costs one extra HF dataset slot.
   - Replace — cleaner if no external consumers were ever published.
   - Recommendation: **sibling** unless you can prove no one is using `-multi`.

6. **ConceptNet 5.7 vs 5.8**? `cnn_app_2.py` pulled 5.7; the README of `conceptnet-de-indexed` says "5.5". The upstream stable is 5.7.
   - 5.7 — matches what's on HF, no re‑extract needed.
   - 5.8 — newer, but requires running the upstream Snakefile fresh (~6 h CPU job).
   - Recommendation: **5.7** for v1 of the all‑languages build. Defer 5.8.

### Housekeeping (§4) — resolved

7. ~~Rotate the HF token~~ — non-issue (no exposure); optional. See §4.1.
8. ~~Recover the lost normalize script via VPS_3~~ — done: rebuilt at
   `pipeline/conceptnet/build_normalized.py`, runs on 8 GB. See §4.2.

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

**Status (re-verified against the shipped DB 2026-05-29):** almost all of
Priority 1 is **already integrated** — the earlier "to integrate" framing was
stale. Source tags in `grundwortschatz.db.gz` confirm: `TATOEBA` (9,757), all
Bundesländer (`HESSEN`/`BAYERN`/`BERLIN`/`BRANDENBURG`/`NIEDERSACHSEN`/
`RHEINLAND_PFALZ`/`SCHLESWIG_HOLSTEIN`), `LITKEY`/DysList/Hurraki misspellings
(10,388 `commonMistakes`), DWDS frequency, and **childLex GPL-3.0 norms (9,008
entries)**. Scripts already in `pipeline/voc-de/`: `add_tatoeba_examples.py`,
`add_*_grundwortschatz.py`, `add_dwds_haeufigkeitsklassen.py`,
`add_childlex_norms.py`, `00b_fetch_de_misspellings.py`.

Remaining:
- **Priority 1 → DONE**, except **Wiktionary "Falsche Freunde"** as a distinct
  false-friends feature (not in the DB — the one genuine open P1 item; EN-mode relevant).
- **Priority 2 → per-source, only after a clear no-NC *data* license is verified.** Default skip.
- **childLex (GPL-3.0) is already shipped in the DB** → see the licensing note
  below + `DATA_LICENSE.md`. GPL is fine (user confirmed); the open call is
  whether to *declare* the combined DB GPL-3.0.
- **Priority 3 → skip** (NC / paid / academic-only).

### Priority 1 — ✅ ALREADY INTEGRATED (except Falsche Freunde)

| Source | URL | License | What it adds | Effort |
|---|---|---|---|---|
| **Tatoeba DE** | https://tatoeba.org/eng/downloads | CC-BY 2.0 FR | ~200k+ German example sentences, many tagged for difficulty / native-speaker-confirmed. Per-word indexing trivial. Replaces / augments sparse Wiktionary examples. | 0.5 day |
| **Wiktionary "Verzeichnis:Deutsch/Fehlschreibungen"** | https://de.wiktionary.org/wiki/Verzeichnis:Deutsch/Fehlschreibungen | CC-BY-SA 4.0 | Clean replacement for the Tacke/Menzel `100/300/400 Fehler` list. | 0.5 day |
| **Wikipedia "Liste häufiger Rechtschreibfehler"** | https://de.wikipedia.org/wiki/Wikipedia:Liste_h%C3%A4ufiger_Rechtschreibfehler | CC-BY-SA 4.0 | Same role as above; complementary coverage. | (combined with above) |
| **Bundesländer Grundwortschätze (Hessen, BW, RLP, Bayern, Sachsen, S-H)** | gov ministries, see LICENSES.md | Public administrative material, attribution typical | Per-Bundesland tags. Widens grade coverage; lets teachers filter by their state. ~500–870 words each, 70-80 % overlap with NRW but the diff is pedagogically interesting. | 1 day total |
| **DWDS Häufigkeitsklassen** | https://www.dwds.de/lemma/csv | ✅ **CC-BY-SA 4.0** — the DWDS-Lemmadatenbank is explicitly CC-BY-SA-4.0 per dwds.de/lemma/list (NB: the general site ToS / TDM-reservation restrict the *corpora*, not this separately-licensed lemma DB) | log-frequency class per lemma. **Done** — `frequency_json.dwds`. | done |
| **Wiktionary "Liste falscher Freunde"** (DE↔EN) | https://de.wiktionary.org/wiki/Verzeichnis:Deutsch/Falsche_Freunde | CC-BY-SA 4.0 | False-friend warnings for the EN learning-mode (when DE-speaker is learning EN, or vice versa). | 0.5 day |

### Priority 2 — integrate ONLY if a clear no-NC data license is verified first

Default = **skip** until the *data* license (not just the code license) is
confirmed non-commercial-OK. Record the per-source verdict in Notes as checked.

| Source | License (verified 2026-05-29) | Verdict |
|---|---|---|
| **DWDS Wortprofil API** (collocations) | ⚠️ **separate product — verify** | The DWDS-**Lemmadatenbank** is explicitly CC-BY-SA 4.0 (see note), but that grant covers the lemma list, NOT necessarily the *Wortprofil* collocations. Check `dwds.de/wortprofil` terms before using; the general site ToS/TDM-reservation restrict corpus content. |
| **LanguageTool DE rule patterns** | ✅ **LGPL-2.1** (commercial OK; rule files in-repo) | OK to extract per-word "triggers rule X" tags. Low-medium value. |
| **Hunspell DE (igerman98)** | ✅ **GPL-2.0/3.0** (commercial OK; verified igerman98 README) | OK — DE DB is already GPL-3.0, so no new license exposure. Systematic plural/conjugation fallback. |
| **OPUS DE corpora** | ⚠️ per-corpus, mixed (some CC-BY-SA, some NC) | Skip for v1 — diminishing returns over HermitDave/Leipzig; would need per-corpus license checks. |

### Stronger candidates than Priority 2 (added 2026-05-29)

| Source | License (verified) | Benefit |
|---|---|---|
| **Wiktionary EN→DE translations** (local `en_wiktionary_normalized.db`, 156,732 de rows) | ✅ CC-BY-SA 4.0 | ✅ **DONE 2026-05-29** — `add_translations_en.py` filled the EN `translations` table (0 → 9,317 across 8,112 words). |
| **Wikidata Lexemes** | ✅ **CC0** (public domain) | Inflection forms, senses, IPA, and DE↔EN translations, multilingual. Ideal license. Could fill inflection/translation gaps in both DBs. ~1-2 days (SPARQL/dump). |
| **Tatoeba EN** | ✅ CC-BY 2.0 | More EN example sentences (the DE DB already uses Tatoeba). Medium value — EN already has Wiktionary + Gutenberg + LLM examples. ~0.5 day. |

### Priority 3 — ✅ decision: SKIP (NC clauses / paid / academic-only)

| Source | Issue |
|---|---|
| MERLIN Corpus (CEFR-leveled German learner texts) | CC-BY-NC-SA — NC blocks commercial |
| GermaNet (academic German WordNet) | €200 academic + NC for commercial — OdeNet covers it already (free CC-BY-SA equivalent) |
| Tüba-D/Z, deWaC, Falko Korpus | Academic-only / NC |
| CELEX2 | Paid commercial license |
| MERLIN, KOLAS, DGS-Korpus | NC clauses |

### childLex (GPL-3.0) — ✅ ALREADY INTEGRATED

| Source | URL | License | Status |
|---|---|---|---|
| **childLex** (Schroeder et al., HU Berlin) | https://childlex.de + https://osf.io/tqgjs | **GPL-3.0** | **Shipped** — `add_childlex_norms.py`; 9,008 entries carry `frequency_json.childlex` age-band norms (ages 6–8 / 9–10 / 11–12) |

**Licensing — ✅ resolved 2026-05-29: the DE DB is declared GPL-3.0.** Because
childLex (GPL-3.0) is bundled and GPL-3.0 content can't be redistributed under
CC-BY-SA-4.0 (one-way compatible), the **combined German DB is GPL-3.0**; the
**English DB stays CC-BY-SA-4.0** (no GPL data). App code stays proprietary;
pipeline scripts stay MIT. Propagated to `DATA_LICENSE.md`, `README.md`, and
the in-app license registry (which already declared the GPL-3.0 posture).

### What actually remains (2026-05-29)

Priority 1 + EN→DE translations + the False Friends game (#48) are all done.
The remaining Priority-2 sources were assessed and **deferred** (low value /
high effort) — see the consolidated **Remaining work** table at the top of
this file for the per-item rationale.

### Falsche Freunde — ✅ DONE (2026-05-29)

Curated DE↔EN false friends (62 pairs; correct, common, K-6+-appropriate —
the raw Wikipedia/Wiktionary lists have errors + vulgar entries). Reference:
Wikipedia "Liste falscher Freunde" (CC-BY-SA 4.0 → EN DB stays CC-BY-SA).
`pipeline/voc-en/add_false_friends_en.py` → `false_friends` table in the EN DB
(55/62 linked to a `words` row). Dart: `FalseFriend` model +
`DictionaryDatabaseService.getFalseFriends()` + `VocabularyService.getFalseFriends()`
+ 3 unit tests. Shipped in `grundwortschatz_en.db.gz`.

---

## 8. Pre-launch: copyleft compliance for App Store / Play Store release

**License posture (2026-05-29):** DE DB = **GPL-3.0** (bundles childLex), EN DB
= **CC-BY-SA-4.0**. App code proprietary; pipeline scripts MIT.

**Triggering event**: the moment we submit to Apple App Store or Google
Play, the app reaches a meaningfully wider audience and the copyleft
obligations on the shipped DBs become operationally important. The current
Vercel deployment is technically already a "distribution", but exposure
is low. **All of the below should be done before the first store
submission.** (Most boxes below are already ticked — verify, don't redo.)

### 8.1 Why the DBs are copyleft (DE GPL-3.0 / EN CC-BY-SA-4.0)

Both DBs inherit copyleft from upstream content:

| Upstream | What it contributes |
|---|---|
| **Wiktionary (DE/EN)** | Definitions, IPA, inflections, examples, etymology, syn/ant, hyper/hypo/mero/holo (~all enrichment_json content) — CC-BY-SA |
| **ConceptNet 5.x** | Semantic relations under enrichment_json.conceptnet — CC-BY-SA |
| **OpenThesaurus / OdeNet** | Synonym closure / DE WordNet sense data — CC-BY-SA |
| **HermitDave / OpenSubtitles** | Frequency rank fields — CC-BY-SA |
| **childLex** (DE only) | **GPL-3.0** age-band norms → makes the **DE** DB GPL-3.0 |

The Flutter app code stays proprietary — only the DB blobs carry copyleft. The
**EN** DB is CC-BY-SA-4.0 (no GPL upstream); the **DE** DB is GPL-3.0 (CC-BY-SA
upstreams are forward-compatible into GPL-3.0). Same legal model as
Wikipedia/Britannica mobile apps, with GPL on the DE data blob.

### 8.2 What the copyleft licenses require (concretely)

| Requirement | How we satisfy it |
|---|---|
| **Attribution** | In-app Settings → Licenses screen (wired via `LicenseRegistry.addLicense` for every source, incl. the childLex GPL-3.0 entry). ✅ |
| **ShareAlike / copyleft** | Each DB must be redistributable under its license. **Action**: publish `grundwortschatz.db.gz` as `cstr/grundwortschatz-voc-de` marked **GPL-3.0**, and `grundwortschatz_en.db.gz` as `cstr/grundwortschatz-voc-en` marked **CC-BY-SA-4.0**; link both from the license screen. |
| **Indicate changes** | Per-source license entries already note "Changes made: …". ✅ |
| **No additional restrictions** | App EULA must not forbid extracting / redistributing the DB. The EULA note in `DATA_LICENSE.md` already exempts both blobs. ✅ |
| **Notice of license** | One-line statement on the License screen + public README — done: README states DE GPL-3.0 / EN CC-BY-SA-4.0. ✅ |

### 8.3 Pre-submission checklist

- [x] `DATA_LICENSE.md` at repo root — dual-license stance, DE GPL-3.0 / EN CC-BY-SA-4.0.
- [x] Repo README note linking to `DATA_LICENSE.md`.
- [x] In-app License screen carries every source incl. childLex GPL-3.0 + the GPL-3.0 DB posture.
- [ ] Upload the DBs as HF datasets with matching license tags:
      **`cstr/grundwortschatz-voc-de` (GPL-3.0)** and
      **`cstr/grundwortschatz-voc-en` (CC-BY-SA-4.0)**, each with full
      attribution + "Changes made" in the dataset README. *(user action — HF account)*
- [ ] Verify the eventual App Store EULA does NOT restrict extracting the DB blobs.

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
