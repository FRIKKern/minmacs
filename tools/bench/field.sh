#!/bin/bash
# The field's idle in a fixture home, issue #52: `bench idle` while fieldfix.py plays agents at work.
#
#   tools/bench/field.sh <bench> <template> <out.json> [seconds] [warmup]
#
# <template> is a home `fieldfix.py make` wrote. Each run takes a fresh APFS clone of it, so runs of a base and a
# change start from the same files, writes the undo log with `bench seed`, starts `fieldfix.py run`, and runs
# `bench idle` with every CLI a fake. It stops only the player it started, which stops only its own sleepers.
# MM_FIELD_LOOKING=1 runs `bench idle --looking`, as while the menu window is open, D11.
set -u
bench=$1 template=$2 out=$3 seconds=${4:-240} warmup=${5:-30}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
base=${MM_FIELD_DIR:-${TMPDIR:-/tmp}}
home=$(mktemp -d "${base%/}/mm-field.$$.XXXX")
cp -cR "$template/." "$home/"
# fieldfix.json names the template's paths; the clone's are the same under its own folder.
python3 -I - "$home" "$template" <<'PY'
import json, sys
home, tpl = sys.argv[1:3]
p = home + "/fieldfix.json"
j = json.load(open(p))
fix = lambda s: home + s[len(tpl):] if s.startswith(tpl) else s
j["roots"], j["claude"] = fix(j["roots"]), fix(j["claude"])
j["trees"] = [fix(t) for t in j["trees"]]
for s in j["sessions"]: s["cwd"], s["transcript"] = fix(s["cwd"]), fix(s["transcript"])
json.dump(j, open(p, "w"), indent=1)
PY
# A linked worktree's .git file and the main repo's worktree list name the template's paths: repair them for the clone.
for g in "$home"/roots/repo*-wt/*/.git; do sed -i '' "s#$template#$home#g" "$g"; done
for g in "$home"/roots/repo*/.git/worktrees/*/gitdir; do sed -i '' "s#$template#$home#g" "$g"; done
run() {
  env MINMACS_HOME="$home" CLAUDE_CONFIG_DIR="$home/claude" CODEX_HOME="$home/codex" PI_CODING_AGENT_SESSION_DIR="$home/pi" \
    GIT_CONFIG_GLOBAL="$home/gitconfig" GIT_CONFIG_NOSYSTEM=1 MINMACS_ROOTS="$home/roots" \
    MINMACS_CLUTTER_ROOT="$home/clutter" MINMACS_CLUTTER_ROWS="$repo/registry/clutter" MINMACS_NO_BACKOFF=1 \
    MINMACS_CLAUDE=/usr/bin/false MINMACS_CODEX=/usr/bin/false MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false "$@"
}
run "$bench" seed --undo "${MM_FIELD_UNDO:-400}" --scan >"$out.seed" || exit 1
python3 -I "$here/fieldfix.py" run "$home" --seconds $((seconds + warmup + 30)) --agents "${MM_FIELD_AGENTS:-8}" &
player=$!
run "$bench" idle --seconds "$seconds" --warmup "$warmup" --tick-runs 0 ${MM_FIELD_LOOKING:+--looking} >"$out"
status=$?
kill -TERM "$player" 2>/dev/null
wait "$player" 2>/dev/null
rm -rf "$home"
exit $status
