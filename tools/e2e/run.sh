#!/bin/bash
# Build and serve build/web separately; see README.md.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_DIR"
export BASE_URL="${BASE_URL:-http://127.0.0.1:18100}"
export EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/wu-live-evidence}"
# The suite creates this directory automatically.
# Supports external installs, e.g. NODE_PATH=/tmp/wu-playwright/node_modules
# PLAYWRIGHT_BROWSERS_PATH=/tmp/wu-browsers. Resolve exactly like the .mjs suite.
if ! node -e "require('module').createRequire(process.cwd() + '/tools/e2e/language-setup-live.mjs')('playwright')" 2>/dev/null; then
  printf '%s\n' 'Playwright is not resolvable. See tools/e2e/README.md for setup.' >&2
  exit 1
fi
exec node tools/e2e/language-setup-live.mjs
