#!/usr/bin/env python3
"""Export the EN SQLite DB to Parquet companion files for HF upload.

Output files:
  - pipeline/voc-en/hf_export/words.parquet
  - pipeline/voc-en/hf_export/translations.parquet
  - pipeline/voc-en/hf_export/examples.parquet
"""

from __future__ import annotations

import gzip
import sqlite3
import sys
import time
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

REPO = Path(__file__).resolve().parents[2]
DB_GZ = REPO / "assets" / "grundwortschatz_en.db.gz"
OUT_DIR = REPO / "pipeline" / "voc-en" / "hf_export"
TMP_DB = Path("/tmp/dbpatch/parquet_export_en.db")

WORDS_SCHEMA = pa.schema([
    ("id", pa.int64()),
    ("original_id", pa.string()),
    ("word", pa.string()),
    ("lemma", pa.string()),
    ("article", pa.string()),
    ("genus", pa.string()),
    ("word_type", pa.string()),
    ("grade_level", pa.int32()),
    ("audio_path", pa.string()),
    ("frequency_json", pa.string()),
    ("enrichment_json", pa.string()),
    ("metadata_json", pa.string()),
])

TRANSLATIONS_SCHEMA = pa.schema([
    ("id", pa.int64()),
    ("word_id", pa.int64()),
    ("lang_code", pa.string()),
    ("translation", pa.string()),
])

EXAMPLES_SCHEMA = pa.schema([
    ("id", pa.int64()),
    ("word_id", pa.int64()),
    ("sentence", pa.string()),
])


def export_table(con, select_sql, schema, out_path, batch_size=5000):
    cur = con.cursor()
    cur.execute(select_sql)
    columns = [d[0] for d in cur.description]
    assert columns == [f.name for f in schema], (
        f"schema/SQL column mismatch: {columns} != {[f.name for f in schema]}"
    )

    writer = pq.ParquetWriter(
        out_path,
        schema,
        compression="zstd",
        compression_level=9,
    )
    total = 0
    try:
        while True:
            rows = cur.fetchmany(batch_size)
            if not rows:
                break
            arrays = []
            for ci, field in enumerate(schema):
                arrays.append(pa.array([row[ci] for row in rows], type=field.type))
            writer.write_batch(pa.RecordBatch.from_arrays(arrays, schema=schema))
            total += len(rows)
    finally:
        writer.close()
    return total


def main():
    if not DB_GZ.exists():
        print(f"ERROR: shipped EN DB not found: {DB_GZ}", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TMP_DB.parent.mkdir(parents=True, exist_ok=True)
    if TMP_DB.exists():
        TMP_DB.unlink()

    print(f"Decompressing {DB_GZ} -> {TMP_DB}")
    with gzip.open(DB_GZ, "rb") as fi, TMP_DB.open("wb") as fo:
        fo.write(fi.read())

    con = sqlite3.connect(f"file:{TMP_DB}?mode=ro", uri=True)
    start = time.time()

    n_words = export_table(
        con,
        "SELECT id, original_id, word, lemma, article, genus, word_type, "
        "grade_level, audio_path, frequency_json, enrichment_json, "
        "metadata_json FROM words ORDER BY id",
        WORDS_SCHEMA,
        OUT_DIR / "words.parquet",
    )
    print(f"  wrote words.parquet - {n_words} rows")

    n_trans = export_table(
        con,
        "SELECT id, word_id, lang_code, translation FROM translations ORDER BY id",
        TRANSLATIONS_SCHEMA,
        OUT_DIR / "translations.parquet",
    )
    print(f"  wrote translations.parquet - {n_trans} rows")

    n_ex = export_table(
        con,
        "SELECT id, word_id, sentence FROM examples ORDER BY id",
        EXAMPLES_SCHEMA,
        OUT_DIR / "examples.parquet",
    )
    print(f"  wrote examples.parquet - {n_ex} rows")

    con.close()
    print(f"Done in {time.time() - start:.1f}s. Output: {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
