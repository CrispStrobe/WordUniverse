#!/usr/bin/env bash
#
# Print what the games would ask a learner — or check that every item they
# generate is well formed. A wrapper around test/audit/challenge_dump_test.dart
# and test/audit/challenge_contract_test.dart, so neither needs environment
# variables to drive. See docs/content-audit.md.
#
#   tools/audit/dump.sh --list
#   tools/audit/dump.sh --game definition_quiz --grade 4 --count 30
#   tools/audit/dump.sh --lang de --pack-de ~/grundwortschatz.db --json
#   tools/audit/dump.sh --check --lang de --pack-de ~/grundwortschatz.db

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

game=all
grade=3
lang=en
count=20
seed=1
format=text
out=
pack_de="${WU_PACK_DE:-}"
mode=dump

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'USAGE'

  --game NAME[,NAME]  one or more games, or "all" (default: all)
  --grade N           grade band 1-6 to generate for (default: 3)
  --lang en|de        which pack (default: en)
  --count N           items per game (default: 20)
  --seed N            RNG seed, so a review is reproducible (default: 1)
  --json              one JSON object per line instead of text
  --out FILE          write there instead of stdout
  --pack-de PATH      decompressed German pack (or set WU_PACK_DE)
  --list              list the games that can be generated, with their packs
  --check             run the contract test instead of printing items
  -h, --help          this
USAGE
}

die() { echo "dump.sh: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --game)    game="${2:?--game needs a value}"; shift 2 ;;
    --grade)   grade="${2:?--grade needs a value}"; shift 2 ;;
    --lang)    lang="${2:?--lang needs a value}"; shift 2 ;;
    --count)   count="${2:?--count needs a value}"; shift 2 ;;
    --seed)    seed="${2:?--seed needs a value}"; shift 2 ;;
    --out)     out="${2:?--out needs a value}"; shift 2 ;;
    --pack-de) pack_de="${2:?--pack-de needs a value}"; shift 2 ;;
    --json)    format=json; shift ;;
    --list)    mode=list; shift ;;
    --check)   mode=check; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         die "unknown option $1 (try --help)" ;;
  esac
done

command -v flutter >/dev/null || die "flutter is not on PATH"
case "$lang" in en|de) ;; *) die "--lang must be en or de" ;; esac
[ "$lang" = de ] && [ -z "$pack_de" ] && die \
  "the German pack is a download: pass --pack-de /path/to/grundwortschatz.db"
[ -n "$pack_de" ] && [ ! -f "$pack_de" ] && die "no pack at $pack_de"

if [ "$mode" = check ]; then
  # The contract test asserts; its output is the failure report, so it is
  # shown as flutter prints it.
  WU_PACK_DE="$pack_de" exec flutter test test/audit/challenge_contract_test.dart
fi

if [ "$mode" = list ]; then
  # `flutter test` interleaves its own progress with the print; the generator
  # lines are the tab-separated ones.
  WU_DUMP=list flutter test test/audit/challenge_dump_test.dart 2>/dev/null |
    grep -P '^[a-z_]+\t' |
    awk -F'\t' '{printf "  %-26s %s\n", $1, $2}'
  exit 0
fi

# Without --out the dump would arrive interleaved with test progress and log
# lines, so it always goes to a file; a file the caller did not ask for is
# printed and removed.
target="$out"
keep=1
if [ -z "$target" ]; then
  target="$(mktemp -t wu_dump_XXXXXX)"
  keep=0
fi

set +e
WU_DUMP="$game" WU_DUMP_GRADE="$grade" WU_DUMP_LANG="$lang" \
  WU_DUMP_COUNT="$count" WU_DUMP_SEED="$seed" WU_DUMP_FORMAT="$format" \
  WU_DUMP_OUT="$target" WU_PACK_DE="$pack_de" \
  flutter test test/audit/challenge_dump_test.dart >/tmp/wu_dump_run.$$ 2>&1
status=$?
set -e

if [ $status -ne 0 ]; then
  echo "dump.sh: the harness failed" >&2
  cat /tmp/wu_dump_run.$$ >&2
  rm -f /tmp/wu_dump_run.$$
  [ $keep -eq 0 ] && rm -f "$target"
  exit 1
fi
rm -f /tmp/wu_dump_run.$$

if [ $keep -eq 0 ]; then
  cat "$target"
  rm -f "$target"
else
  echo "wrote $(grep -c . "$target") lines to $target" >&2
fi
