# Settling tests that run on fixtures only, as a test.sh section. Sourced by test.sh.
# Run with: ./test.sh settling/section
# Every fixture and binary lives in $MINMACS_HOME/settling. Nothing outside it is read or written,
# except that the XPC probe makes launchd start its own service for a moment.
S="$MINMACS_HOME/settling"; mkdir -p "$S"
CF="-O2 -Wall -Wextra -mmacosx-version-min=14.0"

# Clone refcounts on this volume, with clones, a clone of a clone, a hard link and a changed block.
# shellcheck disable=SC2086
clang $CF -fblocks test/settling/clone-refcounts/clones.c -o "$S/clones" 2>"$S/clones.log"
check "clones.c builds without warnings" 0 "$(grep -c warning: "$S/clones.log")"
mkdir -p "$S/clone-fixture" && out=$("$S/clones" "$S/clone-fixture")
check "three full clones report refcount 3" 3 "$(printf '%s\n' "$out" | sed -n '/base, c1 and c2/,/^--/p' | grep -c 'refcnt 3 ')"
check "a changed block takes the file out of the family" 1 "$(printf '%s\n' "$out" | sed -n '/one block of c2/,/^--/p' | grep ' c2 ' | sed -nE 's/.*refcnt ([0-9]+).*/\1/p')"
printf '%s\n' "$out" | sed -n '/one block of c2/,/^--/p' | sed 's/^/        /'   # the raw lines, so a different volume shows its numbers
check "a hard link is not counted as a clone" 3 "$(printf '%s\n' "$out" | sed -n '/one block of c2/,/^--/p' | grep ' base ' | sed -E 's/.*refcnt ([0-9]+).*/\1/')"
# Right after unlink the refcount can still show the deleted clone for a few ms, so this checks
# that it settles, not that the first read is right.
lag=$("$S/clones" "$S/clone-fixture" lag 50)
check "the refcount settles within 5 s after a delete" 0 "$(printf '%s\n' "$lag" | grep -c 'still')"
check "the refcount is right at once after clonefile" 0 "$(printf '%s\n' "$lag" | sed -n 's/^lag: \([0-9]*\) of .*after clonefile$/\1/p')"
# statfs counts the whole volume, and other processes write to it at the same time. A check on it
# passes when one of three fresh runs agrees, so a busy moment does not fail the section.
got=no
for try in 1 2 3; do
  [ "$try" = 1 ] || { rm -rf "$S/clone-fixture"; mkdir -p "$S/clone-fixture"; out=$("$S/clones" "$S/clone-fixture"); }
  v=$(printf '%s\n' "$out" | grep 'delete base and hl' | awk '{print $(NF-1)}')
  got=$(awk -v v="$v" 'BEGIN {print (v > 15.5 && v < 16.5) ? "yes" : "no (" v ")"}')
  [ "$got" = yes ] && break
done
check "statfs frees the 16 MB the extent union predicts" yes "$got"
check "the clone-id rule counts too much for {c2,c4}" "16.00 0.02" "$(printf '%s\n' "$out" | grep '{c2,c4}' | awk '{print $5, $7}')"

# The Sizer without opening files, checked against a delete on a fake pnpm store.
# shellcheck disable=SC2086
clang $CF test/settling/pnpm-freed/bulk.c -o "$S/bulk" 2>"$S/bulk.log"
# shellcheck disable=SC2086
clang $CF -fblocks -Itest/settling/clone-refcounts test/settling/pnpm-freed/freed.c -o "$S/freed" 2>>"$S/bulk.log"
check "bulk.c and freed.c build without warnings" 0 "$(grep -c warning: "$S/bulk.log")"
for try in 1 2 3; do
  rm -rf "$S/pnpm-fixture"; mkdir -p "$S/pnpm-fixture"
  out=$(test/settling/pnpm-freed/fixture.sh "$S/freed" "$S/pnpm-fixture" "$S/bulk")
  mb=$(printf '%s\n' "$out" | sed -n 's/^statfs delta on delete: \([0-9]*\) MB.*/\1/p')
  [ "${mb:-0}" -ge 38 ] && [ "${mb:-0}" -le 42 ] && break
done
check "the extent union says 40 MB is freed" 40.0 "$(printf '%s\n' "$out" | awk '/^freed/ {print $2}')"
check "getattrlistbulk says 40 MB is freed" 40.0 "$(printf '%s\n' "$out" | sed -n 's/^estimate freed.*: \([0-9.]*\) MB/\1/p')"
check "statfs agrees within 2 MB in one of three runs" yes "$([ "${mb:-0}" -ge 38 ] && [ "${mb:-0}" -le 42 ] && echo yes || echo "no ($mb)")"

# An XPC service inside an ad-hoc bundle, called directly and through a symlink.
out=$(test/settling/xpc/build.sh "$S/xpc" 2>&1)
check "the XPC probe builds and verifies" 1 "$(printf '%s\n' "$out" | grep -c 'built and verified')"
check "the XPC probe builds without warnings" 0 "$(printf '%s\n' "$out" | grep -c warning:)"
mkdir -p "$S/xpc-fixture/a" && echo x >"$S/xpc-fixture/a/one"
check "the XPC service answers from an ad-hoc bundle" PASS "$("$S/xpc/MMXPCProbe.app/Contents/MacOS/host" "$S/xpc-fixture" 2>&1 | tail -1)"
ln -sf "$S/xpc/MMXPCProbe.app/Contents/MacOS/host" "$S/probe"
check "it answers through a symlink, as the CLI runs" PASS "$("$S/probe" "$S/xpc-fixture" 2>&1 | tail -1)"

# The owner's probe app only builds here. Running it shows prompts, so the owner runs it.
out=$(test/settling/owner/build.sh "$S/owner" 2>&1)
check "the owner probe builds without warnings and verifies" "0 1" "$(printf '%s\n' "$out" | grep -c warning:) $(printf '%s\n' "$out" | grep -c 'built and verified')"
