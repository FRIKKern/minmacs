#!/bin/sh
# Does `cmux events` need a password outside a cmux terminal? Read-only.
# It reads one replayed event of any category four ways and prints what each got:
#   inside     this shell, with every CMUX_* variable that cmux set
#   bare-env   no CMUX_* variable and no saved capability token, still a child of this shell
#   bare-env-default-path   the same without CMUX_SOCKET_PATH, so the CLI finds the socket itself
#   orphan     no CMUX_* variable, and the parent exits first, so launchd adopts the reader
#              and no cmux process is among its ancestors. This is how a login-item app runs.
# It never passes a password. Usage: run.sh [outdir]
set -u
OUT=${1:-${TMPDIR:-/tmp}/minmacs-settling/cmux-events}
mkdir -p "$OUT"
CMUX=${CMUX_BUNDLED_CLI_PATH:-/Applications/cmux.app/Contents/Resources/bin/cmux}
SOCK="$HOME/.local/state/cmux/cmux-501.sock"
# Start a few events back, so a replay answers at once even when no agent talks.
last=$(tail -c 4096 "$HOME/.cmuxterm/events.jsonl" 2>/dev/null | tail -1 | sed -n 's/.*"seq":\([0-9]*\).*/\1/p')
after=$(( ${last:-10} - 5 ))
cmd="$CMUX events --after $after --limit 1 --no-heartbeat"

# A reader that hangs is stopped by its own watchdog. It only signals the pid it started.
read1() { # name, then the env command prefix
  name=$1; shift
  ( "$@" sh -c "$cmd" >"$OUT/$name.out" 2>"$OUT/$name.err" & p=$!; ( sleep 8; kill $p 2>/dev/null ) & wait $p; echo "exit $?" >"$OUT/$name.exit" )
}
strip="env -u CMUX_SOCKET_CAPABILITY -u CMUX_SOCKET_PATH -u CMUX_SOCKET -u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_PANEL_ID -u CMUX_TAB_ID -u CMUX_CLAUDE_PID -u CMUX_BUNDLE_ID -u __CFBundleIdentifier -u CMUX_SOCKET_PASSWORD"

read1 inside env
# shellcheck disable=SC2086
read1 bare-env $strip CMUX_SOCKET_PATH="$SOCK"
# shellcheck disable=SC2086
read1 bare-env-default-path $strip

# The orphan: a subshell starts the reader in the background and exits at once.
# The reader waits a second, so it connects after launchd has adopted it, then logs its own ppid.
rm -f "$OUT/orphan.exit"
# shellcheck disable=SC2086
( $strip CMUX_SOCKET_PATH="$SOCK" sh -c "sleep 1; echo ppid \$PPID >\"$OUT/orphan.ppid\"; ps -o pid=,ppid=,comm= -p \$\$ >>\"$OUT/orphan.ppid\"; $cmd >\"$OUT/orphan.out\" 2>\"$OUT/orphan.err\"; echo exit \$? >\"$OUT/orphan.exit\"" </dev/null >/dev/null 2>&1 & )
i=0; while [ ! -f "$OUT/orphan.exit" ] && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done

"$CMUX" capabilities 2>&1 | grep access_mode >"$OUT/access_mode.txt"
for n in inside bare-env bare-env-default-path orphan; do
  printf '%-22s %s  first bytes: %s  err: %s\n' "$n" "$(cat "$OUT/$n.exit" 2>/dev/null || echo 'no exit, still running?')" \
    "$(head -c 120 "$OUT/$n.out" 2>/dev/null | tr '\n' ' ')" "$(head -c 160 "$OUT/$n.err" 2>/dev/null | tr '\n' ' ')"
done
echo "orphan parent: $(head -1 "$OUT/orphan.ppid" 2>/dev/null)"
echo "$(cat "$OUT/access_mode.txt")"
