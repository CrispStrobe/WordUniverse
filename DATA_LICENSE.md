# Data License

## Dual-license model

This repository contains two distinct types of content with different licenses:

| Content | License |
|---|---|
| **Application source code** (`lib/`, `android/`, `ios/`, `web/`, etc.) | Proprietary — all rights reserved |
| **German vocabulary database** (`assets/grundwortschatz.db.gz`) | **GNU GPL-3.0** (bundles childLex GPL-3.0 data — see below) |
| **English vocabulary database** (`assets/grundwortschatz_en.db.gz`) | **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)** |
| **Pipeline scripts** (`pipeline/`) | MIT License (see below) |

---

## Vocabulary databases

The bundled databases inherit copyleft obligations from their upstream sources:

- **English DB (`grundwortschatz_en.db.gz`) — CC BY-SA 4.0.** All upstream
  content is CC-BY-SA / CC-BY / permissive / public-domain.
  <https://creativecommons.org/licenses/by-sa/4.0/>
- **German DB (`grundwortschatz.db.gz`) — GNU GPL-3.0.** It bundles childLex
  (GPL-3.0) age-band frequency norms. GPL-3.0 content cannot be redistributed
  under CC-BY-SA-4.0 (compatibility is one-way: CC-BY-SA-4.0 → GPL-3.0), so the
  **combined** German DB is GPL-3.0; the CC-BY-SA upstreams below are
  forward-compatible into it. <https://www.gnu.org/licenses/gpl-3.0.html>

This covers **only the bundled DB blob**. The Flutter **application code stays
proprietary** (it reads the DB at runtime — mere aggregation, not a derived
work), and the **pipeline scripts are MIT**.

### What you must do if you redistribute a DB

- **Attribution** — credit the upstream sources (listed below + the in-app
  License screen).
- **ShareAlike / copyleft** — redistribute the EN DB under CC-BY-SA-4.0 (or
  compatible), the DE DB under GPL-3.0.
- **Indicate changes** — note what was changed from the upstream data.

### Upstream sources and changes made

#### German vocabulary database (`grundwortschatz.db.gz`) — GPL-3.0

| Source | License | Contribution |
|---|---|---|
| Wiktionary (DE) | CC BY-SA 4.0 | Definitions, IPA, inflections, examples, etymology, synonyms, antonyms, hypernyms, hyponyms, related terms |
| ConceptNet 5.x | CC BY-SA 4.0 | Semantic relations (`conceptnet` field) |
| OpenThesaurus | CC BY-SA 3.0 | Synonym/hypernym/hyponym closure |
| OdeNet (German WordNet) | CC BY-SA 4.0 | Sense data, wordnet synsets |
| HermitDave / OpenSubtitles | CC BY-SA 4.0 | Frequency rank fields |
| DWDS-Lemmadatenbank | CC BY-SA 4.0 (per dwds.de/lemma/list) | `frequency_json.dwds` — Häufigkeitsklasse + Wortklasse per lemma. Attribution: "Digitales Wörterbuch der deutschen Sprache (DWDS)" |
| LiTKey corpus (Müller et al. 2021, RUB Bochum) | CC BY-SA 4.0 | `commonMistakes` — primary-school spelling errors |
| DysList (Rauschii et al. 2014) | CC BY-SA 4.0 | `commonMistakes` — dyslexic spelling errors |
| Tatoeba | CC BY 2.0 | Example sentences |
| Project Gutenberg (DE texts) | Public Domain | Example sentences |
| NRW Grundwortschatz (Baden-Württemberg curriculum) | Public domain / official government publication | Grade-level tags, curriculum membership |
| childLex (Schroeder et al., HU Berlin) | **GPL-3.0** | Age-band reading-difficulty frequency norms (`frequency_json.childlex`, 9,008 entries) — **makes the combined DE DB GPL-3.0** |

**Changes made to upstream data:**
- Filtered to ~13,000 primary-school-relevant entries
- Merged grade-level tags from NRW curriculum spreadsheet
- Derived spelling-pattern classifiers from the merged data
- Added `commonMistakes` from LiTKey and DysList corpora
- Added per-grade example sentences via LLM paraphrasing (marked with `source:llm`)
- Frequency ranking added from HermitDave/OpenSubtitles

#### English vocabulary database (`grundwortschatz_en.db.gz`) — CC BY-SA 4.0

| Source | License | Contribution |
|---|---|---|
| Wiktionary (EN) | CC BY-SA 4.0 | Definitions, IPA, inflections, examples, etymology, synonyms, antonyms; phrasal verbs (`phrasal_verbs` table); EN→DE translations (`translations` table) |
| Open English WordNet (OEWN) | CC BY 4.0 | Sense expansion, synonym/antonym sets |
| ConceptNet 5.x | CC BY-SA 4.0 | Semantic relations |
| Norvig spell-errors.txt | MIT / CC BY-SA (upstream Wikipedia) | `commonLearnerErrors` (~4,600 entries) |
| SCOWL / en-wl | MIT-like permissive | UK vs. US spelling variants |
| CEFR-J Vocabulary Profile v1.5 | CC BY-SA 4.0 | CEFR level tags |
| UK DfE statutory word lists | Open Government Licence v3.0 | Year 1–6 grade tags |
| Cambridge YLE vocabulary lists | Permissive (non-commercial restriction lifted for inclusion as tags only) | YLE level tags |
| Project Gutenberg (EN texts, pre-1928) | Public Domain | Example sentences |
| wordfreq | MIT | Frequency bands |
| Wikipedia "Liste falscher Freunde" | CC BY-SA 4.0 | `false_friends` table — curated DE↔EN false friends (reference source; pairs are factual) |

**Changes made to upstream data:**
- Filtered to ~11,500 primary-school-relevant entries (CEFR A1–B2)
- Merged grade-level estimates from UK curriculum + CEFR-J + wordfreq
- Added `commonLearnerErrors` from Norvig corpus
- Added per-grade example sentences via LLM paraphrasing (marked with `source:llm`)
- Added spelling variants from SCOWL

### Dataset availability

In compliance with the copyleft requirements, the databases are available for
download and redistribution at:

- **DE** (GPL-3.0): <https://huggingface.co/datasets/cstr/grundwortschatz-voc-de>
- **EN** (CC BY-SA 4.0): <https://huggingface.co/datasets/cstr/grundwortschatz-voc-en>

---

## Pipeline scripts — MIT License

The scripts in `pipeline/` that were used to build the databases are released
under the MIT License:

```
MIT License

Copyright (c) 2025–2026 CrispStrobe

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## App Store / Play Store EULA note

The End User License Agreement for the application does **not** restrict users
from extracting, copying, or redistributing the vocabulary database blobs
(`assets/grundwortschatz.db.gz`, `assets/grundwortschatz_en.db.gz`), as doing
so would conflict with their copyleft obligations. Users may freely
redistribute the German DB under GPL-3.0 and the English DB under CC BY-SA 4.0.
