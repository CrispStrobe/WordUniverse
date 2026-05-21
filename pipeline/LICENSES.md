# LICENSES — data‑source and tool inventory

Canonical audit of every upstream the build pipelines consume, plus every
library/tool whose output ends up in the shipped DBs. The Flutter app's
in‑app **Settings → Licenses** screen mirrors this list (registered via
`LicenseRegistry.addLicense()` in `lib/features/settings/screens/settings_screen.dart`).

If anything in this table changes, **update both this doc and that file.**

---

## Legal posture (TL;DR)

The shipped `assets/grundwortschatz_*.db.gz` blob inherits **CC‑BY‑SA 4.0**
because it incorporates substantial content from Wiktionary, ConceptNet,
OpenThesaurus, OdeNet, HermitDave/OpenSubtitles, and Wikipedia — all
CC‑BY‑SA. Implication:

- The **Flutter app code** stays under whatever license the owner chooses
  (proprietary is fine).
- The **DB file** is effectively CC‑BY‑SA and re‑distribution must
  preserve attribution + ShareAlike (the Wikipedia‑mobile‑app pattern).
- Attribution is satisfied by the in‑app Settings → Licenses screen, which
  lists every CC‑BY‑* source.

**No NC (Non‑Commercial) clauses block commercial shipment** of the
current DE DB *as long as* the questionable items below are addressed
(FRESCH‑Methode list, Leipzig commercial‑use status for raw text, and the
unidentified 739Leo.csv origin).

For the EN port, three originally‑recommended sources are NOT safe and
have been removed from the EN pipeline scaffolding: **Oxford 3000/5000,
English Vocabulary Profile, SUBTLEX‑US**.

---

## DATA SOURCES — German (used by voc-de)

### ✅ Safe (CC‑BY‑SA / CC‑BY / public administrative material)

| File / source | Provider | License | Used by |
|---|---|---|---|
| DE Wiktionary | Wikimedia Foundation | CC‑BY‑SA 4.0 | step 11 enrichment (definitions, IPA, inflections, examples, etymology, syn/ant, hyper/hypo/mero/holo) |
| ConceptNet 5.x (de) | Luminoso Technologies + community | CC‑BY‑SA 4.0 | step 11 (`enrichment_json.conceptnet`) |
| OdeNet | Universität Hamburg, LT Group | CC‑BY‑SA 4.0 | step 11 (`enrichment_json.odenet`) |
| OpenThesaurus | community / openthesaurus.de | CC‑BY‑SA 4.0 (since 2019; previously LGPL) | step 13b (synonym / hypernym / hyponym closure) |
| `de_50k_hermitdave.txt` | Matthias Buchmeier / HermitDave, derived from OpenSubtitles 2018 | CC‑BY‑SA 4.0 | step 01 frequency signal |
| `Buchmeier20k.txt` | Matthias Buchmeier (EN Wiktionary user namespace, `User:Matthias_Buchmeier/German_frequency_list-*`) | CC‑BY‑SA 4.0 (Wiktionary) | step 01 frequency signal |
| `Grundwortschatz{1L,1S,3L,3S}.csv` | Ministerium für Schule und Bildung NRW | German public administrative material — freely usable for educational purposes; courtesy attribution to MSB NRW | step 01 pedagogical core |
| `111_NRW_Merkwörter.txt` / `422_NRW_Nachdenkwörter.txt` | MSB NRW | same as Grundwortschatz | step 01, step 04 |
| `wortliste-grundwortschatz-nrw.xlsx` | MSB NRW | same as Grundwortschatz | conv_xls.py → output_nested.json → step 04 |
| `A1.csv` / `A2.csv` / `B1.csv` (DWDS-curated) | DWDS / BBAW, redistributing **Goethe‑Institut** wordlists via `https://www.dwds.de/api/lemma/goethe/{A1,A2,B1}.csv` | DWDS public API + Goethe‑Institut original lists. The lists are factual reference material (which lemmas an A1/A2/B1 learner needs); DWDS distributes them programmatically. **Acknowledge both DWDS and Goethe‑Institut.** | step 01 CEFR pedagogical signal |
| UD German treebanks (`UD_German-GSD`, `UD_German-HDT`, `UD_German-LIT`, `UD_German-PUD`) | universaldependencies.org | CC‑BY‑SA 4.0 | `verb_government*.json` (aggregate stats only) |

### ⚠️ Educational use / not formally licensed for commercial redistribution

| File / source | Provider | Status | Used by |
|---|---|---|---|
| `100Fehler.csv`, `300Fehler.csv`, `400Fehler.txt` | **Menzel, W. (1985). Rechtschreibunterricht. Praxis und Theorie. Seelze: Friedrich-Verlag** — empirical study of 2000 student essays. | **Facts.** Empirical research findings are uncopyrightable under German Urheberrecht and EU doctrine. Our build pulls only the empirical headword list, not any specific publication's example sentences / curated PDF presentation. Openly redistributed by educational orgs (e.g. Austrian Bundesverband Legasthenie at lrs-legasthenie.at) with Menzel attribution. | step 01 commonLearnerErrors seed |
| `200Fehler.csv` | RICHTIG / FALSCH pairs — likely self‑compiled or aggregated from open mirrors | Unknown / probably safe | step 01 |
| ~~`532Strategien.csv`~~ — **removed 2026-05-21** | The wordlist was the NRW Grundwortschatz (verified by exact match against `wortliste-grundwortschatz-nrw.xlsx` shared strings); the FRESCH category overlay was of uncertain provenance. **Replaced with `04b_derive_fresch_categories.py`**, which derives the six FRESCH categories algorithmically from the NRW xlsx's own linguistic-feature taxonomy (Doppelkonsonanten → Weiterschwingen, Auslautverhärtung → Ableiten, etc.). | (no longer used) |
| ~~`739Leo.csv`~~ — **removed 2026-05-21** | Confirmed source: **Leoschule Lünen** (Catholic primary school, NRW), Rechtschreibwortschatz page at `https://www.leoschule-luenen.de/index.php/rechtschreibwortschatz/`. Their list is NRW core (533) + school‑specific additions (206) = 739 words. The page carries no explicit license. The NRW 533‑word core is already covered by our other sources; the 206 school‑specific additions are not pedagogically significant enough to justify the license uncertainty. | (no longer used) |
| `Leipzig Corpora Collection` (`top10000de_unileipzig.txt`) | Universität Leipzig, Wortschatz Leipzig | Wordlists (rank/freq only) are CC‑BY for redistributable derivatives; the full corpus has per‑sub‑corpus licenses, some with NC clauses for the underlying text. We ship only ranks (facts), which is safe; the raw text is not shipped. | step 01 frequency signal |
| Leeds Corpora (`leeds_freq.num`) | University of Leeds, Centre for Translation Studies | Their internet corpora are typically CC‑BY for research; commercial use of Web 1T‑derived counts may be restricted. We ship only the rank, not the source corpus. | step 01 frequency signal |

### Concrete cleanup actions before commercial release

1. **`532Strategien.csv`** — keep the strategy *categories* (FRESCH method) as
   a pedagogical concept tag in the DB, but re‑derive the per‑word
   mapping from our own consolidated wordlist (apply the FRESCH rules
   algorithmically). Don't ship the AOL/Persen curated list as a raw
   source file.
2. **`100Fehler.csv` / `300Fehler.csv` / `400Fehler.txt`** — already only
   pulling the headwords. Add explicit "© Dr. Gero Tacke, based on
   Wolfgang Menzel 1985" credit. If commercial concerns are strong,
   replace with own learner‑error data + Wikipedia "Liste häufiger
   Rechtschreibfehler" (CC‑BY‑SA).
3. **`739Leo.csv`** — needs origin identification. If origin can't be
   determined, drop from the pipeline.
4. **Leipzig + Leeds** — current usage (rank only) is safe. Don't widen.

---

## DATA SOURCES — English (planned for voc-en)

### ✅ Safe (CC‑BY‑SA / CC‑BY / OGL / public domain)

| File / source | Provider | License | Used by |
|---|---|---|---|
| EN Wiktionary | Wikimedia Foundation | CC‑BY‑SA 4.0 | step 11 enrichment |
| ConceptNet 5.x (en) | Luminoso + community | CC‑BY‑SA 4.0 | step 11 |
| OEWN (Open English WordNet) | Open English WordNet community | CC‑BY 4.0 | step 11 / step 13b |
| `en_50k_hermitdave.txt` | HermitDave / OpenSubtitles 2018 | CC‑BY‑SA 4.0 | step 01 |
| Wikipedia "Lists of common misspellings" | Wikimedia | CC‑BY‑SA 4.0 | step 11 (commonLearnerErrors) |
| `uk_y1_y6_statutory.csv` | UK Department for Education, English Programmes of Study Appendix 1 | Open Government Licence v3.0 (attribution required, commercial allowed) | step 01 pedagogical primary |
| `dolch_220.csv` | Edward W. Dolch (1948) | **Public domain** (US, pre‑1978 work) | step 01 (G1‑G3) |
| `fry_top1000_freq.txt` (stand‑in) | freq‑based community top‑1000 wordlist | Public domain / MIT (depends on mirror) | step 01 (sight‑word band) |
| `cmudict.txt` | Carnegie Mellon University | Permissive BSD‑style | step 05 (ARPAbet) |
| `aoa_kuperman.csv` | Kuperman, Stadthagen‑Gonzalez & Brysbaert (2012) | Springer supplementary data — typically reusable for derivative facts | step 03 grade fallback |

### ❌ NOT safe — removed from EN scaffolding

| File / source | Why removed |
|---|---|
| Oxford 3000 / Oxford 5000 | © Oxford University Press; not redistributable as a dataset in commercial apps |
| English Vocabulary Profile (EVP) | Cambridge University Press; commercial use requires paid licensing |
| SUBTLEX‑US (Brysbaert et al.) | Free for academic/non‑commercial use only; commercial use needs explicit permission |

Replacement strategy already documented in `pipeline/voc-en/README.md`:
the EN pedagogical primary is UK Y1–6 statutory + Dolch + Fry; the
frequency layer is HermitDave + AoA‑Kuperman; the lexical backbone is
`cstr/en-wiktionary-sqlite-all` (which is itself Wiktionary‑derived,
CC‑BY‑SA).

---

## TOOLS / LIBRARIES used during the build

These tools generate the *output* that ships in the DB. Their license
typically does NOT attach to the output (the output is data, not a derived
work of the tool), but courtesy attribution is good practice.

| Tool | License | Role |
|---|---|---|
| spaCy + `de_core_news_sm` / `en_core_web_sm` | MIT | step 02 (lemma + POS + morphology) |
| pattern.de / PatternLight | BSD‑3‑Clause | morphological analysis (HF Space) |
| HanTa | Apache 2.0 | morphological tagging (HF Space) |
| IWNLP (`Liebeck/IWNLP.Lemmatizer`, `Liebeck/spacy-iwnlp`) | MIT | Wiktionary‑derived lemmatization (HF Space) |
| DWDSmor | Software permissive; DWDS data terms | morphology (HF Space) |
| wiktextract | MIT | parses raw Wiktionary XML dumps → JSONL (VPS step) |
| phonemizer + espeak‑ng | GPL‑3.0 | step 05 (IPA + X‑SAMPA generation). Tools NOT bundled with app; only their output (phoneme strings = facts) is shipped, so GPL does not virally attach. |
| `huggingface_hub`, `gradio_client`, `requests`, `pandas`, `numpy` | Apache‑2.0 / BSD / MIT | build infrastructure |
| SQLite | public domain | DB engine |
| Flutter / Dart / `sqflite` / `provider` / `shared_preferences` / `in_app_purchase` / `audioplayers` / `path_provider` / `url_launcher` / `flutter_tts` / `package_info_plus` | BSD / MIT (per‑package) | app runtime; auto‑included by Flutter's `showLicensePage` |

---

## App‑side wiring

- `lib/features/settings/screens/settings_screen.dart` — `_addCustomLicenses()` registers all CC‑BY/SA data sources and non‑pubspec tools via `LicenseRegistry.addLicense()` during `initState`.
- `Settings → Licenses` button — calls Flutter's built‑in `showLicensePage()`, which merges the custom entries with all pubspec dependency licenses.
- **Polish‑bug to fix:** `applicationVersion: '1.0.3'` is hard‑coded in `showLicensePage(...)`. Replace with dynamic version from `package_info_plus`.
- **Polish‑bug to fix:** licenses are registered in Settings's `initState`. If the user opens `showLicensePage` from somewhere else without ever visiting Settings, the custom entries won't be present. Move registration to `main.dart` startup.

---

## Open verification items (require user input)

| Item | Question |
|---|---|
| `739Leo.csv` | Where did this come from? File name doesn't match any obviously‑public German Grundwortschatz reference. |
| `200Fehler.csv` | Self‑curated or sourced? |
| Goethe‑Institut wordlist redistribution | The DWDS API serves the lists publicly. **Confirm:** is DWDS's redistribution explicitly licensed by Goethe, or is the assumption "factual reference, not copyrightable" sufficient? Defensive option: keep the lemma‑only data (which is factual) and drop any per‑word annotations specific to Goethe's prep materials. |
| FRESCH‑Methode `532Strategien.csv` | Recommend: replace the raw curated list with a derivation we generate ourselves (apply the FRESCH categories to *our* wordlist). Confirm before next build. |
| App vs DB license posture | Confirm the intent: app code stays proprietary (commercial app with in‑app purchases), DB file ships under CC‑BY‑SA 4.0 with prominent attribution. |
