#!/bin/sh
# Builds the autorelease test programs into OUT. Reads WorkForest's source; never changes it.
set -eu
cd "$(dirname "$0")"
OUT=${OUT:-${TMPDIR:-/tmp}/minmacs-settling}
WF=${WF:-$HOME/Documents/GitHub/workforest/Sources/Trees.m}
mkdir -p "$OUT/sessions-flat" "$OUT/sessions-inner"
# Sessions() and the helpers it calls run from ISODate to the end of Sessions().
from=$(grep -n '^static NSDate \*ISODate' "$WF" | cut -d: -f1)
to=$(awk -v f="$from" 'NR>f && /^#pragma mark - Scanner/ {print NR-1; exit}' "$WF")
sed -n "${from},${to}p" "$WF" >"$OUT/sessions-flat/sessions_wf.inc"
# The inner variant drains a pool after each log file Mentions() reads.
sed -E 's/Mentions\(f, paths, (@"[^"]*"), named\);/{ @autoreleasepool { Mentions(f, paths, \1, named); } }/g' \
  "$OUT/sessions-flat/sessions_wf.inc" >"$OUT/sessions-inner/sessions_wf.inc"
F="-fobjc-arc -O2 -Wall -mmacosx-version-min=14.0 -framework Foundation"
# shellcheck disable=SC2086
clang $F -I"$OUT/sessions-flat" sessions.m -o "$OUT/sessions-flat/sessions"
# shellcheck disable=SC2086
clang $F -I"$OUT/sessions-inner" sessions.m -o "$OUT/sessions-inner/sessions"
# shellcheck disable=SC2086
clang $F scan.m -o "$OUT/scan"
# shellcheck disable=SC2086
clang $F patchids.m -o "$OUT/patchids"
grep -c "autoreleasepool" "$OUT/sessions-inner/sessions_wf.inc" | sed 's/^/pools added: /'
