#!/usr/bin/env python3
"""Rebuild a canonical Hugging Face dataset from its own repaired database.

    tools/pack/publish_dataset.py de --report
    tools/pack/publish_dataset.py de --upload

The app ships a *slimmed* artifact built from the canonical database, and
tools/pack/repair_pack.py has only ever been run against that artifact. The
canonical database and the parquet files beside it — which is what anybody
else downloads, and what the next rebuild starts from — still carry every
error the repairs fix: 246 rows in German, 1,593 in English, including 730
names typed as ordinary vocabulary and a phrasal verb glossed as another.

Fixing the artifact and not the source means the next rebuild reintroduces
them. This runs the same repair against the canonical database and writes the
parquet files back out from it, so the dataset and the artifact say the same
thing.
"""

import argparse
import gzip
import pathlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent

DATASETS = {
    'de': ('cstr/grundwortschatz-voc-de', 'grundwortschatz.db.gz'),
    'en': ('cstr/grundwortschatz-voc-en', 'grundwortschatz_en.db.gz'),
}

# The published parquet for `words` omits it; every other table is a
# straight dump.
DROPPED_COLUMNS = {'words': {'audio_path'}}

SKIP_TABLES = ('sqlite_sequence', 'word_feature_index', 'word_feature_index_meta')


def tables(db):
    return [
        name for (name,) in db.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")
        if name not in SKIP_TABLES and not name.startswith('search_index')
    ]


def export_parquet(database, out_dir):
    """Writes one parquet per table, matching what the dataset publishes."""
    import pyarrow as pa
    import pyarrow.parquet as pq

    db = sqlite3.connect(database)
    db.row_factory = sqlite3.Row
    written = []
    for table in tables(db):
        columns = [r[1] for r in db.execute(f'PRAGMA table_info({table})')
                   if r[1] not in DROPPED_COLUMNS.get(table, ())]
        rows = db.execute(
            f'SELECT {", ".join(columns)} FROM {table}').fetchall()
        arrays = {c: [row[c] for row in rows] for c in columns}
        path = out_dir / f'{table}.parquet'
        # Matching what is published: same columns, same types, and zstd,
        # which is what makes words.parquet 18 MB rather than 31.
        pq.write_table(pa.table(arrays), path, compression='zstd')
        written.append((table, len(rows), path))
    db.close()
    return written


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('language', choices=sorted(DATASETS))
    parser.add_argument('--database', type=pathlib.Path, required=True,
                        help='the canonical .db, already decompressed')
    parser.add_argument('--out', type=pathlib.Path,
                        help='where to write the rebuilt files')
    parser.add_argument('--report', action='store_true',
                        help='repair and export, but upload nothing')
    parser.add_argument('--upload', action='store_true')
    args = parser.parse_args()

    if not args.report and not args.upload:
        sys.exit('choose --report or --upload')

    repo, remote_name = DATASETS[args.language]
    out = args.out or pathlib.Path(tempfile.mkdtemp(prefix='wu-dataset-'))
    out.mkdir(parents=True, exist_ok=True)

    repaired = out / args.database.name.replace('.db', '.repaired.db')
    print(f'repairing {args.database.name} -> {repaired.name}')
    subprocess.run(
        [sys.executable, str(HERE / 'repair_pack.py'), str(args.database),
         '--out', str(repaired)],
        check=True)

    print('exporting parquet')
    for table, rows, path in export_parquet(repaired, out):
        print(f'  {table:16} {rows:7d} rows  {path.stat().st_size:>10} bytes')

    archive = out / remote_name
    with open(repaired, 'rb') as src, gzip.open(archive, 'wb', 9) as dst:
        shutil.copyfileobj(src, dst)
    print(f'  {remote_name:16} {archive.stat().st_size:>10} bytes')

    if args.report:
        print(f'\nreport only; nothing uploaded. Files are in {out}')
        return 0

    from huggingface_hub import HfApi
    api = HfApi()
    commit = api.upload_folder(
        folder_path=str(out),
        repo_id=repo,
        repo_type='dataset',
        allow_patterns=['*.parquet', remote_name],
        commit_message='Apply the repairs the app artifact already carries',
        commit_description=(
            'tools/pack/repair_pack.py had only ever been run against the '
            'slimmed artifact the app downloads. The canonical database here, '
            'and the parquet files beside it, still carried every error it '
            'fixes — so anybody rebuilding from this dataset got them back.\n\n'
            'Same tool, same rules, run against the canonical database and '
            'the parquet files written back out from it.'),
    )
    print(f'\nuploaded: {commit.oid}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
