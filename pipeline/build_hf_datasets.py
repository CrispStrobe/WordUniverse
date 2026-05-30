"""Build (and optionally upload) the Hugging Face dataset bundles for the two
vocabulary DBs.

Each bundle is a self-contained folder ready to push to a HF dataset repo:

  pipeline/hf_export/grundwortschatz-voc-de/
    README.md                 ← the dataset card (from voc-de/HF_DATASET_README.md)
    words.parquet             ← viewable tabular splits (declared in the card)
    translations.parquet
    examples.parquet
    grundwortschatz.db.gz      ← the canonical SQLite asset (raw download)

  pipeline/hf_export/grundwortschatz-voc-en/
    README.md, words/translations/examples/phrasal_verbs/false_friends.parquet,
    grundwortschatz_en.db.gz

Licenses (declared in each card's YAML front matter):
  voc-de = GPL-3.0  (bundles childLex GPL-3.0)
  voc-en = CC-BY-SA-4.0

IMPORTANT — German DB is downloaded by the app at first launch (it is GPL-3.0
and intentionally NOT bundled in the store binary). After rebuilding +
re-uploading `grundwortschatz.db.gz` here, update the integrity pins in
`lib/core/services/vocabulary_service.dart` (`_dbSources['de']`):
  - expectedCompressedBytes      = byte size of the new grundwortschatz.db.gz
  - expectedDecompressedBytes    = byte size of the decompressed .db
  - expectedDecompressedSha256   = `shasum -a 256` of the decompressed .db
The sha256 is a soft check (logged, non-fatal), so a forgotten bump degrades
gracefully rather than bricking first launch — but keep it correct.

Requirements (NOT in the system python — use the conda base which has them):
  ~/miniconda3/bin/python -m pip install pyarrow huggingface_hub   # if missing

Usage:
  # 1. Build the parquet + stage the bundles (no network):
  ~/miniconda3/bin/python pipeline/build_hf_datasets.py

  # 2. Upload (needs a write token — `huggingface-cli login` or HF_TOKEN env):
  ~/miniconda3/bin/python pipeline/build_hf_datasets.py --upload
  #   add --owner youruser to override the default 'cstr' namespace

The export folder is git-ignored (regenerate any time); only the README cards
are tracked in the repo.
"""
from __future__ import annotations

import argparse
import gzip
import os
import shutil
import sqlite3
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parent.parent          # repo root
EXPORT = Path(__file__).resolve().parent / "hf_export"

# words columns to export (drop app-internal audio_path; keep JSON blobs as text)
WORD_COLS = ["id", "original_id", "word", "lemma", "article", "genus",
             "word_type", "grade_level", "frequency_json", "enrichment_json",
             "metadata_json"]

DATASETS = {
    "de": {
        "repo": "grundwortschatz-voc-de",
        "db": ROOT / "pipeline/voc-de/grundwortschatz.db",
        "gz": ROOT / "assets/grundwortschatz.db.gz",
        "card": ROOT / "pipeline/voc-de/HF_DATASET_README.md",
        "license": "gpl-3.0",
        "tables": {
            "words": WORD_COLS,
            "translations": ["id", "word_id", "lang_code", "translation"],
            "examples": ["id", "word_id", "sentence"],
        },
    },
    "en": {
        "repo": "grundwortschatz-voc-en",
        "db": ROOT / "pipeline/voc-en/grundwortschatz_en.db",
        "gz": ROOT / "assets/grundwortschatz_en.db.gz",
        "card": ROOT / "pipeline/voc-en/HF_DATASET_README.md",
        "license": "cc-by-sa-4.0",
        "tables": {
            "words": WORD_COLS,
            "translations": ["id", "word_id", "lang_code", "translation"],
            "examples": ["id", "word_id", "sentence"],
            "phrasal_verbs": ["id", "word_id", "phrasal", "base_verb",
                              "particle", "meaning", "senses_json",
                              "distractors_json", "examples_json",
                              "wiktionary_examples_json", "synonyms_json",
                              "grade_band", "base_zipf", "source", "license"],
            "false_friends": ["id", "word_id", "english", "german",
                              "english_means", "german_means", "example",
                              "source", "license"],
        },
    },
}


def export_table(con: sqlite3.Connection, table: str, cols: list, out: Path) -> int:
    rows = con.execute(f"SELECT {', '.join(cols)} FROM {table}").fetchall()
    data = {c: [r[i] for r in rows] for i, c in enumerate(cols)}
    pq.write_table(pa.table(data), out, compression="zstd")
    return len(rows)


def build_one(key: str) -> Path:
    spec = DATASETS[key]
    stage = EXPORT / spec["repo"]
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)

    # README (HF dataset card must be named README.md)
    if not spec["card"].exists():
        raise SystemExit(f"missing card: {spec['card']}")
    shutil.copyfile(spec["card"], stage / "README.md")

    # parquet splits
    con = sqlite3.connect(spec["db"])
    for table, cols in spec["tables"].items():
        n = export_table(con, table, cols, stage / f"{table}.parquet")
        print(f"  {spec['repo']}/{table}.parquet  ({n:,} rows)")
    con.close()

    # canonical compressed SQLite (recompress from the live .db so it's fresh)
    gz_out = stage / spec["gz"].name
    with open(spec["db"], "rb") as fin, gzip.open(gz_out, "wb", compresslevel=9) as fout:
        shutil.copyfileobj(fin, fout)
    print(f"  {spec['repo']}/{gz_out.name}  ({gz_out.stat().st_size/1e6:.1f} MB)")
    return stage


def upload_one(key: str, stage: Path, owner: str, token: str | None):
    from huggingface_hub import HfApi
    spec = DATASETS[key]
    repo_id = f"{owner}/{spec['repo']}"
    api = HfApi(token=token)
    api.create_repo(repo_id, repo_type="dataset", exist_ok=True)
    print(f"  → uploading to {repo_id} (license {spec['license']}) …")
    api.upload_folder(folder_path=str(stage), repo_id=repo_id,
                      repo_type="dataset",
                      commit_message="Update WortUniversum vocabulary dataset")
    print(f"  ✓ https://huggingface.co/datasets/{repo_id}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload", action="store_true", help="push to HF (needs token)")
    ap.add_argument("--owner", default="cstr", help="HF namespace (default cstr)")
    ap.add_argument("--only", choices=["de", "en"], help="build just one")
    args = ap.parse_args()

    keys = [args.only] if args.only else ["de", "en"]
    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")

    stages = {}
    for k in keys:
        print(f"\n=== building {DATASETS[k]['repo']} ===")
        stages[k] = build_one(k)

    if args.upload:
        print("\n=== uploading ===")
        for k in keys:
            upload_one(k, stages[k], args.owner, token)
    else:
        print(f"\nStaged under {EXPORT}/ — re-run with --upload to push.")


if __name__ == "__main__":
    main()
