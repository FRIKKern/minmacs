# ===== Performance: the tab's model, Core/MMPerformance.h, design 132-a =====
# Sourced by test.sh after core. It builds test/performance/performance.m with all of Sources/Core and runs it on fixture
# facts: a fake sample, worktrees, git facts, sessions, agents and five fake experts, inside $MINMACS_HOME. No action
# runs and no process starts. Then it reads the model through the built binary's `minmacs performance`.

pf_dir="$MINMACS_HOME/performance.$$"
mkdir -p "$pf_dir/fixtures" "$pf_dir/home"
# A home of its own, so the gains rows of other sections never reach the look-back checks.
pf_home=$(cd "$pf_dir/home" && pwd -P)
# -O2 as build.sh builds the app, so the bench line reads what the app pays.
pf_cc="clang -fobjc-arc -O2 -mmacosx-version-min=14.0 -ISources -Wall -Wextra -Wno-unused-parameter -Wstrict-prototypes -Werror -DMM_TESTS"
$pf_cc $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/performance/performance.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 -o "$pf_dir/perftest-$$" >"$pf_dir/build.log" 2>&1
pf_r=$?
check "performance: the test binary builds with no warnings" 0 "$pf_r"
[ "$pf_r" = 0 ] || tail -20 "$pf_dir/build.log"

pf_tab=$(printf '\t')
pf_run() { # mode
  MINMACS_HOME="$pf_home" "$pf_dir/perftest-$$" "$pf_dir/fixtures" "$1" >"$pf_dir/$1.out" 2>"$pf_dir/$1.err"
  pf_r=$?
  check "performance: $1 ran to the end" "0 END" "$pf_r $(tail -1 "$pf_dir/$1.out")"
  [ "$pf_r" = 0 ] || tail -10 "$pf_dir/$1.err"
  while IFS="$pf_tab" read -r pf_tag pf_name pf_want pf_got; do
    case "$pf_tag" in
      CHECK) check "$pf_name" "$pf_want" "$pf_got" ;;
      info) echo "  info  $pf_name" ;;
    esac
  done <"$pf_dir/$1.out"
}

if [ "$pf_r" = 0 ]; then
  echo "-- the ring, the sides and the fixes"
  pf_run model
  echo "-- the look-back, from the gains log"
  pf_run lookback
  echo "-- the calm state, with the look-back's rows in the table"
  pf_run calm
  echo "-- what one build costs"
  pf_run bench
  # docs/2.0/BENCH.md, section The Performance model, has the number. The ceiling is ten times it, for a loaded Mac.
  pf_ms=$(awk -F'\t' '$1 == "BENCH" {print $2}' "$pf_dir/bench.out")
  check "performance: one build at fixture scale stays under 6 ms CPU" yes \
    "$(awk -v x="${pf_ms:-99}" 'BEGIN {print (x < 6) ? "yes" : "no"}')"
fi

echo "-- the sources"
check "performance: the model imports no AppKit" 0 "$(cat Sources/Core/MMPerformance.h Sources/Core/MMPerformance.m | grep -cE '#import <(Cocoa|AppKit)')"
check "performance: MMCore.h imports it" 1 "$(grep -c '^#import "Core/MMPerformance.h"' Sources/Core/MMCore.h)"
check "performance: nothing in the model or the verb names the lid" 0 \
  "$(grep -ciwE 'lid|lidOverride|lidClosed' Sources/Core/MMPerformance.h Sources/Core/MMPerformance.m Sources/CLI/MMPerformanceCLI.m | awk -F: '{s+=$2} END {print s+0}')"
check "performance: the model claims no result in words" 0 \
  "$(grep -ciE 'is clean|everything is fine|nothing needs you|all good' Sources/Core/MMPerformance.m Sources/CLI/MMPerformanceCLI.m | awk -F: '{s+=$2} END {print s+0}')"

echo "-- minmacs performance"
# The verb runs cold here: it reads the fixture gains rows the look-back check wrote, and the Mac's own processes,
# read only, as status does. With MINMACS_HOME set and no MINMACS_ROOTS it walks no worktree.
pf_json=$(MINMACS_HOME="$pf_home" "$BIN" performance --json 2>/dev/null)
check "performance: performance --json runs" 0 "$?"
check "performance: --json has the ring, both sides, the fixes and the look-back" "app disk fixes generation lookBack memory needsYou ring" \
  "$(printf '%s' "$pf_json" | json "' '.join(sorted(j))")"
check "performance: --json keeps the ring's memory and disk apart" "disk memory" "$(printf '%s' "$pf_json" | json "' '.join(sorted(j['ring']))")"
check "performance: --json memory parts and other add up to memory used" yes \
  "$(printf '%s' "$pf_json" | json "'yes' if sum(p['bytes'] for p in j['ring']['memory']['parts']) == j['ring']['memory']['used'] else 'no'")"
check "performance: --json disk parts and other add up to disk used" yes \
  "$(printf '%s' "$pf_json" | json "'yes' if sum(p['bytes'] for p in j['ring']['disk']['parts']) == j['ring']['disk']['used'] else 'no'")"
check "performance: --json look-back matches the gains log" "157286400 7340032 104857600 7340032" \
  "$(printf '%s' "$pf_json" | json "'%d %d %d %d' % (j['lookBack']['week']['memoryBack'], j['lookBack']['week']['diskBack'], j['lookBack']['today']['memoryBack'], j['lookBack']['today']['diskBack'])")"
check "performance: --json groups in 132-a's order with its folds" "servers:6 agents:1 apps:2 tabs:0 helpers:0 worktrees:12 clutter:10" \
  "$(printf '%s' "$pf_json" | json "' '.join('%s:%d' % (g['group'], g['fold']) for g in j['memory'] + j['disk'])")"
check "performance: --json fixes are ranked by share" yes \
  "$(printf '%s' "$pf_json" | json "'yes' if all(a['share'] >= b['share'] for a, b in zip(j['fixes'], j['fixes'][1:])) else 'no'")"
check "performance: --json names no lid" 0 "$(printf '%s' "$pf_json" | grep -ciw lid)"
pf_text=$(MINMACS_HOME="$pf_home" "$BIN" performance 2>/dev/null)
check "performance: the text prints memory and disk on their own lines" "1 1" \
  "$(printf '%s\n' "$pf_text" | grep -c '^Memory ') $(printf '%s\n' "$pf_text" | grep -c '^Disk ')"
check "performance: the text has the look-back's numbers" 1 "$(printf '%s\n' "$pf_text" | grep -c '^Back .*this week memory .*today memory')"
check "performance: the text claims no result and names no lid" "0 0" \
  "$(printf '%s\n' "$pf_text" | grep -ciE 'is clean|fine|nothing needs') $(printf '%s\n' "$pf_text" | grep -ciw lid)"
MINMACS_HOME="$pf_home" "$BIN" performance extra >/dev/null 2>&1
check "performance: a word after the verb is a usage error" 2 "$?"
check "performance: help --json lists it as a verb that reads only" "False" \
  "$("$BIN" help --json | json '[v["mutates"] for v in j["verbs"] if v["verb"] == "performance"][0]')"

# ===== end of performance =====
