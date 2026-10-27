# Issue #15: Core Know. The registry, sessions, Where, MMRun and the fact cache. Sourced by test.sh.
# Fixtures only: fake agents from tools/fakeagent.c, fake session files and a fake Codex home under the agent homes
# test.sh sets, a fake pi home, and fake cmux and tmux CLIs. Every pid this section starts goes in procs.
# test/know/knowtool.m links all of Sources/Core, so every sample comes from the real Senses pass.

K="$MINMACS_HOME/know"
mkdir -p "$K/bin" "$K/proj/sub" "$CLAUDE_CONFIG_DIR/sessions" "$CLAUDE_CONFIG_DIR/projects/fixture" "$CODEX_HOME"
K=$(cd "$K" && pwd -P)
KT="$K/knowtool"
clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -DMM_TESTS -ISources \
  $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/know/*.m -framework Cocoa -framework IOKit -framework UserNotifications \
  -lsqlite3 -o "$KT" >"$K/clang.log" 2>&1
check "the Know tool builds" 0 "$?"
check "the Know sources have no warnings under -Wextra" 0 "$(grep -c 'warning:' "$K/clang.log")"
# The fixtures run under names of their own, so nothing else that looks for a fakeagent can reach them.
# Other runs on this Mac start fake agents too, so the names carry this run's pid and stay under 16 characters.
KA="mmka$$"; KH="mmkh$$"
clang -O1 tools/fakeagent.c -o "$K/bin/$KA" && clang -O1 tools/fakehost.c -o "$K/bin/$KH"
check "the fake agent and host build" 0 "$?"
cp "$K/bin/$KA" "$K/bin/codex"
FAKE="$K/bin/$KA"; FHOST="$K/bin/$KH"
# The fixture rows of tools/fixtures and test/know/rows, with the process names changed to match.
python3 - "$K/rows" "$KA" "$KH" <<'PYEOF'
import glob, os, sys
for src in glob.glob("tools/fixtures/*.json") + glob.glob("tools/fixtures/*/*.json") + glob.glob("test/know/rows/*/*.json"):
    rel = os.path.relpath(src, "tools/fixtures") if src.startswith("tools/") else os.path.relpath(src, "test/know/rows")
    dst = os.path.join(sys.argv[1], rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, "w").write(open(src).read().replace('"fakeagent"', '"%s"' % sys.argv[2]).replace('"fakehost"', '"%s"' % sys.argv[3]))
PYEOF
R="$K/rows"
check "the renamed fixture rows pass the validator" 0 "$(python3 tools/validate_row.py "$R"/*.json "$R"/*/*.json >/dev/null; echo $?)"

# Starts a fixture in the background and adds its pid to procs. The pid lands in $LAST.
start() { "$@" & LAST=$!; procs="$procs $LAST"; }
stop() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }
# The state, signal or why of one pid in `knowtool agents` output.
of() { python3 -c "import json,sys; a=[x for x in json.load(sys.stdin)['agents'] if x['pid']==int(sys.argv[1])]; print(a[0]['$2'] if a else 'absent')" "$1"; }
# Claude Code writes procStart in UTC, so the fixture does too.
pstart() { LC_ALL=C TZ=UTC ps -o lstart= -p "$1" | sed 's/^ *//;s/  */ /g'; }
statusfile() { # pid status [procStart]
  printf '{"pid":%s,"sessionId":"sess-%s","cwd":"%s","startedAt":%s000,"procStart":"%s","version":"2.1.311","kind":"interactive","status":"%s","statusUpdatedAt":%s000}\n' \
    "$1" "$1" "$K/proj" "$(date +%s)" "${3:-$(pstart "$1")}" "$2" "$(date +%s)" >"$CLAUDE_CONFIG_DIR/sessions/$1.json"
}

echo "-- registry rows"
bundled="$APP/Contents/Resources/registry/agents"
valid=0; for r in registry/agents/*.json; do python3 tools/validate_row.py "$r" >/dev/null 2>&1 && valid=$((valid+1)); done
check "the bundle ships every row the validator passes" "$valid" "$(ls "$bundled" | wc -l | tr -d ' ')"
check "MMRegistry loads every bundled row" "$valid" "$("$KT" rows "$bundled" | json "j['count']")"
mkdir -p "$K/userrows"
python3 -c "import json,sys; r=json.load(open(sys.argv[1])); r['name']='Claude Code, user row'; json.dump(r, open(sys.argv[2],'w'))" \
  registry/agents/claude-code.json "$K/userrows/claude-code.json"
check "a user row replaces the bundled row with its id" "claude-code=Claude Code, user row" \
  "$("$KT" rows "$bundled" "$K/userrows" | json "[x for x in j['rows'] if x.startswith('claude-code=')][0]")"
norm() { python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$1"; }
MH=$(norm "$MINMACS_HOME")
check "the user's rows are read from the support folder" "$MH/registry/agents" "$("$KT" rows | json "__import__('os').path.normpath(j['defaults'][-1])")"
echo '{"id": "broken"' >"$K/userrows/broken.json"
check "a broken row file is skipped" "$((valid))" "$("$KT" rows "$bundled" "$K/userrows" | json "j['count']")"

echo "-- working, waiting and idle signals per row, against tools/agents_probe.py"
state() { "$KT" agents --rows "$1" | of "$2" state; }
ref() { python3 tools/agents_probe.py --json --rows "$1" | of "$2" state; }
both() { check "$1" "$2" "$(state "$3" "$4")"; check "  the reference probe agrees" "$2" "$(ref "$3" "$4")"; }
start "$FAKE" --work 8; FA=$LAST; sleep 1
both "a fake agent mid-turn is working" working "$R" "$FA"
check "  its signal is the caffeinate child" caffeinate "$("$KT" agents --rows "$R" | of "$FA" signal)"
sleep 9
both "the fake agent after its turn is idle" idle "$R" "$FA"
check "  with no signal" none "$("$KT" agents --rows "$R" | of "$FA" signal)"
stop "$FA"
check "a fake agent that is gone is not found" absent "$(state "$R" "$FA")"
start "$FAKE"; FA=$LAST; sleep 1
both "presence: a missing path keeps a bare-name match out" absent "$R/presence-missing" "$FA"
both "presence: an existing path lets it through" idle "$R/presence-here" "$FA"
both "no_outside_signal: no signal reads unknown" unknown "$R/unknown" "$FA"
stop "$FA"
start "$FAKE" --work 8 --w self; FA=$LAST; sleep 1
both "caffeinate -w with its own pid counts" working "$R/watch" "$FA"
stop "$FA"
start "$FAKE" --work 8 --w other; FA=$LAST; sleep 1
both "caffeinate -w with another pid does not" idle "$R/watch" "$FA"
stop "$FA"
start "$FHOST" "$FAKE" --work 8; FH=$LAST; sleep 1
FHA=$(pgrep -P "$FH" "$KA"); procs="$procs $FHA"
both "an agent under a host is reported once, as the host" working "$R/host" "$FH"
check "  the host lists the agent it hosts" "fake-agent:working" \
  "$("$KT" agents --rows "$R/host" | python3 -c "import json,sys; a=[x for x in json.load(sys.stdin)['agents'] if x['pid']==$FH][0]; print(','.join('%s:%s' % (h['id'], h['state']) for h in a.get('hosted', [])))")"
check "  and the hosted agent is not listed apart" 1 "$("$KT" agents --rows "$R/host" | json "len([a for a in j['agents'] if a['id'].startswith('fake')])")"
sleep 9
both "the host after the hosted turn ended is idle" idle "$R/host" "$FH"
stop "$FH"; stop "$FHA"
start "$FAKE"; FA=$LAST; sleep 1

echo "-- the status file ranks first, TESTS.md question 9"
cpu() { "$KT" agents --rows "$R/cpu" | of "$FA" "$1"; }
check "with no status file the tree CPU signal fires" tree_cpu "$(cpu signal)"
statusfile "$FA" idle
check "status idle with tree CPU over the floor comes out idle" idle "$(cpu state)"
check "  and the status file decided it" status_file "$(cpu signal)"
statusfile "$FA" busy;    check "status busy is working" working "$(cpu state)"
statusfile "$FA" busy "$(LC_ALL=C ps -o lstart= -p "$FA" | sed 's/^ *//;s/  */ /g')"
check "a procStart in local time is read too" status_file "$(cpu signal)"
statusfile "$FA" waiting; check "status waiting is waiting" waiting "$(cpu state)"
statusfile "$FA" shell;   check "status shell is idle with a background shell" "idle:status file shell: idle with a background shell" "$(cpu state):$(cpu why)"
statusfile "$FA" thinking; check "an unknown status word is unknown" unknown "$(cpu state)"
statusfile "$FA" idle "Thu Jan  1 01:00:00 2015"
check "a status file whose procStart is another process is ignored" tree_cpu "$(cpu signal)"
check "the session takes its id from the status file" "sess-$FA" "$(statusfile "$FA" busy; cpu session)"
rm -f "$CLAUDE_CONFIG_DIR/sessions/$FA.json"

echo "-- sessions"
TS=$(date -u -v-10M +%Y-%m-%dT%H:%M:%S.000Z)
printf '{"type":"user","cwd":"%s","gitBranch":"fixture-branch","timestamp":"%s","message":{"role":"user","content":"hi"}}\n{"type":"ai-title","aiTitle":"Fixture \\"title\\""}\n' \
  "$K/proj" "$TS" >"$CLAUDE_CONFIG_DIR/projects/fixture/sess-transcript.jsonl"
statusfile "$FA" busy
printf '{"pid":999999,"sessionId":"sess-dead","cwd":"/nowhere","startedAt":1,"procStart":"Thu Jan  1 01:00:00 2015","status":"busy"}\n' >"$CLAUDE_CONFIG_DIR/sessions/999999.json"
mkdir -p "$K/pi/sessions/--fixture--"
printf '{"type":"session","version":3,"id":"pi-uuid-1","timestamp":"%s","cwd":"%s"}\n' "$TS" "$K/proj/sub" >"$K/pi/sessions/--fixture--/2026-10-27T10-00-00-000Z_pi-uuid-1.jsonl"
python3 test/know/codexdb.py "$CODEX_HOME" "$K/proj" completed
export PI_CODING_AGENT_DIR="$K/pi"
S=$("$KT" sessions --pid "$FA" --id sess-transcript --latest-in "$K/proj/sub" --open-at "$(date +%s)" --folders "$K/proj")
sj() { printf '%s' "$S" | json "$1"; }
check "a transcript gives the session, cwd, branch and title" "claude-code|$K/proj|fixture-branch|Fixture \"title\"" \
  "$(sj "'|'.join([j['withID'][k] for k in ('agent','cwd','branch','title')])")"
check "forPid finds the live status file" "sess-$FA|busy|True" "$(sj "'|'.join(str(j['forPid'][k]) for k in ('id','live','stillWorking'))")"
check "a status file whose pid is gone is not live" "0|None" "$(sj "'|'.join(str(x[k]) for x in j['all'] if x['id']=='sess-dead' for k in ('pid','live'))")"
check "the Codex thread is read with immutable=1 when there is no -shm file" "codex|Fixture thread|fixture-branch|completed" \
  "$(sj "'|'.join(str(x[k]) for x in j['all'] if x['id']=='thread-live' for k in ('agent','title','branch','live'))")"
check "  and the fixture left no -shm file" no "$([ -e "$CODEX_HOME/state_5.sqlite-shm" ] && echo yes || echo no)"
# A plain mode=ro open fails on such a file with the SQLite on this Mac (TESTS.md question 10), but works with the
# SQLite on the CI runner. The reader must work either way, so the check above is the one that counts.
check "an archived Codex thread is left out" 0 "$(sj "len([x for x in j['all'] if x['id']=='thread-old'])")"
check "only the fixture's Codex threads are read, from CODEX_HOME" 1 "$(sj "len([x for x in j['all'] if x['agent']=='codex'])")"
check "a pi session comes from PI_CODING_AGENT_DIR" "pi|$K/proj/sub" "$(sj "'|'.join(str(x[k]) for x in j['all'] if x['id']=='pi-uuid-1' for k in ('agent','cwd'))")"
check "latestIn finds the newest session inside a folder" pi-uuid-1 "$(sj "j['latestIn']['id']")"
check "openAt finds a session open now in the folder" "$K/proj" "$(sj "j['openAt']['cwd']")"
check "the sessions cache is kept in the support folder" yes "$([ -s "$MINMACS_HOME/sessions.json" ] && echo yes || echo no)"

echo "-- Codex turns, TESTS.md question 10"
stop "$FA"
( cd "$K/proj" && exec "$K/bin/codex" ) & CX=$!; procs="$procs $CX"; sleep 1
codexstate() { "$KT" agents --rows "$bundled" | of "$CX" "$1"; }
check "a fake codex process matches the codex row" codex "$(codexstate id)"
check "  newest turn completed: the row signals decide, and it is idle" idle "$(codexstate state)"
python3 test/know/codexdb.py "$CODEX_HOME" "$K/proj" inProgress
check "newest turn inProgress: working, from the Codex event signal" "working:event" "$(codexstate state):$(codexstate signal)"
python3 test/know/codexdb.py "$CODEX_HOME" "$K/proj" completed
python3 -u test/know/codexdb.py "$CODEX_HOME" --hold 20 inProgress >"$K/hold.out" & HOLD=$!; procs="$procs $HOLD"
for i in 1 2 3 4 5 6 7 8 9 10; do grep -q held "$K/hold.out" 2>/dev/null && break; sleep 0.3; done
check "while Codex holds the file the -shm file exists" yes "$([ -e "$CODEX_HOME/thread_history_1.sqlite-shm" ] && echo yes || echo no)"
check "  and mode=ro reads the live turn" "working:event" "$(codexstate state):$(codexstate signal)"
stop "$HOLD"; stop "$CX"

echo "-- cmux events, behind a flag, TESTS.md question 8 and research track E"
cp test/know/fake-cmux.sh "$K/cmux"; chmod +x "$K/cmux"
export MINMACS_CMUX="$K/cmux"
start "$FAKE"; FA=$LAST; sleep 1
SEQ=0
frame() { # name occurred_at
  SEQ=$((SEQ+1))
  printf '{"seq":%s,"name":"agent.hook.%s","category":"agent","source":"claude","occurred_at":"%s","payload":{"session_id":"cmux-sess","cwd":"%s","_ppid":%s,"tool_input":"SECRET","tool_name":"Bash"}}\n' \
    "$SEQ" "$1" "$2" "$K/proj" "$FA" >>"$K/cmux.frames"
}
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
: >"$K/cmux.frames"; frame UserPromptSubmit "$NOW"; frame PreToolUse "$NOW"
check "with the flag off nothing is read" "cmux events are off|0" "$("$KT" events 1 | json "j['reason']+'|'+str(len(j['events']))")"
export MINMACS_CMUX_EVENTS=1
E=$("$KT" events 2)
check "with the flag on the reader gets each agent event" "PreToolUse|claude-code|cmux-sess|$FA" \
  "$(printf '%s' "$E" | json "'|'.join(str(j['events'][-1][k]) for k in ('event','agent','session','ppid'))")"
check "  and keeps no tool input" 0 "$(printf '%s' "$E" | grep -c SECRET)"
check "the reader asks for the agent category with a cursor in the support folder" yes \
  "$(python3 -c "import os,sys; a=open(sys.argv[1]).read().split(); i=a.index('--cursor-file'); print('yes' if a[1:3]==['--category','agent'] and os.path.normpath(a[i+1])==sys.argv[2]+'/cmux.cursor' and '--reconnect' in a else a)" "$K/cmux.args" "$MH")"
ev() { "$KT" agents --rows "$R/cpu" --events 1.5 | of "$FA" "$1"; }
check "a tool event ranks above tree CPU: working" "working:event" "$(ev state):$(ev signal)"
frame Notification "$NOW"
check "a Notification event is waiting" waiting "$(ev state)"
frame Stop "$NOW"
check "a Stop event is idle, over the tree CPU signal" "idle:event" "$(ev state):$(ev signal)"
: >"$K/cmux.frames"; frame PreToolUse 2015-01-01T00:00:00Z
check "an event from before the process started is ignored" tree_cpu "$(ev signal)"
stop "$FA"
unset MINMACS_CMUX_EVENTS

echo "-- Where, ported from LocoHost's Where.m"
cp test/know/fake-tmux.sh "$K/tmux"; chmod +x "$K/tmux"
export MINMACS_TMUX="$K/tmux"
start "$FHOST" "$FAKE"; FH=$LAST; sleep 1
FA=$(pgrep -P "$FH" "$KA"); procs="$procs $FA"
printf '%s\t%%7\tfixture-session\t1\tfixture-window\t0\n' "$FH" >"$K/tmux.panes"
# cmux top --format tsv: three columns MinMacs does not read, then type, id, parent and title.
printf 'x\tx\tx\twindow\twindow:1 WIN-UUID\t\tMain\nx\tx\tx\tworkspace\tworkspace:1 WS-UUID\twindow:1 WIN-UUID\tProject\nx\tx\tx\tsurface\tsurface:2 SURF-UUID\tworkspace:1 WS-UUID\t\342\227\220 repo check\nx\tx\tx\tprocess\t%s\tsurface:2 SURF-UUID\tfakehost\n' "$FH" >"$K/cmux.top"
W=$("$KT" where "$FA")
check "a pane whose shell is above the pid is the tmux place" "tmux|%7|fixture-window" "$(printf '%s' "$W" | json "'|'.join(j['place'][k] for k in ('kind','target','tab'))")"
check "  tmux is asked before cmux" tmux "$(printf '%s' "$W" | json "j['place']['kind']")"
start "$FHOST" "$FAKE"; FH2=$LAST; sleep 1
FA2=$(pgrep -P "$FH2" "$KA"); procs="$procs $FA2"
printf '%s\t%%8\tfixture-session\t1\tfixture-window-2\t0\n' "$FH2" >>"$K/tmux.panes"
WP=$("$KT" where-prune "$FA2")
check "Where caches the place of a live pid" "tmux|True" "$(printf '%s' "$WP" | json "j['kind']+'|'+str(j['cachedBefore'])")"
check "  and drops it once that pid is gone" False "$(printf '%s' "$WP" | json "j['cachedAfter']")"
stop "$FH2"; stop "$FA2"
printf '%s\t%%7\tfixture-session\t1\tfixture-window\t0\n' "$FH" >"$K/tmux.panes"
: >"$K/tmux.panes"
W=$("$KT" where "$FA")
check "with no tmux pane the cmux tab is the place" "cmux|cmux, repo check|WS-UUID|SURF-UUID|WIN-UUID" \
  "$(printf '%s' "$W" | json "'|'.join(j['place'][k] for k in ('kind','label','workspace','surface','window'))")"
: >"$K/cmux.goto"
"$KT" goto "$FA" >/dev/null
check "Go to focuses the cmux tab through the cmux CLI" "focus-panel --panel SURF-UUID --workspace WS-UUID --window WIN-UUID" "$(tail -1 "$K/cmux.goto")"
check "where with wait NO returns the last answer, then a fresh one" "None|cmux" \
  "$("$KT" where-later "$FA" | json "str(j['first'])+'|'+j['later']['kind']")"
: >"$K/cmux.top"
check "outside tmux and cmux the place is a terminal tab or an app" yes \
  "$("$KT" where "$FA" | json "'yes' if j['place'] is None or j['place']['kind'] in ('terminal','iterm','app') else j['place']['kind']")"
stop "$FH"; stop "$FA"
check "a pid that is gone has no place" None "$("$KT" where "$FA" | json "j['place']")"
unset MINMACS_TMUX MINMACS_CMUX PI_CODING_AGENT_DIR

echo "-- MMRun and MMFactCache"
R=$("$KT" run)
rv() { printf '%s\n' "$R" | sed -n "s/^$1=//p"; }
check "MMRun returns output and status" "hello:0:1" "$(rv output):$(rv status):$(rv didRun)"
check "MMRun feeds stdin" "from stdin" "$(rv stdin)"
check "MMRun starts from a clean environment plus env" "unset added" "$(rv clean_env)"
check "MMRun returns stderr and the exit status" "err:3" "$(rv stderr):$(rv exit_status)"
check "MMRun runs in cwd" /usr "$(rv cwd)"
check "MMRun stops a child past its time limit" "1:-1:1" "$(rv timed_out):$(rv timed_out_status):$(rv stopped_within_2s)"
check "MMRun kills a child that ignores SIGTERM" 1 "$(rv term_ignored_killed_within_3s)"
check "MMRun survives a child that never reads its input" 0 "$(rv unread_input_status)"
check "MMRun returns when a grandchild holds the pipes past the limit" 1 "$(rv held_pipes_return_within_3s)"
check "MMRun reports a tool that did not run" "0:-1" "$(rv missing_didRun):$(rv missing_status)"
echo "-- MMSizer, TESTS.md question 11"
SZ="$K/sizes"; mkdir -p "$SZ/f" "$SZ/h" "$SZ/hout" "$SZ/p" "$SZ/q" "$SZ/q2"
head -c 65536 /dev/urandom >"$SZ/f/one"; cp -c "$SZ/f/one" "$SZ/f/clone"
head -c 65536 /dev/urandom >"$SZ/h/x"; ln "$SZ/h/x" "$SZ/hout/xlink"
head -c 65536 /dev/urandom >"$SZ/p/base"; cp -c "$SZ/p/base" "$SZ/p/part"
head -c 4096 /dev/urandom | dd of="$SZ/p/part" bs=4096 seek=3 conv=notrunc 2>/dev/null
head -c 65536 /dev/urandom >"$SZ/q/a"; cp -c "$SZ/q/a" "$SZ/q2/b"
sleep 0.2   # TESTS.md question 11: refcounts may lag a moment after a change
szq() { "$KT" sizer quick "$1" | json "'%d %d' % (j['allocated'], j['freed'])"; }
sze() { "$KT" sizer exact "$@" | json "j['freed']"; }
check "quick: a file and its full clone free one copy" "131072 65536" "$(szq "$SZ/f")"
check "exact: a file and its full clone free one copy" 65536 "$(sze "$SZ/f")"
check "quick: a hard link outside the walk keeps the inode" "65536 0" "$(szq "$SZ/h")"
check "exact: a hard link outside the roots keeps the inode" 0 "$(sze "$SZ/h")"
check "exact: with both links in the roots the inode is freed" 65536 "$(sze "$SZ/h" "$SZ/hout")"
check "quick: a clone whose twin is outside frees nothing" "65536 0" "$(szq "$SZ/q")"
check "exact: a clone whose twin is outside frees nothing" 0 "$(sze "$SZ/q")"
check "exact: a clone and its twin together free one copy" 65536 "$(sze "$SZ/q" "$SZ/q2")"
# APFS copies a changed stretch whole, 16 KB on this Mac, so d is read from the part and the rest is checked against it.
SZD=$(sze "$SZ/p/part")
check "exact: a partial clone alone frees only its changed stretch" yes "$([ "$SZD" -gt 0 ] && [ "$SZD" -lt 65536 ] && echo yes || echo "$SZD")"
check "exact: a partial clone and its base free the whole union" $((65536 + SZD)) "$(sze "$SZ/p")"
check "quick: the estimate counts the pair low, as question 11 found" $((2 * SZD)) "$(szq "$SZ/p" | cut -d' ' -f2)"
check "a missing root is one error" 1 "$("$KT" sizer quick "$SZ/none" | json "j['errors']")"

C=$("$KT" cache)
cv() { printf '%s\n' "$C" | sed -n "s/^$1=//p"; }
check "the fact cache computes with wait YES" v1 "$(cv wait_yes_computes)"
check "  a matching fingerprint is not computed again" v1 "$(cv same_fingerprint_is_cached)"
check "  a new fingerprint is computed again" "1:v2" "$(cv changed_reports_yes):$(cv new_fingerprint_recomputes)"
check "  wait NO returns nil, then fills in the background" "nil:v3" "$(cv wait_no_miss_returns_nil):$(cv wait_no_fills_in_background)"
check "  a stale read returns the old value now and the fresh one later" "v3:v4" "$(cv stale_read_returns_old_value):$(cv then_the_fresh_one)"
check "  forget drops keys that are gone" nil "$(cv forget_drops_dead_keys)"
check "  persist keeps values across instances" v2 "$(cv persist_survives_a_new_instance)"
check "  maxAge expires a value" second "$(cv max_age_expires)"
check "  the cache file is in the support folder" yes "$([ -s "$MINMACS_HOME/know-check.json" ] && echo yes || echo no)"
check "no Know check wrote outside MINMACS_HOME's support folder" no "$([ -e "$HOME/Library/Application Support/MinMacs/know-check.json" ] && echo yes || echo no)"
