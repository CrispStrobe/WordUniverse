# How the word catalogue loads

Measured on the shipped English pack (11,539 words, 73.3 MB of
enrichment/metadata JSON), desktop native, via
`tools/bench/catalogue_load_benchmark.dart`:

| | |
|---|---|
| **old launch** — `SELECT * FROM words` + `jsonDecode` every blob | **2,443 ms** |
|   of which SQLite query | 711 ms |
|   of which decoding 34,617 JSON blobs | 1,732 ms |
| **new launch** — nine light columns, no JSON | **85 ms** |
| hydrating a 200-word round pool | 97 ms |
| building the feature index (once per pack revision, then cached) | 446 ms |

**~29× faster to a usable catalogue**, and the enrichment is never resident.
A phone or a browser pays more for the decode than this desktop run does, so
the ratio there is at least as good.

Re-measure with:

```sh
dart run tools/bench/catalogue_load_benchmark.dart path/to/pack.db
```

## The three pieces

1. **Light load.** `DictionaryDatabaseService.getAllWords()` selects only the
   columns that describe a word — id, spelling, lemma, article, genus, type,
   grade, audio. No enrichment crosses the platform channel.

2. **The feature index** (`db_feature_index.dart`). The questions a word *pool*
   asks of the enrichment — has definitions? synonyms? hyphenation? learner
   errors? — are answered once per pack revision inside SQLite's JSON1
   functions and cached as a compact binary record. It also carries each word's
   `sources` and the JSON half of presentability, both of which used to force
   every blob open at launch.

   The pack database is opened read-only (`db_schema.dart`), which is why the
   index lives beside it rather than as columns in it.

3. **Hydration.** `VocabularyService.takeWordsWithFeature()` narrows a pool on
   the index's integers, then re-reads just those rows with their JSON decoded.
   Games that only display enrichment for the words in play call `hydrate()` on
   that handful directly.

A word that has not been hydrated returns null/empty for every
enrichment-derived field, and reading one warns in debug — see `GermanWord`.

## Why filtering stayed in Dart

Grade, category and word-type filtering still happens over the in-memory
catalogue rather than in SQL, deliberately:

- The catalogue is now light, and the filtered results are memoized
  (`VocabularyService._filtered`), so a filter pass is a scan over ~11.5k small
  objects — cheaper than a round trip.
- Much of the app needs the whole catalogue synchronously anyway: the compound
  splitter's noun map, homophone lookup, the spelling-distractor validity set,
  in-memory search, custom subsets. Moving filtering into SQL would make those
  async without removing the need to hold the words.
- An index on `word_type` was considered and **not** added to the pipelines: no
  query filters on it in SQL, so it would be dead weight in every pack. Add it
  the same day a query needs it.
