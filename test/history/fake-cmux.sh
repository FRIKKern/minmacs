#!/bin/sh
# A fake cmux CLI for the history checks. It reads only files in the folder named by its own location.
# events   prints the frames in cmux.frames, then runs the sleeper this run built, until MinMacs stops it
D=$(dirname "$0")
case "$1" in
  events) cat "$D/cmux.frames" 2>/dev/null; exec "$D/$(cat "$D/sleeper.name")" 30 ;;
esac
exit 0
