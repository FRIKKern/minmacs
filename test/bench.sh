# The bench and its regression gate, issues #23 and #51. Sourced by test.sh after core.
# tools/bench/build.sh builds tools/bench/bench.m with every .m under Sources except main.m, at -O2 as the app.
# A short idle run starts Core with the built-in experts in one process, without status items, with every mode
# Idle in its own MINMACS_HOME. Senses reads the real process table, and nothing acts. The model, cmux and tmux
# CLIs are /usr/bin/false. The old apps are read with proc_pid_rusage and ps, and never signaled.
# Then the menus build from fixture snapshots, the app launches headless twice, and the watchdog watches main while
# every expert's menu opens and its cards are hovered. tools/bench/gate.py checks them against tools/bench/budgets.json.
# The idle run and the menu run take about 55 seconds together, the rest about 15. MM_BENCH_STRICT=1 gates on the
# phase 6 budgets.

bn="$MINMACS_HOME/bench"
mkdir -p "$bn/home"
bn_bin=$(BUILD_DIR="$bn" tools/bench/build.sh 2>"$bn/build.err"); bn_r=$?
check "bench: the bench builds" 0 "$bn_r"
check "bench: the bench has no warnings" 0 "$(cat "$bn/bench/clang.log" "$bn/build.err" 2>/dev/null | grep -c 'warning:')"
[ "$bn_r" = 0 ] || tail -20 "$bn/build.err"
# MINMACS_NO_BACKOFF=1 keeps the 5-second pass on battery and while the person is away, so the window holds as many
# ticks as on a Mac in use, issue #52.
bn_env() {
  env MINMACS_HOME="$bn/home" CLAUDE_CONFIG_DIR="$bn/home/claude" CODEX_HOME="$bn/home/codex" \
    PI_CODING_AGENT_SESSION_DIR="$bn/home/pi" MINMACS_NO_BACKOFF=1 \
    MINMACS_CLAUDE=/usr/bin/false MINMACS_CODEX=/usr/bin/false MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false "$@"
}

# The bench never runs where it could reach a real model, cmux, tmux or support folder.
# Each refusal runs with every other variable set to its fake, so only the one under test can cause it.
for bn_var in MINMACS_HOME MINMACS_CLAUDE MINMACS_CODEX MINMACS_CMUX MINMACS_TMUX; do
  bn_env env -u "$bn_var" "$bn_bin" idle --seconds 1 >/dev/null 2>"$bn/refuse.err"
  check "bench: it refuses to run without $bn_var" "2 1" "$? $(grep -c "$bn_var" "$bn/refuse.err")"
done
# A CLI path outside MINMACS_HOME could be the real one. /bin/echo stands in for it and is never run.
bn_env env MINMACS_CLAUDE=/bin/echo "$bn_bin" idle --seconds 1 >/dev/null 2>"$bn/refuse.err"
check "bench: it refuses a model CLI that is not a fake" "2 1" "$? $(grep -c 'MINMACS_CLAUDE must be' "$bn/refuse.err")"
bn_env env MINMACS_ROOTS=/ "$bn_bin" menus --iterations 1 >/dev/null 2>"$bn/refuse.err"
check "bench: it refuses repo roots outside MINMACS_HOME" "2 1" "$? $(grep -c 'MINMACS_ROOTS' "$bn/refuse.err")"
bn_env env MINMACS_HOME="$HOME/Library/Application Support/MinMacs" "$bn_bin" menus --iterations 1 >/dev/null 2>"$bn/refuse.err"
check "bench: it refuses the real support folder" "2 1" "$? $(grep -c 'real support folder' "$bn/refuse.err")"
check "bench: it signals, quits and stops nothing" 0 "$(grep -cE 'kill\(|MMStop\(|MMQuitApps\(|MMRunAction\(|[Tt]erminate' tools/bench/bench.m)"

bn_start=$(date +%s)
bn_env "$bn_bin" idle --warmup 6 --seconds 30 --tick-runs 8 >"$bn/idle.json" 2>"$bn/idle.err"
check "bench: the idle run exits 0" 0 "$?"
bn_env "$bn_bin" menus --iterations 40 >"$bn/menus.json" 2>"$bn/menus.err"
check "bench: the menu run exits 0" 0 "$?"
bn_secs=$(( $(date +%s) - bn_start ))
# Five experts with menu fixtures hover about 50 cards a turn, about 7 ms each, so the menu run takes about 17 s.
check "bench: the idle and menu runs finish in under 75 seconds" yes "$([ "$bn_secs" -lt 75 ] && echo yes || echo "$bn_secs s")"

bi() { json "$1" <"$bn/idle.json" 2>/dev/null; }
bm() { json "$1" <"$bn/menus.json" 2>/dev/null; }
bn_linked=$(bi 'len(j["expertIDs"])')
check "bench: every linked built-in expert runs" yes "$(bi '"yes" if j["experts"] >= 2 and "minmacs" in j["expertIDs"] and "locohost" in j["expertIDs"] else j["expertIDs"]')"
check "bench: every mode is Idle and nothing acted" "idle 0" "$(bi '"%s %d" % (j["modes"], j["undoRecords"])')"
check "bench: the window is 30 seconds" yes "$(bi '"yes" if 29.5 <= j["windowSeconds"] <= 32 else j["windowSeconds"]')"
# An exit of a watched process adds a sample of its own, so gaps can be shorter, never longer.
check "bench: Senses samples at least every 5 seconds in the window" yes "$(bi '"yes" if j["samples"] >= 5 and j["tickSeconds"]["max"] <= 6.5 else (j["samples"], j["tickSeconds"])')"
# Issue #52: a sample whose facts did not change is skipped, so each sample gives a build or a skip.
check "bench: each sample gives a rebuild or a skip" yes "$(bi '"yes" if j["graph"]["builds"] + j["graph"]["skipped"] >= j["samples"] - 1 else (j["graph"], j["samples"])')"
check "bench: the 5-second pass held without backoff" "off 5 s, base" "$(bi '"%s %s" % (j["backoff"], j["senses"]["interval"])')"
check "bench: the window counts each expert's findings cost" "$bn_linked" "$(bi 'sum(1 for k in j["graph"]["perBuildCPUms"] if k.startswith("findings."))')"
check "bench: the pass carried args, cwds and sockets" yes "$(bi '"yes" if j["senses"]["argsCarriedPerPass"] > 50 and j["senses"]["socketPidsCarriedPerPass"] > 0 else j["senses"]')"
check "bench: the session index read its folders at most once a minute" yes "$(bi '"yes" if j["graph"]["sessionReads"] <= j["windowSeconds"] / 60 + 1 else j["graph"]')"
check "bench: the pass reads the real process table" yes "$(bi '"yes" if j["pids"] > 50 else j["pids"]')"
check "bench: the tick is timed alone too" 8 "$(bi 'j["tickCost"]["passes"]')"
check "bench: each expert's findings are timed alone" "$bn_linked" "$(bi 'len(j["tickCost"]["parts"]["findingsCPUms"])')"
check "bench: the registry and each expert's findings are timed again on the same sample" "$bn_linked 8" "$(bi '"%d %d" % (len(j["tickCost"]["parts"]["findingsWarmCPUms"]), j["tickCost"]["parts"]["registryAgentsWarmCPUms"]["n"])')"
check "bench: the old apps are read over the same window" yes "$(bi '"yes" if all("error" in a or a["cpuSeconds"] >= 0 for a in j["oldApps"]) else j["oldApps"]')"
# Every linked expert has a menu fixture in tools/bench/bench.m, issue #53.
check "bench: every linked expert's menu is built 40 times with rows" "$bn_linked" "$(bm 'sum(1 for e in j["experts"].values() if e["menuOpenMs"]["n"] == 40 and e["rows"] > 0)')"
check "bench: every linked expert has its cards timed" "$bn_linked" "$(bm 'sum(1 for e in j["experts"].values() if e["cards"] > 0 and e["cardHoverMs"]["n"] >= 40)')"
check "bench: every linked expert has what the graph queue prepares timed" "$bn_linked" "$(bm 'sum(1 for e in j["experts"].values() if e["prepareMs"]["n"] == 40)')"
# A menu opens with no card built. Each card is built when its row is hovered, and the menu then holds the same items
# as one with every card built up front.
check "bench: a menu opens with no card built" 0 "$(bm 'j["cardsBuiltAtOpen"]')"
check "bench: every hover built its card" yes "$(bm '"yes" if j["cardsBuiltOnHover"] >= sum(e["cards"] for e in j["experts"].values()) * 40 else j["cardsBuiltOnHover"]')"
check "bench: each menu with hovered cards is the menu with every card built" "$bn_linked 0" "$(bm '"%d %d" % (len(j["sameAsCardsUpFront"]), len(j["differFromCardsUpFront"]))')"
# Main reads what the snapshot holds: no log query and no keeps file read on main while menus open and cards build.
check "bench: menus and cards run no log query on main" 0 "$(bm 'j["logQueriesOnMain"]')"
check "bench: menus and cards read no keeps file on main" 0 "$(bm 'j["keepReadsOnMain"]')"
check "bench: menu open under 30 ms at p95 for every expert" yes "$(bm '"yes" if all(e["menuOpenMs"]["p95"] < 30 for e in j["experts"].values()) else {k: e["menuOpenMs"]["p95"] for k, e in j["experts"].items()}')"
check "bench: card hover under 16 ms at p95 for every expert" yes "$(bm '"yes" if all(e["cardHoverMs"]["p95"] < 16 for e in j["experts"].values()) else {k: e["cardHoverMs"]["p95"] for k, e in j["experts"].items()}')"

# Startup, issue #55: the app's launch headless, twice in one home. The first is a first launch. In the second, an
# expert whose field was empty in the first starts with no item, and every other one is made at launch.
mkdir -p "$bn/start"
bn_start_env() { env MINMACS_HOME="$bn/start" CLAUDE_CONFIG_DIR="$bn/start/claude" CODEX_HOME="$bn/start/codex" \
    MINMACS_CLAUDE=/usr/bin/false MINMACS_CODEX=/usr/bin/false MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false "$@"; }
bn_start_env "$bn_bin" startup >"$bn/startup-first.json" 2>"$bn/startup-first.err"
check "bench: the first headless launch exits 0" 0 "$?"
bn_start_env "$bn_bin" startup >"$bn/startup-later.json" 2>"$bn/startup-later.err"
check "bench: the later headless launch exits 0" 0 "$?"
bsf() { json "$1" <"$bn/startup-first.json" 2>/dev/null; }
bsl() { json "$1" <"$bn/startup-later.json" 2>/dev/null; }
check "bench: the first launch makes every expert's item" "True $bn_linked" "$(bsf '"%s %d" % (j["firstLaunch"], len(j["times"]["made"]))')"
bn_empty=$(bsf '",".join(sorted(k for k, v in j["fieldEmpty"].items() if v))')
check "bench: the later launch leaves the experts with an empty field for later" "False $bn_empty" \
  "$(bsl '"%s %s" % (j["firstLaunch"], ",".join(sorted(j["times"]["deferred"])))')"
bn_full=$(bsf '",".join(sorted(k for k, v in j["fieldEmpty"].items() if not v))')
check "bench: the later launch makes every item whose field was full" "$bn_full" "$(bsl '",".join(sorted(j["times"]["made"]))')"
check "bench: every expert has a summary line on both launches" "$bn_linked $bn_linked" \
  "$(bsf 'sum(1 for k in j["experts"] if "summary." + k in j["times"])') $(bsl 'sum(1 for k in j["experts"] if "summary." + k in j["times"])')"
check "bench: items within 300 ms and summaries within 5 s, both launches" yes \
  "$(python3 -c 'import json,sys; r=[json.load(open(f))["times"] for f in sys.argv[1:]]; print("yes" if all(t["items"] <= 300 and t["summaries"] <= 5000 for t in r) else r)' "$bn/startup-first.json" "$bn/startup-later.json")"
printf '    startup: %s\n' "$(python3 -c 'import json,sys; print("; ".join("%s launch: core %s ms, items %s ms, first snapshot %s ms, every summary %s ms, %d made, %d left for later" % ("first" if x["firstLaunch"] else "later", x["times"]["core"], x["times"]["items"], x["times"]["snapshot"], x["times"]["summaries"], len(x["times"]["made"]), len(x["times"]["deferred"])) for x in [json.load(open(f)) for f in sys.argv[1:]]))' "$bn/startup-first.json" "$bn/startup-later.json")"

# Hang detection, issue #55: every expert's menu opens and every card hover, each a pass of main of its own, with Core
# running, under the main-thread watchdog. It first catches a 120 ms stall made on purpose, with its function named.
bn_env "$bn_bin" hangs --rounds 4 >"$bn/hangs.json" 2>"$bn/hangs.err"
check "bench: the watchdog run exits 0 and finishes" "0 True" "$? $(json 'j["finished"]' <"$bn/hangs.json" 2>/dev/null)"
bh() { json "$1" <"$bn/hangs.json" 2>/dev/null; }
check "bench: the watchdog catches a stall made on purpose, with its stack" "yes True" "$(bh '"yes" if j["selfCheck"]["ms"] >= 100 else j["selfCheck"]["ms"]') $(bh 'j["selfCheck"]["named"]')"
check "bench: the watchdog opens every expert's menu" "$bn_linked" "$(bh 'sum(1 for v in j["opensBy"].values() if v >= 4)')"
check "bench: the watchdog hovers every expert's cards" "$bn_linked" "$(bh 'sum(1 for v in j["hoversBy"].values() if v >= 4)')"
check "bench: the menus opened on Core's live snapshots too" yes "$(bh '"yes" if j["liveOpens"] >= 4 * len(j["opensBy"]) else j["liveOpens"]')"
check "bench: no pass of main over 50 ms in menu opens and card hovers" 0 "$(bh 'len(j["stalls"])')"
[ "$(bh 'len(j["stalls"])')" = 0 ] || bh '"\n".join("    stall %s ms, %s ms CPU, %s, in %s" % (s["ms"], s["cpuMs"], s["state"], s["what"]) for s in j["stalls"])'
check "bench: the watchdog run ran no log query on main" 0 "$(bh 'j["logQueriesOnMain"]')"
# A debug build turns the watchdog on, and MMMain starts it then.
check "bench: DEBUG=1 ./build.sh defines MM_DEBUG, which turns the watchdog on" "1 1 1" \
  "$(grep -c 'DEBUG:-}" = 1 ] && OPT="-O0 -g -DMM_DEBUG"' build.sh) $(grep -c '#ifdef MM_DEBUG' Sources/Shell/MMWatchdog.m) $(grep -c 'MMWatchdogWanted(NSProcessInfo' Sources/Shell/MMShell.m)"
printf '    idle: %s\n' "$(bi '"%.3f %% CPU, %.2f MB footprint, %.2f MB resident, %.3f wakeups/s, %s pids; rebuild %.1f ms CPU median" % (j["cpuPercent"], j["footprintMB"], j["residentMB"], j["interruptWakeupsPerSecond"], j["pids"], j["inWindow"]["rebuildCPUms"]["median"])')"
printf '    menus: %s\n' "$(bm '", ".join("%s open p95 %.1f ms, hover p95 %.1f ms" % (k, e["menuOpenMs"]["p95"], e["cardHoverMs"]["p95"]) for k, e in sorted(j["experts"].items()))')"

# The gate. A budget over the phase 6 number but under today's ceiling prints as over and passes.
bn_strict=""; [ "${MM_BENCH_STRICT:-}" = 1 ] && bn_strict=--strict
python3 tools/bench/gate.py $bn_strict tools/bench/budgets.json "$bn/idle.json" "$bn/menus.json" \
  "$bn/startup-first.json" "$bn/startup-later.json" "$bn/hangs.json" >"$bn/gate.txt"
bn_gate=$?
bn_tab=$(printf '\t')
while IFS="$bn_tab" read -r word what value budget ceiling; do
  case "$word" in
    skip) printf '    gate: skip  %s, %s\n' "$what" "$value" ;;
    over) printf '    gate: over  %s at %s, %s, %s\n' "$what" "$value" "$budget" "$ceiling"; check "bench gate: $what, under the ceiling" ok ok ;;
    ok) check "bench gate: $what, $value" ok ok ;;
    *) check "bench gate: $what" ok "$word $value, $ceiling" ;;
  esac
done <"$bn/gate.txt"
check "bench: the gate passes" 0 "$bn_gate"
