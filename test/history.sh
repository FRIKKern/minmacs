# ===== The last hour in memory, Graph/MMHistory.h =====
# Sourced by test.sh after core. test/history/history.m links all of Sources but main.m and checks the rings with
# fixture values and times: a reused pid, a gone process, the caps and a minute with no pass. Then the graph fills
# them from fake agents and a fake LocoHost expert, and a fake cmux hands over a SubagentStart event.
# The only process it starts is the fake cmux, which runs a sleeper built from test/insomnia/sleeper.c under a name
# of this run. MinMacs stops it when the events reader stops.

hs=$(cd "$MINMACS_HOME" && mkdir -p history && cd history && pwd -P)
mkdir -p "$hs/bin" "$hs/home" "$hs/cmux"
hs_tool="$hs/bin/history-$$"
hs_src=$(find Sources -name '*.m' ! -path 'Sources/main.m' | LC_ALL=C sort)
# shellcheck disable=SC2086
clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -ISources -DMM_TESTS -DMM_VERSION='"2.0.0"' \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  $hs_src test/history/history.m -o "$hs_tool" >"$hs/clang.log" 2>&1
hs_r=$?
check "history: the tool builds" 0 "$hs_r"
check "history: no warnings under -Wextra" 0 "$(grep -c 'warning:' "$hs/clang.log")"
[ "$hs_r" = 0 ] || tail -20 "$hs/clang.log"
hs_tab=$(printf '\t')
hs_run() { # mode, then env
  hs_mode=$1; shift
  env MINMACS_HOME="$hs/home" "$@" "$hs_tool" "$hs_mode" >"$hs/$hs_mode.out" 2>"$hs/$hs_mode.err"
  check "history: $hs_mode runs" 0 "$?"
  while IFS="$hs_tab" read -r hs_n hs_w hs_g; do
    if [ "$hs_n" = info ]; then echo "  info  $hs_w"; else check "$hs_n" "$hs_w" "$hs_g"; fi
  done <"$hs/$hs_mode.out"
}

echo "-- the rings, with fixture values and times"
hs_run rings

echo "-- each graph build fills them, and the snapshot carries a copy"
hs_run graph MINMACS_CMUX=/usr/bin/false

echo "-- subagent starts from the events reader"
hs_sleeper="mmhs-sleeper-$$"
clang -O1 test/insomnia/sleeper.c -o "$hs/cmux/$hs_sleeper" 2>>"$hs/clang.log"
printf '%s\n' "$hs_sleeper" >"$hs/cmux/sleeper.name"
cp test/history/fake-cmux.sh "$hs/cmux/cmux"; chmod +x "$hs/cmux/cmux"
hs_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"seq":1,"name":"agent.hook.SubagentStart","category":"agent","source":"claude","occurred_at":"%s","payload":{"session_id":"sub-sess","cwd":"%s","_ppid":1}}\n{"seq":2,"name":"agent.hook.PreToolUse","category":"agent","source":"claude","occurred_at":"%s","payload":{"session_id":"sub-sess","cwd":"%s","_ppid":1}}\n' \
  "$hs_now" "$hs" "$hs_now" "$hs" >"$hs/cmux/cmux.frames"
hs_run events MINMACS_CMUX="$hs/cmux/cmux" MINMACS_CMUX_EVENTS=1
hs_left=$(pgrep -x "$hs_sleeper" | tr '\n' ' ')
check "history: the fake cmux's sleeper stopped with the reader" "" "$hs_left"
for p in $hs_left; do kill "$p" 2>/dev/null; done   # pgrep matched the name this run gave it, nothing else

echo "-- in memory only, and no timer of its own"
check "history: MMHistory.m writes no file and opens no log" 0 \
  "$(grep -cE 'writeToFile|writeToURL|MMStateFile|MMLog|fopen|open\(|NSFileManager|MMSupportDir|NSUserDefaults|MMSetPref' Sources/Core/Graph/MMHistory.m)"
check "history: MMHistory.m makes no timer and no queue" 0 "$(grep -cE 'MMTimer|dispatch_source|NSTimer|dispatch_after|MMQueue' Sources/Core/Graph/MMHistory.m)"
check "history: the graph build fills it, once per build" 1 "$(grep -c 'MMHistory.shared fillFrom:snap' Sources/Core/Graph/MMGraph.m)"
check "history: the header says which pass fills each ring" 5 \
  "$(grep -cE '^// - (The Mac ring|The disk ring|One ring per live agent tree|One ring per server tree|Subagent starts)[,:]' Sources/Core/Graph/MMHistory.h)"

echo "-- minmacs history"
hs_out=$(env MINMACS_HOME="$hs/home" "$BIN" history --json 2>/dev/null)
check "history: cold, minmacs history --json says no app and holds no ring" "False 0 200 60" \
  "$(printf '%s' "$hs_out" | json '"%s %d %d %d" % (j["app"], j["rings"], j["maxRings"], j["minutes"])')"
check "history: cold, the plain form says why there is none" yes \
  "$(env MINMACS_HOME="$hs/home" "$BIN" history 2>/dev/null | grep -q 'memory only' && echo yes || echo no)"
check "history: help --json lists it as a verb that reads only" "False" \
  "$(env MINMACS_HOME="$hs/home" "$BIN" help --json | json '[v["mutates"] for v in j["verbs"] if v["verb"] == "history"][0]')"

# ===== end of history =====
