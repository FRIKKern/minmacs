# ===== Insomnia expert: keep-awake, lid mode and the guard matrix, issue #31 =====
# Sourced by test.sh after core. Builds test/insomnia/tool.m with all of Core, the kit, the CLI and the expert,
# under -DMM_TESTS, and runs Insomnia's guard matrix from test/insomnia/matrix.txt.
# Fixtures only, all inside $MINMACS_HOME:
#   power facts from a fake power source, so the Mac's own lid, battery and heat are never read or changed
#   test/insomnia/fakecmd.sh in place of sudo, pmset and osascript, named by MINMACS_INSOMNIA_CMD
#   workers built from test/insomnia/sleeper.c under a name unique to this run, started and stopped by the tool
# The assertions are real IOKit ones, held by the tool for its own fixture pids for a few seconds, as caffeinate is.

in_dir="$MINMACS_HOME/insomnia"
mkdir -p "$in_dir/home" "$in_dir/cli"
in_dir=$(cd "$in_dir" && pwd -P)
in_run=$$
in_sleeper="$in_dir/insleep$in_run"

in_cc="clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -DMM_TESTS -ISources"
# shellcheck disable=SC2086
$in_cc $(find Sources/Core Sources/UI Sources/CLI Sources/Experts/Insomnia -name '*.m' | LC_ALL=C sort) test/insomnia/tool.m \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  -o "$in_dir/tool" >"$in_dir/build.log" 2>&1
in_r=$?
check "insomnia: the test tool builds" 0 "$in_r"
check "insomnia: the expert has no warnings under -Wextra" 0 "$(grep -c 'warning:' "$in_dir/build.log")"
[ "$in_r" = 0 ] || tail -20 "$in_dir/build.log"
clang -O1 test/insomnia/sleeper.c -o "$in_sleeper" >>"$in_dir/build.log" 2>&1
check "insomnia: the fixture process builds" 0 "$?"

# ----- The guard matrix -----
if [ "$in_r" = 0 ]; then
  MINMACS_HOME="$in_dir/home" MINMACS_INSOMNIA_CMD="$ROOT/test/insomnia/fakecmd.sh" IN_SLEEPER="$in_sleeper" \
    "$in_dir/tool" matrix test/insomnia/matrix.txt >"$in_dir/matrix.out" 2>"$in_dir/matrix.err"
  check "insomnia: the matrix runs to the end" 0 "$?"
  [ -s "$in_dir/matrix.err" ] && sed 's/^/        /' "$in_dir/matrix.err"
  in_tab=$(printf '\t')
  while IFS="$in_tab" read -r in_kind in_name in_want in_got; do
    case "$in_kind" in
      section) echo "  -- $in_name" ;;
      check) check "insomnia: $in_name" "$in_want" "$in_got" ;;
    esac
  done <"$in_dir/matrix.out"
  check "insomnia: the matrix ran its checks" yes "$([ "$(grep -c '^check' "$in_dir/matrix.out")" -ge 90 ] && echo yes || echo no)"
  check "insomnia: the fake saw only the commands Insomnia runs" 0 \
    "$(grep -cvE '^/usr/bin/sudo -n (-l )?/usr/bin/pmset -a disablesleep [01]$|^/usr/bin/pmset displaysleepnow$|^/usr/bin/osascript -e ' "$in_dir/home/insomnia-fake/log")"
  check "insomnia: no fixture worker is left running" 0 "$(pgrep -f "$in_sleeper" | grep -c .)"
  pkill -f "$in_sleeper" 2>/dev/null

  # In a test home with no fake, every lid command refuses, and nothing runs.
  in_nf=$(MINMACS_HOME="$in_dir/cli" "$in_dir/tool" nofake)
  check "insomnia: no lid command runs in a test home without the fake" "ran: no" "$(printf '%s\n' "$in_nf" | grep '^ran:')"
  check "insomnia: and none runs on main"               "on main: it never runs on the main thread" "$(printf '%s\n' "$in_nf" | grep '^on main:')"
  # MMPower.online, the new Senses fact, against route(8) on this Mac. Both only read the routing table.
  in_route=$(route -n get default >/dev/null 2>&1 && echo 1 || echo 0)
  check "insomnia: MMPower.online agrees with the routing table" "$in_route" "$(MINMACS_HOME="$in_dir/cli" "$in_dir/tool" online)"
fi

# ----- The verbs in the built app, which runs Core cold here -----
in_bin() { MINMACS_HOME="$in_dir/cli" "$BIN" "$@"; }
in_bin awake >/dev/null 2>&1
check "insomnia: awake runs cold"                       0 "$?"
check "insomnia: awake --json has the state"           yes "$(in_bin awake --json 2>/dev/null | json "'yes' if 'holding' in j and 'lid' in j and j['inApp'] is False else 'no'")"
in_bin insomnia on >/dev/null 2>&1
check "insomnia: a change needs the app"                3 "$?"
check "insomnia: --dry-run says what it would do"      "would set lid to on" "$(in_bin insomnia lid on --dry-run 2>/dev/null)"
check "insomnia: the dry run changed no pref"          missing "$([ -f "$in_dir/cli/Preferences/no.guerrilla.minmacs.plist" ] && /usr/libexec/PlistBuddy -c 'Print :insomnia.lid' "$in_dir/cli/Preferences/no.guerrilla.minmacs.plist" 2>/dev/null || echo missing)"
in_bin insomnia set battery 200 --dry-run >/dev/null 2>&1
check "insomnia: a bad guard value is a usage error"   2 "$?"
ln -sf "$BIN" "$in_dir/insomnia"
MINMACS_HOME="$in_dir/cli" "$in_dir/insomnia" awake >/dev/null 2>&1
check "insomnia: the old name runs its verbs"           0 "$?"

# ----- What the release build leaves out, read from the binary and the source -----
check "insomnia: the release binary has no debug prefs" 0 "$(strings "$BIN" | grep -c 'insomnia\.debug')"
check "insomnia: and no fake power source"              0 "$(nm "$BIN" 2>/dev/null | grep -cE 'MMUsePowerSource|MMPowerFrom')"
check "insomnia: the expert has no self-updater"        0 "$(grep -nE 'api\.github\.com|install\.sh|releases/latest|checkForUpdates' Sources/Experts/Insomnia/*.m | grep -c .)"
check "insomnia: the expert runs no process itself"     0 "$(grep -nE 'NSTask|posix_spawn|popen\(|system\(|MMRun\(|NSAppleScript' Sources/Experts/Insomnia/*.m | grep -c .)"
check "insomnia: the expert never reads pmset -g"       0 "$(grep -n 'pmset -g\|"-g"' Sources/Experts/Insomnia/*.m Sources/Core/Act/MMLid.m | grep -c .)"
check "insomnia: main never waits on the expert's queue" 0 "$(grep -nE 'dispatch_sync\(dispatch_get_main_queue|MMOnMain' Sources/Experts/Insomnia/*.m | grep -c .)"
check "insomnia: lid writes go through MMRunAction"     yes "$(grep -q 'MMRunAction(a, _policy' Sources/Experts/Insomnia/MMInsomniaExpert.m && echo yes || echo no)"
check "insomnia: assertions are Core's MMAwake"         0 "$(grep -n 'IOPMAssertionCreate' Sources/Experts/Insomnia/*.m | grep -c .)"

# ----- The menu and cards, in light, dark and Increase Contrast -----
in_out="$in_dir/render"
BUILD_DIR="$in_dir" tools/render.sh "$in_out" >"$in_dir/render.log" 2>&1
check "insomnia: the render runs"                       0 "$?"
check "insomnia: its DESIGN.md checks pass"             0 "$(grep -E '^FAIL' "$in_out/checks.txt" 2>/dev/null | grep -c 'insomnia')"
grep '^FAIL' "$in_out/checks.txt" 2>/dev/null | sed 's/^/        /'
check "insomnia: every menu and card PNG is there"     44 "$(ls "$in_out"/insomnia*.png 2>/dev/null | wc -l | tr -d ' ')"
check "insomnia: every PNG has the kit's one width"    "720 " "$(for f in "$in_out"/insomnia*.png; do sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/ {print $2}'; done | sort -u | tr '\n' ' ')"
check "insomnia: the status label names the expert"    yes "$(grep -q '^ok    Insomnia: the status label names the expert' "$in_out/checks.txt" && echo yes || echo no)"
# ===== end of Insomnia =====
