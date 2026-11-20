# Issue #96: a project folder whose package.json, README, mix.exs or pyproject.toml is a named pipe.
# Sourced by test/locohost.sh with $LH, $lh, check and json set. No writer ever opens these pipes, so an open of one for
# reading waits for ever. `_project` reads the folder on a thread of its own and prints "stuck" past 2 seconds, so a
# read that waits fails its check, and the tool ends with the thread still waiting, so the run never waits on it.
lp="$lh/pipes96"
lp_read() { # folder: stuck, or the name the project's files gave, "-" for none
  lp_out=$("$LH" _project "$1")
  [ "$lp_out" = stuck ] && echo stuck || printf '%s' "$lp_out" | json "j.get('name', '-')" 2>/dev/null
}
if [ "$LH" = "$lh/bin/locohost" ]; then
  mkdir -p "$lp/all" "$lp/pkg"
  for f in package.json README.md mix.exs pyproject.toml; do rm -f "$lp/all/$f"; mkfifo "$lp/all/$f"; done
  check "a project whose files are named pipes is read, and the read returns" - "$(lp_read "$lp/all")"
  printf '{"name": "pipe-fixture"}' >"$lp/pkg/package.json"
  rm -f "$lp/pkg/README.md"; mkfifo "$lp/pkg/README.md"
  check "  a plain package.json beside a README that is a pipe still gives the name" pipe-fixture "$(lp_read "$lp/pkg")"
  rm -rf "$lp"
fi
check "no read in LocoHost opens a file with NSFileHandle" 0 "$(grep -n 'fileHandleForReadingAtPath' Sources/Experts/LocoHost/*.m | grep -c .)"
