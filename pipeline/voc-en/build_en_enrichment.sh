#!/usr/bin/env bash
# build_en_enrichment.sh — Post-build enrichment pipeline for the EN vocabulary DB.
#
# Runs the full enrichment stack in order:
#   1. wordfreq frequency bands
#   2. CEFR-J level tags
#   3. Cambridge YLE + DE curriculum tags
#   4. Gutenberg example sentences (optional, --no-gutenberg to skip)
#   5. LLM grade examples (N passes, default 2)
#
# Starting from grundwortschatz_en.db → assets/grundwortschatz_en.db.gz.
#
# Prerequisites:
#   - grundwortschatz_en.db must exist in this directory (output of step 14)
#   - pip install wordfreq
#   - .env (or ../../.env) must have GROQ_API_KEY, NEBIUS_API_KEY, SCALEWAY_API_KEY,
#     MISTRAL_API_KEY, COHERE_API_KEY populated
#
# Usage:
#   cd pipeline/voc-en
#   bash build_en_enrichment.sh [--workers N] [--no-gutenberg] [--passes N]
#
# All steps are idempotent — safe to re-run after interruption.

set -euo pipefail

WORKERS=3
PASSES=2
SKIP_GUTENBERG=0
SKIP_WIKT_ENRICH=0
SKIP_OEWN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workers) WORKERS="$2"; shift 2 ;;
        --passes)  PASSES="$2";  shift 2 ;;
        --no-gutenberg) SKIP_GUTENBERG=1; shift ;;
        --no-wikt-enrich) SKIP_WIKT_ENRICH=1; shift ;;
        --no-oewn) SKIP_OEWN=1; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="$SCRIPT_DIR/grundwortschatz_en.db"

if [[ ! -f "$DB" ]]; then
    echo "ERROR: $DB not found. Run steps 01-14 first."
    exit 1
fi

echo "=== EN enrichment build ==="
echo "DB:       $DB"
echo "Workers:  $WORKERS"
echo "Passes:   $PASSES"
echo ""

# Step 15a: Add missing curriculum words (CEFR-J A1-B2, YLE, UK statutory)
echo "--- Step 15a: add missing curriculum words ---"
python3 "$SCRIPT_DIR/add_missing_curriculum_en.py" --db "$DB" --no-compress
echo ""

# Step 15b: Word frequency bands (wordfreq)
echo "--- Step 15b: wordfreq frequency bands ---"
python3 "$SCRIPT_DIR/add_wordfreq_en.py" --db "$DB" --no-compress
echo ""

# Step 15c: CEFR-J level tags
echo "--- Step 15c: CEFR-J level tags ---"
python3 "$SCRIPT_DIR/add_cefr_en.py" --db "$DB" --no-compress
echo ""

# Step 15d: Cambridge YLE + DE curriculum tags
echo "--- Step 15d: Cambridge YLE + DE curriculum tags ---"
python3 "$SCRIPT_DIR/add_curriculum_en.py" --db "$DB" --no-compress
echo ""

# Step 15e: UK statutory word lists + gradeLevelEstimate
echo "--- Step 15e: UK curriculum + gradeLevelEstimate ---"
python3 "$SCRIPT_DIR/add_uk_curriculum.py" --db "$DB" --no-compress
echo ""

# Step 15f: Gutenberg example sentences
if [[ $SKIP_GUTENBERG -eq 0 ]]; then
    echo "--- Step 15f: Gutenberg examples ---"
    python3 "$SCRIPT_DIR/add_gutenberg_examples_en.py" --db "$DB" --no-compress
    echo ""
fi

# Step 15g: Wiktionary enrichment for minimal entries (requires external Wiktionary DB)
if [[ $SKIP_WIKT_ENRICH -eq 0 ]]; then
    WIKT_DB="/Volumes/backups/code/WiktionaryEN-space/en_wiktionary_normalized.db"
    if [[ -f "$WIKT_DB" ]]; then
        echo "--- Step 15g: Wiktionary enrichment for minimal entries ---"
        python3 "$SCRIPT_DIR/enrich_minimal_en.py" --db "$DB" --workers "$WORKERS" --no-compress
        echo ""
    else
        echo "--- Step 15g: SKIPPED (Wiktionary DB not at $WIKT_DB) ---"
        echo "    Run manually: python3 enrich_minimal_en.py --db $DB"
        echo ""
    fi
fi

# Step 15h: OEWN (WordNet) sense expansion for entries with empty wordnetSenses
if [[ $SKIP_OEWN -eq 0 ]]; then
    echo "--- Step 15h: OEWN sense expansion ---"
    python3 "$SCRIPT_DIR/add_oewn_en.py" --db "$DB" --filter-status any --no-compress
    echo ""
fi

# Steps 16-17 × PASSES: grade fill → check-all → wipe partials (between passes)
for (( pass=1; pass<=PASSES; pass++ )); do
    echo "--- Pass $pass/$PASSES: grade fill ---"
    python3 "$SCRIPT_DIR/add_llm_examples_en.py" --db "$DB" --grade --workers "$WORKERS" --no-compress

    echo "--- Pass $pass/$PASSES: check-all ---"
    python3 "$SCRIPT_DIR/add_llm_examples_en.py" --db "$DB" --check-all --workers "$WORKERS" --no-compress

    if (( pass < PASSES )); then
        echo "--- Pass $pass/$PASSES: wipe partials for next grade pass ---"
        python3 "$SCRIPT_DIR/add_llm_examples_en.py" --db "$DB" --cleanup --wipe-partials --no-compress
    fi

    echo ""
done

# Final compress to assets
echo "--- Final: compress to assets ---"
ASSETS_GZ="$SCRIPT_DIR/../../assets/grundwortschatz_en.db.gz"
python3 -c "
import gzip, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, 'rb') as fi, gzip.open(dst, 'wb', compresslevel=6) as fo:
    shutil.copyfileobj(fi, fo)
import os; print(f'Written {dst} ({os.path.getsize(dst)//1024} KB)')
" "$DB" "$ASSETS_GZ"

echo ""
echo "=== Build complete ==="
