#!/bin/sh
# A fake cmux CLI for the Know checks. It reads and writes only files in the folder named by its own location.
# events   prints the frames in cmux.frames, records its arguments, then waits to be stopped
# top      prints cmux.top
# other    records its arguments in cmux.goto
D=$(dirname "$0")
case "$1" in
  events) printf '%s\n' "$*" >"$D/cmux.args"; cat "$D/cmux.frames" 2>/dev/null; exec sleep 30 ;;
  top) cat "$D/cmux.top" 2>/dev/null ;;
  *) printf '%s\n' "$*" >>"$D/cmux.goto" ;;
esac
exit 0
