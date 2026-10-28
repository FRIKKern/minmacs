# The open items of the wave 4 reviews. Sourced by test.sh after core.
# Builds test/polish/tool.m with every .m under Sources but main.m. The tool counts what main does through its own
# realpath and stat, which every call from Sources reaches first.
# Fixtures only, all inside $MINMACS_HOME/pl<pid>: a repo with a bare origin, a worktree whose branch is merged and
# whose Claude Code session ended, five more worktrees, one Python http.server in a folder of the merged worktree on a
# high port this section picks, and a folder with hard links for Investigate. MINMACS_ROOTS points inside the fixture.
# The server runs in a session of its own, and cleanup stops only its pid, read from its own pid file.

pl=$(cd "$MINMACS_HOME" && pwd -P)/pl$$
pl_procs_before="$procs"
mkdir -p "$pl/bin" "$pl/pids" "$pl/claude/projects" "$pl/codex" "$pl/render"
pl_top="$MINMACS_HOME"; pl_saved_claude="$CLAUDE_CONFIG_DIR"; pl_saved_codex="$CODEX_HOME"
export MINMACS_HOME="$pl" CLAUDE_CONFIG_DIR="$pl/claude" CODEX_HOME="$pl/codex" GIT_CONFIG_NOSYSTEM=1
export MINMACS_ROOTS="$pl/code" MINMACS_CLAUDE=/usr/bin/false MINMACS_CODEX=/usr/bin/false MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false

pl_src=$(find Sources -name '*.m' ! -path 'Sources/main.m' | LC_ALL=C sort)
# shellcheck disable=SC2086
clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -ISources -DMM_VERSION='"2.0.0"' \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  $pl_src test/polish/tool.m -o "$pl/bin/polish-$$" >"$pl/clang.log" 2>&1
check "polish: test/polish/tool.m builds" 0 "$?"
check "polish: the sources have no warnings" 0 "$(grep -c 'warning:' "$pl/clang.log")"
T="$pl/bin/polish-$$"

G() { git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
export GIT_AUTHOR_DATE="2026-01-01T12:00:00" GIT_COMMITTER_DATE="2026-01-01T12:00:00"
A="$pl/code/app"; W="$pl/code/app.worktrees"; F="$W/feat"
mkdir -p "$W"
G init -q --bare "$pl/origin.git"
G clone -q "$pl/origin.git" "$A" 2>/dev/null
( cd "$A" && printf 'node_modules/\n' >.gitignore && echo one >a.txt && G add -A && G commit -qm first && G push -q origin main 2>/dev/null )
G -C "$A" worktree add -q -b feat "$F" main 2>/dev/null
( cd "$F" && mkdir srv && echo two >srv/b.txt && G add -A && G commit -qm "feat work" )
G -C "$A" merge -q --ff-only feat && G -C "$A" push -q origin main 2>/dev/null
for n in one two three four five; do G -C "$A" worktree add -q -b "$n" "$W/$n" main 2>/dev/null; done
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
# Old file times everywhere, so no index entry is newer than its index and git status leaves each index as it is.
for d in "$A" "$W"/*; do find "$d" -name .git -prune -o -exec touch -h -t 202601010000 {} + 2>/dev/null; done
# A Claude Code session that ran in feat and ended two hours ago.
S="$CLAUDE_CONFIG_DIR/projects/$(printf %s "$F" | tr '/.' '--')"; mkdir -p "$S"
python3 - "$S/pl-$$.jsonl" "$F" <<'PY'
import datetime, json, sys
t = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "timestamp": t, "cwd": sys.argv[2], "sessionId": "pl-feat", "message": {"role": "user", "content": "Finish"}}) + "\n")
PY
# The server, in a session of its own, in the srv folder of feat. It writes its pid file itself.
PL_PY='import http.server, os, sys
os.setsid()
open(os.path.join(sys.argv[2], "server-%d" % os.getpid()), "w").close()
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), http.server.SimpleHTTPRequestHandler).serve_forever()'
P=$((43000 + $$ % 6000)); while nc -z 127.0.0.1 "$P" >/dev/null 2>&1; do P=$((P + 1)); done
( ( cd "$F/srv" && exec python3 -c "$PL_PY" "$P" "$pl/pids" "polish-fixture-$$" ) >/dev/null 2>&1 & )
i=0; while ! nc -z 127.0.0.1 "$P" >/dev/null 2>&1 && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
for f in "$pl"/pids/server-*; do [ -e "$f" ] && procs="$procs ${f##*server-}"; done
check "polish: the fixture server listens on :$P" yes "$(nc -z 127.0.0.1 "$P" >/dev/null 2>&1 && echo yes || echo no)"
# Every mode Idle and no scheduled review, so no watch below wakes a review or acts.
for e in locohost workforest noonoo minmacs; do MINMACS_COLD=1 "$BIN" mode "$e" idle >/dev/null 2>&1; done
python3 - "$pl/Preferences/no.guerrilla.minmacs.plist" <<'PY'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, "rb"))
d["locohost.reviewMinutes"] = 0; d["workforest.reviewMinutes"] = 0
plistlib.dump(d, open(p, "wb"))
PY

echo "-- main reads what the graph queue prepared"
"$T" main "$F" >"$pl/main.json" 2>"$pl/main.err"
check "polish: the main check runs" 0 "$?"
pm() { json "$1" <"$pl/main.json" 2>/dev/null; }
check "polish: with nothing prepared, main makes no Wrap Up plan" 0 "$(pm "j['bare']['plansOnMain']")"
check "polish: and resolves no server folder" 0 "$(pm "j['bare']['serverRealpathsOnMain']")"
check "polish: prepared off main, the plan is made there" yes "$(pm "'yes' if j['prepared']['plansOff'] > 0 else j['prepared']")"
check "polish: and main still makes none and resolves none" "0 0" "$(pm "'%d %d' % (j['prepared']['plansOnMain'], j['prepared']['serverRealpathsOnMain'])")"
check "polish: the card shows Wrap Up and its server from the prepared view" "True True" \
  "$(pm "'%s %s' % ('Wrap Up…' in j['prepared']['actions'], 'Servers' in j['prepared']['facts'] or 'Server' in j['prepared']['facts'])")"
check "polish: no watch reads the prefs file on main" "0 0 0" \
  "$(pm "' '.join(str(j['watchPrefReadsOnMain'][e]) for e in ('locohost', 'workforest', 'noonoo'))")"
check "polish: MinMacs's card sorts a running app" yes "$(pm "'yes' if len(j['sorts']) >= 3 else (j['app'], j['sorts'])")"
check "polish: no sort writes the rules file on main" 0 "$(pm "sum(1 for x in j['sorts'] if x['wroteOnMain'])")"
check "polish: every sort writes it on the act queue" yes "$(pm "'yes' if all(x['wroteOffMain'] for x in j['sorts']) else j['sorts']")"

echo "-- a link whose menu does not open leaves no focus"
"$T" focus >"$pl/focus.json" 2>"$pl/focus.err"
check "polish: the focus check runs" 0 "$?"
pf() { json "$1" <"$pl/focus.json" 2>/dev/null; }
check "polish: the focus is set while the click runs" locohost "$(pf "j['rightAfterNoMenu']")"
check "polish: no menu opened, so the focus clears" "''" "$(pf "repr(j['afterNoMenu'])")"
check "polish: an open menu keeps its focus until it closes" "workforest ''" "$(pf "j['whileOpen'] + ' ' + repr(j['afterClose'])")"
check "polish: a menu that opens a turn later keeps it" noonoo "$(pf "j['openedLater']")"

echo "-- fact rows and link rows at one pitch"
"$T" spacing "$F" "$pl/render" >"$pl/spacing.json" 2>"$pl/spacing.err"
check "polish: the spacing check runs" 0 "$?"
ps_() { json "$1" <"$pl/spacing.json" 2>/dev/null; }
check "polish: the card has facts and a link row" yes "$(ps_ "'yes' if j['links'] >= 1 and j['facts'] >= 3 else j")"
check "polish: every appearance has its rows measured" yes "$(ps_ "'yes' if len(j['pitches']) >= 2 and all(len(p) >= 2 for p in j['pitches'].values()) else j['pitches']")"
check "polish: every row is a native menu item's height apart, within 1.5 pt" yes \
  "$(ps_ "'yes' if all(abs(x - j['itemPitch']) <= 1.5 for p in j['pitches'].values() for x in p) else (j['itemPitch'], j['pitches'])")"
check "polish: the rows are evenly spaced, within 1.5 pt" yes "$(ps_ "'yes' if all(max(p) - min(p) <= 1.5 for p in j['pitches'].values()) else j['pitches']")"
printf '  info  row pitch in points: %s\n' "$(ps_ "j['pitches'].get('light')")"
# POLISH_RENDER=<folder> keeps the card's PNGs, to look at them.
[ -n "${POLISH_RENDER:-}" ] && mkdir -p "$POLISH_RENDER" && cp "$pl"/render/*.png "$POLISH_RENDER"/

echo "-- Investigate and hard links"
iv="$pl/inv"; mkdir -p "$iv/in/sub" "$iv/outside"
printf 'OUTSIDE_LINKED_SECRET_58\n' >"$iv/outside/secret.txt"
ln "$iv/outside/secret.txt" "$iv/in/linked.txt"
printf 'INSIDE_TWICE_MARK\n' >"$iv/in/a.txt"
ln "$iv/in/a.txt" "$iv/in/sub/b.txt"
printf 'INSIDE_ONCE_MARK\n' >"$iv/in/notes.txt"
pl_call() { printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' "$1" "$2"; }
{ pl_call Read '{"file_path":"linked.txt"}'; pl_call Read '{"file_path":"a.txt"}'; pl_call Read '{"file_path":"sub/b.txt"}'
  pl_call Grep '{"pattern":"MARK|SECRET"}'; } | "$BIN" _investigate-tools --folder "$iv/in" >"$iv/out.txt" 2>"$iv/err.txt"
check "polish: the tool server answers four calls" 4 "$(grep -c '"jsonrpc"' "$iv/out.txt")"
pi() { python3 -c "
import json, sys
r = [json.loads(l) for l in open(sys.argv[1]) if l.strip().startswith('{')]
t = [' '.join(c.get('text', '') for c in x.get('result', {}).get('content', [])) for x in r]
e = [bool(x.get('result', {}).get('isError')) for x in r]
print($1)" "$iv/out.txt"; }
check "polish: a hard link to a file outside is refused" "True True" "$(pi "'%s %s' % (e[0], 'hard link outside' in t[0])")"
check "polish: a file whose two links are both inside is read" "False True False True" \
  "$(pi "'%s %s %s %s' % (e[1], 'INSIDE_TWICE_MARK' in t[1], e[2], 'INSIDE_TWICE_MARK' in t[2])")"
check "polish: Grep skips the hard link to the file outside" "False True True" \
  "$(pi "'%s %s %s' % ('OUTSIDE_LINKED' in t[3], 'INSIDE_ONCE_MARK' in t[3], 'INSIDE_TWICE_MARK' in t[3])")"
grep -q OUTSIDE_LINKED_SECRET_58 "$iv/out.txt"; check "polish: no byte of the linked file reaches the output" 1 "$?"

echo "-- the verb specs say which forms change things"
"$BIN" help --json >"$pl/help.json" 2>/dev/null
ph() { python3 -c "
import json, sys
v = {x['verb']: x for x in json.load(open(sys.argv[1]))['verbs']}
print($1)" "$pl/help.json"; }
check "polish: work changes things in its wrap-up form" "True ['wrap-up']" "$(ph "'%s %s' % (v['work']['mutates'], v['work']['mutatingForms'])")"
check "polish: trees keep and protect change things" "True True True" \
  "$(ph "'%s %s %s' % (v['trees']['mutates'], 'keep' in v['trees']['mutatingForms'], 'protect' in v['trees']['mutatingForms'])")"
check "polish: review --now and restore without --list change things" "['--now'] ['!--list']" \
  "$(ph "'%s %s' % (v['review']['mutatingForms'], v['restore']['mutatingForms'])")"
check "polish: a verb that changes things in every form lists no form" "True []" "$(ph "'%s %s' % (v['tidy']['mutates'], v['tidy']['mutatingForms'])")"
check "polish: status and version change nothing" "False False" "$(ph "'%s %s' % (v['status']['mutates'], v['version']['mutates'])")"
MINMACS_COLD=1 "$BIN" trees keep "$W/one" >/dev/null 2>&1; r1=$?
MINMACS_COLD=1 "$BIN" trees protect "$W/one" >/dev/null 2>&1; r2=$?
MINMACS_COLD=1 "$BIN" restore --list --json >/dev/null 2>&1; r3=$?
check "polish: cold, keep and protect need the app and restore --list runs" "3 3 0" "$r1 $r2 $r3"

echo "-- the cold CLI walks and runs git only for verbs that read worktrees"
# MINMACS_GIT names a wrapper that logs each git call, then runs this Mac's git.
pl_git=""; for g in /Library/Developer/CommandLineTools/usr/bin/git /opt/homebrew/bin/git /usr/local/bin/git /Applications/Xcode.app/Contents/Developer/usr/bin/git; do
  [ -x "$g" ] && { pl_git=$g; break; }; done
printf '#!/bin/sh\necho "$*" >>"%s"\nexec "%s" "$@"\n' "$pl/git.log" "$pl_git" >"$pl/bin/git-logged"; chmod +x "$pl/bin/git-logged"
pl_cold() { : >"$pl/git.log"; MINMACS_COLD=1 MINMACS_GIT="$pl/bin/git-logged" "$BIN" "$@" >/dev/null 2>&1; grep -c 'status --porcelain' "$pl/git.log"; }
check "polish: trees list runs git status for each of the seven checkouts" yes "$(n=$(pl_cold trees list --all --json); [ "$n" -ge 7 ] && echo yes || echo "$n")"
# Before, every cold verb ran git status for every checkout. status now takes the cached facts, and the repo index
# runs git status only for a checkout whose index file or HEAD moved since the facts were cached. An earlier git
# status may have rewritten an index, so a few may run, never one for every checkout.
pl_n=$(pl_cold status --json)
check "polish: status runs git status for fewer than the seven checkouts" yes "$([ "$pl_n" -lt 7 ] && echo yes || echo "$pl_n")"
printf '  info  cold status ran git status %s times: %s\n' "$pl_n" "$(grep 'status --porcelain' "$pl/git.log" | awk '{print $2}' | sed "s|$pl/code/||" | tr '\n' ' ')"
check "polish: trees list forces git status again for each checkout" yes "$(n=$(pl_cold trees list --all --json); [ "$n" -ge 7 ] && echo yes || echo "$n")"
check "polish: version, mode and where run no git" "0 0 0" "$(pl_cold version) $(pl_cold mode workforest --json) $(pl_cold where --port "$P" --json)"
check "polish: where runs no git at all" 0 "$(: >"$pl/git.log"; MINMACS_COLD=1 MINMACS_GIT="$pl/bin/git-logged" "$BIN" where --port "$P" >/dev/null 2>&1; grep -c . "$pl/git.log")"
pl_ms() { python3 -c "
import os, subprocess, sys, time
env = dict(os.environ, MINMACS_COLD='1')
best = None
for _ in range(3):
    t = time.time(); subprocess.run(sys.argv[1:], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); d = time.time() - t
    best = d if best is None else min(best, d)
print('%.0f' % (best * 1000))" "$BIN" "$@"; }
printf '  info  cold, best of 3: status %s ms, trees list %s ms, version %s ms\n' "$(pl_ms status --json)" "$(pl_ms trees list --json)" "$(pl_ms version)"

# Stop the server this section started, by the pid its own pid file names, while it still serves our port.
for f in "$pl"/pids/server-*; do
  [ -e "$f" ] || continue
  x=${f##*server-}
  case "$(ps -o command= -p "$x" 2>/dev/null)" in *"polish-fixture-$$"*) kill "$x" 2>/dev/null ;; esac
done
i=0; while nc -z 127.0.0.1 "$P" >/dev/null 2>&1 && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
procs="$pl_procs_before"
unset MINMACS_ROOTS MINMACS_CLAUDE MINMACS_CODEX MINMACS_CMUX MINMACS_TMUX GIT_CONFIG_NOSYSTEM
export CLAUDE_CONFIG_DIR="$pl_saved_claude" CODEX_HOME="$pl_saved_codex" MINMACS_HOME="$pl_top"
