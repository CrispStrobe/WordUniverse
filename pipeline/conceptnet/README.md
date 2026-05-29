# ConceptNet — all-languages normalizer

`build_normalized.py` rebuilds the **lost** normalizer from `../PLAN.md §3`:
it turns `cstr/conceptnet-de-indexed/conceptnet-de-indexed.db` (~23.6 GB,
all ~370 languages, URL-keyed) into a compact integer-keyed
`conceptnet_normalized_all.db` (~6–8 GB) for `cstr/conceptnet-normalized-all`.

**This is optional and independent** — ConceptNet relations are already in
the shipped voc DBs (`enrichment_json.conceptnet`), so this gates nothing in
the app. Build it only when a standalone multi-language ConceptNet DB is wanted.

## Runs on an 8 GB VPS

The binding constraint is **disk (~60–70 GB free)**, not RAM. The script is a
batched, resumable, disk-based SQLite pipeline; defaults are tuned for 8 GB:

- 256 MB page cache (`--cache-mb`)
- `temp_store=FILE` + `SQLITE_TMPDIR` on the big disk (`--tmpdir`) — the unique
  node index (28 M rows) and the two edge indexes (34 M rows) external-merge-sort
  to disk instead of OOMing
- keyset paging by `src.edge` rowid (not O(n²) `OFFSET`)
- WAL + per-batch `wal_checkpoint(TRUNCATE)` → crash-safe, bounded WAL, **resumable**

Wall time ~4–10 h, dominated by the 34 M-row join + the two index sorts.

## Usage

```bash
# build from a local source copy
python3 build_normalized.py --src /mnt/data/conceptnet-de-indexed.db \
    --out /mnt/data/conceptnet_normalized_all.db --tmpdir /mnt/data/tmp

# or download the source from HF first (needs huggingface_hub + auth)
python3 build_normalized.py --download --out conceptnet_normalized_all.db --tmpdir ./tmp

# build then push the result to the sibling dataset
python3 build_normalized.py --src ... --upload-repo cstr/conceptnet-normalized-all

# crashed mid-run? re-run the exact same command — it resumes from the
# _build_meta table in the output DB.

# smoke test on a slice of edges
python3 build_normalized.py --src ... --limit 1000000
```

Each run writes a JSON summary (args, timings, row counts, git SHA) to
`runs/<utc-timestamp>.log` — commit the real run's log as a build record
(per `../LEARNINGS.md`). The synthetic test logs are not committed.

## Output schema

```
rel_norm(rel_pk, rel_url)                                   -- ~50 rows
node_norm(node_pk, node_url, language)  UNIQUE(node_url)     -- ~28 M rows
edge_norm(start_fk, end_fk, rel_fk, weight)                 -- ~34 M rows
    ix_edge_start_rel(start_fk, rel_fk), ix_edge_end_rel(end_fk, rel_fk)
```

Verified end-to-end on a synthetic source DB (correct FK resolution, batched
paging, idempotent resume). Not yet run on the real 23.6 GB source — that
needs the HF download + a 60–70 GB-disk box.
