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

## 1. DE DB safe rebuild (highest priority)

**Goal**: ship a new `assets/grundwortschatz.db.gz` that is **at least
as feature-complete as the current one** and uses **only safely-
licensed source data** — no Tacke (educational-use only), no
unidentified third-party FRESCH-overlay lists, no NC-restricted
content.

### 1.1 What changes vs the current shipped DB

| Component | Currently from | Replacement |
|---|---|---|
| Common learner errors (commonLearnerErrors) | Tacke/Menzel `100/300/400 Fehler` (educational use, not formally redistributable for commercial) | **Wikipedia "Liste häufiger Rechtschreibfehler"** + **Wiktionary "Verzeichnis:Deutsch/Fehlschreibungen"**, both CC-BY-SA 4.0. Fetcher: `00b_fetch_de_misspellings.py` |
| Spelling strategies | `532Strategien.csv` (origin unclear) | **Already replaced** — algorithmic re-derivation from NRW xlsx via `04b_derive_spelling_patterns.py` (commit ed2ebae). Dual taxonomy: 6-cat detailed + 5-cat Thomé. |
| Pedagogical wordlist (Klasse 1–4) | `739Leo.csv` (Leoschule Lünen, no formal license) | **Dropped** — coverage redundant with NRW Grundwortschatz 1L/1S/3L/3S + DWDS Goethe A1/A2/B1 + 111 NRW Merkwörter + 422 NRW Nachdenkwörter |
| Frequency rank (DE corpus) | `top10000de_unileipzig.txt` (some Leipzig sub-corpora are CC-BY-NC) | **Verify** Wortschatzlexikon's specific corpus license; if NC, drop and rely on Buchmeier20k + de_50k_hermitdave (both CC-BY-SA). |
| FRESCH labels in shipped JSON | curated overlay | Replaced by `klangtreu/doppelkonsonant/verwandt/merkwort/morphem/grossschreibung` + `basisgraphem/orthographem/morphem/merkwort/grossschreibung` (own derivation) |
| Tacke license entry in app | listed in `LicenseRegistry` | **Remove** — no Tacke content shipped after rebuild |

### 1.2 Steps to execute (runbook)

```sh
cd pipeline/voc-de
# 1. Fetch the Wikipedia + Wiktionary misspellings (replaces Tacke)
python 00b_fetch_de_misspellings.py        # → de_wiki_misspellings.csv

# 2. Verify Leipzig license posture for our specific corpus
#    (top10000de_unileipzig.txt). If CC-BY-NC, edit 01_consolidate to skip it.
#    For commercial app: probably safer to skip; coverage is OK without it.

# 3. Re-run the consolidation through DB build
#    (Filename drift caveat — see §5 for the rename chain)
python conv_xls.py                          # → output_nested.json (one-time)
python 01_consolidate_wordlists_csv.py      # → voc_de.csv
python 02_enrich_with_spacy_csv.py          # → voc_de_enriched.csv
python 03_conv_csv_to_json.py               # → grundwortschatz.json
python 04_add_nrw_data.py                   # → grundwortschatz_merged.json
python 04b_derive_spelling_patterns.py      # → grundwortschatz_merged_with_patterns.json
python filter_voc.py …_with_patterns.json grundwortschatz_safe.json
python 03a_fix_grades.py
python 05_phoneme_enricher.py
python 06_generate_grapheme_variants.py
python 11_reprocess_full_wikidict.py        # SLOW (cstr/WiktionaryDE API)
python 08_fix_word_types.py
python 12_api_wins_3.py                     # USE _3
python 13_fix_genders_manually.py
# Manually download openthesaurus_dump.sql first
python 13b_enrich_with_openthesaurus.py
python 14_convert_db_to_sqflite.py          # → grundwortschatz.db
gzip -9 grundwortschatz.db -c > ../../assets/grundwortschatz.db.gz
```

### 1.3 Validation: feature parity vs current shipped DB

Before replacing `assets/grundwortschatz.db.gz`, validate the new build
covers everything the old one did:

| Check | How |
|---|---|
| Word count ≥ 10,450 | `sqlite3 new.db 'SELECT count(*) FROM words'` |
| Per-grade distribution within ±5 % of current | same per `grade_level` |
| Translations table populated | `SELECT count(*) FROM translations` ≥ 27,000 |
| Examples table populated | `SELECT count(*) FROM examples` ≥ 24,000 |
| FTS5 search_index works | `SELECT count(*) FROM search_index('Hund')` > 0 |
| `enrichment_json` populated for >95 % | `SELECT count(*) FROM words WHERE enrichment_json != '{}'` |
| spellingStrategy populated | `SELECT count(*) FROM words WHERE enrichment_json LIKE '%spellingStrategy%'` ≥ 10,000 |
| New: spellingPatternsThome populated | same as above |
| commonLearnerErrors populated (Wikipedia-based, not Tacke) | confirm pairs come from `de_wiki_misspellings.csv` |
| In-app License screen: no Tacke entry, no FRESCH brand mention | manual check in Settings → Licenses |

### 1.4 Ship

1. Replace `assets/grundwortschatz.db.gz` with the new build.
2. Bump version: `pubspec.yaml` `version: 1.1.0+N → 1.2.0+N+1`.
3. Update Settings screen license entries: remove the Tacke entry that
   `settings_screen.dart` currently registers; the (already neutralized)
   spelling-pattern entry stays.
4. Per §3 of this plan, prepare the HF dataset mirror for CC-BY-SA
   compliance before next visible distribution.

### 1.5 What we don't have to do

- We do NOT need to drop NRW Grundwortschatz, OpenThesaurus, OdeNet,
  ConceptNet, Wiktionary, HermitDave, Buchmeier, or DWDS Goethe sets —
  all already CC-BY-SA / OGL / public-administrative.
- We do NOT need to drop spelling-pattern tagging — the algorithmic
  derivation is our own work.
- We do NOT need to drop the existing UD treebank-derived
  verb-government data — CC-BY-SA already.

**§§2–4 (EN port, CC-BY-SA, ConceptNet) and §§6–9 (improvements,
sources, housekeeping, open decisions) follow with their pre-existing
content, in the priority order stated above.**

---

## 1a. Reproducibility recipe for the historical DE DB (reference)

*Renumbered to keep the priority §§1–4 order clean; original content
unchanged. Use this as the "as-is" baseline to diff against §1's safe
rebuild output.*

The scripts are all in
`/Volumes/backups/code/voc/lib/features/games/data/`. Restore them to
this directory at `pipeline/voc-de/` before running.

### Inputs (committed in the backup folder)

Pedagogical / curriculum:
- `Grundwortschatz{1L,1S,3L,3S}.csv` — NRW Grundwortschatz, Klasse 1+3.
- `wortliste-grundwortschatz-nrw.xlsx` (+ `conv_xls.py` → `output_nested.json`).
- `A1.csv` / `.json`, `A2.csv` / `.json`, `B1.csv` / `.json` — CEFR.
- `111_NRW_Merkwörter.txt`, `422_NRW_Nachdenkwörter.txt`.

Errors (real misspellings from German children):
- `100Fehler.csv`, `200Fehler.csv`, `300Fehler.csv`, `400Fehler.txt`,
  `532Strategien.csv`, `739Leo.csv`.

Frequency:
- `Buchmeier20k.txt`, `de_50k_hermitdave.txt`, `top10000de.txt`,
  `top10000de_unileipzig.txt`, `leeds_freq.num`.

External (download / manual):
- OpenThesaurus MySQL dump (download from
  `https://www.openthesaurus.de/about/download` →
  `openthesaurus_dump.sql`).
- ConceptNet — accessed via `cstr/WiktionaryDE` Gradio Space, no local
  download needed.

### Step ladder

| Step | Script | Input(s) | Output | Notes |
|---|---|---|---|---|
| 01 | `01_consolidate_wordlists_csv.py` | all wordlists above | `voc_de.csv` | Priority dedup chain: pedagogical > BUCHMEIER > LEEDS > LEIPZIG > HERMIT. Filter ≥2 chars, alphabetic only. Use the `_old.py` for nothing — it's the predecessor. |
| 02 | `02_enrich_with_spacy_csv.py` | `voc_de.csv` | `voc_de_enriched.csv` | spaCy `de_core_news_sm`. Adds lemma, Case, Number, Gender, Degree, PronType, VerbForm. **Article column is source‑of‑truth for genus.** |
| 03 | `03_conv_csv_to_json.py` | `voc_de_enriched.csv` | `grundwortschatz.json` | Assigns `gradeLevel` (BW1=1, BW3=3, NRW111=1, A1=4, A2=5, B1=6, default 5). Computes `frequencyData` + `averageRank`. Issues `id = word_NNNNN`. |
| 03a | `03a_fix_grades.py` | `grundwortschatz_safe.json` | `grundwortschatz_safe_grades_fixed.json` | Run after the safety filter (below). Refined weights: NRW111=2, NRW422=2, LEO739=3. |
| 04 | `04_add_nrw_data.py` | `grundwortschatz.json` + `output_nested.json` | `grundwortschatz_merged.json` | Reconciles articles where Excel disagrees, attaches NRW principles. |
| (filter) | `filter_voc.py` | `grundwortschatz_merged.json` | `grundwortschatz_safe.json` | **Child‑safety LLM filter.** Groq/Together/OpenRouter fallback. Reads keys from `/Users/christianstrobele/code/.env`. Profanity list also lives in `check_conflicts.py`. |
| 05 | `05_phoneme_enricher.py` | `grundwortschatz.json` | `grundwortschatz_phonemized.json` | espeak‑ng via `phonemizer`. **Hardcodes `/opt/homebrew/lib/libespeak-ng.dylib`** — change for non‑macOS. Produces IPA + X‑SAMPA. |
| 06 | `06_generate_grapheme_variants.py` | `grundwortschatz_phonemized.json` + `grapheme.json` | `grundwortschatz_with_grapheme_variations.json` | Feeds spelling‑game distractors with probabilities. |
| 07 | (skip — use 11) | | | All three 07_* variants (`enrich_wikt`, `enrich_hf`, `enrich_hf_with_hyphenation`) are subsets of 11. For a fresh rebuild, skip 07 entirely. |
| 08 | `08_fix_word_types.py` | enriched JSON | `<input>_fixed.json` | When `apiEnrichment.primary_pos` disagrees with our `wordType`, overwrite. |
| 09 | (skip — use 14) | | | The first‑pass `09_build_db.py` is for diagnostics only; `14_convert_db_to_sqflite.py` is the shipped builder. |
| 10 | `10_english_only_2.py` | `..._v24.json` | `..._only_english.json` | Trims `wiktionary_translations` to English‑only. Use the `_2` variant; `10_only_english.py` is for the v23 file. |
| 11 | `11_reprocess_full_wikidict.py` | `grundwortschatz_safe.json` | `grundwortschatz_safe_enriched_v24.json` | **The canonical enrichment step.** Calls `cstr/WiktionaryDE /analyze_word` for every word with `--no-limits`. V24 fields: hyphenation, expressions, proverbs, entryNotes, hypernyms, hyponyms, holonyms, meronyms, coordinate_terms, derived_terms, related_terms, translations, inflections, IPA, definitions, examples, synonyms, antonyms, ConceptNet relations, OdeNet senses. |
| 12 | `12_api_wins_3.py` | `..._v24.json` | `..._v24_consolidated.json` | **Use `_3` only.** Lifts API‑derived genus/article/plural/lemma/audio to top level; promotes V24 fields. Conservative: only fills empty fields. Versions `_1` and `_2` would corrupt genus. |
| 13 | `13_fix_genders_manually.py` | `..._v24_consolidated.json` | overwrites in place + `_backup.json` | Hand‑curated `MANUAL_FIXES` dict for ~95 words where v12 conflict logs showed wrong existing data. |
| 13b | `13b_enrich_with_openthesaurus.py` | `..._v24.json` + `openthesaurus_dump.sql` | `..._v24_with_thesaurus.json` | Parses the OpenThesaurus MySQL dump for synsets, hypernym/hyponym/associations. Attaches under `apiEnrichment.openThesaurus`. |
| 14 | `14_convert_db_to_sqflite.py` | `..._v24_with_thesaurus.json` | `grundwortschatz.db` | Final ship‑DB. Schema: `words` (with JSON blobs `frequency_json`, `enrichment_json`, `metadata_json`), `translations`, `examples`, FTS5 virtual table `search_index` + triggers. |
| (ship) | `gzip -9 grundwortschatz.db -c > ../../assets/grundwortschatz.db.gz` | | | Shipped DB. |

### Step 01 priority dedup chain (for reference)

```
pedagogical (Grundwortschatz 1L/1S/3L/3S, A1/A2/B1, NRW 111, NRW 422,
             100/200/300 Fehler, 532 Strategien, 739 Leo)
> BUCHMEIER (Buchmeier20k.txt — children's book corpus)
> LEEDS (leeds_freq.num — Leeds DE corpus)
> LEIPZIG (top10000de_unileipzig.txt — Uni Leipzig corpus)
> HERMIT (de_50k_hermitdave.txt — HermitDave frequency project)
```

Lower‑priority lists only fill in words the higher‑priority lists don't
cover.

### Wall time

On a recent laptop with `cstr/WiktionaryDE` warm:
- Steps 01–06: minutes total.
- `filter_voc.py`: 30–60 min, dominated by LLM API latency.
- Step 11 (V24 reprocess): 2–6 h. Dominated by Gradio Space throughput.
- Steps 12–14: minutes.

Total: ~3–8 h.

### Filename‑drift caveat

The scripts do **not** rename outputs to match the next step's input. You
must rename in between. The canonical drift chain is:

```
grundwortschatz.json
  → grundwortschatz_safe.json            (after filter_voc)
  → grundwortschatz_safe_enriched_v22a.json  (after old 07a)
  → grundwortschatz_safe_enriched_v23.json   (after 07b)
  → grundwortschatz_safe_enriched_v24.json   (after 11)
  → grundwortschatz_v24_consolidated.json    (after 12_3)
  → grundwortschatz_v24_with_thesaurus.json  (after 13b)
  → grundwortschatz.db                       (after 14)
```

See LEARNINGS.md for why this drift happened and how to avoid it in the
EN pipeline.

---

## 2. Build the EN DB at DE parity

**Goal:** ship `assets/grundwortschatz_en.db.gz` with the same schema and
the same enrichment richness as DE — definitions, IPA, irregular plurals,
verb conjugations, synonyms, antonyms, hypernyms, hyponyms, meronyms,
ConceptNet relations, examples, common learner errors, grapheme variants,
grade levels 1–6.

### Decisions (locked in)

| Decision | Value | Rationale |
|---|---|---|
| Canonical English variant | **UK English** | Aligns with the Year 1–6 statutory spelling lists (the EN pedagogical analogue of NRW Grundwortschatz). US spellings (`color`, `gray`, `-ize`) carried as `commonLearnerErrors` for users from US-influenced contexts. |
| Vocabulary size | **10k, filterable** | Match DE size. Each word tagged so the app can show 3k / 5k / 10k subsets without rebuilding. |
| Grade mapping | **UK Y1–6 primary, CEFR + AoA-Kuperman as fallback** | UK Year is the pedagogical primary (same role as `Grundwortschatz1L/3L` for DE). CEFR + AoA-Kuperman fill gaps for words outside the UK statutory list. All three carried as tags. |
| Reverse translations | **Yes, where available** | German speakers learning English is the primary EN use case. Translation table populated with DE entries where Wiktionary has them. |

### What's already done (don't re‑do)

- **EN lexical backbone on HF** —
  `cstr/en-wiktionary-extracted-all` (raw wiktextract JSONL),
  `cstr/en-wiktionary-sqlite-all` (lossless normalized SQLite, 1.24 M
  entries). Built by VPS scripts `wikt-en.sh` + `norm_all_6_en.py`.
- **EN linguistics hub** — `cstr/WiktionaryEN` Gradio Space, currently
  **RUNNING**. Exposes `/analyze_word` with the same shape as
  `cstr/WiktionaryDE`. Backends: Wiktionary + HanTa + Stanza + NLTK +
  TextBlob + OEWN + OpenBLP + ConceptNet.
- **ConceptNet** — `en` is already in `cstr/conceptnet-normalized-multi`,
  no separate build needed.
- **Frequency seeds** — `top1000en.txt`, `top10000en.txt` at repo root.

### What we don't yet have

| Layer | DE source | EN substitute |
|---|---|---|
| Pedagogical wordlists | NRW Grundwortschatz 1L/1S/3L/3S, A1/A2/B1, Fehler CSVs | Oxford 3000™/5000™, **English Vocabulary Profile** (CEFR), Dolch 220, Fry 1000, **UK Y1–6 statutory spelling lists**, Common Core K‑5 |
| Frequency corpora | Leipzig, Buchmeier20k, de_50k_hermitdave, leeds_freq | **SUBTLEX‑US** (with Age‑of‑Acquisition!), en_50k_hermitdave, Google 1‑gram, AoA‑Kuperman 2012 |
| Spelling "Merkwörter" | 111_NRW_Merkwörter, 422_NRW_Nachdenkwörter | UK National Curriculum statutory lists per year + Wikipedia "Lists of commonly misspelled English words" |
| Common learner errors | 100/200/300 Fehler CSVs | Birkbeck Spelling Error Corpus, Wikipedia common misspellings, Hunspell affix‑mutated typos |
| Genus / article | der/die/das | Drop genus, keep `article` nullable; populate with `a`/`an`/`the` for nouns |
| Compound words | Wortbaumeister (rich) | Sparse in EN — replace as primary game mode (firetruck/breakfast etc) |
| Separable verbs | Verbtrenner | **Phrasal verbs** — multi‑word, requires `enrichment_json.phrasalVerb` field |
| Capitalization | Großschreibung | Different rules — replace with homophone game (their/there/they're) |

### EN pipeline, step by step (mirror of DE 01–14)

```
01_consolidate_en.py        merge Oxford3k+EVP+Dolch+Fry+UK statutory + commonly‑misspelled
                            priority: pedagogical > SUBTLEX‑US > en_50k_hermitdave
02_enrich_with_spacy_en.py  en_core_web_sm → lemma, POS, morphology (no genus)
03_conv_csv_to_json_en.py   grade_level via Dolch/Fry/AoA‑Kuperman + CEFR fallback
04_add_uk_spelling_lists.py UK Year 1–6 statutory + spelling‑rule tags
                            (silent‑e, magic‑e, doubled consonant, vowel teams, etc.)
                            — NRW analogue
05_phoneme_enricher_en.py   phonemizer lang=en-us OR (better) CMU dict join → ARPAbet + IPA
06_generate_grapheme_variants_en.py
                            EN grapheme.json: digraphs (sh/ch/th/ph/ck/qu),
                            silent letters (gh/kn/wr), vowel teams (ea/ee/ai/oa/ou/ow),
                            doubled consonants, e‑drop on suffixing
07_enrich_WiktionaryEN.py   gradio_client → cstr/WiktionaryEN /analyze_word with V24 fields
                            (defs, IPA, irregular plurals, conjugations, syn/ant,
                             hyper/hypo/mero/holo, ConceptNet, examples, frequency, etymology)
08_fix_word_types_en.py     reconcile spaCy POS vs API primary_pos
09_build_db_en.py           same schema; article nullable, genus always NULL
10_only_german_translations.py
                            keep EN→DE only (mirror use case: German speakers learning EN)
11_reprocess_full_wikidict_en.py   full V24 sweep against cstr/WiktionaryEN
12_api_wins_en.py           lift API‑derived plural/lemma/audio; no genus to lift
13_fix_word_types_manually.py     hand‑curated POS edge cases
                            (run/walk/break are noun‑or‑verb)
13b_enrich_with_wordnet.py  OEWN/Princeton WordNet → synsets, hypo/hypernym closure
                            — OpenThesaurus analogue
                            (may be merged into 07/11; OEWN already in cstr/WiktionaryEN)
14_convert_db_to_sqflite_en.py    → assets/grundwortschatz_en.db.gz
```

Ship as a **separate file**, not a merged multi‑lang DB. Keeps the gzip
small, lets the user defer the EN download. `VocabularyService` already
swaps based on selected language.

### Schema compatibility (cross‑lingual)

The current DE schema is mostly language‑agnostic — keep it:

- `words.article`: nullable. EN nouns get `a`/`an`/`the` attached when the
  game needs them (`a apple` problem handled by determiner rules baked
  into `enrichment_json`).
- `words.genus`: NULL for EN. Don't drop — keeps the schema reusable for
  future FR / IT / ES ports.
- `words.word_type`: **canonicalize to English tokens at step 14**
  (`noun`/`verb`/`adjective`/`adverb`/`pronoun`/`preposition`/
  `conjunction`/`interjection`/`article`/`numeral`/`particle`). DE
  currently uses `substantiv`/`adjektiv` — translate at build time and
  keep `metadata.original_word_type_de` if the German form is ever
  needed.
- `enrichment_json`: same shape. EN‑specific additions:
  - `phrasalVerb` (object: `particle`, `meaning`, `examples`)
  - `capitalizationCategory` (`proper` / `common`)
  - `spellingRule` (silent‑e, magic‑e, doubled‑consonant, etc.)

### Game adaptations (minimum to ship EN)

#### App architecture: 2×N matrix (L2L × GUI)

**Single app, both DBs bundled.** Two orthogonal axes:

| Axis | Picks | Setting key | Already done? |
|---|---|---|---|
| L2L (language to learn) | which `grundwortschatz_*.db.gz` to load | `learning_language` (new) | partial — needs `VocabularyService.initialize(l2l)` parameterization |
| GUI language | which `app_*.arb` to render | `locale` (existing) | done — `flutter_localizations` handles it |

Bundle size: DE DB 28 MB + EN DB ~25–35 MB → ~60 MB compressed assets. Under Apple/Play size caps; no on‑demand download plumbing needed.

#### Game compatibility matrix

| Game | L2L=de | L2L=en | Notes |
|---|---|---|---|
| `space_word_rescue` (spelling) | ✅ | ✅ | Language‑agnostic given DB |
| `word_find` (word search grid) | ✅ | ✅ | Language‑agnostic |
| `word_sort` (Noun/Verb/Adj) | ✅ | ✅ | Categories via ARB |
| `wortbaumeister` (compounds) | ✅ | ⚠️ small pool | EN compounds rare but real (firetruck, breakfast); pool ~10× smaller — keep but flag |
| `großschreib` (capitalization) | ✅ | ❌ | DE‑specific rule |
| `großstadt` (capitalization in context) | ✅ | ❌ | DE‑specific rule |
| `verbtrenner` (separable verbs) | ✅ | ❌ | DE morphology |
| `phrasal_verbs` *(new, EN)* | ❌ | ✅ | EN equivalent of `verbtrenner`; same falling‑tile mechanic |
| `homophones` *(new, EN)* | ❌ | ✅ | their/there/they're, your/you're, its/it's |
| `word_memory`, `word_builder`, `word_type_whirl` | ✅ | ✅ | Language‑agnostic |

8 shared games + 3 DE‑only + 2 new EN‑only = 10 game modes per L2L. Equivalent pedagogical depth.

#### Implementation sketch

```dart
// lib/core/services/vocabulary_service.dart
class VocabularyService {
  static const _dbAssets = {
    'de': 'assets/grundwortschatz_de.db.gz',
    'en': 'assets/grundwortschatz_en.db.gz',
  };
  Future<void> initialize(String learningLanguage) async {
    final assetPath = _dbAssets[learningLanguage]!;
    // existing decompress + open code, parameterized on assetPath
  }
}

// lib/features/games/registry.dart  (new)
class GameDescriptor {
  final String key;
  final List<String> supportedL2L;
  final SkillCategory skill;
}
final kGameRegistry = <GameDescriptor>[
  GameDescriptor(key: 'space_word_rescue', supportedL2L: ['de','en']),
  GameDescriptor(key: 'großschreib',       supportedL2L: ['de']),
  GameDescriptor(key: 'phrasal_verbs',     supportedL2L: ['en']),
  // ...
];

// Home menu filters: kGameRegistry.where((g) => g.supportedL2L.contains(currentL2L))
```

**Migration plan for existing DE users:** default `learning_language='de'` on first launch after the EN release so behavior is unchanged. Add an L2L picker in Settings → "Sprache, die ich lernen möchte".

#### Vocabulary subset filtering (the "10k filterable")

Each word carries multiple tags so the app can show subsets without rebuilding:

```jsonc
// inside enrichment_json
{
  "tags": ["oxford3k", "evp", "uk_y2_statutory", "dolch_220"],
  "cefr": "A2",
  "uk_year": 2,
  "aoa_kuperman": 7.4
}
```

Home‑screen scope toggle (extend the existing difficulty picker):

- **Core 3k** (default for ages 6–10) — `oxford3k`
- **Extended 5k** — `oxford3k + evp + oxford5k`
- **Full 10k** — everything

`grade_level` stays primary (UK Y1–6 → G1–G6). CEFR shows as a secondary chip. Mirrors the DE multi‑source consolidation pattern (different German Bundesländer lists feed into one canonical grade, source tags survive).

#### Other UI adjustments

- ARB: `app_en.arb` needs the new game labels (`phrasal_verbs`, `homophones`, L2L picker, scope toggle). Voc currently inlines DE strings; English chrome ARB exists, extend it.
- `großschreib` / `großstadt`: hide from menu when `L2L=en`. No banner needed — the filtered menu is self‑explanatory.

### Effort estimate

| Block | Effort |
|---|---|
| Sources gathered + cleaned | 1–2 days |
| Pipeline scripts ported (mostly mechanical) | 3–5 days |
| API enrichment run (`cstr/WiktionaryEN`) | 1–2 days wall time |
| WordNet step (13b) | 0.5 day, may merge into 11 |
| DB + sqflite ship | 0.5 day |
| Game UI adjustments | 1–2 days |
| **Total** | **~2 weeks** focused |

A 3,000‑word v1 (Oxford 3000 + Dolch + Fry) ships in half that.

### Source URLs (free or research‑use)

- Oxford 3000/5000 — `https://www.oxfordlearnersdictionaries.com/wordlists/oxford3000-5000`
- English Vocabulary Profile (CEFR) — `https://www.englishprofile.org/`
- Dolch 220 — public domain, multiple mirrors
- Fry 1000 — public domain
- SUBTLEX‑US — `https://www.ugent.be/pp/experimentele-psychologie/en/research/documents/subtlexus`
- AoA‑Kuperman 2012 — `http://crr.ugent.be/archives/806`
- UK Year 1–6 statutory spelling — `https://www.gov.uk/government/publications/national-curriculum-in-england-english-programmes-of-study`
- Commonly misspelled — `https://en.wikipedia.org/wiki/Wikipedia:Lists_of_common_misspellings`
- CMU dict — `https://github.com/cmusphinx/cmudict`
- HermitDave en_50k — `https://github.com/hermitdave/FrequencyWords`
- Birkbeck Spelling Error Corpus — Roger Mitton, mirrored on `https://www.dcs.bbk.ac.uk/~ROGER/corpora.html`

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

`hf_REDACTED_ROTATED_TOKEN` was committed to VPS_2
(`/root/.bash_history`) in plaintext via `export HF_TOKEN=...` and `./run_wiktionary_extract.sh`. Anyone who reads that file gets the token.

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

These block forward progress. Numbers reference the section above.

### EN port (§2) — resolved 2026‑05‑21

1. ✅ Canonical: **UK English**. US spellings carried as `commonLearnerErrors`.
2. ✅ Size: **10k, filterable**. Build full 10k, ship full 10k, app filters by tag (oxford3k / extended 5k / full 10k).
3. ✅ Grade mapping: **UK Y1–6 primary**, CEFR + AoA‑Kuperman fallback, all three carried as tags.
4. ✅ Reverse translations: **yes**, where Wiktionary has them.
5. ✅ App shape: **single app, both DBs bundled**, L2L × GUI matrix (see §2 Implementation sketch).

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
| **childLex** (Schroeder et al., HU Berlin) | https://childlex.de | "Frei verfügbar für nicht-kommerzielle Forschung" on the project page — **likely NC** for commercial use; ask the authors. | Would be the single most impactful add for K–6 grade accuracy if license is OK. Deferred until written permission. |

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
- EN port: backbone done on HF → **~2 weeks** of laptop-side scripting.
- ConceptNet expansion: ~½ day code + 4–10 h compute → **~6–8 GB** all-languages DB sibling.
- Spelling-pattern classifier v2: extend beyond NRW + primary-pick + dual taxonomy (§6) — ~2 days.
- 7 additional free-licensed data sources to add (§7).
- **CC-BY-SA compliance pre-store-submission (§8) — half-day, must be done before App Store.**
- One leaked credential to rotate.
