#!/bin/sh
# End-to-end checks of the CLI that ./build.sh --no-install builds, using fixtures only.
#   build/Polite.app quits when asked. build/Stubborn.app refuses. Both come from tools/stubborn.m.
#   tools/fakeagent.c and tools/fakehost.c stand in for agents. A temporary directory holds
#   the rules file and the cmux files.
# Your rules file and your MinMacs settings are never read or written. The CLI runs with
# MINMACS_RULES_FILE and MINMACS_DEFAULTS_DOMAIN set to test copies, which are deleted at the end.
# A check that needs something this machine lacks is skipped, and the reason is printed.
#   ./test.sh --live      also compares real agent sessions between the CLI and the reference probe. Read only.
#   ./test.sh --browser   adds a live Chrome test that opens its own two tabs and closes the one on vimeo.com.
set -u
cd "$(dirname "$0")"
BIN="${MINMACS_BIN:-build/MinMacs.app/Contents/MacOS/MinMacs}"
# Bundle ids unique to this run, so a run never quits a fixture that another checkout's test started.
POLITE=no.guerrilla.minmacs.test$$.polite; STUB=no.guerrilla.minmacs.test$$.stubborn
pass=0; fail=0; skipped=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-46s %s\n' "$1" "$3"; else fail=$((fail+1)); printf '  FAIL  %-46s got %s, want %s\n' "$1" "$3" "$2"; fi; }
skip()  { skipped=$((skipped+1)); printf '  skip  %-46s %s\n' "$1" "$2"; }
# Fixture apps are found by the full path of this checkout's copy, never by name alone.
running() { pgrep -f "$PWD/build/$1.app/Contents/MacOS/$1" >/dev/null && echo yes || echo no; }
[ -x "$BIN" ] || { echo "minmacs CLI not built; run ./build.sh --no-install"; exit 1; }

TMP=$(mktemp -d)
export MINMACS_RULES_FILE="$TMP/rules.json" MINMACS_DEFAULTS_DOMAIN="no.guerrilla.minmacs.test.$$"
R="$MINMACS_RULES_FILE"; DOM="$MINMACS_DEFAULTS_DOMAIN"
rule() { python3 - "$R" "$@" <<'PY'
import json,sys
p,op,key,val=sys.argv[1:5]; j=json.load(open(p)); l=j[key]
if op=='add' and val not in l: l.append(val)
if op=='del' and val in l: l.remove(val)
json.dump(j,open(p,'w'),indent=2)
PY
}
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
FA=; FH=
# Stops only what this run started: its own fixture apps by path, its fake agents by pid.
cleanup() { pkill -9 -f "$PWD/build/Stubborn.app/Contents/MacOS/Stubborn" 2>/dev/null; pkill -f "$PWD/build/Polite.app/Contents/MacOS/Polite" 2>/dev/null
            for p in $FA $FH; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
            [ -x "$LSREGISTER" ] && "$LSREGISTER" -u "$PWD/build/Polite.app" "$PWD/build/Stubborn.app" >/dev/null 2>&1
            defaults delete "$DOM" >/dev/null 2>&1; rm -f "$HOME/Library/Preferences/$DOM.plist"; rm -rf "$TMP"; }
trap cleanup EXIT

"$BIN" rules >/dev/null; [ -f "$R" ] || { echo "the CLI wrote no rules file to $R"; exit 1; }
rule add close $POLITE; rule add close $STUB
# Browsers on the close list are quit, not trimmed, so no check ever sends an Apple event to a real browser.
defaults write "$DOM" minmacs.quitBrowsers -bool true

# fixtures: one app that quits when asked, one that will not
mkfixture() {   # name bundle-id
  mkdir -p "build/$1.app/Contents/MacOS"
  clang -fobjc-arc -framework Cocoa tools/stubborn.m -o "build/$1.app/Contents/MacOS/$1" || exit 1
  cat > "build/$1.app/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleName</key><string>$1</string><key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleExecutable</key><string>$1</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PL
  codesign --force --sign - "build/$1.app" >/dev/null 2>&1
}
mkfixture Polite $POLITE; mkfixture Stubborn $STUB
# Waits up to 5 s for a fixture app to show up after open.
launched() { for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(running "$1")" = yes ] && { echo yes; return; }; sleep 0.5; done; echo no; }

open -g -n build/Polite.app 2>/dev/null; GUI=$(launched Polite)
if [ "$GUI" = no ]; then
  echo "== quitting, restoring and serving"
  skip "graceful quit, restore, force quit, serving" "could not launch a fixture app; this machine has no GUI login session"
else
  echo "== graceful quit and restore (build/Polite.app)"
  check "Polite launched" yes "$GUI"
  "$BIN" plan | sed -n "/^Will quit/,/^[A-Z][a-z]* /p" | grep -q "$POLITE"; check "plan lists it under Will quit" 0 "$?"
  r=$("$BIN" plan --json | python3 -c "import json,sys; j=json.load(sys.stdin); print('yes' if any(a['bundleID']=='$POLITE' for a in j['close']) else 'no')")
                                                                   check "json plan lists it" yes "$r"
  "$BIN" run --yes --only $POLITE >/dev/null; sleep 1;            check "run --only quits it" no "$(running Polite)"
  check "the closed list remembers it" "$POLITE" "$(defaults read "$DOM" minmacs.closedBundleIDs 2>/dev/null | tr -d ' (),"\n')"
  "$BIN" restore >/dev/null;                                       check "restore relaunches it" yes "$(launched Polite)"
  "$BIN" run --yes --only no.such.app | grep -q "nothing to close"; check "run with no targets is a no-op" 0 "$?"
  "$BIN" run --yes --only $POLITE >/dev/null

  echo "== force quit (an app that refuses to quit)"
  open -g -n build/Stubborn.app;                                   check "Stubborn launched" yes "$(launched Stubborn)"
  "$BIN" run --yes --only $STUB >/dev/null; rc=$?;                check "normal run leaves it running" yes "$(running Stubborn)"
                                                                   check "and reports it with exit 3" 3 "$rc"
  "$BIN" run --yes --force --only $STUB >/dev/null; rc=$?; sleep 1; check "run --force kills it" no "$(running Stubborn)"
                                                                   check "and exits 0" 0 "$rc"

  echo "== serving detection (loopback listener)"
  open -g -n build/Stubborn.app --args --listen 47999; launched Stubborn >/dev/null; sleep 1
  "$BIN" plan | grep -q "Spared Stubborn: serving on 127.0.0.1:47999"; check "plan spares it and names the port" 0 "$?"
  "$BIN" run --yes --force --only $STUB >/dev/null;               check "run --force does not touch a spared app" yes "$(running Stubborn)"
  rule add ignoreServing $STUB
  "$BIN" plan | sed -n "/^Will quit/,/^[A-Z][a-z]* /p" | grep -q Stubborn;          check "ignoreServing puts it back on the quit list" 0 "$?"
  "$BIN" run --yes --force --only $STUB >/dev/null; sleep 1;      check "then --force kills it" no "$(running Stubborn)"
  rule del ignoreServing $STUB
fi

echo "== tab classification"
check "youtube.com is noise"            noise "$("$BIN" classify https://www.youtube.com/watch?v=x)"
check "subdomain of a noise host"       noise "$("$BIN" classify music.youtube.com)"
check "github.com is work"              work  "$("$BIN" classify https://github.com/FRIKKern/minmacs)"
check "localhost with a port is work"   work  "$("$BIN" classify http://localhost:4000/studio)"
check "unknown host is left alone"      other "$("$BIN" classify https://example.org/)"
check "work wins when both could match" work  "$("$BIN" classify https://aws.amazon.com/console)"

echo "== rules file (tools/rulecheck.m against fixture rules files)"
clang -fobjc-arc -ISources -framework Foundation tools/rulecheck.m Sources/Rules.m -o build/rulecheck || exit 1
RC="$TMP/rules-check.json"
rc() { MINMACS_RULES_FILE="$RC" build/rulecheck "$@"; }
listed() { rc list "$1" | grep -qxF "$2" && echo yes || echo no; }
cat > "$RC" <<'EOF'
{"version":3,"keep":["com.jetbrains.*"],"close":["com.adobe.*"],"unsorted":[],"tabs":{"noise":[],"work":[]},"ignoreServing":[]}
EOF
check "com.adobe.* closes Photoshop"                close "$(rc verdict com.adobe.Photoshop)"
check "com.adobe.* closes Illustrator"              close "$(rc verdict com.adobe.illustrator)"
rc set keep com.adobe.Photoshop
check "Keep on Photoshop keeps it"                  keep  "$(rc verdict com.adobe.Photoshop)"
check "Illustrator still closes"                    close "$(rc verdict com.adobe.illustrator)"
check "com.adobe.* is still in the close list"      yes   "$(listed close 'com.adobe.*')"
rc set unsorted com.adobe.Photoshop
check "Unsorted on Photoshop leaves it alone"       unsorted "$(rc verdict com.adobe.Photoshop)"
check "and is recorded as an exception"             yes   "$(listed unsorted com.adobe.Photoshop)"
check "Illustrator still closes after that"         close "$(rc verdict com.adobe.illustrator)"
rc set close com.adobe.Photoshop
check "Close on Photoshop closes it again"          close "$(rc verdict com.adobe.Photoshop)"
check "and drops the Unsorted exception"            no    "$(listed unsorted com.adobe.Photoshop)"
rc set close com.jetbrains.goland
check "Close on GoLand beats com.jetbrains.* keep"  close "$(rc verdict com.jetbrains.goland)"
check "IntelliJ is still kept"                      keep  "$(rc verdict com.jetbrains.intellij)"
check "com.jetbrains.* is still in the keep list"   yes   "$(listed keep 'com.jetbrains.*')"
rc set unsorted com.example.nothing
check "Unsorted with no pattern adds no entry"      no    "$(listed unsorted com.example.nothing)"
cat > "$RC" <<'EOF'
{"version":3,"keep":[],"close":[],"unsorted":[],"tabs":{"noise":[],"work":[]},"ignoreServing":["com.adobe.*","*zoom*","com.hnc.Discord"]}
EOF
check "ignoreServing: exact id"                     yes "$(rc serving com.hnc.Discord)"
check "ignoreServing: trailing * matches a prefix"  yes "$(rc serving com.adobe.Photoshop)"
check "ignoreServing: *x* matches inside the id"    yes "$(rc serving us.zoom.xos)"
check "ignoreServing: an unlisted app is not"       no  "$(rc serving com.example.app)"
rc set-serving no com.adobe.Photoshop
check "turning it off for Photoshop works"          no  "$(rc serving com.adobe.Photoshop)"
check "Illustrator is still ignored"                yes "$(rc serving com.adobe.illustrator)"
check "com.adobe.* is still listed"                 yes "$(listed ignoreServing 'com.adobe.*')"
rc set-serving yes com.adobe.Photoshop
check "turning it back on works"                    yes "$(rc serving com.adobe.Photoshop)"
check "and drops the exception"                     no  "$(listed ignoreServing '!com.adobe.Photoshop')"
# An old rules file: version 2, as 1.2.0 wrote it, without most of today's defaults.
cat > "$RC" <<'EOF'
{"version":2,"keep":["com.apple.Terminal","com.google.Chrome"],"close":["com.spotify.client","com.example.mine"],
 "unsorted":["com.apple.Music"],"tabs":{"noise":["youtube.com"],"work":["github.com","netflix.com"]},"ignoreServing":["!com.hnc.Discord"]}
EOF
check "old file: a new keep default arrives"        yes "$(listed keep com.microsoft.VSCode)"
check "old file: a new close default arrives"       yes "$(listed close com.apple.Photos)"
check "old file: a new noise host arrives"          yes "$(listed noise reddit.com)"
check "old file: a new ignoreServing default"       yes "$(listed ignoreServing com.spotify.client)"
check "a user entry stays"                          yes "$(listed close com.example.mine)"
check "a default the user moved to keep stays kept" keep "$(rc verdict com.google.Chrome)"
check "and is not added to close"                   no  "$(listed close com.google.Chrome)"
check "a host the user moved to work stays out of noise" no "$(listed noise netflix.com)"
check "a default on the unsorted list stays out"    unsorted "$(rc verdict com.apple.Music)"
check "a default with a ! exception stays out"      no  "$(rc serving com.hnc.Discord)"
check "the file is written as version 3"            3   "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$RC")"
# A current file, version 3, that lacks a default: it still arrives. 1.2.0 merged only below version 2.
python3 - "$RC" <<'PY'
import json,sys
p=sys.argv[1]; j=json.load(open(p)); j['close'].remove('com.apple.Photos'); j['tabs']['noise'].remove('reddit.com'); json.dump(j,open(p,'w'))
PY
check "current file: a missing default arrives"     yes "$(listed close com.apple.Photos)"
check "current file: a missing host arrives"        yes "$(listed noise reddit.com)"
sum1=$(shasum "$RC"); rc verdict com.example.mine >/dev/null; sum2=$(shasum "$RC")
check "a load with nothing new leaves the file as is" "$sum1" "$sum2"
rc set unsorted com.spotify.client
check "Unsorted on a default survives the next load" unsorted "$(rc verdict com.spotify.client)"
rc set-serving no com.tinyspeck.slackmacgap
check "serving off on a default survives the next load" no "$(rc serving com.tinyspeck.slackmacgap)"

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
python3 tools/validate_row.py registry/agents/*.json >/dev/null;   check "registry rows pass the validator" 0 "$?"
# Every working signal a row declares must be one that both detectors evaluate.
unread=$(python3 - <<'PY'
import glob, json, re
cli = set(re.findall(r'kind isEqualToString:@"(\w+)"', open("Sources/Agents.m").read()))
ref = set(re.findall(r'kind == "(\w+)"', open("tools/agents_probe.py").read()))
used = {s["signal"] for f in glob.glob("registry/agents/*.json") + glob.glob("tools/fixtures/**/*.json", recursive=True)
        for s in json.load(open(f))["working_signals"]}
print(" ".join(sorted(used - (cli & ref))) or "none")
PY
)
check "no row declares a signal the detectors ignore" none "$unread"
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
pkill -P $FH 2>/dev/null; kill $FH 2>/dev/null; wait $FH 2>/dev/null

# Real sessions: wherever the precise signal decides, both implementations must agree.
if [ "${1:-}" = "--live" ]; then
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
else
skip "real sessions: CLI and reference probe agree" "reads real processes; pass --live to run it"
fi

echo "== cmux reader (fixture directory; the real ~/.cmuxterm is never read)"
CMUX="$TMP/cmux"; mkdir -p "$CMUX"; defaults write "$DOM" minmacs.debug.cmuxDir "$CMUX"
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
defaults write "$DOM" minmacs.readCmux -bool true
check "setting on (minmacs.readCmux) reads it" blocked "$(cmuxstate)"
defaults write "$DOM" minmacs.readCmux -bool false
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
defaults delete "$DOM" minmacs.debug.cmuxDir >/dev/null 2>&1; defaults delete "$DOM" minmacs.readCmux >/dev/null 2>&1

if [ "${1:-}" = "--browser" ]; then
  echo "== live browser trim (opens two tabs of its own in Chrome)"
  defaults write "$DOM" minmacs.quitBrowsers -bool false
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
  [ "$was" = "no" ] && echo "  (Chrome was not running before the test; it is left open with the GitHub tab)"
fi

echo; echo "passed $pass, failed $fail, skipped $skipped"; [ $fail = 0 ]
