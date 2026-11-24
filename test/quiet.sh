# ===== quiet: peace for a task while its process runs, D9 part 3 =====
# Sourced by test.sh after core. test/quiet/tool.m stands in for the app: `tool hold` takes a quiet hold for a fixture
# process and keeps its assertions, while other runs of the tool try a mode's run on a fixture server and a fixture
# cache. Fixtures only, all inside $MINMACS_HOME: a sleeper under a name unique to the run is the held process, a
# Python HTTP server in a fixture project is the server, and a pip cache under MINMACS_CLUTTER_ROOT is the cache.
# The test holds only its own sleeper's pid. It stops only what it started, by pid. `pmset -g assertions` is read only
# here, in the test, to see that the assertions come and go.
. ./test/quiet/build.sh
qt=$(cd "$MINMACS_HOME" && pwd -P)/quiet$$
mkdir -p "$qt/root/home/Library/Caches/pip/http" "$qt/app" "$qt/claude"
qt_sleeper="$qt/qsleep$$"
clang -O1 test/insomnia/sleeper.c -o "$qt_sleeper" >"$qt/sleeper.log" 2>&1
check "quiet: the fixture process builds" 0 "$?"
qt_reason="quiet-test-$$"
# Every run of the tool and the binary shares this home: the holds file, the log and the prefs. The clutter root lies
# inside it, as MMClutterRoot asks.
qt_env() { env MINMACS_HOME="$qt" MINMACS_CLUTTER_ROOT="$qt/root" MINMACS_CLUTTER_ROWS="$ROOT/registry/clutter" \
  CLAUDE_CONFIG_DIR="$qt/claude" LOCOHOST_IDLE_MINUTES=0 LOCOHOST_MIN_UPTIME_MINUTES=0 "$@"; }
qt_tool() { qt_env "$DQ" "$@"; }
qt_quiet() { qt_tool cli quiet --json 2>/dev/null | json "$1"; }
qt_unproc() { qp=""; for p in $procs; do [ "$p" = "$1" ] || qp="$qp $p"; done; procs=$qp; }
# Waits up to 5 s for a Python expression on `quiet --json` to be true.
qt_until() { qi=0; while [ $qi -lt 50 ]; do [ "$(qt_quiet "$1")" = True ] && return 0; qi=$((qi+1)); sleep 0.1; done; return 1; }
qt_asserts() { # how many of the assertions named for this run pmset lists now, by type
  pmset -g assertions 2>/dev/null | grep -F "quiet: $qt_reason" | grep -cE "$1"; }
qt_wait_asserts() { qi=0; while [ $qi -lt 50 ]; do [ "$(qt_asserts "$1")" = "$2" ] && return 0; qi=$((qi+1)); sleep 0.1; done; return 1; }

# The fixtures: a pip cache of 8 MB, and a dev server in a project folder. The server calls setsid.
dd if=/dev/zero of="$qt/root/home/Library/Caches/pip/http/wheel.bin" bs=1048576 count=8 2>/dev/null
qt_pip="$qt/root/home/Library/Caches/pip"
printf '{"name": "quiet-fixture", "scripts": {"dev": "python3 -m http.server"}}' >"$qt/app/package.json"
qt_P=$("$PORT" free $((41000 + $$ % 8000)))
QT_PY='import http.server, os, sys
try: os.setsid()
except OSError: pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), http.server.SimpleHTTPRequestHandler).serve_forever()'
(cd "$qt/app" && exec python3 -c "$QT_PY" "$qt_P" >/dev/null 2>&1) &
qt_srv=$!; procs="$procs $qt_srv"
"$PORT" wait "$qt_P" 100
check "quiet: the fixture server listens" 0 "$?"
"$qt_sleeper" 600 & qt_s1=$!; procs="$procs $qt_s1"

echo "-- before any hold, a mode would act on both fixtures"
check "quiet: no hold yet" False "$(qt_quiet "j['active']")"
check "quiet: Eager would stop the fixture server" True "$(qt_tool auto locohost "$qt_P" --dry | json "j['act']")"
check "quiet: Eager would clean the fixture cache" True "$(qt_tool auto noonoo "$qt_pip" --dry | json "j['act']")"

echo "-- the verb's own checks"
qt_env MINMACS_COLD=1 "$BIN" quiet hold "$qt_s1" --reason "$qt_reason" >/dev/null 2>&1
check "quiet: a hold needs the app" 3 "$?"
check "quiet: --dry-run says what it would do" "would keep quiet, and the Mac and display awake, until pid $qt_s1 exits: $qt_reason" \
  "$(qt_env MINMACS_COLD=1 "$BIN" quiet hold "$qt_s1" --reason "$qt_reason" --dry-run 2>/dev/null)"
qt_tool cli quiet hold 1 >/dev/null 2>&1
check "quiet: pid 1 is never held" 1 "$?"
qt_tool cli quiet hold abc >/dev/null 2>&1
check "quiet: a word that is no pid is a usage error" 2 "$?"
qt_tool cli quiet release "$qt_s1" >/dev/null 2>&1
check "quiet: a release with no hold says so" 1 "$?"

echo "-- a hold on the fixture process"
(exec env MINMACS_HOME="$qt" "$DQ" hold "$qt_s1" "$qt_reason" 60 >"$qt/hold1.out" 2>"$qt/hold1.err") &
qt_h1=$!; procs="$procs $qt_h1"
qt_until "j['active'] and j['holders'][0]['pid'] == $qt_s1"
check "quiet: the hold is active" 0 "$?"
check "quiet: it names the process, the reason and that the Mac is held awake" "$qt_s1 $qt_reason True" \
  "$(qt_quiet "'%s %s %s' % (j['holders'][0]['pid'], j['holders'][0]['reason'], j['holders'][0]['awake'])")"
qt_wait_asserts PreventUserIdleSystemSleep 1
check "quiet: the Mac is held awake" 1 "$(qt_asserts PreventUserIdleSystemSleep)"
check "quiet: and the display" 1 "$(qt_asserts PreventUserIdleDisplaySleep)"
check "quiet: the tool holds them, not the held process" "$qt_h1" \
  "$(pmset -g assertions 2>/dev/null | grep -F "quiet: $qt_reason" | sed -n 's/^ *pid \([0-9]*\)(.*/\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//')"
check "quiet: device reports it, from another process" "True $qt_s1 $qt_reason" \
  "$(qt_env MINMACS_COLD=1 "$BIN" device --json 2>/dev/null | json "'%s %s %s' % (j['quiet']['active'], j['quiet']['holders'][0]['pid'], j['quiet']['holders'][0]['reason'])")"
check "quiet: a cold device run says the hold keeps the Mac awake" True \
  "$(qt_env MINMACS_COLD=1 "$BIN" device --json 2>/dev/null | json "j['awake']['held'] and j['awake']['quiet'][0]['awake']")"

qt_tool auto locohost "$qt_P" >"$qt/lh.json" 2>"$qt/lh.err"
check "quiet: Eager plans no stop of the server" False "$(json "j['act']" <"$qt/lh.json")"
check "quiet: and says why" True "$(json "'a quiet hold is active for $qt_reason (pid $qt_s1)' in j['why']" <"$qt/lh.json")"
check "quiet: an Eager run of the stop is refused in MMRunAction" "False True" \
  "$(json "'%s %s' % (j['ran'], j['error'].startswith('kept: a quiet hold is active'))" <"$qt/lh.json")"
check "quiet: the server still listens" 0 "$("$PORT" listening "$qt_P"; echo $?)"
qt_tool auto noonoo "$qt_pip" >"$qt/nn.json" 2>"$qt/nn.err"
check "quiet: Eager plans no clean of the cache" False "$(json "j['act']" <"$qt/nn.json")"
check "quiet: an Eager run of the clean is refused" "False True" \
  "$(json "'%s %s' % (j['ran'], j['error'].startswith('kept: a quiet hold is active'))" <"$qt/nn.json")"
check "quiet: the cache is still there" yes "$([ -f "$qt_pip/http/wheel.bin" ] && echo yes || echo no)"

echo "-- release from another process ends it"
qt_tool cli quiet release "$qt_s1" >/dev/null 2>&1
check "quiet: release exits 0" 0 "$?"
check "quiet: no hold is active" False "$(qt_quiet "j['active']")"
qi=0; while kill -0 "$qt_h1" 2>/dev/null && [ $qi -lt 50 ]; do qi=$((qi+1)); sleep 0.1; done
check "quiet: the keeper saw the release and let go" ended "$(tail -1 "$qt/hold1.out")"
qt_unproc "$qt_h1"
qt_wait_asserts PreventUserIdleDisplaySleep 0
check "quiet: the assertions are gone" "0 0" "$(qt_asserts PreventUserIdleSystemSleep) $(qt_asserts PreventUserIdleDisplaySleep)"
check "quiet: Eager would stop the server again" True "$(qt_tool auto locohost "$qt_P" --dry | json "j['act']")"
check "quiet: the held process was never signaled" 0 "$(kill -0 "$qt_s1" 2>/dev/null; echo $?)"

echo "-- the held process's exit ends it"
"$qt_sleeper" 600 & qt_s2=$!; procs="$procs $qt_s2"
(exec env MINMACS_HOME="$qt" "$DQ" hold "$qt_s2" "$qt_reason" 60 >"$qt/hold2.out" 2>"$qt/hold2.err") &
qt_h2=$!; procs="$procs $qt_h2"
qt_until "j['active'] and j['holders'][0]['pid'] == $qt_s2"
check "quiet: a second hold is active" 0 "$?"
qt_wait_asserts PreventUserIdleDisplaySleep 1
check "quiet: its assertions are there" "1 1" "$(qt_asserts PreventUserIdleSystemSleep) $(qt_asserts PreventUserIdleDisplaySleep)"
# Fix Everything presses still run: a manual stop of the fixture server goes through, and the run says why it may.
qt_tool auto locohost "$qt_P" --by manual >"$qt/manual.json" 2>"$qt/manual.err"
check "quiet: a stop the person asks for still runs" True "$(json "j['ran']" <"$qt/manual.json")"
"$PORT" gone "$qt_P" 50
check "quiet: and the server stopped" 1 "$("$PORT" listening "$qt_P"; echo $?)"
qt_unproc "$qt_srv"
kill "$qt_s2" 2>/dev/null; qt_unproc "$qt_s2"
qi=0; while kill -0 "$qt_h2" 2>/dev/null && [ $qi -lt 50 ]; do qi=$((qi+1)); sleep 0.1; done
check "quiet: the keeper let go when the process exited" ended "$(tail -1 "$qt/hold2.out")"
qt_unproc "$qt_h2"
check "quiet: no hold is active after the exit" False "$(qt_quiet "j['active']")"
qt_wait_asserts PreventUserIdleSystemSleep 0
check "quiet: and the assertions are gone" "0 0" "$(qt_asserts PreventUserIdleSystemSleep) $(qt_asserts PreventUserIdleDisplaySleep)"
check "quiet: the clean runs again once the hold ended" True "$(qt_tool auto noonoo "$qt_pip" | json "j['ran']")"

echo "-- the log"
qt_env MINMACS_COLD=1 "$BIN" log --json --limit 100 >"$qt/log.json" 2>"$qt/log.err"
check "quiet: log --json reads the test home" 0 "$?"
check "quiet: one entry per hold, from its start to its end" 2 \
  "$(json "len([e for e in j['entries'] if e['kind'] == 'quiet' and __import__('re').match(r'Quiet for $qt_reason \(pid [0-9]+\), [0-9]{2}:[0-9]{2} to [0-9]{2}:[0-9]{2}\.$', e['sentence'])])" <"$qt/log.json")"
check "quiet: who ended each" "from the command line|when its process ended" \
  "$(json "'|'.join(sorted(e['who'] for e in j['entries'] if e['kind'] == 'quiet'))" <"$qt/log.json")"
check "quiet: each hold has an undo record of kind quiet" 2 \
  "$(qt_tool cli restore --list --json 2>/dev/null | json "len([r for r in (j if isinstance(j, list) else j.get('records', [])) if r.get('kind') == 'quiet'])")"
check "quiet: holds.json is empty again" "{\"holds\":{}}" "$(tr -d ' \n' <"$qt/quiet/holds.json")"

echo "-- invariants in the source"
check "quiet: the check sits in the shared plan and run, not in an expert" "1 1" \
  "$(grep -c 'if (act && quiet)' Sources/Core/Act/MMAct.m) $(grep -c 'problem = \[@"kept: " stringByAppendingString:quiet\]' Sources/Core/Act/MMAct.m)"
check "quiet: no expert asks for quiet itself" 0 "$(grep -ln 'MMQuiet' Sources/Experts/*/*.m | grep -c .)"
check "quiet: it never signals" 0 "$(grep -nE 'kill\(|MMStop\(|MMQuitApps\(|terminate' Sources/Core/Store/MMQuiet.m | grep -c .)"
check "quiet: it never runs pmset" 0 "$(grep -n 'pmset' Sources/Core/Store/MMQuiet.m | grep -c .)"
kill "$qt_s1" 2>/dev/null; qt_unproc "$qt_s1"
# ===== end of quiet =====
