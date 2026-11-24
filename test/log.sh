# ===== The log: slice 1 of the window's center =====
# Sourced by test.sh after core. Every setting change is a row of the log's setting table with who made it, keeps
# are rows of its keep table, the log reads its newest rows by a range of the index, and the window's middle and
# `minmacs log` say each row in one plain sentence.
# It builds test/window/window.m, which includes test/window/log.m, as test/window.sh does, and runs its two log
# modes, each in a home of its own inside the test home. The CLI checks run the built binary in another such home.
# Nothing here acts: no fix runs, no process starts, and the login item is a fake.

lg_dir="$(cd "$MINMACS_HOME" && pwd -P)/log.$$"
mkdir -p "$lg_dir"
lg_shell="Sources/Shell/MMWindowFeed.m Sources/Shell/MMWindowRows.m Sources/Shell/MMWindowRules.m Sources/Shell/MMWindowJSON.m Sources/Shell/MMFixRunner.m Sources/Shell/MMWindowLog.m Sources/Shell/MMWindowController.m"
lg_ui="Sources/UI/Window/MMWindowModel.m Sources/UI/Window/MMWindowCounts.m Sources/UI/Window/MMWindowFixture.m Sources/UI/Window/MMWindowFixtureRows.m Sources/UI/Window/MMWindowFixtureMore.m Sources/UI/Window/MMWindowFixtureLog.m Sources/UI/MMFormat.m"
lg_cc="clang -fobjc-arc -O1 -mmacosx-version-min=14.0 -ISources -Wall -Wextra -Wno-unused-parameter -Wstrict-prototypes -Werror -DMM_TESTS"
$lg_cc $(find Sources/Core -name '*.m' | LC_ALL=C sort) $lg_shell $lg_ui test/window/window.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 -o "$lg_dir/logtest-$$" >"$lg_dir/build.log" 2>&1
lg_r=$?
check "log: the test binary builds with no warnings" 0 "$lg_r"
[ "$lg_r" = 0 ] || tail -20 "$lg_dir/build.log"

lg_tab=$(printf '\t')
lg_run() { # mode
  mkdir -p "$lg_dir/home-$1"
  MINMACS_HOME="$lg_dir/home-$1" "$lg_dir/logtest-$$" "$lg_dir/home-$1/fixtures" "$1" >"$lg_dir/$1.out" 2>"$lg_dir/$1.err"
  lg_x=$?
  check "log: $1 ran to the end" "0 END" "$lg_x $(tail -1 "$lg_dir/$1.out")"
  [ "$lg_x" = 0 ] || tail -10 "$lg_dir/$1.err"
  while IFS="$lg_tab" read -r lg_tag lg_name lg_want lg_got; do
    case "$lg_tag" in
      CHECK) check "$lg_name" "$lg_want" "$lg_got" ;;
      info) echo "  info  $lg_name" ;;
    esac
  done <"$lg_dir/$1.out"
}

if [ "$lg_r" = 0 ]; then
  echo "-- rows of every kind and the sentences they give"
  lg_run log-words
  echo "-- the window's controller: setting rows by who, reads only while open, nothing on main"
  lg_run log-controller
  # The read is a range of the (tbl, row) index for each table, so its cost does not grow with the log.
  lg_plan=$(/usr/bin/sqlite3 "$lg_dir/home-log-words/minmacs.sqlite" "EXPLAIN QUERY PLAN SELECT * FROM (SELECT row FROM rows WHERE tbl = 'undo' AND row < 9e18 ORDER BY row DESC LIMIT 600) UNION ALL SELECT * FROM (SELECT row FROM rows WHERE tbl = 'setting' AND row < 9e18 ORDER BY row DESC LIMIT 600) ORDER BY row DESC LIMIT 600" 2>&1)
  check "log: each table's part is a search of the index rows_tbl, never a scan of the log" "2 0" \
    "$(printf '%s\n' "$lg_plan" | grep -c 'SEARCH rows USING COVERING INDEX rows_tbl (tbl=? AND row<?)\|SEARCH rows USING INDEX rows_tbl (tbl=? AND row<?)') $(printf '%s\n' "$lg_plan" | grep -c 'SCAN rows')"
fi

echo "-- minmacs mode, review --model and log"
lg_home="$lg_dir/cli"
mkdir -p "$lg_home"
lg_bin() { MINMACS_HOME="$lg_home" "$BIN" "$@"; }
lg_bin log --json >"$lg_dir/empty.json" 2>&1
check "log: on a new Mac the log is empty and its note says what MinMacs watches" "0 yes" \
  "$(json "len(j['entries'])" <"$lg_dir/empty.json") $(json "'yes' if j['note'].startswith('Nothing is in the log yet. MinMacs watches your servers, agents, apps, worktrees and caches.') else j['note']" <"$lg_dir/empty.json")"
lg_bin mode locohost eager >/dev/null 2>&1
lg_bin mode locohost eager >/dev/null 2>&1
lg_bin mode noonoo idle --dry-run >/dev/null 2>&1
lg_bin review --model sonnet >/dev/null 2>&1
lg_bin log --json >"$lg_dir/log.json" 2>&1
check "log: minmacs log --json exits 0" 0 "$?"
check "log: minmacs mode and review --model write one row each, by the command line; the same mode again and a dry run write none" \
  "The model reviews ask changed from auto to sonnet.|from the command line Stop idle servers changed from Careful to Eager.|from the command line" \
  "$(json "' '.join(e['sentence'] + '|' + e['who'] for e in j['entries'])" <"$lg_dir/log.json")"
check "log: --json has the entries, the note and the limit" "entries limit note" "$(json "' '.join(sorted(j.keys()))" <"$lg_dir/log.json")"
check "log: each entry has its words, its time, who, tokens and whether it can be undone" "at canUndo day detail key kind row sentence time tokens who" \
  "$(json "' '.join(sorted(j['entries'][0].keys()))" <"$lg_dir/log.json")"
check "log: an entry's types" "str bool int str" \
  "$(json "' '.join(type(j['entries'][0][k]).__name__ for k in ('sentence', 'canUndo', 'tokens', 'day'))" <"$lg_dir/log.json")"
check "log: a setting entry is today, of kind setting, and its quiet line is its time and who" "Today setting yes" \
  "$(json "' '.join([j['entries'][0]['day'], j['entries'][0]['kind'], 'yes' if j['entries'][0]['detail'] == j['entries'][0]['time'] + ' · from the command line' else j['entries'][0]['detail']])" <"$lg_dir/log.json")"
check "log: the row in the log holds the key, from what, to what and who" "locohost.mode proactive eager cli" \
  "$(/usr/bin/sqlite3 "$lg_home/minmacs.sqlite" "SELECT json_extract(body, '\$.key'), json_extract(body, '\$.old'), json_extract(body, '\$.new'), json_extract(body, '\$.by') FROM rows WHERE tbl = 'setting' AND subject = 'locohost.mode'" | tr '|' ' ')"
check "log: --limit 1 gives one entry, the newest" "1 The model reviews ask changed from auto to sonnet." \
  "$(lg_bin log --json --limit 1 | json "str(len(j['entries'])) + ' ' + j['entries'][0]['sentence']")"
lg_bin log --limit 0 >/dev/null 2>&1
check "log: --limit 0 is a usage error" 2 "$?"
lg_bin log extra >/dev/null 2>&1
check "log: a word after log is a usage error" 2 "$?"
lg_text=$(lg_bin log 2>&1)
check "log: the text groups by day, a sentence and its quiet line under it" "Today|  Stop idle servers changed from Careful to Eager.|    from the command line" \
  "$(printf '%s\n' "$lg_text" | grep -A4 '^Today' | sed -n '1p;4,5p' | sed 's/^    [0-9][0-9]:[0-9][0-9] · /    /' | paste -sd'|' -)"
check "log: help lists the verb" 1 "$(lg_bin help --json | json "sum(1 for v in j['verbs'] if v['verb'] == 'log')")"

echo "-- the sources"
check "log: MMSetMode is told who sets it at every call" 0 \
  "$(grep -rhoE 'MMSetMode\([^;]*\);' Sources | grep -v 'NSString \*by' | grep -vcE 'MMSetMode\([^,]+, [^,]+, @"[a-z]+"\);')"
check "log: one function writes setting rows, and one writes keep rows" "1 1" \
  "$(grep -rc 'append:MMLogSettingTable' Sources | awk -F: '{s+=$2} END {print s+0}') $(grep -rc 'append:MMLogKeepTable' Sources | awk -F: '{s+=$2} END {print s+0}')"
check "log: every pref of review.model is written through MMSetSetting, with who" 0 \
  "$(grep -rn 'MMSetPref(MMReviewModelKey' Sources | grep -c .)"
check "log: the login switch, Start, the unattended skip of the welcome and the old Settings window log the login item" "3 1" \
  "$(grep -c 'MMLogSetting(MMWindowLoginKey' Sources/Shell/MMWindowController.m) $(grep -c 'MMLogSetting(MMWindowLoginKey' Sources/Shell/MMShell.m)"
check "log: the keep-awake switches write undo records, so they need no setting row" "2 0" \
  "$(grep -c 'MMRunAction(a, self->_policy, nil, by\|MMRunAction(a, _policy, nil, @"guard"' Sources/Experts/Insomnia/MMInsomniaExpert.m) $(grep -c 'MMLogSetting' Sources/Experts/Insomnia/MMInsomniaExpert.m)"
check "log: the log's files import no AppKit, run no timer and stay under 500 lines" "0 0 0" \
  "$(grep -cE '#import <(Cocoa|AppKit)' Sources/Shell/MMWindowLog.h Sources/Shell/MMWindowLog.m | awk -F: '{s+=$2} END {print s+0}') $(grep -cE 'NSTimer|dispatch_source|MMTimer\(|performSelector:.*afterDelay' Sources/Shell/MMWindowLog.m Sources/UI/Window/MMWindowLogView.m | awk -F: '{s+=$2} END {print s+0}') $(wc -l Sources/Shell/MMWindowLog.m Sources/UI/Window/MMWindowLogView.m Sources/UI/Window/MMWindowFixtureLog.m | awk '$2 != "total" && $1 >= 500' | grep -c .)"
check "log: the controller reads the log in one place, only when the stamp moved" "1 1" \
  "$(grep -c 'MMWindowLogRead(' Sources/Shell/MMWindowController.m) $(grep -c 'if (_log && \[stamp isEqualToString:_logStamp\]) return _log;' Sources/Shell/MMWindowController.m)"
check "log: the log's view names no Core type and reads no disk" 0 \
  "$(grep -cE '#import "Core/|MMLog |sqlite|NSFileManager|contentsOfFile' Sources/UI/Window/MMWindowLogView.m Sources/UI/Window/MMWindowMiddle.m | awk -F: '{s+=$2} END {print s+0}')"
