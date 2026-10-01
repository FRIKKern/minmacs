#!/bin/sh
# End-to-end checks against the installed CLI, using fixtures only:
#   TextEdit (graceful quit + restore) and build/Stubborn.app, a test app that refuses to quit.
# Nothing else on the machine is touched. `./test.sh --browser` adds a live Chrome tab test
# that opens its own two tabs and closes only the one on vimeo.com.
set -u
cd "$(dirname "$0")"
BIN="$HOME/.local/bin/minmacs"; R="$HOME/Library/Application Support/MinMacs/rules.json"
STUB=no.guerrilla.minmacs.stubborn
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-46s %s\n' "$1" "$3"; else fail=$((fail+1)); printf '  FAIL  %-46s got %s, want %s\n' "$1" "$3" "$2"; fi; }
running() { pgrep -x "$1" >/dev/null && echo yes || echo no; }
rule() { python3 - "$R" "$@" <<'PY'
import json,sys
p,op,key,val=sys.argv[1:5]; j=json.load(open(p)); l=j[key]
if op=='add' and val not in l: l.append(val)
if op=='del' and val in l: l.remove(val)
json.dump(j,open(p,'w'),indent=2)
PY
}
[ -x "$BIN" ] || { echo "minmacs CLI not installed; run ./build.sh"; exit 1; }
"$BIN" plan >/dev/null; [ -f "$R" ] || { echo "no rules file"; exit 1; }

# fixture: the app that will not quit
mkdir -p build/Stubborn.app/Contents/MacOS
clang -fobjc-arc -framework Cocoa tools/stubborn.m -o build/Stubborn.app/Contents/MacOS/Stubborn || exit 1
cat > build/Stubborn.app/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleName</key><string>Stubborn</string><key>CFBundleIdentifier</key><string>$STUB</string>
<key>CFBundleExecutable</key><string>Stubborn</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PL
codesign --force --sign - build/Stubborn.app >/dev/null 2>&1

cp "$R" "$R.bak"
cleanup() { pkill -9 -x Stubborn 2>/dev/null; pkill -x fakeagent 2>/dev/null; pkill -x fakehost 2>/dev/null; osascript -e 'tell application "TextEdit" to quit' >/dev/null 2>&1; mv "$R.bak" "$R"
            defaults delete no.guerrilla.minmacs minmacs.closedBundleIDs >/dev/null 2>&1; defaults delete no.guerrilla.minmacs minmacs.closedTabs >/dev/null 2>&1
            defaults delete no.guerrilla.minmacs minmacs.debug.cmuxDir >/dev/null 2>&1; defaults delete no.guerrilla.minmacs minmacs.readCmux >/dev/null 2>&1; rm -rf "${CMUX:-/nonexistent-dir}"; }
trap cleanup EXIT
rule add close com.apple.TextEdit; rule add close $STUB

echo "== graceful quit and restore (TextEdit)"
open -g -a TextEdit; sleep 2;                                   check "TextEdit launched" yes "$(running TextEdit)"
"$BIN" plan | grep -q "com.apple.TextEdit";                     check "plan lists it under Will quit" 0 "$?"
r=$("$BIN" plan --json | python3 -c "import json,sys; j=json.load(sys.stdin); print('yes' if any(a['bundleID']=='com.apple.TextEdit' for a in j['close']) else 'no')")
                                                                 check "json plan lists it" yes "$r"
"$BIN" run --yes --only com.apple.TextEdit >/dev/null; sleep 1; check "run --only quits it" no "$(running TextEdit)"
"$BIN" restore >/dev/null; sleep 2;                             check "restore relaunches it" yes "$(running TextEdit)"
"$BIN" run --yes --only no.such.app | grep -q "nothing to close"; check "run with no targets is a no-op" 0 "$?"

echo "== force quit (an app that refuses to quit)"
open -g -n build/Stubborn.app; sleep 2;                         check "Stubborn launched" yes "$(running Stubborn)"
"$BIN" run --yes --only $STUB >/dev/null; rc=$?;                check "normal run leaves it running" yes "$(running Stubborn)"
                                                                 check "and reports it with exit 3" 3 "$rc"
"$BIN" run --yes --force --only $STUB >/dev/null; rc=$?; sleep 1; check "run --force kills it" no "$(running Stubborn)"
                                                                 check "and exits 0" 0 "$rc"

echo "== serving detection (loopback listener)"
open -g -n build/Stubborn.app --args --listen 47999; sleep 2
"$BIN" plan | grep -q "Spared Stubborn: serving on 127.0.0.1:47999"; check "plan spares it and names the port" 0 "$?"
"$BIN" run --yes --force --only $STUB >/dev/null;               check "run --force does not touch a spared app" yes "$(running Stubborn)"
rule add ignoreServing $STUB
"$BIN" plan | sed -n "/^Will quit/,/^[A-Z][a-z]* /p" | grep -q Stubborn;          check "ignoreServing puts it back on the quit list" 0 "$?"
"$BIN" run --yes --force --only $STUB >/dev/null; sleep 1;      check "then --force kills it" no "$(running Stubborn)"

echo "== tab classification"
check "youtube.com is noise"            noise "$("$BIN" classify https://www.youtube.com/watch?v=x)"
check "subdomain of a noise host"       noise "$("$BIN" classify music.youtube.com)"
check "github.com is work"              work  "$("$BIN" classify https://github.com/FRIKKern/minmacs)"
check "localhost with a port is work"   work  "$("$BIN" classify http://localhost:4000/studio)"
check "unknown host is left alone"      other "$("$BIN" classify https://example.org/)"
check "work wins when both could match" work  "$("$BIN" classify https://aws.amazon.com/console)"

echo "== agent detection (fixture: tools/fakeagent.c)"
clang -O1 tools/fakeagent.c -o build/fakeagent || exit 1
state() { "$BIN" agents --json --rows tools/fixtures | python3 -c "import json,sys; a=json.load(sys.stdin)['agents']; print(a[0]['state'] if a else 'absent')"; }
ref()   { python3 tools/agents_probe.py --json --row tools/fixtures/fake-agent.json | python3 -c "import json,sys; a=json.load(sys.stdin)['agents']; print(a[0]['state'] if a else 'absent')"; }
check "no fixture running, none found"    absent  "$(state)"
build/fakeagent --work 8 & FA=$!; sleep 2
check "fixture mid-turn is working"       working "$(state)"
check "reference probe agrees"            working "$(ref)"
sleep 8
check "fixture after the turn is idle"    idle    "$(state)"
check "reference probe agrees"            idle    "$(ref)"
kill $FA 2>/dev/null; wait $FA 2>/dev/null
check "fixture gone, none found"          absent  "$(state)"
echo "== agent detection: presence, unknown, hosts, caffeinate -w (fixture rows in tools/fixtures/*/)"
clang -O1 tools/fakehost.c -o build/fakehost || exit 1
python3 tools/validate_row.py tools/fixtures/*/*.json >/dev/null;  check "fixture rows pass the validator" 0 "$?"
# "id:state ... wN iN uN" for a rows directory, from the CLI and from the reference probe
SUMMARY='import json,sys; j=json.load(sys.stdin); print(" ".join("%s:%s" % (a["id"], a["state"]) for a in j["agents"]) or "none", "w%d i%d u%d" % (j["working"], j["idle"], j["unknown"]))'
clirows() { "$BIN" agents --json --rows "tools/fixtures/$1" | python3 -c "$SUMMARY"; }
refrows() { python3 tools/agents_probe.py --json --rows "tools/fixtures/$1" | python3 -c "$SUMMARY"; }
both() { check "$1" "$2" "$(clirows "$3")"; check "  reference agrees" "$2" "$(refrows "$3")"; }

build/fakeagent & FA=$!; sleep 2
both "presence: a missing path keeps a bare-name match out"   "none w0 i0 u0"                 presence-missing
both "presence: an existing path lets it through"             "fake-guarded:idle w0 i1 u0"    presence-here
both "no_outside_signal: no signal reads unknown"             "fake-blind:unknown w0 i0 u1"   unknown
"$BIN" agents --rows tools/fixtures/unknown | grep -q "◌ unknown";               check "table shows the hollow marker" 0 "$?"
"$BIN" agents --rows tools/fixtures/unknown | grep -q "0 working, 0 idle, 1 unknown"; check "totals line counts unknown on its own" 0 "$?"
kill $FA 2>/dev/null; wait $FA 2>/dev/null
build/fakeagent --work 8 & FA=$!; sleep 2
both "no_outside_signal: a fired signal still reads working"  "fake-blind:working w1 i0 u0"   unknown
kill $FA 2>/dev/null; wait $FA 2>/dev/null

build/fakeagent --work 8 --w self & FA=$!; sleep 2
both "caffeinate -w <own pid> counts"                         "fake-watch:working w1 i0 u0"   watch
kill $FA 2>/dev/null; wait $FA 2>/dev/null
build/fakeagent --work 8 --w other & FA=$!; sleep 2
both "caffeinate -w <another pid> does not"                   "fake-watch:idle w0 i1 u0"      watch
kill $FA 2>/dev/null; wait $FA 2>/dev/null
build/fakeagent --work 8 & FA=$!; sleep 2
both "caffeinate without -w does not"                         "fake-watch:idle w0 i1 u0"      watch
kill $FA 2>/dev/null; wait $FA 2>/dev/null

build/fakeagent & FA=$!; sleep 2
both "host rows, agent on its own: reported as itself"        "fake-agent:idle w0 i1 u0"      host
kill $FA 2>/dev/null; wait $FA 2>/dev/null
build/fakehost build/fakeagent --work 8 & FH=$!; sleep 2
both "agent under a host: reported once, as the host"         "fake-host:working w1 i0 u0"    host
"$BIN" agents --json --rows tools/fixtures/host | python3 -c "import json,sys; h=json.load(sys.stdin)['agents'][0].get('hosted',[]); print(','.join('%s:%s' % (x['id'], x['state']) for x in h))" | grep -q "^fake-agent:working$"
                                                                 check "the host lists what it hosts" 0 "$?"
sleep 8
both "host after the hosted turn ended"                       "fake-host:idle w0 i1 u0"       host
kill $FH 2>/dev/null; wait $FH 2>/dev/null
pkill -x fakeagent 2>/dev/null

# Real sessions: wherever the precise signal decides, both implementations must agree.
python3 - "$BIN" <<'PYEOF'
import json, subprocess, sys
a = {x["pid"]: x for x in json.loads(subprocess.run([sys.argv[1], "agents", "--json"], capture_output=True, text=True).stdout)["agents"]}
b = {x["pid"]: x for x in json.loads(subprocess.run(["python3", "tools/agents_probe.py", "--json"], capture_output=True, text=True).stdout)["agents"]}
both = sorted(set(a) & set(b))
precise = [p for p in both if "child" in a[p]["why"] or "child" in b[p]["why"] or (a[p]["state"] == b[p]["state"] == "idle")]
bad = [p for p in precise if a[p]["state"] != b[p]["state"]]
cpu_only = [p for p in both if p not in precise and a[p]["state"] != b[p]["state"]]
print(f"  {'ok  ' if not bad else 'FAIL'}  real sessions: {len(both)} seen by both, {len(precise)} decided precisely, {len(bad)} disagree" + (f"; {len(cpu_only)} differ on CPU alone, which the two sample differently" if cpu_only else ""))
sys.exit(1 if bad else 0)
PYEOF
[ $? = 0 ] && pass=$((pass+1)) || fail=$((fail+1))

echo "== cmux reader (fixture directory; the real ~/.cmuxterm is never read)"
CMUX=$(mktemp -d); defaults write no.guerrilla.minmacs minmacs.debug.cmuxDir "$CMUX"
build/fakeagent & FA=$!; sleep 1
ts() { date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ; }
ev() { printf '{"kind":"%s","createdAt":"%s","workstreamId":"claude-sess-1","payload":{"text":"SECRETPAYLOAD }{ \\" ]"},"cwd":"/x","title":"SECRETTITLE"}\n' "$1" "$(ts "$2")" >> "$CMUX/workstream.jsonl"; }
cat > "$CMUX/claude-hook-sessions.json" <<EOF
{"version":1,"sessions":{"u1":{"pid":$FA,"sessionId":"sess-1","surfaceId":"s1","workspaceId":"w1","updatedAt":1790848276.5,
 "lastBody":"SECRETBODY","launchCommand":{"argv":["}","]"]},"cwd":"/x"}}}
EOF
cmuxstate() { "$BIN" agents --json --rows tools/fixtures "$@" | python3 -c "import json,sys; a=json.load(sys.stdin)['agents']; print(a[0]['state'] if a else 'absent')"; }
: > "$CMUX/workstream.jsonl"; ev userPrompt 5; ev toolUse 4; ev permissionRequest 2
check "permission request reads blocked"       blocked "$(cmuxstate --cmux)"
"$BIN" agents --json --rows tools/fixtures --cmux | grep -q '"why" : "waiting for permission (cmux)"'; check "reason names the permission wait" 0 "$?"
"$BIN" agents --rows tools/fixtures --cmux | grep -q "blocked on you";                                  check "CLI summary counts it" 0 "$?"
check "setting off falls back to idle"         idle "$(cmuxstate)"
defaults write no.guerrilla.minmacs minmacs.readCmux -bool true
check "setting on (minmacs.readCmux) reads it" blocked "$(cmuxstate)"
defaults write no.guerrilla.minmacs minmacs.readCmux -bool false
check "setting back off falls back"            idle "$(cmuxstate)"
ev toolUse 1
check "then a tool event reads working"        working "$(cmuxstate --cmux)"
check "same log, setting off: idle" idle "$(cmuxstate)"
: > "$CMUX/workstream.jsonl"; ev toolUse 120
check "events from before the process started are ignored" idle "$(cmuxstate --cmux)"
: > "$CMUX/workstream.jsonl"; ev permissionRequest 300
check "a blocked event from a reused pid is ignored" idle "$(cmuxstate --cmux)"
: > "$CMUX/workstream.jsonl"; ev toolUse 30; ev stop 20; ev toolResult 10
check "idle notification after a stop is not blocked" idle "$(cmuxstate --cmux)"
: > "$CMUX/workstream.jsonl"; ev userPrompt 30; ev toolUse 20; ev toolResult 10
check "notification in mid-turn is blocked"    blocked "$(cmuxstate --cmux)"
ev toolUse 1
check "next tool event clears it to working"   working "$(cmuxstate --cmux)"
# the log is tens of MB: only the last 2 MB may be read, so a block older than that is never seen
: > "$CMUX/workstream.jsonl"; ev permissionRequest 100
python3 -c "
import sys
l='{\"kind\":\"toolUse\",\"createdAt\":\"2026-01-01T00:00:00Z\",\"workstreamId\":\"claude-other\",\"payload\":{\"t\":\"'+'x'*900+'\"}}\n'
sys.stdout.write(l*3500)" >> "$CMUX/workstream.jsonl"
check "log is over 3 MB" yes "$([ "$(stat -f %z "$CMUX/workstream.jsonl")" -gt 3000000 ] && echo yes || echo no)"
check "a block outside the last 2 MB is not read" idle "$(cmuxstate --cmux)"
check "no payload, title or body text in any output" 0 "$( { "$BIN" agents --json --rows tools/fixtures --cmux; "$BIN" agents --rows tools/fixtures --cmux; } 2>&1 | grep -c SECRET)"
kill $FA 2>/dev/null; wait $FA 2>/dev/null
defaults delete no.guerrilla.minmacs minmacs.debug.cmuxDir >/dev/null 2>&1; defaults delete no.guerrilla.minmacs minmacs.readCmux >/dev/null 2>&1

if [ "${1:-}" = "--browser" ]; then
  echo "== live browser trim (opens two tabs of its own in Chrome)"
  was=$(pgrep -f "Google Chrome.app/Contents/MacOS/Google Chrome$" >/dev/null && echo yes || echo no)
  open -g -a "Google Chrome" "https://vimeo.com/" "https://github.com/FRIKKern/minmacs"; sleep 6
  "$BIN" plan | grep -q "vimeo.com";                            check "plan lists the vimeo tab as noise" 0 "$?"
  "$BIN" plan | grep "Will trim" | grep -q "Google Chrome";     check "Chrome is trimmed, not quit" 0 "$?"
  "$BIN" trim --yes --only-host vimeo.com >/dev/null; sleep 2
  "$BIN" plan | grep -q "vimeo.com";                            check "vimeo tab is gone" 1 "$?"
  check "Chrome is still running" yes "$(pgrep -f 'Google Chrome.app/Contents/MacOS/Google Chrome$' >/dev/null && echo yes || echo no)"
  "$BIN" restore >/dev/null; sleep 4
  "$BIN" plan | grep -q "vimeo.com";                            check "restore reopens the closed tab" 0 "$?"
  "$BIN" trim --yes --only-host vimeo.com >/dev/null
  defaults delete no.guerrilla.minmacs minmacs.closedTabs >/dev/null 2>&1
  [ "$was" = "no" ] && echo "  (Chrome was not running before the test; it is left open with the GitHub tab)"
fi

echo; echo "passed $pass, failed $fail"; [ $fail = 0 ]
