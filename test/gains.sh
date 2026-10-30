# ===== Gains: the kept log of what came back, designs 100 to 103 =====
# Sourced by test.sh. It builds test/gains/gains.m with all of Sources/Core and runs it on fixtures inside
# $MINMACS_HOME: a stop, moves to the test's own Trash, an undo, a failed action, a Wrap Up, the day boundary and
# the 30 days. Then it reads the same table through the built binary's `minmacs gains`.
# The test binary starts its fixture processes itself, and they exit on their own when it ends.

gn_dir="$MINMACS_HOME/gains.$$"
mkdir -p "$gn_dir/fixtures"
gn_cc="clang -fobjc-arc -mmacosx-version-min=14.0 -ISources -Wall -Wextra -Wno-unused-parameter -Wstrict-prototypes -Werror -DMM_TESTS"
$gn_cc $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/gains/gains.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 -o "$gn_dir/gainstest-$$" >"$gn_dir/build.log" 2>&1
gn_r=$?
check "gains: the test binary builds with no warnings" 0 "$gn_r"
[ "$gn_r" = 0 ] || tail -20 "$gn_dir/build.log"
clang -Wall -Werror -o "$gn_dir/gainsfixture-$$" test/gains/fixture.c >>"$gn_dir/build.log" 2>&1
check "gains: the fixture process builds" 0 "$?"

if [ "$gn_r" = 0 ]; then
  "$gn_dir/gainstest-$$" "$gn_dir/gainsfixture-$$" "$gn_dir/fixtures" >"$gn_dir/out.txt" 2>"$gn_dir/err.txt"
  gn_r=$?
  check "gains: the checks ran to the end" "0 END" "$gn_r $(tail -1 "$gn_dir/out.txt")"
  [ "$gn_r" = 0 ] || tail -10 "$gn_dir/err.txt"
  gn_tab=$(printf '\t')
  while IFS="$gn_tab" read -r gn_tag gn_name gn_want gn_got; do
    [ "$gn_tag" = CHECK ] && check "$gn_name" "$gn_want" "$gn_got"
  done <"$gn_dir/out.txt"
fi
check "gains: no fixture process is left running" 0 "$(pgrep -f "gainsfixture-$$" | grep -c .)"

# The verb reads the same table the test binary wrote in $MINMACS_HOME/minmacs.sqlite.
gn_json=$("$BIN" gains --json 2>/dev/null)
check "gains: gains --json runs" 0 "$?"
check "gains: --json has today, total, byDay, byKind, byWho and byWorkstream" "yes" \
  "$(printf '%s' "$gn_json" | json "'yes' if all(k in j for k in ('today','total','byDay','byKind','byWho','byWorkstream','gains','meaning')) else 'no'")"
check "gains: 7 days by default, today last" "7 yes" \
  "$(printf '%s' "$gn_json" | json "'%d %s' % (len(j['byDay']), 'yes' if j['byDay'][-1]['day'] == __import__('time').strftime('%Y-%m-%d') else 'no')")"
check "gains: --json counts today's five actions" 5 "$(printf '%s' "$gn_json" | json "j['today']['actions']")"
check "gains: --json gives disk back apart from memory back" "7000000 yes" \
  "$(printf '%s' "$gn_json" | json "'%d %s' % (j['today']['diskBack'], 'yes' if j['today']['memoryBack'] >= 64*2**20 else 'no')")"
check "gains: --json by kind" "1 3 1" \
  "$(printf '%s' "$gn_json" | json "'%d %d %d' % (j['byKind']['server']['actions'], j['byKind']['cache']['actions'], j['byKind']['workstream']['actions'])")"
check "gains: --json by who" "3 1 1" \
  "$(printf '%s' "$gn_json" | json "'%d %d %d' % (j['byWho']['you']['actions'], j['byWho']['auto']['actions'], j['byWho']['run']['actions'])")"
check "gains: --json lists no undone row" 0 "$(printf '%s' "$gn_json" | json "sum(1 for g in j['gains'] if g['undone'])")"
check "gains: --days 30 gives 30 days" 30 "$("$BIN" gains --days 30 --json 2>/dev/null | json "len(j['byDay'])")"
"$BIN" gains --days 31 >/dev/null 2>&1
check "gains: --days 31 is a usage error" 2 "$?"
"$BIN" gains --days x >/dev/null 2>&1
check "gains: --days x is a usage error" 2 "$?"
gn_text=$("$BIN" gains 2>/dev/null)
check "gains: the text says memory and disk are never added" 1 "$(printf '%s\n' "$gn_text" | grep -c 'never added together')"
check "gains: the text has today's line" 1 "$(printf '%s\n' "$gn_text" | grep -c '^Today .* 5 actions')"
check "gains: the text lists by who did it" 1 "$(printf '%s\n' "$gn_text" | grep -c '^By who did it')"
