# The soak, issue #56, in a short run. Sourced by test.sh after core.
# tools/soak/run.sh runs Core headless with every built-in expert, every mode Idle, the watchdog on and every menu
# opened on the live snapshot, beside fixture churn: worktrees made and removed in a fixture repo, Python servers on
# high ports, fake agents with session files and transcripts. It samples the process with procstat and leaks(1).
# Here it runs 30 seconds, a sample every 8, a churn step every 5 and two of each fixture alive at once, with its home under this run's MINMACS_HOME.
# So each server and agent lives about 10 seconds, two Senses passes, and the graph holds it when the soak reads it.
# Every fixture carries a tag unique to the run, and run.sh stops each by its pid after ps shows that tag.
# The 24-hour run and the week of real use are in docs/2.0/BENCH.md, section Soak.

sk="$MINMACS_HOME/soak"
sk_t0=$(date +%s)
mkdir -p "$sk/tmp" "$sk/refuse"
# The bench section, which runs before this one, built the same Sources at -O2. Its objects are linked here, so only
# soak.m compiles. Run alone, the soak builds everything.
sk_dir=$(SOAK_OBJS="$MINMACS_HOME/bench/bench/obj" BUILD_DIR="$sk" tools/soak/build.sh 2>"$sk/build.err"); sk_r=$?
check "soak: the soak, procstat and the fake agent build" 0 "$sk_r"
check "soak: the build has no warnings" 0 "$(cat "$sk/soak/clang.log" "$sk/build.err" 2>/dev/null | grep -c 'warning:')"
[ "$sk_r" = 0 ] || tail -20 "$sk/build.err"
sk_bin="$sk_dir/soak"

# It refuses to run where it could reach a real model, cmux, tmux, repo or support folder.
sk_env() {
  env MINMACS_HOME="$sk/refuse" MINMACS_ROOTS="$sk/refuse/code" CLAUDE_CONFIG_DIR="$sk/refuse/claude" CODEX_HOME="$sk/refuse/codex" \
    MINMACS_CLAUDE=/usr/bin/false MINMACS_CODEX=/usr/bin/false MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false "$@"
}
for sk_var in MINMACS_HOME MINMACS_ROOTS MINMACS_CLAUDE MINMACS_CODEX MINMACS_CMUX MINMACS_TMUX CLAUDE_CONFIG_DIR; do
  sk_env env -u "$sk_var" "$sk_bin" run --seconds 1 >/dev/null 2>"$sk/refuse.err"
  check "soak: it refuses to run without $sk_var" "2 1" "$? $(grep -c "$sk_var" "$sk/refuse.err")"
done
sk_env env MINMACS_ROOTS=/ "$sk_bin" run --seconds 1 >/dev/null 2>"$sk/refuse.err"
check "soak: it refuses repo roots outside MINMACS_HOME" "2 1" "$? $(grep -c 'MINMACS_ROOTS must lie' "$sk/refuse.err")"
sk_env env MINMACS_CLAUDE=/bin/echo "$sk_bin" run --seconds 1 >/dev/null 2>"$sk/refuse.err"
check "soak: it refuses a model CLI that is not a fake" "2 1" "$? $(grep -c 'MINMACS_CLAUDE must be' "$sk/refuse.err")"
sk_env env MINMACS_HOME="$HOME/Library/Application Support/MinMacs" "$sk_bin" run --seconds 1 >/dev/null 2>"$sk/refuse.err"
check "soak: it refuses the real support folder" "2 1" "$? $(grep -c 'real support folder' "$sk/refuse.err")"
# Core's worker starts this binary again as _walk. Before the soak answered it, each child ran a whole soak and
# started its own child, without end. Any other word only prints the usage.
sk_env "$sk_bin" --seconds 1 >/dev/null 2>"$sk/refuse.err"
check "soak: without the run verb it prints the usage and starts nothing" "2 1" "$? $(grep -c '^usage: soak run' "$sk/refuse.err")"
sk_env "$sk_bin" _walk </dev/null >/dev/null 2>&1
check "soak: _walk is the walker child, which ends when its input ends" 0 "$?"
check "soak: the soak signals, quits and stops nothing" 0 "$(grep -cE 'kill\(|MMStop\(|MMQuitApps\(|MMRunAction\(|[Tt]erminate' tools/soak/soak.m)"
check "soak: run.sh signals only pids it checked" 0 "$(grep -n 'kill ' tools/soak/run.sh | grep -vc 'stop_pid()\|ours "\$SP" && kill')"

# The short run.
sk_start=$(date +%s)
TMPDIR="$sk/tmp" SOAK_DIR="$sk_dir" SOAK_MENUS_EVERY=5 SOAK_KEEP=2 tools/soak/run.sh 30 8 5 "$sk/run" >"$sk/run.out" 2>"$sk/run.err"
sk_r=$?
sk_secs=$(( $(date +%s) - sk_start ))
check "soak: the short run passes its own report" 0 "$sk_r"
[ "$sk_r" = 0 ] || { grep -E 'FAIL|ended|carry' "$sk/run.out"; tail -5 "$sk/run.err"; }
check "soak: the short run takes under 60 seconds" yes "$([ "$sk_secs" -lt 60 ] && echo yes || echo "$sk_secs s")"
ss() { python3 -c "import json,sys; j=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print($1)" "$sk/run/samples.jsonl" 2>/dev/null; }
sm() { json "$1" <"$sk/run/summary.json" 2>/dev/null; }
sc() { json "$1" <"$sk/run/churn.json" 2>/dev/null; }
# On a loaded Mac one leaks(1) read can take 15 seconds and hold up the churn, so the counts asked for are small.
check "soak: at least two samples, each with footprint, CPU, threads and fds" yes \
  "$(ss '"yes" if len(j) >= 2 and all(s["proc"] and s["proc"]["footprintBytes"] > 0 and s["proc"]["threads"] > 0 and s["proc"]["fds"] > 0 for s in j) else j')"
check "soak: leaks(1) ran on every sample" yes "$(ss '"yes" if all(s["leaksExit"] in (0, 1) and s["leaks"] is not None for s in j) else [(s["leaksExit"], s["leaks"]) for s in j]')"
check "soak: the report finds no leak in MinMacs code" 1 "$(grep -c '^| no leak in MinMacs code | pass |' "$sk/run/report.md")"
check "soak: five experts ran, every mode Idle, nothing acted" "5 [] 0" "$(sm '"%d %s %d" % (j["experts"], j["notIdle"], j["undoRecords"])')"
check "soak: no awake hold, so the Mac sleeps as before" 0 "$(sm 'j["peakAwakeHolds"]')"
check "soak: the menus opened on the live snapshot with cards hovered" yes "$(sm '"yes" if j["menuRounds"] >= 2 and j["cardsHovered"] > 0 else (j["menuRounds"], j["cardsHovered"])')"
check "soak: worktrees were made and removed" yes "$(sc '"yes" if j["worktreesMade"] >= 2 and j["worktreesRemoved"] >= 1 else j')"
check "soak: every server and agent started was stopped" yes \
  "$(sc '"yes" if j["serversStarted"] >= 2 and j["serversStarted"] == j["serversStopped"] and j["agentsStarted"] >= 2 and j["agentsStarted"] == j["agentsStopped"] else j')"
check "soak: no process of the run is left" 0 "$(sc 'j["fixturesLeft"]')"
# On the GitHub runner Senses holds the fixture server's process but reads no socket for it, so LocoHost has no
# server to show (issue #56). There the LocoHost part is printed and not gated. On a Mac it is gated.
sk_lh=1; [ -n "${CI:-}" ] && sk_lh=0
check "soak: the graph saw the fixture servers, worktrees, agents and sessions" yes \
  "$(sm '"yes" if (j["peakFixtureFindings"].get("locohost", 0) >= 1 or '"$sk_lh"' == 0) and j["peakFixtureFindings"].get("workforest", 0) >= 1 and j["peakAgents"] >= 1 and j["peakSessions"] >= 1 else (j["peakFixtureFindings"], j["peakAgents"], j["peakSessions"])')"
[ "$sk_lh" = 0 ] && echo "  soak on CI: LocoHost fixture findings at peak $(sm 'j["peakFixtureFindings"].get("locohost", 0)'), not gated here"
# When the fixture check fails, what the soak saw: its last status lines, the churn counts and its errors.
if [ "$(sm '"yes" if j["peakFixtureFindings"].get("locohost", 0) >= 1 and j["peakAgents"] >= 1 else "no"')" != yes ]; then
  tail -3 "$sk/run/status.jsonl" 2>/dev/null | cut -c1-400 | sed 's/^/    status /'
  cut -c1-400 "$sk/run/churn.json" 2>/dev/null | sed 's/^/    churn /'
  tail -5 "$sk/run.err" "$sk/run/soak.err" 2>/dev/null | cut -c1-300 | sed 's/^/    err /'
  for e in "$sk"/run/logs/server-*.err; do [ -s "$e" ] && tail -3 "$e" | cut -c1-300 | sed "s|^|    server ${e##*/} |"; done
fi
check "soak: the home of the run is removed" 0 "$(ls "$sk/tmp" | grep -c .)"

# The report fails a run with a MinMacs leak, a stall outside a leaks window, a crash report or a fixture left.
# The leak is the real cycle of issue #56: LocoHost's and WorkForest's views held the snapshot that held them.
mkdir -p "$sk/bad"
cp test/soak/leaky.txt "$sk/bad/leaks-1.txt"; cp test/soak/leaky.txt "$sk/bad/leaks-2.txt"
cp "$sk/run/host.txt" "$sk/bad/" 2>/dev/null
printf '{"n": 1, "elapsed": 10, "proc": {"footprintBytes": 10485760, "peakFootprintBytes": 10485760, "residentBytes": 1, "cpuNs": 1, "threads": 6, "fds": 25}, "leaksExit": 1, "leaks": 875, "leakedBytes": 1, "leaksSeconds": 2, "leaksFrom": 1000, "leaksTo": 1002}\n{"n": 2, "elapsed": 20, "proc": {"footprintBytes": 10485760, "peakFootprintBytes": 10485760, "residentBytes": 1, "cpuNs": 2, "threads": 6, "fds": 25}, "leaksExit": 1, "leaks": 875, "leakedBytes": 1, "leaksSeconds": 2, "leaksFrom": 2000, "leaksTo": 2002}\n' >"$sk/bad/samples.jsonl"
printf '{"stoppedBy": "SIGTERM", "notIdle": [], "undoRecords": 0, "peakAwakeHolds": 0, "stalls": [{"ms": 300, "cpuMs": 280, "at": 1500, "what": "fixture"}, {"ms": 900, "cpuMs": 0, "at": 2002, "what": "fixture"}, {"ms": 500, "cpuMs": 2, "state": "runs", "at": 1700, "what": "fixture"}]}\n' >"$sk/bad/summary.json"
printf '{"died": "", "soakExit": 0, "fixturesLeft": 2, "seconds": 20, "sampleEvery": 10, "churnEvery": 3, "tag": "fixture"}\n' >"$sk/bad/churn.json"
printf 'mmsoakfixture-2026-10-28-000000.ips\n' >"$sk/bad/reports.txt"
python3 tools/soak/report.py "$sk/bad" >"$sk/bad/report.md"
check "soak: the report fails that run" 1 "$?"
sk_row() { grep "^| $1 |" "$sk/bad/report.md" | cut -d'|' -f3 | tr -d ' '; }
check "soak: it counts the cycle as MinMacs's and the XPC connection as the system's" "FAIL pass" "$(sk_row 'no leak in MinMacs code') $(sk_row 'system framework leak trees do not grow')"
check "soak: a stall outside a leaks window fails, one inside it is listed apart" "FAIL 1" \
  "$(sk_row 'no pass of main over 50 ms') $(grep '^| passes over 50 ms while leaks' "$sk/bad/report.md" | cut -d'|' -f4 | cut -d: -f1 | tr -d ' ')"
check "soak: a pass in which main waited for a core is listed apart" 1 \
  "$(grep '^| passes over 50 ms in which main waited' "$sk/bad/report.md" | cut -d'|' -f4 | cut -d: -f1 | tr -d ' ')"
check "soak: a crash report and a fixture left fail" "FAIL FAIL" "$(sk_row 'no crash, hang or spin report') $(sk_row 'no fixture left running')"
printf '    soak: %s\n' "$(ss '"; ".join("%d s %.2f MB %d threads %d fds %s leaks" % (s["elapsed"], s["proc"]["footprintBytes"] / 1048576, s["proc"]["threads"], s["proc"]["fds"], s["leaks"]) for s in j)')"
printf '    soak: the section took %s s\n' "$(( $(date +%s) - sk_t0 ))"
