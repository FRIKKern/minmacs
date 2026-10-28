# ===== Core wiring: one support folder, one queue maker, no stand-ins, core.sock and MMCoreStart =====
# Sourced by test.sh. test/wire/wire.m links all of Sources/Core. Its fixtures live in $MINMACS_HOME: a copy of
# sleep under a name of this run, a git repo, and the socket and lock in the support folder. It signals only
# the pids it started, and each one goes into procs.

wi_dir="$MINMACS_HOME/wire"
mkdir -p "$wi_dir"
wi_bin="$wi_dir/wire"
clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -ISources \
  $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/wire/wire.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 -o "$wi_bin" >"$wi_dir/clang.log" 2>&1
wi_r=$?
check "wire: the tool builds with all of Core" 0 "$wi_r"
check "wire: Core has no warnings under -Wextra" 0 "$(grep -c 'warning:' "$wi_dir/clang.log")"
[ "$wi_r" = 0 ] || tail -20 "$wi_dir/clang.log"
wi() { "$wi_bin" "$@" 2>/dev/null; }
norm() { python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$1"; }
wj() { printf '%s' "$wi_out" | json "$1"; }

echo "-- no stand-ins"
check "wire: Act's fallbacks are gone" no "$([ -e Sources/Core/Act/MMActFallbacks.m ] && echo yes || echo no)"
check "wire: no Core class is looked up by name" 0 \
  "$(grep -rnE 'NSClassFromString\(@"MM' Sources/Core | grep -c .)"
# Store's migration reads MinMacs 1.2's own folder by that name, so Store is left out of this count.
check "wire: one support folder function, MMSupportDir" 0 \
  "$(grep -rn 'Application Support/MinMacs' Sources/Core --include='*.m' | grep -v '^Sources/Core/Store/' | grep -c .)"
check "wire: no second support folder function" 0 \
  "$(grep -rnE 'MM(Know|Runtime|Review)SupportDir|MMKnowQueue' Sources/Core --include='*.m' --include='*.h' | grep -c .)"
check "wire: one queue maker, MMQueue" 0 \
  "$(grep -rn 'dispatch_queue_create' Sources/Core | grep -v 'Runtime/MMRuntime.m' | grep -c .)"
check "wire: no JSON lines stand-in for the log" 0 \
  "$(grep -rnE 'undo-log\.jsonl|JSONLPath|FallbackAppend' Sources/Core | grep -c .)"
check "wire: the broker runs CLIs through MMRunTask" yes \
  "$(grep -q 'MMRunTask(t, input' Sources/Core/Review/MMModel.m && ! grep -q readDataToEndOfFile Sources/Core/Review/MMModel.m && echo yes || echo no)"

echo "-- prefs stay in MINMACS_HOME"
wi_real="$HOME/Library/Preferences/no.guerrilla.minmacs.plist"
wi_before=$(stat -f '%m %z' "$wi_real" 2>/dev/null || echo none)
wi_out=$(wi prefs)
check "wire: a pref set under MINMACS_HOME reads back" 42 "$(wj 'j["got"]')"
check "  a pref set to nil is removed" nil "$(wj 'j["gone"]')"
check "  it is in the plist inside MINMACS_HOME" 42 "$(wj 'j["inFile"]')"
check "  the target is that plist" "$(norm "$MINMACS_HOME/Preferences/no.guerrilla.minmacs.plist")" "$(wj '__import__("os").path.normpath(j["target"])')"
check "  the real domain does not hold it" nil "$(wj 'j["realDomain"]')"
check "  the person's prefs file is untouched" "$wi_before" "$(stat -f '%m %z' "$wi_real" 2>/dev/null || echo none)"

echo "-- core.sock, ported from Noo-Noo's server.go:82-160"
wi_fifo="$wi_dir/serve.in"; rm -f "$wi_fifo"; mkfifo "$wi_fifo"
"$wi_bin" serve 60 <"$wi_fifo" >"$wi_dir/serve.out" 2>&1 & wi_srv=$!
procs="$procs $wi_srv"
exec 7>"$wi_fifo"   # holds the server's stdin open; closing it ends the server
for i in $(seq 1 50); do grep -q serving "$wi_dir/serve.out" 2>/dev/null && break; sleep 0.1; done
check "wire: the server takes the lock and serves" True "$(json 'j["serving"]' <"$wi_dir/serve.out")"
check "  core.sock is mode 0600" 600 "$(stat -f '%Lp' "$MINMACS_HOME/core.sock" 2>/dev/null)"
wi_out=$(wi ask '{"verb":"echo","n":7}')
check "  a request from another process gets its reply" "7 $wi_srv" "$(wj '"%s %s" % (j["reply"]["echo"], j["reply"]["pid"])')"
check "  the handler runs on the socket queue" no.guerrilla.minmacs.core.socket "$(wj 'j["reply"]["queue"]')"
check "  the reply comes within the CLI's 0.2 seconds" yes "$(wj '"yes" if j["ms"] < 200 else j["ms"]')"
check "  another process sees the instance lock" True "$(wi another | json 'j["another"]')"
wi_out=$(wi serve 1 </dev/null)
check "  a second server is refused by the lock" "another MinMacs holds the instance lock" "$(wj 'j["error"]')"
check "  and the first one still answers" 7 "$(wi ask '{"verb":"echo","n":7}' | json 'j["reply"]["echo"]')"
printf 'not json\n' | nc -U -w 2 "$MINMACS_HOME/core.sock" >"$wi_dir/bad.out" 2>/dev/null
check "  a request that is not JSON gets an error" "the request is not a JSON object" "$(json 'j["error"]' <"$wi_dir/bad.out")"
# A peer that connects and sends nothing must not hold up the next request past the CLI's 0.2 seconds.
(sleep 3 | nc -U "$MINMACS_HOME/core.sock" >/dev/null 2>&1) & wi_quiet=$!
procs="$procs $wi_quiet"
sleep 0.3
check "  a silent peer does not hold up the next request" 5 "$(wi ask '{"verb":"echo","n":5}' | json 'j["reply"]["echo"] if j["reply"] != "none" else "none"')"
kill "$wi_quiet" 2>/dev/null; wait "$wi_quiet" 2>/dev/null
exec 7>&-
wait "$wi_srv" 2>/dev/null
check "  stop removes core.sock" no "$([ -e "$MINMACS_HOME/core.sock" ] && echo yes || echo no)"
check "  with no app, ask gives no reply" none "$(wi ask '{"verb":"echo"}' | json 'j["reply"]')"
check "  and the lock is free again" False "$(wi another | json 'j["another"]')"
# A server killed with SIGKILL leaves its socket file. The next one takes the free lock and replaces it.
"$wi_bin" serve 30 </dev/zero >"$wi_dir/serve2.out" 2>&1 & wi_srv=$!
procs="$procs $wi_srv"
for i in $(seq 1 50); do grep -q serving "$wi_dir/serve2.out" 2>/dev/null && break; sleep 0.1; done
kill -9 "$wi_srv" 2>/dev/null; wait "$wi_srv" 2>/dev/null
check "  a killed server leaves core.sock behind" yes "$([ -S "$MINMACS_HOME/core.sock" ] && echo yes || echo no)"
mkfifo "$wi_dir/serve3.in" 2>/dev/null
"$wi_bin" serve 30 <"$wi_dir/serve3.in" >"$wi_dir/serve3.out" 2>&1 & wi_srv=$!
procs="$procs $wi_srv"
exec 7>"$wi_dir/serve3.in"
for i in $(seq 1 50); do grep -q serving "$wi_dir/serve3.out" 2>/dev/null && break; sleep 0.1; done
check "  the next server replaces the stale socket" "1 $wi_srv" "$(wi ask '{"verb":"echo","n":1}' | json '"%s %s" % (j["reply"]["echo"], j["reply"]["pid"])')"
exec 7>&-
wait "$wi_srv" 2>/dev/null

echo "-- MMCoreStart and MMCoreStop"
wi_sleep="$wi_dir/mmwire-sleep-$$"
# Built here, not copied from /bin: macOS may kill a copy of a system binary when it starts.
clang -O1 test/insomnia/sleeper.c -o "$wi_sleep" >>"$wi_dir/clang.log" 2>&1
wi_repo="$wi_dir/roots/fixture-repo"
mkdir -p "$wi_repo/sub/dir"
git -c init.defaultBranch=main init -q "$wi_repo" >/dev/null 2>&1
# A repo outside the roots with a linked worktree. The walk never sees either, so only worktreeAt's
# reading of the .git file and commondir can find them.
wi_other="$wi_dir/other/fixture-other"
git -c init.defaultBranch=main init -q "$wi_other" >/dev/null 2>&1
git -C "$wi_other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one >/dev/null 2>&1
wi_far="$wi_dir/far/fixture-far"
git -C "$wi_other" worktree add -q -b far-branch "$wi_far" >/dev/null 2>&1
mkdir -p "$wi_far/deep"
wi_out=$(MINMACS_ROOTS="$(dirname "$wi_repo")" "$wi_bin" start "$wi_sleep" "$wi_repo" "$wi_far" 2>"$wi_dir/start.err")
check "wire: MMRegisterExpert keeps one of each expert" "1 yes" "$(wj '"%d %s" % (j["experts"], j["named"])')"
check "  the first snapshot holds the expert's finding" 1 "$(wj 'int(j["firstSnapshot"])')"
check "  it reads the Senses sample and power facts" "1 1" "$(wj '"%d %d" % (j["procsInSample"], j["powerRead"])')"
check "  the repo index finds the fixture repo through the worker" 1 "$(wj 'int(j["repoInFacts"])')"
check "  worktreeAt finds the walked worktree for a path inside it" "$(wj 'j["repo"]')" "$(wj 'j["worktreeAt"]')"
check "  worktreeAt reads .git files for a worktree outside the roots" \
  "$(norm "$wi_far")|$(norm "$wi_other")|far-branch" "$(wj 'j["outside"]')"
check "  core.sock answers ping from the running Core" "1 1" "$(wj '"%d %d" % (j["ping"], j["pingPid"])')"
check "  status lists the registered experts" wiretest "$(wj '",".join(j["statusExperts"])')"
check "  an unknown verb gets an error" "no verb no-such in the running app" "$(wj 'j["unknownVerb"]')"
check "  the running Core holds its own lock, which is not another instance" 0 "$(wj 'int(j["anotherInstance"])')"
check "  an exit rebuilds within a second, before the next pass" yes "$(wj '"yes" if j["exitRebuild"] and j["exitMs"] < 1000 else "%s %s" % (j["exitRebuild"], j["exitMs"])')"
check "  fresh facts never run on main" nil "$(wj 'j["freshOnMain"]')"
check "  fresh facts off main take a new sample" 1 "$(wj 'int(j["freshOffMain"])')"
check "  observers see each new snapshot" 1 "$(wj 'int(j["published"])')"
check "  after MMCoreStop core.sock does not answer" "none 0" "$(wj '"%s %d" % (j["pingAfterStop"], j["socketFileAfterStop"])')"
check "  a build was running when MMCoreStop came" 1 "$(wj 'int(j["buildInFlightAtStop"])')"
check "  after MMCoreStop the 5-second pass no longer rebuilds" 0 "$(wj 'int(j["stillBuildingAfterStop"])')"
check "  after MMCoreStop the build that was running publishes nothing" 0 "$(wj 'int(j["publishedAfterStop"])')"
check "  after MMCoreStop Senses takes no sample" 0 "$(wj 'int(j["stillSamplingAfterStop"])')"
printf '    exit to rebuild: %s ms, first snapshot: %s ms\n' "$(wj 'j["exitMs"]')" "$(wj 'j["firstMs"]')"
check "  no fixture sleep is left running" 0 "$(pgrep -f "$wi_sleep" | grep -c .)"
# ===== end of Core wiring =====
