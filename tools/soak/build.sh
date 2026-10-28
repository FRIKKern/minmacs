#!/bin/sh
# Builds the soak subject from every .m under Sources except main.m, plus tools/soak/soak.m, with build.sh's flags
# for this Mac's architecture and -g, so leaks(1) names frames. Then procstat and the fake agent.
# Each file compiles on its own, eight at a time, then one link.
# Usage: tools/soak/build.sh     BUILD_DIR=dir puts it in dir/soak, default build/soak. Prints the folder.
set -eu
cd "$(dirname "$0")/../.."
OUT="${BUILD_DIR:-build}/soak"
rm -rf "$OUT/obj" && mkdir -p "$OUT/obj"
LOG="$OUT/clang.log"
: >"$LOG"
FLAGS="-fobjc-arc -O2 -g -Wall -mmacosx-version-min=14.0 -arch $(uname -m) -ISources -DMM_VERSION=\"soak\""
export FLAGS OUT
if ! { find Sources -name '*.m' ! -path 'Sources/main.m'; echo tools/soak/soak.m; } | LC_ALL=C sort |
    xargs -P 8 -I{} sh -c 'o="$OUT/obj/$(echo "{}" | tr / _).o"; clang $FLAGS -c "{}" -o "$o" >"$o.log" 2>&1 || { cat "$o.log"; exit 1; }' >>"$LOG" 2>&1; then
  cat "$OUT"/obj/*.log >&2; echo "soak build failed" >&2; exit 1
fi
cat "$OUT"/obj/*.log >>"$LOG"
if ! clang -fobjc-arc -arch "$(uname -m)" -mmacosx-version-min=14.0 "$OUT"/obj/*.o \
    -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
    -o "$OUT/soak" >>"$LOG" 2>&1; then
  cat "$LOG" >&2; echo "soak link failed" >&2; exit 1
fi
for t in procstat agent; do
  clang -O1 -Wall -mmacosx-version-min=14.0 "tools/soak/$t.c" -o "$OUT/$t" >>"$LOG" 2>&1 || { cat "$LOG" >&2; echo "$t build failed" >&2; exit 1; }
done
if grep -q "warning:" "$LOG"; then cat "$LOG" >&2; echo "soak build has warnings; fix them" >&2; exit 1; fi
echo "$OUT"
