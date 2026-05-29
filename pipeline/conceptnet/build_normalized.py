#!/usr/bin/env python3
"""Normalize the all-languages ConceptNet dump into a compact, integer-keyed DB.

Takes `cstr/conceptnet-de-indexed/conceptnet-de-indexed.db` (~23.6 GB,
all ~370 languages, URL-keyed) → `conceptnet_normalized_all.db` (~6-8 GB,
integer-keyed) for `cstr/conceptnet-normalized-all`. This is the rebuild of
the *lost* normalizer described in `pipeline/PLAN.md §3`; the recipe there is
the spec, this is the runnable, resumable, low-memory implementation.

ConceptNet relations are ALREADY in the shipped voc DBs, so this is an
independent, optional dataset build — it gates nothing in the app.

Source schema (inferred; verified at startup):
    node(id TEXT, language TEXT)              -- ~28 M rows
    relation(id TEXT)                         -- ~50 rows
    edge(start_id, end_id, rel_id, weight)    -- ~34 M rows
Output schema:
    rel_norm(rel_pk, rel_url)
    node_norm(node_pk, node_url, language)    + UNIQUE(node_url)
    edge_norm(start_fk, end_fk, rel_fk, weight)
        + ix_edge_start_rel(start_fk, rel_fk), ix_edge_end_rel(end_fk, rel_fk)

== Hardware ==
Binding constraint is DISK, not RAM: ~60-70 GB free (source 23.6 GB + dest
~8 GB + index/VACUUM temp). Runs comfortably on an **8 GB-RAM VPS** with the
defaults below — SQLite is a disk engine, the work is batched, and the big
index sorts spill to disk via temp_store=FILE. Wall time ~4-10 h, dominated
by the 34 M-row join + the two edge-index sorts.

Why these defaults (vs a naive 32 GB run):
  - cache_size 256 MB (--cache-mb): pure RAM page cache; small is fine.
  - temp_store=FILE + SQLITE_TMPDIR on the big disk: the unique node index
    (28 M rows) and the two edge indexes (34 M rows) external-merge-sort;
    temp_store=MEMORY would OOM, FILE spills to disk in bounded RAM.
  - keyset paging by src rowid range (not OFFSET): OFFSET is O(n^2) over 34 M.
  - WAL + per-batch checkpoint(TRUNCATE): crash-safe AND bounded WAL, so the
    multi-hour edge phase is *resumable* (--resume, on by default). PLAN.md
    suggested journal_mode=OFF for raw speed; resumability beats it on a long
    job, so WAL is the default here (use --journal off for a throwaway run).

== Usage ==
    # local source already downloaded:
    python3 build_normalized.py --src /path/conceptnet-de-indexed.db \
        --out conceptnet_normalized_all.db --tmpdir /mnt/data/tmp

    # download source from HF (needs huggingface_hub + auth), then build:
    python3 build_normalized.py --download --out conceptnet_normalized_all.db

    # build then push to the sibling dataset:
    python3 build_normalized.py --src ... --upload-repo cstr/conceptnet-normalized-all

    # crash? just re-run the same command — it resumes from the meta table.
    # smoke test on a slice:
    python3 build_normalized.py --src ... --limit 1000000
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNS_DIR = HERE / "runs"

DEFAULT_SRC_REPO = "cstr/conceptnet-de-indexed"
DEFAULT_SRC_FILE = "conceptnet-de-indexed.db"
DEFAULT_OUT_REPO = "cstr/conceptnet-normalized-all"
DEFAULT_OUT_FILE = "conceptnet_normalized_all.db"

_t0 = time.monotonic()


def log(msg: str) -> None:
    el = time.monotonic() - _t0
    print(f"[{el/60:6.1f}m] {msg}", flush=True)


def _git_sha() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], cwd=HERE,
            stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return "unknown"


# ---------------------------------------------------------------------------
# Resume bookkeeping (a tiny meta table in the output DB)
# ---------------------------------------------------------------------------

def _ensure_meta(con: sqlite3.Connection) -> None:
    con.execute("CREATE TABLE IF NOT EXISTS _build_meta("
                "key TEXT PRIMARY KEY, value TEXT)")


def get_meta(con: sqlite3.Connection, key: str) -> str | None:
    row = con.execute("SELECT value FROM _build_meta WHERE key=?", (key,)).fetchone()
    return row[0] if row else None


def set_meta(con: sqlite3.Connection, key: str, value) -> None:
    con.execute("INSERT INTO _build_meta(key,value) VALUES(?,?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                (key, str(value)))


def done(con: sqlite3.Connection, phase: str) -> bool:
    return get_meta(con, f"phase:{phase}") == "done"


def mark_done(con: sqlite3.Connection, phase: str) -> None:
    set_meta(con, f"phase:{phase}", "done")
    con.commit()


# ---------------------------------------------------------------------------
# Source acquisition + verification
# ---------------------------------------------------------------------------

def download_source(repo: str, fname: str) -> str:
    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        sys.exit("--download needs huggingface_hub: pip install huggingface_hub")
    log(f"downloading {repo}/{fname} (~23.6 GB) …")
    path = hf_hub_download(repo_id=repo, filename=fname, repo_type="dataset")
    log(f"source at {path}")
    return path


def verify_source(con: sqlite3.Connection) -> None:
    """Confirm the attached source has the node/relation/edge shape we expect."""
    tables = {r[0] for r in con.execute(
        "SELECT name FROM src.sqlite_master WHERE type='table'")}
    for t in ("node", "relation", "edge"):
        if t not in tables:
            sys.exit(f"source missing table '{t}' (found: {sorted(tables)}). "
                     "Source schema differs from PLAN.md §3 — inspect before building.")
    ncols = {r[1] for r in con.execute("PRAGMA src.table_info(node)")}
    ecols = {r[1] for r in con.execute("PRAGMA src.table_info(edge)")}
    if not {"id", "language"} <= ncols:
        sys.exit(f"src.node columns unexpected: {sorted(ncols)}")
    if not {"start_id", "end_id", "rel_id", "weight"} <= ecols:
        sys.exit(f"src.edge columns unexpected: {sorted(ecols)}")
    langs = [r[0] for r in con.execute(
        "SELECT DISTINCT language FROM src.node LIMIT 8")]
    log(f"source verified (node/relation/edge); sample languages: {langs}")


# ---------------------------------------------------------------------------
# DB setup
# ---------------------------------------------------------------------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS rel_norm(
    rel_pk  INTEGER PRIMARY KEY,
    rel_url TEXT UNIQUE NOT NULL);
CREATE TABLE IF NOT EXISTS node_norm(
    node_pk  INTEGER PRIMARY KEY,
    node_url TEXT NOT NULL,
    language TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS edge_norm(
    start_fk INTEGER NOT NULL,
    end_fk   INTEGER NOT NULL,
    rel_fk   INTEGER NOT NULL,
    weight   REAL    NOT NULL);
"""


def open_out(out: str, src: str, cache_mb: int, journal: str, tmpdir: str) -> sqlite3.Connection:
    # SQLITE_TMPDIR must be set before connecting; it's where external-merge
    # sorts (the big index builds) spill — put it on the roomy disk.
    os.environ["SQLITE_TMPDIR"] = tmpdir
    Path(tmpdir).mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(out)
    con.execute(f"PRAGMA journal_mode = {journal}")
    con.execute("PRAGMA synchronous = NORMAL")
    con.execute(f"PRAGMA cache_size = {-cache_mb * 1024}")  # negative => KiB
    con.execute("PRAGMA temp_store = FILE")
    con.execute("PRAGMA foreign_keys = OFF")
    con.execute("ATTACH DATABASE ? AS src", (src,))
    _ensure_meta(con)
    con.executescript(SCHEMA)
    con.commit()
    return con


# ---------------------------------------------------------------------------
# Build phases
# ---------------------------------------------------------------------------

def phase_rel(con: sqlite3.Connection) -> None:
    if done(con, "rel"):
        return
    log("rel_norm …")
    con.execute("DELETE FROM rel_norm")
    con.execute("INSERT INTO rel_norm(rel_url) SELECT DISTINCT id FROM src.relation")
    n = con.execute("SELECT COUNT(*) FROM rel_norm").fetchone()[0]
    mark_done(con, "rel")
    log(f"rel_norm: {n} relations")


def phase_nodes(con: sqlite3.Connection, dedupe: bool) -> None:
    if done(con, "nodes"):
        return
    log("node_norm … (~28 M rows)")
    con.execute("DROP INDEX IF EXISTS ix_node_url")
    con.execute("DELETE FROM node_norm")
    if dedupe:
        con.execute("INSERT INTO node_norm(node_url, language) "
                    "SELECT id, MIN(language) FROM src.node GROUP BY id")
    else:
        con.execute("INSERT INTO node_norm(node_url, language) "
                    "SELECT id, language FROM src.node")
    con.commit()
    log("node_norm: building UNIQUE index ix_node_url (external sort on disk) …")
    try:
        con.execute("CREATE UNIQUE INDEX ix_node_url ON node_norm(node_url)")
    except sqlite3.IntegrityError:
        sys.exit("duplicate node_url in source — re-run with --dedupe-nodes.")
    n = con.execute("SELECT COUNT(*) FROM node_norm").fetchone()[0]
    mark_done(con, "nodes")
    log(f"node_norm: {n:,} nodes indexed")


def phase_edges(con: sqlite3.Connection, batch: int, limit: int | None) -> None:
    if done(con, "edges"):
        return
    total = con.execute("SELECT COUNT(*) FROM src.edge").fetchone()[0]
    if limit:
        total = min(total, limit)
    last = int(get_meta(con, "last_edge_rowid") or 0)
    if last:
        log(f"resuming edges from src.edge rowid > {last:,}")
    log(f"edge_norm … target {total:,} rows, batch {batch:,}")

    while True:
        # Upper rowid bound for this batch via a *bounded* OFFSET (within the
        # batch only — never a global OFFSET, which would be O(n^2)).
        hi_row = con.execute(
            "SELECT rowid FROM src.edge WHERE rowid > ? ORDER BY rowid "
            "LIMIT 1 OFFSET ?", (last, batch - 1)).fetchone()
        hi = hi_row[0] if hi_row else con.execute(
            "SELECT MAX(rowid) FROM src.edge").fetchone()[0]
        if hi is None or hi <= last:
            break
        # Insert + advance the resume marker atomically (one WAL transaction).
        con.execute(
            "INSERT INTO edge_norm(start_fk, end_fk, rel_fk, weight) "
            "SELECT n1.node_pk, n2.node_pk, r.rel_pk, e.weight "
            "FROM src.edge e "
            "JOIN node_norm n1 ON n1.node_url = e.start_id "
            "JOIN node_norm n2 ON n2.node_url = e.end_id "
            "JOIN rel_norm  r  ON r.rel_url  = e.rel_id "
            "WHERE e.rowid > ? AND e.rowid <= ?", (last, hi))
        set_meta(con, "last_edge_rowid", hi)
        con.commit()
        con.execute("PRAGMA wal_checkpoint(TRUNCATE)")  # keep WAL bounded
        last = hi
        inserted = con.execute("SELECT COUNT(*) FROM edge_norm").fetchone()[0]
        log(f"edge_norm: ~{min(last, total):,}/{total:,} src rows scanned, "
            f"{inserted:,} edges")
        if limit and last >= limit:
            break
    mark_done(con, "edges")
    n = con.execute("SELECT COUNT(*) FROM edge_norm").fetchone()[0]
    log(f"edge_norm: {n:,} edges")


def phase_indexes(con: sqlite3.Connection) -> None:
    if done(con, "indexes"):
        return
    log("edge indexes (external sort on disk; the other slow step) …")
    con.execute("CREATE INDEX IF NOT EXISTS ix_edge_start_rel "
                "ON edge_norm(start_fk, rel_fk)")
    con.execute("CREATE INDEX IF NOT EXISTS ix_edge_end_rel "
                "ON edge_norm(end_fk, rel_fk)")
    mark_done(con, "indexes")
    log("edge indexes built")


def phase_finalize(con: sqlite3.Connection) -> None:
    if done(con, "finalize"):
        return
    log("ANALYZE …")
    con.execute("ANALYZE")
    con.commit()
    # VACUUM cannot run inside a transaction and needs ~dest-size temp disk.
    log("VACUUM … (needs ~dest-size free disk for its temp copy)")
    con.execute("VACUUM")
    mark_done(con, "finalize")
    log("finalized")


def write_runlog(out: str, args, counts: dict) -> None:
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y-%m-%dT%H-%M-%S", time.gmtime())
    summary = {
        "stamp_utc": stamp,
        "git_sha": _git_sha(),
        "wall_minutes": round((time.monotonic() - _t0) / 60, 1),
        "out": out,
        "out_size_bytes": Path(out).stat().st_size if Path(out).exists() else None,
        "args": {k: v for k, v in vars(args).items()},
        "counts": counts,
    }
    path = RUNS_DIR / f"{stamp}.log"
    path.write_text(json.dumps(summary, indent=2) + "\n")
    log(f"run log → {path}")


def upload(out: str, repo: str, fname: str) -> None:
    try:
        from huggingface_hub import HfApi
    except ImportError:
        sys.exit("--upload-repo needs huggingface_hub: pip install huggingface_hub")
    log(f"uploading {out} → {repo}/{fname} …")
    HfApi().upload_file(path_or_fileobj=out, path_in_repo=fname,
                        repo_id=repo, repo_type="dataset")
    log("uploaded")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Normalize all-languages ConceptNet (8 GB-friendly, resumable)")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--src", help="path to conceptnet-de-indexed.db (23.6 GB)")
    src.add_argument("--download", action="store_true",
                     help=f"download {DEFAULT_SRC_REPO}/{DEFAULT_SRC_FILE} from HF")
    ap.add_argument("--src-repo", default=DEFAULT_SRC_REPO)
    ap.add_argument("--src-file", default=DEFAULT_SRC_FILE)
    ap.add_argument("--out", default=DEFAULT_OUT_FILE)
    ap.add_argument("--tmpdir", default=None,
                    help="dir for SQLite temp/sort spill (default: alongside --out)")
    ap.add_argument("--cache-mb", type=int, default=256, help="page cache (RAM)")
    ap.add_argument("--batch", type=int, default=500_000, help="edge rows per commit")
    ap.add_argument("--journal", choices=["wal", "off"], default="wal",
                    help="wal = crash-safe + resumable (default); off = fastest")
    ap.add_argument("--dedupe-nodes", action="store_true",
                    help="GROUP BY node id if the source has duplicate node URLs")
    ap.add_argument("--fresh", action="store_true",
                    help="ignore resume state; rebuild from scratch")
    ap.add_argument("--limit", type=int, default=None,
                    help="process only the first N src edges (smoke test)")
    ap.add_argument("--upload-repo", default=None,
                    help=f"push result, e.g. {DEFAULT_OUT_REPO}")
    ap.add_argument("--upload-file", default=DEFAULT_OUT_FILE)
    args = ap.parse_args()

    src_path = download_source(args.src_repo, args.src_file) if args.download else args.src
    if not Path(src_path).exists():
        sys.exit(f"source not found: {src_path}")
    if args.fresh and Path(args.out).exists():
        log(f"--fresh: removing {args.out}")
        Path(args.out).unlink()

    tmpdir = args.tmpdir or str(Path(args.out).resolve().parent)
    con = open_out(args.out, src_path, args.cache_mb, args.journal, tmpdir)
    log(f"out={args.out}  cache={args.cache_mb}MB  journal={args.journal}  "
        f"tmpdir={tmpdir}  batch={args.batch:,}")
    verify_source(con)

    phase_rel(con)
    phase_nodes(con, args.dedupe_nodes)
    phase_edges(con, args.batch, args.limit)
    phase_indexes(con)
    phase_finalize(con)

    counts = {t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
              for t in ("rel_norm", "node_norm", "edge_norm")}
    log(f"counts: {counts}")
    con.close()

    write_runlog(args.out, args, counts)
    if args.upload_repo:
        upload(args.out, args.upload_repo, args.upload_file)
    log("done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
