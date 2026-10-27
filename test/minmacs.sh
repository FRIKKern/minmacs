# ===== MinMacs expert: apps, quit, force quit, restore, tab trim and agent sparing, issue #21 =====
# Sourced by test.sh after core. Builds test/minmacs/tool.m with all of Core, the kit and the expert, under -DMM_TESTS.
# Fixtures only, all inside $MINMACS_HOME, with names and bundle ids unique to this run:
#   four copies of test/minmacs/stubborn.m: one that quits when asked, one that refuses, a fixture browser, and one an agent starts
#   test/minmacs/agent.c under its own name, with a registry row that names it
#   a JSON file for the fake tab bridge, so no Apple event reaches a real browser
# The tool quits and trims only bundle ids with this run's prefix. Cleanup stops only the pids this section started.

mx="$MINMACS_HOME/mmx"
mkdir -p "$mx/home" "$mx/rows" "$mx/pi"
mx=$(cd "$mx" && pwd -P)
mxh="$mx/home"
mx_run=$$
mx_only="no.guerrilla.minmacs.mmx$mx_run."
mx_tab=$(printf '\t')
mx_lsreg=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

mx_cc="clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -DMM_TESTS -ISources"
# shellcheck disable=SC2046
$mx_cc $(find Sources/Core Sources/UI Sources/Experts/MinMacs -name '*.m' | LC_ALL=C sort) test/minmacs/tool.m \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  -o "$mx/tool" >"$mx/build.log" 2>&1
mx_r=$?
check "minmacs: the test tool builds" 0 "$mx_r"
check "minmacs: the expert has no warnings under -Wextra" 0 "$(grep -c 'warning:' "$mx/build.log")"
[ "$mx_r" = 0 ] || tail -20 "$mx/build.log"
clang -O1 test/minmacs/agent.c -o "$mx/mmxagent$mx_run" >>"$mx/build.log" 2>&1
check "minmacs: the fixture agent builds" 0 "$?"

# One fixture app bundle: name, bundle id.
mx_app() {
  mkdir -p "$mx/$1.app/Contents/MacOS"
  clang -fobjc-arc -mmacosx-version-min=14.0 -framework Cocoa test/minmacs/stubborn.m -o "$mx/$1.app/Contents/MacOS/$1" >>"$mx/build.log" 2>&1 || return 1
  cat >"$mx/$1.app/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleName</key><string>$1</string><key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleExecutable</key><string>$1</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PL
  codesign --force --sign - "$mx/$1.app" >/dev/null 2>&1
}
mx_polite="MMXPolite$mx_run"; mx_pid_polite="${mx_only}polite"
mx_stub="MMXStubborn$mx_run"; mx_pid_stub="${mx_only}stubborn"
mx_browse="MMXBrowse$mx_run"; mx_pid_browse="${mx_only}browse.polite"
mx_spare="MMXSpare$mx_run"; mx_pid_spare="${mx_only}spare.polite"
mx_ok=0
for a in "$mx_polite:$mx_pid_polite" "$mx_stub:$mx_pid_stub" "$mx_browse:$mx_pid_browse" "$mx_spare:$mx_pid_spare"; do
  mx_app "${a%%:*}" "${a#*:}" || mx_ok=1
done
check "minmacs: the four fixture apps build" 0 "$mx_ok"

# The fixture agent's registry row, under this run's process name.
sed "s/\"fakeagent\"/\"mmxagent$mx_run\"/; s/\"fake-agent\"/\"mmx-agent\"/; s/\"Fake Agent\"/\"Fixture Agent\"/" \
  tools/fixtures/fake-agent.json >"$mx/rows/mmx-agent.json"
check "minmacs: the fixture row passes the validator" 0 "$(python3 tools/validate_row.py "$mx/rows/mmx-agent.json" >/dev/null 2>&1; echo $?)"

# Quit gets two seconds in place of eight, so the checks stay short.
python3 - "$mxh/Preferences/no.guerrilla.minmacs.plist" <<'PY'
import os, plistlib, sys
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
plistlib.dump({"minmacs.grace": 2.0}, open(sys.argv[1], "wb"))
PY

mxt() { MINMACS_HOME="$mxh" MMM_ONLY="$mx_only" MMM_ROWS="$mx/rows" MMM_TABS="$mx/tabs.json" MMM_BROWSER="$mx_pid_browse" \
        PI_CODING_AGENT_SESSION_DIR="$mx/pi" "$mx/tool" "$@"; }
# The pid of a fixture app, found by the full path of this run's copy, or empty.
mx_pidof() { pgrep -f "$mx/$1.app/Contents/MacOS/$1" | head -1; }
mx_running() { [ -n "$(mx_pidof "$1")" ] && echo yes || echo no; }
mx_launched() { for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do p=$(mx_pidof "$1"); [ -n "$p" ] && { procs="$procs $p"; echo yes; return; }; sleep 0.5; done; echo no; }
mx_gone() { for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(mx_running "$1")" = no ] && { echo yes; return; }; sleep 0.5; done; echo no; }
# One field of one app in `apps --json`: the group it sits in, or its reason.
mx_group() { mxt verb apps --json | python3 -c "
import json,sys; j=json.load(sys.stdin)
g=[k for k in ('quit','trim','spared','keep','unsorted') for a in j[k] if a['bundleID']==sys.argv[1]]
print(g[0] if g else 'absent')" "$1"; }
mx_reason() { mxt verb apps --json | python3 -c "
import json,sys; j=json.load(sys.stdin)
r=[a.get('reason','') for k in ('quit','trim','spared','keep','unsorted') for a in j[k] if a['bundleID']==sys.argv[1]]
print(r[0] if r else 'absent')" "$1"; }
mx_undo() { mxt undo | python3 -c "import json,sys; j=json.load(sys.stdin); print($1)"; }

if [ "$mx_r" = 0 ]; then
  # ----- Rules, ported from tools/rulecheck.m on branch legacy: #43, #44 and #45 -----
  mkdir -p "$mxh/minmacs"
  mx_rules="$mxh/minmacs/rules.json"
  listed() { mxt list "$1" | grep -qxF "$2" && echo yes || echo no; }
  cat >"$mx_rules" <<'EOF'
{"version":3,"keep":["com.jetbrains.*"],"close":["com.adobe.*"],"unsorted":[],"tabs":{"noise":[],"work":[]},"ignoreServing":[]}
EOF
  check "minmacs rules: com.adobe.* closes Photoshop"           close "$(mxt verdict com.adobe.Photoshop)"
  check "minmacs rules: com.adobe.* closes Illustrator"         close "$(mxt verdict com.adobe.illustrator)"
  mxt verb apps keep com.adobe.Photoshop >/dev/null
  check "minmacs rules #43: Keep on Photoshop keeps it"         keep "$(mxt verdict com.adobe.Photoshop)"
  check "minmacs rules #43: Illustrator still closes"           close "$(mxt verdict com.adobe.illustrator)"
  check "minmacs rules #43: com.adobe.* stays on the close list" yes "$(listed close 'com.adobe.*')"
  mxt verb apps unsorted com.adobe.Photoshop >/dev/null
  check "minmacs rules: Unsorted on Photoshop leaves it alone"  unsorted "$(mxt verdict com.adobe.Photoshop)"
  check "minmacs rules: and is recorded as an exception"        yes "$(listed unsorted com.adobe.Photoshop)"
  mxt verb apps close com.adobe.Photoshop >/dev/null
  check "minmacs rules: Close drops the Unsorted exception"     no "$(listed unsorted com.adobe.Photoshop)"
  mxt verb apps close com.jetbrains.goland >/dev/null
  check "minmacs rules: Close on GoLand beats com.jetbrains.*"  close "$(mxt verdict com.jetbrains.goland)"
  check "minmacs rules: IntelliJ is still kept"                 keep "$(mxt verdict com.jetbrains.intellij)"
  mxt verb apps unsorted com.example.nothing >/dev/null
  check "minmacs rules: Unsorted with no pattern adds no entry" no "$(listed unsorted com.example.nothing)"
  cat >"$mx_rules" <<'EOF'
{"version":3,"keep":[],"close":[],"unsorted":[],"tabs":{"noise":[],"work":[]},"ignoreServing":["com.adobe.*","*zoom*","com.hnc.Discord"]}
EOF
  check "minmacs rules #44: ignoreServing exact id"             yes "$(mxt serving com.hnc.Discord)"
  check "minmacs rules #44: a trailing * matches a prefix"      yes "$(mxt serving com.adobe.Photoshop)"
  check "minmacs rules #44: *x* matches inside the id"          yes "$(mxt serving us.zoom.xos)"
  check "minmacs rules #44: an unlisted app is not ignored"     no "$(mxt serving com.example.app)"
  mxt verb apps serving on com.adobe.Photoshop >/dev/null
  check "minmacs rules #44: serving on for Photoshop works"     no "$(mxt serving com.adobe.Photoshop)"
  check "minmacs rules #44: Illustrator is still ignored"       yes "$(mxt serving com.adobe.illustrator)"
  check "minmacs rules #44: the pattern stays"                  yes "$(listed ignoreServing 'com.adobe.*')"
  mxt verb apps serving off com.adobe.Photoshop >/dev/null
  check "minmacs rules #44: and back off drops the exception"   no "$(listed ignoreServing '!com.adobe.Photoshop')"
  cat >"$mx_rules" <<'EOF'
{"version":2,"keep":["com.apple.Terminal","com.google.Chrome"],"close":["com.spotify.client","com.example.mine"],
 "unsorted":["com.apple.Music"],"tabs":{"noise":["youtube.com"],"work":["github.com","netflix.com"]},"ignoreServing":["!com.hnc.Discord"]}
EOF
  check "minmacs rules #45: a version 2 file gets a keep default"   yes "$(listed keep com.microsoft.VSCode)"
  check "minmacs rules #45: and a close default"                    yes "$(listed close com.apple.Photos)"
  check "minmacs rules #45: and a noise host"                       yes "$(listed noise reddit.com)"
  check "minmacs rules #45: and an ignoreServing default"           yes "$(listed ignoreServing com.spotify.client)"
  check "minmacs rules #45: a user entry stays"                     yes "$(listed close com.example.mine)"
  check "minmacs rules #45: a default the user kept stays kept"     keep "$(mxt verdict com.google.Chrome)"
  check "minmacs rules #45: and is not added to close"              no "$(listed close com.google.Chrome)"
  check "minmacs rules #45: a host moved to work stays out of noise" no "$(listed noise netflix.com)"
  check "minmacs rules #45: a default on the unsorted list stays out" unsorted "$(mxt verdict com.apple.Music)"
  check "minmacs rules #45: a default with a ! exception stays out" no "$(mxt serving com.hnc.Discord)"
  check "minmacs rules: the file is written as version 3"           3 "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$mx_rules")"
  python3 - "$mx_rules" <<'PY'
import json,sys
p=sys.argv[1]; j=json.load(open(p)); j['close'].remove('com.apple.Photos'); j['tabs']['noise'].remove('reddit.com'); json.dump(j,open(p,'w'))
PY
  check "minmacs rules #45: a version 3 file gets a missing default" yes "$(listed close com.apple.Photos)"
  check "minmacs rules #45: and a missing host"                     yes "$(listed noise reddit.com)"
  mx_sum1=$(shasum "$mx_rules" | cut -c1-12); mxt verdict com.example.mine >/dev/null; mx_sum2=$(shasum "$mx_rules" | cut -c1-12)
  check "minmacs rules #45: a load with nothing new leaves the file" "$mx_sum1" "$mx_sum2"
  mxt verb apps unsorted com.spotify.client >/dev/null
  check "minmacs rules #45: Unsorted on a default survives a load"  unsorted "$(mxt verdict com.spotify.client)"
  mxt verb apps serving on com.tinyspeck.slackmacgap >/dev/null
  check "minmacs rules #45: serving on for a default survives a load" no "$(mxt serving com.tinyspeck.slackmacgap)"
  check "minmacs: youtube.com is noise"            noise "$(mxt verb apps classify https://www.youtube.com/watch?v=x)"
  check "minmacs: a subdomain of a noise host"     noise "$(mxt verb apps classify music.youtube.com)"
  check "minmacs: localhost with a port is work"   work "$(mxt verb apps classify http://localhost:4000/studio)"
  check "minmacs: an unknown host is left alone"   other "$(mxt verb apps classify https://example.org/)"
  check "minmacs: work wins when both match"       work "$(mxt verb apps classify https://aws.amazon.com/console)"
  # The fixtures go on the close list. Everything else keeps the defaults.
  for b in "$mx_pid_polite" "$mx_pid_stub" "$mx_pid_browse" "$mx_pid_spare"; do mxt verb apps close "$b" >/dev/null; done

  # ----- Quit, restore and the undo record -----
  open -g -n "$mx/$mx_polite.app" 2>/dev/null
  mx_gui=$(mx_launched "$mx_polite")
  check "minmacs: the polite fixture app launched" yes "$mx_gui"
fi

if [ "$mx_r" = 0 ] && [ "$mx_gui" = yes ]; then
  check "minmacs: apps lists it under Will quit"       quit "$(mx_group "$mx_pid_polite")"
  mxt verb apps | sed -n '/^Will quit/,/^[A-Z]/p' | grep -q "$mx_pid_polite"
  check "minmacs: the text plan lists it under Will quit" 0 "$?"
  check "minmacs: --dry-run says what it would do"     yes "$(mxt verb apps quit "$mx_pid_polite" --dry-run | grep -q '^would quit' && echo yes || echo no)"
  check "minmacs: and quits nothing"                   yes "$(mx_running "$mx_polite")"
  check "minmacs: the tool refuses a real app"         9 "$(mxt verb apps quit com.apple.Finder >/dev/null 2>&1; echo $?)"
  check "minmacs: the tool refuses --all"              9 "$(mxt verb apps quit "$mx_pid_polite" --all >/dev/null 2>&1; echo $?)"
  mx_old=$(mx_pidof "$mx_polite")
  mxt verb apps quit "$mx_pid_polite" >"$mx/quit.txt"; mx_rc=$?
  check "minmacs: apps quit exits 0"                   0 "$mx_rc"
  check "minmacs: and the app is gone"                 yes "$(mx_gone "$mx_polite")"
  check "minmacs: the undo record is done"             done "$(mx_undo "j[0]['state']")"
  check "minmacs: it is kind quit, by cli"             "quit cli" "$(mx_undo "j[0]['kind'], j[0]['by']")"
  check "minmacs: it names the bundle id to relaunch"  "$mx_pid_polite" "$(mx_undo "j[0]['payload']['relaunch']['bundleID']")"
  check "minmacs: and the instance it quit"            "$mx_old" "$(mx_undo "j[0]['payload']['relaunch']['pid'].split(':')[0]")"
  check "minmacs: status counts one to restore"        1 "$(mxt verb status --json | python3 -c "import json,sys; print(json.load(sys.stdin)['restorable'])")"
  check "minmacs: restore --dry-run opens nothing"     no "$(mxt verb restore --dry-run >/dev/null; sleep 1; mx_running "$mx_polite")"
  mxt verb restore --json >"$mx/restore.json"; mx_rc=$?
  check "minmacs: restore exits 0"                     0 "$mx_rc"
  check "minmacs: restore relaunches it"               yes "$(mx_launched "$mx_polite")"
  check "minmacs: the record is restored"              restored "$(mx_undo "j[0]['state']")"
  check "minmacs: a second restore has nothing to do"  0 "$(mxt verb restore --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)['results']))")"

  # ----- A finding from an old snapshot: the app quit and opened again before the action ran -----
  mx_old=$(mx_pidof "$mx_polite")
  mxt stale "$mx_pid_polite" 5 >"$mx/stale.txt" 2>&1 &
  mx_stale=$!; procs="$procs $mx_stale"
  sleep 2
  kill "$mx_old" 2>/dev/null
  mx_gone "$mx_polite" >/dev/null
  open -g -n "$mx/$mx_polite.app" 2>/dev/null
  mx_launched "$mx_polite" >/dev/null
  wait "$mx_stale"; mx_rc=$?
  check "minmacs: an action on a stale finding is refused" 1 "$mx_rc"
  check "minmacs: because the fresh check sees the old pid gone" yes "$(grep -q 'refused: cannot run now: it has already quit' "$mx/stale.txt" && echo yes || echo no)"
  check "minmacs: and the new instance still runs"     yes "$(mx_running "$mx_polite")"

  # ----- Modes: Proactive never quits, Eager only under memory pressure, and only after the day of watching -----
  check "minmacs: Proactive keeps a close-list app" "keep${mx_tab}Proactive never quits an app on its own" \
    "$(MMM_PRESSURE=1 mxt plan proactive | grep "^$mx_pid_polite" | cut -f2,3)"
  check "minmacs: Eager keeps it with no memory pressure" "keep${mx_tab}Eager quits apps only while memory pressure or heat is high" \
    "$(MMM_PRESSURE=1 mxt plan eager | grep "^$mx_pid_polite" | cut -f2,3)"
  check "minmacs: Eager under pressure waits for the day of watching" yes \
    "$(MMM_PRESSURE=4 mxt plan eager | grep "^$mx_pid_polite" | cut -f3 | grep -q '^would act' && echo yes || echo no)"
  printf '%s\n' "$(( $(date +%s) - 2 * 86400 ))" >"$mxh/watching-since"
  check "minmacs: Eager under pressure after a day would quit it" act \
    "$(MMM_PRESSURE=4 mxt plan eager | grep "^$mx_pid_polite" | cut -f2)"
  rm -f "$mxh/watching-since"
  mx_p=$(mx_pidof "$mx_polite"); kill "$mx_p" 2>/dev/null; mx_gone "$mx_polite" >/dev/null

  # ----- Force quit: SIGKILL's app form only on a second request -----
  open -g -n "$mx/$mx_stub.app" 2>/dev/null
  check "minmacs: the stubborn fixture app launched"  yes "$(mx_launched "$mx_stub")"
  mxt verb apps quit "$mx_pid_stub" --force >"$mx/force1.txt"; mx_rc=$?
  check "minmacs: Force Quit before Quit is refused"  1 "$mx_rc"
  check "minmacs: and says why"                       yes "$(grep -q 'Force Quit comes only after Quit' "$mx/force1.txt" && echo yes || echo no)"
  check "minmacs: and the app still runs"             yes "$(mx_running "$mx_stub")"
  mxt verb apps quit "$mx_pid_stub" >"$mx/quit2.txt"; mx_rc=$?
  check "minmacs: a normal Quit it refuses exits 3"   3 "$mx_rc"
  check "minmacs: it still runs"                      yes "$(mx_running "$mx_stub")"
  check "minmacs: the record failed"                  failed "$(mx_undo "j[0]['state']")"
  mxt verb apps quit "$mx_pid_stub" --force >"$mx/force2.txt"; mx_rc=$?
  check "minmacs: Force Quit as the second request exits 0" 0 "$mx_rc"
  check "minmacs: and the app is gone"                yes "$(mx_gone "$mx_stub")"
  check "minmacs: the force record says kill"         "done kill" "$(mx_undo "j[0]['state'], j[0]['payload']['relaunch']['step']")"
  check "minmacs: a failed Quit is not offered for restore" 1 "$(mxt verb restore --dry-run --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)['results']))")"

  # ----- Serving: a loopback listener spares a close-list app, and ignoreServing turns that off -----
  mx_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
  open -g -n "$mx/$mx_stub.app" --args --listen "$mx_port" 2>/dev/null
  mx_launched "$mx_stub" >/dev/null
  sleep 1
  check "minmacs: a listener spares it"               spared "$(mx_group "$mx_pid_stub")"
  check "minmacs: and names the port"                 "serving on 127.0.0.1:$mx_port" "$(mx_reason "$mx_pid_stub")"
  mxt verb apps quit "$mx_pid_stub" >"$mx/serve.txt"; mx_rc=$?
  check "minmacs: Quit on a spared app is refused"    1 "$mx_rc"
  check "minmacs: by MustKeep on fresh facts"         yes "$(grep -q "kept: serving on 127.0.0.1:$mx_port" "$mx/serve.txt" && echo yes || echo no)"
  check "minmacs: and it still runs"                  yes "$(mx_running "$mx_stub")"
  mxt verb apps serving off "$mx_pid_stub" >/dev/null
  check "minmacs: ignoreServing puts it back on Will quit" quit "$(mx_group "$mx_pid_stub")"
  mxt verb apps quit "$mx_pid_stub" >/dev/null
  mxt verb apps quit "$mx_pid_stub" --force >/dev/null
  check "minmacs: then Quit and Force Quit end it"    yes "$(mx_gone "$mx_stub")"
  mxt verb apps serving on "$mx_pid_stub" >/dev/null

  # ----- Agent-aware sparing: an app a working agent started stays -----
  "$mx/mmxagent$mx_run" --work 60 --app "$mx/$mx_spare.app/Contents/MacOS/$mx_spare" &
  mx_agent=$!; procs="$procs $mx_agent"
  check "minmacs: the agent's app launched"           yes "$(mx_launched "$mx_spare")"
  for c in $(pgrep -P "$mx_agent"); do procs="$procs $c"; done
  sleep 2
  check "minmacs: the agent reads working"            working "$(mxt verb apps --json | python3 -c "import json,sys; a=[x for x in json.load(sys.stdin)['agents'] if x['name']=='Fixture Agent']; print(a[0]['state'] if a else 'absent')")"
  check "minmacs: its app is spared"                  spared "$(mx_group "$mx_pid_spare")"
  check "minmacs: and the reason names the agent"     "Fixture Agent started it and is working" "$(mx_reason "$mx_pid_spare")"
  mxt verb apps quit "$mx_pid_spare" >"$mx/spare.txt"; mx_rc=$?
  check "minmacs: Quit on it is refused"              1 "$mx_rc"
  check "minmacs: and the app still runs"             yes "$(mx_running "$mx_spare")"
  check "minmacs: status counts the agent"            1 "$(mxt verb status --json | python3 -c "import json,sys; print(json.load(sys.stdin)['agents']['working'])")"
  mx_p=$(mx_pidof "$mx_spare")
  for c in $(pgrep -P "$mx_agent"); do kill "$c" 2>/dev/null; done
  kill "$mx_agent" 2>/dev/null; wait "$mx_agent" 2>/dev/null
  kill "$mx_p" 2>/dev/null; mx_gone "$mx_spare" >/dev/null

  # ----- Browser tab trim against the fake bridge -----
  open -g -n "$mx/$mx_browse.app" 2>/dev/null
  check "minmacs: the fixture browser launched"       yes "$(mx_launched "$mx_browse")"
  mx_bp=$(mx_pidof "$mx_browse")
  cat >"$mx/tabs.json" <<EOF
{"tabs": [
 {"pid": $mx_bp, "window": 1, "id": 11, "url": "https://www.youtube.com/watch?v=fixture", "title": "Video"},
 {"pid": $mx_bp, "window": 1, "id": 12, "url": "https://github.com/fixture/repo", "title": "Repo"},
 {"pid": $mx_bp, "window": 1, "id": 13, "url": "https://example.org/", "title": "Other"},
 {"pid": $mx_bp, "window": 1, "id": 14, "url": "https://vimeo.com/fixture", "title": "Clip"},
 {"pid": $mx_bp, "window": 2, "id": 21, "url": "https://www.reddit.com/r/fixture", "title": "Private", "mode": "incognito"}
], "closed": [], "opened": []}
EOF
  check "minmacs: a browser is trimmed, not quit"     trim "$(mx_group "$mx_pid_browse")"
  check "minmacs: --dry-run names the noise tabs"     "would close 2 of 4 tabs in $mx_browse: youtube.com, vimeo.com" \
    "$(mxt verb apps trim "$mx_pid_browse" --dry-run)"
  MMM_MOVE_HOST=vimeo.com mxt verb apps trim "$mx_pid_browse" >"$mx/trim.txt"; mx_rc=$?
  check "minmacs: trim exits 0"                       0 "$mx_rc"
  mx_tabs() { python3 -c "import json,sys; j=json.load(open(sys.argv[1])); print($1)" "$mx/tabs.json"; }
  check "minmacs: it closed the noise tab"            "https://www.youtube.com/watch?v=fixture" "$(mx_tabs "' '.join(j['closed'])")"
  check "minmacs: a tab that moved on stays open"     yes "$(mx_tabs "'yes' if any(t['id']==14 for t in j['tabs']) else 'no'")"
  check "minmacs: work and other tabs stay"           "12 13" "$(mx_tabs "' '.join(str(t['id']) for t in j['tabs'] if t['id'] in (12,13))")"
  check "minmacs: a private window is never read"     yes "$(mx_tabs "'yes' if any(t['id']==21 for t in j['tabs']) else 'no'")"
  check "minmacs: the browser still runs"             yes "$(mx_running "$mx_browse")"
  check "minmacs: the trim record holds only the closed tab" "trim done https://www.youtube.com/watch?v=fixture" \
    "$(mx_undo "j[0]['kind'], j[0]['state'], ' '.join(t['url'] for t in j[0]['payload']['tabs'])")"
  check "minmacs: a second trim finds no noise tab"   1 "$(mxt verb apps trim "$mx_pid_browse" >/dev/null 2>&1; echo $?)"
  # By its rid, so the force quit records above are not relaunched here.
  mxt verb restore "$(mx_undo "j[0]['rid']")" >/dev/null
  check "minmacs: restore reopens the closed tab"     "https://www.youtube.com/watch?v=fixture" "$(mx_tabs "' '.join(j['opened'])")"
  check "minmacs: and marks the trim restored"        restored "$(mx_undo "[r['state'] for r in j if r['kind']=='trim'][0]")"
  mx_p=$(mx_pidof "$mx_browse"); kill "$mx_p" 2>/dev/null; mx_gone "$mx_browse" >/dev/null

  check "minmacs: status prints one line"             yes "$(mxt verb status | grep -q '^MinMacs: [0-9]* app' && echo yes || echo no)"
fi

# Invariants read from the source: no signal, no spawn and no tick tool in the expert. Quitting goes through Core Act.
check "minmacs: the expert sends no signal itself"   0 "$(grep -nE '\bkill\(|SIGKILL|SIGTERM|forceTerminate|\bterminate\]' Sources/Experts/MinMacs/*.m | grep -c .)"
check "minmacs: the expert runs no process"          0 "$(grep -nE 'NSTask|popen\(|system\(|posix_spawn|\blsof\b|\bnettop\b|\bpmset\b|claude -p|codex exec' Sources/Experts/MinMacs/*.m | grep -c .)"
check "minmacs: actions run through MMRunAction"     yes "$(grep -q 'MMRunAction(' Sources/Experts/MinMacs/MMMinMacsExpert.m && echo yes || echo no)"
check "minmacs: quitting goes through MMQuitApps"    yes "$(grep -q 'MMQuitApps(' Sources/Experts/MinMacs/MMMinMacsExpert.m && echo yes || echo no)"

# ----- The menu and cards from a fixture, in light, dark and Increase Contrast -----
if [ "$mx_r" = 0 ]; then
  mx_out="$ROOT/build/render/minmacs"
  rm -rf "$mx_out"
  MINMACS_HOME="$mx/render-home" "$mx/tool" render "$mx_out" >/dev/null 2>&1
  check "minmacs: the render runs"                    0 "$?"
  check "minmacs: every PNG is there"                 28 "$(ls "$mx_out"/*.png 2>/dev/null | wc -l | tr -d ' ')"
  check "minmacs: the render's DESIGN.md checks pass" 0 "$([ -f "$mx_out/checks.txt" ] && { grep -c '^FAIL' "$mx_out/checks.txt"; true; } || echo missing)"
  grep '^FAIL' "$mx_out/checks.txt" 2>/dev/null | sed 's/^/        /'
  check "minmacs: every PNG has the kit's one width"  "720 " "$(for f in "$mx_out"/*.png; do sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/ {print $2}'; done | sort -u | tr '\n' ' ')"
  check "minmacs: the accessibility state is words"   "3 apps to quit" "$(sed -n 's/^TEXT a11y //p' "$mx_out/checks.txt")"
  check "minmacs: no line holds parentheses"          0 "$(grep '^TEXT' "$mx_out/checks.txt" | grep -c '[()]')"
  check "minmacs: a stuck app's card offers Force Quit" yes "$(grep -q '^TEXT cardaction slack | Force Quit' "$mx_out/checks.txt" && echo yes || echo no)"
  check "minmacs: a spared app's Quit is dimmed"      yes "$(grep -q '^TEXT cardaction figma | Quit | in use' "$mx_out/checks.txt" && echo yes || echo no)"
fi

# Stops what this section started, by pid, and drops the fixture bundles from LaunchServices.
for a in "$mx_polite" "$mx_stub" "$mx_browse" "$mx_spare"; do
  pkill -9 -f "$mx/$a.app/Contents/MacOS/$a" 2>/dev/null
  [ -x "$mx_lsreg" ] && "$mx_lsreg" -u "$mx/$a.app" >/dev/null 2>&1
done
# ===== end of MinMacs =====
