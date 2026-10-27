# Core Senses and Runtime, issue #14. Sourced by test.sh after core, which built $APP.
# test/senses/probe.m links Sources/Core/Runtime and Sources/Core/Senses with -DMM_TESTS.
# Every fixture lives in $MINMACS_HOME: a Python listener with one connection and one child, a sleep,
# git repos and a watched folder. Each pid this section starts goes into procs, so cleanup stops it.
# MM_PASS_BUDGET_MS and MM_PASS_P95_BUDGET_MS change the cost budget for slower machines.

sn_dir="$MINMACS_HOME/senses"
mkdir -p "$sn_dir"
sn_probe="$sn_dir/probe"
clang -fobjc-arc -O2 -mmacosx-version-min=14.0 -arch arm64 -arch x86_64 -ISources -DMM_TESTS \
  -Wall -Wextra -Wno-unused-parameter -Werror \
  Sources/Core/Runtime/*.m Sources/Core/Senses/*.m test/senses/probe.m \
  -framework Cocoa -framework IOKit -o "$sn_probe" >"$sn_dir/clang.log" 2>&1
sn_r=$?
check "the senses probe builds with MM_TESTS and no warnings" 0 "$sn_r"
[ "$sn_r" = 0 ] || tail -20 "$sn_dir/clang.log"
sn() { "$sn_probe" "$@" 2>/dev/null; }

# P1. Labeled serial queues, one per job, with a pool per block.
sn_out=$(sn labels)
check "MMQueue labels the Senses queue" no.guerrilla.minmacs.core.senses "$(printf '%s' "$sn_out" | json 'j["senses"]')"
check "the same expert and job give the same queue" 1 "$(printf '%s' "$sn_out" | json 'j["same"]')"
check "a block runs on its labeled queue" no.guerrilla.minmacs.locohost.where "$(printf '%s' "$sn_out" | json 'j["where"]')"
check "each block drains its own autorelease pool" True "$(printf '%s' "$sn_out" | json 'j["poolDrained"]')"

# Invariant 4. No subprocess in Senses, and no tool named in a string.
sn_spawn=$(grep -nE 'NSTask|posix_spawn|popen\(|[^a-zA-Z_]system\(|execv|fork\(' Sources/Core/Senses/*.m | grep -c .)
check "Senses starts no subprocess" 0 "$sn_spawn"
sn_tools=$(grep -nE '"[^"]*(lsof|nettop|pmset|/bin/ps)[^"]*"' Sources/Core/Senses/*.m | grep -c .)
check "Senses names no lsof, nettop, ps or pmset" 0 "$sn_tools"

# P6 to P10. One pass sees the fixture's process, tree, args, cwd and sockets.
sn_fx="$sn_dir/fixture"; mkdir -p "$sn_fx"
sn_fx_real=$(cd "$sn_fx" && pwd -P)
(cd "$sn_fx" && exec python3 "$ROOT/test/senses/server.py" "$sn_fx/port") &
sn_srv=$!
procs="$procs $sn_srv"
for i in $(seq 1 50); do [ -f "$sn_fx/port" ] && break; sleep 0.1; done
read -r sn_port sn_kid <"$sn_fx/port"
procs="$procs $sn_kid"
sn_out=$(sn sample "$sn_srv" "$sn_port" "$sn_kid")
sj() { printf '%s' "$sn_out" | json "$1"; }
check "the pass finds the fixture process" 1 "$(sj 'j["found"]')"
check "the fixture is alive by pid and start time" True "$(sj 'j["alive"]')"
check "a key with another start time is not alive" False "$(sj 'j["staleAlive"]')"
check "the key string is pid:start" "$sn_srv:$(sj 'j["startSec"]')" "$(sj 'j["keyString"]')"
check "args are read lazily from the sample" True "$(sj '"'"$ROOT/test/senses/server.py"'" in j["args"]')"
check "cwd is read lazily from the sample" "$sn_fx_real" "$(sj 'j["cwd"]')"
check "the socket table has the fixture's listener" "127.0.0.1:$sn_port" "$(sj '",".join(j["listen"])')"
check "both ends of the fixture's connection are seen" 2 "$(sj 'j["establishedOnPort"]')"
check "the fixture's child is in its tree" True "$(sj 'j["kidInTree"]')"
check "the fixture's child is among its children" True "$(sj 'j["kidIsChild"]')"
check "the child's first ancestor is the fixture" 1 "$(sj 'j["kidParent"]')"
check "an ancestor walk ends at launchd" 1 "$(sj 'j["lastAncestor"]')"
check "another user's process has cpuPercent -1" -1 "$(sj 'j["launchdCPU"]')"
check "another user's process has footprint 0" 0 "$(sj 'j["launchdFootprint"]')"
check "one pass covers root's processes too" yes "$(sj '"yes" if j["procs"] > 50 else j["procs"]')"
check "cpu and energy rank are in range" True "$(sj 'j["cpuSane"] == 1 and j["rankSane"] == 1')"
check "latest is the sample just taken" 1 "$(sj 'j["latestIsSample"]')"
kill "$sn_srv" "$sn_kid" 2>/dev/null; wait "$sn_srv" 2>/dev/null

# The cost of one pass on this machine, median and p95 over 60 passes.
# This Mac measured 6.1 ms median idle and 7.4 ms while other builds ran. The budget leaves room for load.
sn_budget=${MM_PASS_BUDGET_MS:-12}
sn_budget95=${MM_PASS_P95_BUDGET_MS:-25}
sn_out=$(sn bench 60)
printf '    pass cost: %s\n' "$(printf '%s' "$sn_out" | json '"cpu median %.2f ms, p95 %.2f ms, wall median %.2f ms, %d pids, %d sockets, %.1f MB max resident, %+.0f KB footprint after warm-up" % (j["cpuMedianMs"], j["cpuP95Ms"], j["wallMedianMs"], j["pids"], j["sockets"], j["maxResidentMB"], j["footprintGrowthKB"])')"
check "60 passes ran" 60 "$(sj 'j["passes"]')"
check "pass CPU median is at most ${sn_budget} ms" yes "$(sj '"yes" if j["cpuMedianMs"] <= '"$sn_budget"' else j["cpuMedianMs"]')"
check "pass CPU p95 is at most ${sn_budget95} ms" yes "$(sj '"yes" if j["cpuP95Ms"] <= '"$sn_budget95"' else j["cpuP95Ms"]')"
check "60 passes started no child process" 0 "$(sj 'j["children"]')"
check "the footprint grows less than 4 MB over the passes" yes "$(sj '"yes" if j["footprintGrowthKB"] < 4096 else j["footprintGrowthKB"]')"

# P11. Exits from kqueue NOTE_EXIT, on main.
sleep 2 &
sn_sleep=$!
procs="$procs $sn_sleep"
sn_out=$(sn exits "$sn_sleep")
check "a key whose process already ended fires at once" True "$(sj 'j["goneAtOnce"]')"
check "the fixture's exit fires MMSignalExit" True "$(sj 'j["liveFired"]')"
check "the exit fires after the process ended" True "$(sj 'j["deadWhenFired"]')"
check "the exit names the keys watched" True "$(sj 'j["keys"] == j["want"]')"
check "exit observers run on main" True "$(sj 'j["onMain"]')"
wait "$sn_sleep" 2>/dev/null

# P12. App and sleep notifications from NSWorkspace. The probe posts them itself and launches nothing.
sn_out=$(sn apps)
check "an app launch fires MMSignalApp" 64 "$(sj 'j["bits"]')"
check "the detail is the NSRunningApplication" 1 "$(sj 'j["detailIsApp"]')"
check "app observers run on main" True "$(sj 'j["onMain"]')"
check "a wake fires MMSignalSleep" 1 "$(sj 'j["sleepFired"]')"

# P13 and P14. Power facts from IOKit and sysctl, read-only.
sn_out=$(sn power)
check "battery is -1 or a percent" yes "$(sj '"yes" if -1 <= j["battery"] <= 100 else j["battery"]')"
check "memory pressure is 1, 2 or 4" yes "$(sj '"yes" if j["pressure"] in (1, 2, 4) else j["pressure"]')"
check "thermal state is 0 to 3" yes "$(sj '"yes" if 0 <= j["thermal"] <= 3 else j["thermal"]')"
check "free disk is read" yes "$(sj '"yes" if j["diskFreeGB"] > 0 else 0')"
check "the power facts are fresh" 1 "$(sj 'j["fresh"]')"

# P66. The fake power source changes every fact and Senses pushes each change.
sn_out=$(sn fakepower)
check "the first pass pushes no power change" 0 "$(sj 'j["bitsBeforeChange"]')"
check "memory, disk, thermal, power and lid changes are pushed" 31 "$(sj 'j["bits"]')"
check "the pass reads power on the Senses queue" no.guerrilla.minmacs.core.senses "$(sj 'j["readLabel"]')"
check "the pass does not run on main" False "$(sj 'j["readOnMain"]')"
check "nil goes back to the real power source" 1 "$(sj 'j["realAgain"]')"
check "nm reads the release build's Senses symbols" yes "$(nm "$BIN" 2>/dev/null | grep -q MMProcAlive && echo yes || echo no)"
check "the release build has no fake power source" 0 "$(nm "$BIN" 2>/dev/null | grep -c MMUsePowerSource)"

# P3. A turn past its budget skips the next one, and a watched task is ended at the deadline.
sn_out=$(sn job)
check "an overrun skips exactly one turn" 2 "$(sj 'j["ranSlow"]')"
check "pastDeadline turns YES once the budget is spent" '0.05:0:1 1:0:0' "$(sj '" ".join(j["turns"])')"
check "a task past the deadline gets terminate" '2 15' "$(sj '"%d %d" % (j["childReason"], j["childStatus"])')"
check "it ends near the deadline" 1 "$(sj 'j["childEndedSoon"]')"
check "a task the job dropped is still ended at the deadline" 'True True' "$(sj '"%s %s" % (j["droppedRanFirst"], j["droppedEnded"])')"

# P5. A crash leaves its breadcrumb. The next launch reads it once.
sn crumbs crash >/dev/null
check "the crashing probe dies inside its job" 3 "$?"
sn_out=$(sn crumbs read)
check "the next launch names the job that ran last" test.crashy "$(sj 'j["leftOver"]')"
check "the breadcrumb is read once" nil "$(sn crumbs read | json 'j["leftOver"]')"
sn crumbs clean >/dev/null
check "a clean exit leaves no breadcrumb" nil "$(sn crumbs read | json 'j["leftOver"]')"

# P15. FSEvents with a saved event id.
sn_fold="$sn_dir/watched"; mkdir -p "$sn_fold"
sn_out=$(sn folders "$sn_fold")
check "a new watch saves the current event id at once" True "$(sj 'j["savedAtStart"]')"
check "a change in the watched folder is pushed" True "$(sj 'j["live"]')"
check "node_modules is filtered in the callback" False "$(sj 'j["sawSkipped"]')"
check "stop saves the event id" 1 "$(sj 'j["savedId"]')"
check "the next watch replays what changed while stopped" True "$(sj 'j["replayed"]')"
check "it replays nothing from before the saved id" False "$(sj 'j["replayedBeforeSavedId"]')"
check "callbacks run on the watch's queue" no.guerrilla.minmacs.core.fixture "$(sj 'j["label"]')"

# P4. The worker child: repo discovery, the Sizer call, a crash mid-request and a restart.
sn_repos="$sn_dir/repos"; mkdir -p "$sn_repos" "$sn_dir/outside"
sn_git() { git -c user.name=fixture -c user.email=fixture@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
sn_git init "$sn_repos/alpha" && sn_git -C "$sn_repos/alpha" commit --allow-empty -m one
sn_git -C "$sn_repos/alpha" worktree add -b feature "$sn_repos/alpha-wt" && sn_git -C "$sn_repos/alpha" worktree lock "$sn_repos/alpha-wt"
sn_git init "$sn_repos/beta" && sn_git -C "$sn_repos/beta" commit --allow-empty -m one && sn_git -C "$sn_repos/beta" checkout --detach
sn_git -C "$sn_repos/beta" worktree add -b far "$sn_dir/outside/beta-far"
mkdir -p "$sn_repos/proj/node_modules" && sn_git init "$sn_repos/proj/node_modules/hidden"
sn_out=$(sn worker "$sn_repos")
check "the worker finds mains, linked and outside worktrees" \
  'alpha-wt|alpha|feature|locked alpha|alpha|main|open beta-far|beta|far|open beta|beta|-|open' "$(sj '" ".join(j["rows"])')"
check "the worker reports no error" "" "$(sj 'j["error"]')"
check "worker replies never arrive on main" False "$(sj 'j["replyOnMain"]')"
check "sizeTrees goes through MMSizer quick" '1002 7' "$(sj '"%d %d" % (j["sizeA"], j["freedA"])')"
check "exactSize goes through MMSizer exact" 84 "$(sj 'j["exact"]')"
check "the worker runs as a child of the caller" 1 "$(sj 'j["childFound"]')"
check "a request in flight fails when the child dies" 1 "$(sj 'j["inflightFailed"]')"
check "the next request starts a new child" 1 "$(sj 'j["restarted"]')"
# The idle close ends the child. A request sent as that happens must still be answered by a new child.
sn_out=$(MM_WORKER_IDLE=0.1 sn workerrace 40)
check "requests sent at the idle close are all answered" '40 40 0' "$(sj '"%d %d %d" % (j["sent"], j["answered"], j["errors"])')"
check "the idle close ends the child and the next request starts one" yes "$(sj '"yes" if j["children"] > 10 else j["children"]')"
sn_req=$(printf '{"id":1,"method":"findWorktrees","args":{"roots":["%s"],"skip":["node_modules"]}}' "$sn_repos")
check "minmacs _walk answers on stdout" 4 "$(printf '%s\n' "$sn_req" | "$BIN" _walk 2>/dev/null | json 'len(j["result"])')"
check "minmacs help does not list _walk" 0 "$("$BIN" help 2>/dev/null | grep -c _walk)"
