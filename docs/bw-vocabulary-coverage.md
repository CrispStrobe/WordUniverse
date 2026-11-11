# BW vocabulary coverage and source repair

Audit date: **2026-11-08**. This report separates the unchanged downloaded
dictionary, official word-list membership, and project-authored lexical
corrections. They have different evidence and counting units.

The pinned German dictionary contains **769 distinct rows carrying BW1 or
BW3**, not 774 distinct words. The four official BW documents confirm the
origin of the repository CSVs. They also expose import losses, an incomplete
teacher-list export, and capitalization/sense collisions. The new membership
asset preserves **864 source declarations and 857 distinct normalized,
case-sensitive spellings**. These numbers are not an alternative definition
of the ZSL's description of **approximately 870 words**.

## Exact inputs

### Downloaded dictionary

The registry in [language_pack.dart](../lib/core/models/language_pack.dart)
pins this immutable Hugging Face revision:

[`5b4757f2ba5ba8bd40ecc7ad2df0c45b53b5e953/grundwortschatz-app.db.gz`](https://huggingface.co/datasets/cstr/grundwortschatz-voc-de/resolve/5b4757f2ba5ba8bd40ecc7ad2df0c45b53b5e953/grundwortschatz-app.db.gz).

| Input | Bytes | SHA-256 |
| --- | ---: | --- |
| Compressed runtime pack | 16,047,300 | `cd350f6e5fda2dc7a5aba2121188ee475e54b9fd273fa5e4214533cdefb42059` |
| Decompressed SQLite database | 96,518,144 | `1df66b74d7074ce82d866acc7a5684db1647d9d1d1e45a3d5c5cb363a2d4af63` |

Both local files match these pins. The database contains **13,040 word rows**.
The audit opens it with SQLite `mode=ro` and `PRAGMA query_only=ON`. It does
not mutate the dictionary, its feature index, or the download registry.

### Official source receipt

The [ZSL Grundwortschatz page](https://zsl-bw.de/,Lde/Startseite/allgemein-bildende-schulen/grundwortschatz-deutsch-gs)
identifies these materials as Baden-Württemberg's primary-school spelling
vocabulary and supplies separate teacher and pupil lists for classes 1–2
and 3–4. The [ministry publication page](https://km.baden-wuerttemberg.de/de/service/publikation/did/grundwortschatz-fuer-den-rechtschreibunterricht-an-den-grundschulen-in-baden-wuerttemberg)
identifies the publication year as 2020. The Word files below were retrieved
from the ZSL links on the audit date. Their hashes are checked before the
audit tool accepts them or regenerates membership.

| Code | Official Word document | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| 1L | [Teacher list, classes 1–2](https://zsl-bw.de/site/pbs-bw-rebrush2024/get/documents_E463558729/KULTUS.Dachmandant/KULTUS/Dienststellen/zsl/Allgemeine%20Bildung/Grundschulen/Grundwortschatz-Deutsch-GS/Lehrkraefte-1-2-Alphabetische-Woerterlisten.docx) | 349,475 | `eca925f77cb07ee8d2460eeef7045d7db14adec22b6b59f92638c77f74f724fb` |
| 1S | [Pupil list, classes 1–2](https://zsl-bw.de/site/pbs-bw-rebrush2024/get/documents_E972787316/KULTUS.Dachmandant/KULTUS/Dienststellen/zsl/Allgemeine%20Bildung/Grundschulen/Grundwortschatz-Deutsch-GS/Schueler-1-2-Alphabetische-Woerterlisten.docx) | 337,742 | `79d080acb670402b0ea48ad7cd8b1a73e77791221886d7957c73ca9ec1db957a` |
| 3L | [Teacher list, classes 3–4](https://zsl-bw.de/site/pbs-bw-rebrush2024/get/documents_E-838648795/KULTUS.Dachmandant/KULTUS/Dienststellen/zsl/Allgemeine%20Bildung/Grundschulen/Grundwortschatz-Deutsch-GS/Lehrkraefte-3-4-Alphabetische-Woerterlisten.docx) | 353,556 | `f52f32a954b6382cd7dde1ada9edcd6d6dba786f2d8f6e4336128f1556573b3b` |
| 3S | [Pupil list, classes 3–4](https://zsl-bw.de/site/pbs-bw-rebrush2024/get/documents_E251272688/KULTUS.Dachmandant/KULTUS/Dienststellen/zsl/Allgemeine%20Bildung/Grundschulen/Grundwortschatz-Deutsch-GS/Schueler-3-4-Alphabetische-Woerterlisten.docx) | 337,152 | `145ab75bb6560d46a878e5f6ceb0bed59b455888d42fb9529257e15ca3139108` |

The original repository files were checked at commit
[`c320e88c74bfbd02efa8fdca448bd15bb2448865`](https://github.com/CrispStrobe/WordUniverse/tree/c320e88c74bfbd02efa8fdca448bd15bb2448865/pipeline/voc-de).
The headword sets in `1L`, `1S`, and `3S` match the corresponding official
documents exactly. Original `3L` is a strict subset missing its entire
19-headword Z section. That section has now been restored from the official
teacher document, including its forms, page references, and worksheet rows.

| Repository CSV | Original SHA-256 | Current SHA-256 if changed |
| --- | --- | --- |
| `Grundwortschatz1L.csv` | `19830bf28dfb9138312ee55f09ca6d1c8cae1648a67c21d99de6f94092006a57` | unchanged |
| `Grundwortschatz1S.csv` | `59cca802e9ce68ba8979c5441a1bb5b0eccef54e1b147bc500d5c19a7947b790` | unchanged |
| `Grundwortschatz3L.csv` | `d85f91bc380b1d6d59c27405ad7a1f7bcd7f3ab0981f251e5d90351e2cf78008` | `09b0cacc059c3d042cc5f1e43ff4b8f13c19b40ea9276e4c1ec2d1ff95ba26b8` |
| `Grundwortschatz3S.csv` | `a86fbaf678b28b12ade34c314e525966d0db61ed9c9cb3d0845e1273cab9204f` | unchanged |

The previous NRW descriptions of these four CSVs in the pipeline README
and history were incorrect. NRW's `111_NRW_Merkwörter.txt`,
`422_NRW_Nachdenkwörter.txt`, and Excel material remain separate sources.

## Counting and normalization

Blank worksheet rows and repeated alphabet headings are not vocabulary
entries. Teacher rows count when their page cell contains one or more
numeric page references. The two `Jahr` rows in 3L remain two source
declarations of one spelling.

| List | Original lexical rows | Original distinct labels | Official distinct labels | Repaired distinct labels |
| --- | ---: | ---: | ---: | ---: |
| 1L | 410 | 410 | 410 | 410 |
| 1S | 414 | 414 | 414 | 414 |
| 3L | 418 | 417 | 436 | 436 |
| 3S | 450 | 450 | 450 | 450 |

The membership asset uses the pupil lists as its membership basis. It
normalizes Unicode to NFC, trims and collapses whitespace, preserves case,
removes only the explicit optional suffix `(-)`, and removes the optional
context prefixes `(ein) ` and `(sich) ` from the lookup spelling. Every
original label, source band, article, document identifier, and table/row
position remains attached. Thus `(ein) paar` maps to lower-case `paar`,
while the noun `Paar` remains distinct. `sein(-)` remains an explicitly
recorded pattern context; equal spelling does not establish the same sense
as the verb `sein`.

This gives 414 normalized BW1 spellings and 450 BW3 spellings. Seven
spellings occur in both bands, so the union has **857** spellings.
The overlapping spelling `sein` needs separate verb and possessive
handling. No normalization expands every inflection, converts `ß` to `ss`,
matches synonyms, or treats related word families as identical headwords.

The official approximate total, source row counts, normalized spelling
counts, runtime rows, and source-tag memberships measure different things.
There is no justified calculation of “774 out of 870” or a claim that this
export covers every current official KOMPASS requirement.

## Coverage of the unchanged pinned pack

Runtime membership is read from `metadata_json.sources`, not inferred from
the word's grade. The legacy pack contains **393 BW1 rows** and **381 BW3
rows**. The five rows `dürfen`, `Gras`, `laufen`, `schlafen`, and `Weg`
carry both tags. Consequently **393 + 381 = 774 memberships**, but
**393 + 381 − 5 = 769 distinct rows**.

| Measure | BW1 | BW3 |
| --- | ---: | ---: |
| Official normalized exact spellings | 414 | 450 |
| Exact spelling present as a pinned database row | 409 | 442 |
| Exact spelling missing | 5 | 8 |
| Present spelling lacks the corresponding source tag | 20 | 64 |
| Tagged spelling absent from that exact-case source band | 4 | 3 |

These are spelling checks before verifying a matching grammatical sense or
applying game-specific filters. For example, the existing verb `sein`
cannot establish coverage of the BW3 possessive pattern.

### Missing exact spellings

Four source spellings have no word row even with a lowercase diagnostic
comparison: **E-Mail, vergesslich, Zeh, Zylinder**. Nine more have only a
differently capitalized row whose orthographic or grammatical role differs:

| Required source spelling | Band | Existing row with different case |
| --- | --- | --- |
| `arm` | BW1 | `Arm` — noun |
| `essen` | BW1 | `Essen` — noun |
| `leben` | BW1 | `Leben` — noun |
| `morgen` | BW1 | `Morgen` — noun |
| `sie` | BW1 | `Sie` — pronoun with different capitalization |
| `nächste` | BW3 | `Nächste` — noun |
| `paar` from `(ein) paar` | BW3 | `Paar` — noun |
| `vertrauen` | BW3 | `Vertrauen` — noun |
| `weg` | BW3 | `Weg` — noun |

The seven erroneous band associations are `Essen`, `Leben`, `Morgen`, and
`Sie` for BW1; `Nächste`, `Vertrauen`, and `Weg` for BW3. Runtime correction
must replace the inherited BW band tags using exact source membership.
Simply adding missing tags would retain these mistakes. The BW1 noun
`Weg` remains a valid BW1 member.

### Present spellings missing their correct tag

These lists include the explicit annotation normalization described above.
They are source-band memberships, so a spelling can appear in both lists.

**BW1, 20:** Bauch, Biene, Dach, ein, Eule, eure, fangen, fliegen, fragen,
haben, jung, können, Küche, Maus, müssen, Nacht, Schule, sein, spielen, viel.

**BW3, 64:** all, beide, bisschen, dein, dies, Durst, durstig, erklären,
Erklärung, erzählen, Erzählung, freuen, ganz, gesund, Gesundheit, Glück,
glücklich, hoffen, Hoffnung, ihn, ihr, jede, jemand, kein, krank, Krankheit,
manch, mein, niemand, Ruhe, ruhig, schwierig, Schwierigkeit, sein, solch,
Sprung, Stamm, Stärke, uns, vergessen, verwandt, Verwandtschaft, welche,
wenig, Witz, witzig, Zahn, Zeichnung, Zeitung, Zelt, Zeugnis, ziehen,
ziemlich, Zoo, Zucker, zuerst, Zug, Zukunft, zurück, zusammen, Zwerg,
zwischen, zählen, ängstlich.

For comparison with the old importer's alphabetic-only, case-insensitive
policy, the audit also reports the narrower 17 BW1 and 44 BW3 untagged
plain labels, and three entirely absent alphabetic labels. These forgiving
diagnostics do not replace the strict results above.

## Source/importer repairs

The repaired [BW reader](../pipeline/voc-de/bw_source_lists.py) and
[consolidation stage](../pipeline/voc-de/01_consolidate_wordlists_csv.py)
address the independently verified losses:

1. **Multiple page references:** 13 BW1 and 14 BW3 teacher rows contain
   page lists such as `24, 49`. The original numeric coercion dropped all
   27. The reader now retains every reference and the original page text.
2. **Short-only heads:** the original left join made the long list the
   sole vocabulary source. The exact-label outer union now preserves
   pupil-list heads such as `fliegen`, `fragen`, and `Erklärung`.
3. **Missing Z section:** all 19 official teacher rows have been restored
   to 3L. UTF-8 BOM and CRLF are preserved.
4. **Explicit notation and hyphens:** the known annotations are normalized
   without discarding their declarations, and `E-Mail` survives the final
   character filter. Unknown label forms raise a diagnostic.
5. **Capitalization:** every key declared by BW receives case-sensitive
   consolidation, including against other source lists. An external noun
   `Essen` cannot overwrite BW `essen` or contribute its article/type.
   Keys outside BW retain the previous consolidation policy.

`BW_RawLabels`, `BW_Pages`, and `BW_Provenance` preserve the declarations,
forms, articles, page references, filenames, and CSV row locations.
The spaCy enrichment stage preserves these columns unchanged, and JSON
conversion exports them as `bwSourceLabels`, `bwSourcePages`, and
`bwSourceProvenance`. The SQLite converter's generic metadata path retains
them. They are provenance, not proof that same-spelling grammatical senses
are identical.

These pipeline repairs affect future builds. They do not retroactively
change the immutable downloaded pack.

## Runtime data boundary

[`assets/data/bw_membership_v1.json`](../assets/data/bw_membership_v1.json)
contains official membership and the source receipt, without definitions
or invented difficulty labels. Its checked Word document hashes are also
embedded in the read-only exporter. A changed official file requires a
reviewed receipt update rather than silently inheriting the old claim.

Project-authored supplemental entries and corrected ordinary senses belong
in the separate lexical overlay, not in the authority-bearing membership
asset. The source audit identifies 13 missing exact spellings, the separate
BW3 possessive use of `sein`, and five concrete incorrect lexical records.
The reviewed pack of 2026-11-10 (see `tools/pack/llm_correct.py`) has since
corrected Gabel, Herr, Luchs and Mandarine at the source, and its rebuild
the same day corrected August (`tools/pack/repair_pack.py`,
`GERMAN_ROW_CORRECTIONS`); the overrides remain in place for all five. A
sixth, Band, was added after a read of the games on the reviewed pack:

| Existing ID | Word | Pinned pack problem | Required ordinary meaning |
| --- | --- | --- | --- |
| `word_00692` | August | Typed as a proper noun; leading sense is a personal name | Month |
| `word_03407` | Gabel | Typed as a proper noun; leading sense is a surname | Cutlery |
| `word_04368` | Herr | Typed as a proper noun; leading sense is a surname | Ordinary noun/address |
| `word_05837` | Luchs | Leading sense describes an inflected form of another noun | Animal |
| `word_05944` | Mandarine | Leading sense describes a plural of another noun | Fruit |
| `word_00876` | Band | Article *die* (music group), glosses of *der Band* (book); BW3 lists "Band; Bänder" | Ribbon (*das Band*), added 2026-11-10 |

An override must keep candidate selection, feature-index answers, and
hydration consistent. It must not make person-name senses eligible merely
because their spelling also occurs in BW. The read-only audit continues to
report the pinned database's original gaps after runtime overlay repair;
runtime integration tests verify the effective application view separately.

## Difficulty and quality limits

Among the 769 legacy tagged rows, `grade_level` and `gradeLevelEstimate`
have the same distribution: **393 at 1, 127 at 2, and 249 at 3**. All 769
estimates in the pinned pack have `gradeLevelEstimateSource: "nrw"`.
The old estimator assigned that label when copying any existing grade from
1 through 4. It does not establish that every word came from NRW, nor is it
a calibrated BW grade or KOMPASS difficulty measurement.

The repaired
[grade estimator](../pipeline/voc-de/compute_grade_level_estimate.py) now
uses `gradeLevelEstimateSource: "existing_grade_level"` for those copies.
`gradeLevelEstimateEvidence` identifies the inherited `words.grade_level`
field and preserves explicit `gradeLevelSource`/`gradeLevelEvidence` as
`upstreamSource`/`upstreamEvidence` when supplied. Old ambiguous estimate
labels and source-list membership do not establish that origin. ChildLex
and DWDS decisions retain their existing numerical rules and record the
selected field and heuristic. Numeric grade values are unchanged.

| `spellingDifficulty` index | App label | Tagged rows |
| --- | --- | ---: |
| 0 | easy | 503 |
| 1 | medium | 125 |
| 2 | hard | 81 |
| 3 | expert | 60 |

**257 of the 503 zero-valued entries have no LiTKey error rate.** The
original JSON conversion initializes this field to zero. A zero can
therefore mean missing evidence, rather than demonstrated ease.
512 tagged rows have a stored LiTKey error rate. The
[LiTKey integration](../pipeline/voc-de/add_litkey_profiles.py) maps rates
below 0.25, 0.50, and 0.75 to indices 0, 1, and 2 respectively, with the
remaining rates assigned index 3. None of these 769 rows retains the
corresponding sample-size field, so the audit cannot assess the reliability
of a rate such as 1.0. These are corpus-derived item hints, not an individual
child's mastery score.

Future CSV-to-JSON builds retain the compatible numeric field but now add
`spellingDifficultySource: "unknown"` and an explicit unknown
`spellingDifficultyEvidence` object when no measured spelling evidence is
available. A default zero therefore remains distinguishable from an
observed zero error rate. Both LiTKey producers set the source to `litkey`
and the evidence status to `corpus-derived`, recording the actual error
rate, aggregation unit, and available token/error counts. Missing counts
remain unknown. Counts already calculated by future enrichment runs are
now retained; this does not repair the absent counts in the pinned pack.
Every such evidence record explicitly states `calibrated: false`.
The existing score thresholds are unchanged.

All 769 rows have a primary spelling-strategy label. Its distribution is
220 capitalization, 200 sound-spelling correspondence, 150 doubled
consonants, 74 vowel lengthening, 65 related-word reasoning, 47 morpheme
structure, and 13 memorized spellings. These project enrichment categories
are not an official KOMPASS scoring scheme.

The shipped feature index additionally marks eight tagged rows as not
being their own enriched headword, and 13 as lacking a usable leading
definition. A separate pack flag marks 7 leading glosses as above their
reader's level. Some of these are useful function words whose dictionary
parses do not make suitable child-facing meaning questions. Such flags
call for appropriate game filtering or a reviewed explanation; they do
not mean the source word itself should be removed from spelling practice.

Source membership, a spelling-strategy tag, a stored example, and a usable
game question are separate checks. This audit does not certify every
definition, generated example, inflection, pronunciation, or distraction
choice in the pack. It does not predict school recommendations or official
KOMPASS results.

## Reproduction

The audit uses Python's standard library. Provide the verified decompressed
pack and, for the independent official comparison, the four Word documents
under the exact filenames from the source receipt above:

```bash
python3 tools/audit/bw_vocabulary_coverage.py /path/to/grundwortschatz-app.db \
  --official-dir /path/to/bw-word-documents --as-of 2026-11-08 > bw-audit.json
```

The tool checks the current pack pins by default. `--allow-unpinned` is an
explicit option for comparing a different pack and records the mismatch.
Without `--official-dir`, it still audits the CSVs and pinned database but
does not claim to have rechecked the external documents.

Regenerate the membership asset deterministically, without writing inputs:

```bash
python3 tools/audit/bw_vocabulary_coverage.py --format membership \
  --official-dir /path/to/bw-word-documents --as-of 2026-11-08 \
  > /tmp/bw_membership_v1.json
cmp assets/data/bw_membership_v1.json /tmp/bw_membership_v1.json
```

To reproduce the original incomplete-source counts, extract the four CSVs
from commit `c320e88c74bfbd02efa8fdca448bd15bb2448865` into a temporary
directory and pass that directory as `--source-dir`. The audit reports
the SHA-256 of each selected CSV, so historical and repaired snapshots
cannot be mistaken for each other. The current restored 3L has no missing
official headword labels; the original 3L reports the 19 missing Z heads.

Focused importer regressions run with:

```bash
python3 -m unittest discover -s pipeline/voc-de -p 'test_bw_source_lists.py'
python3 -m unittest discover -s pipeline/voc-de -p 'test_*evidence.py'
```

All **11 source regressions and 13 evidence regressions passed** on the
audit date. The source checks exercise the
actual consolidation adapter with isolated fixtures,
multiple page references, short-only words, source-case conflicts,
annotations, provenance, and the restored official Z table. A fixture also
follows the source declarations through mocked spaCy enrichment, JSON
conversion, and an in-memory SQLite database. Evidence checks cover grade
provenance, unchanged numeric boundaries, unknown versus observed zero,
retained actual sample counts, and JSON-to-SQLite metadata preservation. No full
dictionary rebuild or remote dataset publication is needed for this audit.
