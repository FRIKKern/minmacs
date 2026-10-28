#!/bin/sh
# Issue #54: scans and review at scale. Makes 300 fixture checkouts with test/git/benchfix.py and a 20 GB clutter tree
# of APFS clones and sparse files with tools/bench/clutterfix.py, all in a fresh MINMACS_HOME under TMPDIR.
# Then two launches of `bench scale` in that home: the first with no caches, the second with the caches the first saved.
# The first also scans the clutter tree and reviews 100 worktrees through test/review/fakeclaude.py.
# Usage: tools/bench/scale.sh [out]     out defaults to build/bench/scale-<date>
#   BUILD_DIR, BENCH_BIN   as in run.sh
#   MM_SCALE_NO_CLUTTER=1  leaves the clutter tree out
# The clutter tree is left out, with a line that says so, when the volume has under 50 GB free.
set -eu
cd "$(dirname "$0")/../.."
OUT=${1:-build/bench/scale-$(date -u +%Y%m%dT%H%M%SZ)}
BIN=${BENCH_BIN:-$(tools/bench/build.sh)}
mkdir -p "$OUT"
H=$(mktemp -d "${TMPDIR:-/tmp}/minmacs-scale.XXXXXX")
H=$(cd "$H" && pwd -P)
trap 'rm -rf "$H"' EXIT
mkdir -p "$H/roots" "$H/fake" "$H/claude" "$H/codex"
cp test/review/fakeclaude.py test/review/fakeanswer.py test/review/fakecount.py "$H/fake/"
t0=$(date +%s)
env GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
  GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
  python3 test/git/benchfix.py "$H/roots" 30 300 8 >"$OUT/fixture.json"
echo "fixture: 300 checkouts in $(( $(date +%s) - t0 )) s"
CL=""
if [ "${MM_SCALE_NO_CLUTTER:-}" != 1 ]; then
  if MINMACS_HOME="$H" python3 tools/bench/clutterfix.py "$H/clutter" "$H/roots" 20 >"$OUT/clutterfix.json" 2>"$OUT/clutterfix.err"; then
    CL=--clutter; cat "$OUT/clutterfix.json"
  else
    echo "clutter: left out, $(cat "$OUT/clutterfix.err")"
  fi
fi
run() {
  env MINMACS_HOME="$H" MINMACS_ROOTS="$H/roots" MINMACS_CLUTTER_ROOT="$H/clutter" MINMACS_CLUTTER_ROWS="$PWD/registry/clutter" \
    CLAUDE_CONFIG_DIR="$H/claude" CODEX_HOME="$H/codex" PI_CODING_AGENT_SESSION_DIR="$H/pi" GIT_CONFIG_GLOBAL=/dev/null \
    MINMACS_CLAUDE="$H/fake/fakeclaude.py" MINMACS_CODEX=/usr/bin/false MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false \
    RV_TEST_SENT="$H/sent.json" RV_TEST_COUNT="$H/count.json" "$BIN" scale "$@"
}
{ date -u +%Y-%m-%dT%H:%M:%SZ; sw_vers -productVersion; sysctl -n hw.model hw.ncpu; uptime; } >"$OUT/host.txt"
run --expect 300 $CL --review 100 --warm 10 --idle 10 >"$OUT/scale-first.json"
run --expect 300 --warm 10 --idle 10 >"$OUT/scale-later.json"
uptime >>"$OUT/host.txt"
python3 tools/bench/gate.py tools/bench/budgets.json "$OUT/scale-first.json" "$OUT/scale-later.json" >"$OUT/gate.txt" && r=0 || r=$?
python3 tools/bench/report.py --scale "$OUT/scale-first.json" "$OUT/scale-later.json" >"$OUT/report.md"
cat "$OUT/host.txt" "$OUT/report.md" "$OUT/gate.txt"
echo "results in $OUT"
exit "$r"
