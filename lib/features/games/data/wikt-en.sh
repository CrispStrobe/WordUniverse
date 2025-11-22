#!/bin/bash

# --- Robust Shell Script Settings ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Exit immediately if an unset variable is used.
set -u
# Fail a pipeline if any command in it fails (not just the last one).
set -o pipefail

# --- Configuration ---
# Set the username for your Hugging Face account (MUST BE SET IN ENV)
# export HF_USERNAME="your-hf-username"
# export HF_TOKEN="your-hf-token-with-write-access"

# Define a safe working directory in /tmp
WORK_DIR="/tmp/wiktionary_extract"
CLONE_DIR="$WORK_DIR/wiktextract"
VENV_DIR="$WORK_DIR/venv"
UPLOAD_SCRIPT_NAME="$WORK_DIR/upload_to_hf.py"

# Wiktionary Dump Configuration
DUMP_URL="https://dumps.wikimedia.org/enwiktionary/latest/enwiktionary-latest-pages-articles.xml.bz2"
DUMP_FILE="$WORK_DIR/enwiktionary-latest.xml.bz2"
OUTPUT_FILE="$WORK_DIR/en-wiktionary.jsonl"
REPO_NAME="en-wiktionary-extracted"

# --- Helper Functions ---
echo_step() {
    echo ""
    echo "#################################################################"
    echo "### $1"
    echo "#################################################################"
}

check_command() {
  if ! command -v $1 &> /dev/null; then
    echo "Error: Required command '$1' not found."
    echo "Please install it using your system's package manager."
    echo "(e.g., On Debian/Ubuntu: sudo apt-get install -y $2)"
    exit 1
  fi
}

# === 1. Prerequisite Checks ===
echo_step "1. Checking Prerequisites..."

check_command "python3" "python3 python3-venv"
check_command "git" "git"
check_command "wget" "wget"

if [ -z "${HF_USERNAME:-}" ]; then
    echo "Error: HF_USERNAME environment variable is not set."
    echo "Please set it before running: export HF_USERNAME=\"your-username\""
    exit 1
fi

if [ -z "${HF_TOKEN:-}" ]; then
    echo "Error: HF_TOKEN environment variable is not set."
    echo "Please set it before running: export HF_TOKEN=\"your-hf-token\""
    exit 1
fi

export HF_REPO_ID="$HF_USERNAME/$REPO_NAME"
export HF_DATA_FILE="$OUTPUT_FILE"

echo "All prerequisites found."
echo "Hugging Face User: $HF_USERNAME"
echo "Repo ID:           $HF_REPO_ID"

# === 2. Setup Working Environment ===
echo_step "2. Setting up working directory: $WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Creating Python virtual environment at $VENV_DIR..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
echo "Virtual environment activated."

# === 3. Install Python Dependencies ===
echo_step "3. Installing Python dependencies (huggingface_hub, datasets)"
pip install huggingface_hub datasets

# === 4. Install wiktextract from Source ===
echo_step "4. Installing wiktextract from source"

# Clean up any previous attempts
pip uninstall -y wiktextract 2>/dev/null || true
rm -rf "$CLONE_DIR"

echo "Cloning wiktextract repository..."
git clone https://github.com/tatuylonen/wiktextract.git "$CLONE_DIR"

echo "Installing from local clone (editable mode)..."
cd "$CLONE_DIR"
python -m pip install -e .
cd "$WORK_DIR"

echo "wiktextract installation complete."
echo "wiktextract path: $(which python)"

# === 5. Download Wiktionary Dump ===
echo_step "5. Downloading English Wiktionary Dump"
echo "URL: $DUMP_URL"
echo "Output: $DUMP_FILE"

if [ -f "$DUMP_FILE" ]; then
    echo "Dump file already exists. Skipping download."
else
    wget -O "$DUMP_FILE" "$DUMP_URL"
    echo "Download complete."
fi
ls -lh "$DUMP_FILE"

# === 6. Run Wiktextract Processing ===
echo_step "6. Running wiktextract... (This will take a very long time)"
echo "Reading from: $DUMP_FILE"
echo "Writing to:   $OUTPUT_FILE"

# Clean up any old output file
rm -f "$OUTPUT_FILE"

python -m wiktextract.wiktwords \
    --all \
    --edition de \
    --language-name English \
    --out "$OUTPUT_FILE" \
    "$DUMP_FILE"

echo "Processing complete!"
ls -lh "$OUTPUT_FILE"

# === 7. Create Python Upload Script ===
echo_step "7. Creating HF upload script: $UPLOAD_SCRIPT_NAME"

# Use a "here document" (cat << EOF) to write the Python script
cat << EOF > "$UPLOAD_SCRIPT_NAME"
import os
import sys
from datasets import load_dataset
from huggingface_hub import login

try:
    # Read variables set by the shell script
    HF_TOKEN = os.environ["HF_TOKEN"]
    REPO_ID = os.environ["HF_REPO_ID"]
    DATA_FILE = os.environ["HF_DATA_FILE"]

except KeyError as e:
    print(f"Error: Missing environment variable: {e}", file=sys.stderr)
    print("This script should be run by the main shell script.", file=sys.stderr)
    sys.exit(1)


if not os.path.exists(DATA_FILE):
    print(f"Error: Output file '{DATA_FILE}' not found.", file=sys.stderr)
    print("Did the 'wiktextract' processing step fail?", file=sys.stderr)
    sys.exit(1)

try:
    print(f"Logging in to Hugging Face as {os.environ.get('HF_USERNAME')}...")
    login(token=HF_TOKEN)
    print("Login successful.")

    print(f"Loading generated {DATA_FILE} into a Dataset object...")
    extracted_dataset = load_dataset('json', data_files=DATA_FILE, split='train')
    print(extracted_dataset)

    print(f"Pushing dataset to the Hub at {REPO_ID}...")
    extracted_dataset.push_to_hub(REPO_ID)

    print("\n--- Upload Complete! ---")
    print(f"View your dataset at: https://huggingface.co/datasets/{REPO_ID}")

except Exception as e:
    print(f"An error occurred during the upload process: {e}", file=sys.stderr)
    sys.exit(1)
EOF

echo "Upload script created."

# === 8. Run Python Upload Script ===
echo_step "8. Running upload script..."

# The required env vars (HF_TOKEN, HF_REPO_ID, HF_DATA_FILE)
# are already exported in this shell session.
python "$UPLOAD_SCRIPT_NAME"

# === 9. Cleanup ===
echo_step "9. Deactivating virtual environment"
deactivate

echo ""
echo "--- All steps completed successfully! ---"
echo "Working directory was: $WORK_DIR"
echo "You can now inspect the files or remove the directory: rm -r $WORK_DIR"
