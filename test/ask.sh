# ===== Ask MinMacs, tier 0: slice 4 of the window's center =====
# Sourced by test.sh after core. A question typed into the window's middle, or given to `minmacs ask`, is answered
# from what MinMacs knows: the log's rows, the window's rows and Fix Everything's plan. No model is asked and nothing
# goes on the network. Every ask is a row of the log's ask table. An answer never acts: a keep or an undo comes back as
# the existing button and verb, and only a press on it does anything.
# It builds test/window/window.m, which includes test/window/ask.m, as test/log.sh does, and runs its ask modes, each
# in a home of its own inside the test home. The CLI checks run the built binary in another such home, on log rows the
# tool wrote there. The one press it makes is Keep in the controller check, which keeps a fixture worktree in that
# home's own files. No process is signaled.

ak_dir="$(cd "$MINMACS_HOME" && pwd -P)/ask.$$"
mkdir -p "$ak_dir"
ak_shell="Sources/Shell/MMWindowFeed.m Sources/Shell/MMWindowRows.m Sources/Shell/MMWindowAgent.m Sources/Shell/MMWindowRules.m Sources/Shell/MMWindowJSON.m Sources/Shell/MMFixRunner.m Sources/Shell/MMWindowLog.m Sources/Shell/MMWindowLogRun.m Sources/Shell/MMWindowLogFold.m Sources/Shell/MMAsk.m Sources/Shell/MMAskCLI.m Sources/Shell/MMKeepCLI.m Sources/Shell/MMWindowController.m"
ak_ui="Sources/UI/Window/MMWindowModel.m Sources/UI/Window/MMWindowAnswer.m Sources/UI/Window/MMWindowFixtureAsk.m Sources/UI/Window/MMWindowCounts.m Sources/UI/Window/MMWindowCollapse.m Sources/UI/Window/MMWindowFixture.m Sources/UI/Window/MMWindowFixtureRows.m Sources/UI/Window/MMWindowFixtureMore.m Sources/UI/Window/MMWindowFixtureLog.m Sources/UI/Window/MMWindowFixtureWeek.m Sources/UI/MMFormat.m"
ak_cc="clang -fobjc-arc -O1 -mmacosx-version-min=14.0 -ISources -Wall -Wextra -Wno-unused-parameter -Wstrict-prototypes -Werror -DMM_TESTS"
# shellcheck disable=SC2086
$ak_cc $(find Sources/Core -name '*.m' | LC_ALL=C sort) $ak_shell $ak_ui test/window/window.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 -o "$ak_dir/asktest-$$" >"$ak_dir/build.log" 2>&1
ak_r=$?
check "ask: the test binary builds with no warnings" 0 "$ak_r"
[ "$ak_r" = 0 ] || tail -20 "$ak_dir/build.log"

ak_tab=$(printf '\t')
ak_run() { # mode [home]
  ak_h="${2:-$ak_dir/home-$1}"
  mkdir -p "$ak_h"
  MINMACS_HOME="$ak_h" "$ak_dir/asktest-$$" "$ak_h/fixtures" "$1" >"$ak_dir/$1.out" 2>"$ak_dir/$1.err"
  ak_x=$?
  check "ask: $1 ran to the end" "0 END" "$ak_x $(tail -1 "$ak_dir/$1.out")"
  [ "$ak_x" = 0 ] || tail -10 "$ak_dir/$1.err"
  while IFS="$ak_tab" read -r ak_tag ak_name ak_want ak_got; do
    case "$ak_tag" in
      CHECK) check "$ak_name" "$ak_want" "$ak_got" ;;
      info) echo "  info  $ak_name" ;;
    esac
  done <"$ak_dir/$1.out"
}

ak_home="$ak_dir/cli"
if [ "$ak_r" = 0 ]; then
  echo "-- each kind of question, the fallback, the ask row and nothing acting, on the window's own model"
  ak_run ask-engine
  echo "-- the window's controller: answers in a later model, Keep only on a press, nothing on main"
  ak_run ask-controller
  ak_run ask-rows "$ak_home"
fi

echo "-- minmacs ask, for BarkBot and the command line"
ak_bin() { MINMACS_HOME="$ak_home" perl -e 'alarm shift; exec @ARGV' 120 "$BIN" "$@"; }
ak_rows() { /usr/bin/sqlite3 "$ak_home/minmacs.sqlite" "$1" 2>/dev/null; }
ak_before="$(ak_rows "SELECT count(*) FROM rows WHERE tbl = 'undo' AND state = 'restored'") $(ak_rows "SELECT count(*) FROM rows WHERE tbl = 'keep'")"
ak_bin ask "why did you quit chat" --json >"$ak_dir/why.json" 2>"$ak_dir/why.err"
check "ask: minmacs ask --json exits 0" 0 "$?"
check "ask: --json has the question, the kind, the answer, who answered, the entries, the suggestion, the examples and the row" \
  "answer answeredBy entries examples kind question row suggest" "$(json "' '.join(sorted(j.keys()))" <"$ak_dir/why.json")"
check "ask: why did you quit chat gives the quit from the log with its own reason, answered by the rules" \
  "why|rules|1|Quit Chat. Undo opens it again.|Its reason: Memory pressure.|None" \
  "$(json "'|'.join(str(x) for x in [j['kind'], j['answeredBy'], len(j['entries']), j['entries'][0]['sentence'], j['entries'][0]['why'], j['suggest']])" <"$ak_dir/why.json")"
check "ask: an entry has its sentence, why, quiet line, row and log entry" "detail logKey row sentence why" \
  "$(json "' '.join(sorted(j['entries'][0].keys()))" <"$ak_dir/why.json")"
ak_bin ask --json undo the last one >"$ak_dir/undo.json" 2>&1
check "ask: undo the last one suggests the existing verb with its record, and acts on nothing" "undo|r-a1|minmacs restore r-a1|action command target title" \
  "$(json "'|'.join([j['kind'], j['suggest']['target'], j['suggest']['command'], ' '.join(sorted(j['suggest'].keys()))])" <"$ak_dir/undo.json")"
ak_bin ask --json "is it going to rain tomorrow" >"$ak_dir/unknown.json" 2>&1
check "ask: a question no rule knows gets the honest fallback and three examples, never an answer made up" \
  "unknown|I can't answer that without the model yet.|3|0|None" \
  "$(json "'|'.join(str(x) for x in [j['kind'], j['answer'], len(j['examples']), len(j['entries']), j['suggest']])" <"$ak_dir/unknown.json")"
ak_bin ask --json "what would you clean now" >"$ak_dir/plan.json" 2>&1
check "ask: what would you clean now is the plan of Fix Everything, which runs nothing until pressed" "plan yes" \
  "$(json "j['kind'] + ' ' + ('yes' if j['answer'].startswith('Fix Everything') else j['answer'])" <"$ak_dir/plan.json")"
ak_text=$(ak_bin ask undo the last one 2>&1)
check "ask: the text says the answer, the entry and the verb to run, and runs it not" "yes yes" \
  "$(printf '%s\n' "$ak_text" | grep -q '^The newest thing can still be taken back. Nothing changes until you press Undo.$' && echo yes || echo no) $(printf '%s\n' "$ak_text" | grep -q '^To do it: minmacs restore r-a1$' && echo yes || echo no)"
ak_bin ask >/dev/null 2>&1
check "ask: no question is a usage error" 2 "$?"
check "ask: no answer acted: nothing was taken back and nothing kept" "$ak_before" \
  "$(ak_rows "SELECT count(*) FROM rows WHERE tbl = 'undo' AND state = 'restored'") $(ak_rows "SELECT count(*) FROM rows WHERE tbl = 'keep'")"
check "ask: every ask wrote one ask row, by the command line, answered by the rules" "5 cli rules" \
  "$(ak_rows "SELECT count(*) FROM rows WHERE tbl = 'ask'") $(ak_rows "SELECT DISTINCT json_extract(body, '\$.by') FROM rows WHERE tbl = 'ask'") $(ak_rows "SELECT DISTINCT json_extract(body, '\$.answeredBy') FROM rows WHERE tbl = 'ask'")"
check "ask: the row holds the question as asked" "why did you quit chat" "$(ak_rows "SELECT json_extract(body, '\$.question') FROM rows WHERE tbl = 'ask' ORDER BY row LIMIT 1")"
check "ask: minmacs log tells the asks, newest first" "ask yes" \
  "$(ak_bin log --json --limit 1 | json "j['entries'][0]['kind'] + ' ' + ('yes' if j['entries'][0]['sentence'] == 'Asked \u201Cundo the last one\u201D. Answered from what MinMacs knows, with no model.' else j['entries'][0]['sentence'])")"
check "ask: help lists ask, as a verb that changes nothing" "1 False" \
  "$(ak_bin help --json | json "str(sum(1 for v in j['verbs'] if v['verb'] == 'ask')) + ' ' + str([v['mutates'] for v in j['verbs'] if v['verb'] == 'ask'][0])")"

ak_bin keep 99999 --dry-run >/dev/null 2>&1
check "ask: minmacs keep names nothing for a port nothing serves" 1 "$?"
ak_bin keep --dry-run >/dev/null 2>&1; ak_k1=$?
ak_bin keep 3000 --days -1 --dry-run >/dev/null 2>&1; ak_k2=$?
check "ask: minmacs keep with nothing to keep, or days below 0, is a usage error" "2 2" "$ak_k1 $ak_k2"
check "ask: help lists keep, as a verb that changes things" "1 True" \
  "$(ak_bin help --json | json "str(sum(1 for v in j['verbs'] if v['verb'] == 'keep')) + ' ' + str([v['mutates'] for v in j['verbs'] if v['verb'] == 'keep'][0])")"

echo "-- the sources"
check "ask: the engine asks no model, opens no connection and runs no process" 0 \
  "$(grep -cE '\bMMModel\b|MMInvestigate|NSURLSession|NSURLConnection|CFSocket|nw_|https?://|NSTask|posix_spawn|popen\(|system\(|claude -p|codex' Sources/Shell/MMAsk.h Sources/Shell/MMAsk.m Sources/Shell/MMAskCLI.m | awk -F: '{s+=$2} END {print s+0}')"
check "ask: the engine acts on nothing: no keep, no restore, no action" 0 \
  "$(grep -cE 'MMKeep keep:|restore:|MMRunAction|MMRunWrapUp|MMRemoval' Sources/Shell/MMAsk.m Sources/Shell/MMAskCLI.m | awk -F: '{s+=$2} END {print s+0}')"
check "ask: the engine and the answer's model import no AppKit" 0 \
  "$(grep -cE '#import <(Cocoa|AppKit)' Sources/Shell/MMAsk.h Sources/Shell/MMAsk.m Sources/Shell/MMAskCLI.m Sources/UI/Window/MMWindowAnswer.m | awk -F: '{s+=$2} END {print s+0}')"
check "ask: only a press keeps: the controller's Keep is the one MMKeep of the window, and Undo is the log's own restore" "1 1" \
  "$(grep -c 'MMKeep keep:' Sources/Shell/MMWindowController.m) $(grep -c 'MMUndo.shared restore:' Sources/Shell/MMWindowController.m)"
check "ask: the views name no Core type and read no disk" 0 \
  "$(grep -cE '#import "Core/|MMLog |sqlite|NSFileManager|contentsOfFile|MMKeep|MMUndo' Sources/UI/Window/MMWindowAsk.m Sources/UI/Window/MMWindowViewAsk.m | awk -F: '{s+=$2} END {print s+0}')"
check "ask: no timer in the engine or the views, and each file under 500 lines" "0 0" \
  "$(grep -cE 'NSTimer|dispatch_source|MMTimer\(|afterDelay' Sources/Shell/MMAsk.m Sources/Shell/MMAskCLI.m Sources/UI/Window/MMWindowAsk.m Sources/UI/Window/MMWindowViewAsk.m | awk -F: '{s+=$2} END {print s+0}') $(wc -l Sources/Shell/MMAsk.m Sources/Shell/MMAskCLI.m Sources/UI/Window/MMWindowAsk.m Sources/UI/Window/MMWindowViewAsk.m Sources/UI/Window/MMWindowMiddle.m Sources/UI/Window/MMWindowView.m | awk '$2 != "total" && $1 >= 500' | grep -c .)"
check "ask: PRIVACY.md says asks stay on this Mac and nothing is sent" 1 "$(grep -c '^## Ask MinMacs$' docs/PRIVACY.md)"

echo "-- the window's pictures"
ak_out="$ak_dir/render"
BUILD_DIR="$ak_dir/render-build" tools/render.sh "$ak_out" >"$ak_dir/render.log" 2>&1
check "ask: the render tool draws the window" 0 "$?"
check "ask: the field empty and typing, and five answers, in dark and Increase Contrast" 16 "$(ls "$ak_out"/window/ask-*.png 2>/dev/null | wc -l | tr -d ' ')"
check "ask: the window's ask checks pass" "18 0" "$(grep -c 'window ask' "$ak_out/checks.txt" 2>/dev/null) $(grep '^FAIL' "$ak_out/checks.txt" 2>/dev/null | grep -c 'window ask')"
grep '^FAIL' "$ak_out/checks.txt" 2>/dev/null | sed 's/^/        /'
check "ask: no window check fails, the log's and the words' among them" 0 "$([ -f "$ak_out/checks.txt" ] && { grep -c '^FAIL' "$ak_out/checks.txt"; true; } || echo missing)"
