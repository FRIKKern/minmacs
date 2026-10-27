#!/bin/sh
# A fake xcrun for test/noonoo.sh. It knows one command, `simctl delete unavailable`, and acts only on the fixture
# Devices folder under $MINMACS_CLUTTER_ROOT, which must sit inside $MINMACS_HOME. A device is unavailable when its
# folder holds a file named unavailable. It prints what it deleted, as simctl does.
[ "$*" = "simctl delete unavailable" ] || { echo "fake xcrun: only simctl delete unavailable, not: $*" >&2; exit 2; }
d="$MINMACS_CLUTTER_ROOT/home/Library/Developer/CoreSimulator/Devices"
case "$MINMACS_CLUTTER_ROOT" in "$MINMACS_HOME"/*) ;; *) echo "fake xcrun: not a fixture root" >&2; exit 3 ;; esac
[ -d "$d" ] || exit 0
for x in "$d"/*; do
  [ -f "$x/unavailable" ] || continue
  rm -r "$x" && echo "Deleted $(basename "$x")"
done
exit 0
