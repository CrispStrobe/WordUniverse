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

## In a browser

The same pack, installed and measured in Chromium through the app's real web
path (`test/live/web_index_benchmark_live_test.dart`):

| | |
|---|---|
| **old launch** — `SELECT *` + `jsonDecode` | **3,430 ms** |
|   of which the query itself | 2,565 ms |
|   of which decoding 34,617 blobs | 865 ms |
| **new launch** — light columns | **314 ms** |
| index build, once per pack revision | 3,404 ms |
| index encode (the cached record is 0.3 MB) | 246 ms |
| index decode, every later launch | 118 ms |

So a launch goes from 3,430 ms to **432 ms** (light query plus reading the
cached index) — **8× on every launch after the first**. The first launch after
an install pays the build instead of the decode and comes out ~500 ms slower
than the old path, which is noise next to the install it follows.

Note the shape differs from native: in the browser the *query* dominates
(2,565 ms of 3,430 ms), because 73 MB of JSON has to cross the sqflite worker
boundary. Not fetching it is the win either way.

### The install itself is the web's real cost

That same run took **88 seconds** to install the pack, 61 s of it decompressing
93.9 MB. `db_platform_web.dart` hands the gunzip to `compute()`, which routes
through an isolate on native but is only a microtask on the web — so it runs on
the main thread. A browser's own `DecompressionStream('gzip')` would do this
natively and incrementally. That is untouched here and is the largest remaining
item on the web first-run path.

Re-measure with:

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
