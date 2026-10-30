# Wrap Up of a finished workstream, issue #27. Sourced by test.sh after core.
# Fixtures only, all inside $MINMACS_HOME/wu<pid>: a repo with a bare origin, a worktree whose branch is merged and whose
# Claude Code session ended, a Python http.server on a high port this section picks, a helper left behind under a
# name unique to the run, an ignored .env, an untracked .env.local and a node_modules folder. A fixture browser is a
# process under a name unique to the run with a bundle id unique to the run, and its tabs live in a JSON file that the
# tool's fake tab bridge reads and changes, so no Apple event reaches a real browser. MINMACS_ROOTS and
# MINMACS_CLUTTER_ROOT point inside the fixture, so no real worktree, server or cache is read or touched.
# Items go to the real Trash, and every check that moves one restores it, so the Trash ends as it began.
# Cleanup stops only the pids this section started or restored, read from its own pid files and its own port.

wu=$(cd "$MINMACS_HOME" && pwd -P)/wu$$
wu_procs_before="$procs"                     # cleanup puts procs back to this once it stopped its own
mkdir -p "$wu/bin" "$wu/pids" "$wu/claude/projects" "$wu/codex" "$wu/root/home"
wu_top="$MINMACS_HOME"; wu_saved_claude="$CLAUDE_CONFIG_DIR"; wu_saved_codex="$CODEX_HOME"
# A support folder of its own, so this section's undo rows never reach another section's counts.
export MINMACS_HOME="$wu" CLAUDE_CONFIG_DIR="$wu/claude" CODEX_HOME="$wu/codex" GIT_CONFIG_NOSYSTEM=1
export MINMACS_ROOTS="$wu/code" MINMACS_CLUTTER_ROOT="$wu/root" MINMACS_CLUTTER_ROWS="$ROOT/registry/clutter"
export MINMACS_CLAUDE="$ROOT/test/review/fakeclaude.py" MINMACS_CODEX="$ROOT/test/review/fakecodex.py" RV_TEST_SENT="$wu/sent.json"

wu_src=$(find Sources -name '*.m' ! -path 'Sources/main.m' ! -path 'Sources/Shell/*' | LC_ALL=C sort)
# shellcheck disable=SC2086
clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -ISources -DMM_VERSION='"2.0.0"' -DMM_TESTS \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  $wu_src test/wrapup/tool.m -o "$wu/bin/tool" >"$wu/clang.log" 2>&1
check "wrapup: test/wrapup/tool.m builds" 0 "$?"
check "wrapup: Core and the experts have no warnings" 0 "$(grep -c 'warning:' "$wu/clang.log")"
WH="wuh$$"                                   # the helper's name, unique to this run
clang -Wall -mmacosx-version-min=14.0 test/wrapup/helper.c -o "$wu/bin/$WH" >"$wu/helper.log" 2>&1
check "wrapup: the helper fixture builds" 0 "$?"
WB="wub$$"                                   # the fixture browser's process name, unique to this run
clang -Wall -mmacosx-version-min=14.0 test/wrapup/helper.c -o "$wu/bin/$WB" >>"$wu/helper.log" 2>&1
check "wrapup: the fixture browser builds" 0 "$?"
T="$wu/bin/tool"
wu_has() { [ -e "$1" ] && echo yes || echo no; }
wu_listening() { nc -z 127.0.0.1 "$1" >/dev/null 2>&1 && echo yes || echo no; }
wu_alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null && echo yes || echo no; }
# Only our fixture port: its listener is the server this section started or restored.
wu_listener() { lsof -nP -t -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -1; }
wu_wait() { i=0; while [ $i -lt 100 ] && ! eval "$1"; do sleep 0.1; i=$((i+1)); done; }

echo "-- fixtures in $wu"
G() { git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
export GIT_AUTHOR_DATE="2026-01-01T12:00:00" GIT_COMMITTER_DATE="2026-01-01T12:00:00"
A="$wu/code/app"; W="$wu/code/app.worktrees"; F="$W/feat"
mkdir -p "$W"
G init -q --bare "$wu/origin.git"
G clone -q "$wu/origin.git" "$A" 2>/dev/null
( cd "$A" && printf 'node_modules/\n.env\n' >.gitignore && printf '{"name": "wu-app"}\n' >package.json && echo one >a.txt \
  && G add -A && G commit -qm first && G push -q origin main 2>/dev/null )
G -C "$A" worktree add -q -b feat "$F" main 2>/dev/null
( cd "$F" && echo two >b.txt && G add -A && G commit -qm "feat work" )
G -C "$A" merge -q --ff-only feat && G -C "$A" push -q origin main 2>/dev/null
WU_HEAD=$(G -C "$F" rev-parse HEAD)
printf 'DB_PASSWORD=wu-fixture\n' >"$F/.env"                      # ignored: saved to the recovery folder
printf 'API_URL=http://127.0.0.1\n' >"$F/.env.local"               # untracked config: to the Trash
mkdir -p "$F/node_modules/pkg" && printf 'module.exports = 1\n' >"$F/node_modules/pkg/index.js"
# notes: merged, its session ended, and an untracked file that is work. open: a branch that is not merged.
G -C "$A" worktree add -q -b notes "$W/notes" main 2>/dev/null; echo draft >"$W/notes/notes.txt"
G -C "$A" worktree add -q -b open "$W/open" main 2>/dev/null; ( cd "$W/open" && echo wip >c.txt && G add -A && G commit -qm "open work" )
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
for d in "$W"/*; do find "$d" -exec touch -h -t 202601010000 {} + 2>/dev/null; done
# A Claude Code session that ran in each worktree and ended two hours ago: a transcript, and no live status file.
wu_session() {
  S="$CLAUDE_CONFIG_DIR/projects/$(printf %s "$1" | tr '/.' '--')"; mkdir -p "$S"
  python3 - "$S/wu-$2-$$.jsonl" "$1" "$2" <<'PY'
import datetime, json, sys
t = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "timestamp": t, "cwd": sys.argv[2], "sessionId": "wu-" + sys.argv[3],
                        "message": {"role": "user", "content": "Finish the fixture work"}}) + "\n")
    f.write(json.dumps({"type": "ai-title", "aiTitle": "Fixture " + sys.argv[3], "sessionId": "wu-" + sys.argv[3]}) + "\n")
PY
}
for n in feat notes open; do wu_session "$W/$n" "$n"; done
# The server and the helper, detached, so launchd is their parent, as when the agent that started them ended.
P=$((41000 + $$ % 7000)); while [ "$(wu_listening "$P")" = yes ]; do P=$((P+1)); done
wu_serve() { ( cd "$F" && exec python3 -m http.server "$P" --bind 127.0.0.1 >/dev/null 2>&1 & echo $! >"$wu/pids/server-$1" ); }
wu_helper() { ( cd "$F" && exec "$wu/bin/$WH" "$wu/pids/helper-$1" ${2:-} >/dev/null 2>&1 & ); wu_wait "[ -s '$wu/pids/helper-$1' ]"; }
wu_serve 1; wu_helper 1
procs="$procs $(cat "$wu/pids/server-1") $(cat "$wu/pids/helper-1")"
wu_wait '[ "$(wu_listening "$P")" = yes ]'
check "wrapup: the fixture server listens on :$P" yes "$(wu_listening "$P")"
WU_SERVER=$(cat "$wu/pids/server-1"); WU_HELPER=$(cat "$wu/pids/helper-1")
# The fixture browser runs outside the worktree, so it is no helper of it. Q is a port no part stops.
( cd "$wu" && exec "$wu/bin/$WB" "$wu/pids/browser" >/dev/null 2>&1 & ); wu_wait "[ -s '$wu/pids/browser' ]"
WU_BROWSER_PID=$(cat "$wu/pids/browser"); procs="$procs $WU_BROWSER_PID"
Q=$((P + 1)); while [ "$(wu_listening "$Q")" = yes ]; do Q=$((Q+1)); done
export WU_BROWSER="no.guerrilla.minmacs.wub$$.browser" WU_BROWSER_PID WU_TABS="$wu/tabs.json"
wu_tabs_file() {
  cat >"$WU_TABS" <<EOF
{"tabs": [
 {"pid": $WU_BROWSER_PID, "window": 1, "id": 11, "url": "http://localhost:$P/", "title": "App"},
 {"pid": $WU_BROWSER_PID, "window": 1, "id": 12, "url": "http://127.0.0.1:$P/docs", "title": "Docs"},
 {"pid": $WU_BROWSER_PID, "window": 1, "id": 13, "url": "http://[::1]:$P/admin", "title": "Admin"},
 {"pid": $WU_BROWSER_PID, "window": 1, "id": 14, "url": "http://localhost:$Q/", "title": "Another server"},
 {"pid": $WU_BROWSER_PID, "window": 1, "id": 15, "url": "https://example.org/", "title": "Elsewhere"},
 {"pid": $WU_BROWSER_PID, "window": 2, "id": 21, "url": "http://localhost:$P/private", "title": "Private", "mode": "incognito"}
], "closed": [], "opened": [], "reads": [], "denied": $1}
EOF
}
wu_tabs_file false
wu_tab() { python3 -c "import json,sys; j=json.load(open(sys.argv[1])); print($1)" "$WU_TABS"; }

echo "-- what Wrap Up would do"
[ -n "${WU_DEBUG:-}" ] && "$T" verb clutter list --json | head -60
J=$("$T" verb work wrap-up "$F" --dry-run --json); r=$?
check "wrapup: the dry run exits 0" 0 "$r"
check "wrapup: a merged worktree whose session ended is ready" True "$(echo "$J" | json "j['ready']")"
check "wrapup: a browser on no list in the rules gets no tabs part" "servers helpers caches config worktree" \
  "$(echo "$J" | json "' '.join(p['step'] for p in j['parts'])")"
"$T" verb apps keep "$WU_BROWSER" >/dev/null 2>&1
check "wrapup: a browser on the keep list gets no tabs part" "servers helpers caches config worktree" \
  "$("$T" verb work wrap-up "$F" --dry-run --json | json "' '.join(p['step'] for p in j['parts'])")"
"$T" verb apps close "$WU_BROWSER" >/dev/null 2>&1
check "wrapup: the fixture browser is on the close list now" close \
  "$(python3 -c "import json,sys; j=json.load(open(sys.argv[1])); print('close' if sys.argv[2] in j['close'] else 'not')" "$wu/minmacs/rules.json" "$WU_BROWSER")"
J=$("$T" verb work wrap-up "$F" --dry-run --json)
check "wrapup: the parts run servers, helpers, tabs, caches, config, worktree" "servers helpers tabs caches config worktree" \
  "$(echo "$J" | json "' '.join(p['step'] for p in j['parts'])")"
check "wrapup: each expert owns its part" "locohost minmacs minmacs noonoo workforest workforest" "$(echo "$J" | json "' '.join(p['expert'] for p in j['parts'])")"
check "wrapup: the tabs part names the count and the browser" "Close 3 localhost tabs in Fixture Browser" "$(echo "$J" | json "j['parts'][2]['title']")"
check "wrapup: its dry run names the port and keeps the browser running" yes \
  "$(echo "$J" | json "'yes' if ':$P' in j['parts'][2]['dryRun'] and 'keep Fixture Browser running' in j['parts'][2]['dryRun'] else j['parts'][2]['dryRun']")"
check "wrapup: the dry run closes no tab" "6 0" "$(wu_tab "len(j['tabs']), len(j['closed'])" | tr -d '(),')"
check "wrapup: the server part names the fixture port" yes "$(echo "$J" | json "'yes' if ':$P' in j['parts'][0]['title'] else j['parts'][0]['title']")"
check "wrapup: the helper part is the fixture helper" yes "$(echo "$J" | json "'yes' if '$WH' in j['parts'][1]['title'] else j['parts'][1]['title']")"
check "wrapup: the config part names .env.local" yes "$(echo "$J" | json "'yes' if '.env.local' in j['parts'][4]['dryRun'] else j['parts'][4]['dryRun']")"
check "wrapup: every part says what it would do" 0 "$(echo "$J" | json "sum(1 for p in j['parts'] if not p['dryRun'])")"
check "wrapup: the dry run changes nothing" "yes yes yes yes" \
  "$(wu_listening "$P") $(wu_alive "$WU_HELPER") $(wu_has "$F/node_modules") $(wu_has "$F/.env.local")"
check "wrapup: the text dry run says so" yes "$("$T" verb work wrap-up "$F" --dry-run | tail -1 | grep -q '^Dry run. Nothing was changed.$' && echo yes || echo no)"
J=$("$T" verb work wrap-up "workforest:worktree:$F" --dry-run --json)
check "wrapup: a WorkForest finding id names the same workstream" True "$(echo "$J" | json "j['ready']")"
J=$("$T" verb work wrap-up "$W/open" --dry-run --json); r=$?
check "wrapup: an unmerged branch cannot wrap up, exit 1" "1 its branch is not merged" "$r $(echo "$J" | json "j['whyNot']")"
J=$("$T" verb work wrap-up "$W/notes" --dry-run --json); r=$?
check "wrapup: an untracked file that is work keeps the worktree" "1 yes" \
  "$(echo "$r") $(echo "$J" | json "'yes' if 'notes.txt' in (j['whyNot'] or '') else j['whyNot']")"
J=$("$T" verb work wrap-up "$A" --dry-run --json)
check "wrapup: a main checkout never wraps up" "a main checkout is never wrapped up" "$(echo "$J" | json "j['whyNot']")"
MINMACS_COLD=1 "$BIN" work wrap-up "$F" >/dev/null 2>&1; r=$?
check "wrapup: with no app the minmacs binary refuses to act, exit 3" "3 yes yes" "$r $(wu_listening "$P") $(wu_has "$F")"
check "wrapup: minmacs help lists work wrap-up" yes "$("$BIN" help 2>/dev/null | grep -q 'work wrap-up <id> \[--dry-run\] \[--json\]' && echo yes || echo no)"

echo "-- the card"
C=$("$T" card "$F")
check "wrapup: the merged worktree's card offers Wrap Up…" yes "$(echo "$C" | json "'yes' if any(a['title'] == 'Wrap Up…' for a in j['actions']) else [a['title'] for a in j['actions']]")"
check "wrapup: its gray tail counts the server and the size" yes "$(echo "$C" | json "'yes' if [a['tail'] for a in j['actions'] if a['title'] == 'Wrap Up…'][0].startswith('1 server, ') else j")"
check "wrapup: Wrap Up sits among the card's first four actions" yes "$(echo "$C" | json "'yes' if [a['title'] for a in j['actions']][:4].count('Wrap Up…') == 1 else j")"
check "wrapup: no Wrap Up when an untracked file is work" no "$("$T" card "$W/notes" | json "'yes' if any(a['title'] == 'Wrap Up…' for a in j['actions']) else 'no'")"
check "wrapup: no Wrap Up on an unmerged branch" no "$("$T" card "$W/open" | json "'yes' if any(a['title'] == 'Wrap Up…' for a in j['actions']) else 'no'")"

echo "-- the tabs part on main, as a menu builds the plan"
wu_tabs_file true
J=$("$T" plan "$F" 3)
check "wrapup: on main with no read kept, the plan has no tabs part" no "$(echo "$J" | json "'yes' if any(p.startswith('tabs') for p in j[0]) else 'no'")"
check "wrapup: a browser that would prompt is never read in the background" "no 0" \
  "$(echo "$J" | json "'yes' if any(p.startswith('tabs') for p in j[2]) else 'no'") $(wu_tab "len(j['reads'])")"
wu_tabs_file false
J=$("$T" plan "$F" 3)
check "wrapup: one the person allowed is read in the background, and the next plan shows it" yes \
  "$(echo "$J" | json "'yes' if 'tabs Close 3 localhost tabs in Fixture Browser' in j[2] else j")"

echo "-- Wrap Up runs as one step"
WU_MOVE_URL="http://[::1]:$P/admin" "$T" verb work wrap-up "$F" --json >"$wu/run.json"; r=$?
J=$(cat "$wu/run.json")
check "wrapup: it exits 0" 0 "$r"
check "wrapup: the record is done" done "$(echo "$J" | json "j['state']")"
RID=$(echo "$J" | json "j['rid']")
check "wrapup: one part record per part, all done" "6 done done done done done done" \
  "$(echo "$J" | json "' '.join([str(len(j['records']))] + [x['state'] for x in j['records']])")"
check "wrapup: the server stopped" no "$(wu_listening "$P")"
check "wrapup: the helper stopped" no "$(wu_alive "$WU_HELPER")"
check "wrapup: the worktree is gone" no "$(wu_has "$F")"
check "wrapup: the two localhost tabs on :$P closed" "http://localhost:$P/ http://127.0.0.1:$P/docs" "$(wu_tab "' '.join(j['closed'])")"
check "wrapup: a tab that moved on since the read stays open" yes "$(wu_tab "'yes' if any(t['id'] == 13 and 'moved' in t['url'] for t in j['tabs']) else j['tabs']")"
check "wrapup: a tab on a port no part stops stays open" yes "$(wu_tab "'yes' if any(t['id'] == 14 for t in j['tabs']) else 'no'")"
check "wrapup: a tab on another host stays open" yes "$(wu_tab "'yes' if any(t['id'] == 15 for t in j['tabs']) else 'no'")"
check "wrapup: a private window's tab is never closed" yes "$(wu_tab "'yes' if any(t['id'] == 21 for t in j['tabs']) and not any('private' in u for u in j['closed']) else 'no'")"
check "wrapup: the browser still runs" yes "$(wu_alive "$WU_BROWSER_PID")"
G -C "$A" rev-parse --verify -q feat >/dev/null; check "wrapup: the merged branch is deleted with -d" 1 "$?"
check "wrapup: git no longer lists it" no "$(G -C "$A" worktree list | grep -q "$F" && echo yes || echo no)"
U=$(python3 - "$wu/minmacs.sqlite" "$RID" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1])
rows = [json.loads(b) for (b,) in c.execute("select body from rows where tbl='undo' order by rowid")]
latest = {}
for b in rows: latest[b['rid']] = b
parts = sorted([b for b in latest.values() if b.get('parentRid') == sys.argv[2]], key=lambda b: b['payload'].get('part', -1))
out = {'parent': latest[sys.argv[2]], 'parts': parts}
print(json.dumps(out))
PY
)
check "wrapup: the parts are numbered in the order they ran" "0 1 2 3 4 5" "$(echo "$U" | json "' '.join(str(p['payload']['part']) for p in j['parts'])")"
check "wrapup: the server part keeps its restart command" yes "$(echo "$U" | json "'yes' if 'http.server' in j['parts'][0]['payload']['restart']['command'] else j['parts'][0]['payload']")"
check "wrapup: the tabs record is kind tabs and keeps the two closed URLs to reopen" "tabs http://localhost:$P/ http://127.0.0.1:$P/docs" \
  "$(echo "$U" | json "' '.join([j['parts'][2]['kind']] + j['parts'][2]['payload']['reopen']['urls'])")"
check "wrapup: it reopens in the browser it came from, after the other parts" "$WU_BROWSER True" \
  "$(echo "$U" | json "j['parts'][2]['payload']['reopen']['bundleID'] + ' ' + str(j['parts'][2]['payload']['restoreLast'])")"
check "wrapup: node_modules went to the Trash" yes "$(echo "$U" | json "'yes' if any(t['from'].endswith('/feat/node_modules') for t in j['parts'][3]['payload'].get('trashed', [])) else j['parts'][3]['payload']")"
check "wrapup: .env.local went to the Trash" yes "$(echo "$U" | json "'yes' if any(t['from'].endswith('/feat/.env.local') for t in j['parts'][4]['payload'].get('trashed', [])) else j['parts'][4]['payload']")"
check "wrapup: .env was saved before the worktree went" True "$(echo "$U" | json "'.env' in j['parts'][5]['payload']['recovery']['saved']")"
check "wrapup: the record lists its parts" 6 "$(echo "$U" | json "len(j['parent']['payload']['parts'])")"
check "wrapup: the restore list shows one record for the whole step" "$RID" \
  "$("$T" verb restore --list --json | json "[r['rid'] for r in j['records'] if r['kind'] == 'wrapup'][0]")"

echo "-- one restore takes it all back, in reverse order"
J=$("$T" verb restore "$RID" --json); r=$?
check "wrapup: restore exits 0" 0 "$r"
check "wrapup: restore says restored" True "$(echo "$J" | json "j['restored'][0]['restored']")"
check "wrapup: the worktree is back at its commit" "$WU_HEAD" "$(G -C "$F" rev-parse HEAD 2>/dev/null)"
check "wrapup: on its branch again" feat "$(G -C "$F" symbolic-ref --short HEAD 2>/dev/null)"
check "wrapup: with .env" "DB_PASSWORD=wu-fixture" "$(cat "$F/.env" 2>/dev/null)"
check "wrapup: with .env.local" "API_URL=http://127.0.0.1" "$(cat "$F/.env.local" 2>/dev/null)"
check "wrapup: with node_modules" "module.exports = 1" "$(cat "$F/node_modules/pkg/index.js" 2>/dev/null)"
wu_wait '[ "$(wu_listening "$P")" = yes ]'
check "wrapup: the server listens again" yes "$(wu_listening "$P")"
WU_SERVER2=$(wu_listener "$P"); [ -n "$WU_SERVER2" ] && procs="$procs $WU_SERVER2"
wu_wait "[ -s '$wu/pids/helper-1' ] && [ \"\$(cat '$wu/pids/helper-1')\" != '$WU_HELPER' ]"
WU_HELPER2=$(cat "$wu/pids/helper-1"); procs="$procs $WU_HELPER2"
check "wrapup: the helper runs again" "yes yes" "$([ "$WU_HELPER2" != "$WU_HELPER" ] && echo yes || echo no) $(wu_alive "$WU_HELPER2")"
check "wrapup: the helper runs in the worktree again" yes "$(lsof -a -p "$WU_HELPER2" -d cwd -Fn 2>/dev/null | grep -q "^n$F$" && echo yes || echo no)"
R=$(python3 - "$wu/minmacs.sqlite" "$RID" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1])
latest = {}
for (b,) in c.execute("select body from rows where tbl='undo' order by rowid"):
    b = json.loads(b); latest[b['rid']] = b
parts = sorted([b for b in latest.values() if b.get('parentRid') == sys.argv[2]], key=lambda b: b['payload']['part'])
print(' '.join([latest[sys.argv[2]]['state']] + [b['state'] for b in parts]))
# The order restore ran in: the time each part was marked restored, newest part first, and the tabs part last.
rest = [b for b in parts if b['kind'] != 'tabs']; tabs = [b for b in parts if b['kind'] == 'tabs']
at = [b['payload']['restored']['restoredAt'] for b in rest]
last = bool(tabs) and tabs[0]['payload']['restored']['restoredAt'] >= max(at)
print('reverse' if at == sorted(at, reverse=True) else 'not reverse', 'last' if last else 'not last')
print(min(at))
PY
)
check "wrapup: the record and every part say restored" "restored restored restored restored restored restored restored" "$(echo "$R" | head -1)"
check "wrapup: the parts came back newest first, the tabs after the servers" "reverse last" "$(echo "$R" | sed -n 2p)"
check "wrapup: the closed tabs reopened in their browser" "http://localhost:$P/ http://127.0.0.1:$P/docs|$WU_BROWSER" \
  "$(wu_tab "' '.join(o['url'] for o in j['opened']) + '|' + ' '.join(sorted(set(o['bundleID'] for o in j['opened'])))")"
check "wrapup: they reopened once the server part was back" yes \
  "$(wu_tab "'yes' if j['opened'] and min(o['at'] for o in j['opened']) >= $(echo "$R" | sed -n 3p) else j['opened']")"
check "wrapup: and the server listened when they opened" yes "$(wu_listening "$P")"
"$T" verb restore "$RID" >/dev/null 2>&1; check "wrapup: a second restore is refused, exit 1" 1 "$?"

echo "-- a part that fails stops the rest, and the record says which"
for f in "$F" "$F/node_modules" "$F/.env.local"; do touch -h -t 202601010000 "$f"; done
wu_helper 2 stubborn; WU_STUB=$(cat "$wu/pids/helper-2"); procs="$procs $WU_STUB"
J=$("$T" verb work wrap-up "$F" --json); r=$?
check "wrapup: a stubborn helper fails the run, exit 1" "1 failed" "$r $(echo "$J" | json "j['state']")"
check "wrapup: the record names the helper part" "helpers yes" \
  "$(echo "$J" | json "j['failedPart']['step'] + (' yes' if '$WH' in j['failedPart']['title'] else ' ' + j['failedPart']['title'])")"
check "wrapup: and says the rest did not run" yes "$(echo "$J" | json "'yes' if 'did not run' in j['error'] else j['error']")"
check "wrapup: the server part before it ran" no "$(wu_listening "$P")"
check "wrapup: the caches, config and worktree stay" "yes yes yes" "$(wu_has "$F/node_modules") $(wu_has "$F/.env.local") $(wu_has "$F")"
RID2=$(echo "$J" | json "j['rid']")
"$T" verb restore "$RID2" >/dev/null 2>&1; check "wrapup: restore takes back the parts that ran" 0 "$?"
wu_wait '[ "$(wu_listening "$P")" = yes ]'
check "wrapup: the server listens again" yes "$(wu_listening "$P")"
x=$(wu_listener "$P"); [ -n "$x" ] && procs="$procs $x"
for f in "$wu"/pids/helper-*; do x=$(cat "$f" 2>/dev/null); [ -n "$x" ] && procs="$procs $x"; done

echo "-- the invariants"
check "wrapup: the experts run no git and no process for it" 0 \
  "$(grep -nE 'NSTask|/usr/bin/git|MMRun\(|MMRunTask|MMGit\(|popen|system\(|kill\(' Sources/Experts/MinMacs/MMMinMacsWrapUp.m | grep -c .)"
check "wrapup: no part deletes for good or forces git" 0 \
  "$(grep -nE 'removeItemAt|unlink\(|rmdir\(|--force|emptyTrash' Sources/Core/Act/MMWrapUp.m Sources/Experts/MinMacs/MMMinMacsWrapUp.m | grep -c .)"
check "wrapup: Core runs every part through MMRunActionPart" 1 "$(grep -c 'MMRunActionPart(p.action' Sources/Core/Act/MMWrapUp.m)"

# Stop what this section started or restored, and nothing else. Wrap Up stopped some of these pids minutes ago,
# and the Mac may have given a pid to another process since, so each pid is signaled only while it still runs a
# fixture command: the helper under its run-unique name, or the http.server on this section's port.
wu_ours() {
  c=$(ps -o command= -p "$1" 2>/dev/null)
  case "$c" in "$wu/bin/$WH "*|"$wu/bin/$WB "*|*"http.server $P --bind 127.0.0.1"*) return 0 ;; esac
  return 1
}
check "wrapup: a pid that runs no fixture command is never ours" no "$(wu_ours $$ && echo yes || echo no)"
for x in $(cat "$wu"/pids/* 2>/dev/null) $(wu_listener "$P"); do wu_ours "$x" && kill -9 "$x" 2>/dev/null; done
# The pids this section added to procs are stopped or gone, so the harness's cleanup never signals a reused one.
procs="$wu_procs_before"
unset MINMACS_ROOTS MINMACS_CLUTTER_ROOT MINMACS_CLUTTER_ROWS MINMACS_CLAUDE MINMACS_CODEX RV_TEST_SENT GIT_CONFIG_NOSYSTEM \
  WU_BROWSER WU_BROWSER_PID WU_TABS
export CLAUDE_CONFIG_DIR="$wu_saved_claude" CODEX_HOME="$wu_saved_codex" MINMACS_HOME="$wu_top"
