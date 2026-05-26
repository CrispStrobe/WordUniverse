#!/usr/bin/env bash
# build_de_enrichment.sh — Post-build enrichment pipeline for the DE vocabulary DB.
#
# Runs the full enrichment stack (Gutenberg examples + LLM grade examples, 2 passes)
# starting from grundwortschatz.db and producing assets/grundwortschatz.db.gz.
#
# Prerequisites:
#   - grundwortschatz.db must exist in this directory (output of step 14)
#   - .env (or ../../.env) must have GROQ_API_KEY, NEBIUS_API_KEY, SCALEWAY_API_KEY,
#     MISTRAL_API_KEY, COHERE_API_KEY populated
#   - sources/gutenberg_corpus.db must exist (built by add_gutenberg_examples.py --build)
#
# Usage:
#   cd pipeline/voc-de
#   bash build_de_enrichment.sh [--workers N] [--no-gutenberg] [--passes N]
#
# All steps are idempotent — safe to re-run after interruption.

set -euo pipefail

WORKERS=3
PASSES=2
SKIP_GUTENBERG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workers) WORKERS="$2"; shift 2 ;;
        --passes)  PASSES="$2";  shift 2 ;;
        --no-gutenberg) SKIP_GUTENBERG=1; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="$SCRIPT_DIR/grundwortschatz.db"

if [[ ! -f "$DB" ]]; then
    echo "ERROR: $DB not found. Run steps 01-14 first."
    exit 1
fi

echo "=== DE enrichment build ==="
echo "DB:       $DB"
echo "Workers:  $WORKERS"
echo "Passes:   $PASSES"
echo ""

# Step 15: Gutenberg example sentences
if [[ $SKIP_GUTENBERG -eq 0 ]]; then
    echo "--- Step 15: Gutenberg examples ---"
    python3 "$SCRIPT_DIR/add_gutenberg_examples.py" --db "$DB"
    echo ""
fi

# Steps 16-17 × PASSES: grade fill → cleanup dupes → check-all → cleanup partials
for (( pass=1; pass<=PASSES; pass++ )); do
    echo "--- Pass $pass/$PASSES: grade fill ---"
    python3 "$SCRIPT_DIR/add_llm_examples.py" --db "$DB" --grade --workers "$WORKERS" --no-compress

    echo "--- Pass $pass/$PASSES: cleanup Vorname dupes ---"
    python3 "$SCRIPT_DIR/add_llm_examples.py" --db "$DB" --cleanup --no-compress

    echo "--- Pass $pass/$PASSES: check-all ---"
    python3 "$SCRIPT_DIR/add_llm_examples.py" --db "$DB" --check-all --workers "$WORKERS" --no-compress

    if (( pass < PASSES )); then
        echo "--- Pass $pass/$PASSES: wipe partials for next grade pass ---"
        python3 "$SCRIPT_DIR/add_llm_examples.py" --db "$DB" --cleanup --wipe-partials --no-compress
    fi

    echo ""
done

# Final compress to assets
echo "--- Final: compress to assets ---"
ASSETS_GZ="$SCRIPT_DIR/../../assets/grundwortschatz.db.gz"
python3 -c "
import gzip, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, 'rb') as fi, gzip.open(dst, 'wb', compresslevel=6) as fo:
    shutil.copyfileobj(fi, fo)
import os; print(f'Written {dst} ({os.path.getsize(dst)//1024} KB)')
" "$DB" "$ASSETS_GZ"

echo ""
echo "=== Build complete ==="
