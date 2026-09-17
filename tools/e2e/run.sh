#!/bin/bash
# Build/serve separately, or set BASE_URL to a production host. See README.md.
set -euo pipefail
E2E_DIR="$(cd "$(dirname "$0")" && pwd)"
# No dependency on legacy external NODE_PATH installations.
unset NODE_PATH
exec node "$E2E_DIR/run-live.mjs"
