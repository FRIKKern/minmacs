# ===== Graph: owners, workstreams and the snapshot, issue #16 =====
# Sourced by test.sh after core. Builds test/graph/graph.m against Sources/Core/Graph alone, with facts built by hand.
# It needs no Senses or Know code, starts no process but its own test binary, and reads no file outside $MINMACS_HOME.
# ThreadSanitizer is left out: on macOS 27 with this clang, an empty C program built with it crashes at launch.

gr_dir="$MINMACS_HOME/graph"
mkdir -p "$gr_dir"
gr_src="$(find Sources/Core/Graph -name '*.m' | LC_ALL=C sort) test/graph/graph.m"
gr_cc="clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -ISources -framework Foundation"
gr_tab=$(printf '\t')

# shellcheck disable=SC2086
if $gr_cc -O2 -arch arm64 -arch x86_64 $gr_src -o "$gr_dir/graph" >"$gr_dir/build.log" 2>&1; then
  check "test/graph/graph.m builds with no warnings" 0 "$(grep -c "warning:" "$gr_dir/build.log")"
  "$gr_dir/graph" >"$gr_dir/out.txt" 2>"$gr_dir/err.txt"
  check "test/graph/graph.m runs" 0 "$?"
  while IFS="$gr_tab" read -r gr_n gr_w gr_g; do check "$gr_n" "$gr_w" "$gr_g"; done <"$gr_dir/out.txt"
else
  check "test/graph/graph.m builds" 0 1
  tail -20 "$gr_dir/build.log"
fi

# ===== end of Graph =====
