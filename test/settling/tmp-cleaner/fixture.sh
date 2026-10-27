#!/bin/sh
# Owner step: proves on fixtures what tmp_cleaner removes. It only writes inside its own folder.
# ctime cannot be set back, so a fresh fixture waits at least 4 nights before a check means anything.
#   fixture.sh make     makes the fixture and writes a manifest
#   fixture.sh check    run on day 5 or later: prints what is gone
set -u
# The first fixture sits in $TMPDIR. MM_TMP_FIXTURE puts a second one elsewhere.
F=${MM_TMP_FIXTURE:-${TMPDIR:-/tmp}/minmacs-settling/tmp-cleaner-fixture}
case "${1:-}" in
  make)
    mkdir -p "$F/emptydir" "$F/full/deep" "$F/kept"
    echo a >"$F/untouched.txt"; echo b >"$F/full/deep/untouched.txt"; echo c >"$F/kept/read-daily.txt"
    date -u +%FT%TZ >"$F/.made"
    echo "made $F. Read kept/read-daily.txt once a day with cat, then run 'fixture.sh check' after 4 nights." ;;
  check)
    echo "made $(cat "$F/.made" 2>/dev/null), now $(date -u +%FT%TZ)"
    for p in untouched.txt full/deep/untouched.txt full/deep full emptydir kept/read-daily.txt; do
      [ -e "$F/$p" ] && echo "kept  $p" || echo "gone  $p"
    done ;;
  *) echo "usage: fixture.sh make | check"; exit 2 ;;
esac
