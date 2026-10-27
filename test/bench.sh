# The bench and its regression gate, issues #23 and #51. Sourced by test.sh after core.
# tools/bench/build.sh builds tools/bench/bench.m with every .m under Sources except main.m, at -O2 as the app.
# A short idle run starts Core with the built-in experts in one process, without status items, with every mode
# Idle in its own MINMACS_HOME. Senses reads the real process table, and nothing acts. The model, cmux and tmux
# CLIs are /usr/bin/false. The old apps are read with proc_pid_rusage and ps, and never signaled.
# Then the menus build from fixture snapshots, and tools/bench/gate.py checks both against tools/bench/budgets.json.
# The idle run and the menu run take about 50 seconds together. MM_BENCH_STRICT=1 gates on the phase 6 budgets.

bn="$MINMACS_HOME/bench"
mkdir -p "$bn/home"
bn_bin=$(BUILD_DIR="$bn" tools/bench/build.sh 2>"$bn/build.err"); bn_r=$?
check "bench: the bench builds" 0 "$bn_r"
check "bench: the bench has no warnings" 0 "$(cat "$bn/bench/clang.log" "$bn/build.err" 2>/dev/null | grep -c 'warning:')"
[ "$bn_r" = 0 ] || tail -20 "$bn/build.err"
bn_env() {
  env MINMACS_HOME="$bn/home" CLAUDE_CONFIG_DIR="$bn/home/claude" CODEX_HOME="$bn/home/codex" \
    MINMACS_CLAUDE=/usr/bin/false MINMACS_CODEX=/usr/bin/false MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false "$@"
}

# The bench never runs where it could reach a real model, cmux, tmux or support folder.
env -u MINMACS_CLAUDE "$bn_bin" idle --seconds 1 >/dev/null 2>&1
check "bench: it refuses to run without a fake model CLI" 2 "$?"
check "bench: it signals, quits and stops nothing" 0 "$(grep -cE 'kill\(|MMStop\(|MMQuitApps\(|MMRunAction\(|[Tt]erminate' tools/bench/bench.m)"

bn_start=$(date +%s)
bn_env "$bn_bin" idle --warmup 6 --seconds 30 --tick-runs 8 >"$bn/idle.json" 2>"$bn/idle.err"
check "bench: the idle run exits 0" 0 "$?"
bn_env "$bn_bin" menus --iterations 40 >"$bn/menus.json" 2>"$bn/menus.err"
check "bench: the menu run exits 0" 0 "$?"
bn_secs=$(( $(date +%s) - bn_start ))
check "bench: the short run finishes in under a minute" yes "$([ "$bn_secs" -lt 60 ] && echo yes || echo "$bn_secs s")"

bi() { json "$1" <"$bn/idle.json" 2>/dev/null; }
bm() { json "$1" <"$bn/menus.json" 2>/dev/null; }
bn_linked=$(bi 'len(j["expertIDs"])')
check "bench: every linked built-in expert runs" yes "$(bi '"yes" if j["experts"] >= 2 and "minmacs" in j["expertIDs"] and "locohost" in j["expertIDs"] else j["expertIDs"]')"
check "bench: every mode is Idle and nothing acted" "idle 0" "$(bi '"%s %d" % (j["modes"], j["undoRecords"])')"
check "bench: the window is 30 seconds" yes "$(bi '"yes" if 29.5 <= j["windowSeconds"] <= 32 else j["windowSeconds"]')"
# An exit of a watched process adds a sample of its own, so gaps can be shorter, never longer.
check "bench: Senses samples at least every 5 seconds in the window" yes "$(bi '"yes" if j["samples"] >= 5 and j["tickSeconds"]["max"] <= 6.5 else (j["samples"], j["tickSeconds"])')"
check "bench: each sample gives a rebuild" yes "$(bi '"yes" if j["inWindow"]["rebuildCPUms"]["n"] >= j["samples"] - 1 else j["inWindow"]["rebuildCPUms"]["n"]')"
check "bench: the pass reads the real process table" yes "$(bi '"yes" if j["pids"] > 50 else j["pids"]')"
check "bench: the tick is timed alone too" 8 "$(bi 'j["tickCost"]["passes"]')"
check "bench: each expert's findings are timed alone" "$bn_linked" "$(bi 'len(j["tickCost"]["parts"]["findingsCPUms"])')"
check "bench: the old apps are read over the same window" yes "$(bi '"yes" if all("error" in a or a["cpuSeconds"] >= 0 for a in j["oldApps"]) else j["oldApps"]')"
check "bench: every expert's menu is built 40 times" "$bn_linked" "$(bm 'sum(1 for e in j["experts"].values() if e["menuOpenMs"]["n"] == 40 and e["rows"] > 0)')"
check "bench: every expert's cards are timed" "$bn_linked" "$(bm 'sum(1 for e in j["experts"].values() if e["cards"] > 0 and e["cardHoverMs"]["n"] >= 40)')"
printf '    idle: %s\n' "$(bi '"%.3f %% CPU, %.2f MB footprint, %.2f MB resident, %.3f wakeups/s, %s pids; rebuild %.1f ms CPU median" % (j["cpuPercent"], j["footprintMB"], j["residentMB"], j["interruptWakeupsPerSecond"], j["pids"], j["inWindow"]["rebuildCPUms"]["median"])')"
printf '    menus: %s\n' "$(bm '", ".join("%s open p95 %.1f ms, hover p95 %.1f ms" % (k, e["menuOpenMs"]["p95"], e["cardHoverMs"]["p95"]) for k, e in sorted(j["experts"].items()))')"

# The gate. A budget over the phase 6 number but under today's ceiling prints as over and passes.
bn_strict=""; [ "${MM_BENCH_STRICT:-}" = 1 ] && bn_strict=--strict
python3 tools/bench/gate.py $bn_strict tools/bench/budgets.json "$bn/idle.json" "$bn/menus.json" >"$bn/gate.txt"
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
