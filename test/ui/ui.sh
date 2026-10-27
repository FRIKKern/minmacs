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

# Three subjects with one menu and four cards each, Noo-Noo's with one menu and five cards, plus the status icons,
# in four appearances.
ui_want=88
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

# The kit's own checks, without drawing.
if clang -fobjc-arc -Wall -mmacosx-version-min=14.0 -ISources -framework Cocoa \
     $(find Sources/UI -name '*.m' | LC_ALL=C sort) test/ui/kit.m -o "$MINMACS_HOME/ui/kit" >"$MINMACS_HOME/ui/kit.log" 2>&1; then
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
