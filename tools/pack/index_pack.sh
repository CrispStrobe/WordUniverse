#!/usr/bin/env bash
#
# Write the feature index into a pack, so no device has to derive it.
#
#   tools/pack/index_pack.sh <pack.db>
#
# See test/audit/index_pack_test.dart, which this wraps: the work needs the
# app's own code, and that needs the Flutter VM.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ $# -eq 1 ] || { echo "usage: $(basename "$0") <pack.db>" >&2; exit 2; }
pack="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
[ -f "$pack" ] || { echo "index_pack: no pack at $pack" >&2; exit 2; }
cd "$root"
WU_INDEX_PACK="$pack" flutter test test/audit/index_pack_test.dart |
  grep -E 'indexed|Some tests failed|All tests passed' || true
