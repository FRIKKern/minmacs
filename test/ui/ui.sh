# ===== UI: the menu kit and the render tool =====
# Sourced by test.sh after the other sections, or run alone with sh test/ui/ui.sh.
# It builds tools/render.m against Sources/UI, renders the fixture menus and cards into build/render,
# where CI keeps them, and checks that every PNG is there. It also runs the kit's own checks in test/ui/kit.m.
# Nothing here starts the app or creates a status item.

if ! command -v check >/dev/null 2>&1; then
  # Run alone: the few harness pieces this section uses.
  cd "$(dirname "$0")/../.." || exit 1
  ROOT=$(pwd -P)
  MINMACS_HOME=$(mktemp -d "${TMPDIR:-/tmp}/minmacs-ui.XXXXXX")
  pass=0; fail=0; ui_alone=1
  check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-56s %s\n' "$1" "$3"; else fail=$((fail+1)); printf '  FAIL  %-56s got %s, want %s\n' "$1" "$3" "$2"; fi; }
  trap 'rm -rf "$MINMACS_HOME"' EXIT
  echo "== ui"
fi

ui_out="$ROOT/build/render"
ui_log="$MINMACS_HOME/ui-render.log"
BUILD_DIR="$MINMACS_HOME/ui" "$ROOT/tools/render.sh" "$ui_out" >"$ui_log" 2>&1
ui_r=$?
check "tools/render.sh builds and renders" 0 "$ui_r"
[ "$ui_r" = 0 ] || tail -20 "$ui_log"
check "the render build has no warnings" 0 "$(grep -c "warning:" "$MINMACS_HOME/ui/render-bin/clang.log" 2>/dev/null)"

# Three subjects with one menu and four cards each, WorkForest with a fifth card, Noo-Noo with one menu and five cards,
# plus the status icons, in four appearances: 92. Insomnia's four subjects add four menus and seven cards: 44.
# WorkForest's docs card, which shows Wrap Up, issue #27: 4. The two menus a cross-link opens, LocoHost's and
# WorkForest's with the linked card first, add 8.
ui_want=148
check "every PNG is there" "$ui_want" "$(ls "$ui_out"/*.png 2>/dev/null | wc -l | tr -d ' ')"
for ui_name in locohost-menu locohost-card-checkout locohost-card-orbit locohost-card-docs locohost-card-postgres \
               workforest-menu workforest-card-promo workforest-card-search workforest-card-hooks workforest-card-limits \
               minmacs-menu minmacs-card-spotify minmacs-card-slack minmacs-card-chrome minmacs-card-figma status; do
  ui_ok=yes
  for ui_mode in light dark contrast-light contrast-dark; do [ -s "$ui_out/$ui_name-$ui_mode.png" ] || ui_ok=no; done
  check "$ui_name in light, dark and Increase Contrast" yes "$ui_ok"
done
check "Increase Contrast renders differ from the plain ones" yes \
  "$([ "$(md5 -q "$ui_out/locohost-menu-light.png" 2>/dev/null)" != "$(md5 -q "$ui_out/locohost-menu-contrast-light.png" 2>/dev/null)" ] && echo yes || echo no)"
# The kit's one width, at two pixels per point.
ui_widths=$(for f in "$ui_out"/*.png; do sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/ {print $2}'; done | sort -u | tr '\n' ' ')
check "every PNG has the kit's one width" "720 " "$ui_widths"
ui_fails=missing
[ -f "$ui_out/checks.txt" ] && ui_fails=$(grep -c '^FAIL' "$ui_out/checks.txt")
check "the render's DESIGN.md checks all pass" 0 "$ui_fails"
grep '^FAIL' "$ui_out/checks.txt" 2>/dev/null | sed 's/^/        /'

# The window that opens from the icon, issue #62, in window/: 23 pictures in dark and in dark with Increase Contrast.
# The last four came from the first look at the real window: young is one minute in with an empty disk side and nobody
# asking, calm is twelve minutes in with nothing to fix and a look-back, and long has names longer than their column.
# removal-settings is Settings as the feed fills it today, with the card for the removal choice of issue #62.
# The six welcome pictures are the first launch: the welcome alone with the switch on and off and each removal choice
# picked, the welcome of a person who used MinMacs for more than a day before, and the window right after a Start
# that came before the first numbers.
# It is dark glass in every appearance, and wider than a menu, so its PNGs stay out of the 720 px check above.
ui_win="$ui_out/window"
check "every window PNG is there" 84 "$(ls "$ui_win"/*.png 2>/dev/null | wc -l | tr -d ' ')"
ui_ok=yes
for ui_name in busy-main busy-server busy-worktree busy-settings removal-settings quiet-main quiet-server peak-main peak-worktree running-main done-main empty-main memory-only-main disk-only-main \
               young-main calm-main long-main long-agent busy-agent busy-asks busy-app busy-cache busy-fix calm-cache young-server calm-settings real-main real-agent real-server real-fix extreme-main extreme-server extreme-asks extreme-tree extreme-running-main extreme-done-main welcome-main welcome-off-main welcome-trash-main welcome-delete-main welcome-watched-main welcome-started; do
  for ui_mode in dark contrast-dark; do [ -s "$ui_win/$ui_name-$ui_mode.png" ] || { ui_ok=no; echo "        missing $ui_name-$ui_mode.png"; }; done
done
check "each window state in dark and Increase Contrast" yes "$ui_ok"
ui_sizes=$(for f in "$ui_win"/*.png; do sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixelWidth/ {w=$2} /pixelHeight/ {print w "x" $2}'; done | sort -u | tr '\n' ' ')
check "every window PNG is 1020 by 728 points, two pixels each" "2040x1456 " "$ui_sizes"
ui_md() { md5 -q "$ui_win/$1.png" 2>/dev/null; }
check "the window differs under Increase Contrast, with a pointed row and in Settings" "yes yes yes" \
  "$([ "$(ui_md busy-main-dark)" != "$(ui_md busy-main-contrast-dark)" ] && echo yes || echo no) $([ "$(ui_md busy-main-dark)" != "$(ui_md busy-server-dark)" ] && echo yes || echo no) $([ "$(ui_md busy-main-dark)" != "$(ui_md busy-settings-dark)" ] && echo yes || echo no)"
check "no window fixture shows a banned phrase or an old app name" 12 \
  "$(grep -c '^ok    window .*: no shown string holds a banned phrase or an old app name' "$ui_out/checks.txt" 2>/dev/null)"

ui_look() { grep -c "^ok    window$1" "$ui_out/checks.txt" 2>/dev/null; }
check "no row's name is cut with an ellipsis, in five fixtures" 5 "$(ui_look " .*: no row's name is cut with an ellipsis")"
check "a young hour draws no line, twelve minutes draw as twelve, a full hour as sixty" "1 1 1 1" \
  "$(ui_look ' young: one filled minute is no line') $(ui_look ' calm: twelve filled minutes draw as twelve') $(ui_look ' busy: a full hour draws all sixty') $(ui_look ' young: no row shows an hour line before five')"
check "an empty group says so, and nothing to fix shows what came back today" "1 5 1" \
  "$(ui_look ' young: nobody asks, nothing to fix, and each empty disk group says so') $(ui_look ': the .* group has words for when it is empty') $(ui_look ' calm: nothing to fix, with memory and disk back today as two numbers')"
check "the top band folds away when nobody asks and comes back" "1 1" \
  "$(ui_look ': with nobody asking the top band folds away') $(ui_look ': the band comes back when an agent asks')"
check "a group rests on a whole row and opens at its top" "1 1" \
  "$(ui_look ': every group opens at its first row') $(ui_look ': a closed window forgets its scrolling')"
check "the young hour, the folded band and the look-back change the picture" "yes yes yes" \
  "$([ "$(ui_md young-main-dark)" != "$(ui_md empty-main-dark)" ] && echo yes || echo no) $([ "$(ui_md calm-main-dark)" != "$(ui_md quiet-main-dark)" ] && echo yes || echo no) $([ "$(ui_md long-main-dark)" != "$(ui_md busy-main-dark)" ] && echo yes || echo no)"

# The dock's gains: a side that gives nothing back is not shown as "0 KB back".
check "the dock shows only the sides above zero, before a press, in a run and at its end" "5 0" "$(ui_look ' gains: ') $(grep -c '^FAIL  window gains' "$ui_out/checks.txt" 2>/dev/null)"
check "a day with one side to fix marks only the rows of its fixes" 2 "$(ui_look ' .*-only: only rows of the fixes that are left say they go')"
check "one side alone changes the picture" "yes yes" \
  "$([ "$(ui_md memory-only-main-dark)" != "$(ui_md busy-main-dark)" ] && echo yes || echo no) $([ "$(ui_md memory-only-main-dark)" != "$(ui_md disk-only-main-dark)" ] && echo yes || echo no)"

# The second look against 195-a, tools/render-window-polish.m: one rule for sizes, no line under a dimmed button, whole
# rows, a side with room closing with its whole number, a story's first line, the pointed row in the dock, and Stop.
# 44: the counted phrases at 0, 1 and 2 came with the plurals fix.
check "the second look's checks are there and pass" "44 0" "$(grep -cE '^ok    window (sizes|dock|lists|story|settings|motion|words|facts)' "$ui_out/checks.txt" 2>/dev/null) $(grep -cE '^FAIL  window (sizes|dock|lists|story|settings|motion|words|facts)' "$ui_out/checks.txt" 2>/dev/null)"
# No drawn string holds an ellipsis or is cut, on every made-up day, the real-shaped one and the day of extremes among them.
check "no drawn string holds an ellipsis or leaves its box, and the made-up rows speak the feed's words" "1 1" \
  "$(ui_look ' words: on every day and in every state no drawn string holds an ellipsis') $(ui_look ' words: every made-up row has a state word, fact labels and a fix title the feed can make')"
check "the pointer on a row or on Fix Everything changes the picture" "yes yes" \
  "$([ "$(ui_md busy-agent-dark)" != "$(ui_md busy-asks-dark)" ] && echo yes || echo no) $([ "$(ui_md busy-fix-dark)" != "$(ui_md busy-main-dark)" ] && echo yes || echo no)"

# The welcome of the first launch: it stands alone, its answers stay the person's, Start hands them over once and it
# does not come back. tools/render-window-look.m holds the checks.
check "the welcome's checks all ran and passed" "30 0" "$(grep -c '^ok    welcome:' "$ui_out/checks.txt" 2>/dev/null) $(grep -c '^FAIL  welcome:' "$ui_out/checks.txt" 2>/dev/null)"
check "the welcome is its own picture, and the switch, each removal choice and a watched day change it" "yes yes yes yes yes yes" \
  "$([ "$(ui_md welcome-main-dark)" != "$(ui_md young-main-dark)" ] && echo yes || echo no) $([ "$(ui_md welcome-main-dark)" != "$(ui_md welcome-off-main-dark)" ] && echo yes || echo no) $([ "$(ui_md welcome-main-dark)" != "$(ui_md welcome-trash-main-dark)" ] && echo yes || echo no) $([ "$(ui_md welcome-trash-main-dark)" != "$(ui_md welcome-delete-main-dark)" ] && echo yes || echo no) $([ "$(ui_md welcome-started-dark)" != "$(ui_md welcome-main-dark)" ] && echo yes || echo no) $([ "$(ui_md welcome-watched-main-dark)" != "$(ui_md welcome-main-dark)" ] && echo yes || echo no)"
# The press guard: a second press where Start was runs no fix, and nothing that fades takes a press.
check "the guard's checks all ran and passed: no press reaches the menu before it has arrived" "8 0" "$(grep -c '^ok    welcome guard:' "$ui_out/checks.txt" 2>/dev/null) $(grep -c '^FAIL  welcome guard:' "$ui_out/checks.txt" 2>/dev/null)"
# With real fades, in a window ordered in off every screen: the turn to Settings, a close inside the guard, a late welcome.
check "the checks in a window that is really shown all ran and passed" "5 0" "$(grep -c '^ok    window shown:' "$ui_out/checks.txt" 2>/dev/null) $(grep -c '^FAIL  window shown:' "$ui_out/checks.txt" 2>/dev/null)"
check "the welcome's view stays under 500 lines and names no host and no Core type" "1 0" \
  "$(wc -l <"$ROOT/Sources/UI/Window/MMWindowWelcome.m" | awk '{print ($1 < 500) ? 1 : 0}') $(grep -cE 'MMWindowHost|#import "(Core|Shell)/' "$ROOT/Sources/UI/Window/MMWindowWelcome.m")"

# One spec converter: Sources/UI/MMSpecMenu. The second one, MMSpecKit, is gone, and nothing calls its functions.
check "one spec converter, MMSpecMenu" "no 0" \
  "$([ -e "$ROOT/Sources/UI/MMSpecKit.m" ] && echo yes || echo no) $(grep -rnE 'MMSpecKit|MMMenuForSpec|MMCardForSpec|MMItemForAction' "$ROOT/Sources" "$ROOT/tools" "$ROOT/test" | grep -v '^.*ui\.sh:' | grep -c .)"

# The kit's own checks, without drawing.
if clang -fobjc-arc -Wall -mmacosx-version-min=14.0 -ISources -framework Cocoa \
     $(find Sources/UI -name '*.m' | LC_ALL=C sort) Sources/Core/MMSpecs.m test/ui/kit.m -o "$MINMACS_HOME/ui/kit" >"$MINMACS_HOME/ui/kit.log" 2>&1; then
  check "test/ui/kit.m builds with no warnings" 0 "$(grep -c "warning:" "$MINMACS_HOME/ui/kit.log")"
  ui_tab=$(printf '\t')
  "$MINMACS_HOME/ui/kit" >"$MINMACS_HOME/ui/kit.out" 2>&1
  check "test/ui/kit.m runs" 0 "$?"
  while IFS="$ui_tab" read -r ui_n ui_w ui_g; do check "$ui_n" "$ui_w" "$ui_g"; done <"$MINMACS_HOME/ui/kit.out"
else
  check "test/ui/kit.m builds" 0 1
  cat "$MINMACS_HOME/ui/kit.log"
fi

if [ "${ui_alone:-0}" = 1 ]; then echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; fi
# ===== end of UI =====
