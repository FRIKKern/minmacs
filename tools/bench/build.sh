#!/bin/sh
# Builds the bench from every .m under Sources except main.m, plus tools/bench/bench.m, with build.sh's flags
# for this Mac's architecture only, so it runs the same Core and experts the app runs.
# Each file compiles on its own, eight at a time, then one link.
# Usage: tools/bench/build.sh     BUILD_DIR=dir puts it in dir/bench, default build/bench. Prints the binary's path.
set -eu
cd "$(dirname "$0")/../.."
OUT="${BUILD_DIR:-build}/bench"
rm -rf "$OUT/obj" && mkdir -p "$OUT/obj"
LOG="$OUT/clang.log"
: >"$LOG"
FLAGS="-fobjc-arc -O2 -Wall -mmacosx-version-min=14.0 -arch $(uname -m) -ISources -DMM_VERSION=\"bench\""
export FLAGS OUT
if ! { find Sources -name '*.m' ! -path 'Sources/main.m'; echo tools/bench/bench.m; } | LC_ALL=C sort |
    xargs -P 8 -I{} sh -c 'o="$OUT/obj/$(echo "{}" | tr / _).o"; clang $FLAGS -c "{}" -o "$o" >"$o.log" 2>&1 || { cat "$o.log"; exit 1; }' >>"$LOG" 2>&1; then
  cat "$OUT"/obj/*.log >&2; echo "bench build failed" >&2; exit 1
fi
cat "$OUT"/obj/*.log >>"$LOG"
# shellcheck disable=SC2046
if ! clang -fobjc-arc -arch "$(uname -m)" -mmacosx-version-min=14.0 "$OUT"/obj/*.o \
    -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
    -o "$OUT/bench" >>"$LOG" 2>&1; then
  cat "$LOG" >&2; echo "bench link failed" >&2; exit 1
fi
if grep -q "warning:" "$LOG"; then cat "$LOG" >&2; echo "bench build has warnings; fix them" >&2; exit 1; fi
echo "$OUT/bench"
