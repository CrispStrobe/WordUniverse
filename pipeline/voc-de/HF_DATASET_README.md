---
license: gpl-3.0
language:
- de
- en
task_categories:
- text-classification
- token-classification
- translation
size_categories:
- 10K<n<100K
tags:
- german
- vocabulary
- grundwortschatz
- orthography
- rechtschreibung
- primary-school
- education
- lexical-database
- frequency
- childlex
- dwds
- wiktionary
- conceptnet
- openthesaurus
- odenet
pretty_name: WortUniversum — German primary-school Grundwortschatz with multi-corpus enrichment
configs:
- config_name: default
  data_files:
  - split: words
    path: words.parquet
  - split: translations
    path: translations.parquet
  - split: examples
    path: examples.parquet
---

# WortUniversum German Vocabulary Database

> Status: **published** at
> [`cstr/grundwortschatz-voc-de`](https://huggingface.co/datasets/cstr/grundwortschatz-voc-de)
> (GPL-3.0). The shipped SQLite asset lives at `assets/grundwortschatz.db.gz` in
> the [WortUniversum / words-universe](https://github.com/CrispStrobe/words-universe)
> repository; this dataset is its CC-BY-SA→GPL-3.0 re-distribution form. Rebuild
> + re-push with `pipeline/build_hf_datasets.py --upload`.

## Dataset summary

A curated, enriched lexical database of **10,450 German lemmas** covering
the primary-school *Grundwortschatz* (basic vocabulary) used across
German Bundesländer, with extensive per-word annotation including:

- definitions, IPA, inflections, hyphenation
- example sentences (~24,500)
- English translations (~27,500)
- ConceptNet semantic relations
- OpenThesaurus / OdeNet synonyms, hypernyms, hyponyms, meronyms
- multi-corpus frequency rank (HermitDave / Buchmeier / Leipzig / Leeds)
- DWDS Häufigkeitsklasse (7-level frequency band 0–6)
- **childLex age-graded norms** (Klasse 1-2 / 3-4 / 5-6 frequency)
- dual spelling-pattern taxonomies (6-cat detailed + 5-cat broad)
- per-Bundesland source attribution and per-Bundesland orthographic-pattern category labels
- Wikipedia-derived common-misspelling pairs

The dataset is built bottom-up from CC-BY-SA-4.0 and GPL-3.0 upstream
sources; see [License & attribution](#license--attribution) below.

## Languages

- **de** (German) — primary, all lemma content
- **en** (English) — translations only

## Dataset structure

The dataset is shipped as a SQLite database (`grundwortschatz.db.gz`,
~19 MB compressed, ~122 MB uncompressed). It is also exportable to
Parquet via the bundled converter (see *Loading*, below).

### Tables

#### `words` (10,450 rows)

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Surrogate key |
| `original_id` | TEXT UNIQUE | Stable pre-build identifier |
| `word` | TEXT | Surface form (may be inflected) |
| `lemma` | TEXT | Canonical lemma |
| `article` | TEXT | `der` / `die` / `das` for nouns |
| `genus` | TEXT | grammatical gender |
| `word_type` | TEXT | spaCy POS-coarsened category |
| `grade_level` | INTEGER | 1–6, NRW Grundwortschatz / DWDS Goethe-derived |
| `audio_path` | TEXT | (optional) audio asset key |
| `frequency_json` | TEXT (JSON) | Per-corpus frequency / rank — see below |
| `enrichment_json` | TEXT (JSON) | Definitions, IPA, examples, inflections, syn/ant, hyper/hypo, ConceptNet, OpenThesaurus, spelling-pattern taxonomies, misspelling pairs |
| `metadata_json` | TEXT (JSON) | Source attribution, per-Bundesland category labels, spaCy morphology |

#### `translations` (27,587 rows)

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Surrogate key |
| `word_id` | INTEGER FK → `words.id` | Parent lemma |
| `lang_code` | TEXT | ISO 639-1, e.g. `en` |
| `translation` | TEXT | Target translation |

#### `examples` (24,471 rows)

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Surrogate key |
| `word_id` | INTEGER FK → `words.id` | Parent lemma |
| `sentence` | TEXT | German example sentence |

#### `search_index` (FTS5 virtual table)

Full-text search index over `words.word`, `words.lemma`, and aggregated
translations. Backed by `words` table content (`content=words`).

### Key JSON fields

#### `frequency_json`

```jsonc
{
  "buchmeier":  {"rank": 223,  "frequency": 14405},      // EN Wiktionary user namespace (Matthias Buchmeier)
  "hermit":     {"rank": 197,  "frequency": 95349},      // HermitDave / OpenSubtitles 2018
  "leipzig":    {"rank": 644},                            // Wortschatz Leipzig (rank only)
  "leeds":      {"rank": 367,  "frequency": 192.03},     // Leeds Corpora
  "dwds":       {"frequenzklasse": 4, "wortklasse": "Substantiv"},  // 7-level band 0-6
  "childlex":   {"age1_freq_norm": 679.4, "age2_freq_norm": 627.1, "age3_freq_norm": 605.4}
                                                          // childLex norms by age band
}
```

#### `enrichment_json`

```jsonc
{
  "primary_pos": "noun",
  "primary_lemma": "Mutter",
  "definitions": ["weiblicher Elternteil …", "weibliches Tier …", …],
  "inflections": [{"form_text": "Mütter", "tags": "nominative, plural"}, …],
  "pronunciation": [{"ipa": "[ˈmʊtɐ]", "audio": "De-Mutter.ogg"}, …],
  "examples":  [{"text": "Sie ist die Mutter von zwei Kindern.", "ref": "...", "year": 2017}, …],
  "hyphenation": ["Mut-ter"],
  "expressions": [{"expression": "bei Mutter Grün schlafen"}, …],
  "proverbs":    [{"proverb": "Vorsicht ist die Mutter der Porzellankiste"}, …],
  "synonyms":    ["Mama", "Mutti", …],
  "antonyms":    ["Vater", "Kind", …],
  "hypernyms":   [{"hypernym_word": "Elternteil"}, …],
  "hyponyms":    [{"hyponym_word": "Großmutter"}, …],
  "conceptnet":  [{"relation": "RelatedTo", "target": "bemuttern", "weight": 2.0}, …],
  "openThesaurus": [{"synonyms": [...], "associations": [...], "categories": [...]}, …],
  "wiktionary_translations": [{"lang": "Englisch", "word": "mother", …}, …],

  "spellingStrategy":          ["doppelkonsonant", "grossschreibung"],
  "spellingStrategyPrimary":   "doppelkonsonant",
  "spellingExplanation":       "Nach einem kurzen Selbstlaut steht der doppelte Mitlaut zwischen den Silben: „Mut-ter". Du hörst ihn nur einmal.",
  "spellingStrategySource":    "principle_based_v3",
  "nrwLinguisticFeatures":     ["Artikel.die", "morphematisches Prinzip.Umlautung.ü", …],
  "commonLearnerErrors":       [{"error": "Mütterr", "source": "wiki_haeufige_falschschreibungen"}]
}
```

Spelling-strategy taxonomy (science-grounded — see
`pipeline/voc-de/SPELLING_STRATEGY_SPEC.md`):

- **`spellingStrategy`** / **`spellingStrategyPrimary`** — one or more of **7**
  neutral linguistic categories, each mapping to an orthographic principle of
  German (Eisenberg/Fuhrhop, Maas, Gallmann, Schmidt/Fuhrhop, the amtliches
  Regelwerk, and Günther Thomé's Basisgrapheme-vs-Orthographeme inventory):
  `klangtreu` (phonographisch / Basisgraphem), `doppelkonsonant` (Schärfung —
  all short-vowel doublings, `Tasse`=`Mann`), `dehnung` (long-vowel marking:
  Dehnungs-h, aa/ee/oo, ie, silbentrennendes-h), `verwandt` (Stammkonstanz:
  Auslautverhärtung + Umlaut), `morphem` (prefix/suffix/separable particle/noun
  compound), `merkwort` (etymological exception: v→[f], ch→[k]),
  `grossschreibung` (nouns).
- **`spellingExplanation`** — a per-word German explanation of the strategy
  (e.g. „Verlängere: Mann → Männer"; „zusammengesetzt: Haus + Tür"), with a
  category template fallback.

Derived algorithmically from each word's own enrichment (hyphenation,
inflections, IPA) by `spelling_strategy_classifier.py`
(`spellingStrategySource: "principle_based_v3"`). The `nrwLinguisticFeatures`
field is kept as provenance. (The earlier worksheet-fitted taxonomy and its
`spellingPatterns` dual view were removed.)

#### `metadata_json`

```jsonc
{
  "sources": ["A1", "BUCHMEIER", "BW1", "HERMIT", "NRW422",
              "BERLIN", "BRANDENBURG", "HESSEN", "RHEINLAND_PFALZ",
              "BAYERN", "NIEDERSACHSEN", "SCHLESWIG_HOLSTEIN"],
  "hessenCategories":          ["Lautgetreue Wörter auf -el",
                                 "Lautgetreue ableitbare Nomen mit Umlautung a – ä"],
  "rheinland_pfalzCategories": ["Lautgetreue Wörter auf -el", …],
  "bayernCategories":          ["Verbindung von Strategien zu den verschiedenen Prinzipien"],
  "schleswig_holsteinCategories": ["Themen-Wortschätze · Im Klassenraum"],

  "averageRank": 3608.5,
  "wiktionaryInflections": [...],
  "derivedTerms": [...],
  "url": "https://www.dwds.de/wb/leiten",
  "verbFormSpacy": "Fin", "numberSpacy": "Plur", …
}
```

## Source attribution (`metadata_json.sources`)

Each word's `sources` array contains tokens indicating which upstream
wordlists declared this lemma. Distribution across the 10,450 words:

| Token | Coverage | Source | License |
|---|---|---|---|
| `HERMIT` | 8,428 | HermitDave / OpenSubtitles 2018 frequency list | CC-BY-SA 4.0 |
| `BUCHMEIER` | 7,846 | Matthias Buchmeier German frequency list (EN Wiktionary user namespace) | CC-BY-SA 4.0 |
| `LEIPZIG` | 5,970 | Wortschatz Leipzig rank | facts (rank-only safe) |
| `LEEDS` | 4,162 | Leeds Corpora rank | facts (rank-only safe) |
| `B1` | 1,801 | DWDS Goethe-Zertifikat B1 lemma list | factual reference |
| `HESSEN` | 1,599 | Grundwortschatz Hessen (Hess. Kultusministerium) | §5 UrhG amtliches Werk |
| `NIEDERSACHSEN` | 1,455 | Orientierungswortschatz Niedersachsen (Nds. KuMi, 2015) | §5 UrhG amtliches Werk |
| `RHEINLAND_PFALZ` | 1,377 | Grundwortschatz RLP (Min. f. Bildung Mainz, 2021) | §5 UrhG amtliches Werk |
| `BRANDENBURG` | 1,341 | Grundwortschatz Brandenburg (LISUM, 2024) | **CC-BY-SA 4.0** |
| `BERLIN` | 1,338 | Berliner Grundwortschatz (LISUM, 2024) | **CC-BY-SA 4.0** |
| `BAYERN` | 1,087 | Grundwortschatz Bayern (ISB Bayern) | §5 UrhG amtliches Werk |
| `A1` | 802 | DWDS Goethe-Zertifikat A1 lemma list | factual reference |
| `SCHLESWIG_HOLSTEIN` | 633 | Rechtschreib-Grundwortschatz SH (SH MinBuB / IQSH, 2023) | §5 UrhG amtliches Werk |
| `A2` | 602 | DWDS Goethe-Zertifikat A2 lemma list | factual reference |
| `NRW422`, `NRW111` | 532 | NRW Grundwortschatz (Min. f. Schule u. Bildung NRW) | public administrative |
| `BW1`, `BW3` | 774 | Baden-Württemberg Grundwortschatz | public administrative |
| `FEHLER100/200/300/400` | 932 | Common-misspelling lists from Menzel 1985 (empirical study) | facts (uncopyrightable) |

## Per-Bundesland orthographic categories

For words tagged with `HESSEN`, `RHEINLAND_PFALZ`, `BAYERN`, or
`SCHLESWIG_HOLSTEIN`, an additional `{bundesland}Categories: [...]`
array preserves the source publication's own orthographic-pattern
classification:

- **`hessenCategories`** — 53 categories like `Lautgetreue Einsilber`, `Wörter mit Doppelkonsonanz`, `Funktionswörter mit Auslautverhärtung`, `Fremdwörter`, `Monatsnamen`, `Merkwörter`.
- **`rheinland_pfalzCategories`** — 40 categories (mostly mirroring Hessen, per the RLP publication's own attribution).
- **`bayernCategories`** — 43 fine-grained orthographem labels: `<er>`, `<el>`, `<ck>`, `<ie>`, `<tz>`, `<Sp>/<sp>`, etc.
- **`schleswig_holsteinCategories`** — 59 hierarchical categories: `Offene Silben · Wörter mit einfachen und komplexen Anfangsrändern`, `Themen-Wortschätze · Im Klassenraum`, `Affixe · Präfixe · Trennbare Verben · ab-`, etc.

## Algorithmic grade-band signal

The `frequency_json.childlex` field provides age-graded frequency norms
derived from childLex's 10M-token corpus of German children's literature
(Schroeder, Würzner, Heister, Geyken & Kliegl 2015):

| Field | Age | School level |
|---|---|---|
| `age1_freq_norm` | 6–8 | Klasse 1–2 |
| `age2_freq_norm` | 9–10 | Klasse 3–4 |
| `age3_freq_norm` | 11–12 | Klasse 5–6 |

Values are occurrences per million in age-appropriate reading material.
A word that appears only in `age3_freq_norm` is a candidate for
Klasse-5-6-specific vocabulary; a word with declining frequency across
age bands (e.g. *Apfel*: 162.9 → 58.0 → 33.2) is early-grades-skewed.

## License & attribution

This dataset is licensed under **GNU General Public License v3.0 or
later (GPL-3.0-or-later)**, the strongest copyleft license among its
upstream sources.

### License-cascade explanation

The dataset incorporates content from sources under both
CC-BY-SA-4.0 and GPL-3.0. Per Creative Commons' 2015
[v4-compatible decision](https://creativecommons.org/2015/10/08/v4-compatible/),
CC-BY-SA-4.0 is **one-way compatible** with GPL-3.0: combined works
must be redistributed under GPL-3.0, with attribution preserved for
every constituent CC-BY-SA-4.0 source.

### Upstream sources

| Source | License | Contribution |
|---|---|---|
| Deutsches Wiktionary | CC-BY-SA 4.0 | Definitions, IPA, inflections, examples, etymology, syn/ant, hyper/hypo |
| ConceptNet 5.x (DE) | CC-BY-SA 4.0 | Semantic relations |
| OdeNet | CC-BY-SA 4.0 | DE WordNet sense data |
| OpenThesaurus | CC-BY-SA 4.0 | Synonym / hypernym / hyponym closure |
| HermitDave/OpenSubtitles 2018 frequency list | CC-BY-SA 4.0 | Frequency signal |
| Matthias Buchmeier German frequency list | CC-BY-SA 4.0 (Wiktionary) | Frequency signal |
| Wikipedia "Liste häufiger Rechtschreibfehler" | CC-BY-SA 4.0 | Common learner errors |
| **DWDS Lemma-Datenbank** | **CC-BY-SA 4.0** | Häufigkeitsklasse 0-6 |
| **childLex 0.17.01** | **GPL-3.0** | Age-graded freq norms (Kl 1-2 / 3-4 / 5-6) |
| NRW Grundwortschatz (incl. xlsx + Merkwörter + Nachdenkwörter) | public administrative (§5 UrhG) — Min. f. Schule u. Bildung NRW | Grade tags + xlsx-derived spelling-pattern taxonomy |
| Baden-Württemberg Grundwortschatz | public administrative (§5 UrhG) — KuMi BW | Grade tags |
| Berliner Grundwortschatz (LISUM 2024) | **CC-BY-SA 4.0 explicit** | Bundesland tag |
| Brandenburger Grundwortschatz (LISUM 2024) | **CC-BY-SA 4.0 explicit** | Bundesland tag |
| Grundwortschatz Hessen 2021 | public administrative (§5 UrhG) — Hess. KuMi | Bundesland tag + orthographic categories |
| Grundwortschatz Rheinland-Pfalz 2021 | public administrative (§5 UrhG) — Min. Bildung RLP | Bundesland tag + orthographic categories |
| Orientierungswortschatz Niedersachsen 2015 | public administrative (§5 UrhG) — Nds. KuMi | Bundesland tag |
| Grundwortschatz Bayern (LehrplanPLUS) | public administrative (§5 UrhG) — ISB Bayern | Bundesland tag + orthographem categories |
| Rechtschreib-Grundwortschatz SH 2023 | public administrative (§5 UrhG) — SH MinBuB / IQSH | Bundesland tag + hierarchical categories |
| DWDS Goethe-Zertifikat A1/A2/B1 lemma lists | DWDS API redistribution of Goethe-Institut lists; factual reference | CEFR tags |
| Common-misspelling lists from Menzel 1985 | empirical facts, uncopyrightable | commonLearnerErrors seed |
| UD German treebanks (`UD_German-GSD`, `UD_German-HDT`, etc.) | CC-BY-SA 4.0 | Aggregate stats only |

### Required attributions

When redistributing or citing this dataset, include:

- Wikipedia / Wiktionary / Wikimedia Foundation (CC-BY-SA 4.0)
- ConceptNet (https://conceptnet.io/) — Luminoso Technologies + community
- OdeNet — Universität Hamburg, LT Group
- OpenThesaurus — community / openthesaurus.de
- HermitDave — github.com/hermitdave/FrequencyWords
- Matthias Buchmeier — `User:Matthias_Buchmeier/German_frequency_list-*` on EN Wiktionary
- Wortschatz Leipzig — Universität Leipzig
- DWDS / BBAW Berlin — "Digitales Wörterbuch der deutschen Sprache (DWDS), CC-BY-SA 4.0"
- **childLex** — *Schroeder, S., Würzner, K.-M., Heister, J., Geyken, A., & Kliegl, R. (2015). childLex: A lexical database of German read by children. Behavior Research Methods, 47(4), 1085–1094.* (https://osf.io/tqgjs/)
- NRW: Ministerium für Schule und Bildung des Landes NRW
- Baden-Württemberg: Kultusministerium Baden-Württemberg
- Berlin / Brandenburg: Landesinstitut für Schule und Medien Berlin-Brandenburg (LISUM)
- Hessen: Hessisches Kultusministerium
- Rheinland-Pfalz: Ministerium für Bildung Rheinland-Pfalz
- Niedersachsen: Niedersächsisches Kultusministerium
- Bayern: Staatsinstitut für Schulqualität und Bildungsforschung München (ISB)
- Schleswig-Holstein: Ministerium für Allgemeine und Berufliche Bildung, Wissenschaft, Forschung und Kultur des Landes SH; mit Mitwirkung von IQSH und der Europa-Universität Flensburg
- Menzel (1985): *Rechtschreibunterricht. Praxis und Theorie.* Seelze: Friedrich-Verlag.

### Changes made from upstream

Per CC-BY-SA-4.0's "indicate changes" requirement and GPL-3.0's
notification of modification:

- **Selection / filtering**: We retain only ~10,450 of Wiktionary's ~100k German lemmas, filtered through a multi-corpus intersection of common-vocabulary signals. Selection criteria documented in the build pipeline.
- **Schema flattening**: Wiktionary's nested JSONL structure is flattened into the `words.enrichment_json` blob with per-word fields documented above.
- **Merging**: NRW grade tags (Klasse 1-6) are merged into `words.grade_level` from the NRW Grundwortschatz xlsx; Bundesländer-specific category labels are merged from the respective state publications.
- **Algorithmic derivation**: Spelling-pattern taxonomies (`spellingStrategy`, `spellingPatterns`) are derived algorithmically from the NRW xlsx feature paths, with a surface-heuristic fallback for words outside NRW.
- **Re-encoding**: childLex .dat files were re-encoded from Latin-1 to UTF-8 for storage.
- **Source-attribution tokens**: Bundesländer membership is recorded as discrete tokens in `metadata_json.sources` to enable per-state filtering.

## Loading

### SQLite (native)

```python
import sqlite3, gzip
with gzip.open("grundwortschatz.db.gz", "rb") as fi:
    with open("grundwortschatz.db", "wb") as fo:
        fo.write(fi.read())

con = sqlite3.connect("grundwortschatz.db")
con.row_factory = sqlite3.Row
for r in con.execute("SELECT word, lemma, frequency_json FROM words WHERE word_type = 'verb' LIMIT 5"):
    print(r["word"], r["lemma"])
```

### datasets / Parquet

A Parquet export is produced by the bundled converter
`pipeline/voc-de/14_convert_db_to_sqflite.py` and made available as
companion files alongside the SQLite asset.

```python
from datasets import load_dataset
ds = load_dataset("cstr/grundwortschatz-voc-de")
print(ds["words"][0])
```

## Pedagogical / didactic context

This database powers WortUniversum, an orthography and grammar learning
app targeting German-speaking primary-school children (Klasse 1–6) and
language learners.

The spelling-strategy taxonomy (`spellingStrategy` list +
`spellingStrategyPrimary` + a per-word `spellingExplanation`) is grounded in
the orthographic principles of German (phonographisch / silbisch /
morphologisch / morphematisch / syntaktisch), per Eisenberg & Fuhrhop, Maas,
Gallmann, Schmidt/Fuhrhop, the amtliches Regelwerk, and Günther Thomé's
Basisgrapheme-vs-Orthographeme inventory. Seven neutral linguistic categories:
`klangtreu`, `doppelkonsonant`, `dehnung`, `verwandt`, `morphem`, `merkwort`,
`grossschreibung`. Derived algorithmically from each word's own enrichment
(hyphenation, inflections, IPA). Full spec + citations:
`pipeline/voc-de/SPELLING_STRATEGY_SPEC.md`.

The childLex age-graded norms and Bundesländer category labels together
provide an algorithmic basis for grade-band classification: a word
appearing only in childLex Age 3 (ages 11-12) and not in any Klasse 1-2
wordlist is a strong Klasse 5-6 candidate.

## Citation

If you use this dataset in academic work, please cite:

```bibtex
@dataset{wortuniversum_grundwortschatz_de_2026,
  title  = {WortUniversum --- German primary-school Grundwortschatz with multi-corpus enrichment},
  year   = {2026},
  url    = {https://huggingface.co/datasets/cstr/grundwortschatz-voc-de},
  note   = {SQLite/Parquet dataset combining Wiktionary, ConceptNet, OdeNet,
            OpenThesaurus, DWDS, childLex, and German Bundesländer Grundwortschätze
            under GPL-3.0. See dataset card for full attribution.}
}
```

Please **also cite the relevant upstream sources** for any specific
field you use (e.g. childLex citation for the `frequency_json.childlex`
norms; DWDS citation for `frequency_json.dwds`).

## Project links

- Build pipeline + scripts: https://github.com/CrispStrobe/words-universe/tree/main/pipeline/voc-de
- App that consumes this dataset: WortUniversum (Flutter, proprietary)
- Issue tracker / source corrections: GitHub Issues on the words-universe repo
