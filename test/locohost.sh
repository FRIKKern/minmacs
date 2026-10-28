# LocoHost on the shared core, issue #22. Sourced by test.sh after core.
# Ports the 54 checks of LocoHost 0.1's test.sh, then adds the 2.0 ones: the verbs, restore, the render and the invariants.
# Fixtures only: Python HTTP servers on high ports this section picks, in a project folder inside $MINMACS_HOME,
# and test/review's fake claude and codex in place of the real CLIs. Every stop and every auto run names a fixture port,
# and every review is scoped to it with --port, so no other server on this Mac is judged or touched.
# Where reads a fake tmux and a fake cmux, so no real session is made or asked.

lh="$MINMACS_HOME/lh"
mkdir -p "$lh/bin" "$lh/pids" "$lh/app" "$lh/real" "$lh/home"
# A support folder of its own, so this section's reviews, usage and undo rows never reach another section's counts.
lh_top="$MINMACS_HOME"
export MINMACS_HOME="$lh/home"

# The CLI: the minmacs binary when its verb registry runs LocoHost's verbs under the locohost name, else
# test/locohost/lhcli.m, which runs the same verbs through the same registry, as the app runs a verb handed over core.sock.
# LH_REAL=1 picks the binary; its mutating verbs need the app. Both are named so MinMacs counts their connections as its own.
ln -sf "$BIN" "$lh/real/locohost"
if [ "${LH_REAL:-}" = 1 ] && "$lh/real/locohost" free 47100 2>/dev/null | grep -qE '^[0-9]+$'; then
  LH="$lh/real/locohost"; echo "  the minmacs binary runs the locohost verbs"
else
  lh_src=$(find Sources -name '*.m' ! -path 'Sources/main.m' ! -path 'Sources/Shell/*' | LC_ALL=C sort)
  # shellcheck disable=SC2086
  clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -ISources \
    -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
    $lh_src test/locohost/lhcli.m -o "$lh/bin/MinMacs" >"$lh/clang.log" 2>&1
  check "test/locohost/lhcli.m builds" 0 "$?"
  check "the LocoHost sources have no warnings" 0 "$(grep -c 'warning:' "$lh/clang.log")"
  ln -sf "$lh/bin/MinMacs" "$lh/bin/locohost"
  LH="$lh/bin/locohost"
fi

export MINMACS_CLAUDE="$ROOT/test/review/fakeclaude.py" MINMACS_CODEX="$ROOT/test/review/fakecodex.py" RV_TEST_SENT="$lh/sent.json"
export MINMACS_TMUX="$lh/tmux" MINMACS_CMUX="$ROOT/test/locohost/fake-cmux.sh"
cp test/locohost/fake-tmux.sh "$lh/tmux"
unset RV_TEST_GO RV_TEST_UNSURE RV_TEST_KEEP RV_TEST_CLAUDE_LIMIT RV_TEST_CODEX_UNSUPPORTED LOCOHOST_IDLE_MINUTES LOCOHOST_MIN_UPTIME_MINUTES LOCOHOST_PROACTIVE_MINUTES

lh_listening() { nc -z 127.0.0.1 "$1" >/dev/null 2>&1 && echo yes || echo no; }
# The fixture server. It writes its pid file into $lh/pids, and the command line carries a fake key and a URL password,
# so the review shows what is redacted. Detached, so it has no shell or agent above it.
LH_PY='import http.server, os, signal, sys
open(os.path.join(sys.argv[3], "pid-%d" % os.getpid()), "w").close()
if sys.argv[2] == "stubborn": signal.signal(signal.SIGTERM, signal.SIG_IGN)
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), http.server.SimpleHTTPRequestHandler).serve_forever()'
lh_serve() { # port, [stubborn], [seconds to wait before starting]
  ( ( sleep "${3:-0}"; cd "$lh/app" && exec python3 -c "$LH_PY" "$1" "${2:-plain}" "$lh/pids" --api-key SUPERSECRET123 DATABASE_URL=postgres://user:hunter2@db/x ) >/dev/null 2>&1 & )
}
# Stops what this section started and nothing else: the pids in its own pid files.
lh_stop_all() { for f in "$lh"/pids/pid-*; do [ -e "$f" ] && kill -9 "${f##*pid-}" 2>/dev/null; rm -f "$f"; done; }
# A fresh instance of the fixture on its port, so the fingerprint cache sends it to the model again.
# close takes a port or a pid. With nothing on the port, it would match a process whose pid equals the port, so it runs
# only while the fixture listens.
lh_fresh() { [ "$(lh_listening "$P")" = yes ] && "$LH" close "$P" --yes --force >/dev/null 2>&1; lh_stop_all; lh_serve "$P" "${1:-plain}"; "$LH" ready "$P" --timeout 10 >/dev/null; }

# The project folder: a package.json, a README, a secret .env and an agent session that started just before the server.
APPDIR=$(cd "$lh/app" && pwd -P)
printf '{"name": "fixture-app", "description": "Fixture project for LocoHost tests", "scripts": {"dev": "python3 -m http.server"}}' > "$lh/app/package.json"
printf '# Fixture\n\nA small server that test.sh starts and stops.\n' > "$lh/app/README.md"
printf 'API_TOKEN=ENVSECRET999\n' > "$lh/app/.env"
LH_SESS="$CLAUDE_CONFIG_DIR/projects/$(printf %s "$APPDIR" | tr '/.' '--')"
mkdir -p "$LH_SESS"
python3 - "$LH_SESS/fixture-$$.jsonl" "$APPDIR" <<'PY'
import json, sys, datetime
t = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "timestamp": t, "cwd": sys.argv[2], "message": {"role": "user", "content": "Start the fixture server, password=HUNTER77 is fine"}}) + "\n")
    f.write(json.dumps({"type": "ai-title", "aiTitle": "Fixture session", "sessionId": "fixture"}) + "\n")
PY
# MinMacs acts on its own only after a day of watching. The fixture Mac has watched for two.
python3 -c "import time; print(int(time.time()) - 2 * 86400)" > "$MINMACS_HOME/watching-since"
CLAUDE_HOME_SAVED="$CLAUDE_CONFIG_DIR"

P=$("$LH" free $((40000 + $$ % 9000)))   # below 49152, where ports are picked by hand
echo "== ports, fixture port $P"
check "free returns a port nobody listens on" no "$(lh_listening "$P")"
"$LH" ready "$P" --timeout 1 >/dev/null 2>&1;                      check "ready times out with exit 1" 1 "$?"
lh_serve "$P" plain 1
"$LH" ready "$P" --http --timeout 15 >/dev/null;                    check "ready --http waits for the server" 0 "$?"
"$LH" who "$P" | grep -q "Python http.server";                       check "who names the framework" 0 "$?"
r=$("$LH" list --json | json "[h['kind'] for h in j['hosts'] if $P in h['ports']][0]")
                                                                     check "list --json lists it as a dev server" dev "$r"
"$LH" who "$P" | grep -q "SUPERSECRET123";                           check "who shows the full command locally" 0 "$?"

echo "== review and close idle"
LOCOHOST_IDLE_MINUTES=0 RV_TEST_GO=":$P" "$LH" review --port "$P" >/dev/null 2>&1; check "review with the fake CLI succeeds" 0 "$?"
grep -q "SUPERSECRET123" "$RV_TEST_SENT";                            check "the api key value is not sent" 1 "$?"
grep -q "hunter2" "$RV_TEST_SENT";                                   check "the URL password is not sent" 1 "$?"
grep -q "http.server" "$RV_TEST_SENT";                               check "the rest of the command is sent" 0 "$?"
grep -q "fixture-app" "$RV_TEST_SENT";                               check "the package.json name is sent" 0 "$?"
grep -q "ENVSECRET999" "$RV_TEST_SENT";                              check ".env contents are never sent" 1 "$?"
grep -q "Fixture session" "$RV_TEST_SENT";                           check "the agent session title is sent" 0 "$?"
grep -q "HUNTER77" "$RV_TEST_SENT";                                  check "a secret in the session prompt is never sent" 1 "$?"
LOCOHOST_IDLE_MINUTES=0 "$LH" explain "$P" | grep -q "fixture says so"; check "explain shows the model's reason" 0 "$?"
r=$("$LH" list --json | json "sorted(k for k in [h for h in j['hosts'] if $P in h['ports']][0] if k.startswith('idle') or k == 'energyRank')")
                                                                     check "list --json has the waste counters" "['energyRank', 'idleCPUSeconds']" "$r"
r=$("$LH" waste --json | json "[h['port'] for h in j['hosts']].count($P)")
                                                                     check "waste lists the fixture" 1 "$r"
r=$("$LH" idle --json --port "$P" | json "len(j['candidates'])")
                                                                     check "with a 30 min threshold nothing is idle yet" 0 "$r"
r=$(LOCOHOST_IDLE_MINUTES=0 "$LH" idle --json --port "$P" | json "len(j['candidates'])")
                                                                     check "quiet plus an idle verdict makes a candidate" 1 "$r"
LH_RULES=$("$LH" rules)
python3 - "$LH_RULES" "$P" add <<'PY'
import json,sys; p,port,op=sys.argv[1],int(sys.argv[2]),sys.argv[3]; j=json.load(open(p)); l=j.setdefault('protect.ports',[])
(l.append(port) if op=='add' else l.remove(port)); json.dump(j,open(p,'w'))
PY
r=$(LOCOHOST_IDLE_MINUTES=0 "$LH" idle --json --port "$P" | json "len(j['candidates'])")
                                                                     check "a protected port is never a candidate" 0 "$r"
python3 - "$LH_RULES" "$P" remove <<'PY'
import json,sys; p,port,op=sys.argv[1],int(sys.argv[2]),sys.argv[3]; j=json.load(open(p)); l=j.setdefault('protect.ports',[])
(l.append(port) if op=='add' else l.remove(port)); json.dump(j,open(p,'w'))
PY
# Legacy #44: protect lists match with the same wildcards everywhere, so a name pattern protects too.
python3 - "$LH_RULES" <<'PY'
import json,sys; p=sys.argv[1]; j=json.load(open(p)); j.setdefault('protect.names',[]).append('Pyth*'); json.dump(j,open(p,'w'))
PY
r=$(LOCOHOST_IDLE_MINUTES=0 "$LH" idle --json --port "$P" | json "len(j['candidates'])")
                                                                     check "a protect.names pattern with * protects it" 0 "$r"
python3 - "$LH_RULES" <<'PY'
import json,sys; p=sys.argv[1]; j=json.load(open(p)); j['protect.names'].remove('Pyth*'); json.dump(j,open(p,'w'))
PY
LOCOHOST_IDLE_MINUTES=0 "$LH" close-idle --yes --port "$P" >/dev/null; check "close-idle --yes stops it, exit 0" 0 "$?"
check "and the port is free" no "$(lh_listening "$P")"
"$LH" stopped --json | grep -q "http.server";                       check "stopped keeps its restart command" 0 "$?"

echo "== Luna when Haiku is out of usage"
lh_stop_all; lh_serve "$P"; "$LH" ready "$P" --timeout 10 >/dev/null
# The idle verdict above was for the stopped instance. The new one on the same port and folder has the same finding id.
r=$(LOCOHOST_IDLE_MINUTES=0 "$LH" idle --json --port "$P" | json "len(j['candidates'])")
                                                                     check "a verdict for an earlier instance makes no candidate" 0 "$r"
r=$("$LH" list --json | json "'review' in [h for h in j['hosts'] if $P in h['ports']][0]")
                                                                     check "and list --json shows no verdict for it" False "$r"
r=$("$LH" explain "$P" | grep -c "fixture says so")
                                                                     check "and explain shows no earlier reason" 0 "$r"
RV_TEST_CLAUDE_LIMIT=1 OPENAI_API_KEY=sk-test "$LH" review --model auto --port "$P" --json >"$lh/luna.json" 2>/dev/null
r=$(json "j['model']" <"$lh/luna.json");                             check "auto falls back to Luna, without the API key" gpt-6-luna "$r"
r=$(json "'usage limit' in (j['note'] or '')" <"$lh/luna.json");     check "and notes why Haiku was skipped" True "$r"
grep -q "SUPERSECRET123" "$RV_TEST_SENT";                            check "the api key value is not sent to Luna" 1 "$?"
lh_fresh
r=$(RV_TEST_CODEX_UNSUPPORTED=gpt-6-luna "$LH" review --model luna --port "$P" --json | json "j['model']")
                                                                     check "luna moves on from a model the account lacks" gpt-5.6-luna "$r"

echo "== modes, every auto run names the fixture port, so no other server is judged or stopped"
export LOCOHOST_IDLE_MINUTES=0 LOCOHOST_MIN_UPTIME_MINUTES=0
# A mode acts only when it is the mode set, as MMRunAction checks again right before it stops anything.
lh_plan() { lh_m=$1; shift; "$LH" mode "$lh_m" >/dev/null; "$LH" auto --mode "$lh_m" --port "$P" --json "$@" | json "j['plan'][0]['stop'] if j['plan'] else 'none'"; }
lh_why() { "$LH" auto --mode "$1" --port "$P" --dry-run --json | json "j['plan'][0]['why']"; }
# A session counts for a server only when it was active up to 60 s before the server started. Mark it active now,
# so a slow runner that reaches this point minutes after the section began still links the two.
python3 - "$LH_SESS/fixture-$$.jsonl" "$APPDIR" <<'PY'
import json, sys, datetime
t = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
with open(sys.argv[1], "a") as f:
    f.write(json.dumps({"type": "user", "timestamp": t, "cwd": sys.argv[2], "message": {"role": "user", "content": "Keep the fixture server up"}}) + "\n")
PY
lh_fresh
r=$(RV_TEST_GO=":$P" "$LH" review --mode eager --port "$P" --json | json "'Fixture summary: 1 items.' in j['summary']")
                                                                     check "the review writes a summary" True "$r"
# The reason itself is the value, so a failure shows which rule spoke first.
r=$(lh_why eager | cut -c1-28);                                       check "eager keeps a server whose agent session is active" "its agent session was active" "$r"
export CLAUDE_CONFIG_DIR="$MINMACS_HOME/no-sessions"   # from here on no session, so the mode decides
RV_TEST_GO=":$P" "$LH" review --mode proactive --port "$P" >/dev/null 2>&1
r=$(lh_plan idle);                                                   check "idle mode stops nothing" False "$r"
r=$(lh_plan proactive);                                              check "proactive waits for a long quiet" False "$r"
r=$(LOCOHOST_PROACTIVE_MINUTES=0 lh_plan proactive);                 check "proactive stops sure idle after the wait" True "$r"
r=$("$LH" stopped --json | json "j[0]['by']");                       check "stopped records the mode" proactive "$r"
check "and the port is free" no "$(lh_listening "$P")"

lh_fresh
RV_TEST_UNSURE=":$P" RV_TEST_KEEP=":$P" "$LH" review --mode eager --port "$P" >/dev/null 2>&1
r=$(python3 -c "
import json,sys
hit=False
for line in open('$RV_TEST_SENT.judge'):
    line=line.strip()
    if not line: continue
    j=json.loads(line)
    hit = hit or any($P in f.get('ports',[]) for b in j.get('blocks',[]) for f in b.get('f',[]))
print(hit)")
                                                                     check "eager sends an unsure server to the judge" True "$r"
r=$(lh_plan eager --dry-run);                                        check "the judge keeps it when it shows evidence" False "$r"
r=$(lh_why eager | python3 -c "import sys; print(sys.stdin.read().startswith('evidence'))")
                                                                     check "and says what the evidence is" True "$r"
lh_fresh
RV_TEST_UNSURE=":$P" "$LH" review --mode eager --port "$P" >/dev/null 2>&1
r=$(LOCOHOST_MIN_UPTIME_MINUTES=30 lh_plan eager);                   check "eager never stops a server started minutes ago" False "$r"
r=$(lh_plan eager);                                                  check "eager stops it without evidence" True "$r"
check "and the port is free" no "$(lh_listening "$P")"
r=$("$LH" stopped --json | json "j[0]['by']");                       check "stopped records the mode" eager "$r"
"$LH" restart "$P" >/dev/null;                                       check "restart starts it again from its recorded command" 0 "$?"
"$LH" ready "$P" --http --timeout 15 >/dev/null;                     check "and it answers again" 0 "$?"
RV_TEST_GO=":$P" "$LH" review --mode eager --port "$P" >/dev/null 2>&1
"$LH" keep "$P" 1 >/dev/null
r=$("$LH" auto --mode eager --port "$P" --json | json "j['plan'][0]['why'].startswith('kept by you')")
                                                                     check "keep holds it back from eager" True "$r"
"$LH" keep "$P" 0 >/dev/null
r=$(lh_plan eager --dry-run);                                        check "and releasing it hands it back to the mode" True "$r"
"$LH" mode proactive >/dev/null
unset LOCOHOST_IDLE_MINUTES LOCOHOST_MIN_UPTIME_MINUTES
export CLAUDE_CONFIG_DIR="$CLAUDE_HOME_SAVED"

echo "== where a server runs"
W=$("$LH" free $((P + 1)))
# A shell that stays above the server, as a tmux pane's shell does. The fake tmux names that shell's pid as a pane.
( ( cd "$lh/app" && exec sh -c "python3 -c '$LH_PY' $W plain '$lh/pids' & echo \$\$ > '$lh/pane.pid'; wait" ) >/dev/null 2>&1 & )
"$LH" ready "$W" --timeout 10 >/dev/null
printf '%s\t%%7\tlocohost-test-%s\t0\tfixture\t0\n' "$(cat "$lh/pane.pid")" "$$" > "$lh/tmux.panes"
r=$("$LH" where "$W" --json | json "j.get('kind','none')")
check "where names the tmux pane a server runs in" tmux "$r"
# Go To from the menu runs tmux, which can take seconds. It must run off main, so the menu's main thread never waits.
if [ "$LH" = "$lh/bin/locohost" ]; then
  : >"$lh/tmux.goto"; echo 2 >"$lh/tmux.slow"
  r=$("$lh/bin/MinMacs" _gotime "$W" 2>/dev/null)
  rm -f "$lh/tmux.slow"
  check "Go To from the menu returns to main at once" yes "$([ -n "$r" ] && [ "$r" -lt 10 ] && echo yes || echo no)"
  check "  and still selects the pane, off main" 1 "$(grep -c '^select-pane' "$lh/tmux.goto")"
fi
kill "$(cat "$lh/pane.pid")" 2>/dev/null
lh_stop_all

echo "== a failed review closes nothing"
lh_fresh
RV_TEST_CLAUDE_LIMIT=1 MINMACS_CODEX=/usr/bin/false "$LH" review --model auto --port "$P" >/dev/null 2>&1
                                                                     check "both models failing exits 1" 1 "$?"
MINMACS_CLAUDE=/usr/bin/false "$LH" review --model haiku --port "$P" >/dev/null 2>&1; check "review reports failure with exit 1" 1 "$?"
r=$(LOCOHOST_IDLE_MINUTES=0 "$LH" idle --json --port "$P" | json "len(j['candidates'])")
                                                                     check "and nothing is a candidate" 0 "$r"
"$LH" close "$P" --yes >/dev/null;                                   check "close <port> --yes stops one server" 0 "$?"

echo "== a server that ignores SIGTERM"
lh_stop_all; lh_serve "$P" stubborn; "$LH" ready "$P" --timeout 10 >/dev/null
"$LH" close "$P" --yes >/dev/null; rc=$?;                            check "close leaves it running, exit 3" 3 "$rc"
check "still listening" yes "$(lh_listening "$P")"
"$LH" close "$P" --yes --force >/dev/null;                           check "close --force kills it, exit 0" 0 "$?"
check "and the port is free" no "$(lh_listening "$P")"

echo "== 2.0: verbs, restore and the core"
"$LH" verbs >"$lh/verbs.txt" 2>/dev/null || "$lh/bin/locohost" verbs >"$lh/verbs.txt" 2>/dev/null
for v in hosts where review restore; do
  check "MMExpert registers the $v verb" yes "$(cut -f1 "$lh/verbs.txt" | grep -qx "$v" && echo yes || echo no)"
done
check "every 1.x verb is registered" 0 "$(for v in list who explain ready free waste summary auto mode idle close-idle close open stopped restart keep rules; do cut -f1 "$lh/verbs.txt" | grep -qx "$v" || echo "$v"; done | grep -c .)"
check "the 1.x verbs say so in their usage" 0 "$(awk -F'\t' '$1!="hosts" && $1!="where" && $1!="review" && $1!="restore" && $1!="legacyName" && $1!="registered" && $3 !~ /^locohost /' "$lh/verbs.txt" | grep -c .)"
check "the legacy name is locohost" locohost "$(awk -F'\t' '$1=="legacyName" {print $2}' "$lh/verbs.txt")"
check "LocoHost registers itself with Core" yes "$(awk -F'\t' '$1=="registered" {print $2}' "$lh/verbs.txt")"
lh_stop_all; lh_serve "$P"; "$LH" ready "$P" --timeout 10 >/dev/null
r=$("$LH" hosts "$P" --json | json "j['framework']");                check "hosts <port> explains one port" "Python http.server" "$r"
r=$("$LH" hosts "$P" --json | json "'SUPERSECRET123' in json.dumps(j['reviewFacts'])")
                                                                     check "and what the review would get is redacted" False "$r"
r=$("$LH" hosts --json | json "any($P in h['ports'] for h in j['hosts'])"); check "hosts lists every localhost" True "$r"
# A second fixture in a folder whose name is too long for the project column, so the row cuts it.
LH_LONG="$lh/a-project-folder-with-a-name-far-too-long-for-its-column"
mkdir -p "$LH_LONG"; LP=$("$LH" free $((P + 7)))
( ( cd "$LH_LONG" && exec python3 -c "$LH_PY" "$LP" plain "$lh/pids" ) >/dev/null 2>&1 & )
"$LH" ready "$LP" --timeout 10 >/dev/null
# Each column of the text table starts where its header does, counted in characters, for every row.
r=$("$LH" hosts | python3 -c "
import sys
lines = sys.stdin.read().split('\n')
head = lines[0]
cols = [head.index(w) for w in ('what', 'project', 'up ', 'state', 'started by')]
rows = [l for l in lines[1:] if l[3:4].isdigit()]
bad = [l for l in rows if any(len(l) > c and (l[c - 1] != ' ' or l[c] == ' ') for c in cols)]
long = [l for l in rows if l[3:].startswith('$LP ')]
print('%d %d %s' % (len(rows) > 1, len(bad), 'cut' if long and '\u2026' in long[0][cols[1]:cols[2]] else 'whole'))")
check "hosts: every column starts under its header, a cut name too" "1 0 cut" "$r"
if [ "$LH" = "$lh/bin/locohost" ]; then
  # The menu, cards, badge and label on the main thread read what the snapshot holds: no undo log, no keeps file.
  check "the menu on main reads no undo log and no keeps file" "0 0" "$("$lh/bin/MinMacs" _menureads 2>/dev/null | cut -d' ' -f1,2)"
fi
"$LH" close "$P" --yes --dry-run >/dev/null;                         check "close --dry-run exits 0" 0 "$?"
check "and stops nothing" yes "$(lh_listening "$P")"
"$LH" close "$P" --yes >/dev/null
rid=$("$LH" restore --json | json "[x['rid'] for x in j if x['port'] == $P][0]")
check "restore lists the stop with its record id" yes "$([ -n "$rid" ] && echo yes || echo no)"
"$LH" restore "$rid" >/dev/null;                                     check "restore <record id> starts it again" 0 "$?"
"$LH" ready "$P" --http --timeout 15 >/dev/null;                     check "and it answers again" 0 "$?"
r=$("$LH" stopped --json | json "[x['state'] for x in j if x['rid'] == '$rid'][0]"); check "the record reads restored" restored "$r"
"$LH" restore "$rid" >/dev/null 2>&1;                                check "a second restore of the same record is refused" 1 "$?"
r=$(python3 -c "import sqlite3; c=sqlite3.connect('$MINMACS_HOME/minmacs.sqlite'); print(c.execute(\"select count(*) from rows where tbl='undo' and expert='locohost'\").fetchone()[0] > 0)" 2>&1)
check "stops are undo records in Core's log" True "$r"
# Legacy #48: no registry row declares socket_activity. LocoHost decides socket activity from Senses' sockets.
check "no registry row declares socket_activity" 0 "$(grep -l socket_activity registry/agents/*.json registry/schema.json | grep -c .)"
check "the expert never runs lsof, nettop, ps or pmset" 0 "$(grep -nE '"[^"]*(lsof|nettop|pmset|/bin/ps)[^"]*"' Sources/Experts/LocoHost/*.m | grep -c .)"
check "the expert lists no processes or sockets itself" 0 "$(grep -nE 'proc_listpids|PROC_PIDLISTFDS|KERN_PROC_ALL|proc_pidfdinfo' Sources/Experts/LocoHost/*.m | grep -c .)"
# Invariant 2: the CLI's cold facts come from Sources/CLI. LocoHost has no fact source of its own and takes no sample.
check "the expert has no fact source and takes no sample" 0 "$(grep -nE 'MMFactSource|sampleNow|factsFor:\(uint64_t|freshFactsFor' Sources/Experts/LocoHost/*.m | grep -c .)"
check "the expert prints only through MMArgs" 0 "$(grep -nE '(^|[^a-zA-Z_])printf\(' Sources/Experts/LocoHost/*.m | grep -vE '\[y/N\]|initWithData:d' | grep -c .)"
# Git facts come from Core's repo index. LocoHost reads no git file and runs no git.
check "the expert reads no git file and runs no git" 0 "$(grep -nE '"HEAD"|/\.git|gitdir|MMGit\(|ls-files|@"index"' Sources/Experts/LocoHost/*.m | grep -c .)"
check "MMLHGitOf reads the repo index's worktree and facts" "1 1" \
  "$(grep -c 'MMRepoIndex.shared worktreeAt:' Sources/Experts/LocoHost/MMLHScan.m) $(grep -c 'MMRepoIndex.shared factsFor:wt wait:NO' Sources/Experts/LocoHost/MMLHScan.m)"
check "the expert never asks the model itself" 0 "$(grep -nE 'MMModel|claudePath|codexPath|NSTask' Sources/Experts/LocoHost/*.m | grep -c .)"
check "the expert never signals a process itself" 0 "$(grep -nE '[^a-zA-Z_]kill\(' Sources/Experts/LocoHost/*.m | grep -c .)"
check "the expert names no .env file in its code" 0 "$(grep -nE '@"[^"]*\.env("|[^a-zA-Z])' Sources/Experts/LocoHost/*.m | grep -c .)"
lh_stop_all

echo "== the menu and cards, rendered"
lh_r="$lh/render"
if BUILD_DIR="$lh/render-build" tools/render.sh "$lh_r" >"$lh/render.log" 2>&1; then lh_ok=0; else lh_ok=1; tail -20 "$lh/render.log"; fi
check "tools/render.sh passes every DESIGN.md check" 0 "$lh_ok"
check "the LocoHost menu follows DESIGN.md rules 3 and 4" 1 "$(grep -c '^ok    locohost: the menu follows' "$lh_r/checks.txt" 2>/dev/null)"
check "the LocoHost cards follow the card rules" 0 "$(grep -E '^FAIL  locohost' "$lh_r/checks.txt" 2>/dev/null | grep -c .)"
lh_png=0
for m in light dark contrast-light contrast-dark; do [ -s "$lh_r/locohost-menu-$m.png" ] && lh_png=$((lh_png+1)); done
check "the LocoHost menu renders in light, dark and Increase Contrast" 4 "$lh_png"
check "every LocoHost card renders in four appearances" 0 "$(for c in $(ls "$lh_r" | grep -v contrast | sed -n 's/^locohost-card-\(.*\)-light\.png$/\1/p'); do for m in dark contrast-light contrast-dark; do [ -s "$lh_r/locohost-card-$c-$m.png" ] || echo "$c-$m"; done; done | grep -c .)"
procs="$procs $(ls "$lh/pids" 2>/dev/null | sed 's/pid-//' | tr '\n' ' ')"
lh_stop_all
unset MINMACS_CLAUDE MINMACS_CODEX RV_TEST_SENT MINMACS_TMUX MINMACS_CMUX
export MINMACS_HOME="$lh_top"
