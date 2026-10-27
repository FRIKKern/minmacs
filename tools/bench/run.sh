#!/bin/sh
# Runs the bench: idle cost with the old apps over the same window, then menu build times, then the gate.
# Usage: tools/bench/run.sh [seconds] [warmup] [iterations] [out]
#   seconds     the idle window, default 600, the ten minutes of PLAN.md phase 1
#   warmup      seconds after MMCoreStart before the window opens, default 30
#   iterations  menu builds per expert, default 200
#   out         where idle.json, menus.json and gate.txt go, default build/bench/<date>
#   BUILD_DIR   where the bench binary is built, default build. Give each parallel run its own.
#   BENCH_BIN   a bench binary built already, to skip the build
#   MM_BENCH_STRICT=1   the gate fails on the phase 6 budgets themselves, not only on today's ceilings
# Every support file lands in a fresh MINMACS_HOME under TMPDIR, removed at the end. Every mode is Idle there.
# The model, cmux and tmux CLIs are /usr/bin/false, and Claude Code's and Codex's folders point into that home,
# so the bench reads the real process table and power facts, and nothing else of the person's.
# The old apps are read with proc_pid_rusage and ps only. Nothing is signaled.
set -eu
cd "$(dirname "$0")/../.."
SECS=${1:-600}
WARM=${2:-30}
ITER=${3:-200}
OUT=${4:-build/bench/$(date -u +%Y%m%dT%H%M%SZ)}
BIN=${BENCH_BIN:-$(tools/bench/build.sh)}
mkdir -p "$OUT"
HOME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/minmacs-bench.XXXXXX")
trap 'rm -rf "$HOME_DIR"' EXIT
run() {
  env MINMACS_HOME="$HOME_DIR" CLAUDE_CONFIG_DIR="$HOME_DIR/claude" CODEX_HOME="$HOME_DIR/codex" GIT_CONFIG_GLOBAL=/dev/null \
    MINMACS_CLAUDE=/usr/bin/false MINMACS_CODEX=/usr/bin/false MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false \
    "$BIN" "$@"
}
{ date -u +%Y-%m-%dT%H:%M:%SZ; sw_vers -productVersion; sysctl -n hw.model hw.ncpu; uptime; } >"$OUT/host.txt"
run idle --seconds "$SECS" --warmup "$WARM" >"$OUT/idle.json"
uptime >>"$OUT/host.txt"
run menus --iterations "$ITER" >"$OUT/menus.json"
strict=""
[ "${MM_BENCH_STRICT:-}" = 1 ] && strict=--strict
python3 tools/bench/gate.py $strict tools/bench/budgets.json "$OUT/idle.json" "$OUT/menus.json" >"$OUT/gate.txt" && r=0 || r=$?
python3 tools/bench/report.py "$OUT/idle.json" "$OUT/menus.json" "$OUT/host.txt" >"$OUT/report.md"
cat "$OUT/report.md" "$OUT/gate.txt"
echo "results in $OUT"
exit "$r"
