# The idle cost of the 5-second tick, issue #52. Sourced by test.sh after core.
# test/idle/idletool.m links all of Sources/Core with -DMM_TESTS. Its fixtures are a Python listener on a port it
# picks, a shell that execs a copy of sleep with a name unique to this run, a sleep child of the tool itself, and
# session folders inside $MINMACS_HOME. Each pid the section starts goes into procs, so cleanup stops it.

id_dir="$MINMACS_HOME/idle"
mkdir -p "$id_dir"
id_tool="$id_dir/idletool"
clang -fobjc-arc -O2 -mmacosx-version-min=14.0 -arch arm64 -arch x86_64 -ISources -DMM_TESTS \
  -Wall -Wextra -Wno-unused-parameter -Werror \
  $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/idle/idletool.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 -o "$id_tool" >"$id_dir/clang.log" 2>&1
id_r=$?
check "idle: the tool builds with MM_TESTS and no warnings" 0 "$id_r"
[ "$id_r" = 0 ] || tail -20 "$id_dir/clang.log"
it() { "$id_tool" "$@" 2>"$id_dir/err.txt"; }

# A process with the same pid, start time and name keeps its args, cwd and sockets. A connection makes it run,
# and its sockets are read again.
id_fx="$id_dir/fixture"; mkdir -p "$id_fx"
id_fx_real=$(cd "$id_fx" && pwd -P)
(cd "$id_fx" && exec python3 "$ROOT/test/idle/server.py" "$id_fx/port") &
id_srv=$!
procs="$procs $id_srv"
for i in $(seq 1 50); do [ -f "$id_fx/port" ] && break; sleep 0.1; done
read -r id_port <"$id_fx/port"
sleep 0.5
id_out=$(it carry "$id_srv" "$id_port")
ij() { printf '%s' "$id_out" | json "$1"; }
check "idle: the fixture listens in the first pass" True "$(ij 'j["listenA"]')"
check "idle: a second pass keeps the same args" True "$(ij 'j["argsSame"]')"
check "idle: and the same cwd" True "$(ij 'j["cwdSame"]')"
check "idle: the second pass carried the args the first one read" 1 "$(ij 'j["argsCarried"]')"
check "idle: a process that used no CPU is marked unchanged" True "$(ij 'j["idleSecondPass"]')"
check "idle: its sockets were carried, and it still listens" "yes True" "$(ij '("yes" if j["socketsCarried"] > 0 else j["socketsCarried"]) + " " + str(j["listenB"])')"
check "idle: a connection to it is seen in the next pass" "True 1 True" "$(ij '"%s %d %s" % (j["connected"], j["establishedAfter"], j["ranAfter"])')"
check "idle: the pass parts add up to no more than the pass" True "$(ij 'j["partsSum"]')"

# An exec keeps the pid and start time and changes the name, so the args are read again.
# A copy of a system binary is killed at launch, so the fixture is a sleeper built here, under a name unique to this run.
id_copy="$id_dir/w4idle-sleep-$$"
printf '#include <stdlib.h>\n#include <unistd.h>\nint main(int c, char **v) { sleep(c > 1 ? (unsigned)atoi(v[1]) : 60); return 0; }\n' >"$id_dir/sleeper.c"
clang -O1 -o "$id_copy" "$id_dir/sleeper.c" 2>>"$id_dir/clang.log"
sh -c 'while [ ! -f "$1" ]; do sleep 0.1; done; exec "$2" 60 w4idle-after' w4idle-sh "$id_dir/go" "$id_copy" &
id_sh=$!
procs="$procs $id_sh"
sleep 0.3
id_out=$(it exec "$id_sh" "$id_dir/go")
check "idle: before the exec the args are the shell's" True "$(ij '"w4idle-sh" in j["before"] or any("while" in a for a in j["before"])')"
check "idle: after the exec the args are read again" "$id_copy 60 w4idle-after" "$(ij '" ".join(j["after"])')"
check "idle: and the name changed, as p_comm keeps it" "$(printf '%s' "w4idle-sleep-$$" | cut -c1-16)" "$(ij 'j["nameAfter"]')"
kill "$id_sh" 2>/dev/null; wait "$id_sh" 2>/dev/null

# An exit is dropped from the last sample with no new pass.
id_out=$(it without)
check "idle: the exited child was in the sample and below the tool" "True True" "$(ij '"%s %s" % (j["seen"], j["wasChild"])')"
check "idle: the sample without it lacks it and its child link" "True True True" "$(ij '"%s %s %s" % (j["gone"], j["childGone"], j["selfKept"])')"
check "idle: it is the latest, with a new generation and the old time" "True True True" "$(ij '"%s %s %s" % (j["latest"], j["newGeneration"], j["sameTime"])')"
check "idle: it took no pass and kept the args read" "True True" "$(ij '"%s %s" % (j["noPass"], j["argsKept"])')"

# The pass backs off on battery and while the person is away, and comes back at once.
id_out=$(MINMACS_TICK=5 it pace)
check "idle: on power and here, the base interval" "5 base" "$(ij 'j["ac 0"]')"
check "idle: on battery, twice the base" "10 battery" "$(ij 'j["battery 0"]')"
check "idle: away 5 minutes, three times the base" "15 away" "$(ij 'j["ac 400"]')"
check "idle: both, six times the base" "30 battery, away" "$(ij 'j["battery 400"]')"
id_out=$(MINMACS_TICK=5 MINMACS_NO_BACKOFF=1 it pace)
check "idle: MINMACS_NO_BACKOFF keeps the base interval" "5 base" "$(ij 'j["battery 400"]')"
id_out=$(MINMACS_TICK=0.5 it cadence)
check "idle: the timer fires at the base interval" yes "$(ij '"yes" if len(j["base"]) >= 3 and all(0.3 <= g <= 0.9 for g in j["base"]) else j["base"]')"
# The first gap on battery spans the switch, so it is left out.
check "idle: on battery the timer slows to twice the base" yes "$(ij '"yes" if j["reason"] == "battery" and len(j["battery"]) >= 2 and all(0.8 <= g <= 1.4 for g in j["battery"][1:]) else j')"

# A build whose facts did not change is skipped, and an expert whose inputs did not change hands back its findings.
id_out=$(it graph)
check "idle: the first build asks every expert" True "$(ij 'j["firstBuilt"]')"
check "idle: the same facts again build nothing" True "$(ij 'j["sameSkipped"]')"
check "idle: CPU inside its band builds nothing" True "$(ij 'j["bandSkipped"]')"
check "idle: one more process builds" True "$(ij 'j["changeBuilt"]')"
check "idle: and the expert with the same inputs is not asked" True "$(ij 'j["reused"]')"
check "idle: its last findings are in the snapshot" 1 "$(ij 'j["reusedFindings"]')"
check "idle: a build for any other reason asks every expert" True "$(ij 'j["forcedBuilt"]')"
check "idle: CPU that leaves its band builds" True "$(ij 'j["bandBuilt"]')"
check "idle: the graph counts reuse and cost per expert" "True True" "$(ij '"%s %s" % (j["reusedCounted"], j["costsByExpert"])')"

# The session index reads its folders only after FSEvents names a change in them.
id_cl="$id_dir/claude"; id_pi="$id_dir/pi"
mkdir -p "$id_cl" "$id_pi"
id_out=$(CLAUDE_CONFIG_DIR="$id_cl" PI_CODING_AGENT_SESSION_DIR="$id_pi" it sessions "$id_cl")
check "idle: without the watch every refresh reads" 2 "$(ij 'j["unwatchedReads"]')"
check "idle: with the watch the first refresh reads" True "$(ij 'j["firstRead"]')"
check "idle: refreshes with no change read nothing" True "$(ij 'j["quietSkips"]')"
check "idle: a new transcript is noticed and read" "True True True" "$(ij '"%s %s %s" % (j["noted"], j["newFound"], j["readAfterChange"])')"
check "idle: a line added to a transcript moves its last activity" "True True" "$(ij '"%s %s" % (j["noted2"], j["lastActiveMoved"])')"
check "idle: a file outside the session folders asks for nothing" "0 True" "$(ij '"%d %s" % (j["otherNotes"], j["noReadWithoutChange"])')"
check "idle: refreshAll always reads" True "$(ij 'j["refreshAllReads"]')"

# App lookups are kept, and the log's stamp moves only on a write.
id_out=$(it apps)
check "idle: the app list is kept between calls" True "$(ij 'j["sameList"]')"
check "idle: the owning app and responsible pid are kept in a sample" "True True" "$(ij '"%s %s" % (j["sameOwner"], j["sameResponsible"])')"
check "idle: and carried to the next sample" "True True" "$(ij '"%s %s" % (j["responsibleCarried"], j["ownerCarried"])')"
id_out=$(it stamp)
check "idle: the log's stamp moves on a write and holds after" "True True" "$(ij '"%s %s" % (j["moved"], j["steady"])')"

# Invariant 2: the experts read the graph. The new digests read facts only.
check "idle: no expert digest samples, scans or runs anything" 0 "$(sed -n '/inputDigestFrom:(MMFacts/,/^}/p' Sources/Experts/*/*.m | grep -cE 'sampleNow|MMRun|NSTask|refresh|sysctl|proc_pid')"

kill "$id_srv" 2>/dev/null; wait "$id_srv" 2>/dev/null
rm -f "$id_copy"
