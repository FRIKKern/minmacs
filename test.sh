#!/bin/sh
# The shared test harness for MinMacs 2.0. Fixtures only.
# Usage: ./test.sh [section ...]    a section is a file in test/, such as test/locohost.sh. Default is all of them.
#
# The harness builds its own copy of the app into a temporary MINMACS_HOME and tests that copy.
# It never uses ~/Applications/MinMacs.app or ~/.local/bin/minmacs, and never launches the app.
# Every section runs with the same shell, so it can use the helpers and variables below:
#   check <name> <want> <got>   one result line; a mismatch counts as a failure
#   json <expr>                 evaluates a Python expression on JSON from stdin, with the parsed value as j
#   APP, BIN, MINMACS_HOME, ROOT
# A section starts its own fixtures inside $MINMACS_HOME and stops only what it started.
set -u
cd "$(dirname "$0")"
ROOT=$(pwd -P)
MINMACS_HOME=$(mktemp -d "${TMPDIR:-/tmp}/minmacs-test.XXXXXX")
export MINMACS_HOME
# Agent session logs move into the temp folder, so the agent running the tests never feeds a fixture.
export CLAUDE_CONFIG_DIR="$MINMACS_HOME/claude" CODEX_HOME="$MINMACS_HOME/codex"
export GIT_CONFIG_GLOBAL=/dev/null
APP="$MINMACS_HOME/build/MinMacs.app"
BIN="$APP/Contents/MacOS/MinMacs"
procs=""                      # pids a section started; cleanup stops these and nothing else

pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-56s %s\n' "$1" "$3"; else fail=$((fail+1)); printf '  FAIL  %-56s got %s, want %s\n' "$1" "$3" "$2"; fi; }
json() { python3 -c "import json,sys; j=json.load(sys.stdin); print($1)"; }
cleanup() { for p in $procs; do kill "$p" 2>/dev/null; done; rm -rf "$MINMACS_HOME"; }
trap cleanup EXIT

# core builds the copy every other section tests, so it always runs first.
sections="test/core.sh"
if [ $# -gt 0 ]; then
  for s in "$@"; do [ "$s" = core ] || sections="$sections test/$s.sh"; done
else
  for f in $(ls test/*.sh | LC_ALL=C sort); do [ "$f" = test/core.sh ] || sections="$sections $f"; done
fi
for f in $sections; do
  [ -f "$f" ] || { echo "no section $f"; fail=$((fail+1)); continue; }
  echo "== $(basename "$f" .sh)"
  . "./$f"
done

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
