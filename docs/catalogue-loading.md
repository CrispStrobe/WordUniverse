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
| reading it from the pack instead (the packs ship it now) | 209 ms |

**~29× faster to a usable catalogue**, and the enrichment is never resident.
A phone or a browser pays more for the decode than this desktop run does, so
the ratio there is at least as good.

## The index the pack brings with it

The feature index is a pure function of the pack: the same bitmask per row on
every device, derived from the same JSON. Deriving it costs about 3 seconds
for the German pack and 3 for the English one — once per install, and again
whenever the bit layout changes and the cache is discarded.

`tools/pack/index_pack.sh` writes it into the artifact instead, using the
app's own `WordFeatureIndex.build` rather than a reimplementation. On open the
app reads `word_feature_index` if the pack has one, after checking that the
format matches `kWordFeatureIndexFormat` and that the row count still matches
the `words` table; anything else and it derives its own as before. Measured on
the English pack: **3,075 ms to derive, 209 ms to read**, for 94 KB more
download (146 KB for German).

The verification is the point. The bits are persisted, so an index built for
an older layout would be silently wrong in a way no game could notice — and a
pack is republished far less often than the app ships.

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

### The install, and why only the web path uses native primitives

The same run originally took **88 seconds** to install the pack, 61 s of it
decompressing 93.9 MB. `compute()` gives native platforms a real isolate but is
only a microtask on the web, so that ran on the main thread — as did SHA-256,
which the German pack pins and enforces. Measured in Chromium:

| 93.9 MB | Dart | browser |
|---|---|---|
| gunzip | 60,556 ms (`package:archive`) | **1,717 ms** (`DecompressionStream`) |
| sha256 | 190,095 ms (`package:crypto`) | **624 ms** (`crypto.subtle`) |

The German pack is worse, because it is 149 MB and pins a digest that **is**
enforced. Through the old path, in the same browser:

| German pack, 149 MB | |
|---|---|
| gunzip `package:archive` | 81,661 ms |
| sha256 `package:crypto` | 273,379 ms |
| **total, on the main thread** | **355,040 ms — 5m 55s** |

and that is before the download, the storage write and the launch.

The web loader now uses the browser's own primitives, falling back to the Dart
path when they are missing (older Safari, or a non-secure origin where
`crypto.subtle` does not exist). Legacy adoption, which hashes a whole installed
database to match it against the pinned digest, uses the same native digest.

Measured end to end in the app, driving the real UI with Playwright against a
release build: **45.6 s from clicking Download to a playable German quiz** —
network fetch of 25 MB, gunzip, enforced digest, IndexedDB write, feature index
build and the game's first pool, all included. English install went 88 s to
30 s, its decompression 61.3 s to 1.3 s.

On the **VM** the same comparison says to leave the Dart path alone — it is
compiled to machine code, and the alternatives are not worth touching a
validation path for:

| 149 MB (German pack) | |
|---|---|
| gunzip `package:archive` | 1,296 ms |
| gunzip `dart:io gzip.decode` | 1,014 ms |
| sha256 `package:crypto` | 4,329 ms |

`dart run tools/bench/gzip_benchmark.dart <pack.db.gz>` reproduces that.

### What the web install costs now

| phase, 93.9 MB | |
|---|---|
| fetch the compressed asset | 885 ms |
| gunzip (browser) | 1,056 ms |
| **`writeDatabaseBytes` into IndexedDB** | **24,220 ms** |
| open + validate (cold) | 11,852 ms |
| open + validate (warm, the second open) | 147 ms |

Storage is now the whole cost. `sqflite_common_ffi_web` 1.1.1 opens
`IndexedDbFileSystem` unconditionally, with no OPFS option — OPFS is the
storage SQLite-on-wasm is meant to use and would change both numbers, but
reaching it means going around sqflite_common_ffi_web and migrating every
installed pack, so it is a decision rather than a patch.

Re-measure with:

```sh
# native catalogue load
dart run tools/bench/catalogue_load_benchmark.dart path/to/pack.db

# native gzip/sha comparison
dart run tools/bench/gzip_benchmark.dart path/to/pack.db.gz

# browser: install, index build, launch (see the test header for its fixtures)
flutter test --platform chrome test/live/web_index_benchmark_live_test.dart
```

All figures here are single runs on one machine, and the browser ones move by
roughly ±10% between runs. They are the right order of magnitude, not a
benchmark suite.

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
