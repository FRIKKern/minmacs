#!/bin/sh
# Stands in for sudo, pmset and launchctl in the migration checks. MMLidOverride and the follow-up run it in place
# of the real program, with the real command line as its arguments. It logs each call under
# $MINMACS_HOME/migrate-fake and keeps the lid state there, which the test tool's fake power source reads.
# Nothing real is run.
d="$MINMACS_HOME/migrate-fake"
mkdir -p "$d"
printf '%s\n' "$*" >>"$d/log"
case "$*" in
  "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0")
    [ -f "$d/fail" ] && { echo "sudo: a password is required" >&2; exit 1; }
    echo 0 >"$d/lid" ;;
  "/bin/launchctl bootout gui/"*) ;;
  *) echo "unexpected command: $*" >&2; exit 2 ;;
esac
