#!/usr/bin/env bash
# The local gate ladder, in one command. Run this before every commit.
#
#   bash tool/gates.sh            # G0..G5 at tier T0
#   bash tool/gates.sh --tier=T1  # same, wider differential tier
#
# Gates that need the upstream workspace (the Java oracle, the .adk corpus) are SKIPPED
# with a loud notice when it is absent -- a fresh clone of this repository alone cannot
# run them. Skipped is reported separately from passed, because a ladder that counts a
# skip as a pass is how a gate quietly stops testing anything.
set -uo pipefail

cd "$(dirname "$0")/.."
source tool/env.sh >/dev/null

TIER="T0"
for a in "$@"; do
  case "$a" in
    --tier=*) TIER="${a#*=}" ;;
    *) echo "gates.sh: unknown option $a" >&2; exit 2 ;;
  esac
done

PASS=0; FAIL=0; SKIP=0
_run() {                       # _run <name> <command...>
  local name="$1"; shift
  printf '\n=== %s ===\n' "$name"
  if "$@"; then PASS=$((PASS+1)); echo "  -> PASS  $name"
  else FAIL=$((FAIL+1)); echo "  -> FAIL  $name"; fi
}
_skip() { SKIP=$((SKIP+1)); printf '\n=== %s ===\n  -> SKIP  %s\n' "$1" "$2"; }

_run "G0  toolchain contract"        bash tool/env.sh --check
_run "G1  dart format"               "$DART" format --output=none --set-exit-if-changed .
_run "G2  engine purity"             "$DART" run tool/check_engine_purity.dart packages/sudoku_engine
_run "G3  dart analyze"              "$DART" analyze --fatal-infos .
_run "G4  engine unit tests"         bash -c 'cd packages/sudoku_engine && "$DART" test --reporter=compact'

# G5 is the differential gate and it is the only one that can tell you whether the port is
# CORRECT rather than merely well-formed. The four above can all pass on an engine that
# computes the wrong answer.
if [ -x "$HARNESS/tool/diff.sh" ] && [ -d "$UPSTREAM_ASSETS" ]; then
  _run "G5  differential diff $TIER" bash "$HARNESS/tool/diff.sh" --tier="$TIER" --sections=parse,geom,dlx
else
  _skip "G5  differential diff $TIER" "upstream workspace not present at $HARNESS"
fi

printf '\n========================================\n'
printf 'gates: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
printf '========================================\n'
[ "$FAIL" -eq 0 ]
