#!/bin/sh
# The soak, issue #56. Core headless with every built-in expert, every mode Idle, beside fixture churn, sampled for
# footprint, CPU, open fds, threads and leaks(1), with crash reports and main-thread stalls checked at the end.
# Usage: tools/soak/run.sh [seconds] [sample-every] [churn-every] [out]
#   seconds       how long the soak runs, default 86400, the 24 hours of PLAN.md phase 6
#   sample-every  seconds between samples, default 3600. The first sample comes after a warm-up of 120 seconds,
#                 or a tenth of the run when that is shorter, and the last one right before the stop
#   churn-every   seconds between churn steps, default 20
#   out           where samples.jsonl, status.jsonl, summary.json, leaks-*.txt and report.md go,
#                 default build/soak/<date>
#   BUILD_DIR     where the soak binaries are built, default build. SOAK_DIR names a folder built already.
#   SOAK_MENUS_EVERY  seconds between rounds of every expert's menu and cards on the live snapshot, default 60
#   SOAK_KEEP     how many worktrees, servers and agents stay alive at once, default 4, 3 and 3. A number keeps
#                 that many of each, so a short run removes and stops some too
#
# Each churn step, inside a fresh MINMACS_HOME under TMPDIR: a fixture worktree is made in the fixture repo, with a
# commit, and the oldest past four is removed. A Python HTTP server starts in the newest worktree on a free high port,
# and the oldest past three stops. A fake agent starts with a Claude Code session file and a transcript, and the
# oldest past three stops, its files removed. Every live transcript gets a line.
# Every fixture name carries this run's tag. A fixture is stopped by its pid only, after ps shows the tag in its
# command line. Servers and agents call setsid and end by themselves after a while, even if this script dies.
# The model, cmux and tmux CLIs are /usr/bin/false. Only the fixture registry row is loaded, and the fake agent has no
# working signal, so Insomnia holds nothing. Nothing outside MINMACS_HOME is written, signaled or removed.
set -u
cd "$(dirname "$0")/../.."
ROOT=$(pwd -P)
SECS=${1:-86400}
EVERY=${2:-3600}
CHURN=${3:-20}
OUT=${4:-build/soak/$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd -P)
B=${SOAK_DIR:-$(tools/soak/build.sh)} || { echo "soak: the build failed" >&2; exit 1; }
B=$(cd "$B" && pwd -P)

# A tag unique to this run: the pid and a random byte. Process names stay under 16 characters.
TAG="$$$(od -An -N1 -tu1 /dev/urandom | tr -d ' ')"
SOAK="mmsoak$TAG"; AGENT="mmsa$TAG"; MARK="mms(oak-?|a)$TAG( |$)"
H=$(mktemp -d "${TMPDIR:-/tmp}/minmacs-soak.XXXXXX") && H=$(cd "$H" && pwd -P)
mkdir -p "$H/bin" "$H/code" "$H/claude/sessions" "$H/claude/projects" "$H/codex" "$H/pi" \
  "$H/pids/servers" "$H/pids/agents" "$H/registry/agents"
cp "$B/soak" "$H/bin/$SOAK" && cp "$B/agent" "$H/bin/$AGENT"
PROCSTAT="$B/procstat"

# The pid is this run's own: alive, above 1, and ps shows the tag in its command line.
ours() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -gt 1 ] && ps -o command= -p "$1" 2>/dev/null | grep -qE -- "$MARK"; }
stop_pid() { ours "$1" && kill "$1" 2>/dev/null; }

G() { git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
A="$H/code/app$TAG"; W="$H/code/app$TAG.worktrees"
G init -q --bare "$H/origin.git"
G clone -q "$H/origin.git" "$A" 2>/dev/null
( cd "$A" && echo one >a.txt && G add -A && G commit -qm first && G push -q origin main 2>/dev/null )
mkdir -p "$W"

# The fixture row, under this run's process name.
sed "s/\"fakeagent\"/\"$AGENT\"/; s/\"fake-agent\"/\"soak-agent\"/; s/\"Fake Agent\"/\"Soak Agent\"/" \
  tools/fixtures/fake-agent.json >"$H/registry/agents/soak-agent.json"
python3 tools/validate_row.py "$H/registry/agents/soak-agent.json" >/dev/null 2>&1 || { echo "soak: the fixture row fails the validator" >&2; exit 1; }

STARTED=$(date +%s); touch "$OUT/.started"
{ date -u +%Y-%m-%dT%H:%M:%SZ; sw_vers -productVersion; sysctl -n hw.model hw.ncpu; uptime; git rev-parse --short HEAD; } >"$OUT/host.txt"
env MINMACS_HOME="$H" MINMACS_ROOTS="$H/code" CLAUDE_CONFIG_DIR="$H/claude" CODEX_HOME="$H/codex" \
  PI_CODING_AGENT_SESSION_DIR="$H/pi" GIT_CONFIG_GLOBAL=/dev/null \
  MINMACS_CLAUDE=/usr/bin/false MINMACS_CODEX=/usr/bin/false MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false \
  "$H/bin/$SOAK" run --seconds $((SECS + 600)) --menus-every "${SOAK_MENUS_EVERY:-60}" --status "$OUT/status.jsonl" >"$OUT/summary.json" 2>"$OUT/soak.err" &
SP=$!

# Every process of this run: the soak, its walker child, the servers and the agents. Each name carries the tag.
tagged() { ps -axo pid=,command= | grep -E -- "$MARK" | grep -v grep | awk '$1 > 1 {print $1}'; }
cleanup() {
  for f in "$H"/pids/servers/* "$H"/pids/agents/*; do [ -e "$f" ] && stop_pid "${f##*/}"; done
  ours "$SP" && kill "$SP" 2>/dev/null
  sleep 1
  for p in $(tagged); do [ "$p" != $$ ] && stop_pid "$p"; done
  rm -rf "$H"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

PY='import http.server, os, sys, threading
os.setsid()   # a session of its own, test rule 5
open(os.path.join(sys.argv[2], str(os.getpid())), "w").write(os.getcwd())
threading.Timer(float(sys.argv[3]), lambda: os._exit(0)).start()   # ends by itself if the soak script dies
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), http.server.SimpleHTTPRequestHandler).serve_forever()'
LIFE=$((CHURN * 12 + 120))
PORT=$((40000 + $$ % 8000))
free_port() { while nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; do PORT=$((PORT + 1)); [ "$PORT" -gt 49900 ] && PORT=40000; done; }

made=0; removed=0; started_servers=0; stopped_servers=0; started_agents=0; stopped_agents=0; i=0
oldest() { ls -tr "$1" 2>/dev/null | head -1; }
count() { ls "$1" 2>/dev/null | grep -c .; }

churn() {
  i=$((i + 1))
  # A worktree with a commit, and the oldest past SOAK_KEEP removed, with the servers inside it stopped first.
  G -C "$A" worktree add -q -b "b$i" "$W/wt$i" main 2>/dev/null &&
    ( cd "$W/wt$i" && echo "$i" >"f$i.txt" && G add -A && G commit -qm "work $i" ) && made=$((made + 1))
  while [ "$(ls "$W" | grep -c .)" -gt "${SOAK_KEEP:-4}" ]; do
    old=$(ls "$W" | sed 's/^wt//' | sort -n | head -1)
    for f in "$H"/pids/servers/*; do
      [ -e "$f" ] && [ "$(cat "$f")" = "$W/wt$old" ] && { stop_pid "${f##*/}"; rm -f "$f"; stopped_servers=$((stopped_servers + 1)); }
    done
    G -C "$A" worktree remove --force "$W/wt$old" 2>/dev/null; G -C "$A" branch -q -D "b$old" 2>/dev/null
    [ -d "$W/wt$old" ] && rm -rf "$W/wt$old"
    removed=$((removed + 1))
  done
  # A server in the newest worktree, and the oldest past SOAK_KEEP stopped. Its pid file may come a step later.
  free_port
  ( ( cd "$W/wt$i" && exec python3 -c "$PY" "$PORT" "$H/pids/servers" "$LIFE" "mmsoak-$TAG" ) >/dev/null 2>&1 & )
  PORT=$((PORT + 1)); started_servers=$((started_servers + 1))
  while [ "$(count "$H/pids/servers")" -gt "${SOAK_KEEP:-3}" ]; do
    f=$(oldest "$H/pids/servers"); stop_pid "$f"; rm -f "$H/pids/servers/$f"; stopped_servers=$((stopped_servers + 1))
  done
  # A fake agent with a session file and a transcript, and the oldest past SOAK_KEEP stopped with its files.
  "$H/bin/$AGENT" "$LIFE" "$TAG" >/dev/null 2>&1 &
  ap=$!; started_agents=$((started_agents + 1))
  proj="$H/claude/projects/$(printf %s "$W/wt$i" | tr '/.' '--')"; mkdir -p "$proj"
  printf '%s\n' "$proj" >"$H/pids/agents/$ap"
  now=$(date +%s)
  printf '{"pid":%s,"sessionId":"soak-%s","cwd":"%s","startedAt":%s000,"version":"2.1.311","kind":"interactive","status":"idle","statusUpdatedAt":%s000}\n' \
    "$ap" "$ap" "$W/wt$i" "$now" "$now" >"$H/claude/sessions/$ap.json"
  printf '{"type":"user","sessionId":"soak-%s","cwd":"%s","timestamp":"%s","message":{"role":"user","content":"step %s"}}\n' \
    "$ap" "$W/wt$i" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$i" >"$proj/soak-$ap.jsonl"
  while [ "$(count "$H/pids/agents")" -gt "${SOAK_KEEP:-3}" ]; do
    f=$(oldest "$H/pids/agents"); proj=$(cat "$H/pids/agents/$f")
    stop_pid "$f"; wait "$f" 2>/dev/null
    rm -f "$H/pids/agents/$f" "$H/claude/sessions/$f.json" "$proj/soak-$f.jsonl"; rmdir "$proj" 2>/dev/null
    stopped_agents=$((stopped_agents + 1))
  done
  for f in "$H"/pids/agents/*; do
    [ -e "$f" ] || continue
    printf '{"type":"assistant","sessionId":"soak-%s","timestamp":"%s","message":{"role":"assistant","content":"ok %s"}}\n' \
      "${f##*/}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$i" >>"$(cat "$f")/soak-${f##*/}.jsonl"
  done
  # A server or agent that ended by itself leaves its pid file. It is gone, so the file goes too.
  for f in "$H"/pids/servers/* "$H"/pids/agents/*; do [ -e "$f" ] && ! ours "${f##*/}" && rm -f "$f"; done
}

# One sample: procstat, then leaks(1) on the soak process. leaks suspends it while it reads its heap.
n=0
sample() {
  n=$((n + 1))
  st=$("$PROCSTAT" "$SP" 2>/dev/null) || st='null'
  t0=$(date +%s)
  leaks "$SP" >"$OUT/leaks-$n.txt" 2>&1; lr=$?
  t1=$(date +%s)
  line=$(grep -E '^Process [0-9]+: [0-9]+ leaks? for' "$OUT/leaks-$n.txt" | head -1)
  python3 - "$n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$((t0 - STARTED))" "$st" "$lr" "$t0" "$t1" "$line" >>"$OUT/samples.jsonl" <<'PYEOF'
import json, re, sys
n, at, el, st, rc, t0, t1, line = sys.argv[1:]
secs = int(t1) - int(t0)
m = re.search(r": (\d+) leaks? for (\d+) total", line)
print(json.dumps({"n": int(n), "at": at, "elapsed": int(el), "proc": json.loads(st), "leaksExit": int(rc),
                  "leaksSeconds": secs, "leaksFrom": int(t0), "leaksTo": int(t1), "leaks": int(m.group(1)) if m else None,
                  "leakedBytes": int(m.group(2)) if m else None}, sort_keys=True))
PYEOF
}

: >"$OUT/samples.jsonl"
WARM=$((SECS / 10)); [ "$WARM" -gt 120 ] && WARM=120
END=$((STARTED + SECS)); NEXT=$((STARTED + WARM)); died=""
while [ "$(date +%s)" -lt "$END" ]; do
  ours "$SP" || { died="the soak process ended at $(( $(date +%s) - STARTED )) s"; break; }
  # The soak, its walker, at most 4 servers and 4 agents. Many more means something spawns without end: stop.
  nt=$(tagged | grep -c .); [ "$nt" -gt 20 ] && { died="$nt processes carry the tag at $(( $(date +%s) - STARTED )) s"; break; }
  churn
  now=$(date +%s)
  if [ "$now" -ge "$NEXT" ] && [ "$((END - now))" -gt "$CHURN" ]; then sample; NEXT=$((NEXT + EVERY)); fi
  left=$((END - $(date +%s))); [ "$left" -le 0 ] && break
  sleep $((left < CHURN ? left : CHURN))
done
[ -z "$died" ] && sample

# Stop: the fixtures first, then the soak with SIGTERM, which writes its summary.
for f in "$H"/pids/servers/*; do [ -e "$f" ] && { stop_pid "${f##*/}"; rm -f "$f"; stopped_servers=$((stopped_servers + 1)); }; done
for f in "$H"/pids/agents/*; do [ -e "$f" ] && { stop_pid "${f##*/}"; wait "${f##*/}" 2>/dev/null; rm -f "$f"; stopped_agents=$((stopped_agents + 1)); }; done
sexit=""
if [ -z "$died" ]; then ours "$SP" && kill -TERM "$SP"; fi
wait "$SP"; sexit=$?
sleep 1
left=0; for p in $(tagged); do [ "$p" != $$ ] && left=$((left + 1)); done

# Crash, hang and spin reports of this run's processes, read only.
: >"$OUT/reports.txt"
for d in "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports; do
  [ -d "$d" ] || continue
  find "$d" -newer "$OUT/.started" \( -name "$SOAK*" -o -name "$AGENT*" -o -name "*mmsoak*$TAG*" \) 2>/dev/null >>"$OUT/reports.txt"
done

python3 - "$OUT" >"$OUT/churn.json" <<PYEOF
import json
print(json.dumps({"steps": $i, "worktreesMade": $made, "worktreesRemoved": $removed,
  "serversStarted": $started_servers, "serversStopped": $stopped_servers,
  "agentsStarted": $started_agents, "agentsStopped": $stopped_agents,
  "fixturesLeft": $left, "soakExit": int("${sexit:-1}"), "died": "$died", "seconds": $SECS,
  "sampleEvery": $EVERY, "churnEvery": $CHURN, "tag": "$TAG"}, sort_keys=True))
PYEOF
python3 tools/soak/report.py "$OUT" >"$OUT/report.md"; r=$?
cat "$OUT/report.md"
echo "results in $OUT"
exit "$r"
