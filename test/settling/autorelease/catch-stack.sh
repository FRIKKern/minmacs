#!/bin/sh
# Waits for WorkForest's next memory spike and samples its stacks for 3 seconds while it lasts.
# Read-only: ps and sample. sample reads the stacks and never signals the process.
# Usage: catch-stack.sh <pid> [limit MB] [seconds] [outfile]
set -u
PID=$1; LIMIT=${2:-300}; SECS=${3:-900}; OUT=${4:-spike-sample.txt}
end=$(( $(date +%s) + SECS ))
while [ "$(date +%s)" -lt "$end" ]; do
  rss=$(ps -o rss= -p "$PID" | tr -d ' ')
  [ -n "$rss" ] || { echo "pid $PID is gone"; exit 1; }
  if [ "$rss" -gt $((LIMIT * 1024)) ]; then
    echo "rss $rss KB at $(date -u +%T)" >"$OUT.info"
    sample "$PID" 3 -file "$OUT" >/dev/null 2>&1
    ps -o rss= -p "$PID" >>"$OUT.info"
    echo "sampled at rss $rss KB"; exit 0
  fi
  perl -e 'select(undef,undef,undef,0.2)'
done
echo "no spike in $SECS s"
