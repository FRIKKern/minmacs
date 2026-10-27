#!/bin/sh
# Renders the menu kit's fixture menus and hover cards to PNG, in light, dark and Increase Contrast.
# Usage: tools/render.sh [output folder]     default build/render, the folder CI keeps
#   BUILD_DIR=dir    where the render binary is built, default build. Give each parallel run its own.
# The render tool links Sources/UI, the specs in Sources/Core/MMExpert.m and each expert's pure menu code,
# so it never starts the app and never scans anything.
# It exits 1 when a DESIGN.md check in checks.txt fails.
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-build/render}"
BIN="${BUILD_DIR:-build}/render-bin"
mkdir -p "$BIN" "$OUT"
LOG="$BIN/clang.log"
# shellcheck disable=SC2046
if ! clang -fobjc-arc -O0 -Wall -mmacosx-version-min=14.0 -ISources -framework Cocoa \
    $(find Sources/UI -name '*.m' | LC_ALL=C sort) Sources/Core/MMSpecs.m Sources/Experts/LocoHost/MMLHHost.m Sources/Experts/Insomnia/MMINMenu.m tools/render.m -o "$BIN/render" >"$LOG" 2>&1; then
  cat "$LOG" >&2; echo "render build failed" >&2; exit 1
fi
if grep -q "warning:" "$LOG"; then cat "$LOG" >&2; echo "render build has warnings; fix them" >&2; exit 1; fi
rm -f "$OUT"/*.png "$OUT"/shell/*.png "$OUT/checks.txt"
"$BIN/render" "$OUT"
